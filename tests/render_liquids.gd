extends SceneTree
## Opt-in native capture of floor liquids: wax, moss, ink, glass, fire, ice
## and water patches spreading in, then settled. Needs a display (or Xvfb)
## and EMBERKEEP_LIQUIDS_CAPTURE set to an output directory.
var game

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("go")

func frames(count: int) -> void:
	for i in count: await process_frame

func snap(out: String, label: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	if out != "": image.save_png(out.path_join("liquids_%s.png" % label))
	print("LIQUIDS CAPTURE %s" % label)

func go() -> void:
	var out := OS.get_environment("EMBERKEEP_LIQUIDS_CAPTURE")
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
	var feet: Vector3 = game.player.global_position
	game.fps.yaw = 0.0
	game.fps.pitch = -.55
	game.update_camera(0.0, true)
	await frames(4)
	var residue = game.residue
	var spots := {"wax": Vector3(-2.2, 0, -2.4), "moss": Vector3(0, 0, -2.6), "ink": Vector3(2.2, 0, -2.4),
		"glass": Vector3(-2.0, 0, -4.6), "water": Vector3(.4, 0, -4.8), "ice": Vector3(2.6, 0, -4.6)}
	for kind in spots:
		var at: Vector3 = feet + spots[kind]
		if kind == "ice":
			residue.add("water", at, 1.0, true)
			residue.freeze(at, 1.0)
		else:
			residue.add(kind, at, 1.0, true)
	residue.add("wax", feet + Vector3(-.4, 0, -6.6), 1.0, true)
	residue.update_sim(.3)
	residue.ignite(feet + Vector3(-.4, 0, -6.6), 1.0)
	residue.update_sim(.3)
	# Mid-spread, then settled.
	await frames(1)
	residue.animate(.12)
	snap(out, "spreading")
	for i in 20:
		residue.animate(.05)
		await frames(1)
	snap(out, "settled")
	# Close and low over the wax and moss, where a body shows its thickness.
	game.player.place(feet + Vector3(-.6, 0, -.2))
	game.fps.yaw = .35
	game.fps.pitch = -.32
	game.update_camera(0.0, true)
	await frames(4)
	snap(out, "close")
	game.queue_free()
	await frames(3)
	quit(0)
