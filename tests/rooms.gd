extends SceneTree
## Phase 2 gate: real multi-cell rooms, explicit portals, navigation, camera,
## minimap and footprint clipping. No live saves are touched (see tools/test.sh).
var checks = 0
var failures = 0
var run
var game
const DT = 1.0 / 60.0

func _initialize() -> void:
	call_deferred("test_rooms")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

## A mirror of the halo shader's footprint mask, evaluated on the CPU.
func shader_mask(rects: PackedVector4Array, p: Vector2) -> float:
	var best = 0.0
	for r in rects:
		var low = Vector2(smoothstep(r.x, r.x + .15, p.x), smoothstep(r.y, r.y + .15, p.y))
		var high = Vector2(1.0 - smoothstep(r.z - .15, r.z, p.x), 1.0 - smoothstep(r.w - .15, r.w, p.y))
		best = maxf(best, low.x * low.y * high.x * high.y)
	return best

func test_geometry() -> void:
	var l = RoomGeometry.new([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)])
	check(l.contains(Vector2(0, 0), .4) and l.contains(Vector2(18, 0), .4) and l.contains(Vector2(0, 14), .4), "L footprint contains each cell")
	check(l.contains(Vector2(9, 0), .4) and l.contains(Vector2(0, 7), .4), "open seams inside one room are walkable")
	check(not l.contains(Vector2(18, 14), 0) and not l.contains(Vector2(12, 10), 0), "the missing quadrant is void")
	check(not l.contains(Vector2(9.2, 7.2), .3), "the concave corner keeps clearance")
	check(l.contains(Vector2(8.6, 6.6), .3), "space beside the concave corner remains usable")
	var safe = l.nearest_inside(Vector2(12, 10), .4)
	check(l.contains(safe, .4) and safe.distance_to(Vector2(12, 10)) < 4.0, "recovery from the void lands on the nearest floor")
	check(not l.segment_clear(Vector2(18, 0), Vector2(0, 14)), "a straight line across the void is not walkable")
	check(l.segment_clear(Vector2(18, 0), Vector2(0, 0)), "a line along one arm is walkable")
	check(l.boundary_normal(Vector2(18, 7.3)) == Vector2(0, -1), "a projectile leaving the long arm bounces back inward")
	check(l.boundary_normal(Vector2(9.3, 12)) == Vector2(-1, 0), "the inner wall of the short arm bounces back inward")
	check(l.exposed_sides().size() == 8, "an L of three cells has eight exposed cell sides")
	var rects = l.shader_rects()
	check(shader_mask(rects, Vector2(15, 11)) == 0.0, "glows are clipped inside the missing quadrant")
	check(shader_mask(rects, Vector2(9, 0)) > .99 and shader_mask(rects, Vector2(0, 7)) > .99, "glows are seamless across internal seams")
	check(shader_mask(rects, Vector2(27.2, 0)) == 0.0 and shader_mask(rects, Vector2(-9.1, 0)) == 0.0, "glows stop at the outer walls")
	var nav = RoomNavigation.new(l, [])
	var path = nav.find_path(Vector2(18, 0), Vector2(0, 14))
	check(path.size() > 3, "navigation finds a route around the L bend")
	var route_ok = true
	var previous = Vector2(18, 0)
	for point in path:
		if not l.segment_clear(previous, point, .3, .25): route_ok = false
		previous = point
	check(route_ok, "every path leg stays on the floor")

