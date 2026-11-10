extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("exercise")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)
func exercise() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false); game.set_physics_process(false)
	var run = root.get_node("Run")
	var planner = load("res://scripts/dungeon/upper_furnishings.gd")
	for seed_value in [31609250, 72913504, 18523427, 64872557]:
		game.start_run("candle", seed_value, false)
		for record in run.rooms.values():
			if record.get("fps_terrain", {}).get("kind", "") != "floor": continue
			run.current_room = record.id
			game.enter_room(Vector3.ZERO)
			game.room.resume_build(true)
			var room = game.room
			var upper: Array = record.props.filter(func(p): return float(p.get("height", 0)) > 3)
			print("UPPER DENSITY ", seed_value, " cells=", room.geometry.cells.size(), " props=", upper.size())
			check(upper.size() >= 8 * room.geometry.cells.size(), "upstairs has distributed furniture across the footprint")
			var kinds := {}
			for p in upper:
				kinds[p.kind] = true
				check(room.props.has(p.id), "upstairs props use the normal runtime registry")
				check(is_equal_approx(room.props[p.id].node.position.y, 3.2), "upstairs furniture is grounded on its own floor")
				check(not room.navigation_blockers(0).has(p.id), "upper furniture does not obstruct ground-floor AI")
			check(kinds.size() >= 4, "upstairs has varied recipes")
			check(room.geometry.terrain == room.terrain, "streamed rooms retain their elevation queries")
			var pickup_count: int = record.get("pickups", []).size()
			for p in upper:
				if room.props[p.id].definition.has("breakable"): game.destroy_prop(record.id, p, false)
			for drop in record.get("pickups", []).slice(pickup_count):
				check(is_equal_approx(float(drop.get("height", 0)), 3.2), "upstairs container loot retains its saved elevation")
			var before := JSON.stringify(record.props)
			planner.resolve(room, record.props)
			check(JSON.stringify(record.props) == before, "rebuilding does not duplicate or reroll saved furniture")
			for p in room.candle_points:
				var level := 3.2 if p.y > 3.2 else 0.0
				check(not room.navigation_blockers(level).values().any(func(area): return area.grow(.3).has_point(Vector2(p.x, p.z))), "wall candles stay outside furniture footprints")
			await process_frame
	game.end_run(false)
	game.reaper.flush()
	game.queue_free()
	await process_frame
	print("UPPER FURNISHINGS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
