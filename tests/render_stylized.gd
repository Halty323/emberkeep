extends "res://tests/render_light_materials.gd"
## Opt-in GL review, reusing the collision-clear eye-level camera composer.
## EMBERKEEP_STYLE_CAPTURE; optional EMBERKEEP_STYLE_CAPTURE_POLICY=powervr.

func capture() -> void:
	output = OS.get_environment("EMBERKEEP_STYLE_CAPTURE")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Set EMBERKEEP_STYLE_CAPTURE and run with an OpenGL display")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var settings = root.get_node("Settings")
	settings.set_value("sound",false)
	settings.set_value("music",false)
	settings.set_value("small_details","high")
	settings.set_value("effects_detail","high")
	RenderPolicy.device_override = RenderPolicy.for_device("Android","Imagination","PowerVR","gl_compatibility") if OS.get_environment("EMBERKEEP_STYLE_CAPTURE_POLICY")=="powervr" else RenderPolicy.for_device("Linux","Mesa","review","gl_compatibility")
	settings.apply_render_policy()
	run = root.get_node("Run")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	var fixtures := [
		{"name":"cellar-entry","theme":"cellar","depth":1,"shape":"single"},
		{"name":"cistern-bend","theme":"cistern","depth":3,"shape":"bend","seed":64217},
		{"name":"mosslit-hall","theme":"halls","depth":3,"shape":"wide"},
		{"name":"kiln-workshop","theme":"kiln","depth":3,"shape":"wide"},
		{"name":"reflection-room","theme":"cistern","depth":3,"shape":"single"}
	]
	if OS.get_environment("EMBERKEEP_STYLE_REFLECTION_ONLY")=="1": fixtures = [fixtures.back()]
	var scene_filter := OS.get_environment("EMBERKEEP_STYLE_SCENE")
	if not scene_filter.is_empty(): fixtures = fixtures.filter(func(fixture): return fixture.name==scene_filter)
	for fixture in fixtures:
		if not await compose(fixture):
			game.queue_free()
			await process_frame
			quit(1)
			return
	if RenderPolicy.current().reflections and not fixtures.is_empty() and fixtures.back().name=="reflection-room": await reflection_comparison()
	var file := FileAccess.open(output.path_join("measurements.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(measurements,"  "))
	game.queue_free()
	await process_frame
	print("STYLIZED GL REVIEW: ",measurements.size()," eye-level rooms; policy=",RenderPolicy.current().reason)
	quit()

func reflection_comparison() -> void:
	# Lay one broad, real gameplay pool in the composed flat cistern. Avoid
	# comparing two different scenes or an orthographic material test sphere.
	var at: Vector3 = game.player.global_position+game.fps.forward()*3.5
	at.y = 0
	game.residue.add("water",at,4.2,true)
	game.residue.rebuild("water")
	game.set_process(false)
	game.mirror.follow(true,root.get_visible_rect().size)
	game.residue.set_mirror(true)
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("reflections-on.png"))
	var reflected: Image = game.mirror.get_texture().get_image()
	reflected.save_png(output.path_join("reflection-camera.png"))
	# Projection tests cannot detect a broken lit draw pass. This furnished
	# fixture must contain many opaque surface edges, not just sky and flames.
	var edges := 0
	for y in range(1,reflected.get_height()):
		for x in reflected.get_width():
			var a := reflected.get_pixel(x,y)
			var b := reflected.get_pixel(x,y-1)
			if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))) > 6.0/255: edges += 1
	print("REFLECTION IMAGE: ",edges," lit-scene edges")
	if edges < 2000:
		push_error("Reflection is missing the furnished room's opaque geometry")
		quit(1)
		return
	game.mirror.follow(false,root.get_visible_rect().size)
	game.residue.set_mirror(false)
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("reflections-off.png"))
	print("STYLIZED REFLECTION: perspective FOV=",game.mirror.mirror.fov," target=",game.mirror.size," msaa=",game.mirror.msaa_3d)
