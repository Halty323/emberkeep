extends SceneTree
## Real GLES pixel checks for local volumetric integration and opaque depth.
## Run tools/render_room_illumination.sh under an OpenGL display.
var failures := 0
func _initialize() -> void: call_deferred("exercise")
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; push_error("FAIL: "+label)
func frame_image(name: String) -> Image:
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var directory := OS.get_environment("EMBERKEEP_LIGHT_VOLUME_CAPTURE")
	if not directory.is_empty(): picture.save_png(directory.path_join(name+".png"))
	return picture
func difference(a: Image, b: Image) -> float:
	var sum := 0.0
	var count := 0
	for y in range(0,a.get_height(),4):
		for x in range(0,a.get_width(),4):
			sum += absf(a.get_pixel(x,y).get_luminance()-b.get_pixel(x,y).get_luminance())
			count += 1
	return sum/count
func exercise() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run with a real OpenGL display")
		quit(1); return
	var settings = root.get_node("Settings")
	settings.set_value("sound",false); settings.set_value("music",false)
	settings.set_value("effects_detail","high")
	var policy = load("res://scripts/graphics/render_policy.gd")
	policy.device_override = policy.for_device("Android","Imagination","PowerVR","gl_compatibility")
	settings.apply_render_policy()
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("10161e")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = 0.0
	world.add_child(environment)
	var camera := Camera3D.new()
	camera.position = Vector3(0,1.5,5)
	world.add_child(camera)
	var type = load("res://scripts/graphics/room_illumination.gd")
	var fog = type.new()
	world.add_child(fog)
	fog.add_volume(Vector3(0,3.5,0),0.0,Color("b3cde0"),2.3)
	fog.apply_quality()
	var visible: Image = await frame_image("volume-visible")
	fog.hide()
	var clear: Image = await frame_image("volume-disabled")
	var presence := difference(visible,clear)
	check(presence > .002,"a genuine spatial light volume is visible from outside")
	fog.show()
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new(); box.size = Vector3(20,20,.2)
	wall.mesh = box
	wall.position = Vector3(0,1.5,2.8)
	var surface := StandardMaterial3D.new()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.albedo_color = Color("192635")
	wall.material_override = surface
	world.add_child(wall)
	var blocked: Image = await frame_image("volume-behind-wall")
	fog.hide()
	var opaque: Image = await frame_image("opaque-wall-only")
	var leak := difference(blocked,opaque)
	check(leak < .001,"an opaque wall completely occludes a light volume behind it")
	wall.hide(); fog.show()
	camera.position = Vector3(0,1.5,.2)
	var inside: Image = await frame_image("inside-volume")
	fog.hide()
	var inside_clear: Image = await frame_image("inside-volume-disabled")
	var interior := difference(inside,inside_clear)
	check(interior > .002 and interior < .22,"walking into the medium keeps thin scattering without a white flash")
	print("LOCAL FOG GLES: %d failures; outside %.5f; wall leak %.6f; inside %.5f" % [failures,presence,leak,interior])
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
