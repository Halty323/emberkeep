extends SceneTree
## The experiment must keep its memory/pass budgets, project the actual
## reflected perspective, and leave the gameplay random stream untouched.
var checks := 0
var failures := 0
var game

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("exercise")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func settle() -> void:
	for i in 3: await process_frame

func exercise() -> void:
	# A headless root defaults to a 64x64 render target while its stretched
	# visible rect is 1280x720. Use a real screen ratio for projection checks.
	root.size = Vector2i(1280,720)
	var settings = root.get_node("Settings")
	var run = root.get_node("Run")
	var style = load("res://scripts/graphics/dungeon_style.gd")
	var lighting = load("res://scripts/dungeon/floor_light.gd")
	var water = load("res://scripts/graphics/water_mirror.gd")
	var rng_state: int = run.rng.state
	var environment := Environment.new()
	RenderPolicy.device_override = RenderPolicy.for_device("Linux","Mesa","test","gl_compatibility")
	DungeonAtmosphere.configure(environment)
	check(environment.sky != null and environment.sky.radiance_size == Sky.RADIANCE_SIZE_128,"reflected indirect light has one small static radiance cube")
	var radiance = environment.sky
	for floor_number in [1,2,3]: DungeonAtmosphere.configure(environment,lighting.first_person(lighting.profile(floor_number)))
	check(environment.sky == radiance,"changing floor color reuses the existing radiance resource")
	check(environment.ambient_light_source == Environment.AMBIENT_SOURCE_BG,"radiance configuration does not overwrite diffuse ambient preferences")
	RenderPolicy.device_override = RenderPolicy.for_device("Android","Imagination","PowerVR","gl_compatibility")
	DungeonAtmosphere.configure(environment)
	check(environment.sky == null and environment.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED,"PowerVR never allocates the radiance cube")
	settings.set_value("effects_detail","high")
	for material in [style.floor_material({}),style.wall_material(Color.WHITE),style.wood_material(Color.WHITE)]:
		check(is_zero_approx(material.get_shader_parameter("relief_depth")),"PowerVR retains carved normals without extra height refinements")
	RenderPolicy.device_override = RenderPolicy.for_device("Linux","Mesa","test","gl_compatibility")
	for quality in ["high","low","balanced","high"]:
		settings.set_value("effects_detail",quality)
		var material = style.wall_material(Color.WHITE)
		check((material.get_shader_parameter("relief_depth")>0.0) == (quality!="low"),"height detail follows settings without stale cache entries")
	check(run.rng.state == rng_state,"material, radiance and quality changes never advance gameplay RNG")
	settings.set_value("sound",false)
	settings.set_value("music",false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.start_run("candle",18523427,false)
	game.paused = true
	await settle()
	var wall_material = style.wall_material(Color.WHITE)
	var held_material: ShaderMaterial = game.fps.weapon_shape.get_child(0).material_override
	var held_id: int = held_material.get_instance_id()
	game.camera.position = Vector3(1,1.5,5)
	game.camera.look_at(Vector3(0,0,-4))
	game.camera.fov = 88
	game.mirror.follow(true,Vector2(1280,720))
	check(is_equal_approx(game.mirror.mirror.fov,88),"perspective mirror copies the player's actual field of view")
	check(game.mirror.mirror.projection == game.camera.projection,"mirror uses the same projection mode")
	check(game.mirror.mirror.get_world_3d() == game.camera.get_world_3d(),"reflection camera shares the actual room's 3D world")
	check(game.mirror.canvas_cull_mask == 0,"auxiliary viewport cannot inherit root 2D drawing")
	check(game.mirror.mirror.global_basis.determinant() > .99,"reflected camera remains a proper right-handed basis")
	check(is_equal_approx(game.mirror.mirror.position.y,2*water.SURFACE-game.camera.position.y),"camera is reflected about the actual water surface")
	for point in [Vector3(-1,2,-4),Vector3(2,1,-6),Vector3(.5,3,-8)]:
		var reflected: Vector3 = point
		reflected.y = 2*water.SURFACE-point.y
		var wanted: Vector2 = game.camera.unproject_position(reflected)/game.camera.get_viewport().get_visible_rect().size
		var actual: Vector2 = game.mirror.mirror.unproject_position(point)/Vector2(game.mirror.size)
		actual.x = 1-actual.x
		check(actual.distance_to(wanted)<.003,"mirrored geometry aligns with its mathematical surface projection")
	for mesh in game.fps.weapon_shape.find_children("*","MeshInstance3D",true,false):
		check(mesh.layers & game.mirror.mirror.cull_mask == 0,"the player's held weapon never floats inside a room reflection")
		check(mesh.layers & Geo.LIT_LAYERS != 0,"the held weapon still receives the real room lights")
	check(game.mirror.mirror.cull_mask & (2|8) == 0,"mirror excludes screen passes, residue and ground to prevent recursion")
	for lantern in game.room.lanterns:
		check(lantern.glass.layers & game.mirror.mirror.cull_mask != 0,"real world flames remain visible in the reflection")
		check(lantern.glass.layers & Geo.LIT_LAYERS == 0,"reflected flames never receive additive fixture light")
	check(game.mirror.get_child_count() == 1 and game.mirror.msaa_3d == Viewport.MSAA_DISABLED,"reflection uses exactly one camera and no MSAA")
	check(game.mirror.positional_shadow_atlas_size==256 and game.mirror.positional_shadow_atlas_quad_0==Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1,"Compatibility reflection keeps a valid, bounded single shadow tile")
	game.residue.add("water",Vector3.ZERO,2,true)
	game.residue.rebuild("water")
	game._process(.016)
	check(game.mirror.render_target_update_mode == SubViewport.UPDATE_ALWAYS,"a wet first-person room actually starts the mirror")
	check(game.residue.views.water.material.shader.resource_path.ends_with("/water_stylized.gdshader"),"first-person water uses the lit, screen-copy-free glaze")
	check(game.residue.views.water.view.mesh.get_mesh_arrays()[Mesh.ARRAY_VERTEX].size() == 4,"flat water keeps a two-triangle shared surface")
	var terrain = game.room.terrain
	var old_ledge: Rect2 = terrain.ledge
	terrain.ledge = Rect2(Vector2.ONE,Vector2(4,4))
	check(not game.residue.reflective(),"split levels never sample a reflection from the wrong elevation")
	terrain.ledge = old_ledge
	settings.set_value("effects_detail","low")
	game._process(.016)
	check(game.mirror.render_target_update_mode == SubViewport.UPDATE_DISABLED,"effects Low stops the extra reflected room render")
	check(is_zero_approx(wall_material.get_shader_parameter("relief_depth")) and is_zero_approx(held_material.get_shader_parameter("relief_depth")),"effects Low immediately updates wall and held-weapon materials already in use")
	settings.set_value("effects_detail","high")
	check(wall_material.get_shader_parameter("relief_depth")>0 and held_material.get_shader_parameter("relief_depth")>0,"returning to High restores existing surface relief")
	check(held_material.get_instance_id()==held_id and game.fps.weapon_shape.get_child(0).material_override==held_material,"live quality changes reuse the original view model material")
	RenderPolicy.device_override = RenderPolicy.for_device("Android","Imagination","PowerVR","gl_compatibility")
	game.screen_fx.apply_quality()
	game.mirror.follow(true,Vector2(2424,1080))
	check(game.mirror.render_target_update_mode == SubViewport.UPDATE_DISABLED,"PowerVR cannot enable the mirror even when requested directly")
	check(is_zero_approx(held_material.get_shader_parameter("relief_depth")),"the conservative device policy also updates existing held materials")
	game.queue_free()
	await settle()
	RenderPolicy.device_override = {}
	print("STYLIZED LIGHTING: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
