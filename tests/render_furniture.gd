extends SceneTree
## Opt-in OpenGL captures of furnished rooms: ./tools/render.sh furniture
## One capture per layout theme plus a concealed seam before and after reveal.
var failures = 0
var game
var run

func _initialize() -> void:
	if OS.get_environment("EMBERKEEP_RENDER_TEST") != "1" or DisplayServer.get_name() == "headless":
		push_error("Use tools/render.sh furniture with a real display, not --headless.")
		quit(1)
		return
	call_deferred("capture")

func fail(message: String) -> void:
	failures += 1
	push_error("FAIL: " + message)

func shot(name: String) -> void:
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	var path = OS.get_environment("EMBERKEEP_RENDER_OUTPUT").path_join(name + ".png")
	if image.save_png(path) != OK:
		fail("could not save " + path)
	print("FURNITURE_RENDER ", name, " image=", path)

func find(want: Callable) -> Array:
	run.generator = run.GENERATOR_V2
	for seed_value in range(1, 300):
		run.seed_value = seed_value
		run.floor_number = 1
		run.generate_floor()
		for key in run.rooms:
			if want.call(key, run.rooms[key]): return [seed_value, key]
	return []

func show(found: Array, name: String) -> void:
	if found.is_empty():
		fail("no room for " + name)
		return
	game.start_run("candle", found[0], false)
	await process_frame
	run.current_room = found[1]
	run.rooms[found[1]].cleared = true
	game.enter_room(Vector3.ZERO)
	game.paused = true
	await shot(name)

func capture() -> void:
	run = root.get_node("Run")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	for theme in ["reading_room", "storage", "workshop", "living_quarters", "shrine"]:
		await show(find(func(_k, r): return r.get("theme") == theme and r.props.size() > 5), "theme_" + theme)
	await show(find(func(_k, r): return r.template == "hall_grand"), "grand_room")
	var secret = find(func(k, r): return r.type == "secret" and run.rooms[run.neighbors(k, true)[0]].type != "boss")
	if not secret.is_empty():
		var parent: String = run.neighbors(secret[1], true)[0]
		var pid: String = run.room_portal_ids[secret[1]][0]
		await show([secret[0], parent], "seam_hidden")
		var socket = game.room.sockets.filter(func(s): return s.portal == pid)[0]
		var door: Vector3 = game.room.socket_position(socket)
		game.player.position = door - Vector3(socket.dir.x, 0, socket.dir.y) * 2.0
		game.update_camera(0.0, true)
		await shot("seam_hidden_close")
		game.reveal_portal(pid, true)
		await shot("seam_revealed")
	game.end_run(false)
	game.queue_free()
	await process_frame
	print("EMBERKEEP FURNITURE RENDER RESULT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
