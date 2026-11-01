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
	check(style.verify_material_assets().is_empty(), "all high-resolution materials and retained authoring sheets load")
	for quality in ["low", "balanced", "high"]:
		settings.set_value("effects_detail", quality)
		for theme in content.families.floors:
			var mat = style.floor_material(theme.look)
			check(mat == style.floor_material(theme.look), "floor materials cached: " + theme.id)
			check(style.floor_mesh().get_mesh_arrays()[Mesh.ARRAY_VERTEX].size() == 4, "first-person ground keeps four vertices at " + quality)
			check(mat.shader.resource_path == "res://shaders/dungeon_floor.gdshader", "all themes use physically shaded ground")
			check(mat.get_shader_parameter("paint").get_width() == DungeonPBR.resolution(), "real source texture matches the device budget")
	check(style.maps.size() <= 3, "three reusable maps cover every theme")
	check(root.get_node("Run").rng.state == original_rng, "cosmetic textures never consume gameplay random numbers")
	var textures = load("res://scripts/graphics/dungeon_textures.gd")
	var surfaces: Dictionary = {}
	for theme in content.families.floors:
		var texture = textures.wall(theme.id)
		check(texture == textures.wall(theme.id), "theme masonry reuses its generated texture: " + theme.id)
		check(texture.paint.get_width() == 256 and texture.normal.get_width() == 256, "theme masonry fits the texture budget")
		surfaces[hash(texture.paint.get_image().get_data())] = true
	check(surfaces.size() >= 6, "floors have distinct masonry artwork, not just different tint values")
	check(textures.wall("unknown_future_floor") == textures.wall("masonry"), "unknown theme uses bounded fallback artwork")
	check(root.get_node("Run").rng.state == original_rng, "theme masonry does not consume gameplay randomness")
	for family in DungeonPBR.FAMILIES:
		var source: Dictionary = DungeonPBR.maps(family)
		check(source == DungeonPBR.maps(family), "source PBR maps are shared: " + family)
		check(source.paint.get_width() == 2048 and source.normal.get_width() == 2048, "desktop uses actual 2K source detail")
		check(source.orm.get_width() == 1024, "packed AO/roughness uses a bounded shared map")
	check(DungeonPBR.maps("unknown_future_surface") == DungeonPBR.maps("masonry"), "unknown surface cannot grow the texture-family cache")
	var policy = load("res://scripts/graphics/render_policy.gd")
	policy.device_override = policy.for_device("Android", "Imagination", "PowerVR", "gl_compatibility")
	check(not policy.current().post_processing and not policy.current().msaa, "style preserves PowerVR restrictions")
	for family in DungeonPBR.FAMILIES:
		var source: Dictionary = DungeonPBR.maps(family)
		check(source.paint.get_width() == 1024 and source.normal.get_width() == 1024, "mobile loads smaller originals without changing physical response")
		check(source.orm == DungeonPBR.loaded[family+"_desktop"].orm, "mobile shares the same physical surface properties")
	check(DungeonPBR.loaded.size() <= 8, "all device variants remain bounded by four surface families")
	check(root.get_node("Run").rng.state == original_rng, "loading true surface maps never spends gameplay randomness")
	var lightweight = style.floor_mesh()
	check(lightweight.subdivide_width == 0 and lightweight.subdivide_depth == 0, "fallback has no displaced ground geometry")
	for path in ["res://shaders/dungeon_floor.gdshader", "res://shaders/dungeon_wall.gdshader", "res://shaders/dungeon_wood.gdshader", "res://shaders/lantern_glass.gdshader"]:
		var code: String = load(path).code
		check(not "hint_screen_texture" in code and not "hint_depth_texture" in code and not "textureLod" in code, "style shader avoids screen/depth/vertex textures: " + path)
	print("DUNGEON STYLE: %d checks, %d failures; maps=%d materials=%d" % [checks,failures,style.maps.size(),style.materials.size()])
	quit(0 if failures == 0 else 1)
