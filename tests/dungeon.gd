extends SceneTree
## Multi-cell rooms: generation validity across many seeds, shared geometry,
## movement and ricochets at L bends, navigation, explicit portals, one clear
## per logical room, camera framing, light selection and the v1 save adapter.
var checks = 0
var failures = 0
var run
var catalog
var game
# Loaded at runtime: naming these classes statically in a SceneTree entry
# script compiles them before the project autoloads are registered.
var Geometry
var Generator
var Navigation
var Room
const SCREEN_RIGHT = Vector3(0.7739573, 0, -0.6332378)
const SCREEN_DOWN = Vector3(0.6332378, 0, 0.7739573)

func _initialize() -> void:
	call_deferred("test_dungeon")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

## Screen-space stick input that walks in a world direction.
func stick_for(world: Vector3) -> Vector2:
	var direction = world.normalized()
	return Vector2(direction.dot(SCREEN_RIGHT), direction.dot(SCREEN_DOWN))

func flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)

func test_dungeon() -> void:
	run = root.get_node("Run")
	catalog = root.get_node("Content")
	Geometry = load("res://scripts/dungeon/room_geometry.gd")
	Generator = load("res://scripts/dungeon/floor_generator.gd")
	Navigation = load("res://scripts/dungeon/room_navigation.gd")
	Room = load("res://scripts/world.gd")
	test_geometry()
	test_generation()
	await test_scenes()
	await test_room_validation()
	await test_legacy_migration()
	print("EMBERKEEP DUNGEON TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_geometry() -> void:
	var single = Geometry.new([Vector2i.ZERO])
	check(single.contains(Vector2(8.6, 6.6), .3) and not single.contains(Vector2(8.8, 0), .3), "1x1 keeps the original movement limits")
	var segments = single.wall_segments()
	check(segments.size() == 8, "1x1 room has two wall segments per side around its sockets")
	for segment in segments:
		var length = segment.to - segment.from
		check(is_equal_approx(length, 7.8 if segment.dir.x == 0 else 5.8), "1x1 wall segment keeps its doorway gap")
	var hall = Geometry.new([Vector2i(0, 0), Vector2i(1, 0)])
	var top = hall.wall_segments().filter(func(s): return s.dir == Vector2i(0, -1))
	check(top.size() == 3, "a 2x1 long wall is one merged run cut at both sockets")
	check(top.any(func(s): return is_equal_approx(s.from, 1.2) and is_equal_approx(s.to, 16.8)), "merged run spans the open seam")
	check(hall.contains(Vector2(9.0, 0), .3), "open seams inside one room are walkable")
	check(hall.wall_segments().all(func(s): return not (s.dir.x != 0 and is_equal_approx(s.line, 9.0))), "no wall is built on an internal seam")
	# Every L rotation keeps 18x14 cells and a proper concave notch.
	var template = catalog.record("rooms", "bend_l3")
	var shapes := {}
	for rotation in 4:
		var cells = Geometry.rotate_cells(template.cells, rotation)
		shapes[str(cells)] = true
		var low = cells[0]
		for cell in cells: low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		check(low == Vector2i.ZERO, "rotated footprint is normalised")
		var geometry = Geometry.new(cells)
		check(is_equal_approx(geometry.bounds().size.x, 36) and is_equal_approx(geometry.bounds().size.y, 28), "rotation keeps 18x14 cells, not 14x18")
		var missing = Vector2i.ZERO
		for x in 2:
			for y in 2:
				if not geometry.has_cell(Vector2i(x, y)): missing = Vector2i(x, y)
		var hole = Geometry.cell_center(missing)
		check(not geometry.contains(hole) and not geometry.contains(hole + Vector2(4, 3)), "missing quadrant is outside the room")
		for light in template.lights:
			var at = Geometry.resolve_anchor(template.cells, rotation, light)
			check(geometry.contains(at, .5), "rotated light anchor stays inside the footprint")
		check(geometry.contains(Geometry.resolve_anchor(template.cells, rotation, template.pedestal), 1.0), "rotated pedestal stays inside")
	check(shapes.size() == 4, "the L has four distinct rotations")
	var l = Geometry.new([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)])
	# Diagonal travel into the notch reports the wall actually crossed.
	check(l.exit_normal(Vector2(8, 8.5), Vector2(9.5, 8.6)) == Vector2(-1, 0), "crossing into the notch from the lower arm hits its side wall")
	check(l.exit_normal(Vector2(10, 6.5), Vector2(10.2, 7.5)) == Vector2(0, -1), "crossing into the notch from the right arm hits its top wall")
	check(l.exit_normal(Vector2(8.8, 6.8), Vector2(9.3, 7.4)) != Vector2.ZERO, "diagonal corner crossing reports a normal")
	check(l.exit_normal(Vector2(25, 0), Vector2(27.4, 0)) == Vector2(-1, 0), "outer wall normal faces inward")
	# Recovery slides along walls and never jumps across the notch.
	var kept = l.recover(Vector2(8.5, 6.5), Vector2(9.5, 7.5), .3)
	check(l.contains(kept, .3) and not (kept.x > 9 and kept.y > 7), "recovery stays out of the missing quadrant")
	check(l.recover(Vector2(5, 6.6), Vector2(5.5, 6.9), .3).x > 5.4, "recovery keeps sliding along a wall")
	check(l.contains(l.safe_point(Vector2(14, 12), .5), .5), "safe point pulls a notch spawn back inside")
	var image = l.mask_image()
	check(image.get_size() == Vector2i(2, 2) and image.get_pixel(1, 1).r < .5 and image.get_pixel(0, 1).r > .5, "footprint mask marks only real cells")
	# Navigation routes around the concave corner without cutting it.
	var nav = Navigation.new(l, .5)
	var start = Vector2(22, 0)
	var goal = Vector2(0, 18)
	check(not nav.line_clear(start, goal), "line of sight through the notch is blocked")
	var path = nav.find_path(start, goal)
	check(path.size() > 3 and path[path.size() - 1].distance_to(goal) < .01, "a path reaches the far arm")
	var previous = start
	for point in path:
		check(l.contains(point, .5) and l.contains(previous.lerp(point, .5), .45), "path stays in walkable cells")
		previous = point
	check(nav.reachable(Vector2(0, 0), Vector2(22, 0)), "every arm is reachable")

