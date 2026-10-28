extends SceneTree
## Pooled effects: budgets per detail level, priority channels, recycling,
## rate limits, culling, cleanup across rooms, and gameplay independence
## from effects detail and frame-rate settings.
var checks = 0
var failures = 0
var run
var catalog
var settings
var game
var Pool
var FX

func _initialize() -> void:
	call_deferred("test_effects")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func test_effects() -> void:
	run = root.get_node("Run")
	catalog = root.get_node("Content")
	settings = root.get_node("Settings")
	Pool = load("res://scripts/effects/effects_pool.gd")
	FX = load("res://scripts/fx.gd")
	test_catalog()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game.start_run("candle", 71001, false)
	game.paused = true
	await test_budgets()
	await test_cleanup()
	await test_independence()
	settings.set_value("effects_detail", "balanced")
	game.end_run(false)
	game.queue_free()
	await process_frame
	print("EMBERKEEP EFFECTS TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func rejected(records: Array, label: String) -> void:
	catalog.errors = PackedStringArray()
	catalog.ingest("effects", records)
	var problems: PackedStringArray = catalog.errors
	problems.append_array(catalog.validate())
	check(not problems.is_empty(), "validator rejects " + label)
	catalog.load_catalog()

func test_catalog() -> void:
	for id in ["muzzle", "impact", "hit_spark", "death_puff", "dash_dust", "footstep", "pickup", "ward", "prop_dust", "chest_open",
		"paint_splash", "discovery_glint", "candle_wisp", "firefly", "shelf_dust", "brazier_spark"]:
		check(not catalog.record("effects", id).is_empty(), "effect recipe exists: " + id)
	var base = catalog.record("effects", "impact").duplicate(true)
	var odd = base.duplicate(true)
	odd.channel = "everything"
	rejected([odd], "unknown channels")
	var brief = base.duplicate(true)
	brief.lifetime = [0, .1]
	rejected([brief], "zero-length lifetimes")
	var silent = catalog.record("effects", "firefly").duplicate(true)
	silent.erase("rate")
	rejected([silent], "ambient emitters without a rate")
	check(catalog.errors.is_empty(), "catalog restores after negative checks")

func pool():
	return game.room.effects

func at_view() -> Vector3:
	return game.player.global_position + Vector3(0, .5, 0)

func test_budgets() -> void:
	for level in ["low", "balanced", "high"]:
		settings.set_value("effects_detail", level)
		game.enter_room(Vector3(0, 0, 2))
		await process_frame
		var effects = pool()
		check(effects == Pool.current, level + ": the room owns the current pool")
		var budget = settings.EFFECT_BUDGETS[level]
		check(game.room.ember_origins.size() + effects.budgets.ambient == budget.ambient, level + ": embers and emitters share one ambient budget")
		for i in 400:
			FX.play("dash_dust", at_view())
		check(effects.transient_count() <= budget.transient, level + ": transient particles stay within budget")
		var atmosphere = effects.channel_counts[effects.CHANNELS.atmosphere]
		check(atmosphere > 0, level + ": atmosphere fills spare capacity")
		for i in 400:
			FX.play("burst", at_view(), Color.WHITE)
		check(effects.transient_count() <= budget.transient, level + ": transient budget holds under important spam")
		check(effects.channel_counts[effects.CHANNELS.atmosphere] < atmosphere, level + ": important feedback displaces atmosphere first")
		check(FX.play("dash_dust", at_view()) == 0, level + ": atmosphere is dropped when only important effects remain")
		for frame in 300:
			effects._process(1.0 / 60.0)
		check(effects.channel_counts[effects.CHANNELS.ambient] <= effects.budgets.ambient, level + ": ambient emitters respect their share")
		check(effects.transient_count() == 0, level + ": transient particles expire")
		for i in 200:
			effects.mark(at_view(), Color.RED, {"size": .8, "lifetime": 5.0, "alpha": .5})
		check(effects.marks.size() <= budget.marks and effects.live_marks() <= budget.marks, level + ": floor marks are budgeted and recycled")
		for i in 50:
			FX.ring_burst(null, at_view(), Color.WHITE, 2.0)
			FX.beam(null, at_view(), at_view() + Vector3(2, 0, 0), Color.WHITE)
		check(effects.rings.size() <= effects.MAX_RINGS and effects.beams.size() <= effects.MAX_BEAMS, level + ": rings and beams reuse a fixed pool")
		check(effects.find_children("*", "Light3D", true, false).is_empty(), level + ": effects never add lights")
	# High fire rates share one emission per interval.
	var effects = pool()
	effects.last_emit.clear()
	var first = FX.play("muzzle", at_view(), Color.WHITE)
	var second = FX.play("muzzle", at_view(), Color.WHITE)
	check(first > 0 and second == 0, "muzzle flecks are rate-limited")
	# Effects outside the view are not spent at all.
	check(FX.play("burst", game.camera.global_position - game.camera.global_basis.z * -40.0, Color.WHITE) == 0, "effects behind the camera are culled")
	check(effects.particles.layers == 2 and effects.particles.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "particles stay on the unlit effects layer")

func count_nodes(node: Node) -> int:
	var total = 1
	for child in node.get_children():
		total += count_nodes(child)
	return total

func test_cleanup() -> void:
	settings.set_value("effects_detail", "high")
	var room_ids: Array = run.rooms.keys().filter(func(id): return not run.rooms[id].get("secret", false))
	for id in room_ids: run.rooms[id].cleared = true
	run.current_room = room_ids[0]
	game.enter_room(Vector3(0, 0, 2))
	await process_frame
	var previous = pool()
	for i in 200: FX.play("burst", at_view(), Color.WHITE)
	var baseline = -1
	for loop in 3:
		for id in room_ids.slice(0, 4):
			run.current_room = id
			game.enter_room(Vector3(0, 0, 2))
			for i in 120: FX.play("burst", at_view(), Color.WHITE)
			for i in 30: pool().mark(at_view(), Color.RED, {"size": .8, "lifetime": 5.0, "alpha": .5})
			await process_frame
			await process_frame
		run.current_room = room_ids[0]
		game.enter_room(Vector3(0, 0, 2))
		await process_frame
		await process_frame
		var nodes = count_nodes(root)
		if baseline < 0: baseline = nodes
		else: check(nodes == baseline, "room changes leave no orphan effects or node growth (%d vs %d)" % [nodes, baseline])
	check(not is_instance_valid(previous), "a replaced room's pool is freed with it")
	# Essential telegraphs are gameplay views, independent of the pool.
	settings.set_value("effects_detail", "low")
	game.enter_room(Vector3(0, 0, 2))
	for i in 400: FX.play("burst", at_view(), Color.WHITE)
	var charger = game.spawn_enemy(game.player.position + Vector3(4, 0, 0), "charger")
	charger.timer = 0
	charger.update_sim(1.0 / 60.0)
	check(is_instance_valid(charger.warning) and charger.warning.visible, "a charge telegraph appears even with the effects budget saturated")
	charger.queue_free()
	game.enemies.clear()

## Runs a fixed command stream and reports everything gameplay depends on.
func simulate(detail: String, fps: int) -> Dictionary:
	settings.set_value("effects_detail", detail)
	settings.set_value("fps_limit", fps)
	game.start_run("scatter", 71777, false)
	var combat = ""
	for id in run.rooms:
		if run.rooms[id].type == "combat" and run.rooms[id].cells.size() == 1:
			combat = id
			break
	run.current_room = combat
	game.enter_room(Vector3(0, 0, 4))
	game.paused = false
	run.hp = 100
	run.stats.max_hp = 100
	for frame in 600:
		game.ui.left_vector = Vector2(sin(frame * .05), cos(frame * .03)) * .5
		# Aim at the nearest foe: a deterministic, combat-resolving stream.
		var target = game.nearest_enemy(game.player.global_position, 99.0)
		if target:
			var to = (target.global_position - game.player.global_position).normalized()
			game.ui.right_vector = Vector2(to.dot(game.screen_right), to.dot(game.screen_down))
		else:
			game.ui.right_vector = Vector2.ZERO
		game._physics_process(1.0 / 60.0)
		if not run.active: break
	game.ui.left_vector = Vector2.ZERO
	game.ui.right_vector = Vector2.ZERO
	var foes = game.enemies.filter(func(e): return is_instance_valid(e) and e.alive).map(func(e): return [e.source, snappedf(e.hp, .001), e.position.snapped(Vector3.ONE * .001)])
	foes.sort()
	return {"player": game.player.position.snapped(Vector3.ONE * .001), "hp": run.hp, "coins": run.coins, "kills": run.kills,
		"rng": str(run.rng.state), "foes": foes, "drops": run.rooms[combat].get("pickups", []).size()}

func test_independence() -> void:
	var low = simulate("low", 30)
	var high = simulate("high", 120)
	var unlimited = simulate("balanced", 0)
	check(low.kills > 0, "the scripted fight actually resolves combat")
	check(low == high, "Low effects at 30 FPS and High at 120 FPS give identical gameplay")
	check(high == unlimited, "unlimited FPS changes nothing in the simulation")
	var state = str(run.rng.state)
	for i in 300: FX.play("burst", at_view(), Color.WHITE)
	check(str(run.rng.state) == state, "cosmetic randomness never consumes the gameplay RNG")
	settings.set_value("fps_limit", 60)
	await process_frame
