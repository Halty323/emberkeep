extends SceneTree
## Opt-in native capture of breaking props crumbling and doors slamming shut.
## Needs a display (or Xvfb) and EMBERKEEP_PROPS_CAPTURE set to a directory.
var game

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("go")

func frames(count: int) -> void:
	for i in count: await process_frame

func snap(out: String, label: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	if out != "": image.save_png(out.path_join("props_%s.png" % label))
	print("PROPS CAPTURE %s" % label)

## Waits for `seconds` of game time, however slow the renderer's frames are.
func wait(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	var target := seconds / Engine.time_scale
	while (Time.get_ticks_msec() - start) / 1000.0 < target: await process_frame

func go() -> void:
	var out := OS.get_environment("EMBERKEEP_PROPS_CAPTURE")
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(2)
	game.start_run("candle", 7072, false)
	await frames(30)
	game.set_physics_process(false)
	for kind in ["crate", "barrel", "jar"]:
		var room_id := ""
		var record := {}
		for id in run.rooms:
			for prop in run.rooms[id].get("props", []):
				if prop.kind == kind and not prop.get("destroyed", false):
					room_id = id
					record = prop
					break
			if room_id != "": break
		if room_id == "":
			print("no %s found" % kind)
			continue
		run.current_room = room_id
		run.rooms[room_id].cleared = true
		game.enter_room(Vector3(0, 0, 2))
		await frames(20)
		var at := Vector3(float(record.position[0]), 0, float(record.position[1]))
		var stand := at + Vector3(0, 0, 2.6)
		game.player.place(Vector3(stand.x, game.room.floor_height(stand), stand.z))
		game.fps.yaw = 0.0
		game.fps.pitch = -.35
		game.update_camera(0.0, true)
		await frames(6)
		Engine.time_scale = .1
		game.destroy_prop(room_id, record, true)
		await wait(.07)
		snap(out, kind + "_a")
		await wait(.25)
		snap(out, kind + "_b")
		await wait(.6)
		snap(out, kind + "_c")
		Engine.time_scale = 1.0
	# Doors: stand in a room facing a doorway, open, then slam.
	var gates: Array = game.room.gates
	if not gates.is_empty():
		var gate: Node3D = gates[0]
		var facing := gate.global_basis.z.normalized()
		var stand := gate.global_position + facing * 3.5
		if not game.room.geometry.contains(Vector2(stand.x, stand.z), .3): stand = gate.global_position - facing * 3.5
		game.player.place(Vector3(stand.x, game.room.floor_height(stand), stand.z))
		var look := gate.global_position - stand
		game.fps.yaw = atan2(-look.x, -look.z)
		game.fps.pitch = -.05
		game.room.set_open(true)
		game.update_camera(0.0, true)
		await frames(6)
		Engine.time_scale = .1
		game.room.set_open(false)
		await wait(.08)
		snap(out, "door_swing")
		await wait(.08)
		snap(out, "door_bounce")
		await wait(.4)
		snap(out, "door_shut")
		Engine.time_scale = 1.0
	game.queue_free()
	await frames(3)
	quit(0)
