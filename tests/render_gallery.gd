extends SceneTree
## Opt-in OpenGL capture of the Phase 6 painting collection: ./tools/render.sh gallery
## Shows a furnished room with its mounted painting, the painting viewer and
## the journal's gallery page with a partly discovered collection.
var failures = 0
var game
var run

func _initialize() -> void:
	if OS.get_environment("EMBERKEEP_RENDER_TEST") != "1" or DisplayServer.get_name() == "headless":
		push_error("Use tools/render.sh gallery with a real display, not --headless.")
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
	print("GALLERY_RENDER ", name, " image=", path)

func capture() -> void:
	run = root.get_node("Run")
	var F = load("res://scripts/dungeon/furnishing.gd")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_run("candle", 777, false)
	await process_frame
	game.set_physics_process(false)
	var key := ""
	for k in run.rooms:
		if run.rooms[k].get("gallery") == "guaranteed" and run.rooms[k].has("mount"): key = k
	if key == "":
		fail("no gallery room on this seed")
	else:
		run.current_room = key
		run.rooms[key].cleared = true
		game.enter_room(Vector3.ZERO)
		await process_frame
		var view: Vector2 = F.view_point(run.rooms[key].mount)
		game.player.position = Vector3(view.x, 0, view.y)
		await shot("gallery_room")
		game.inspect_painting(run.rooms[key].painting)
		await shot("gallery_viewer")
		game.ui.close_painting()
		for id in ["mona_lisa", "starry_night", "kiss_1907"]:
			load("res://scripts/gallery/gallery.gd").discover(id)
		game.paused = true
		game.ui.show_screen("gallery")
		await shot("gallery_journal")
	game.end_run(false)
	game.queue_free()
	await process_frame
	print("EMBERKEEP GALLERY RENDER RESULT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
