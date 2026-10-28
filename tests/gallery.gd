extends SceneTree
## Phase 6 gate: the twelve-painting collection and the Paint Sprayer.
## Eleven unique works stay locked, the twelfth unlocks once, every
## acquisition path respects the gate, and adding artwork never relocks it.
var checks = 0
var failures = 0
var run
var game
var content
var G
var W

func _initialize() -> void:
	call_deferred("test_gallery")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func ids() -> Array:
	return content.get_def("collections", "world_classics_12_v1").paintings

func reset_profile() -> void:
	run.profile.paintings = []
	run.profile.unlocks = []
	run.save_profile()

func test_catalog() -> void:
	check(content.errors.is_empty(), "the painting catalog validates: " + ", ".join(content.errors))
	check(ids().size() == 12, "the founding collection requires exactly twelve works")
	var unique := {}
	for id in ids(): unique[id] = true
	check(unique.size() == 12, "the twelve works are distinct")
	check(content.get_def("collections", "world_classics_12_v1").unlocks.weapon == "paint_sprayer", "the collection unlocks the Paint Sprayer")
	var problems: Array[String] = []
	content._validate_collections(problems, {"id": "x", "paintings": ["mona_lisa", "nope"], "unlocks": {"weapon": "laser"}})
	check(problems.size() == 2, "collections reject missing works and weapons")
	for id in ids():
		var record: Dictionary = content.get_def("paintings", id)
		check(record.aspect > 0 and record.caption.length() > 20, id + ": has an aspect and an original caption")

## Shipped images must match their recorded provenance exactly.
func test_images() -> void:
	var pending: Array = []
	for id in ids():
		var record: Dictionary = content.get_def("paintings", id)
		var path: String = record.image
		if not FileAccess.file_exists(path):
			pending.append(id)
			check(not record.has("provenance"), id + ": no provenance is claimed for a missing image")
			continue
		var bytes := FileAccess.get_file_as_bytes(path)
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(bytes)
		check(hashing.finish().hex_encode() == record.provenance.sha256, id + ": shipped bytes match the recorded SHA-256")
		var image := Image.new()
		check(image.load(ProjectSettings.globalize_path(path)) == OK, id + ": image decodes")
		check(absf(float(image.get_width()) / image.get_height() - record.aspect) < .01 * record.aspect, id + ": recorded aspect matches the image")
		check(maxi(image.get_width(), image.get_height()) <= 1100, id + ": wall texture stays near 1024 px")
		check(record.provenance.rights.license != "" or record.provenance.rights.usage_terms != "", id + ": a rights statement is recorded")
	print("PAINTING IMAGES PENDING IMPORT: %d (%s)" % [pending.size(), ", ".join(pending)])
	for id in ids(): G.texture(id)
	check(G.resident() <= G.RESIDENT_TEXTURES, "decoded paintings stay within the residency budget")

func test_unlock_gate() -> void:
	reset_profile()
	check(not W.is_available("paint_sprayer"), "the Paint Sprayer starts locked")
	check(W.is_available("candle") and W.available().size() == content.weapons.size() - 1, "every other weapon stays available")
	for i in 11:
		var result: Dictionary = G.discover(ids()[i])
		check(result.new and result.unlocked.is_empty(), "work %d is new and unlocks nothing yet" % (i + 1))
	check(G.discover(ids()[3]).new == false and G.progress().x == 11, "a duplicate inspection does not count")
	check(not W.is_available("paint_sprayer"), "eleven unique works keep it locked")
	var last: Dictionary = G.discover(ids()[11])
	check(last.new and last.unlocked == ["paint_sprayer"], "the twelfth unlocks it")
	check(W.is_available("paint_sprayer") and run.profile.unlocks.count("paint_sprayer") == 1, "it unlocks exactly once")
	check(G.discover(ids()[11]).unlocked.is_empty(), "rediscovering never re-announces the unlock")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(run.PROFILE_PATH))
	check(saved.paintings.size() == 12 and "paint_sprayer" in saved.unlocks, "progress and unlock are saved together")
	# Later content can never enlarge the requirement for an earned weapon.
	var collection: Dictionary = content.get_def("collections", "world_classics_12_v1")
	collection.paintings.append("future_work")
	check(W.is_available("paint_sprayer"), "adding artwork never relocks the weapon")
	collection.paintings.erase("future_work")
	# A crash between the final discovery and the unlock is repaired on load.
	run.profile.unlocks = []
	run.save_profile()
	run.load_profile()
	check(W.is_available("paint_sprayer"), "profile load reconciles a missing unlock")
	# Death and new runs keep discoveries.
	game.start_run("candle", 515, false)
	await process_frame
	game.end_run(false)
	run.load_profile()
	check(run.profile.paintings.size() == 12, "discoveries survive death and a new run")

