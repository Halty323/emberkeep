extends SceneTree
## Opt-in native capture of the mist on the first two floors: a room on the
## first floor, the same view without mist for comparison, and a lit corner.
## Needs a display (or Xvfb) and EMBERKEEP_MIST_CAPTURE set to an output
## directory.
var game
var run

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("go")

func frames(count: int) -> void:
	for i in count: await process_frame

func shot(out: String, label: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	if out != "": image.save_png(out.path_join("mist_%s.png" % label))
	print("MIST CAPTURE %s" % label)

func go() -> void:
	var out := OS.get_environment("EMBERKEEP_MIST_CAPTURE")
	run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(2)
	game.start_run("candle", 7072, false)
	await frames(40)
	var fight: Array = run.rooms.keys().filter(func(id): return run.rooms[id].type == "combat")
	run.current_room = fight[0]
	run.rooms[fight[0]].cleared = true
	game.enter_room(Vector3(0, 0, 4))
	await frames(30)
	game.set_physics_process(false)
	game.player.place(Vector3(0, game.room.floor_height(Vector3(0, 0, 5)), 5))
	game.fps.yaw = 0.0
	game.fps.pitch = -.12
	await frames(8)
	shot(out, "room")
	var sheets: Array = game.room.find_children("*", "GeometryInstance3D", true, false).filter(func(node): return node.get_meta("surface_role", "") == "mist")
	print("MIST SHEETS %d" % sheets.size())
	for sheet in sheets: sheet.visible = false
	await frames(4)
	shot(out, "room_clear")
	for sheet in sheets: sheet.visible = true
	game.fps.yaw = PI * .75
	await frames(6)
	shot(out, "corner")
	game.queue_free()
	await frames(3)
	quit(0)
