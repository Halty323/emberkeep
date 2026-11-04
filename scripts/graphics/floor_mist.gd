class_name FloorMist
extends RefCounted
## Mist lingering over the floor on the first two floors of a climb, the
## damp low rooms at the bottom of the tower. It is made of sheets of slow,
## drifting noise at ankle and shin height, in every room and passage; kept
## that low, it meets walls, doors and furniture where they meet the floor.
## Lanterns, candles, spells and the player's own light make it glow; between
## them it fades into the dark (shaders/floor_mist.gdshader).
## Low effects detail keeps one sheet; others lay two.
const FLOORS := 2
# [height above the floor, strength, noise offset] for each sheet.
const SHEETS := [[.12, 1.0, Vector2.ZERO], [.4, .7, Vector2(.43, .17)]]
static var materials: Array = []
static var noise: ImageTexture

## Whether the floor being played lingers in mist.
static func wanted() -> bool:
	return Run.active and Run.floor_number <= FLOORS

static func sheet_count() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var settings = tree.root.get_node_or_null("Settings") if tree else null
	return 1 if settings and str(settings.values.get("effects_detail", "")) == "low" else SHEETS.size()

## Lays the mist over one floor rectangle (a room cell or a passage tile).
static func cover(parent: Node3D, area: Rect2, light: Dictionary = {}, layers := 1) -> void:
	for i in sheet_count():
		var sheet := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = area.size
		sheet.mesh = plane
		sheet.material_override = material(i, light)
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sheet.layers = layers
		sheet.position = Vector3(area.get_center().x, float(SHEETS[i][0]), area.get_center().y)
		sheet.set_meta("surface_role", "mist")
		parent.add_child(sheet)

## One material per sheet, shared by every room; the floor's light tints it.
static func material(index: int, light: Dictionary) -> ShaderMaterial:
	while materials.size() <= index:
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/floor_mist.gdshader")
		mat.set_shader_parameter("noise_map", noise_map())
		mat.set_shader_parameter("strength", .5 * float(SHEETS[materials.size()][1]))
		mat.set_shader_parameter("offset", SHEETS[materials.size()][2])
		materials.append(mat)
	if not light.is_empty():
		# Cool and pale, leaning a little to the floor's own ambient colour;
		# the cellar's mist is thicker than the floor above it.
		var tint: Color = Color("b6c2cc").lerp(light.get("ambient_color", Color("9aaec2")), .3)
		materials[index].set_shader_parameter("tint", tint)
		materials[index].set_shader_parameter("strength", (.85 if Run.floor_number <= 1 else .68) * float(SHEETS[index][1]))
	return materials[index]

static func noise_map() -> ImageTexture:
	if noise: return noise
	var source := FastNoiseLite.new()
	source.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	source.frequency = .018
	source.fractal_octaves = 3
	source.seed = 1307
	var image: Image = source.get_seamless_image(128, 128)
	image.convert(Image.FORMAT_L8)
	image.generate_mipmaps()
	noise = ImageTexture.create_from_image(image)
	return noise
