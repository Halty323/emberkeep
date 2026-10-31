extends SceneTree
func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("capture")

func capture() -> void:
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	RenderPolicy.device_override = RenderPolicy.for_device("Android", "Imagination", "PowerVR", "gl_compatibility")
	settings.apply_render_policy()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_run("candle", 64217, false)
	for i in 8: await physics_frame
	game.fps.yaw = -.55
	game.fps.pitch = -.06
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var directory = OS.get_environment("EMBERKEEP_FPS_CAPTURE")
	root.get_texture().get_image().save_png(directory.path_join("first-person-start.png"))
	var run = root.get_node("Run")
	for id in run.rooms:
		if run.rooms[id].type == "combat" and run.rooms[id].cells.size() > 1:
			run.current_room = id
			game.enter_room(Vector3(0, 0, 2))
			break
	game.paused = true
	game.ui.toast_time = 0
	game.ui.floor_title_start = -100
	game.fps.yaw = -.4
	game.fps.pitch = -.05
	game.player.invulnerability = 100
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var clear_image = root.get_texture().get_image()
	clear_image.save_png(directory.path_join("first-person-arena.png"))
	var cloud_at: Vector3 = game.player.global_position + game.fps.forward() * 4.0
	game.residue.add_cloud(cloud_at, 2.0, "steam")
	for cloud in game.residue.clouds: cloud.age = .5
	game.residue.refresh_cloud_surface()
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var single = root.get_texture().get_image()
	single.save_png(directory.path_join("first-person-mist.png"))
	var point = game.camera.unproject_position(Vector3(cloud_at.x, .8, cloud_at.z))
	var clear = sample_patch(clear_image, point)
	var one = sample_patch(single, point)
	game.residue.add_cloud(cloud_at, 2.0, "steam")
	for cloud in game.residue.clouds: cloud.age = .5
	game.residue.refresh_cloud_surface()
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var duplicate = root.get_texture().get_image()
	duplicate.save_png(directory.path_join("first-person-mist-overlap.png"))
	var two = sample_patch(duplicate, point)
	var presence = (absf(one.r - clear.r) + absf(one.g - clear.g) + absf(one.b - clear.b)) / 3
	var overlap = absf(two.get_luminance() - one.get_luminance())
	var passed = presence > .0015 and overlap < .004
	print("FIRST PERSON GL: presence=", presence, " overlap gain=", overlap, " passed=", passed, " projection=", game.camera.projection, " policy=", RenderPolicy.current().reason)
	if not passed: push_error("FAIL: eye-level mist must render without accumulating overlap brightness")
	game.queue_free()
	await process_frame
	quit(0 if passed else 1)

func sample_patch(picture: Image, point: Vector2) -> Color:
	var total = Color(0, 0, 0, 0)
	for x in range(-6, 7):
		for y in range(-6, 7):
			total += picture.get_pixel(clampi(roundi(point.x) + x, 0, picture.get_width() - 1), clampi(roundi(point.y) + y, 0, picture.get_height() - 1))
	return total / 169.0