func test_generation() -> void:
	var fallbacks = 0
	var templates := {}
	var rotations := {}
	for seed_value in range(1, 161):
		for floor_number in range(1, 4):
			var floor_data = Generator.generate(seed_value, floor_number)
			if floor_data.get("fallback", false): fallbacks += 1
			var problems = Generator.validate(floor_data)
			check(problems.is_empty(), "seed %d floor %d validates: %s" % [seed_value, floor_number, "; ".join(problems)])
			for room in floor_data.rooms.values():
				templates[room.template] = true
				if room.template == "bend_l3": rotations[room.rotation] = true
			if seed_value <= 20:
				check(JSON.stringify(Generator.generate(seed_value, floor_number)) == JSON.stringify(floor_data), "generation is repeatable")
	check(fallbacks == 0, "no floor needed the single-cell fallback (%d did)" % fallbacks)
	for id in ["hearth_1x1", "hall_2x1", "hall_1x2", "great_2x2", "bend_l3"]:
		check(templates.has(id), "template appears in generated floors: " + id)
	check(rotations.size() == 4, "all four L rotations appear in generated floors")
	# The bounded fallback itself is a valid, playable floor.
	var fallback = Generator.from_legacy(Generator.legacy_rooms(5, 2))
	fallback["fallback"] = true
	check(Generator.validate(fallback).is_empty(), "known-valid fallback floor validates")

## A hand-built floor: start, an L, a 2x2 hall, and a 2x1 hall whose long wall
## has two separate doorways.
func build_test_floor() -> Dictionary:
	var floor_data = {"rooms": {}, "portals": {}, "owners": {}, "generator": 2}
	var t = func(id): return catalog.record("rooms", id)
	Generator.place_room(floor_data, t.call("hearth_1x1"), 0, Vector2i(0, 0), 900, 1)
	Generator.place_room(floor_data, t.call("bend_l3"), 0, Vector2i(1, 0), 900, 1)
	Generator.place_room(floor_data, t.call("great_2x2"), 0, Vector2i(-2, 0), 900, 1)
	Generator.place_room(floor_data, t.call("hall_2x1"), 0, Vector2i(1, 2), 900, 1)
	Generator.place_room(floor_data, t.call("hearth_1x1"), 0, Vector2i(2, 1), 900, 1)
	Generator.add_portal(floor_data, Vector2i(0, 0), Vector2i(1, 0))
	Generator.add_portal(floor_data, Vector2i(0, 0), Vector2i(-1, 0))
	Generator.add_portal(floor_data, Vector2i(1, 1), Vector2i(0, 1))
	Generator.add_portal(floor_data, Vector2i(2, 2), Vector2i(0, -1))
	for id in ["1,0", "-2,0", "1,2"]: floor_data.rooms[id].type = "combat"
	floor_data.rooms["2,1"].type = "rest"
	return floor_data

