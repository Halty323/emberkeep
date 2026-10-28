extends SceneTree
## Phase 4 gate: the full footprint set, themed furniture layouts, persistent
## breakables and secret rooms. Mandatory progression never needs a secret,
## every required object stays reachable, and destroyed/revealed state
## survives reload.
var checks = 0
var failures = 0
var run
var game
var F
var Items

func _initialize() -> void:
	call_deferred("test_furniture")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func saved() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(run.SAVE_PATH))

func step(seconds: float, delta := .05) -> void:
	for i in roundi(seconds / delta):
		game._physics_process(delta)

func test_catalog() -> void:
	var content = root.get_node("Content")
	check(content.errors.is_empty(), "the furniture catalog validates: " + ", ".join(content.errors))
	var problems: Array[String] = []
	content._validate_furniture(problems, {"id": "ghost", "recipe": "crate", "size": [1, 1], "height": 1, "blocks": false, "placement": "corner", "breakable": {"hp": 5, "table": "prop_small"}})
	check(problems.any(func(m): return m.contains("no collision")), "a breakable without collision is rejected")
	problems = []
	content._validate_layouts(problems, {"id": "odd", "roles": ["combat"], "weight": 1, "wall": ["throne"]})
	check(problems.any(func(m): return m.contains("missing furniture")), "a layout naming missing furniture is rejected")
	var templates = content.families.rooms.map(func(r): return r.id)
	for id in ["hall_single", "hall_long", "hall_corner", "hall_grand"]:
		check(id in templates, "the footprint set includes " + id)

func layout_ok(label: String, key: String) -> void:
	var room: Dictionary = run.rooms[key]
	var layout: Dictionary = run.room_layout(key)
	var geometry := RoomGeometry.new(layout.cells)
	var props: Array = room.get("props", [])
	var reserved: Array = F.reserved_circles(geometry, layout, room.get("chests", []))
	var obstacles: Array = []
	for i in props.size():
		var record: Dictionary = props[i]
		var def: Dictionary = root.get_node("Content").get_def("furniture", record.def)
		var rect: Rect2 = F.record_rect(record)
		for corner in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
			if not geometry.contains(corner, .04):
				check(false, label + ": %s sits on the floor" % record.id)
				break
		if record.def != "rug" and record.def != "pillar":
			for circle in reserved:
				if F._rect_hits_circle(rect, circle[0], circle[1]):
					check(false, label + ": %s keeps door lanes, rewards and chests clear" % record.id)
					break
		if def.blocks:
			obstacles.append({"rect": rect})
			for j in range(i + 1, props.size()):
				var other: Dictionary = props[j]
				if root.get_node("Content").get_def("furniture", other.def).blocks and rect.intersects(F.record_rect(other)):
					check(false, label + ": %s and %s do not overlap" % [record.id, other.id])
	var nav := RoomNavigation.new(geometry, obstacles, F.CLEARANCE)
	check(nav.connected(F.required_points(geometry, layout, room.get("chests", []))), label + ": every doorway, reward and chest is reachable")

func test_generation() -> void:
	var themes := {}
	var templates := {}
	var prop_kinds := {}
	var breakables := 0
	run.generator = run.GENERATOR_V2
	for seed_value in range(1, 121):
		run.seed_value = seed_value
		run.floor_number = 1 + seed_value % 3
		run.generate_floor()
		for key in run.rooms:
			var room: Dictionary = run.rooms[key]
			templates[room.template] = true
			themes[room.get("theme", "")] = true
			check(room.has("props"), "seed %d: room %s has a resolved furnishing" % [seed_value, key])
			for record in room.get("props", []):
				prop_kinds[record.def] = true
				if root.get_node("Content").get_def("furniture", record.def).has("breakable"): breakables += 1
			layout_ok("seed %d room %s" % [seed_value, key], key)
	for id in ["hall_single", "hall_long", "hall_corner", "hall_grand"]:
		check(templates.has(id), "generation uses " + id)
	for theme in root.get_node("Content").families.layouts:
		check(themes.has(theme.id), "generation uses the %s theme" % theme.id)
	check(prop_kinds.size() >= 14, "most furniture kinds appear (%d)" % prop_kinds.size())
	check(breakables > 200, "floors offer breakables (%d)" % breakables)
	run.seed_value = 77
	run.floor_number = 2
	run.generate_floor()
	var first := JSON.stringify(run.rooms)
	run.generate_floor()
	check(first == JSON.stringify(run.rooms), "furnishing is deterministic")

## A seed whose room has something matching `want`.
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
	game.enter_room(Vector3(0, 0, 0))
	await physics_frame
	await physics_frame

func breakable_ids() -> Array:
	return game.room.props.keys().filter(func(id): return root.get_node("Content").get_def("furniture", game.room.props[id].record.def).has("breakable"))

