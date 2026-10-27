extends SceneTree
## Phase 1 foundations: catalog validation, save migration, the interaction
## registry and the single validated action path.
var checks = 0
var failures = 0
var run
var catalog
var game

func _initialize() -> void:
	call_deferred("test_foundation")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func write_json(path: String, value) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func has_problem(fragment: String) -> bool:
	return catalog.errors.any(func(message): return message.contains(fragment))

func test_catalog() -> void:
	check(catalog.errors.is_empty(), "shipped catalog validates cleanly: " + ", ".join(catalog.errors))
	DirAccess.make_dir_recursive_absolute("user://fixture/content")
	write_json("user://fixture/data.json", {"items": [
		{"id": "ok_relic", "rarity": "common", "effects": {"damage": .1}},
		{"id": "ok_relic", "rarity": "common", "effects": {}},
		{"id": "Bad Id", "rarity": "common", "effects": {}},
		{"id": "odd_relic", "rarity": "legendary", "effects": {"teleport": 1}}],
		"weapons": [{"id": "wand", "damage": -1, "cooldown": .2, "speed": 10, "count": 1, "spread": 0, "effects": {"warp": 1}}]})
	write_json("user://fixture/content/pickups.json", {"pickups": [{"id": "coin"}, {"id": "coin"}, {"name": "no id"}]})
	write_json("user://fixture/content/rooms.json", {"wrong_key": []})
	catalog.load_catalog("user://fixture/data.json", "user://fixture/content")
	check(has_problem("duplicate relic id: ok_relic"), "duplicate relic IDs are rejected")
	check(has_problem("malformed id: Bad Id"), "malformed IDs are rejected")
	check(has_problem("unknown rarity"), "unknown rarities are rejected")
	check(has_problem("unknown effect teleport"), "unknown relic effects are rejected")
	check(has_problem("weapon wand has invalid damage"), "impossible weapon values are rejected")
	check(has_problem("unknown effect warp"), "unknown weapon effects are rejected")
	check(has_problem("duplicate pickups id: coin"), "duplicate family IDs are rejected")
	check(has_problem("pickups has missing or malformed id"), "family records need IDs")
	check(has_problem("rooms: file must contain"), "a malformed family file is reported")
	catalog.load_catalog()
	check(catalog.errors.is_empty() and catalog.items.size() == 60, "the real catalog reloads cleanly")
	var presets = FileAccess.get_file_as_string("res://export_presets.cfg")
	var include_lines = presets.split("\n") as Array
	include_lines = include_lines.filter(func(line): return line.begins_with("include_filter="))
	check(include_lines.size() == 3, "every export preset declares packaged data")
	for line in include_lines:
		check(line.contains("content/*.json") and line.contains("assets/data.json"), "export preset packages canonical content: " + line)

func test_migration() -> void:
	run.seed_value = 7777
	run.floor_number = 2
	run.generate_floor()
	var rooms_v1: Dictionary = run.rooms.duplicate(true)
	var some_room: String = rooms_v1.keys()[1]
	rooms_v1[some_room]["pickups"] = [{"id": 1234, "kind": "coin", "value": 3, "position": [1.0, 2.0]}]
	var rng = RandomNumberGenerator.new()
	rng.seed = 7777
	for i in 13: rng.randf()
	var v1 = {"version": 1, "seed": 7777, "floor": 2, "rooms": rooms_v1, "current_room": "0,0",
		"inventory": ["warm_wax"], "weapon": "needle", "hp": 4.5, "coins": 21, "kills": 9, "cleared": 3,
		"elapsed": 120.0, "daily": false, "rng_state": str(rng.state)}
	write_json(run.SAVE_PATH, v1)
	run.rooms = {}
	check(run.load_run(), "version 1 run save loads through the migration adapter")
	check(JSON.stringify(run.rooms) == JSON.stringify(JSON.parse_string(JSON.stringify(rooms_v1))), "legacy floor graph, room state and drops are preserved")
	check(str(run.rng.state) == str(rng.state), "migration does not advance gameplay RNG")
	check(run.generator == run.GENERATOR_LEGACY, "legacy saves keep the legacy generator")
	check(run.coins == 21 and is_equal_approx(run.hp, 4.5) and run.weapon_id == "needle" and run.inventory == ["warm_wax"], "resources and equipment survive migration")
	check(run.keys == 0 and run.bombs == 0 and run.wards == 0 and run.active_item.is_empty(), "new resources default safely")
	check(run.next_entity >= 1234, "new drop IDs cannot collide with migrated drops")
	check(run.new_entity_id() > 1234, "the next stable ID follows the highest saved one")
	run.active = true
	run.save_run()
	var saved = JSON.parse_string(FileAccess.get_file_as_string(run.SAVE_PATH))
	check(int(saved.version) == run.SAVE_VERSION and int(saved.generator) == run.GENERATOR_LEGACY, "re-saving writes the current version and keeps the generator")
	write_json(run.SAVE_PATH, {"version": 99, "seed": 1})
	check(not run.load_run(), "an unknown future save version is refused")
	var broken = v1.duplicate(true)
	broken.version = 2
	write_json(run.SAVE_PATH, broken)
	check(not run.load_run(), "a version 2 save missing its new fields is refused")
	run.active = false
	DirAccess.remove_absolute(run.SAVE_PATH)

