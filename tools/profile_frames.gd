extends SceneTree
## Stutter profiler. A bot plays the real first-person game through real
## frames: it fights each room (finishing foes one at a time after a while),
## walks to an open doorway, follows the corridor and moves on. Every frame's
## time is recorded with what happened in it (corridor built, neighbour
## staged, room entered), then the median, tail and worst frames are printed.
##   godot --headless --fixed-fps 60 --path . --script res://tools/profile_frames.gd
## Headless, a frame's time is its CPU work; under Xvfb (no --headless) it
## includes rendering and first-use shader compiles. Software GL numbers are
## a workload reference, not phone timings.
## Env: ROOMS (rooms to visit, 10), SEED (4242), DETAIL (effects detail,
## high), MAX_FRAMES (9000), OUT (optional JSON of every frame).
var game
var run
var frames: Array = []
var events: Array = []
var last_usec := 0
var last_room := ""
var last_corridor := 0
var last_staged := 0
var phase := "fight"
var visited := {}
var fight_frames := 0
var stuck := 0
var last_pos := Vector2.ZERO
var rooms_left := 10
var route: Array = []
var portal := ""
var route_corridor = null

func _initialize() -> void:
	call_deferred("go")

func note(text: String) -> void:
	events.append(text)

func go() -> void:
	run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	settings.set_value("effects_detail", OS.get_environment("DETAIL") if OS.get_environment("DETAIL") != "" else "high")
	rooms_left = int(OS.get_environment("ROOMS")) if OS.get_environment("ROOMS") != "" else 10
	var t0 = Time.get_ticks_usec()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var seed_value = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 4242
	var t1 = Time.get_ticks_usec()
	game.start_run(load("res://scripts/items/forge.gd").id_for(seed_value, 0), seed_value, false)
	print("PERF start_run took %.1f ms (scene load %.1f ms)" % [(Time.get_ticks_usec() - t1) / 1000.0, (t1 - t0) / 1000.0])
	run.stats.max_hp = 999
	run.hp = 999
	last_room = run.current_room
	visited[last_room] = true
	last_usec = Time.get_ticks_usec()
	process_frame.connect(on_frame)
	physics_frame.connect(drive)

func on_frame() -> void:
	var now = Time.get_ticks_usec()
	var ms = (now - last_usec) / 1000.0
	last_usec = now
	if run.current_room != last_room:
		note("entered room %s (%s)" % [run.current_room, run.rooms[run.current_room].type])
		last_room = run.current_room
	var corridor = game.corridors.active.get_instance_id() if is_instance_valid(game.corridors.active) else 0
	if corridor != last_corridor:
		note("corridor built" if corridor != 0 else "corridor released")
		last_corridor = corridor
	var staged = game.corridors.staged_room.get_instance_id() if is_instance_valid(game.corridors.staged_room) else 0
	if staged != last_staged:
		if staged != 0: note("neighbour room staged")
		last_staged = staged
	if frames.size() % 600 == 0:
		print("PERF progress frame=%d phase=%s room=%s rooms_left=%d" % [frames.size(), phase, run.current_room, rooms_left])
	if frames.size() > int(OS.get_environment("MAX_FRAMES") if OS.get_environment("MAX_FRAMES") != "" else "9000"):
		finish()
		return
	frames.append({"ms": snappedf(ms, .01), "events": events.duplicate(), "shots": game.shots.size(), "foes": game.enemies.size(), "phase": phase, "room": run.current_room, "fight": fight_frames})
	events.clear()

## Steers the player like a thumb on the stick: face the target, push forward.
func steer_to(point: Vector2) -> bool:
	var at = Vector2(game.player.position.x, game.player.position.z)
	var delta = point - at
	if delta.length() < .3:
		game.ui.left_vector = Vector2.ZERO
		return true
	game.fps.yaw = atan2(-delta.x, -delta.y)
	game.fps.pitch = 0
	game.ui.left_vector = Vector2(0, -1)
	return false