func floor_ok(label: String) -> void:
	var owners = {}
	var total_cells = 0
	for key in run.rooms:
		for cell in run.room_cells(key):
			total_cells += 1
			owners[cell] = key
	check(owners.size() == total_cells, label + ": no occupied-cell overlap")
	for key in run.rooms:
		var room: Dictionary = run.rooms[key]
		var template: Dictionary = root.get_node("Content").get_def("rooms", room.get("template", ""))
		check(not template.is_empty(), label + ": rooms reference real templates")
		if template.is_empty(): continue
		var expected = []
		for c in run.rotate_cells(template.cells, int(room.rotation)):
			expected.append(c + run.coord(key))
		var actual = run.room_cells(key)
		expected.sort()
		actual.sort()
		check(expected == actual, label + ": footprint matches its template rotation")
		check(room.type in template.roles, label + ": role is legal for the template")
	for pid in run.portals:
		var portal: Dictionary = run.portals[pid]
		var a = run._cell(portal.cell_a)
		var b = run._cell(portal.cell_b)
		check(owners.get(a) == portal.a and owners.get(b) == portal.b and portal.a != portal.b, label + ": portal joins the rooms that own its cells")
		check(absi(a.x - b.x) + absi(a.y - b.y) == 1, label + ": portal sockets face each other")
		check(pid in run.room_portal_ids[portal.a] and pid in run.room_portal_ids[portal.b], label + ": portal is reciprocal")
	var secrets: Array = run.rooms.keys().filter(func(k): return run.rooms[k].type == "secret")
	check(secrets.size() == 1, label + ": exactly one optional secret room")
	for hidden in [false, true]:
		var visited = {"0,0": true}
		var queue: Array = ["0,0"]
		while not queue.is_empty():
			var key: String = queue.pop_front()
			for next in run.neighbors(key, hidden):
				if not visited.has(next):
					visited[next] = true
					queue.append(next)
		if hidden:
			check(visited.size() == run.rooms.size(), label + ": the secret is reachable through its seam")
		else:
			check(visited.size() == run.rooms.size() - secrets.size() and secrets.all(func(k): return not visited.has(k)), label + ": every required room is reachable without secrets")
	for key in secrets:
		var ids: Array = run.room_portal_ids[key]
		check(ids.size() == 1 and run.portals[ids[0]].state == "concealed", label + ": a secret is a leaf behind one concealed seam")
		check(run.rooms[run.neighbors(key, true)[0]].type != "boss", label + ": secrets never hang off the boss room")
	var large = 0
	for kind in ["start", "boss", "treasure", "shop", "rest"]:
		check(run.rooms.values().filter(func(r): return r.type == kind).size() == 1, label + ": exactly one " + kind)
	for room in run.rooms.values():
		if room.cells.size() > 1: large += 1
	check(large >= 1, label + ": at least one larger room per floor")
	check(run.rooms["0,0"].type == "start", label + ": the start room is at the origin")

func test_generation() -> void:
	for seed_value in range(1, 301):
		for floor_value in range(1, 4):
			run.generator = run.GENERATOR_V2
			run.seed_value = seed_value
			run.floor_number = floor_value
			run.generate_floor()
			var label = "seed %d floor %d" % [seed_value, floor_value]
			floor_ok(label)
			var before = JSON.stringify([run.rooms, run.portals])
			run.generate_floor()
			check(JSON.stringify([run.rooms, run.portals]) == before, label + ": generation is repeatable")
	run.generator = run.GENERATOR_LEGACY
	run.seed_value = 5
	run.floor_number = 1
	run.generate_floor()
	check(run.rooms.values().all(func(r): return not r.has("cells")), "legacy runs keep generating single-cell floors")
	check(run.portals.size() > 0 and run.portals.values().all(func(p): return p.a in run.neighbors(p.b)), "legacy doors are derived from adjacency")

func find_room(template: String) -> Array:
	for seed_value in range(1, 400):
		run.generator = run.GENERATOR_V2
		run.seed_value = seed_value
		run.floor_number = 1
		run.generate_floor()
		for key in run.rooms:
			if run.rooms[key].get("template") == template and run.rooms[key].type == "combat":
				return [seed_value, key]
	return []

func enter(seed_value: int, key: String) -> void:
	game.start_run("candle", seed_value, false)
	game.paused = true
	run.current_room = key
	game.enter_room(Vector3(0, 0, 2))

func screen_input(world: Vector3) -> Vector2:
	return Vector2(world.dot(game.screen_right), world.dot(game.screen_down)).normalized()

func player_in_frame(label: String) -> void:
	var view = game.get_viewport().get_visible_rect()
	for height in [.12, 1.25]:
		var point: Vector2 = game.camera.unproject_position(game.player.global_position + Vector3.UP * height)
		check(view.grow(-24).has_point(point), label + ": player stays in frame")

