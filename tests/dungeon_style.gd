extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("exercise")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
func exercise() -> void:
	var style = load("res://scripts/graphics/dungeon_style.gd")
	var content = root.get_node("Content")
	var settings = root.get_node("Settings")
	var original_rng: int = root.get_node("Run").rng.state
	for quality in ["low", "balanced", "high"]:
		settings.set_value("effects_detail", quality)
		for theme in content.families.floors:
			var mat = style.floor_material(theme.look)
			check(mat == style.floor_material(theme.look), "floor materials cached: " + theme.id)
			check(style.floor_mesh().get_mesh_arrays()[Mesh.ARRAY_VERTEX].size() == 4, "first-person ground keeps four vertices at " + quality)
			check(mat.shader.resource_path == "res://shaders/dungeon_floor.gdshader", "all themes use painted floor")
			check(mat.get_shader_parameter("paint").get_width() == 256, "bounded period texture dimensions")
	check(style.maps.size() <= 3, "three reusable maps cover every theme")
	check(root.get_node("Run").rng.state == original_rng, "cosmetic textures never consume gameplay random numbers")
	var policy = load("res://scripts/graphics/render_policy.gd")
	policy.device_override = policy.for_device("Android", "Imagination", "PowerVR", "gl_compatibility")
	check(not policy.current().post_processing and not policy.current().msaa, "style preserves PowerVR restrictions")
	var lightweight = style.floor_mesh()
	check(lightweight.subdivide_width == 0 and lightweight.subdivide_depth == 0, "fallback has no displaced ground geometry")
	for path in ["res://shaders/dungeon_floor.gdshader", "res://shaders/dungeon_wall.gdshader", "res://shaders/dungeon_wood.gdshader", "res://shaders/lantern_glass.gdshader"]:
		var code: String = load(path).code
		check(not "hint_screen_texture" in code and not "hint_depth_texture" in code and not "textureLod" in code, "style shader avoids screen/depth/vertex textures: " + path)
	print("DUNGEON STYLE: %d checks, %d failures; maps=%d materials=%d" % [checks,failures,style.maps.size(),style.materials.size()])
	quit(0 if failures == 0 else 1)
