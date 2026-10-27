extends SceneTree
var failures := 0
var checks := 0
var game
var run
var catalog

func _initialize() -> void:
	call_deferred("test_all")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func test_all() -> void:
	run = root.get_node("Run")
	catalog = root.get_node("Content")
	check(catalog.items.size() == 60, "60 relics loaded")
	check(catalog.weapons.size() == 10, "10 weapons loaded")
	var valid_stats: Dictionary = catalog.base_stats()
	for item in catalog.items:
		for key in item.effects:
			check(valid_stats.has(key), "implemented stat: " + key)
	for seed_value in range(1, 51):
		run.seed_value = seed_value
		for floor_value in range(1, 4):
			run.floor_number = floor_value
			run.generate_floor()
			var visited := {"0,0": true}
			var queue: Array = ["0,0"]
			while not queue.is_empty():
				var key: String = queue.pop_front()
				for next in run.neighbors(key):
					if not visited.has(next):
						visited[next] = true
						queue.append(next)
			check(visited.size() == run.rooms.size(), "all rooms reachable")
			for kind in ["boss", "treasure", "shop", "rest"]:
				var count := 0
				for room in run.rooms.values():
					if room.type == kind: count += 1
				check(count == 1, "exactly one " + kind)
			var before := JSON.stringify(run.rooms)
			run.generate_floor()
			check(JSON.stringify(run.rooms) == before, "seed reproducibility")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	game.start_run("candle", 482765, false)
	check(game.ui.mode == "play" and run.active, "run starts")
	game.paused = true
	run.gain_item("seeking_spark")
	run.gain_item("skipping_stone")
	run.gain_item("shattered_star")
	run.gain_item("storm_lantern")
	run.gain_item("winter_mint")
	run.gain_item("firefly_jar")
	check(run.stats.homing > 0 and run.stats.bounce == 2 and run.stats.split == 2 and run.stats.chain == 3, "synergy effects combine")
	check(game.player.orbit_meshes.size() == 1, "orbital appears")
	run.coins = 37
	run.hp = 3
	run.save_run()
	var state: String = str(run.rng.state)
	run.coins = 0
	run.inventory.clear()
	check(run.load_run(), "save loads")
	check(run.coins == 37 and run.hp == 3 and run.inventory.size() == 6, "save roundtrip")
	check(str(run.rng.state) == state, "64-bit RNG state preserved")
	# Save writes occur through the same persistence API used by Android lifecycle.
	game.continue_run()
	game.paused = true
	var enemy = game.spawn_enemy(Vector3(1, 0, 0), "brute")
	var initial_hp: float = enemy.hp
	var shot = game.spawn_shot(Vector3(1, .65, -.1), Vector3.FORWARD, 4, 0, run.projectile_stats(), Color.WHITE, true)
	shot.hit_enemy(enemy)
	check(enemy.hp < initial_hp, "projectile damage applied")
	check(enemy.chill_time > 0, "element status applied")
	check(game.shots.size() >= 3, "split creates child projectiles")
	game.player.invulnerability = 0
	var before_hp: float = run.hp
	game.player.dash()
	game.player.hurt(1, Vector3.ZERO)
	check(run.hp == before_hp, "dash grants invulnerability")
	check(game.player.dash_cooldown > 0, "dash has cooldown")
	game.pause_game()
	check(game.paused and game.ui.mode == "pause", "pause screen")
	game.resume_game()
	check(not game.paused and game.ui.mode == "play", "resume screen")
	game.paused = true
	# Exercise every weapon firing path with actual scene instances.
	for weapon in catalog.weapons:
		run.weapon_id = weapon.id
		game.player.fire()
	check(game.shots.size() > 20, "all weapons instantiate projectiles")
	# Exercise room combat, rewards and progression, without touching live data.
	# These checks use single-cell coordinates; multi-cell rooms are covered
	# by tests/dungeon.gd.
	var combat_key := ""
	for key in run.rooms:
		if run.rooms[key].type == "combat" and run.rooms[key].cells.size() == 1: combat_key = key; break
	run.current_room = combat_key
	game.enter_room(Vector3(0, 0, 4))
	check(not game.room.open and game.enemies.size() > 0, "combat room locks with enemies")
	for foe in game.enemies.duplicate():
		if is_instance_valid(foe): foe.take_hit(100000, Vector3.ZERO)
	for foe in game.enemies.duplicate():
		if is_instance_valid(foe) and foe.alive: foe.take_hit(100000, Vector3.ZERO)
	game.clear_room()
	check(game.room.open and run.rooms[combat_key].cleared, "room clear opens exits")
	game.ensure_offers(true)
	var offers: Array = run.rooms[combat_key].offers
	check(offers.size() == 3, "three reward offers")
	run.rooms[combat_key].claimed = false
	game.chosen_reward_shop = false
	var before_count: int = run.inventory.size()
	game.choose_offer(0)
	check(run.inventory.size() == before_count + 1, "reward grants relic")
	game.choose_offer(0)
	check(run.inventory.size() == before_count + 1, "reward cannot be claimed twice")
	# Drops survive both room reconstruction and a disk save/load roundtrip.
	game.spawn_pickup(Vector3(4, 0, 2), "silver_coin")
	var drop_id: String = game.pickups.back().drop_id
	run.save_run()
	game.enter_room(Vector3(0, 0, 4))
	var restored = game.pickups.filter(func(p): return p.drop_id == drop_id)
	check(restored.size() == 1, "uncollected drop survives room re-entry")
	check(run.load_run(), "checkpoint with drops loads")
	game.enter_room(Vector3(0, 0, 4))
	restored = game.pickups.filter(func(p): return p.drop_id == drop_id)
	check(restored.size() == 1, "uncollected drop survives disk save/load")
	var old_coins: int = run.coins
	game.player.position = restored[0].position
	restored[0].age = 1
	restored[0].update_sim(0)
	check(run.coins == old_coins + 5, "restored drop grants its original value")
	run.load_run()
	game.enter_room(Vector3(0, 0, 4))
	check(game.pickups.filter(func(p): return p.drop_id == drop_id).is_empty(), "collected drop cannot be restored twice")
	var bouncing = game.spawn_shot(Vector3(8.8, .65, 0), Vector3.RIGHT, 1, 20, {"bounce": 1}, Color.WHITE, true)
	bouncing.update_sim(.02)
	check(bouncing.alive and bouncing.bounces == 0 and bouncing.direction.x < 0, "projectile ricochets off room boundary")
	# Boss reward persists until chosen, including after a save reload.
	var boss_key := ""
	for key in run.rooms:
		if run.rooms[key].type == "boss": boss_key = key; break
	run.current_room = boss_key
	game.enter_room(Vector3(0, 0, 4))
	check(game.get_boss() != null, "boss encounter spawns")
	game.get_boss().take_hit(100000, Vector3.ZERO)
	game.clear_room()
	run.load_run()
	game.enter_room(Vector3(0, 0, 4))
	check(game.marker.get_meta("kind") == "treasure", "unclaimed boss reward survives reload")
	run.rooms[boss_key].erase("offers")
	game.enter_room(Vector3(0, 0, 4))
	check(game.marker.get_meta("kind") == "treasure" and run.rooms[boss_key].offers.size() == 3, "interrupted boss reward generation recovers")
	game.chosen_reward_shop = false
	game.choose_offer(0)
	game.enter_room(Vector3(0, 0, 4))
	check(game.marker.get_meta("kind") == "exit", "claimed boss reward becomes floor exit")
	# Independent multitouch streams do not cancel one another.
	game.ui.show_screen("play")
	var finger_left := InputEventScreenTouch.new()
	finger_left.index = 0
	finger_left.position = game.ui.offset + Vector2(140, 574) * game.ui.scale_value
	finger_left.pressed = true
	game.ui._input(finger_left)
	var finger_right := InputEventScreenTouch.new()
	finger_right.index = 1
	finger_right.position = game.ui.offset + Vector2(1112, 574) * game.ui.scale_value
	finger_right.pressed = true
	game.ui._input(finger_right)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = game.ui.offset + Vector2(188, 574) * game.ui.scale_value
	game.ui._input(drag)
	check(game.ui.left_vector.x > .7 and game.ui.right_touch == 1, "left stick moves while right finger remains captured")
	finger_left.pressed = false
	game.ui._input(finger_left)
	check(game.ui.left_vector == Vector2.ZERO and game.ui.right_touch == 1, "releasing move stick preserves aim touch")
	finger_right.pressed = false
	game.ui._input(finger_right)
	check(game.ui.right_touch == -1, "aim stick releases independently")
	run.inventory.append("eternal_hearth")
	run.rebuild_stats()
	run.hp = 2
	run.rooms[boss_key].cleared = false
	run.cleared = 1
	run.mark_cleared()
	check(run.hp == 3, "Eternal Hearth heals every cleared combat room")
	run.next_floor()
	check(run.floor_number == 2 and run.current_room == "0,0", "floor progression")
	# Run 180 real physics frames to catch movement, AI and projectile runtime errors.
	run.current_room = run.neighbors("0,0")[0]
	game.enter_room(Vector3(0, 0, 4))
	run.hp = 6
	game.paused = false
	for frame in 180:
		await physics_frame
		if run.active:
			game.player.invulnerability = .1
			game._physics_process(1.0 / 60)
	check(run.active, "simulated combat runs for 180 frames")
	# Extreme builds stay bounded and every catalog effect reaches live combat.
	run.inventory = catalog.items.map(func(item): return item.id)
	run.rebuild_stats()
	game.player.refresh_orbitals()
	check(game.player.orbit_meshes.size() <= 8, "orbital cap keeps extreme builds bounded")
	for weapon in catalog.weapons:
		run.weapon_id = weapon.id
		game.player.fire()
	for frame in 90:
		await physics_frame
		if run.active:
			game.player.invulnerability = .1
			game._physics_process(1.0 / 60)
	check(game.shots.size() <= 200, "extreme multishot build respects projectile limit")
	game.end_run(false)
	check(not run.active and game.ui.mode == "dead" and not run.has_save(), "death ends run and clears save")
	var previous_wins: int = run.profile.wins
	game.start_run("candle", 12345, false)
	game.end_run(true)
	check(game.ui.mode == "won" and run.profile.wins == previous_wins + 1 and not run.has_save(), "victory updates profile and clears active checkpoint")
	await process_frame
	game.queue_free()
	await process_frame
	print("EMBERKEEP TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
