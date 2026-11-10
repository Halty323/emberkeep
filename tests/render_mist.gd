extends SceneTree
## Opt-in native capture of the floor mist over standing water: the same
## spot seen level, looking down, and turned a little, so frames can be
## compared for fog that reshuffles or vanishes as the view changes. Needs a
## display (or Xvfb) and EMBERKEEP_MIST_CAPTURE set to an output directory.
var game

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("go")

func frames(count: int) -> void:
	for i in count: await process_frame

func snap(out: String, label: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	if out != "": image.save_png(out.path_join("mist_%s.png" % label))
	print("MIST CAPTURE %s" % label)

func go() -> void:
	var out := OS.get_environment("EMBERKEEP_MIST_CAPTURE")
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(2)
	game.start_run("candle", 29716392, false)
	await frames(30)
	var fight: Array = run.rooms.keys().filter(func(id): return run.rooms[id].type == "combat" and run.rooms[id].get("fps_terrain", {}).is_empty())
	run.current_room = fight[0]
	run.rooms[fight[0]].cleared = true
	game.enter_room(Vector3(0, 0, 4))
	await frames(4)
	game.residue.add("water", Vector3(0, 0, -1), 3.0, true)
	game.residue.add("water", Vector3(3, 0, 2), 2.0, true)
	await frames(30)
	game.set_physics_process(false)
	# A spot with nothing for six metres ahead (north), so the floor shows.
	var at := Vector3(0, 0, 4)
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	for candidate in [Vector3(0, 0, 4), Vector3(-4, 0, 4), Vector3(4, 0, 4), Vector3(-6, 0, 5), Vector3(6, 0, 5), Vector3(0, 0, 6), Vector3(-3, 0, 1), Vector3(3, 0, 1)]:
		if not game.room.geometry.contains(Vector2(candidate.x, candidate.z), 1.0) or game.room.blocked_at(Vector2(candidate.x, candidate.z)): continue
		var clear := true
		for side in [-1.0, 0.0, 1.0]:
			var from: Vector3 = candidate + Vector3(side * .8, 1.0, 0)
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -.6, -6.0), 0xFFFFFFFF)).is_empty(): clear = false
		if clear:
			at = candidate
			break
	at.y = game.room.floor_height(at)
	game.residue.add("water", at + Vector3(0, 0, -3.5), 2.4, true)
	await frames(10)
	for view in [["level", 0.0, -.12], ["down", 0.0, -.75], ["turned", .35, -.4], ["down_turned", -.3, -.9]]:
		game.player.place(at)
		game.fps.yaw = view[1]
		game.fps.pitch = view[2]
		game.update_camera(0.0, true)
		await frames(5)
		snap(out, view[0])
	game.queue_free()
	await frames(3)
	quit(0)
