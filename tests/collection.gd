extends SceneTree
## The painting collection: provenance, placement and distribution, the
## permanent journal, the twelve-painting unlock and every Paint Sprayer gate.
var checks = 0
var failures = 0
var run
var catalog
var collection
var game
var Library
var unlock_signals = 0

func _initialize() -> void:
	call_deferred("test_collection")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func test_collection() -> void:
	run = root.get_node("Run")
	catalog = root.get_node("Content")
	collection = root.get_node("Collection")
	Library = load("res://scripts/progression/painting_library.gd")
	collection.unlocked.connect(func(_weapon): unlock_signals += 1)
	test_catalog()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	reset_profile()
	test_placement()
	test_four_runs()
	test_daily()
	reset_profile()
	test_weapon_gates_locked()
	await test_viewer()
	test_unlock_boundary()
	test_weapon_gates_unlocked()
	test_sprayer()
	game.end_run(false)
	game.queue_free()
	await process_frame
	print("EMBERKEEP COLLECTION TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func reset_profile() -> void:
	run.profile.paintings = []
	run.profile.unlocks = []
	run.save_profile()

func required() -> Array:
	return catalog.record("collections", collection.FOUNDING).paintings

func rejected(family: String, records: Array, label: String) -> void:
	catalog.errors = PackedStringArray()
	catalog.ingest(family, records)
	var problems: PackedStringArray = catalog.errors
	problems.append_array(catalog.validate())
	check(not problems.is_empty(), "validator rejects " + label)
	catalog.load_catalog()

func test_catalog() -> void:
	check(required().size() == 12, "the founding collection holds twelve works")
	check("woman_with_parasol" in required() and "water_lilies_1906" not in required(), "unverified Water Lilies is replaced by its documented fallback")
	for id in required():
		var painting = catalog.record("paintings", id)
		check(painting.verification == "observed" and painting.record_url.begins_with("https://") and painting.source.page.begins_with("https://"),
			"provenance recorded for " + id)
		check(not painting.caption.is_empty() and not painting.credit.is_empty() and not painting.rights.is_empty(), "caption, credit and rights for " + id)
	check(catalog.record("paintings", "last_supper").medium.contains("wall painting"), "the Last Supper is labelled as a wall painting")
	var base = catalog.record("paintings", "mona_lisa").duplicate(true)
	var unsourced = base.duplicate(true)
	unsourced.record_url = ""
	rejected("paintings", [unsourced], "paintings without an institutional record")
	var no_page = base.duplicate(true)
	no_page.source = {"type": "commons"}
	rejected("paintings", [no_page], "paintings without a reproduction source")
	var unhashed = base.duplicate(true)
	unhashed.asset.status = "imported"
	rejected("paintings", [unhashed], "imported files without hashes and dimensions")
	var cropped = base.duplicate(true)
	cropped.asset.merge({"status": "imported", "sha256_wall": "a".repeat(64), "sha256_full": "b".repeat(64), "retrieved": "2026-10-28",
		"revision": "r", "image_url": "https://example.org/x.jpg", "width": 1000, "height": 1000}, true)
	rejected("paintings", [cropped], "files whose proportions do not match the composition")
	var risky = catalog.record("collections", collection.FOUNDING).duplicate(true)
	risky.paintings = required().slice(0, 11) + ["water_lilies_1906"]
	rejected("collections", [risky], "collections that include unverified works")
	check(catalog.errors.is_empty(), "catalog restores after negative checks")

## Mount and painting assignments for the current floor.
func assignments() -> Dictionary:
	var result := {}
	for id in run.rooms:
		for mount in run.rooms[id].get("mounts", []):
			result[mount.id] = mount.painting
	return result

func guaranteed_painting() -> String:
	var ids: Array = run.rooms.keys()
	ids.sort()
	for id in ids:
		if run.rooms[id].type == "rest" and not run.rooms[id].mounts.is_empty(): return run.rooms[id].mounts[0].painting
	return ""

func test_placement() -> void:
	for seed_value in range(300, 330):
		game.start_run("candle", seed_value, false)
		for floor_number in 3:
			var pick = guaranteed_painting()
			check(pick in required(), "each floor has a guaranteed painting opportunity")
			var rest = run.rooms.values().filter(func(r): return r.type == "rest")[0]
			check(not rest.get("secret", false) and rest.id in reachable_without_secrets(), "the guaranteed painting never sits behind a secret")
			for room in run.rooms.values():
				var placed = room.get("mounts", []).map(func(m): return m.painting).filter(func(p): return p != "")
				check(placed.size() == room.get("mounts", []).size(), "every mount on the floor is filled")
				var unique := {}
				for p in placed: unique[p] = true
				check(unique.size() == placed.size(), "a room never shows the same work twice")
			if floor_number < 2: run.next_floor()
	# Assignments are stored with the rooms: reload never rerolls them.
	game.start_run("candle", 4401, false)
	var before = assignments()
	run.save_run()
	collection.discover(required()[0])
	check(run.load_run() and assignments() == before, "reloading never rerolls an assigned painting")
	# Collection progress never shifts topology, encounters or loot.
	reset_profile()
	game.start_run("candle", 4402, false)
	var fresh = strip_paintings(run.rooms)
	for id in required(): run.profile.paintings.append(id)
	game.start_run("candle", 4402, false)
	check(strip_paintings(run.rooms) == fresh, "floors are identical whatever the collection progress")
	reset_profile()

func strip_paintings(rooms: Dictionary) -> String:
	var copy = rooms.duplicate(true)
	for room in copy.values():
		for mount in room.get("mounts", []): mount.painting = ""
	return JSON.stringify(copy)

func reachable_without_secrets() -> Dictionary:
	var seen := {"0,0": true}
	var queue: Array = ["0,0"]
	while not queue.is_empty():
		for next in run.neighbors(queue.pop_front()):
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen

## Inspecting every guaranteed painting completes the twelve within four runs.
func test_four_runs() -> void:
	for attempt in 3:
		reset_profile()
		var runs = 0
		while collection.progress().x < 12 and runs < 6:
			runs += 1
			game.start_run("candle", 9000 + attempt * 31 + runs, false)
			for floor_number in 3:
				var pick = guaranteed_painting()
				check(not collection.seen(pick) or collection.progress().x == 12, "a guaranteed slot shows an unseen work while any remain")
				collection.discover(pick)
				if floor_number < 2: run.next_floor()
			game.end_run(false)
			check(collection.progress().x == mini(12, runs * 3), "a failed run keeps every inspected work")
		check(runs <= 4, "the collection completes within four runs (%d)" % runs)
	# Optional galleries add chances without draining later floors.
	reset_profile()
	game.start_run("candle", 9300, false)
	var secret_pick = ""
	for room in run.rooms.values():
		if room.get("variant", "") == "gallery" and not room.mounts.is_empty(): secret_pick = room.mounts[0].painting
	if secret_pick != "":
		check(secret_pick not in run.painting_slots, "a secret gallery's work stays in the guaranteed pool for later floors")

func test_daily() -> void:
	reset_profile()
	game.start_run("candle", 20261028, true)
	var empty_profile = []
	for floor_number in 3:
		empty_profile.append(guaranteed_painting())
		if floor_number < 2: run.next_floor()
	for id in required().slice(0, 7): run.profile.paintings.append(id)
	game.start_run("candle", 20261028, true)
	var progressed = []
	for floor_number in 3:
		progressed.append(guaranteed_painting())
		if floor_number < 2: run.next_floor()
	check(empty_profile == progressed, "the daily seed follows a fixed artwork schedule, not each profile")

func test_weapon_gates_locked() -> void:
	check(not collection.weapon_available("paint_sprayer"), "Paint Sprayer starts locked")
	var starters = collection.available_weapons().map(func(w): return w.id)
	check("paint_sprayer" not in starters and starters.size() == 10, "starter choices exclude the locked weapon")
	for step in 12: game.ui.cycle_weapon(1)
	var cycled = []
	for step in 11:
		cycled.append(game.ui.starter_weapon().id)
		game.ui.cycle_weapon(1)
	check("paint_sprayer" not in cycled, "starter cycling never reaches a locked weapon")
	game.start_run("paint_sprayer", 777, false)
	check(run.weapon_id == "candle", "a new run cannot start with a locked weapon")
	game.start_run("paint_sprayer", run.daily_seed(), true)
	check(run.weapon_id == "candle", "a daily run cannot start with a locked weapon")
	var offered := {}
	for seed_value in range(500, 540):
		game.start_run("candle", seed_value, false)
		for id in run.rooms:
			if run.rooms[id].type in ["shop", "treasure"]:
				run.current_room = id
				game.ensure_offers(run.rooms[id].type == "treasure")
				for offer in run.rooms[id].offers: offered[offer.id] = true
	check(offered.size() > 5 and not offered.has("paint_sprayer"), "shops and rewards never offer a locked weapon")
	# ALLRELICS stays passive-only.
	game.start_run("candle", 778, false)
	game.redeem_secret_code("ALLRELICS")
	check(run.profile.paintings.is_empty() and not collection.weapon_available("paint_sprayer"), "the relic code discovers no paintings and unlocks nothing")

func test_viewer() -> void:
	game.start_run("candle", 610, false)
	var rest_id = ""
	for id in run.rooms:
		if run.rooms[id].type == "rest": rest_id = id
	run.current_room = rest_id
	game.enter_room(Vector3(0, 0, 2))
	game.paused = false
	var mount: Dictionary = run.rooms[rest_id].mounts[0]
	var view: Dictionary = game.room.paintings[mount.id]
	var painting = catalog.record("paintings", mount.painting)
	check(absf(view.size.x / view.size.y - painting.aspect) < .002, "the canvas keeps the full composition's proportions")
	check(view.size.x <= mount.width and view.size.y <= mount.height, "the canvas fits its mount")
	check(Library.resident() <= Library.WALL_CACHE, "bundled image residency is bounded")
	game.player.place(Vector3(float(mount.view[0]), 0, float(mount.view[1])))
	game.update_interaction()
	check(game.interactions.focused == "painting:" + mount.id and game.interaction_text.contains("Look at"), "the painting offers an inspection prompt")
	game.interact()
	check(game.ui.mode == "painting" and game.paused, "inspection opens the paused viewer")
	check(collection.seen(painting.id) and collection.progress().x == 1, "inspection discovers the work permanently")
	check(game.ui.painting_texture == null or Library.has_image(painting.id), "the viewer shows only a bundled reproduction or the awaiting-import notice")
	game.ui.close_painting()
	check(game.ui.mode == "play" and not game.paused and game.ui.painting_texture == null, "closing resumes play and releases the large image")
	game.interact()
	game.ui.close_painting()
	check(collection.progress().x == 1 and run.profile.paintings.count(painting.id) == 1, "looking again adds no progress")
	game.ui.open_journal("pause")
	game.ui.set_journal_tab("paintings")
	await process_frame
	var slots = game.ui.content.get_children().filter(func(n): return n is Button and String(n.name).begins_with("Gallery_") and not n.is_queued_for_deletion())
	check(slots.size() == 1, "the journal opens discovered works only")
	if not slots.is_empty():
		slots[0].pressed.emit()
		check(game.ui.mode == "painting" and game.ui.painting_back == "journal", "a journal slot opens the viewer")
		game.ui.close_painting()
		check(game.ui.mode == "journal", "the viewer returns to the journal")
	game.ui.set_journal_tab("relics")
	game.ui.close_subscreen()

func test_unlock_boundary() -> void:
	reset_profile()
	unlock_signals = 0
	for id in required().slice(0, 11):
		collection.discover(id)
		collection.discover(id)
	check(collection.progress().x == 11 and not collection.weapon_available("paint_sprayer"), "eleven unique works keep the weapon locked")
	collection.discover(required()[11])
	check(collection.weapon_available("paint_sprayer") and unlock_signals == 1, "the twelfth unlocks Paint Sprayer exactly once")
	collection.discover(required()[11])
	check(unlock_signals == 1 and run.profile.unlocks.count("paint_sprayer") == 1, "duplicates never repeat the reward")
	# A crash between the last discovery and saving the unlock is repaired on load.
	run.profile.unlocks = []
	run.save_profile()
	run._ready()
	collection._ready()
	check(collection.weapon_available("paint_sprayer"), "profile load reconciles a missed unlock")
	# New artwork never enlarges the original requirement or relocks the reward.
	var extra = catalog.record("paintings", "wheat_cypresses").duplicate(true)
	extra.id = "future_work"
	catalog.ingest("paintings", catalog.families.paintings + [extra])
	check(collection.progress().y == 12 and collection.weapon_available("paint_sprayer"), "adding artwork never relocks the weapon")
	catalog.load_catalog()
	game.end_run(false)
	check(collection.weapon_available("paint_sprayer") and collection.progress().x == 12, "death and new runs keep the collection")

func test_weapon_gates_unlocked() -> void:
	check("paint_sprayer" in collection.available_weapons().map(func(w): return w.id), "the unlocked weapon joins the starters")
	game.start_run("paint_sprayer", 779, false)
	check(run.weapon_id == "paint_sprayer", "an unlocked weapon can start a run")
	run.save_run()
	run.profile.unlocks = []
	check(run.load_run() and run.weapon_id == "paint_sprayer", "a known save keeps its weapon even if the profile lost the unlock")
	run.profile.unlocks = ["paint_sprayer"]

func test_sprayer() -> void:
	game.start_run("paint_sprayer", 780, false)
	game.paused = true
	var weapon = catalog.weapon_by_id.paint_sprayer
	var colors = []
	for burst in 6:
		var before = game.shots.size()
		game.player.fire()
		colors.append(game.shots.back().tint.to_html(false))
		check(game.shots.size() - before == int(weapon.count), "each burst fires its pellets")
	check(colors == [weapon.cycle[0].color, weapon.cycle[1].color, weapon.cycle[2].color, weapon.cycle[0].color, weapon.cycle[1].color, weapon.cycle[2].color].map(func(c): return c.trim_prefix("#")),
		"pigment cycles red, blue, green deterministically")
	var foe = game.spawn_enemy(game.player.position + Vector3(2, 0, 0), "brute")
	for i in 3:
		var stats = run.projectile_stats()
		var pigment = weapon.cycle[posmod(run.pigment, 3)]
		for key in pigment.effects: stats[key] = float(stats.get(key, 0)) + float(pigment.effects[key])
		run.pigment += 1
		var shot = game.spawn_shot(foe.global_position + Vector3(0, .65, -.3), Vector3.BACK, 2.2, 0, stats, Color(pigment.color), true)
		shot.hit_enemy(foe)
	check(foe.burn_time > 0 and foe.chill_time > 0 and foe.poison_time > 0, "red burns, blue chills and green poisons through the shared status pipeline")
	run.save_run()
	var pigment_saved = run.pigment
	run.pigment = 0
	check(run.load_run() and run.pigment == pigment_saved, "pigment position is saved gameplay state")
	check(float(run.projectile_stats().get("range", 1.0)) < .7, "close range is a real tradeoff")
	var sprayer_dps = weapon.damage * weapon.count / weapon.cooldown
	var candle = catalog.weapon_by_id.candle
	check(sprayer_dps < candle.damage * candle.count / candle.cooldown * 1.3, "sustained damage stays in line with the existing weapons")
	foe.queue_free()
