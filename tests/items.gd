extends SceneTree
## Phase 3 gate: pickups, keys and chests, bombs, the reward ledger, the
## timed active-item ledger and touch action buttons. Spending, collection and
## swaps persist once; pause freezes timers; held sticks survive action taps.
var checks = 0
var failures = 0
var run
var game
## Loaded after autoloads exist; the class references Content.
var Items

func _initialize() -> void:
	call_deferred("test_items")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func saved() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(run.SAVE_PATH))

func room_data() -> Dictionary:
	return run.rooms[run.current_room]

## Save, then load through the real Continue path.
func reload() -> void:
	run.save_run()
	game.continue_run()
	await process_frame

func step(seconds: float, delta := .05) -> void:
	for i in roundi(seconds / delta):
		game._physics_process(delta)

func fresh_run(seed_value: int) -> void:
	game.start_run("candle", seed_value, false)
	await process_frame
	game.player.position = Vector3(6, 0, 4)

func test_catalog() -> void:
	var content = root.get_node("Content")
	check(content.errors.is_empty(), "the shipped item catalog validates: " + ", ".join(content.errors))
	var problems: Array[String] = []
	content._validate_actives(problems, {"id": "x", "name": "X", "handler": "teleport", "cooldown": 5, "params": {}})
	check(problems.any(func(m): return m.contains("unknown handler")), "an active with an unimplemented handler is rejected")
	problems = []
	content._validate_pickups(problems, {"id": "x", "effect": "coins", "amount": 1, "visual": "coin", "cap": 0})
	check(problems.any(func(m): return m.contains("cap")), "a pickup with an impossible cap is rejected")
	for table in content.families.drop_tables:
		var gen = RandomNumberGenerator.new()
		gen.seed = 5
		for i in 200:
			for pickup in Items.roll_table(table.id, gen, 2.0):
				check(content.has_def("pickups", pickup), "drop table %s only yields real pickups" % table.id)
	check(Items.pickup_def("coin").id == "copper_coin" and Items.pickup_def("heart").id == "half_heart", "legacy drop kinds resolve")

func test_pickups() -> void:
	await fresh_run(31001)
	run.keys = 0
	game.spawn_pickup(Vector3(1, 0, 1), "key", 1)
	var key_id: int = game.pickups.back().drop_id
	check(game.perform_action({"type": "CollectPickup", "drop_id": key_id}).ok and run.keys == 1, "a key pickup grants one key")
	check(not game.perform_action({"type": "CollectPickup", "drop_id": key_id}).ok and run.keys == 1, "a key cannot be collected twice")
	check(int(saved().keys) == 1 and not saved().rooms[run.current_room].get("pickups", []).any(func(d): return int(d.id) == key_id), "collection is saved together with its removed drop")
	await reload()
	check(run.keys == 1 and not game.pickups.any(func(p): return p.drop_id == key_id), "a collected key stays collected after Continue")
	run.keys = 9
	game.spawn_pickup(Vector3(1, 0, 1), "key", 1)
	check(game.perform_action({"type": "CollectPickup", "drop_id": game.pickups.back().drop_id}).reason == "not_useful" and run.keys == 9, "keys respect their cap")
	run.bombs = 0
	game.spawn_pickup(Vector3(1, 0, 1), "bomb", 1)
	check(game.perform_action({"type": "CollectPickup", "drop_id": game.pickups.back().drop_id}).ok and run.bombs == 1, "a bomb pickup grants a bomb")
	var coins: int = run.coins
	game.spawn_pickup(Vector3(1, 0, 1), "silver_coin", 5)
	check(game.perform_action({"type": "CollectPickup", "drop_id": game.pickups.back().drop_id}).ok and run.coins == coins + 5, "a silver coin is worth five")
	run.wards = 0
	game.spawn_pickup(Vector3(1, 0, 1), "ward", 1)
	check(game.perform_action({"type": "CollectPickup", "drop_id": game.pickups.back().drop_id}).ok and run.wards == 1, "a ward pickup grants a ward")
	run.hp = 3
	game.player.invulnerability = 0
	game.player.shield = 0
	game.player.hurt(1, Vector3.ZERO)
	check(run.wards == 0 and is_equal_approx(run.hp, 3), "a ward absorbs one hit before health")
	game.player.invulnerability = 0
	game.player.hurt(1, Vector3.ZERO)
	check(is_equal_approx(run.hp, 2), "with no ward left, the hit costs health")
	game.spawn_pickup(Vector3(1, 0, 1), "small_battery", 15)
	check(game.perform_action({"type": "CollectPickup", "drop_id": game.pickups.back().drop_id}).reason == "not_useful", "a battery without a cooling active stays on the ground")
	for kind in ["copper_coin", "full_heart", "ward", "key", "bomb", "full_battery", "coin", "heart"]:
		game.spawn_pickup(Vector3(-2, 0, 1), kind, 1)
		check(game.pickups.back().visual.get_child_count() > 0, "pickup %s has a visual" % kind)