func drive() -> void:
	if not run.active or game.in_menu:
		finish()
		return
	if game.paused: game.resume_game()
	if game.ui.mode != "play":
		if game.ui.mode == "reward": game.close_reward()
		else: game.ui.show_screen("play")
	run.hp = 999
	game.player.invulnerability = 1.0
	var data: Dictionary = run.rooms[run.current_room]
	var live = game.enemies.filter(func(e): return is_instance_valid(e) and e.alive and not e.inert)
	if not live.is_empty():
		phase = "fight"
		fight_frames += 1
		game.ui.left_vector = Vector2.ZERO
		var foe = live[0]
		var to: Vector3 = foe.global_position - game.player.global_position
		game.fps.yaw = atan2(-to.x, -to.z)
		game.fps.pitch = 0
		game.ui.fire_touch = 1
		# Real fights for a while, then finish them so the walk goes on.
		if fight_frames > 240 and fight_frames % 20 == 0:
			foe.take_hit(foe.max_hp * 2.0 + 50.0, Vector3.ZERO)
		if fight_frames > 900:
			# A foe that cannot be shot down (a phase, a shield): end it.
			for enemy in live:
				enemy.alive = false
				game.enemies.erase(enemy)
				enemy.queue_free()
		return
	game.ui.fire_touch = -1
	fight_frames = 0
	if rooms_left <= 0:
		finish()
		return
	if not route.is_empty():
		# The walk ends when the corridor it followed is released on arrival.
		if not is_instance_valid(game.corridors.active) or game.corridors.active != route_corridor:
			route.clear()
			rooms_left -= 1
			portal = ""
		else:
			phase = "corridor"
			var offset: Vector2 = Vector2(game.corridors.active.position.x, game.corridors.active.position.z)
			if steer_to(route[0] + offset) and route.size() > 1: route.pop_front()
			return
	# Choose an open doorway toward a room not yet seen, and walk to it.
	if portal == "":
		var best := ""
		for id in data.get("portals", []):
			if run.portals[id].state not in ["open", "revealed"]: continue
			var other = run.other_room(id, run.current_room)
			if best == "" or not visited.has(other): best = id
			if not visited.has(other): break
		if best == "":
			finish()
			return
		portal = best
		visited[run.other_room(best, run.current_room)] = true
	phase = "walk"
	var side = run.portal_side(portal, run.current_room)
	var door: Vector2 = load("res://scripts/dungeon/room_geometry.gd").socket_point(side.cell, side.dir)
	var approach = door - Vector2(side.dir) * 1.2
	var at = Vector2(game.player.position.x, game.player.position.z)
	if at.distance_to(last_pos) < .002: stuck += 1
	else: stuck = 0
	last_pos = at
	if stuck > 240:
		# Furniture in the way: step to the doorway directly.
		game.player.place(Vector3(approach.x, game.player.position.y, approach.y))
		stuck = 0
	if steer_to(approach):
		if game.corridors.portal_id != portal: game.corridors.arm(portal)
		if is_instance_valid(game.corridors.active) and game.corridors.portal_id == portal:
			route = game.corridors.active.path.duplicate()
			route.append(route.back() + Vector2(side.dir) * 2.2)
			route_corridor = game.corridors.active

var done := false

func finish() -> void:
	if done: return
	done = true
	physics_frame.disconnect(drive)
	process_frame.disconnect(on_frame)
	var times: Array = frames.map(func(f): return f.ms)
	times.sort()
	var count = times.size()
	var spikes = frames.filter(func(f): return f.ms > 16.7)
	var report = {"frames": count, "median_ms": times[count / 2], "p95_ms": times[int(count * .95)], "p99_ms": times[int(count * .99)], "max_ms": times[-1],
		"over_16ms": spikes.size(), "over_33ms": frames.filter(func(f): return f.ms > 33.3).size(), "rooms_visited": visited.size()}
	print("PERF REPORT " + JSON.stringify(report))
	var worst = frames.duplicate()
	worst.sort_custom(func(a, b): return a.ms > b.ms)
	for f in worst.slice(0, 25):
		print("PERF SPIKE %.1f ms phase=%s fight_frame=%d room=%s shots=%d foes=%d events=%s" % [f.ms, f.phase, f.fight, f.room, f.shots, f.foes, f.events])
	var out = OS.get_environment("OUT")
	if out != "":
		var file = FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify({"report": report, "frames": frames}))
		file.close()
	quit()
