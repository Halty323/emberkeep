extends SceneTree
func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("capture")
func capture() -> void:
	var out = OS.get_environment("EMBERKEEP_TITLE_CAPTURE")
	if out.is_empty():
		push_error("Set EMBERKEEP_TITLE_CAPTURE to a capture directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var settings = root.get_node("Settings")
	settings.set_value("sound",false)
	settings.set_value("music",false)
	RenderPolicy.device_override = RenderPolicy.for_device("Android","Imagination","PowerVR","gl_compatibility")
	settings.apply_render_policy()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("home.png"))
	game.ui.show_screen("armory")
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("preparation.png"))
	print("TITLE GL: draw calls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," nodes=",Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	game.queue_free()
	await process_frame
	quit()