func use_floor(floor_data: Dictionary, room_id: String) -> void:
	run.rooms = floor_data.rooms
	run.portals = floor_data.portals
	run.current_room = room_id

func test_scenes() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	game.start_run("candle", 31337, false)
	game.paused = true
	var floor_data = build_test_floor()
	use_floor(floor_data, "1,0")
	run.rooms["1,0"].cleared = true
	game.enter_room(Vector3(5, 0, 3))
	var geometry = game.room.geometry
	check(geometry.cells.size() == 3, "the L builds as one logical room")
	var mask = geometry.shader_mask_values()
	check(mask.room_grid_cells == Vector2(2, 2) and mask.room_grid_origin == Vector2(-9, -7), "halo footprint mask covers the room grid")
	check(mask.room_footprint.get_image().get_pixel(1, 1).r < .5, "halo mask excludes the L's notch")
	# The player walks into every bend, corner and door without escaping.
	var targets = [Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1)]
	var escaped = 0
	for heading in targets:
		for start in [Vector3(5, 0, 3), Vector3(20, 0, 2), Vector3(2, 0, 18)]:
			game.player.place(start)
			for frame in 150:
				await physics_frame
				game.player.update_sim(1.0 / 60.0, stick_for(heading), Vector3.ZERO, false)
				var at = flat(game.player.position)
				if not geometry.contains(at, .29) or (at.x > 9 and at.y > 7): escaped += 1
	check(escaped == 0, "player never leaves the L or enters its notch (%d frames escaped)" % escaped)
	# An enemy in one arm reaches a player in the other around the bend.
	game.player.place(Vector3(2, 0, 14))
	game.player.invulnerability = 999
	var enemy = game.spawn_enemy(Vector3(14, 0, 2), "mote")
	var closest = INF
	var outside = 0
	for frame in 600:
		await physics_frame
		if not is_instance_valid(enemy) or not enemy.alive: break
		enemy.update_sim(1.0 / 60.0)
		closest = minf(closest, enemy.position.distance_to(game.player.position))
		if not geometry.contains(flat(enemy.position), .44): outside += 1
	check(closest < 1.5, "enemy routes around the L bend to the player (closest %.2f)" % closest)
	check(outside == 0, "enemy stays inside the footprint")
	if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	# Ricochets at the notch stay inside and use the struck wall.
	for heading in [Vector3(1, 0, 1), Vector3(1, 0, .3), Vector3(.3, 0, 1)]:
		var shot = game.spawn_shot(Vector3(6, .65, 4), heading.normalized(), 1, 12, {"bounce": 4, "range": 3}, Color.WHITE, true)
		var left = 0
		for frame in 90:
			await physics_frame
			if not is_instance_valid(shot) or not shot.alive: break
			shot.update_sim(1.0 / 60.0)
			if shot.alive and not geometry.contains(flat(shot.global_position), 0): left += 1
		check(left == 0, "ricochets keep projectiles inside the L")
		check(not is_instance_valid(shot) or shot.bounces < 4, "projectile actually ricocheted")
	# Portal triggers name one specific connection each.
	var l_portals: Array = run.rooms["1,0"].portals
	check(l_portals.size() == 2, "L has its two explicit doorways")
	for portal_id in l_portals:
		use_floor(floor_data, "1,0")
		game.enter_room(Vector3(5, 0, 3))
		var side = run.portal_side(portal_id, "1,0")
		var trigger = Geometry.socket_point(side.cell, side.dir) - Vector2(side.dir) * .5
		game.player.place(Vector3(trigger.x, 0, trigger.y))
		game.room.set_open(true)
		game.check_portals()
		check(game.pending_portal == portal_id, "doorway trigger identifies portal " + portal_id)
		var destination = run.other_room(portal_id, "1,0")
		game.travel(game.pending_portal)
		check(run.current_room == destination, "portal leads to its paired room")
		check(game.room.geometry.contains(flat(game.player.position), .3), "arrival is inside the destination room")
		var back = run.portal_side(portal_id, destination)
		check(flat(game.player.position).distance_to(Geometry.entry_point(back.cell, back.dir)) < .6, "arrival uses the paired entry anchor")
	# Two doors on one long wall lead to different rooms.
	var hall_portals: Array = run.rooms["1,2"].portals
	var hall_sides = hall_portals.map(func(id): return run.portal_side(id, "1,2"))
	check(hall_sides.size() == 2 and hall_sides[0].dir == hall_sides[1].dir and hall_sides[0].cell != hall_sides[1].cell,
		"2x1 hall has two doorways on the same long wall")
	check(run.other_room(hall_portals[0], "1,2") != run.other_room(hall_portals[1], "1,2"), "each doorway keeps its own destination")
	# Adjacent rooms without a portal stay separate.
	check("2,1" not in run.neighbors("1,0"), "sharing an edge does not create a doorway")
	# A 2x2 hall clears and rewards once.
	use_floor(floor_data, "-2,0")
	game.enter_room(Vector3(9, 0, 7))
	check(not game.room.open and game.enemies.size() > 4, "large room locks with a larger encounter")
	var cleared_before: int = run.cleared
	for foe in game.enemies.duplicate():
		if is_instance_valid(foe): foe.take_hit(100000, Vector3.ZERO)
	for foe in game.enemies.duplicate():
		if is_instance_valid(foe) and foe.alive: foe.take_hit(100000, Vector3.ZERO)
	game.enemies = game.enemies.filter(func(e): return is_instance_valid(e) and e.alive)
	game.clear_room()
	game.clear_room()
	check(run.cleared == cleared_before + 1, "a four-cell room counts one clear")
	game.enter_room(Vector3(9, 0, 7))
	check(game.room.open and game.enemies.is_empty(), "re-entering a cleared large room never relocks it")
	# Close framing follows through every corner and door of the large room.
	var basis: Basis = game.camera.basis
	for point in [Vector3(-8.7, 0, -6.7), Vector3(26.7, 0, -6.7), Vector3(-8.7, 0, 20.7), Vector3(26.7, 0, 20.7), Vector3(9, 0, 7), Vector3(26.7, 0, 0)]:
		game.player.place(point)
		game.update_camera(0, true)
		var view = game.get_viewport().get_visible_rect().grow(-24)
		for height in [.12, 1.25]:
			check(view.has_point(game.camera.unproject_position(point + Vector3.UP * height)), "player stays framed in the large room at %s" % point)
		check(game.camera.basis.is_equal_approx(basis), "large rooms never rotate the camera")
		check(is_equal_approx(game.camera.size, game.CAMERA_GAME_SIZE), "large rooms keep the close zoom")
	# Large rooms move a bounded pool of fill lights with hysteresis.
	check(game.room.lantern_points.size() == 8 and game.room.lamps.size() == game.room.MAX_ACTIVE_FILLS, "fill lights are a bounded pool")
	var lights = game.room.get_children().filter(func(n): return n is Light3D and n.shadow_enabled)
	check(lights.size() <= 1, "large room keeps at most one local shadow map")
	game.room.update_light_selection(Vector3(-8, 0, -6))
	var near_corner = game.room.lamp_assignment.duplicate()
	check(game.room.update_light_selection(Vector3(-7.5, 0, -5.5)) == false, "small view changes keep the same lights")
	game.room.update_light_selection(Vector3(26, 0, 20))
	check(game.room.lamp_assignment != near_corner, "lights follow the view across a large room")
	var nearest_far = game.room.lantern_points.map(func(p): return Vector2(p.x, p.z).distance_to(Vector2(26, 20))).min()
	check(game.room.lamp_assignment.any(func(i): return is_equal_approx(Vector2(game.room.lantern_points[i].x, game.room.lantern_points[i].z).distance_to(Vector2(26, 20)), nearest_far)),
		"the nearest lantern is lit")
	# Continue validates an entry anchor that a stale save placed in the notch.
	use_floor(floor_data, "1,0")
	run.entry = {"room": "1,0", "position": [20.0, 12.0]}
	game.enter_room(game.saved_entry())
	check(game.room.geometry.contains(flat(game.player.position), .5), "continue repairs an entry outside the footprint")
	# The minimap only knows visited rooms and open neighbours.
	for id in run.rooms: run.rooms[id].visited = id == "1,0"
	var known: Array = game.ui.map_rooms()
	check("1,0" in known and "0,0" in known and "1,2" in known and "2,1" not in known and "-2,0" not in known,
		"map shows the current room and its doorway neighbours only")
	game.ui.open_map("play")
	await process_frame
	check(game.ui.mode == "map" and game.paused, "full map opens as a paused view")
	game.ui.close_subscreen()
	check(game.ui.mode == "play" and not game.paused, "closing the map resumes play")
	game.return_to_title()
	game.queue_free()
	await process_frame

