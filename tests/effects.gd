extends SceneTree
## Phase 5 gate: every effect obeys the room budgets and cleans up with its
## room, essential cues survive saturation, the local shadow budget stays at
## one, and particle detail or frame rate never changes gameplay.
var checks = 0
var failures = 0
var run
var game
var settings
var Pool
var Fx

func _initialize() -> void:
	call_deferred("test_effects")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func find(want: Callable) -> Array:
	run.generator = run.GENERATOR_V2
	for seed_value in range(1, 300):
		run.seed_value = seed_value
		run.floor_number = 1
		run.generate_floor()
		for key in run.rooms:
			if want.call(key, run.rooms[key]): return [seed_value, key]
	return []

func enter(seed_value: int, key: String, clear := true) -> void:
	game.start_run("candle", seed_value, false)
	await process_frame
	run.current_room = key
	if clear: run.rooms[key].cleared = true
	game.paused = false
	game.enter_room(Vector3.ZERO)
	await process_frame

func test_budgets(found: Array) -> void:
	for level in ["low", "balanced", "high"]:
		settings.values.effects_detail = level
		await enter(found[0], found[1])
		var pool = game.room.effects
		var budget: Dictionary = Pool.BUDGETS[level]
		check(Fx.active == pool, level + ": the facade drives the current room's pool")
		check(pool.ambient.size() == budget.ambient and pool.ambient_mesh.multimesh.instance_count == budget.ambient, level + ": ambient fills exactly its budget")
		check(pool.ambient.any(func(a): return a.kind == "wisp") and pool.ambient.any(func(a): return a.kind == "ember"), level + ": ambient mixes candle wisps and embers")
		var children: int = pool.get_child_count()
		for i in 400:
			Fx.burst(null, Vector3(0, .5, 0), Color.ORANGE, 8, 1.0)
			Fx.ring_burst(null, Vector3.ZERO, Color.WHITE, 2.0)
			Fx.beam(null, Vector3.ZERO, Vector3(2, 1, 0), Color.WHITE)
			Fx.floor_mark(Vector3(randf_range(-6, 6), 0, randf_range(-4, 4)), Color(0, 0, 0, .5), .4)
		pool._process(1.0 / 60.0)
		var counts: Dictionary = pool.active_counts()
		check(counts.transient <= budget.transient, level + ": transient particles stay within budget (%d)" % counts.transient)
		check(counts.marks <= budget.marks, level + ": floor marks stay within budget")
		check(counts.rings <= Pool.RING_POOL and counts.beams <= Pool.BEAM_POOL, level + ": rings and beams reuse a fixed pool")
		check(pool.get_child_count() == children, level + ": spamming effects allocates no nodes")
		# Saturated with feedback, atmosphere is dropped but essential cues still land.
		var dropped: int = pool.dropped
		check(not pool.emit(Vector3.ZERO, Vector3.ZERO, Color.WHITE, .1, 1.0, Pool.Priority.ATMOSPHERE), level + ": atmosphere is the first to go when full")
		check(pool.dropped == dropped + 1, level + ": dropped atmosphere is counted")
		check(pool.emit(Vector3.ZERO, Vector3.ZERO, Color.RED, .1, 1.0, Pool.Priority.ESSENTIAL), level + ": essential cues always find room")
		check(pool.transient_count <= budget.transient, level + ": replacement never grows the batch")
		# Effects expire.
		for i in 120: pool._process(1.0 / 30.0)
		counts = pool.active_counts()
		check(counts.transient == 0 and counts.rings == 0 and counts.beams == 0, level + ": transient effects expire")
	settings.values.effects_detail = "balanced"

func test_limits(found: Array) -> void:
	await enter(found[0], found[1])
	var pool = game.room.effects
	for i in 100:
		Fx.muzzle(Vector3(0, .6, 0), Vector3.RIGHT, Color.WHITE)
	check(pool.transient_count <= 8, "muzzle flecks are rate-limited (%d)" % pool.transient_count)
	for i in 100:
		Fx.impact(Vector3(0, .6, 0), Color.WHITE)
	check(pool.transient_count <= 8 + 8 * 2 * 2, "impact chips are rate-limited")
	check(not pool.mark(Vector3(500, 0, 500), Color.BLACK, .5), "floor marks outside the footprint are refused")
	check(pool.mark(Vector3(0, 0, 0), Color.BLACK, .5), "floor marks inside the footprint are kept")
	var time: float = pool.time
	game.paused = true
	pool._process(.5)
	check(is_equal_approx(pool.time, time), "effects freeze while the game is paused")
	game.paused = false