func test_breakables() -> void:
	var found: Array = find(func(_k, r): return r.type == "combat" and r.props.any(func(p): return p.def in ["crate", "barrel"]))
	check(not found.is_empty(), "a seed has a combat room with a crate or barrel")
	if found.is_empty(): return
	await enter(found[0], found[1])
	var key: String = found[1]
	var ids: Array = breakable_ids()
	check(not ids.is_empty(), "breakables are built in the room")
	var id: String = ids[0]
	var record: Dictionary = game.room.props[id].record
	var obstacles_before: int = game.room.obstacles.size()
	var drops_before: int = run.rooms[key].get("pickups", []).size()
	game.damage_prop(id, 1.0)
	check(not record.destroyed and game.prop_damage.get(id, 0) == 1.0, "a hit chips a breakable without breaking it")
	game.damage_prop(id, 999.0)
	check(record.destroyed and not game.room.props.has(id), "enough damage breaks it once")
	check(game.room.obstacles.size() == obstacles_before - 1, "navigation and repulsion forget the broken piece")
	check(not game.room.navigation.blocked.has(game.room.navigation.to_grid(Vector2(record.position[0], record.position[1]))), "the navigation grid reopens where it stood")
	var drops_after: int = run.rooms[key].get("pickups", []).size()
	check(not game.perform_action({"type": "BreakProp", "prop": id}).ok, "a broken piece cannot break again")
	check(run.rooms[key].get("pickups", []).size() == drops_after, "breaking grants its drops once")
	check(saved().rooms[key].props.any(func(p): return p.id == id and p.destroyed), "the destroyed state is saved")
	var unbreakable: Array = game.room.props.keys().filter(func(i): return game.room.props[i].record.def == "pillar")
	if not unbreakable.is_empty():
		check(game.perform_action({"type": "BreakProp", "prop": unbreakable[0]}).reason == "unbreakable", "pillars cannot be broken")
	# The loot stream belongs to the prop, not the run: same prop, same drops.
	var loot := RandomNumberGenerator.new()
	loot.seed = hash("%d:%s" % [run.seed_value, id])
	var expected = Items.roll_table(root.get_node("Content").get_def("furniture", record.def).breakable.table, loot, run.stats.luck)
	check(drops_after - drops_before == expected.size(), "drops come from the prop's own loot stream")
	run.save_run()
	game.continue_run()
	await physics_frame
	check(not game.room.props.has(id), "a broken piece stays broken after Continue")
	check(run.rooms[key].get("pickups", []).size() == drops_after, "its drops are neither lost nor duplicated on reload")
	# A friendly shot into a crate chips it; the next shots break it.
	ids = breakable_ids()
	if not ids.is_empty():
		var target: String = ids[0]
		var rect: Rect2 = F.record_rect(game.room.props[target].record)
		var aim := Vector3(rect.get_center().x, .6, rect.get_center().y)
		var from := aim + Vector3(0, 0, 2.2)
		if not game.room.geometry.contains(from, .3): from = aim - Vector3(0, 0, 2.2)
		var shot = game.spawn_shot(from, aim - from, 6.0, 12.0, {}, Color.WHITE, true)
		for i in 30:
			if not is_instance_valid(shot) or not shot.alive: break
			shot.update_sim(1.0 / 60.0)
		check(game.prop_damage.get(target, 0.0) > 0 or game.room.props.get(target, {}).get("record", {}).get("destroyed", true), "a friendly shot damages a breakable it hits")

func test_detail_invariance() -> void:
	var found: Array = find(func(_k, r): return r.props.size() > 6)
	if found.is_empty(): return
	var counts: Array = []
	var settings = root.get_node("Settings")
	for level in ["low", "high"]:
		settings.values.small_details = level
		await enter(found[0], found[1])
		var colliders := 0
		for node in game.room.get_children():
			if node is StaticBody3D and node.has_meta("prop_id"): colliders += 1
		counts.append([colliders, game.room.props.size(), game.room.obstacles.size()])
	check(counts[0] == counts[1], "small details never change furniture collision or layout (%s)" % str(counts))
	settings.values.small_details = "balanced"

func test_spawns() -> void:
	var found: Array = find(func(_k, r): return r.type == "combat" and r.props.filter(func(p): return p.def != "rug").size() > 6)
	if found.is_empty(): return
	await enter(found[0], found[1], false)
	check(not game.enemies.is_empty(), "the furnished combat room has foes")
	for enemy in game.enemies:
		check(not game.room.blocked_at(Vector2(enemy.position.x, enemy.position.z), .2), "foes never spawn inside furniture")

func secret_parent(key: String) -> String:
	return run.neighbors(key, true)[0]

