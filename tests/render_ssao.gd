extends SceneTree
## Opt-in GL comparison of real depth-based contact occlusion and HUD safety.
## Requires EMBERKEEP_SSAO_CAPTURE and disposable XDG storage.
var measurements: Array = []
var captures: Dictionary = {}
func mean_difference(a: Image, b: Image, rect: Rect2i, absolute := false) -> float:
	var sum := 0.0
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var av := a.get_pixel(x,y)
			var bv := b.get_pixel(x,y)
			var difference := (av.r+av.g+av.b-bv.r-bv.g-bv.b)/3.0
			sum += absf(difference) if absolute else difference
	return sum/float(rect.size.x*rect.size.y)

func _initialize() -> void: call_deferred("capture")
func box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var view = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	view.mesh = mesh
	view.position = at
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .9
	view.material_override = material
	parent.add_child(view)
func capture() -> void:
	var output = OS.get_environment("EMBERKEEP_SSAO_CAPTURE")
	if output.is_empty() or DisplayServer.get_name()=="headless":
		push_error("Set EMBERKEEP_SSAO_CAPTURE and run with an OpenGL display")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.13,.15,.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = .8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	scene.add_child(environment)
	var light = DirectionalLight3D.new()
	light.light_energy = .35
	light.rotation_degrees = Vector3(-45,-25,0)
	scene.add_child(light)
	box(scene,Vector3(0,-.16,0),Vector3(14,.3,14),Color(.57,.58,.59))
	box(scene,Vector3(0,.65,0),Vector3(1.8,1.3,1.8),Color(.61,.59,.55))
	box(scene,Vector3(-2.2,1.4,-1.5),Vector3(.25,2.8,5.4),Color(.5,.54,.57))
	box(scene,Vector3(.3,1.4,-3),Vector3(5.2,2.8,.25),Color(.5,.54,.57))
	var camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(4,3.3,6)
	camera.look_at(Vector3(-.2,.6,-.6))
	camera.fov = 58
	camera.current = true
	var pass_node = ScreenAmbientOcclusion.create(camera)
	# This world-space alpha card must survive the screen-reading AO pass.
	var flame = MeshInstance3D.new()
	var flame_mesh = QuadMesh.new()
	flame_mesh.size = Vector2(.5,.8)
	flame.mesh = flame_mesh
	flame.position = Vector3(1.7,.8,0)
	var flame_material = StandardMaterial3D.new()
	flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.albedo_color = Color(.8,.22,.04,.8)
	flame_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flame.material_override = flame_material
	scene.add_child(flame)
	var layer = CanvasLayer.new()
	layer.layer = 5
	root.add_child(layer)
	var hud = ColorRect.new()
	hud.position = Vector2(32,32)
	hud.size = Vector2(120,56)
	hud.color = Color(.85,.45,.12)
	layer.add_child(hud)
	for quality in ["off","low","high"]:
		pass_node.configure(quality,true)
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		captures[quality] = image
		image.save_png(output.path_join(quality+".png"))
		measurements.append({"quality":quality,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"video_mb":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0})
	# A zero-intensity depth pass must leave scene color unchanged. This
	# catches double tonemapping that a bright ungraded fixture can conceal.
	pass_node.configure("high",true)
	pass_node.surface.set_shader_parameter("intensity",0.0)
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var zero := root.get_texture().get_image()
	var scene_error := mean_difference(captures.off,zero,Rect2i(200,150,800,500),true)
	var contact := mean_difference(captures.off,captures.high,Rect2i(530,460,160,40))
	var hud_error := mean_difference(captures.off,captures.high,Rect2i(32,32,120,56),true)
	if scene_error>.0001 or contact<.004 or hud_error>.00001:
		push_error("SSAO comparison failed: zero-pass scene error=%f contact=%f HUD error=%f" % [scene_error,contact,hud_error])
		quit(1)
		return
	print("SSAO GL pixels: zero-pass error=",scene_error," contact darkening=",contact," HUD error=",hud_error)
	var settings = root.get_node_or_null("Settings")
	if settings and settings.fullscreen_supported():
		var windowed_size := DisplayServer.window_get_size()
		settings.set_value("fullscreen",true)
		for frame in 3: await process_frame
		if DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_FULLSCREEN:
			push_error("Fullscreen preference did not reach the desktop window")
			quit(1)
			return
		settings.set_value("fullscreen",false)
		for frame in 3: await process_frame
		if DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_WINDOWED or DisplayServer.window_get_size()!=windowed_size:
			push_error("Windowed preference did not restore the desktop window and size")
			quit(1)
			return
		print("SSAO GL: fullscreen/windowed preference applied and restored")
	var file = FileAccess.open(output.path_join("measurements.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(measurements,"  "))
	print("SSAO GL: ",JSON.stringify(measurements))
	scene.queue_free()
	layer.queue_free()
	await process_frame
	await process_frame
	quit()
