extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("exercise")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: "+label)
func exercise() -> void:
	var planner = load("res://scripts/dungeon/corridor_plan.gd")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game); current_scene = game
	game.set_process(false); game.set_physics_process(false)
	game.start_run("candle",31609250,false)
	game.paused = true
	var ui = game.ui
	var original := PackedVector2Array([Vector2(1,2),Vector2(3,4)])
	for i in 60:
		var drawn: PackedVector2Array = ui.partial_path(original,1.0)
		drawn[0] += Vector2(100,100)
		check(original[0] == Vector2(1,2),"redrawing finished ink does not move the cached path")
	var run = root.get_node("Run")
	var portal: String = run.rooms[run.current_room].portals[0]
	game.corridors.arm(portal)
	var transit = game.corridors
	check(is_instance_valid(transit.active),"real corridor is available for map traversal")
	var sample: Dictionary = planner.sample(transit.active.path,transit.handoff)
	game.player.position = Vector3(sample.at.x,0,sample.at.y)
	var before: Vector2 = ui.map_player_position()
	var focus_before: Vector2 = ui.map_room_focus()
	check(not ui.map_corridor_progress().is_empty(),"a player in the corridor uses passage coordinates")
	transit.rebase(transit.destination_room,transit.destination_offset)
	check(ui.map_player_position().distance_to(before) < .0001,"player marker stays continuous across room rebasing")
	check(ui.map_room_focus().distance_to(focus_before) < .0001,"map center stays continuous across room rebasing")
	var previous := -1.0
	for i in range(1,20):
		var along: float = planner.distance(transit.active.path,0,transit.active.path.size()-1)*float(i)/20
		var at: Vector2 = planner.sample(transit.active.path,along).at
		game.player.position = Vector3(at.x,0,at.y)+transit.active.position
		var state: Dictionary = ui.map_corridor_progress()
		if state.is_empty(): continue
		check(state.progress >= previous,"map motion progresses along every corridor bend")
		previous = state.progress
	game.end_run(false); game.reaper.flush(); game.queue_free()
	await process_frame
	print("MAP TRANSITION: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
