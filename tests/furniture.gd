extends SceneTree
## Furniture layouts, breakables, painting mounts and secret rooms.
## Run through tools/test.sh with disposable storage.
var checks = 0
var failures = 0
var run
var catalog
var settings
var game
var Generator
var Geometry
var Navigation
var Furnish
var Visuals

func _initialize() -> void:
	call_deferred("test_furniture")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func test_furniture() -> void:
	run = root.get_node("Run")
	catalog = root.get_node("Content")
	settings = root.get_node("Settings")
	Generator = load("res://scripts/dungeon/floor_generator.gd")
	Geometry = load("res://scripts/dungeon/room_geometry.gd")
	Navigation = load("res://scripts/dungeon/room_navigation.gd")
	Furnish = load("res://scripts/dungeon/furnisher.gd")
	Visuals = load("res://scripts/dungeon/prop_visuals.gd")
	test_catalog()
	test_layouts()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	await test_detail_levels()
	await test_breakables()
	await test_secrets()
	test_occluders()
	game.end_run(false)
	game.queue_free()
	await process_frame
	print("EMBERKEEP FURNITURE TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func rejected(family: String, records: Array, label: String) -> void:
	catalog.errors = PackedStringArray()
	catalog.ingest(family, records)
	var problems: PackedStringArray = catalog.errors
	problems.append_array(catalog.validate())
	check(not problems.is_empty(), "validator rejects " + label)
	catalog.load_catalog()

func test_catalog() -> void:
	var families = catalog.families.furniture.filter(func(p): return p.id != "pillar")
	check(families.size() >= 16, "about sixteen furniture families (%d)" % families.size())
	check(Visuals.RECIPES == catalog.PROP_RECIPES, "every registered recipe has a visual")
	check(catalog.families.layouts.size() >= 6, "themed layouts: reading, storage, workshop, quarters, shrine, gallery")
	var decor = catalog.record("furniture", "book_pile").duplicate(true)
	decor.solid = true
	rejected("furniture", [decor], "solid decorative props, whose collision could vanish at Low detail")
	var odd = catalog.record("furniture", "crate").duplicate(true)
	odd.recipe = "teleporter"
	rejected("furniture", [odd], "unknown visual recipes")
	var lootless = catalog.record("furniture", "crate").duplicate(true)
	lootless.breakable = {"health": 5, "drops": "nothing_here"}
	rejected("furniture", [lootless], "breakables naming a missing drop table")
	var ghost = catalog.record("furniture", "crate").duplicate(true)
	ghost.blocks_shots = false
	rejected("furniture", [ghost], "breakables that shots cannot hit")
	rejected("layouts", [{"id": "z", "roles": ["combat"], "pieces": [{"prop": "throne", "count": [1, 1]}]}], "layouts naming missing props")
	check(catalog.errors.is_empty(), "catalog restores after negative checks")

## Data-level navigation for a generated room: walls, solid props and chests.
func room_navigation(room: Dictionary, geometry, clearance := .5):
	var blockers := {}
	for prop in room.props:
		if catalog.record("furniture", prop.kind).get("solid", false) and not prop.get("destroyed", false):
			blockers[prop.id] = Furnish.record_rect(prop)
	for chest in room.chests:
		blockers[chest.id] = Rect2(Generator.vec2(chest.position) - Vector2(.5, .33), Vector2(1.0, .66))
	return Navigation.new(geometry, clearance, blockers)

func test_layouts() -> void:
	var kinds := {}
	var themes := {}
	var variants := {}
	var rest_mounts = 0
	var rest_rooms = 0
	for seed_value in range(1, 41):
		for floor_number in range(1, 4):
			var floor_data = Generator.generate(seed_value, floor_number)
			check(Generator.validate(floor_data).is_empty(), "furnished floor validates")
			var secrets = floor_data.rooms.values().filter(func(r): return r.get("secret", false))
			check(secrets.size() == 1, "exactly one optional secret room per floor")
			for secret in secrets:
				variants[secret.variant] = true
				check(secret.portals.size() == 1 and floor_data.portals[secret.portals[0]].state == "concealed",
					"the secret room is a leaf behind one concealed passage")
				var host = floor_data.portals[secret.portals[0]]
				var host_id = host.a.room if host.b.room == secret.id else host.b.room
				check(floor_data.rooms[host_id].type != "boss", "the boss room never hides the secret")
			for id in floor_data.rooms:
				var room = floor_data.rooms[id]
				if room.has("theme"): themes[room.theme] = true
				var anchor = Generator.vec(room.anchor)
				var geometry = Geometry.new(Generator.room_cells(room).map(func(c): return c - anchor))
				var zones = Generator.reserved_zones(floor_data, room)
				var solids: Array = []
				for prop in room.props:
					kinds[prop.kind] = true
					var definition = catalog.record("furniture", prop.kind)
					var rect = Furnish.record_rect(prop)
					check(Furnish.rect_inside(geometry, rect, .04), "prop inside its room: " + prop.id)
					if definition.solid:
						check(not Furnish.hits_zone(rect, zones.filter(func(z): return z.kind not in ["lantern", "pedestal"] or prop.kind != "pillar"), true), "solid prop clear of doorways, entries, pedestal and lanterns: " + prop.id)
						for other in solids:
							check(not rect.intersects(Furnish.record_rect(other)), "solid props never overlap")
						for chest in room.chests:
							check(not rect.intersects(Rect2(Generator.vec2(chest.position) - Vector2(.6, .45), Vector2(1.2, .9))), "furniture never covers a chest")
						solids.append(prop)
					if definition.get("tall", false):
						var along_front = false
						for segment in geometry.wall_segments():
							if Geometry.is_front(segment.dir) and rect.grow(.15).intersects(Rect2(Geometry.segment_box(segment).center - Geometry.segment_box(segment).size / 2, Geometry.segment_box(segment).size)):
								along_front = true
						check(not along_front, "tall pieces stand only on rear walls: " + prop.id)
				for mount in room.get("mounts", []):
					check(not Geometry.is_front(Generator.vec(mount.dir)), "paintings hang on rear walls that stay visible")
					check(mount.width >= 1.2 and mount.height > 1.0, "mount has room for a painting")
					for prop in solids:
						check(Furnish.record_rect(prop).get_center().distance_to(Generator.vec2(mount.view)) > 1.0, "nothing solid stands in a painting's viewing spot")
				if room.type == "rest":
					rest_rooms += 1
					if not room.mounts.is_empty(): rest_mounts += 1
				# Every required object stays reachable from every doorway.
				if seed_value <= 12:
					var nav = room_navigation(room, geometry)
					var hub = geometry.safe_point(Generator.vec2(room.pedestal), .5)
					var goals: Array = []
					for chest in room.chests: goals.append(Generator.vec2(chest.position) + Vector2(0, 1.0))
					for mount in room.mounts: goals.append(Generator.vec2(mount.view))
					for portal_id in room.portals:
						var portal = floor_data.portals[portal_id]
						var side = portal.a if portal.a.room == id else portal.b
						goals.append(Geometry.entry_point(Generator.vec(side.cell) - anchor, Generator.vec(side.dir)))
					for goal in goals:
						check(nav.reachable(hub, goal), "required spot reachable in %s (seed %d)" % [id, seed_value])
	for kind in ["table", "chair", "bookcase", "bench", "cupboard", "crate", "barrel", "jar", "brazier", "wall_shelf", "book_pile", "rug", "partition", "workbench", "cot"]:
		check(kinds.has(kind), "prop family appears in generated rooms: " + kind)
	for theme in ["reading_room", "storage", "workshop", "living_quarters", "shrine", "gallery"]:
		check(themes.has(theme), "theme appears: " + theme)
	check(variants.has("cache") and variants.has("gallery"), "both secret variants appear")
	check(rest_mounts == rest_rooms, "every rest room offers a painting mount (%d of %d)" % [rest_mounts, rest_rooms])

func furnished_room(kind: String) -> String:
	for id in run.rooms:
		var room = run.rooms[id]
		if room.type == kind and room.props.any(func(p): return catalog.record("furniture", p.kind).has("breakable")):
			return id
	return ""

func test_detail_levels() -> void:
	game.start_run("candle", 61001, false)
	game.paused = true
	var room_id = ""
	for id in run.rooms:
		if run.rooms[id].props.any(func(p): return catalog.record("furniture", p.kind).detail == "decor"):
			room_id = id
			break
	check(room_id != "", "a room with decorative props exists")
	run.current_room = room_id
	run.rooms[room_id].cleared = true
	var shapes := {}
	for level in ["low", "balanced", "high"]:
		settings.set_value("small_details", level)
		game.enter_room(Vector3(0, 0, 2))
		var colliders = game.room.find_children("*", "StaticBody3D", true, false).map(func(body): return [body.global_position.snapped(Vector3.ONE * .01), body.collision_layer])
		colliders.sort()
		shapes[level] = {"colliders": colliders, "obstacles": game.room.obstacles.size(), "props": game.room.props.size(),
			"details": game.room.detail_meshes.reduce(func(total, mesh): return total + mesh.multimesh.instance_count, 0)}
	check(shapes.low.colliders == shapes.high.colliders and shapes.low.colliders == shapes.balanced.colliders, "collision is identical at every detail level")
	check(shapes.low.obstacles == shapes.high.obstacles, "navigation obstacles are identical at every detail level")
	check(shapes.low.props < shapes.high.props, "Low hides decorative pieces")
	check(shapes.low.details < shapes.high.details, "High adds small details such as book spines")
	settings.set_value("small_details", "balanced")

func test_breakables() -> void:
	game.start_run("candle", 61002, false)
	game.paused = false
	var room_id = furnished_room("combat")
	check(room_id != "", "a combat room has breakable furniture")
	run.current_room = room_id
	run.rooms[room_id].cleared = true
	game.enter_room(Vector3(0, 0, 2))
	var record: Dictionary = run.rooms[room_id].props.filter(func(p): return catalog.record("furniture", p.kind).has("breakable"))[0]
	var at = Furnish.record_rect(record).get_center()
	var nav = game.room.navigation(.5)
	check(not nav.walkable(at), "an intact breakable blocks navigation")
	var drops_before = run.rooms[room_id].get("pickups", []).size()
	# Shoot it from close range until it breaks.
	var shots = 0
	while game.room.props.has(record.id) and shots < 40:
		var from = Vector3(at.x, .65, at.y) + Vector3(0, 0, 1.6)
		var shot = game.spawn_shot(from, Vector3(0, 0, -1), 6, 20, {}, Color.WHITE, true)
		for frame in 12:
			await physics_frame
			if not is_instance_valid(shot) or not shot.alive: break
			shot.update_sim(1.0 / 60.0)
		shots += 1
	check(record.destroyed and not game.room.props.has(record.id), "friendly shots break furniture")
	check(nav.walkable(at), "breaking updates navigation once")
	check(not game.room.obstacles.any(func(o): return o.get("id", "") == record.id), "a broken prop no longer repels foes")
	var drops_after = run.rooms[room_id].get("pickups", []).size()
	game.destroy_prop(room_id, record, true)
	check(run.rooms[room_id].get("pickups", []).size() == drops_after, "a broken prop never drops twice")
	run.save_run()
	check(run.load_run(), "broken furniture saves")
	game.enter_room(Vector3(0, 0, 2))
	check(not game.room.props.has(record.id), "destroyed furniture stays destroyed after reload")
	# Loot comes from a per-prop stream, independent of fragment effects.
	var a = RandomNumberGenerator.new()
	a.seed = catalog.stable_hash("loot:%d:%d:%s" % [run.seed_value, run.floor_number, record.id])
	var expected = load("res://scripts/items/drops.gd").roll(catalog.record("furniture", record.kind).breakable.drops, a, run.stats.luck)
	check(drops_after - drops_before == expected.size(), "breakable loot is deterministic per prop")

func test_secrets() -> void:
	game.start_run("candle", 61003, false)
	game.paused = false
	var secret_id = ""
	var portal_id = ""
	for id in run.rooms:
		if run.rooms[id].get("secret", false):
			secret_id = id
			portal_id = run.rooms[id].portals[0]
	var host = run.other_room(portal_id, secret_id)
	run.rooms[host].cleared = true
	run.current_room = host
	game.enter_room(Vector3(0, 0, 2))
	clear_enemies()
	# Nothing about the secret leaks before it is found.
	for id in run.rooms: run.rooms[id].visited = id == host
	check(secret_id not in run.neighbors(host), "the hidden room is absent from neighbour lists")
	check(secret_id not in game.ui.map_rooms(), "the hidden room is absent from the map")
	check(not game.room.hidden_seam().is_empty(), "the host room has a concealed seam")
	var side = run.portal_side(portal_id, host)
	var socket = Geometry.socket_point(side.cell, side.dir)
	check(not game.room.sockets[game.room.socket_key(side.cell, side.dir)].has("gate"), "a concealed seam starts as solid wall")
	check(game.room.sockets[game.room.socket_key(side.cell, side.dir)].has("hints"), "a concealed seam shows subtle hints")
	# Bullets alone never open it.
	var shot = game.spawn_shot(Vector3(socket.x, .65, socket.y) - Vector3(side.dir.x, 0, side.dir.y) * 1.5, Vector3(side.dir.x, 0, side.dir.y), 50, 20, {}, Color.WHITE, true)
	for frame in 10:
		if is_instance_valid(shot) and shot.alive: shot.update_sim(1.0 / 60.0)
	check(run.portals[portal_id].state == "concealed", "ordinary shots never reveal a secret")
	# The Miner's Lantern points at the seam here, and only here.
	run.active_item = {"instance": "a1", "def": "miners_lantern"}
	run.cooldowns = {"miners_lantern": 0.0}
	check(game.submit({"type": "use_active"}).ok and run.cooldown_remaining("miners_lantern") > 0, "Miner's Lantern hints at a nearby seam")
	check(run.portals[portal_id].state == "concealed", "a hint does not open the wall")
	# A bomb against the seam reveals it for good.
	var inside = socket - Vector2(side.dir) * .9
	game.player.place(Vector3(inside.x, 0, inside.y))
	run.bombs = 2
	game.submit({"type": "place_bomb"})
	game.player.place(Vector3(0, 0, 2))
	for frame in 120:
		game._physics_process(1.0 / 60.0)
		if run.pending_bombs.is_empty(): break
	check(run.portals[portal_id].state == "revealed", "a bomb reveals the concealed passage")
	var opened = game.room.sockets[game.room.socket_key(side.cell, side.dir)]
	check(opened.state == "revealed" and opened.has("gate"), "the wall becomes a doorway in the live room")
	check(not is_instance_valid(opened.walls.collider) or opened.walls.collider.is_queued_for_deletion(), "the plug's collision is removed with it")
	check(secret_id in run.neighbors(host) and secret_id in game.ui.map_rooms(), "a revealed room appears on the map")
	var saved = JSON.parse_string(FileAccess.get_file_as_string("user://run.json"))
	check(saved.portals[portal_id].state == "revealed", "the reveal is saved with the blast")
	check(run.load_run(), "revealed floor reloads")
	game.enter_room(Vector3(0, 0, 2))
	check(game.room.sockets[game.room.socket_key(side.cell, side.dir)].state == "revealed", "reloading never reseals an opened wall")
	game.travel(portal_id)
	check(run.current_room == secret_id and game.room.open, "the secret room is enterable and safe")
	var room = run.rooms[secret_id]
	if room.variant == "cache":
		check(room.chests.size() == 1 and not room.chests[0].locked, "a cache holds an unlocked chest")
		game.actions.open_chest(room.chests[0].id)
		check(room.chests[0].opened, "the cache opens")
		run.load_run()
		game.enter_room(Vector3(0, 0, 2))
		check(run.rooms[secret_id].chests[0].opened, "reloading never replenishes the cache")
	else:
		check(room.mounts.size() >= 1, "a forgotten gallery has painting mounts")
	# Offscreen: a bomb left at another floor's seam still opens it.
	game.start_run("candle", 61004, false)
	game.paused = false
	for id in run.rooms:
		if run.rooms[id].get("secret", false):
			secret_id = id
			portal_id = run.rooms[id].portals[0]
	host = run.other_room(portal_id, secret_id)
	run.rooms[host].cleared = true
	run.current_room = host
	game.enter_room(Vector3(0, 0, 2))
	clear_enemies()
	side = run.portal_side(portal_id, host)
	inside = Geometry.socket_point(side.cell, side.dir) - Vector2(side.dir) * .9
	game.player.place(Vector3(inside.x, 0, inside.y))
	game.submit({"type": "place_bomb"})
	var away = run.neighbors(host)[0]
	run.current_room = away
	run.rooms[away].cleared = true
	game.enter_room(Vector3(0, 0, 2))
	for frame in 150: game._physics_process(1.0 / 60.0)
	check(run.portals[portal_id].state == "revealed", "an offscreen bomb reveals the seam from saved state")
	run.current_room = host
	game.enter_room(Vector3(0, 0, 2))
	check(game.room.sockets[game.room.socket_key(side.cell, side.dir)].has("gate"), "returning finds the offscreen reveal")

func clear_enemies() -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()

func test_occluders() -> void:
	var stage = Node3D.new()
	root.add_child(stage)
	var room = load("res://scripts/world.gd").new()
	stage.add_child(room)
	var record = {"id": "t:f0", "kind": "partition", "position": [0.0, 0.0], "rotation": 0, "size": [2.4, .3]}
	room.build(stage, {"type": "combat", "seed": 2, "cells": [[0, 0]], "anchor": [0, 0], "props": [record], "chests": [], "lights": [], "pedestal": [0, 4]})
	check(room.occluders.size() == 1, "free-standing tall pieces can cut away")
	var collider_before = room.props["t:f0"].base.get_child(0).global_transform
	room.update_wall_visibility(Vector3(0, 0, -1.2), 0, [])
	check(room.occluders[0].node.scale.y < .5, "a piece lowers when an actor stands behind it")
	check(room.props["t:f0"].base.get_child(0).global_transform == collider_before, "its collision never moves")
	room.update_wall_visibility(Vector3(0, 0, 3), 0, [])
	check(is_equal_approx(room.occluders[0].node.scale.y, 1.0), "it recovers when nothing is hidden")
	stage.free()