func test_cleanup(found: Array) -> void:
	await enter(found[0], found[1])
	var old_pool = game.room.effects
	var counts: Array = []
	for round in 8:
		for i in 30: Fx.burst(null, Vector3.ZERO, Color.WHITE, 6, 1.0)
		game.enter_room(Vector3.ZERO)
		await process_frame
		await process_frame
		counts.append(get_node_count())
	check(not is_instance_valid(old_pool), "the old room's pool is freed with its room")
	check(Fx.active == game.room.effects, "the facade follows the new room")
	check(counts[7] <= counts[2], "room replacement leaves no orphan effects (%s)" % str(counts))

func test_shadow_budget(found: Array) -> void:
	await enter(found[0], found[1])
	var shadowed := 0
	var local := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Light3D and node.visible:
			if not node is DirectionalLight3D:
				local += 1
				if node.shadow_enabled: shadowed += 1
	check(shadowed <= 1, "at most one local shadowed light in the largest furnished room (%d)" % shadowed)
	check(local <= game.room.LIGHT_POOL + 1 + 2, "furniture and effects add no per-object lights (%d)" % local)

func snapshot() -> Dictionary:
	var foes: Array = []
	for enemy in game.enemies:
		if is_instance_valid(enemy) and enemy.alive:
			# Positions are left out: the physics solver's body-body contact
			# order jitters them run to run even with identical settings.
			foes.append([enemy.source, snappedf(enemy.hp, .0001)])
	return {"player": game.player.position.snappedf(.0001), "hp": run.hp, "coins": run.coins, "kills": run.kills,
		"rng": run.rng.state, "foes": foes, "shots": game.shots.size(), "drops": run.rooms[run.current_room].get("pickups", []).size()}

## One fixed command stream: move in a square while firing in a circle, on
## real physics frames. Cosmetic updates run at the given render rate.
func scripted_fight(found: Array, detail: String, render_dt: float) -> Dictionary:
	settings.values.effects_detail = detail
	await enter(found[0], found[1], false)
	await physics_frame
	game.ui.touch_used = true
	game.set_physics_process(true)
	var physics_dt := 1.0 / 60.0
	var render_clock := 0.0
	for tick in 360:
		var phase := tick / 90
		game.ui.left_vector = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP][phase % 4] * .8
		game.ui.right_vector = Vector2.RIGHT.rotated(tick * .07)
		await physics_frame
		render_clock += physics_dt
		while render_clock >= render_dt:
			render_clock -= render_dt
			game._process(render_dt)
			if is_instance_valid(game.room): game.room.effects._process(render_dt)
		if not run.active: break
	game.set_physics_process(false)
	game.ui.left_vector = Vector2.ZERO
	game.ui.right_vector = Vector2.ZERO
	return snapshot()

func test_determinism(found: Array) -> void:
	var low: Dictionary = await scripted_fight(found, "low", 1.0 / 30.0)
	var high: Dictionary = await scripted_fight(found, "high", 1.0 / 120.0)
	var balanced: Dictionary = await scripted_fight(found, "balanced", 1.0 / 60.0)
	check(low.shots > 0 and low.foes.any(func(f): return f[1] < 20.0), "the scripted fight actually fights")
	check(JSON.stringify(low) == JSON.stringify(high), "Low particles at 30 FPS and High at 120 FPS give the same gameplay")
	check(JSON.stringify(low) == JSON.stringify(balanced), "particle detail never changes gameplay")
	settings.values.effects_detail = "balanced"

func test_effects() -> void:
	run = root.get_node("Run")
	settings = root.get_node("Settings")
	Pool = load("res://scripts/fx/effect_pool.gd")
	Fx = load("res://scripts/fx.gd")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	var grand: Array = find(func(_k, r): return r.template == "hall_grand" and r.props.size() > 8)
	check(not grand.is_empty(), "a seed has a furnished grand hall")
	if not grand.is_empty():
		await test_budgets(grand)
		await test_limits(grand)
		await test_cleanup(grand)
		await test_shadow_budget(grand)
	var fight: Array = find(func(_k, r): return r.type == "combat" and r.cells.size() == 1)
	await test_determinism(fight)
	game.end_run(false)
	game.queue_free()
	root.get_node("Audio").music_player.stop()
	await process_frame
	await process_frame
	print("EMBERKEEP EFFECTS TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