## Built rooms: every doorway entry is clear and reaches the pedestal, and the
## boss has a body-width route to every door.
func test_room_validation() -> void:
	var stage = Node3D.new()
	root.add_child(stage)
	for seed_value in range(1, 9):
		for floor_number in range(1, 4):
			var floor_data = Generator.generate(seed_value, floor_number)
			run.rooms = floor_data.rooms
			run.portals = floor_data.portals
			for id in floor_data.rooms:
				var room_state = floor_data.rooms[id]
				var room = Room.new()
				stage.add_child(room)
				room.build(stage, room_state)
				var nav = room.navigation(.5)
				var hub = Vector2(room.pedestal.x, room.pedestal.z) + (Vector2(0, -2.5) if room_state.type == "boss" else Vector2.ZERO)
				hub = room.geometry.safe_point(hub, .5, room.blocked_at)
				for portal_id in room_state.portals:
					var side = run.portal_side(portal_id, id)
					var entry = Geometry.entry_point(side.cell, side.dir)
					check(nav.walkable(entry), "doorway entry is clear in %s" % id)
					check(nav.reachable(entry, hub), "doorway reaches the room centre in %s" % id)
					if room_state.type == "boss":
						check(room.navigation(1.0).reachable(entry, hub), "boss has a body-width route in %s" % id)
				room.free()
	stage.free()
	await process_frame