func test_chests() -> void:
	await fresh_run(31002)
	var data := room_data()
	data.chests = [{"id": "test:0", "position": [-3.0, -3.0], "locked": true, "opened": false, "table": "chest"}]
	game.build_room_objects()
	var target := "chest:test:0"
	check(not game.interactions.get_target(target).is_empty(), "a chest in a cleared room is interactable")
	game.player.position = Vector3(-3, 0, -2)
	run.keys = 0
	var result: Dictionary = game.perform_action({"type": "Interact", "target": target})
	check(result.reason == "no_key" and run.keys == 0 and not data.chests[0].opened, "a locked chest without a key does nothing")
	run.keys = 2
	var drops_before: int = data.get("pickups", []).size()
	result = game.perform_action({"type": "Interact", "target": target})
	check(result.ok and run.keys == 1 and data.chests[0].opened, "opening spends exactly one key")
	check(data.get("pickups", []).size() > drops_before, "the chest's contents are persistent drops")
	var file := saved()
	check(int(file.keys) == 1 and file.rooms[run.current_room].chests[0].opened, "key spend and opened chest are saved together")
	check(not game.perform_action({"type": "Interact", "target": target}).ok and run.keys == 1, "an opened chest cannot be opened again")
	check(game.interactions.get_target(target).is_empty(), "an opened chest stops offering its prompt")
	await reload()
	check(run.keys == 1 and room_data().chests[0].opened, "the opened chest and key debit survive Continue")
	check(game.interactions.get_target(target).is_empty(), "a reloaded opened chest is not interactable")

func test_bombs() -> void:
	await fresh_run(31003)
	run.bombs = 1
	game.player.position = Vector3(0, 0, 0)
	check(game.perform_action({"type": "PlaceBomb"}).ok, "a bomb can be placed")
	game.player.position = Vector3(6, 0, 4)
	check(run.bombs == 0 and run.pending_bombs.size() == 1, "placing debits the bomb and records it as pending")
	check(int(saved().bombs) == 0 and saved().pending_bombs.size() == 1, "debit and pending bomb are saved together")
	check(game.perform_action({"type": "PlaceBomb"}).reason == "no_bombs" and run.pending_bombs.size() == 1, "no bombs means no placement")
	step(1.0)
	var fuse := float(run.pending_bombs[0].fuse)
	check(fuse < Items.BOMB_FUSE and fuse > 0, "the fuse burns on gameplay time")
	await reload()
	check(run.bombs == 0 and run.pending_bombs.size() == 1, "Continue neither refunds nor loses a pending bomb")
	check(game.bomb_nodes.has(int(run.pending_bombs[0].id)) and is_instance_valid(game.bomb_nodes[int(run.pending_bombs[0].id)]), "the pending bomb is rebuilt in its room")
	var enemy = game.spawn_enemy(Vector3(.5, 0, 0), "brute", "")
	enemy.hp = 5
	step(Items.BOMB_FUSE + .2)
	check(run.pending_bombs.is_empty() and saved().pending_bombs.is_empty(), "the bomb detonates once and is removed from the save")
	check(not is_instance_valid(enemy) or not enemy.alive, "the blast damages enemies in its radius")
	check(run.bombs == 0, "detonation never refunds")
	# Pausing freezes the fuse.
	run.bombs = 1
	game.player.position = Vector3(0, 0, 0)
	game.perform_action({"type": "PlaceBomb"})
	game.player.position = Vector3(6, 0, 4)
	game.pause_game()
	step(5.0)
	check(run.pending_bombs.size() == 1 and is_equal_approx(float(run.pending_bombs[0].fuse), Items.BOMB_FUSE), "a paused game freezes bomb fuses")
	game.resume_game()
	step(3.0)
	check(run.pending_bombs.is_empty(), "the fuse resumes after unpausing")

