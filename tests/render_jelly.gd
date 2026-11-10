extends SceneTree
## Opt-in native capture of gelatin foes and bloom: a line-up of several
## kinds near a lantern, close and from a few steps back. Needs a display (or
## Xvfb) and EMBERKEEP_JELLY_CAPTURE set to an output directory.
var game

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("go")

func frames(count: int) -> void:
	for i in count: await process_frame

func snap(out: String, label: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	if out != "": image.save_png(out.path_join("jelly_%s.png" % label))
	print("JELLY CAPTURE %s" % label)

func go() -> void:
	var out := OS.get_environment("EMBERKEEP_JELLY_CAPTURE")
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	if OS.get_environment("EMBERKEEP_JELLY_BLOOM") != "": settings.set_value("bloom", OS.get_environment("EMBERKEEP_JELLY_BLOOM"))
	if OS.get_environment("EMBERKEEP_JELLY_DETAIL") != "": settings.set_value("effects_detail", OS.get_environment("EMBERKEEP_JELLY_DETAIL"))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(2)
	game.start_run("candle", 7072, false)
	await frames(30)
	run.floor_number = int(OS.get_environment("EMBERKEEP_JELLY_FLOOR")) if OS.get_environment("EMBERKEEP_JELLY_FLOOR") != "" else 3
	var fight: Array = run.rooms.keys().filter(func(id): return run.rooms[id].type == "combat" and run.rooms[id].get("fps_terrain", {}).is_empty())
	run.current_room = fight[0]
	run.rooms[fight[0]].cleared = true
	game.enter_room(Vector3(0, 0, 4))
	await frames(30)
	game.set_physics_process(false)
	# Stand a few steps from the room's first lantern, looking past it.
	var lamp: Vector3 = game.room.lantern_points[0] if not game.room.lantern_points.is_empty() else Vector3.ZERO
	var stand := lamp + Vector3(0, 0, 5.2)
	if not game.room.geometry.contains(Vector2(stand.x, stand.z), 1.0): stand = lamp + Vector3(0, 0, -5.2)
	var toward := (lamp - stand).normalized()
	var side := Vector3(-toward.z, 0, toward.x)
	game.player.place(Vector3(stand.x, game.room.floor_height(stand), stand.z))
	game.fps.yaw = atan2(-toward.x, -toward.z)
	game.fps.pitch = -.12
	var kinds := ["mote", "brute", "spitter", "charger", "sporecap", "bailer", "splitter"]
	for i in kinds.size():
		var at: Vector3 = stand + toward * (3.4 + .6 * (i % 2)) + side * (i - (kinds.size() - 1) / 2.0) * .95
		var foe = game.spawn_enemy(at, kinds[i])
		foe.global_position = Vector3(at.x, game.room.floor_height(at), at.z)
		foe.visual.rotation.y = atan2(toward.x, toward.z)
	game.update_camera(0.0, true)
	await frames(8)
	snap(out, "lineup")
	game.player.place(game.player.global_position + toward * 1.3 + side * .2)
	game.fps.pitch = -.2
	game.update_camera(0.0, true)
	await frames(6)
	snap(out, "close")
	# A struck foe flashes and shudders.
	for foe in game.enemies:
		foe.flash = .6
		foe.wobble = 1.0
		foe.show_flash(.016)
	await frames(3)
	snap(out, "struck")
	game.queue_free()
	await frames(3)
	quit(0)
