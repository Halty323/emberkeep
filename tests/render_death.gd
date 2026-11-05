extends SceneTree
## Opt-in native capture of Death's bargain: Death as a black shape in the
## mist, then robed, then with its eyes lit, and the bargain screen over it.
## Needs a display (or Xvfb) and EMBERKEEP_DEATH_CAPTURE set to an output
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
	if out != "": image.save_png(out.path_join("death_%s.png" % label))
	print("DEATH CAPTURE %s" % label)

func go() -> void:
	var out := OS.get_environment("EMBERKEEP_DEATH_CAPTURE")
	run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(2)
	game.start_run("candle", 7070, false)
	await frames(30)
	# Death's rooms come from the second floor, on about a third of floors.
	var dark_ids: Array = []
	for attempt in 40:
		run.seed_value = 7070 + attempt
		run.floor_number = 3
		run.generate_floor()
		dark_ids = run.rooms.keys().filter(func(id): return run.rooms[id].type == "dark")
		if not dark_ids.is_empty(): break
	var dark_id = dark_ids[0]
	run.current_room = dark_id
	game.enter_room(game.room.pedestal + Vector3(0, 0, 3.2) if game.room else Vector3(0, 0, 3))
	await frames(20)
	game.player.place(game.room.pedestal + Vector3(0, 0, 3.4))
	game.set_physics_process(false)
	var figure = game.death_figure
	figure.set_process(false)
	var towards: Vector3 = figure.global_position + Vector3.UP * 1.5 - (game.player.global_position + Vector3.UP * 1.6)
	game.fps.yaw = atan2(-towards.x, -towards.z)
	game.fps.pitch = .08
	figure.rotation.y = atan2(-towards.x, -towards.z)
	for stage in [["shape", 1.7], ["robed", 3.1], ["eyes", 5.0]]:
		figure.state = "rising"
		figure.clock = stage[1]
		figure._process(0.0)
		await frames(6)
		shot(out, stage[0])
	game.open_bargain()
	figure._process(0.0)
	game.ui.pick_bargain(1, "trial")
	await frames(6)
	shot(out, "bargain")
	game.queue_free()
	await frames(3)
	quit(0)