func kill(enemy) -> void:
	enemy.take_hit(99999, Vector3.ZERO)

func test_reward_ledger() -> void:
	await fresh_run(31004)
	var source := "%d:%s:7" % [run.floor_number, run.current_room]
	var kills: int = run.kills
	var drops: int = room_data().get("pickups", []).size()
	kill(game.spawn_enemy(Vector3(-4, 0, -2), "mote", source))
	check(run.kills == kills + 1 and run.reward_ledger.has(source), "a kill is credited once in the ledger")
	var after: int = room_data().get("pickups", []).size()
	check(after > drops, "the kill drops its reward")
	await reload()
	kill(game.spawn_enemy(Vector3(-4, 0, -2), "mote", source))
	check(run.kills == kills + 1 and room_data().get("pickups", []).size() == after, "a reloaded re-kill of the same source pays nothing")
	kill(game.spawn_enemy(Vector3(-4, 0, -2), "mote", ""))
	check(run.kills == kills + 1 and room_data().get("pickups", []).size() == after, "summoned foes never pay out")
	var splitter = game.spawn_enemy(Vector3(-4, 0, -2), "splitter", source + "s")
	kill(splitter)
	var children: Array = game.enemies.filter(func(e): return is_instance_valid(e) and e.alive and e.kind == "wisp")
	check(children.size() == 2 and children.map(func(e): return e.source).has(source + "s:0") and children.map(func(e): return e.source).has(source + "s:1"), "splitter children get deterministic sources")
	for child in children: kill(child)
	check(run.kills == kills + 4, "each splitter child is credited once")

