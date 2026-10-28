extends SceneTree
## Opt-in worst-case scene for device profiling: the largest room, every
## relic, Paint Sprayer, active companions and a buff, furniture and a crowd,
## all firing. Prints frame-time distribution, draw calls, primitives, texture
## and video memory, node counts and the room-transition stall. Software GL
## numbers are a workload reference only, never a device performance claim.

func _initialize() -> void:
	if OS.get_environment("EMBERKEEP_STRESS_TEST") != "1" or DisplayServer.get_name() == "headless":
		push_error("Use tools/render_stress.sh with a real display, not --headless.")
		quit(1)
		return
	call_deferred("measure")

func percentile(values: Array, fraction: float) -> float:
	var sorted = values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, int(sorted.size() * fraction))]

func measure() -> void:
	var run = root.get_node("Run")
	var catalog = root.get_node("Content")
	var settings = root.get_node("Settings")
	settings.set_value("effects_detail", OS.get_environment("EMBERKEEP_STRESS_DETAIL") if OS.get_environment("EMBERKEEP_STRESS_DETAIL") != "" else "high")
	settings.set_value("small_details", "high")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	run.profile.unlocks = ["paint_sprayer"]
	var generator = load("res://scripts/dungeon/floor_generator.gd")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_run("paint_sprayer", 424242, false)
	var floor_data = {"rooms": {}, "portals": {}, "owners": {}, "generator": 2}
	generator.place_room(floor_data, catalog.record("rooms", "hearth_1x1"), 0, Vector2i(0, 0), 424242, 1)
	generator.place_room(floor_data, catalog.record("rooms", "great_2x2"), 0, Vector2i(1, 0), 424242, 1)
	generator.add_portal(floor_data, Vector2i(0, 0), Vector2i(1, 0))
	floor_data.rooms["1,0"].type = "combat"
	generator.dress_floor(floor_data, 424242, 1)
	run.rooms = floor_data.rooms
	run.portals = floor_data.portals
	run.current_room = "1,0"
	var start = Time.get_ticks_usec()
	game.enter_room(Vector3(1, 0, 0))
	var transition_ms = (Time.get_ticks_usec() - start) / 1000.0
	run.grant_all_relics()
	game.player.refresh_orbitals()
	run.add_modifier("copper_kettle", 999, catalog.record("actives", "copper_kettle").params.effects)
	run.add_modifier("moth_jar", 999, {}, {"companions": 2, "companion_damage": 6.0})
	run.hp = 999
	run.stats.max_hp = 999
	for i in 14:
		var foe = game.spawn_enemy(Vector3(4 + (i % 5) * 4, 0, 2 + (i / 5) * 5), ["mote", "spitter", "charger", "brute"][i % 4], "stress:%d" % i)
		foe.hp = 1e9
		foe.max_hp = 1e9
	game.paused = false
	game.ui.toast_time = 0
	var frames: Array = []
	var calls = 0.0
	var primitives = 0.0
	for frame in 240:
		game.player.invulnerability = 1.0
		var target = game.nearest_enemy(game.player.global_position, 99.0)
		if target:
			var to = (target.global_position - game.player.global_position).normalized()
			game.ui.right_vector = Vector2(to.dot(game.screen_right), to.dot(game.screen_down))
		var before = Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		frames.append((Time.get_ticks_usec() - before) / 1000.0)
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var image = root.get_texture().get_image()
	var path = OS.get_environment("EMBERKEEP_STRESS_OUTPUT").path_join("stress-largest-room.png")
	image.save_png(path)
	var report = {
		"renderer": RenderingServer.get_video_adapter_name(), "effects_detail": settings.values.effects_detail,
		"frame_ms_median": percentile(frames, .5), "frame_ms_p95": percentile(frames, .95), "frame_ms_max": frames.max(),
		"draw_calls": calls / frames.size(), "primitives": primitives / frames.size(),
		"texture_mem_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "shots": game.shots.size(),
		"particles": game.room.effects.count, "props": game.room.props.size(), "room_transition_ms": transition_ms,
		"image": path}
	print("EMBERKEEP STRESS REPORT " + JSON.stringify(report))
	game.queue_free()
	await process_frame
	quit(0)
