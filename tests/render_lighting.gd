extends SceneTree
## Opt-in real-renderer regression. Run tools/render_lighting.sh to isolate saves.

func _initialize() -> void:
	if OS.get_environment("EMBERKEEP_RENDER_TEST") != "1" or DisplayServer.get_name() == "headless":
		push_error("Use tools/render_lighting.sh with a real display, not --headless.")
		quit(1)
		return
	call_deferred("capture")

func capture() -> void:
	var output = OS.get_environment("EMBERKEEP_RENDER_OUTPUT")
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("shadows", true)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_run("needle", 20261026, false)
	run.floor_number = 2
	run.generate_floor()
	for key in run.rooms:
		if run.rooms[key].type == "combat":
			run.current_room = key
			break
	run.rooms[run.current_room].cleared = true
	run.rooms[run.current_room].claimed = true
	game.enter_room(Vector3(0, 0, 2.0))
	game.paused = true
	game.ui.toast_time = 0
	game.make_marker("rest", Vector3(1.0, 0, -1.0))
	game.spawn_enemy(Vector3(-3, 0, 0), "mote")
	game.spawn_enemy(Vector3(3.5, 0, -.5), "brute")
	game.spawn_shot(Vector3(1, .65, 1), Vector3.RIGHT, 5, 10, {}, Color("ffc474"), true)
	var failures = 0
	for setting in [true, false]:
		settings.set_value("shadows", setting)
		game.room.apply_lighting_quality()
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		var image = root.get_texture().get_image()
		var path = output.path_join("lantern-shadows-" + ("on" if setting else "off") + ".png")
		if image.save_png(path) != OK:
			push_error("Could not save lighting capture: " + path)
			failures += 1
		# The reported solid halo planes painted the void just left of the room
		# yellow. Test the actual output, not merely the shader's source text.
		var outside = image.get_pixel(int(image.get_width() * 100.0 / 1280), int(image.get_height() * .5))
		var floor_pixel = image.get_pixel(image.get_width() / 2, image.get_height() / 2)
		if outside.get_luminance() > .13 or floor_pixel.get_luminance() < .1:
			push_error("Lighting pixel regression: bright halo outside the room, or an unrendered floor.")
			failures += 1
		var start = Time.get_ticks_usec()
		var calls = 0.0
		for frame in 30:
			await RenderingServer.frame_post_draw
			calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		print("LIGHTING_RENDER shadows=", setting, " frame_ms=", float(Time.get_ticks_usec() - start) / 30000.0,
			" draw_calls=", calls / 30.0, " image=", path)
	game.queue_free()
	root.get_node("Audio").music_player.stop()
	for player in root.get_node("Audio").players: player.stop()
	await process_frame
	await process_frame
	print("EMBERKEEP RENDER TEST RESULT: ", failures, " failures")
	quit(0 if failures == 0 else 1)