func test_actives() -> void:
	await fresh_run(31005)
	var items = game.items
	check(game.perform_action({"type": "UseActive"}).reason == "no_active", "nothing to use without an active")
	game.equip_active("pocket_hearth")
	run.hp = 2
	run.coins = 2
	check(game.perform_action({"type": "UseActive"}).reason == "insufficient_coins" and items.cooldown_left() == 0, "an unaffordable use starts no cooldown")
	run.coins = 10
	run.hp = run.stats.max_hp
	check(game.perform_action({"type": "UseActive"}).reason == "not_useful" and run.coins == 10, "healing at full health is refused for free")
	run.hp = 2
	check(game.perform_action({"type": "UseActive"}).ok and is_equal_approx(run.hp, 4) and run.coins == 7, "a valid use heals and pays its cost")
	check(is_equal_approx(items.cooldown_left(), 60), "use starts the declared cooldown")
	check(game.perform_action({"type": "UseActive"}).reason == "cooling_down" and is_equal_approx(run.hp, 4), "a cooling active cannot be used")
	game.pause_game()
	step(3.0)
	check(is_equal_approx(items.cooldown_left(), 60), "a paused game freezes cooldowns")
	game.resume_game()
	game.ui.show_screen("map")
	game.paused = true
	step(3.0)
	check(is_equal_approx(items.cooldown_left(), 60), "the map freezes cooldowns")
	game.ui.close_map()
	step(2.0)
	check(absf(items.cooldown_left() - 58) < .01, "cooldowns tick on gameplay time")
	# Swapping drops the held active; its ledger entry keeps counting down.
	run.cooldowns["ember_flask"] = 0.0
	var dropped_before: int = room_data().get("actives", []).size()
	game.equip_active("ember_flask")
	check(run.active_item.id == "ember_flask" and room_data().actives.size() == dropped_before + 1, "a swap sets the old active down")
	var record: Dictionary = room_data().actives.back()
	check(record.active == "pocket_hearth", "the dropped record names the old active")
	step(4.0)
	check(absf(float(run.cooldowns.pocket_hearth) - 54) < .01, "a set-down active keeps recharging")
	game.player.position = Vector3(record.position[0], 0, record.position[1])
	check(game.perform_action({"type": "Interact", "target": "active:%d" % int(record.id)}).ok and run.active_item.id == "pocket_hearth", "picking it back up swaps again")
	check(absf(items.cooldown_left() - 54) < .01, "swapping back never resets the cooldown")
	check(room_data().actives.any(func(r): return r.active == "ember_flask"), "the flask is now on the floor")
	await reload()
	check(run.active_item.id == "pocket_hearth" and absf(items.cooldown_left() - 54) < .01, "the active and its cooldown survive Continue")
	check(room_data().actives.any(func(r): return r.active == "ember_flask"), "dropped actives survive Continue")
	# A second instance of the same definition shares the ledger entry.
	game.equip_active("pocket_hearth")
	check(absf(items.cooldown_left() - 54) < .01, "a duplicate instance cannot dodge the cooldown")
	game.spawn_pickup(Vector3(1, 0, 1), "small_battery", 15)
	check(game.perform_action({"type": "CollectPickup", "drop_id": game.pickups.back().drop_id}).ok and absf(items.cooldown_left() - 39) < .01, "a small battery removes fifteen seconds")
	game.spawn_pickup(Vector3(1, 0, 1), "full_battery", 0)
	check(game.perform_action({"type": "CollectPickup", "drop_id": game.pickups.back().drop_id}).ok and items.cooldown_left() == 0, "a full battery recharges completely")
	# A fresh press is required: one request uses once, holding never repeats.
	run.hp = 1
	run.coins = 20
	game.request_active = true
	step(.05)
	check(not game.request_active and is_equal_approx(run.hp, 3), "a press uses the active once")
	run.cooldowns.pocket_hearth = 0.0
	step(.5)
	check(is_equal_approx(run.hp, 3), "a ready active is not used without a new press")
	game.equip_active("ember_flask")
	run.cooldowns.ember_flask = 0.0
	var shots: int = game.shots.size()
	check(game.perform_action({"type": "UseActive"}).ok and game.shots.size() >= shots + 14, "the ember flask releases its ring")

func touch(index: int, at: Vector2, pressed := true) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = at * game.ui.scale_value + game.ui.offset
	game.ui._input(event)

func test_touch() -> void:
	await fresh_run(31006)
	var ui = game.ui
	ui.touch_used = true
	check(ui.touch_controls_visible(), "touch controls show once touch is used")
	for action in ui.ACTION_BUTTONS:
		var spec: Array = ui.ACTION_BUTTONS[action]
		check(ui.action_button_at(spec[0]) == action, "%s button is hit at its centre" % action)
		check(spec[0].y - spec[1] > 330 and spec[0].x - spec[1] > 730, "%s button sits in the right thumb area" % action)
		for other in ui.ACTION_BUTTONS:
			if other != action:
				var other_spec: Array = ui.ACTION_BUTTONS[other]
				check(spec[0].distance_to(other_spec[0]) > spec[1] + other_spec[1], "%s and %s buttons never overlap" % [action, other])
		check(not ui.INTERACTION_RECT.intersects(Rect2(spec[0] - Vector2.ONE * spec[1], Vector2.ONE * spec[1] * 2)), "%s button clears the interaction prompt" % action)
	touch(0, Vector2(200, 500))
	touch(1, Vector2(1180, 420))
	check(ui.left_touch == 0 and ui.right_touch == 1, "both sticks capture their fingers")
	touch(2, ui.ACTION_BUTTONS.active[0])
	touch(3, ui.ACTION_BUTTONS.bomb[0])
	touch(4, ui.ACTION_BUTTONS.dash[0])
	check(game.request_active and game.request_bomb and game.request_dash, "action taps raise their requests")
	check(ui.left_touch == 0 and ui.right_touch == 1, "action taps never steal a held stick")
	touch(2, ui.ACTION_BUTTONS.active[0], false)
	touch(3, ui.ACTION_BUTTONS.bomb[0], false)
	touch(4, ui.ACTION_BUTTONS.dash[0], false)
	check(ui.left_touch == 0 and ui.right_touch == 1, "releasing action taps leaves both sticks captured")
	touch(0, Vector2(200, 500), false)
	touch(1, Vector2(1180, 420), false)
	check(ui.left_touch == -1 and ui.right_touch == -1, "sticks release with their own fingers")
	game.request_active = false
	game.request_bomb = false
	game.request_dash = false
	game.equip_active("pocket_hearth")
	run.cooldowns.pocket_hearth = 12.0
	ui.queue_redraw()
	await process_frame
	check(true, "the HUD draws actives, bombs and supplies")

