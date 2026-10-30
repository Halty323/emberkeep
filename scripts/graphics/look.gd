class_name Look
extends RefCounted
## Surfaces and their quality. Floors are finely divided sheets whose shader
## raises the stones and paints them from the floor theme (content/floors.json
## "surface"); walls wear generated brick textures, mapped in world space.
## Effects detail decides how fine the floor sheet is and how much relief it
## has: Low lays it flat. Purely visual: nothing here touches gameplay.
const CELL := Vector2(18.0, 14.0)
const FLOOR_TOP := -.035
const PATTERNS := ["slabs", "rock", "earth"]
# Floor sheet vertices per world unit and stone relief, by effects detail.
const DENSITY := [0, 2, 4]
const RELIEF := [0.0, .025, .035]
const SURFACE_KEYS := ["pattern", "size", "grout", "roughness", "wetness", "frost", "embers", "ember_color", "moss", "moss_color", "brass", "cracks", "sparkle"]
const DEFAULT_PALETTE := ["49433d", "45413b", "4d463e", "413e39", "50473e"]
static var detail_texture: ImageTexture
static var brick_albedo: ImageTexture
static var brick_normal: ImageTexture
static var floor_materials: Dictionary = {}
static var wall_materials: Dictionary = {}
static var meshes: Dictionary = {}

static func quality() -> int:
	return maxi(0, Settings.DETAIL_LEVELS.find(Settings.values.effects_detail))

## Four kinds of seamless noise in one texture: mottling, patches, frost and
## ridged veins for cracks. Built once, on first use.
static func detail() -> ImageTexture:
	if detail_texture: return detail_texture
	var size = 128
	var layers: Array = []
	for spec in [[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, .045, FastNoiseLite.FRACTAL_FBM, 11], [FastNoiseLite.TYPE_CELLULAR, .03, FastNoiseLite.FRACTAL_NONE, 23],
			[FastNoiseLite.TYPE_SIMPLEX, .09, FastNoiseLite.FRACTAL_FBM, 37], [FastNoiseLite.TYPE_SIMPLEX, .035, FastNoiseLite.FRACTAL_RIDGED, 51]]:
		var noise = FastNoiseLite.new()
		noise.noise_type = spec[0]
		noise.frequency = spec[1]
		noise.fractal_type = spec[2]
		noise.seed = spec[3]
		layers.append(noise.get_seamless_image(size, size).get_data())
	var bytes = PackedByteArray()
	bytes.resize(size * size * 4)
	var stride = layers[0].size() / (size * size)
	for i in size * size:
		for c in 4:
			bytes[i * 4 + c] = layers[c][i * stride]
	var image = Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, bytes)
	image.generate_mipmaps()
	detail_texture = ImageTexture.create_from_image(image)
	return detail_texture

## The floor sheet for one cell at the current detail.
static func floor_mesh() -> PlaneMesh:
	var level = quality()
	if meshes.has(level): return meshes[level]
	var mesh = PlaneMesh.new()
	mesh.size = CELL
	mesh.subdivide_width = int(CELL.x) * DENSITY[level]
	mesh.subdivide_depth = int(CELL.y) * DENSITY[level]
	meshes[level] = mesh
	return mesh

static func floor_material(look: Dictionary) -> ShaderMaterial:
	var key = "%s|%d" % [JSON.stringify(look.get("floor", [])) + JSON.stringify(look.get("surface", {})), quality()]
	if floor_materials.has(key): return floor_materials[key]
	var surface: Dictionary = look.get("surface", {})
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/floor_stone.gdshader")
	var colors: Array = look.get("floor", DEFAULT_PALETTE)
	for i in 5: mat.set_shader_parameter("palette_" + "abcde"[i], Color(colors[i]))
	mat.set_shader_parameter("pattern", maxi(0, PATTERNS.find(surface.get("pattern", "slabs"))))
	mat.set_shader_parameter("stone_size", float(surface.get("size", 2.4)))
	mat.set_shader_parameter("grout_color", Color(surface.get("grout", "17150f")))
	mat.set_shader_parameter("roughness_value", float(surface.get("roughness", .85)))
	for key_name in ["wetness", "frost", "embers", "moss", "brass", "cracks", "sparkle"]:
		mat.set_shader_parameter(key_name, float(surface.get(key_name, .5 if key_name == "cracks" else 0.0)))
	if surface.has("ember_color"): mat.set_shader_parameter("ember_color", Color(surface.ember_color))
	if surface.has("moss_color"): mat.set_shader_parameter("moss_color", Color(surface.moss_color))
	mat.set_shader_parameter("relief", RELIEF[quality()])
	mat.set_shader_parameter("detail", detail())
	floor_materials[key] = mat
	return mat

## Bricks in running bond with mortar, chips and per-brick tone, plus their
## normal map. Two world units square, tinted by the wall's own colour.
static func bricks() -> void:
	if brick_albedo: return
	var size = 128
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = .08
	noise.seed = 7
	var tone = Image.create(size, size, false, Image.FORMAT_RGB8)
	var bump = Image.create(size, size, false, Image.FORMAT_RGB8)
	var rows = 8
	var columns = 4
	for y in size:
		var row = y * rows / size
		var fy = float(y * rows % size) / size
		for x in size:
			var shift = (size / columns / 2) if row % 2 == 1 else 0
			var xs = (x + shift) % size
			var column = xs * columns / size
			var fx = float(xs * columns % size) / size
			var n = noise.get_noise_2d(x, y) * .5 + .5
			var edge = minf(minf(fx, 1.0 - fx) * size / columns, minf(fy, 1.0 - fy) * size / rows)
			var mortar = edge < 1.6 + n * 1.2
			var brick_tone = .78 + .3 * fposmod(sin(float(column * 7 + row * 13) * 12.9898) * 43758.5453, 1.0)
			var value = .46 if mortar else brick_tone * (.82 + .3 * n)
			tone.set_pixel(x, y, Color(value, value, value))
			var height = 0.0 if mortar else clampf(edge / 4.0, 0.0, 1.0) * (.75 + .25 * n)
			bump.set_pixel(x, y, Color(height, height, height))
	tone.generate_mipmaps()
	bump.bump_map_to_normal_map(6.0)
	bump.generate_mipmaps()
	brick_albedo = ImageTexture.create_from_image(tone)
	brick_normal = ImageTexture.create_from_image(bump)

## A wall face or cap: the brick texture in world space, so every wall's
## courses line up; a cap is smoother, dressed stone.
static func wall_material(color: Color, cap := false) -> StandardMaterial3D:
	var key = "%s|%s|%d" % [color.to_html(), cap, quality()]
	if wall_materials.has(key): return wall_materials[key]
	var mat = StandardMaterial3D.new()
	mat.roughness = .82 if not cap else .7
	if quality() == 0:
		mat.albedo_color = color
	else:
		bricks()
		var lift = 1.45 if not cap else 1.3
		mat.albedo_color = Color(color.r * lift, color.g * lift, color.b * lift, 1.0)
		mat.albedo_texture = brick_albedo
		mat.normal_enabled = true
		mat.normal_texture = brick_normal
		mat.normal_scale = .8 if not cap else .4
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE * (.5 if not cap else .35)
	wall_materials[key] = mat
	return mat