func test_escape(label: String) -> void:
	var geometry: RoomGeometry = game.room.geometry
	var area = geometry.bounds()
	var escaped = 0
	var trials = 0
	# Let the physics space register the room once; movement then runs
	# synchronously with the fixed 60 Hz step.
	await physics_frame
	for cell in geometry.cells:
		var center = geometry.cell_center(cell)
		for direction in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 1).normalized(), Vector3(-1, 0, 1).normalized(), Vector3(1, 0, -1).normalized()]:
			trials += 1
			game.player.position = Vector3(center.x, 0, center.y) + direction * 2
			game.player.last_valid = game.player.position
			game.player.velocity = Vector3.ZERO
			for frame in 150:
				game.player.update_sim(DT, screen_input(direction), Vector3.ZERO, false)
				if not geometry.contains(game.player.position, .29):
					escaped += 1
					break
	check(escaped == 0, label + ": the player never leaves the footprint (%d pushes)" % trials)
	# Dash into the concave corner and every wall at full speed.
	for cell in geometry.cells:
		var center = geometry.cell_center(cell)
		game.player.position = Vector3(center.x, 0, center.y)
		game.player.last_valid = game.player.position
		for direction in [Vector3(1, 0, 1).normalized(), Vector3(-1, 0, -1).normalized()]:
			game.player.dash_cooldown = 0
			game.player.last_move = direction
			game.player.dash()
			for frame in 40:
				game.player.update_sim(DT, screen_input(direction), Vector3.ZERO, false)
			check(geometry.contains(game.player.position, .29), label + ": dashing cannot escape through a corner")
	check(area.has_point(Vector2(game.player.position.x, game.player.position.z)), label + ": player stays inside room bounds")

func test_enemy_route(label: String, kind: String, start: Vector2, goal: Vector2) -> void:
	game.player.position = Vector3(goal.x, 0, goal.y)
	game.player.invulnerability = 999
	var enemy = game.spawn_enemy(Vector3(start.x, 0, start.y), kind)
	enemy.speed = 2.0
	var reached = false
	var escaped = false
	await physics_frame
	for frame in 2400:
		game.player.invulnerability = 999
		enemy.update_sim(DT)
		if not is_instance_valid(enemy): break
		if not game.room.geometry.contains(enemy.position, minf(.45, enemy.radius) - .01): escaped = true
		if enemy.position.distance_to(game.player.position) < (6.0 if kind == "spitter" else 2.5):
			reached = true
			break
	check(reached, label + ": %s reaches the player around the bend (%s -> %s)" % [kind, enemy.position if is_instance_valid(enemy) else "gone", game.player.position])
	check(not escaped, label + ": %s stays on the floor" % kind)
	if is_instance_valid(enemy):
		enemy.alive = false
		enemy.queue_free()
	game.enemies = game.enemies.filter(func(e): return is_instance_valid(e) and e.alive)