func test_generation() -> void:
	var with_chests := 0
	var geometry_ok := true
	run.generator = run.GENERATOR_V2
	for seed_value in range(1, 151):
		run.seed_value = seed_value
		run.floor_number = 1 + seed_value % 3
		run.generate_floor()
		for key in run.rooms:
			for chest in run.rooms[key].get("chests", []):
				with_chests += 1
				var layout: Dictionary = run.room_layout(key)
				var geometry := RoomGeometry.new(layout.cells)
				var at := Vector2(chest.position[0], chest.position[1])
				if not geometry.contains(at, 1.0): geometry_ok = false
				for socket in layout.sockets:
					if geometry.entry_point(socket.cell, socket.dir).distance_to(at) < 2.5: geometry_ok = false
				var secret: bool = run.rooms[key].type == "secret"
				if not secret and (run.rooms[key].type not in ["combat", "treasure"] or not chest.locked): geometry_ok = false
				if secret and (chest.locked or chest.table != "secret_cache"): geometry_ok = false
	check(with_chests > 150, "generated floors contain locked chests (%d)" % with_chests)
	check(geometry_ok, "chests sit inside their room, clear of doorways; locked only in combat and treasure rooms, open caches in secrets")
	run.seed_value = 4242
	run.floor_number = 1
	run.generate_floor()
	var first: Dictionary = run.rooms.duplicate(true)
	run.generate_floor()
	check(JSON.stringify(first) == JSON.stringify(run.rooms), "chest placement is deterministic")

## Phase 7: the remaining six actives. Each refuses (no cooldown) when it
## would do nothing, then acts once and starts its declared cooldown.
func use_fresh(id: String) -> Dictionary:
	game.equip_active(id)
	run.cooldowns[id] = 0.0
	return game.perform_action({"type": "UseActive"})

