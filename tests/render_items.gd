extends SceneTree
## Opt-in OpenGL capture of the Phase 3 items: ./tools/render.sh items
## Shows every pickup visual, a locked chest, a live bomb, a dropped active
## and the touch HUD with the active and bomb buttons.
var failures = 0
var game
var run

func _initialize() -> void:
	if OS.get_environment("EMBERKEEP_RENDER_TEST") != "1" or DisplayServer.get_name() == "headless":
		push_error("Use tools/render.sh items with a real display, not --headless.")
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
	print("ITEM_RENDER ", name, " image=", path)

func capture() -> void:
	run = root.get_node("Run")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_run("candle", 777, false)
	await process_frame
	game.set_physics_process(false)
	var kinds = ["copper_coin", "silver_coin", "half_heart", "full_heart", "ward", "key", "bomb", "small_battery", "full_battery"]
	for i in kinds.size():
		game.spawn_pickup(Vector3(-5 + i * 1.2, 0, 2.5), kinds[i], 1)
	var data: Dictionary = run.rooms[run.current_room]
	data.chests = [{"id": "render:0", "position": [-5.5, -3.8], "locked": true, "opened": false, "table": "chest"}]
	game.equip_active("pocket_hearth")
	game.equip_active("ember_flask")
	run.cooldowns.ember_flask = 9.0
	run.keys = 2
	run.bombs = 3
	run.wards = 1
	game.player.position = Vector3(3, 0, -1)
	game.perform_action({"type": "PlaceBomb"})
	game.player.position = Vector3(0, 0, 0)
	game.ui.touch_used = true
	game.build_room_objects()
	await shot("items_room")
	game.end_run(false)
	game.queue_free()
	await process_frame
	print("EMBERKEEP ITEM RENDER RESULT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
