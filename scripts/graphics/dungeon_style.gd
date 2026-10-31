class_name DungeonStyle
extends RefCounted
## PS2-era material economy: small reusable painted maps, low-poly silhouettes
## and real local lights. Detail is baked once, never searched per fragment.
static var maps: Dictionary = {}
static var materials: Dictionary = {}
static var floor_sheet: PlaneMesh

static func floor_mesh() -> PlaneMesh:
	if not floor_sheet:
		floor_sheet = PlaneMesh.new()
		floor_sheet.size = RoomGeometry.CELL
	return floor_sheet

static func surface_maps(kind: int) -> Dictionary:
	if maps.has(kind): return maps[kind]
	const SIZE := 256
	var paint = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var height = Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var noise = FastNoiseLite.new()
	noise.seed = 417 + kind
	noise.frequency = .085
	for y in SIZE:
		for x in SIZE:
			var row = y / 64
			var shifted = posmod(x + (32 if row % 2 else 0), SIZE)
			var edge = minf(minf(shifted % 64, 63 - shifted % 64), minf(y % 64, 63 - y % 64))
			var grain = noise.get_noise_2d(x, y) * .5 + .5
			var id = (shifted / 64) + row * 7
			var tone = .76 + .24 * fposmod(sin(float(id) * 17.31) * 431.7, 1.0)
			var bevel = smoothstep(1.0 + grain * 1.6, 6.0, edge)
			if kind == 1:
				bevel = smoothstep(.2, .65, grain)
			elif kind == 2:
				bevel = .7 + .3 * grain
			# Light brushwork at the lip and pooled dirt in the joint.
			var value = tone * (.83 + grain * .24) * lerpf(.28, 1.0, bevel)
			var lip = maxf(0, 1.0 - absf(edge - 5.5) / 2.0) * .08 if kind == 0 else 0.0
			paint.set_pixel(x, y, Color(clampf(value + lip, 0, 1), 1.0 - bevel, fposmod(id * .317, 1.0) if kind == 0 else grain, .72 + .25 * (1.0 - bevel)))
			height.set_pixel(x, y, Color(bevel * (.8 + grain * .2), bevel * (.8 + grain * .2), bevel * (.8 + grain * .2)))
	paint.generate_mipmaps()
	height.bump_map_to_normal_map(2.0)
	height.generate_mipmaps()
	maps[kind] = {"paint": ImageTexture.create_from_image(paint), "normal": ImageTexture.create_from_image(height)}
	return maps[kind]

static func floor_material(look: Dictionary) -> ShaderMaterial:
	var key = "floor" + JSON.stringify(look)
	if materials.has(key): return materials[key]
	var surface: Dictionary = look.get("surface", {})
	var kind = maxi(0, Look.PATTERNS.find(surface.get("pattern", "slabs")))
	var textures = surface_maps(kind)
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/dungeon_floor.gdshader")
	var colors: Array = look.get("floor", Look.DEFAULT_PALETTE)
	for i in 5: mat.set_shader_parameter("palette_" + "abcde"[i], Color(colors[i]))
	mat.set_shader_parameter("paint", textures.paint)
	mat.set_shader_parameter("relief_map", textures.normal)
	mat.set_shader_parameter("detail", Look.detail())
	mat.set_shader_parameter("tile_scale", .25 * 2.4 / maxf(.8, float(surface.get("size", 2.4))))
	for parameter in ["wetness", "moss", "frost", "embers", "brass"]:
		mat.set_shader_parameter(parameter, float(surface.get(parameter, 0)))
	mat.set_shader_parameter("moss_color", Color(surface.get("moss_color", "40532b")))
	mat.set_shader_parameter("ember_color", Color(surface.get("ember_color", "ff722c")))
	materials[key] = mat
	return mat

static func wall_material(color: Color, cap := false) -> ShaderMaterial:
	var key = "wall" + color.to_html() + str(cap)
	if materials.has(key): return materials[key]
	Look.bricks()
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/dungeon_wall.gdshader")
	mat.set_shader_parameter("tint", color.lightened(.12))
	mat.set_shader_parameter("paint", Look.brick_albedo)
	mat.set_shader_parameter("relief_map", Look.brick_normal)
	mat.set_shader_parameter("tile_scale", .35 if cap else .5)
	mat.set_shader_parameter("relief_strength", .22 if cap else .55)
	materials[key] = mat
	return mat

static func wood_material(color: Color, local_space := false) -> ShaderMaterial:
	var key = "wood" + color.to_html() + str(local_space)
	if materials.has(key): return materials[key]
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/dungeon_wood.gdshader")
	mat.set_shader_parameter("local_space", local_space)
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("detail", Look.detail())
	materials[key] = mat
	return mat

static func dress_props(room) -> void:
	for entry in room.props.values():
		for mesh in entry.node.find_children("*", "MeshInstance3D", true, false):
			var source = mesh.material_override
			if not source is StandardMaterial3D or source.emission_enabled: continue
			var color: Color = source.albedo_color
			if color.is_equal_approx(PropVisuals.WOOD) or color.is_equal_approx(PropVisuals.DARK_WOOD) or color.is_equal_approx(PropVisuals.LIGHT_WOOD):
				mesh.material_override = wood_material(color)

static func lantern_glass() -> ShaderMaterial:
	if materials.has("glass"): return materials.glass
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/lantern_glass.gdshader")
	materials.glass = mat
	return mat