func test_all_actives() -> void:
	var defs: Array = root.get_node("Content").families.actives
	check(defs.size() == 8, "all eight actives are in the catalog")
	await fresh_run(31007)
	for enemy in game.enemies: enemy.queue_free()
	game.enemies.clear()
	await process_frame
	for id in ["gale_bell", "winter_globe", "copper_kettle", "moth_jar", "bell_jar"]:
		var used := use_fresh(id)
		check(not used.ok and used.reason == "no_target" and game.items.cooldown_left() == 0, id + " is refused in an empty room")
	game.player.position = Vector3(0, 0, 0)
	var near = game.spawn_enemy(Vector3(2, 0, 0), "brute", "")
	var far = game.spawn_enemy(Vector3(-7, 0, -4), "mote", "")
	var hostile = game.spawn_shot(Vector3(1.5, .6, 1), Vector3.LEFT, 1, 0.01, {}, Color.RED, false)
	# Gale Bell clears nearby hostile shots and pushes foes away.
	check(use_fresh("gale_bell").ok and not (is_instance_valid(hostile) and hostile.alive), "the gale clears a nearby hostile shot")
	check(near.knock_velocity.x > 1.0, "the gale pushes a nearby foe away")
	check(is_equal_approx(game.items.cooldown_left(), 35), "the gale starts its cooldown")
	# Winter Globe slows everything; bosses resist.
	far.boss = true
	check(use_fresh("winter_globe").ok and is_equal_approx(near.chill_time, 4) and is_equal_approx(far.chill_time, 2), "the globe slows foes, half as long for bosses")
	far.boss = false
	# Copper Kettle: a refreshing, non-stacking layer that never eats relics.
	var damage: float = run.stats.damage
	check(use_fresh("copper_kettle").ok and is_equal_approx(run.stats.damage, damage + .35), "the kettle raises damage")
	check(use_fresh("copper_kettle").ok and run.modifiers.size() == 1 and is_equal_approx(run.stats.damage, damage + .35), "a second kettle refreshes instead of stacking")
	var relic: String = root.get_node("Content").items[0].id
	run.gain_item(relic)
	var with_relic: float = Content_damage_without_modifiers()
	await reload()
	check(run.modifiers.size() == 1 and run.stats.damage > with_relic, "the kettle layer survives Continue")
	step(6.5)
	check(run.modifiers.is_empty() and is_equal_approx(run.stats.damage, with_relic), "the kettle expires and the relic acquired during it stays")
	near = game.spawn_enemy(Vector3(2, 0, 0), "brute", "")
	# Moth Jar: two companions within the budget, room-scoped.
	game.player.position = Vector3(0, 0, 0)
	check(use_fresh("moth_jar").ok and game.live_companions().size() == 2, "the moth jar releases two moths")
	check(use_fresh("moth_jar").reason == "no_capacity" and game.items.cooldown_left() == 0, "moths beyond the budget are refused for free")
	var hp_before: float = near.hp
	step(1.5)
	check(not is_instance_valid(near) or not near.alive or near.hp < hp_before, "the moths attack")
	step(10.0)
	check(game.live_companions().is_empty(), "the moths leave when their time is up")
	# Bell Jar: untouchable for its duration, then hits land again.
	near = game.spawn_enemy(Vector3(3, 0, 0), "brute", "")
	run.hp = 4
	check(use_fresh("bell_jar").ok and game.player.bell_time > 0, "the bell jar covers the player")
	game.player.hurt(1, Vector3.ZERO)
	check(is_equal_approx(run.hp, 4), "no hit lands under the bell jar")
	game.player.update_sim(3.0, Vector2.ZERO, Vector3.ZERO, false)
	run.wards = 0
	game.player.hurt(1, Vector3.ZERO)
	check(is_equal_approx(run.hp, 3), "hits land again once it lifts")
	# Miner's Lantern: only beside a concealed seam, and it never opens it.
	check(use_fresh("miners_lantern").reason == "no_target", "the lantern is refused with no seam in the room")
	var seam_room := ""
	for key in run.rooms:
		if run.rooms[key].type != "secret" and run.room_layout(key).sockets.any(func(s): return s.get("state", "open") == "concealed"):
			seam_room = key
	check(seam_room != "", "the floor has a room beside its secret")
	run.current_room = seam_room
	run.rooms[seam_room].cleared = true
	game.enter_room(Vector3.ZERO)
	await process_frame
	var concealed: int = game.room.concealed.size()
	check(use_fresh("miners_lantern").ok and is_equal_approx(game.items.cooldown_left(), 40), "the lantern lights a seam")
	check(game.room.concealed.size() == concealed and game.room.find_children("SeamHint*", "", true, false).size() >= 2, "the seam glows but stays closed")

func Content_damage_without_modifiers() -> float:
	var saved_modifiers: Array = run.modifiers
	run.modifiers = []
	run.rebuild_stats()
	var value: float = run.stats.damage
	run.modifiers = saved_modifiers
	run.rebuild_stats()
	return value

func test_items() -> void:
	run = root.get_node("Run")
	Items = load("res://scripts/items/item_system.gd")
	test_catalog()
	test_generation()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	await test_pickups()
	await test_chests()
	await test_bombs()
	await test_reward_ledger()
	await test_actives()
	await test_all_actives()
	await test_touch()
	game.end_run(false)
	game.queue_free()
	root.get_node("Audio").music_player.stop()
	await process_frame
	await process_frame
	print("EMBERKEEP ITEMS TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
