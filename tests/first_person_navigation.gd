extends SceneTree
## Exercise physical motion through real furnished rooms, not just A* reachability.
var game
var run
var checks := 0
var failures := 0
var terrain_rooms := 0
var extra_motion_checked := false

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("exercise")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func step(motion: Vector2, count: int) -> void:
	for frame in count:
		await physics_frame
		game.player.update_sim(1.0 / 60, motion, game.fps.forward(), false)

func place_player(at: Vector3) -> void:
	game.player.place(at)
	game.player.velocity = Vector3.ZERO
	game.player.push = Vector3.ZERO
	game.player.dash_time = 0
	game.player.dash_cooldown = 0
	game.fps.jump_buffer = 0
	game.fps.yaw = 0

func exercise() -> void:
	run = root.get_node("Run")
	root.get_node("Settings").set_value("sound", false)
	root.get_node("Settings").set_value("music", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	for seed_value in [18523427, 64217, 81031]:
		game.start_run("candle", seed_value, false)
		for id in run.rooms:
			if run.rooms[id].type != "combat" or run.rooms[id].cells.size() < 2: continue
			run.current_room = id
			game.enter_room(Vector3(0, 0, 2))
			game.paused = true
			for enemy in game.enemies: enemy.queue_free()
			game.enemies.clear()
			await step(Vector2.ZERO, 2)
			var terrain = game.room.terrain
			if not terrain or not terrain.ramp.has_area(): continue
			terrain_rooms += 1
			var x: float = terrain.ramp.get_center().x
			place_player(Vector3(x, .05, terrain.ramp.end.y + .6))
			await step(Vector2.ZERO, 5)
			await step(Vector2(0, -1), 66)
			check(game.player.position.z < terrain.ramp.position.y + .1 and game.player.position.y > 1.05,
				"walk up physical ramp seed %d room %s" % [seed_value, id])
			await step(Vector2(0, 1), 68)
			check(game.player.position.z > terrain.ramp.end.y and game.player.position.y < .12,
				"walk down physical ramp seed %d room %s" % [seed_value, id])
			var nav = game.room.navigation(.5)
			var deck: Vector2 = terrain.ledge.get_center()
			var bottom = Vector2(x, terrain.ramp.end.y + .6)
			check(nav.reachable(bottom, deck), "enemy-sized route reaches gallery seed %d room %s" % [seed_value, id])
			check(not nav.line_clear(deck, deck + Vector2.LEFT * 3), "navigation rejects gallery cliff shortcuts seed %d room %s" % [seed_value, id])
			check(terrain.valid_blueprint(run.rooms[id].fps_terrain, game.room.geometry), "generated terrain blueprint is valid")
			if not extra_motion_checked:
				extra_motion_checked = true
				await check_jump_dash_and_recovery(terrain)
				await check_enemy_climb(terrain)
				check_saved_layout_validation(terrain)
			await process_frame
	check(terrain_rooms >= 6, "real multi-cell ramp coverage includes the reported seed and independent layouts")
	await check_more_seeded_rooms()
	game.queue_free()
	await process_frame
	print("FIRST PERSON NAVIGATION: %d checks, %d failures; %d physical ramp rooms" % [checks, failures, terrain_rooms])
	quit(0 if failures == 0 else 1)

func check_jump_dash_and_recovery(terrain) -> void:
	var middle: Vector2 = terrain.ramp.get_center()
	var floor_y: float = terrain.height(middle)
	place_player(Vector3(middle.x, floor_y + .04, middle.y))
	await step(Vector2.ZERO, 12)
	game.fps.jump_buffer = .14
	await step(Vector2.ZERO, 14)
	check(game.player.position.y > floor_y + .6, "jump leaves the physical slope")
	await step(Vector2.ZERO, 55)
	check(absf(game.player.position.y - floor_y) < .12, "jump lands stably on the physical slope")
	place_player(Vector3(middle.x, .04, terrain.ramp.end.y + .6))
	await step(Vector2.ZERO, 6)
	game.player.last_move = Vector3.FORWARD
	game.player.dash()
	await step(Vector2(0, -1), 50)
	check(game.player.position.y > 1.05 and game.player.position.z < terrain.ramp.position.y,
		"dash climbs through the ramp-to-deck seam")
	check(Vector2(game.player.velocity.x, game.player.velocity.z).length() <= game.player.RUN_SPEED * float(run.stats.speed) + .15,
		"dash returns to running speed without a long residual slide")
	var deck: Vector2 = terrain.ledge.get_center()
	place_player(Vector3(deck.x, 1.24, deck.y))
	await step(Vector2.ZERO, 6)
	game.player.last_move = Vector3.BACK
	game.player.dash()
	await step(Vector2(0, 1), 50)
	check(game.player.position.y < .13 and game.player.position.z > terrain.ramp.end.y,
		"dash descends through the deck-to-ramp seam")
	place_player(Vector3(middle.x, .04, terrain.ramp.end.y + .6))
	game.fps.yaw = PI
	await step(Vector2.ZERO, 6)
	await step(Vector2(0, 1), 66)
	check(game.player.position.y > 1.05, "backpedalling climbs the slope with opposite camera yaw")
	place_player(Vector3(deck.x, .05, deck.y))
	await step(Vector2.ZERO, 16)
	check(game.player.position.y > 1.05 and Vector2(game.player.position.x, game.player.position.z).distance_to(deck) < .2,
		"old under-gallery positions recover vertically without crossing a wall")

func check_enemy_climb(terrain) -> void:
	var deck: Vector2 = terrain.ledge.get_center()
	place_player(Vector3(deck.x, 1.24, deck.y))
	game.player.invulnerability = 100
	var at = Vector3(terrain.ramp.get_center().x, .02, terrain.ramp.end.y + .6)
	var enemy = game.spawn_enemy(at, "mote")
	enemy.place(at)
	enemy.timer = 1000
	for frame in 260:
		await physics_frame
		enemy.update_sim(1.0 / 60)
	check(enemy.position.y > .95 and enemy.position.z < terrain.ramp.position.y + .5,
		"a real enemy pursues the player up the collision slope")
	enemy.queue_free()
	game.enemies.clear()
	await process_frame

func check_saved_layout_validation(terrain) -> void:
	var record: Dictionary = run.rooms[run.current_room]
	var valid: Dictionary = record.fps_terrain.duplicate(true)
	var geometry = game.room.geometry
	for malformed in [null, "truncated", [], {"version": 9}, {"version": 1, "ledge": [0, 0, 2], "ramp": [0, 0, 3, 3]},
		{"version": 1, "ledge": [0, 0, -3, 2], "ramp": [0, 2, -3, 3]},
		{"version": 1, "ledge": [0, 0, 3, 2], "ramp": [0, 5, 3, 3]},
		{"version": 1, "ledge": [9999, 0, 3, 2], "ramp": [9999, 2, 3, 3]},
		{"version": 1, "ledge": [0, 0, INF, 2], "ramp": [0, 2, INF, 3]}]:
		check(not terrain.valid_blueprint(malformed, geometry), "malformed saved terrain is rejected")
		record.fps_terrain = malformed
		var instance = terrain.get_script().new()
		instance.setup(game.room)
		check(record.fps_terrain is Dictionary and record.fps_terrain.is_empty() and not instance.ledge.has_area(),
			"malformed saved terrain falls back to flat without loading a blocker")
	var portal_geometry = load("res://scripts/dungeon/room_geometry.gd").new([Vector2i.ZERO])
	var portal_layout = {"version": 1, "ledge": [-1.7, -5.5, 3.4, 2.6], "ramp": [-1.7, -2.9, 3.4, 3.6]}
	check(terrain.valid_blueprint(portal_layout, portal_geometry), "portal regression fixture stays within the floor footprint")
	check(not terrain.valid_blueprint(portal_layout, portal_geometry, {"north": {"cell": Vector2i.ZERO, "dir": Vector2i.UP}}),
		"persisted terrain cannot obstruct a required doorway")
	record.fps_terrain = valid

func check_more_seeded_rooms() -> void:
	var inspected := 0
	for seed_value in [99, 421, 9001, 26018, 73021, 109321, 468103, 992301]:
		game.start_run("candle", seed_value, false)
		for id in run.rooms:
			if run.rooms[id].type != "combat" or run.rooms[id].cells.size() < 2: continue
			run.current_room = id
			run.rooms[id].cleared = true
			run.rooms[id].claimed = true
			game.enter_room(Vector3(0, 0, 2))
			var terrain = game.room.terrain
			if not terrain or not terrain.ramp.has_area(): continue
			inspected += 1
			check(terrain.valid_blueprint(run.rooms[id].fps_terrain, game.room.geometry), "additional seeded gallery stays within the footprint")
			var bottom = terrain.ramp.get_center() + Vector2(0, terrain.ramp.size.y / 2 + .6)
			var top: Vector2 = terrain.ledge.get_center()
			check(game.room.navigation(.5).reachable(bottom, top), "additional furnished gallery has a connected ramp route")
			for socket in game.room.sockets.values():
				var entry = load("res://scripts/dungeon/room_geometry.gd").entry_point(socket.cell, socket.dir)
				check(game.room.navigation(.5).reachable(entry, bottom), "gallery reservation preserves doorway reachability")
			await process_frame
	check(inspected > 8, "seeded gallery and doorway checks cover more than eight independent rooms")
