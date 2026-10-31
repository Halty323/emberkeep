extends SceneTree
## Headless, fixed-clock workload and resource bounds. Timings are CPU
## samples, not phone frame-rate or GPU performance claims.
var checks := 0
var failures := 0
var game
var run
var settings
var catalog
var timings: Array = []
var rebuild_nodes: Array = []
var peak_shots := 0

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("exercise")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + description)

func settle() -> void:
	for i in 3: await process_frame

func clear_fight() -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy):
			enemy.alive = false
			enemy.queue_free()
	game.enemies.clear()
	for shot in game.shots:
		if is_instance_valid(shot): shot.queue_free()
	game.shots.clear()

func tick() -> void:
	var before = Time.get_ticks_usec()
	game._physics_process(1.0 / 60.0)
	# Simulate presentation on the same clock; dead shots deliberately retain
	# a short fade after leaving the active gameplay list.
	for child in game.scene_root.get_children():
		if child.has_method("shine"): child._process(1.0 / 60.0)
	game.room.effects._process(1.0 / 60.0)
	timings.append((Time.get_ticks_usec() - before) / 1000.0)
	peak_shots = maxi(peak_shots, game.shots.size())

func exercise() -> void:
	run = root.get_node("Run")
	settings = root.get_node("Settings")
	catalog = root.get_node("Content")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	settings.set_value("effects_detail", "high")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.set_process(false)
	game.start_run("candle", 18523427, false)
	game.paused = true
	await settle()
	check(game.first_person, "stress workload uses the real first-person mode")
	await test_search_throttle()
	await test_projectile_resources()
	await test_occluded_lanterns()
	await test_boss_workloads()
	await test_saturated_build()
	await test_elevated_effects()
	await test_rebuild_bounds()
	game.pause_game()
	game.queue_free()
	await settle()
	timings.sort()
	print("FIRST PERSON CPU WORKLOAD: " + JSON.stringify({"samples": timings.size(), "median_ms": timings[timings.size() / 2], "p95_ms": timings[int(timings.size() * .95)], "peak_active_shots": peak_shots, "rebuild_nodes": rebuild_nodes}))
	print("EMBERKEEP FIRST PERSON STRESS RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_search_throttle() -> void:
	clear_fight()
	await settle()
	var geometry_script = load("res://scripts/dungeon/room_geometry.gd")
	var nav_script = load("res://scripts/dungeon/room_navigation.gd")
	var geometry = geometry_script.new([Vector2i.ZERO])
	# A target with no admissible endpoint used to trigger a full search on
	# every tick because an empty path bypassed the enemy's cooldown.
	var navigation = nav_script.new(geometry, .5, {"sealed": Rect2(-10, -8, 20, 16)})
	game.room.navigators[.5] = navigation
	var enemy = game.spawn_enemy(Vector3(-3, 0, 0), "mote")
	game.player.place(Vector3(3, 0, 0))
	for i in 180: enemy.steer_toward(game.player.position, 1.0 / 60.0)
	check(enemy.path_queries > 0 and enemy.path_queries <= 7, "unreachable path searches obey the staggered cooldown")
	var old_queries: int = enemy.path_queries
	enemy.place(Vector3(-2, 0, 0))
	enemy.steer_toward(game.player.position, 1.0 / 60.0)
	check(enemy.path_queries == old_queries + 1, "teleporting an enemy invalidates its cached path")
	game.room.navigators.clear()

func test_projectile_resources() -> void:
	clear_fight()
	await settle()
	var cores: Dictionary = {}
	var quads: Dictionary = {}
	var pools: Dictionary = {}
	var accepted = 0
	for i in 150:
		var shot = game.spawn_shot(Vector3(0, 1.0, 0), Vector3.FORWARD, 1, 10, {"size": .5 + float(i % 8) * .25}, Color("ffd18c"), true)
		if shot == null: continue
		accepted += 1
		cores[shot.core.mesh.get_instance_id()] = true
		quads[shot.glow.mesh.get_instance_id()] = true
		if shot.streak: quads[shot.streak.mesh.get_instance_id()] = true
		if shot.splat: pools[shot.splat.mesh.get_instance_id()] = true
	check(accepted == 150, "the friendly projectile budget accepts its complete volley")
	check(cores.size() == 1 and quads.size() == 1 and pools.size() <= 1, "all projectile sizes share at most three immutable mesh resources")
	check(game.spawn_shot(Vector3.ZERO, Vector3.FORWARD, 1, 10, {}, Color.WHITE, true) == null, "friendly fire preserves the hostile reserve")
	for i in 50: game.spawn_shot(Vector3(2, 1, 0), Vector3.BACK, 1, 5, {}, Color.RED, false)
	check(game.shots.size() == game.MAX_SHOTS, "a full mixed volley is bounded by the global cap")
	check(game.spawn_shot(Vector3.ZERO, Vector3.FORWARD, 1, 10, {}, Color.WHITE, false) == null, "hostile spawning also respects the global cap")
	clear_fight()
	await settle()
	var policy_script = load("res://scripts/graphics/render_policy.gd")
	policy_script.device_override = policy_script.for_device("Android", "Imagination", "PowerVR", "gl_compatibility")
	var mobile_shot = game.spawn_shot(Vector3(0, 1, 0), Vector3.FORWARD, 1, 10, {}, Color.WHITE, true)
	check(mobile_shot.streak != null and mobile_shot.splat == null, "PowerVR retains projectile ribbons without per-pellet floor planes")
	policy_script.device_override = {}

func test_boss_workloads() -> void:
	for theme in catalog.families.floors:
		game.start_run("candle", 61003, false)
		run.floor_plan = [theme.id, theme.id, theme.id, theme.id, theme.id]
		run.floor_twists = ["", "", "", "", ""]
		run.floor_number = 3
		run.generate_floor()
		for id in run.rooms:
			if run.rooms[id].type != "boss": continue
			run.current_room = id
			game.enter_room(Vector3(0, 0, 4))
			break
		game.paused = false
		game.player.invulnerability = 999
		run.stats.max_hp = 999
		run.hp = 999
		var boss = game.enemies.filter(func(enemy): return enemy.boss)[0]
		# Exercise later-phase attacks, including summons and changing arenas.
		boss.hp = boss.max_hp * .3
		for frame in 720:
			if frame % 18 == 0:
				var aim: Vector3 = (boss.position + Vector3.UP - (game.player.position + Vector3.UP * 1.5)).normalized()
				game.spawn_shot(game.player.position + Vector3.UP * 1.5, aim, .01, 20, {"bounce": 2, "pierce": 2}, Color("ffd18c"), true)
			tick()
			if frame % 60 == 0: await process_frame
		check(boss.alive and boss.position.is_finite(), "twelve-second late-phase workload: " + theme.boss.kind)
		check(game.player.position.is_finite() and run.hp > 0, "player state stays valid against " + theme.boss.kind)
		check(game.shots.size() <= game.MAX_SHOTS, "projectile bound holds against " + theme.boss.kind)
		check(game.room.effects.count <= game.room.effects.budgets.transient + game.room.effects.budgets.ambient, "particle bound holds against " + theme.boss.kind)
		await settle()

func test_rebuild_bounds() -> void:
	game.start_run("candle", 18523427, false)
	game.paused = true
	var id: String = run.current_room
	for room_id in run.rooms:
		if run.rooms[room_id].type == "combat" and run.rooms[room_id].cells.size() > 1:
			id = room_id
			break
	run.current_room = id
	for visit in 12:
		game.enter_room(Vector3(0, 0, 2))
		await settle()
		rebuild_nodes.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	check(rebuild_nodes.max() - rebuild_nodes.min() <= 12, "identical room rebuilds do not accumulate nodes")

func test_saturated_build() -> void:
	game.start_run("candle", 18523427, false)
	for id in run.rooms:
		if run.rooms[id].type == "combat" and run.rooms[id].cells.size() > 1:
			run.current_room = id
			game.enter_room(Vector3(0, 0, 2))
			break
	clear_fight()
	run.grant_all_relics()
	game.player.refresh_orbitals()
	run.stats.max_hp = 999
	run.hp = 999
	game.player.invulnerability = 999
	var positions: Array = []
	for i in 14:
		var point = game.room.geometry.random_point(run.rng, 1.5)
		var enemy = game.spawn_enemy(Vector3(point.x, 0, point.y), ["mote", "spitter", "charger", "brute"][i % 4])
		enemy.hp = 1e9
		enemy.max_hp = 1e9
		positions.append(enemy.position)
	game.paused = false
	var peak = 0
	for frame in 720:
		var enemy = game.nearest_enemy(game.player.position, 80)
		if enemy:
			game.player.aim_direction = (enemy.position + Vector3.UP - game.player.shot_origin()).normalized()
			if game.player.fire_cooldown <= 0: game.player.fire()
		tick()
		peak = maxi(peak, game.shots.size())
		if frame % 4 == 0: await process_frame
	check(run.inventory.size() == catalog.items.size(), "saturated build carries every relic")
	check(peak > 20 and peak <= game.MAX_SHOTS, "all-relics fire reaches a meaningful workload and respects the shot cap")
	check(game.player.position.is_finite() and run.hp > 0, "all-relics combat keeps valid player state")
	check(game.room.effects.count <= game.room.effects.budgets.transient + game.room.effects.budgets.ambient, "all-relics combat respects shared particle capacity")
	print("FIRST PERSON SATURATED BUILD: peak shots=", peak, " room nodes=", game.scene_root.get_child_count())

func test_elevated_effects() -> void:
	game.start_run("candle", 18523427, false)
	game.paused = true
	var gallery = false
	for id in run.rooms:
		if run.rooms[id].type != "combat" or run.rooms[id].cells.size() < 2: continue
		run.current_room = id
		game.enter_room(Vector3(0, 0, 2))
		if game.room.terrain and game.room.terrain.ledge.has_area():
			gallery = true
			break
	check(gallery, "regression seed supplies a raised-effects test gallery")
	if not gallery: return
	clear_fight()
	var point: Vector2 = game.room.terrain.ledge.get_center()
	var at = Vector3(point.x, game.room.terrain.height(point), point.y)
	game.player.place(at)
	var brute = game.spawn_enemy(at + Vector3(.5, 0, 0), "brute")
	var mote = game.spawn_enemy(at + Vector3(.9, 0, 0), "mote")
	brute.throw_mote(Vector3.RIGHT, 1)
	check(not mote.thrown.is_empty() and mote.thrown.to.y > .8, "thrown motes land on the gallery instead of inside its solid deck")
	game.room.effects.mark(at, Color.RED, {"size": .8, "lifetime": 5.0, "alpha": .5})
	var mark = game.room.effects.marks[-1]
	check(mark.node.position.y > at.y, "paint and impact marks rest above the raised floor")

func test_occluded_lanterns() -> void:
	clear_fight()
	game.player.place(Vector3(3, 0, 2))
	for index in game.room.lanterns.size(): game.room.set_lantern(index, false)
	game.room.lanterns[0].at = Vector3(0, 0, -.8)
	var geo = load("res://scripts/geo.gd")
	var wall = geo.collider(game.scene_root, Vector3(0, 1, 0), Vector3(3, 2.5, .2))
	for i in 3: await physics_frame
	var shot = game.spawn_shot(Vector3(0, 1.6, 1), Vector3.FORWARD, 1, 100, {}, Color.WHITE, true)
	shot.update_sim(.018)
	check(not game.room.lanterns[0].burning, "a lantern behind nearer cover cannot be relit through it")
	check(absf(shot.global_position.z - .1) < .02, "wall impact feedback occurs at the actual swept surface")
	wall.queue_free()
	for i in 3: await physics_frame
	var clear_shot = game.spawn_shot(Vector3(0, 1.6, 1), Vector3.FORWARD, 1, 100, {}, Color.WHITE, true)
	clear_shot.update_sim(.035)
	check(game.room.lanterns[0].burning, "fast projectiles relight glass crossed between their endpoints")