func test_registry() -> void:
	var registry = InteractionRegistry.new()
	registry.register("painting_a", "painting", Vector3(.5, 0, 0), "Inspect")
	registry.register("exit", "exit", Vector3(1.4, 0, 0), "Descend")
	check(registry.select(Vector3.ZERO).id == "exit", "a decorative painting never steals the exit prompt")
	registry.unregister("exit")
	check(registry.select(Vector3.ZERO).id == "painting_a", "the painting becomes available alone")
	registry.register("painting_b", "painting", Vector3(-.5, 0, 0), "Inspect")
	registry.focused_id = ""
	check(registry.select(Vector3.ZERO).id == "painting_a", "equal-distance ties resolve deterministically by ID")
	check(registry.select(Vector3(-.2, 0, 0)).id == "painting_a", "hysteresis keeps a nearly-equal focus")
	check(registry.select(Vector3(-1.4, 0, 0)).id == "painting_b", "focus moves once the other target is clearly better")
	check(registry.select(Vector3(20, 0, 0)).is_empty() and registry.focused_id == "", "nothing is focused out of range")
	check(registry.select(Vector3.ZERO, func(target): return target.id == "painting_a").id == "painting_b", "obstructed targets are skipped")

func test_actions() -> void:
	var actions = GameActions.new()
	var counter = {"n": 0}
	actions.register("Poke", func(_action): counter.n += 1; return GameActions.ok())
	check(not actions.perform({"type": "Teleport"}).ok, "unknown actions fail validation")
	check(actions.perform({"type": "Poke", "event_id": "e1"}).ok and counter.n == 1, "an action applies once")
	check(actions.perform({"type": "Poke", "event_id": "e1"}).reason == "duplicate_event" and counter.n == 1, "a repeated event ID is ignored")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	game.start_run("candle", 99001, false)
	game.spawn_pickup(Vector3(1, 0, 1), "coin", 4)
	var drop_id: int = game.pickups.back().drop_id
	var coins: int = run.coins
	check(game.perform_action({"type": "CollectPickup", "drop_id": drop_id}).ok and run.coins == coins + 4, "collecting a pickup grants its value")
	check(not game.perform_action({"type": "CollectPickup", "drop_id": drop_id}).ok and run.coins == coins + 4, "a pickup cannot be collected twice")
	check(not run.rooms[run.current_room].get("pickups", []).any(func(d): return int(d.id) == drop_id), "the persistent drop record is removed")
	run.hp = run.stats.max_hp
	game.spawn_pickup(Vector3(1, 0, 1), "heart", 1)
	var heart_id: int = game.pickups.back().drop_id
	check(game.perform_action({"type": "CollectPickup", "drop_id": heart_id}).reason == "not_useful", "a heart at full health stays on the ground")
	game.make_marker("rest", Vector3(5, 0, 0))
	game.player.position = Vector3.ZERO
	check(game.perform_action({"type": "Interact", "target": game.marker.get_meta("target_id")}).reason == "out_of_range", "interaction validates range")
	game.player.position = Vector3(5, 0, 0)
	run.hp = 1
	var rest_target = game.marker.get_meta("target_id")
	check(game.perform_action({"type": "Interact", "target": rest_target}).ok and run.hp == 4, "a valid interaction applies")
	check(not game.perform_action({"type": "Interact", "target": rest_target}).ok and run.hp == 4, "a claimed rest cannot heal twice")
	game.player.position = Vector3.ZERO
	var before = run.coins
	run.hp = 1
	game.spawn_pickup(Vector3(0, 0, 0), "heart", 1)
	root.get_node("Session").submit({"type": "CollectPickup", "drop_id": game.pickups.back().drop_id})
	check(run.hp == 2 and run.coins == before, "transport commands use the same handlers")
	game.end_run(false)
	game.queue_free()
	await process_frame

func test_foundation() -> void:
	run = root.get_node("Run")
	catalog = root.get_node("Content")
	test_catalog()
	test_migration()
	test_registry()
	await test_actions()
	root.get_node("Audio").music_player.stop()
	await process_frame
	print("EMBERKEEP FOUNDATION TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
