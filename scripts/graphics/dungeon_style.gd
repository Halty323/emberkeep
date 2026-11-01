class_name DungeonStyle
extends RefCounted
## Lighting-led surfaces: real high-resolution stone and wood with normal,
## roughness and occlusion maps. Shared by rooms, architecture and the title.
static var maps: Dictionary = {}
static var materials: Dictionary = {}
static var floor_sheet: PlaneMesh

static func floor_mesh() -> PlaneMesh:
	if not floor_sheet:
		floor_sheet = PlaneMesh.new()
		floor_sheet.size = RoomGeometry.CELL
	return floor_sheet

static func surface_maps(kind: int) -> Dictionary:
	var key := str(clampi(kind,0,2)) + "|" + str(DungeonPBR.resolution())
	if maps.has(key): return maps[key]
	maps[key] = DungeonPBR.maps("flagstone" if kind == 0 else "rock")
	return maps[key]

static func floor_material(look: Dictionary) -> ShaderMaterial:
	var key = "floor" + JSON.stringify(look) + str(DungeonPBR.resolution())
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
	mat.set_shader_parameter("orm", textures.orm)
	mat.set_shader_parameter("uv_aspect", textures.uv_aspect)
	mat.set_shader_parameter("detail", Look.detail())
	mat.set_shader_parameter("tile_scale", .34 * 2.4 / maxf(.8, float(surface.get("size", 2.4))))
	mat.set_shader_parameter("earth", 1.0 if kind == 2 else 0.0)
	mat.set_shader_parameter("relief_strength", .65 if kind == 0 else .48)
	for parameter in ["wetness", "moss", "frost", "embers", "brass"]:
		mat.set_shader_parameter(parameter, float(surface.get(parameter, 0)))
	mat.set_shader_parameter("moss_color", Color(surface.get("moss_color", "40532b")))
	mat.set_shader_parameter("ember_color", Color(surface.get("ember_color", "ff722c")))
	materials[key] = mat
	return mat

static func wall_material(color: Color, cap := false, family := "masonry") -> ShaderMaterial:
	var key = "wall" + color.to_html() + str(cap) + family + str(DungeonPBR.resolution())
	if materials.has(key): return materials[key]
	var textures = DungeonPBR.maps("rock" if family in ["cistern", "halls"] and not cap else "masonry")
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/dungeon_wall.gdshader")
	mat.set_shader_parameter("tint", color.lightened(.45))
	mat.set_shader_parameter("paint", textures.paint)
	mat.set_shader_parameter("relief_map", textures.normal)
	mat.set_shader_parameter("orm", textures.orm)
	mat.set_shader_parameter("uv_aspect", textures.uv_aspect)
	mat.set_shader_parameter("tile_scale", .42 if cap else .4)
	mat.set_shader_parameter("relief_strength", .36 if cap else .72)
	mat.set_shader_parameter("dampness", .55 if family == "cistern" else (.16 if family == "halls" else 0.0))
	materials[key] = mat
	return mat

static func wood_material(color: Color, local_space := false) -> ShaderMaterial:
	var key = "wood" + color.to_html() + str(local_space) + str(DungeonPBR.resolution())
	if materials.has(key): return materials[key]
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/dungeon_wood.gdshader")
	mat.set_shader_parameter("local_space", local_space)
	mat.set_shader_parameter("tint", color.lightened(.3))
	var textures = DungeonPBR.maps("wood")
	mat.set_shader_parameter("paint", textures.paint)
	mat.set_shader_parameter("relief_map", textures.normal)
	mat.set_shader_parameter("orm", textures.orm)
	mat.set_shader_parameter("uv_aspect", textures.uv_aspect)
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

static var candle_mesh: QuadMesh
static func candle_flame() -> ShaderMaterial:
	if materials.has("candle_flame"): return materials.candle_flame
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/hearth_flame.gdshader")
	mat.set_shader_parameter("billboard",true)
	materials.candle_flame = mat
	return mat

static func candle_flame_mesh() -> QuadMesh:
	if not candle_mesh:
		candle_mesh = QuadMesh.new()
		candle_mesh.size = Vector2(.16,.25)
	return candle_mesh

static func verify_material_assets() -> Array[String]:
	var errors: Array[String] = DungeonPBR.verify_assets()
	var paths: Array[String] = ["res://assets/materials/aging.png"]
	for kind in 3:
		for channel in ["paint","normal"]: paths.append("res://assets/materials/floor_%d_%s.png" % [kind,channel])
	for family in ["cellar","cistern","halls","crypt","archive","kiln","belfry","hearth","masonry","dressed"]:
		for channel in ["paint","normal"]: paths.append("res://assets/materials/wall_%s_%s.png" % [family,channel])
	for path in paths:
		if not ResourceLoader.exists(path):
			errors.append("Missing material sheet: " + path)
			continue
		var texture = load(path)
		if not texture is Texture2D or texture.get_width() <= 0: errors.append("Unreadable material sheet: " + path)
	return errors