func test_secrets() -> void:
	var found: Array = find(func(k, r): return r.type == "secret" and run.rooms[secret_parent(k)].type in ["combat", "treasure", "rest", "shop"])
	check(not found.is_empty(), "a seed has a secret room off an ordinary room")
	if found.is_empty(): return
	var secret: String = found[1]
	var parent: String = secret_parent(secret)
	var pid: String = run.room_portal_ids[secret][0]
	await enter(found[0], parent)
	check(game.room.concealed.has(pid), "the concealed seam shows a hint on the wall")
	check(secret not in run.neighbors(parent) and secret not in game.ui.map_rooms(), "a hidden room leaks into neither neighbours nor the map")
	var socket: Dictionary = game.room.sockets.filter(func(s): return s.portal == pid)[0]
	check(game.perform_action({"type": "EnterPortal", "portal": pid}).reason == "concealed", "a concealed seam cannot be walked through")
	# Bullets never reveal it.
	var door: Vector3 = game.room.socket_position(socket)
	var inward := -Vector3(socket.dir.x, 0, socket.dir.y)
	var shot = game.spawn_shot(door + inward * 3.0 + Vector3.UP * .6, -inward, 50.0, 12.0, {}, Color.WHITE, true)
	for i in 40:
		if not is_instance_valid(shot) or not shot.alive: break
		shot.update_sim(1.0 / 60.0)
	check(run.portals[pid].state == "concealed", "an ordinary shot does not reveal the seam")
	# A bomb against the seam opens it.
	run.bombs = 1
	game.player.position = door + inward * 1.2
	check(game.perform_action({"type": "PlaceBomb"}).ok, "a bomb can be set against the seam")
	game.player.position = Vector3.ZERO
	game.player.last_valid = Vector3.ZERO
	step(Items.BOMB_FUSE + .3)
	check(run.portals[pid].state == "open", "the bomb reveals the seam")
	check(not game.room.concealed.has(pid) and game.room.gates.any(func(g): return g.get_meta("portal") == pid), "the wall becomes a doorway in place")
	check(saved().portals[pid].state == "open", "the reveal is saved before anything inside is claimed")
	check(secret in run.neighbors(parent) and secret in game.ui.map_rooms(), "the revealed room appears on the map")
	# Walk in and claim the cache without a key.
	check(game.perform_action({"type": "EnterPortal", "portal": pid}).ok and run.current_room == secret, "the revealed doorway leads into the secret")
	var chest: Dictionary = run.rooms[secret].chests[0]
	check(not chest.locked and chest.table == "secret_cache", "a secret holds an open cache")
	run.keys = 0
	game.player.position = Vector3(chest.position[0], 0, chest.position[1] + 1.1)
	check(game.perform_action({"type": "Interact", "target": "chest:" + chest.id}).ok and chest.opened, "the cache opens without a key")
	run.save_run()
	game.continue_run()
	await physics_frame
	check(run.portals[pid].state == "open" and run.rooms[secret].chests[0].opened, "reveal and claim survive Continue")
	run.current_room = parent
	game.enter_room(Vector3.ZERO)
	check(not game.room.concealed.has(pid), "re-entering never reseals the wall")
	check(game.interactions.get_target("chest:" + chest.id).is_empty(), "the cache does not replenish")

func test_offscreen_breach() -> void:
	var found: Array = find(func(k, r): return r.type == "secret" and run.rooms[secret_parent(k)].type == "combat")
	if found.is_empty(): return
	var secret: String = found[1]
	var parent: String = secret_parent(secret)
	var pid: String = run.room_portal_ids[secret][0]
	game.start_run("candle", found[0], false)
	await process_frame
	game.paused = false
	var layout: Dictionary = run.room_layout(parent)
	var socket: Dictionary = layout.sockets.filter(func(s): return s.portal == pid)[0]
	var at: Vector2 = RoomGeometry.new(layout.cells).entry_point(socket.cell, socket.dir, 1.0)
	run.pending_bombs.append({"id": run.new_entity_id(), "room": parent, "position": [at.x, at.y], "fuse": .2, "floor": run.floor_number})
	game.player.position = Vector3(0, 0, 2)
	step(.5)
	check(run.portals[pid].state == "open", "a bomb in an unloaded room still opens its seam from saved state")
	check(run.pending_bombs.is_empty(), "the offscreen bomb resolves once")

func test_furniture() -> void:
	run = root.get_node("Run")
	F = load("res://scripts/dungeon/furnishing.gd")
	Items = load("res://scripts/items/item_system.gd")
	test_catalog()
	test_generation()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	await test_breakables()
	await test_detail_invariance()
	await test_spawns()
	await test_secrets()
	await test_offscreen_breach()
	game.end_run(false)
	game.queue_free()
	root.get_node("Audio").music_player.stop()
	await process_frame
	await process_frame
	print("EMBERKEEP FURNITURE TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