func test_large_room(template: String) -> void:
	var found = find_room(template)
	check(not found.is_empty(), template + ": a seed produces this room")
	if found.is_empty(): return
	enter(found[0], found[1])
	var key: String = found[1]
	var geometry: RoomGeometry = game.room.geometry
	var label = template
	check(geometry.cells.size() == run.room_cells(key).size(), label + ": the built room uses the real footprint")
	check(Geo.footprint == geometry.shader_rects(), label + ": glows use this room's footprint mask")
	for node in game.room.get_children():
		if node is MeshInstance3D and node.material_override is ShaderMaterial and node.material_override.shader.resource_path.ends_with("halo.gdshader"):
			check(node.material_override.get_shader_parameter("room_cells") == geometry.shader_rects(), label + ": each halo is clipped to the footprint")
			break
	# Walls only on exposed edges: no collider on an open seam.
	for node in game.room.get_children():
		if not node is StaticBody3D or node.has_meta("prop_id"): continue
		var p = Vector2(node.position.x, node.position.z)
		var size: Vector3 = node.get_child(0).shape.size
		if size.x > 2 or size.z > 2:
			var on_seam = false
			for cell in geometry.cells:
				for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
					if geometry.has_cell(cell + direction):
						var seam = geometry.socket_point(cell, direction)
						if (direction.x != 0 and absf(p.x - seam.x) < .5 and absf(p.y - seam.y) < 7) or (direction.y != 0 and absf(p.y - seam.y) < .5 and absf(p.x - seam.x) < 9):
							on_seam = true
			check(not on_seam, label + ": no wall stands on an open seam")
	# Lighting budget holds in large rooms; fills follow the player.
	var lights = game.room.find_children("*", "Light3D", true, false)
	check(lights.filter(func(l): return l is OmniLight3D).size() == 4, label + ": four pooled warm fills")
	check(lights.filter(func(l): return l.shadow_enabled).size() <= 1, label + ": at most one local shadow map")
	var far_cell = geometry.cells.back()
	var far_center = geometry.cell_center(far_cell)
	game.player.position = Vector3(far_center.x, 0, far_center.y)
	for i in 3: game.room.update_light_selection(game.player.position)
	var near_lights = game.room.lamps.filter(func(l): return Vector2(l.position.x, l.position.z).distance_to(far_center) < 12)
	check(near_lights.size() >= 3, label + ": fills move to lanterns near the player")
	game.ui.sync_lighting()
	check(game.ui.lighting_lamps.size() == 4, label + ": the dungeon-lit UI receives the selected lights")
	# Camera follows through the room, keeps its basis and frames the player.
	var basis: Basis = game.camera.basis
	for cell in geometry.cells:
		var center = geometry.cell_center(cell)
		for corner in [Vector2(-8.7, -6.7), Vector2(8.7, -6.7), Vector2(-8.7, 6.7), Vector2(8.7, 6.7), Vector2.ZERO]:
			var p = center + corner
			if not geometry.contains(p, .29): continue
			game.player.position = Vector3(p.x, 0, p.y)
			game.update_camera(0, true)
			check(game.camera.basis.is_equal_approx(basis), label + ": camera keeps its isometric basis")
			player_in_frame(label + " " + str(p))
	check(is_equal_approx(game.camera.size, game.CAMERA_GAME_SIZE), label + ": combat keeps the close zoom")
	# Foreground cutaway uses each wall's own normal and extent.
	var lowered = 0
	var standing = 0
	var probe: Dictionary = game.room.front_walls[0]
	var middle = (probe.span.x + probe.span.y) / 2.0
	var inside_wall = probe.plane - 1.5
	game.player.position = Vector3(middle, 0, inside_wall) if probe.side.y > 0 else Vector3(inside_wall, 0, middle)
	game.room.update_wall_visibility(game.player.position, 0, [])
	check(is_equal_approx(probe.body.mesh.size.y * probe.body.scale.y, .45), label + ": the wall in front of the player cuts away")
	for wall in game.room.front_walls:
		var height = wall.body.mesh.size.y * wall.body.scale.y
		if is_equal_approx(height, .45): lowered += 1
		else: standing += 1
	check(lowered > 0 and standing > 0, label + ": only the nearby foreground walls cut away")
	await test_escape(label)
	if template == "hall_corner":
		# Opposite arms of the L: the straight line crosses the void.
		var arms: Array = []
		for cell in geometry.cells:
			var neighbours = geometry.cells.filter(func(c): return absi(c.x - cell.x) + absi(c.y - cell.y) == 1).size()
			if neighbours == 1: arms.append(geometry.cell_center(cell))
		check(arms.size() == 2 and not geometry.segment_clear(arms[0], arms[1]), label + ": the two arms have no straight route")
		# Route tests use a quiet room: idle encounter foes would only block the lane.
		for foe in game.enemies:
			if is_instance_valid(foe): foe.free()
		game.enemies.clear()
		if arms.size() == 2:
			for kind in ["mote", "brute", "charger", "spitter"]:
				await test_enemy_route(label, kind, arms[0], arms[1])
		# A bouncing projectile fired at the inner corner stays inside.
		for i in 8:
			var arm: Vector2 = arms[0] if arms.size() == 2 else Vector2.ZERO
			var origin = Vector3(arm.x, .65, arm.y)
			var shot = game.spawn_shot(origin, Vector3(cos(i * .7), 0, sin(i * .7)), 1, 18, {"bounce": 6, "range": 3}, Color.WHITE, true)
			var inside = true
			for frame in 120:
				if not is_instance_valid(shot) or not shot.alive: break
				shot.update_sim(DT)
				if shot.alive and not geometry.contains(shot.global_position, -.05): inside = false
			check(inside, label + ": ricochets stay inside the footprint")
	# Clear and reward exactly once for the whole logical room.
	game.room.set_open(false)
	var cleared_before: int = run.cleared
	for foe in game.enemies.duplicate():
		if is_instance_valid(foe): foe.take_hit(1e9, Vector3.ZERO)
	game.enemies = game.enemies.filter(func(e): return is_instance_valid(e) and e.alive)
	game.clear_room()
	run.mark_cleared()
	check(run.cleared == cleared_before + 1, label + ": a multi-cell room clears once")
	var offers = run.rooms[key].get("offers", []).duplicate(true)
	game.enter_room(Vector3(0, 0, 2))
	check(game.enemies.is_empty() and game.room.open, label + ": a cleared large room stays cleared")
	check(run.rooms[key].get("offers", []) == offers, label + ": re-entry never rerolls its reward")
	# Every doorway leads to the paired room and back to the same socket.
	for socket in game.room.sockets:
		var door: Vector3 = game.room.socket_position(socket)
		var entry: Vector3 = game.portal_entry(key, socket.portal)
		check(geometry.contains(entry, .45), label + ": entry anchor is on the floor")
		for obstacle in game.room.obstacles:
			check(entry.distance_to(obstacle.position) > 1.6, label + ": entry anchor is clear of pillars")
	var tested = 0
	for socket in game.room.sockets.filter(func(x): return x.state != "concealed"):
		if tested >= 3: break
		tested += 1
		run.current_room = key
		game.enter_room(Vector3(0, 0, 2))
		game.paused = false
		var door: Vector3 = game.room.socket_position(socket)
		game.player.position = door - Vector3(socket.dir.x, 0, socket.dir.y) * .5
		game.check_doors()
		await process_frame
		check(run.current_room == socket.other, label + ": doorway leads to its paired room")
		check(run.checkpoint.portal == socket.portal, label + ": the entry portal becomes the checkpoint")
		var back: Vector3 = game.portal_entry(socket.other, socket.portal)
		check(game.player.position.distance_to(back) < .01, label + ": arrival uses the paired entry anchor")
		check(game.room.geometry.contains(game.player.position, .45), label + ": arrival is on the floor")
		game.paused = true
		var visible = game.ui.map_rooms()
		check(key in visible and socket.other in visible, label + ": the map shows both sides of a used doorway")
	# Continue resumes at the saved entry anchor, never in the void.
	run.current_room = key
	game.enter_room(game.portal_entry(key, game.room.sockets[0].portal), game.room.sockets[0].portal)
	run.save_run()
	game.continue_run()
	game.paused = true
	check(run.current_room == key and game.room.geometry.contains(game.player.position, .45), label + ": Continue places the player inside the footprint")
	run.checkpoint = {"room": key, "portal": "missing"}
	game.enter_room(game.checkpoint_spawn())
	check(game.room.geometry.contains(game.player.position, .45), label + ": an unknown checkpoint falls back to a safe spawn")

