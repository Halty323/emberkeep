extends SceneTree
## Frame pacing: the work that used to land in one long frame (a neighbour
## room, its route grids, a fight's first path search, a ledge's residue
## surface) is spread or reused without changing what gets built, and the eye
## moves smoothly between fixed ticks. Shader warm-up never touches the run.
var checks := 0
var failures := 0
var game
var run
var Room
var Navigation
var Residue
var Doorway

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("exercise")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func settle() -> void:
	for i in 3: await process_frame

func exercise() -> void:
	Room = load("res://scripts/world.gd")
	Navigation = load("res://scripts/dungeon/room_navigation.gd")
	Residue = load("res://scripts/combat/residue.gd")
	Doorway = load("res://scripts/presentation/dungeon_doorway.gd")
	run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.start_run("candle", 31609250, false)
	game.paused = true
	await settle()
	await paced_rooms()
	navigation_matches_brute_force()
	doorways_share_meshes()
	eye_interpolation()
	await reaper_and_save()
	await prewarm_is_inert()
	game.queue_free()
	await settle()
	print("FRAME PACING: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func shape_of(node: Node) -> Array:
	var result: Array = []
	for child in node.find_children("*", "", true, false):
		var line: String = child.get_class()
		if child is MeshInstance3D and child.mesh: line += ":%d" % child.mesh.get_surface_count()
		if child is Node3D: line += ":" + str(child.position.snapped(Vector3.ONE * .001))
		result.append(line)
	return result

func fight_room() -> String:
	var best := ""
	for id in run.rooms:
		var data: Dictionary = run.rooms[id]
		if data.type != "combat": continue
		if best == "" or data.get("cells", [[0, 0]]).size() > run.rooms[best].get("cells", [[0, 0]]).size(): best = id
	return best

func paced_rooms() -> void:
	var id := fight_room()
	check(id != "", "the fixture floor has a fight room")
	var data: Dictionary = run.rooms[id]
	var whole = Room.new()
	game.corridors.add_child(whole)
	whole.process_mode = Node.PROCESS_MODE_DISABLED
	whole.build(game, data)
	check(not whole.building, "an ordinary build finishes in its own call")
	# Staged: a slice now, the rest one slice per resume.
	var staged = Room.new()
	staged.process_mode = Node.PROCESS_MODE_DISABLED
	game.corridors.add_child(staged)
	staged.build(game, data, false, true)
	var slices := 1
	while staged.building and slices < 5000:
		staged.resume_build()
		slices += 1
	check(not staged.building and slices > 1, "a staged room builds over several slices (%d)" % slices)
	check(shape_of(staged) == shape_of(whole), "a paced build makes exactly the same room")
	check(staged.navigators.has(Vector2(.5, 0)) and staged.navigators.has(Vector2(1.0, 0)), "a staged fight room has its foes' route grids ready")
	var direct = Navigation.new(staged.geometry, .5, staged.navigation_blockers(0.0), 0.0)
	var same := true
	for x in range(direct.grid.region.position.x, direct.grid.region.end.x):
		for y in range(direct.grid.region.position.y, direct.grid.region.end.y):
			if direct.grid.is_point_solid(Vector2i(x, y)) != staged.navigators[Vector2(.5, 0)].grid.is_point_solid(Vector2i(x, y)): same = false
	check(same, "a grid filled a column at a time equals one filled at once")
	# Needed early: one call finishes everything that is left.
	var hurried = Room.new()
	hurried.process_mode = Node.PROCESS_MODE_DISABLED
	game.corridors.add_child(hurried)
	hurried.build(game, data, false, true)
	hurried.resume_build(true)
	check(not hurried.building and shape_of(hurried) == shape_of(whole), "a hurried staged room completes at once, identical")
	var pool = load("res://scripts/effects/effects_pool.gd")
	for room in [whole, staged, hurried]:
		game.corridors.remove_child(room)
		room.free()
	game.room.geometry.apply_shader_mask()
	pool.current = game.room.effects
	# A ledge room's residue surface is built while staging and kept on its
	# geometry; it is the surface entering the room would have built.
	var ledges := 0
	for room_id in run.rooms:
		var room = Room.new()
		room.process_mode = Node.PROCESS_MODE_DISABLED
		game.corridors.add_child(room)
		room.build(game, run.rooms[room_id], false, true)
		room.resume_build(true)
		if room.geometry.terrain and room.geometry.terrain.ledge.has_area():
			ledges += 1
			var fresh = Residue.new()
			fresh.first_person = true
			fresh.geometry = room.geometry
			fresh.grid_for(room.geometry)
			var prepared: bool = room.geometry.has_meta(fresh.surface_meta())
			var kept: ArrayMesh = room.geometry.get_meta(fresh.surface_meta()) if prepared else null
			room.geometry.remove_meta(fresh.surface_meta())
			var rebuilt: ArrayMesh = fresh.build_elevated_surface()
			check(prepared and kept.get_faces() == rebuilt.get_faces(), "staging prepares the same ledge residue surface the room would build")
			var field = Residue.new()
			game.corridors.add_child(field)
			field.setup(game, room.geometry)
			check(field.elevated_surface == rebuilt, "entering the room reuses the kept surface")
			fresh.free()
			field.free()
		game.corridors.remove_child(room)
		room.free()
	print("FRAME PACING ledge rooms: %d" % ledges)
	game.room.geometry.apply_shader_mask()
	pool.current = game.room.effects

## The bucketed walkable test equals testing every blocker everywhere.
func navigation_matches_brute_force() -> void:
	var room = game.room
	var blockers := {"a": Rect2(-3, -2, 1.5, 1.2), "b": Rect2(2, 1, .8, 2.4), "c": Rect2(-1, 3, 4, .5), "edge": Rect2(-9.5, -7.5, 2, 2)}
	for clearance in [.5, 1.0]:
		var nav = Navigation.new(room.geometry, clearance, blockers, 0.0)
		var mismatches := 0
		for x in range(nav.grid.region.position.x, nav.grid.region.end.x):
			for y in range(nav.grid.region.position.y, nav.grid.region.end.y):
				var point: Vector2 = nav.to_world(Vector2i(x, y))
				var open: bool = room.geometry.contains(point, clearance)
				if open and room.geometry.terrain: open = room.geometry.terrain.traversable(point, clearance) if not room.geometry.terrain.loft else room.geometry.terrain.loft.walkable(point, clearance, 0)
				for id in blockers:
					if blockers[id].grow(clearance).has_point(point): open = false
				if open == nav.grid.is_point_solid(Vector2i(x, y)): mismatches += 1
		check(mismatches == 0, "bucketed blockers give the same grid at clearance %.1f (%d differ)" % [clearance, mismatches])
		nav.remove_blocker("a")
		var cleared: Vector2 = Rect2(-3, -2, 1.5, 1.2).get_center()
		check(nav.walkable(cleared) == room.geometry.contains(cleared, clearance), "a removed blocker stops blocking")
		check(not nav.walkable(Rect2(2, 1, .8, 2.4).get_center()), "the remaining blockers still block")

func doorways_share_meshes() -> void:
	var leaves: Array = []
	for gate in game.room.gates:
		if not gate.has_meta("physical_doorway"): continue
		var leaf: Node = gate.get_node("Barrier/LeftLeaf")
		leaves.append(leaf.get_child(0).mesh)
	check(leaves.size() >= 2 and leaves.all(func(mesh): return mesh == leaves[0]), "every doorway draws the same shared leaf mesh")

func eye_interpolation() -> void:
	var fps = game.fps
	var player = game.player
	var start: Vector3 = player.global_position
	fps.sample_view()
	player.global_position = start + Vector3(.1, 0, 0)
	fps.sample_view()
	check(fps.view_from.is_equal_approx(start) and fps.view_to.is_equal_approx(start + Vector3(.1, 0, 0)), "the eye keeps the body's last two ticks")
	var drawn: Vector3 = fps.view_position(player)
	check(drawn.x >= start.x - .0001 and drawn.x <= start.x + .1001, "the drawn eye lies between the two ticks")
	player.global_position = start + Vector3(5, 0, 0)
	check(fps.view_position(player).is_equal_approx(start + Vector3(5, 0, 0)), "a body moved outside a tick is drawn where it is")
	fps.sample_view()
	player.global_position = start + Vector3(30, 0, 0)
	fps.sample_view()
	check(fps.view_from.is_equal_approx(fps.view_to), "a rebase-sized jump never sweeps the eye across the floor")
	check(fps.view_position(player, true).is_equal_approx(player.global_position), "a snap draws the eye at the body")
	player.global_position = start
	fps.view_position(player, true)
	game.paused = false
	game.ui.show_screen("play")
	fps.update_view(1.0 / 60.0)
	game.ui.look_delta = Vector2(20, 0)
	var yaw: float = fps.yaw
	fps.update_view(1.0 / 60.0)
	check(not is_equal_approx(fps.yaw, yaw) and game.ui.look_delta == Vector2.ZERO, "touch look turns the view on a drawn frame")
	game.paused = true

## A left room leaves the world at once and is deleted over later frames;
## a corridor arrival saves a couple of frames after the handoff.
func reaper_and_save() -> void:
	var reaper = load("res://scripts/first_person/node_reaper.gd").new()
	var top := Node3D.new()
	var nodes: Array = [top]
	var parent: Node3D = top
	for i in 60:
		var child := Node3D.new()
		parent.add_child(child)
		nodes.append(child)
		if i % 6 == 0: parent = child
	game.add_child(top)
	reaper.reap(top)
	check(not top.is_inside_tree() and is_instance_valid(top) and reaper.pending() == nodes.size(), "a reaped tree leaves the world at once, still to be deleted")
	reaper.step(1000000)
	check(reaper.pending() == 0 and nodes.all(func(node): return not is_instance_valid(node)), "the reaper deletes every node, deepest first, without errors")
	game.save_soon()
	check(game.save_due == 2, "a corridor arrival schedules its save")
	await settle()
	check(game.save_due == -1, "the scheduled save runs within a few frames")
	var watch = load("res://scripts/graphics/frame_watch.gd")
	watch.mark("a test cause")
	watch.frame(.05)
	check(watch.hitches.back()[2] == "a test cause" and int(watch.hitches.back()[1]) == 50, "a long frame is reported with what the game was doing")

## Warm-up draws foes, shots and drops that never join the run.
func prewarm_is_inert() -> void:
	var Prewarm = load("res://scripts/graphics/shader_prewarm.gd")
	var entity_counter: int = game.entity_counter
	var rng_state: int = run.rng.state
	var enemies: int = game.enemies.size()
	var shots: int = game.shots.size()
	var pickups: int = game.pickups.size()
	var drops: int = run.rooms[run.current_room].get("pickups", []).size()
	var lights: int = game.room.extra_lights.size()
	var roots: int = game.scene_root.get_child_count()
	var visited: Array = run.rooms.keys().filter(func(id): return run.rooms[id].get("visited", false))
	var warm = Prewarm.begin(game)
	check(warm.find_children("*", "DungeonEnemy", true, false).size() >= 2, "warm-up shows this floor's foes")
	check(warm.find_children("*", "EmberShot", true, false).size() == 2, "warm-up shows a friendly and a hostile shot")
	check(game.entity_counter == entity_counter and run.rng.state == rng_state, "warm-up leaves entity ids and the run's RNG alone")
	check(game.enemies.size() == enemies and game.shots.size() == shots and game.pickups.size() == pickups and get_nodes_in_group("enemies").size() == enemies, "warm-up foes, shots and drops are not in play")
	check(run.rooms[run.current_room].get("pickups", []).size() == drops and game.room.extra_lights.size() == lights, "warm-up records no drops and lends the room no lights")
	check(game.scene_root.get_child_count() == roots + 1, "everything a warm-up setup left behind is held by the warm-up")
	var pool = load("res://scripts/effects/effects_pool.gd").current
	check(pool == null or pool.transient_count() > 0, "warm-up draws every effect")
	var steps := 0
	var most_rooms := 0
	var shown := {}
	while warm.active() and steps < 500:
		var rooms: Array = warm.find_children("*", "DungeonRoom", true, false)
		most_rooms = maxi(most_rooms, rooms.size())
		for room in rooms: shown[room.data.id] = true
		warm.step()
		steps += 1
	check(shown.size() == run.rooms.size() - 1 and most_rooms == 1, "warm-up shows every other room, one at a time (%d)" % shown.size())
	check(warm.shaders.size() > 10 and warm.find_children("*", "DungeonRoom", true, false).is_empty(), "warm-up ends with one swatch set per distinct shader and no rooms (%d shaders)" % warm.shaders.size())
	check(run.rooms.keys().filter(func(id): return run.rooms[id].get("visited", false)) == visited and run.current_room == game.room.data.id, "showing the other rooms visits none of them")
	check(load("res://scripts/effects/effects_pool.gd").current == game.room.effects, "the active room keeps its particle pool")
	check(steps > Prewarm.HOLD_FRAMES and warm.swatches == warm.shaders.size(), "warm-up lays its shaders a few per frame, then holds (%d frames)" % steps)
	check(pool == null or pool.transient_count() == 0, "warm-up particles are gone when the veil lifts")
	await settle()
	check(not is_instance_valid(warm) and game.scene_root.get_child_count() == roots, "warm-up removes itself after its frames")