func test_acquisition_paths() -> void:
	reset_profile()
	game.start_run("paint_sprayer", 616, false)
	await process_frame
	check(run.weapon_id == "candle", "a locked weapon cannot start a run")
	game.start_run("paint_sprayer", run.daily_seed(), true)
	await process_frame
	check(run.weapon_id == "candle", "a locked weapon cannot start a daily run")
	var ui = game.ui
	ui.starter_index = 0
	for i in 30:
		ui.cycle_weapon(1)
		check(content.weapons[ui.starter_index].id != "paint_sprayer", "starter cycling skips the locked weapon")
	var offered := {}
	for seed_value in range(1, 60):
		game.start_run("candle", seed_value, false)
		var data: Dictionary = run.rooms[run.current_room]
		data.type = "shop"
		data.erase("offers")
		game.ensure_offers()
		for offer in data.offers:
			if offer.kind == "weapon": offered[offer.id] = true
	check(not offered.has("paint_sprayer") and offered.size() > 3, "shops and rewards never offer a locked weapon")
	check(run.grant_all_relics() > 0 and run.profile.paintings.is_empty() and not W.is_available("paint_sprayer"), "ALLRELICS stays passive-only")
	# A saved run that already holds the weapon still loads.
	run.weapon_id = "paint_sprayer"
	run.save_run()
	check(run.load_run() and run.weapon_id == "paint_sprayer", "existing saved equipment stays loadable")
	for id in ids(): G.discover(id)
	offered = {}
	for seed_value in range(1, 120):
		game.start_run("candle", seed_value, false)
		var data: Dictionary = run.rooms[run.current_room]
		data.type = "shop"
		data.erase("offers")
		game.ensure_offers()
		for offer in data.offers:
			if offer.kind == "weapon": offered[offer.id] = true
	check(offered.has("paint_sprayer"), "once unlocked, shops can offer it")
	game.start_run("paint_sprayer", 717, false)
	await process_frame
	check(run.weapon_id == "paint_sprayer", "once unlocked, it can start a run")

func guaranteed_room() -> String:
	for key in run.rooms:
		if run.rooms[key].get("gallery") == "guaranteed" and run.rooms[key].has("painting"): return key
	return ""

func test_distribution() -> void:
	reset_profile()
	run.generator = run.GENERATOR_V2
	run.daily = false
	for seed_value in range(1, 80):
		run.seed_value = seed_value
		run.assigned_paintings = {}
		for floor_value in range(1, 4):
			run.floor_number = floor_value
			run.generate_floor()
			var key := guaranteed_room()
			check(key != "" and run.rooms[key].type != "secret" and run.rooms[key].type != "boss", "seed %d floor %d: one accessible painting" % [seed_value, floor_value])
			var guaranteed: Array = run.rooms.keys().filter(func(k): return run.rooms[k].get("gallery") == "guaranteed")
			check(guaranteed.size() == 1, "seed %d floor %d: exactly one guaranteed slot" % [seed_value, floor_value])
	# Four completed runs, inspecting each guaranteed painting, finish the set.
	reset_profile()
	for run_index in 4:
		run.seed_value = 9000 + run_index * 13
		run.assigned_paintings = {}
		for floor_value in range(1, 4):
			run.floor_number = floor_value
			run.generate_floor()
			G.discover(run.rooms[guaranteed_room()].painting)
	check(G.progress().x == 12, "four completed runs are enough to find all twelve (%d)" % G.progress().x)
	# Collection progress never changes layout, enemies or loot.
	reset_profile()
	run.seed_value = 4321
	run.floor_number = 2
	run.assigned_paintings = {}
	run.generate_floor()
	var fresh := strip_art(run.rooms)
	var fresh_art: String = run.rooms[guaranteed_room()].painting
	for id in ids().slice(0, 7): run.profile.paintings.append(id)
	run.assigned_paintings = {}
	run.generate_floor()
	check(JSON.stringify(strip_art(run.rooms)) == JSON.stringify(fresh), "progress never changes the floor itself")
	check(run.rooms[guaranteed_room()].painting not in ids().slice(0, 7), "guaranteed slots prefer unseen works")
	# Daily runs follow a fixed schedule, not the profile.
	run.daily = true
	run.generate_floor()
	var daily_art: String = run.rooms[guaranteed_room()].painting
	reset_profile()
	run.generate_floor()
	check(run.rooms[guaranteed_room()].painting == daily_art, "the daily schedule ignores collection progress")
	run.daily = false
	# Optional secret galleries never drain later floors' pool.
	var secret_galleries := 0
	for seed_value in range(1, 120):
		run.seed_value = seed_value
		run.floor_number = 1
		run.assigned_paintings = {}
		run.generate_floor()
		for key in run.rooms:
			if run.rooms[key].get("gallery") == "optional" and run.rooms[key].has("painting"):
				secret_galleries += 1
		check(run.assigned_paintings.size() == 1, "only the guaranteed slot is reserved from later floors")
	check(secret_galleries > 10, "secret galleries add optional chances (%d)" % secret_galleries)