func test_legacy_migration() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	var old_rooms = Generator.legacy_rooms(4242, 2)
	var treasure := ""
	var cleared := ""
	for key in old_rooms:
		if old_rooms[key].type == "treasure": treasure = key
		if old_rooms[key].type == "combat" and cleared == "": cleared = key
	old_rooms[treasure]["offers"] = [{"kind": "item", "id": "warm_wax", "price": 8}]
	old_rooms[cleared].cleared = true
	old_rooms[cleared].visited = true
	old_rooms[cleared]["pickups"] = [{"id": 77, "kind": "coin", "value": 3, "position": [2.0, 1.0]}]
	var rng = RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 17: rng.randf()
	var state = str(rng.state)
	var v1 = {"version": 1, "seed": 4242, "floor": 2, "rooms": old_rooms, "current_room": cleared,
		"inventory": ["warm_wax", "splinter"], "weapon": "needle", "hp": 5.0, "coins": 23, "kills": 9,
		"cleared": 4, "elapsed": 321.5, "daily": false, "rng_state": state}
	var file = FileAccess.open("user://run.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(v1))
	file.close()
	check(run.load_run(), "a version 1 run save loads")
	check(run.generator_version == Generator.LEGACY_VERSION, "migrated run keeps the legacy generator")
	check(run.rooms.size() == old_rooms.size() and run.rooms.keys().all(func(k): return old_rooms.has(k)), "room graph keys are preserved")
	for key in old_rooms:
		check(run.rooms[key].type == old_rooms[key].type and int(run.rooms[key].seed) == int(old_rooms[key].seed), "room type and seed preserved: " + key)
		check(run.rooms[key].cells.size() == 1, "legacy rooms adapt as single cells")
	check(run.rooms[treasure].offers[0].id == "warm_wax", "saved offers survive migration")
	check(str(run.rng.state) == state, "gameplay RNG state is not advanced by migration")
	check(run.hp == 5.0 and run.coins == 23 and run.inventory == ["warm_wax", "splinter"] and run.weapon_id == "needle", "health, coins, relics and weapon survive")
	var expected_portals = 0
	for key in old_rooms:
		for step in [Vector2i.RIGHT, Vector2i.DOWN]:
			if old_rooms.has(Generator.key_of(Generator.legacy_coord(key) + step)): expected_portals += 1
	check(run.portals.size() == expected_portals, "every v1 neighbour pair keeps its implied doorway")
	check(Generator.validate({"rooms": run.rooms, "portals": run.portals, "generator": 1}).is_empty(), "migrated floor validates")
	game.continue_run()
	check(game.ui.mode == "play" and game.room.geometry.contains(flat(game.player.position), .3), "migrated run continues inside its saved room")
	check(game.pickups.any(func(p): return p.drop_id == 77), "saved drops are restored after migration")
	run.save_run()
	var saved = JSON.parse_string(FileAccess.get_file_as_string("user://run.json"))
	check(int(saved.version) == run.SAVE_VERSION and int(saved.generator) == Generator.LEGACY_VERSION, "re-saved run is v2 and pins the legacy generator")
	run.next_floor()
	check(run.rooms.values().all(func(room): return room.cells.size() == 1), "later floors of a legacy run use the legacy generator")
	var legacy_next = Generator.legacy_rooms(4242, 3)
	check(run.rooms.size() == legacy_next.size() and run.rooms.keys().all(func(k): return legacy_next.has(k)), "legacy floor layout is identical to v1")
	game.start_run("candle", 99, false)
	check(run.generator_version == Generator.VERSION, "new runs use generator v2")
	game.end_run(false)
	game.queue_free()
	await process_frame