func test_map_privacy() -> void:
	game.start_run("candle", 4242, false)
	game.paused = true
	var visible = game.ui.map_rooms()
	var nearby = run.neighbors(run.current_room)
	for key in run.rooms:
		var allowed = run.rooms[key].visited or key in nearby
		check((key in visible) == allowed, "minimap only shows visited rooms and known doorways")
	game.paused = false
	game.ui.show_screen("play")
	var trigger = game.ui.content.get_children().filter(func(n): return n is Button and n.get_meta("control_id", "") == "MapTrigger" and not n.is_queued_for_deletion())
	check(trigger.size() == 1, "the compact map has one native trigger")
	if not trigger.is_empty(): trigger[0].pressed.emit()
	check(game.ui.mode == "map" and game.paused, "tapping the compact map opens the full floor map paused")
	game.ui.close_map()
	check(game.ui.mode == "play" and not game.paused, "closing the full map resumes play")

func test_rooms() -> void:
	run = root.get_node("Run")
	test_geometry()
	test_generation()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	await test_large_room("hall_long")
	await test_large_room("hall_corner")
	await test_large_room("hall_grand")
	await test_map_privacy()
	game.end_run(false)
	game.queue_free()
	root.get_node("Audio").music_player.stop()
	await process_frame
	await process_frame
	print("EMBERKEEP ROOMS TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