func strip_art(rooms: Dictionary) -> Dictionary:
	var copy: Dictionary = rooms.duplicate(true)
	for key in copy: copy[key].erase("painting")
	return copy

func test_inspection() -> void:
	reset_profile()
	game.start_run("candle", 2024, false)
	await process_frame
	var key := guaranteed_room()
	var id: String = run.rooms[key].painting
	run.current_room = key
	run.rooms[key].cleared = true
	game.paused = false
	game.enter_room(Vector3.ZERO)
	await process_frame
	check(game.room.has_node("Painting"), "the painting hangs on its mount")
	var canvas: MeshInstance3D = game.room.get_node("Painting/Canvas")
	var shown: Vector2 = canvas.mesh.size
	check(absf(shown.x / shown.y - content.get_def("paintings", id).aspect) < .01, "the wall canvas keeps the work's proportions")
	var target := "painting:" + key
	check(not game.interactions.get_target(target).is_empty(), "a cleared room offers the painting")
	var view: Vector2 = load("res://scripts/dungeon/furnishing.gd").view_point(run.rooms[key].mount)
	game.player.position = Vector3(view.x, 0, view.y)
	check(game.perform_action({"type": "Interact", "target": target}).ok, "the painting can be inspected")
	check(game.ui.mode == "painting" and game.paused, "inspection opens the viewer and pauses")
	check(G.is_discovered(id), "inspection records the discovery")
	await process_frame
	game.ui.close_painting()
	check(game.ui.mode == "play" and not game.paused, "closing the viewer resumes play")
	var progress: Vector2i = G.progress()
	game.perform_action({"type": "Interact", "target": target})
	check(G.progress() == progress and not game.ui.painting_result.new, "a second inspection adds nothing")
	game.ui.close_painting()
	run.save_run()
	game.continue_run()
	await process_frame
	check(run.rooms[key].painting == id, "revisiting never rerolls the assigned work")
	game.ui.show_screen("journal")
	game.ui.show_screen("gallery")
	await process_frame
	check(game.ui.mode == "gallery", "the collection page opens from the journal")
	game.ui.show_screen("play")

func test_sprayer() -> void:
	for id in ids(): G.discover(id)
	game.start_run("paint_sprayer", 333, false)
	await process_frame
	game.paused = false
	var before: int = game.shots.size()
	var pigments: Array = content.weapon_by_id.paint_sprayer.pigments
	var seen: Array = []
	for i in 3:
		var count: int = game.shots.size()
		game.player.fire()
		var shot = game.shots.back()
		seen.append(shot.tint.to_html(false))
		var effect: String = pigments[i].effects.keys()[0]
		check(float(shot.stats.get(effect, 0)) >= float(pigments[i].effects[effect]), "pigment %s applies %s" % [pigments[i].name, effect])
	check(seen == pigments.map(func(p): return Color(p.color).to_html(false)), "pigments cycle red, blue, green in order")
	check(run.pigment_index == 3, "the pigment cycle is gameplay state")
	run.save_run()
	run.pigment_index = 0
	run.load_run()
	check(run.pigment_index == 3, "the pigment cycle survives save and load")
	# Friendly volleys never starve enemy attacks.
	for i in 300:
		game.spawn_shot(Vector3(0, .6, 0), Vector3.RIGHT, 1, 1, {}, Color.WHITE, true)
	var friendly: int = game.shots.filter(func(s): return is_instance_valid(s) and s.friendly).size()
	check(friendly <= 160, "friendly shots stop at their share of the cap (%d)" % friendly)
	check(game.spawn_shot(Vector3(0, .6, 0), Vector3.LEFT, 1, 1, {}, Color.RED, false) != null, "enemies can still fire at maximum friendly volume")

func test_gallery() -> void:
	run = root.get_node("Run")
	content = root.get_node("Content")
	G = load("res://scripts/gallery/gallery.gd")
	W = load("res://scripts/items/weapon_availability.gd")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	test_catalog()
	test_images()
	await test_unlock_gate()
	await test_acquisition_paths()
	test_distribution()
	await test_inspection()
	await test_sprayer()
	reset_profile()
	game.end_run(false)
	game.queue_free()
	root.get_node("Audio").music_player.stop()
	await process_frame
	await process_frame
	print("EMBERKEEP GALLERY TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
