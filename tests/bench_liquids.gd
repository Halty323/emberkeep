extends SceneTree
## Opt-in timing of the floor liquids while a lot is spilt at once: a room
## flooded patch by patch, with wax and fire spreading over it. Prints the
## average and worst time a frame spends in the residue's sim and animation.
func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("go")

func go() -> void:
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in 3: await process_frame
	game.start_run("candle", 7072, false)
	for i in 20: await process_frame
	var big := ""
	for id in run.rooms:
		if run.rooms[id].get("fps_terrain", {}).is_empty() and (big == "" or run.rooms[id].cells.size() > run.rooms[big].cells.size()): big = id
	run.current_room = big
	run.rooms[big].cleared = true
	game.enter_room(Vector3(0, 0, 2))
	for i in 10: await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	var residue = game.residue
	residue.animate_headless = true
	residue.clock = 1.0
	var gen := RandomNumberGenerator.new()
	gen.seed = 99
	var cells: Array = game.room.geometry.cells
	var total := 0.0
	var worst := 0.0
	var frames := 240
	var parts := [0.0, 0.0, 0.0]
	for frame in frames:
		var start := Time.get_ticks_usec()
		# Two spills a frame for the first three seconds, then it settles.
		if frame < 180:
			for spill in 2:
				var center: Vector2 = load("res://scripts/dungeon/room_geometry.gd").cell_center(cells[gen.randi() % cells.size()])
				var at := Vector3(center.x + gen.randf_range(-7, 7), 0, center.y + gen.randf_range(-5, 5))
				residue.add(["water", "water", "wax", "ink"][gen.randi() % 4], at, gen.randf_range(1.0, 2.6))
			if frame % 20 == 10: residue.ignite(Vector3(gen.randf_range(-6, 6), 0, gen.randf_range(-4, 4)), 3.0, true)
		var a := Time.get_ticks_usec()
		residue.update_sim(1.0 / 60.0)
		var b := Time.get_ticks_usec()
		residue.animate(1.0 / 60.0)
		var c := Time.get_ticks_usec()
		parts[0] += (a - start) / 1000.0
		parts[1] += (b - a) / 1000.0
		parts[2] += (c - b) / 1000.0
		var took := (Time.get_ticks_usec() - start) / 1000.0
		total += took
		worst = maxf(worst, took)
	print("LIQUID BENCH: %d cells, %d tiles, average %.2f ms a frame, worst %.2f ms" % [cells.size(), residue.tiles.size(), total / frames, worst])
	print("LIQUID BENCH PARTS: spilling %.2f, sim %.2f, drawing %.2f ms a frame" % [parts[0] / frames, parts[1] / frames, parts[2] / frames])
	game.queue_free()
	await process_frame
	quit(0)
