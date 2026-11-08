extends SceneTree
## Opt-in native capture of a whole-floor two-storey room: the ground floor
## under its slab, the staircase, and the upper floor. Needs a display (or
## Xvfb) and EMBERKEEP_STOREYS_CAPTURE set to an output directory.
var game

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("go")

func frames(count: int) -> void:
	for i in count: await process_frame

func snap(out: String, label: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	if out != "": image.save_png(out.path_join("storeys_%s.png" % label))
	print("STOREYS CAPTURE %s" % label)

func look(from: Vector3, yaw: float, pitch: float) -> void:
	game.player.place(from)
	game.player.velocity = Vector3.ZERO
	game.fps.yaw = yaw
	game.fps.pitch = pitch
	game.update_camera(0.0, true)

func go() -> void:
	var out := OS.get_environment("EMBERKEEP_STOREYS_CAPTURE")
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(2)
	game.start_run("candle", 15877521, false)
	await frames(20)
	var id := ""
	for key in run.rooms:
		if run.rooms[key].get("fps_terrain", {}).get("kind", "") == "floor": id = key
	if id == "":
		print("STOREYS no whole-floor room"); quit(1); return
	run.current_room = id
	run.rooms[id].cleared = true
	game.enter_room(Vector3(0, 0, 2))
	await frames(30)
	game.set_physics_process(false)
	var loft = game.room.terrain.loft
	var flight: Rect2 = loft.stairs
	var foot := Vector3(flight.get_center().x, 0, flight.end.y + 4.5)
	look(foot, 0.0, .12)
	await frames(6)
	snap(out, "stairs_from_below")
	look(Vector3(flight.get_center().x + 6.0, 0, flight.end.y + 1.0), PI * .5, .05)
	await frames(6)
	snap(out, "ground_floor")
	var up: Vector3 = loft.upper_spot(0)
	look(up + Vector3(0, 0, 3.0), 0.0, -.05)
	await frames(6)
	snap(out, "upper_floor")
	look(Vector3(flight.get_center().x, loft.RISE, flight.position.y - 1.0), PI, -.45)
	await frames(6)
	snap(out, "stairwell_from_above")
	game.queue_free()
	await frames(3)
	quit(0)
