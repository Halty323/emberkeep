extends SceneTree
## Opt-in real-renderer regression. Run tools/render_lighting.sh to isolate saves.

func _initialize() -> void:
	if OS.get_environment("EMBERKEEP_RENDER_TEST") != "1" or DisplayServer.get_name() == "headless":
		push_error("Use tools/render_lighting.sh with a real display, not --headless.")
		quit(1)
		return
	call_deferred("capture")

func save(path: String) -> Image:
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	image.save_png(path)
	print("LIGHTING_RENDER image=", path)
	return image

func screen_pixel(game, image: Image, world: Vector3) -> Color:
	var at: Vector2 = game.camera.unproject_position(world)
	var scale = Vector2(image.get_width(), image.get_height()) / game.get_viewport().get_visible_rect().size
	return image.get_pixel(clampi(int(at.x * scale.x), 0, image.get_width() - 1), clampi(int(at.y * scale.y), 0, image.get_height() - 1))

## An L room in both shadow modes: glow and paint never light the notch.
func capture_l_room(game, run, output: String) -> int:
	var failures = 0
	var generator = load("res://scripts/dungeon/floor_generator.gd")
	var catalog = root.get_node("Content")
	var floor_data = {"rooms": {}, "portals": {}, "owners": {}, "generator": 2}
	generator.place_room(floor_data, catalog.record("rooms", "hearth_1x1"), 0, Vector2i(0, 0), 4, 1)
	generator.place_room(floor_data, catalog.record("rooms", "bend_l3"), 0, Vector2i(1, 0), 4, 1)
	generator.add_portal(floor_data, Vector2i(0, 0), Vector2i(1, 0))
	floor_data.rooms["1,0"].cleared = true
	run.rooms = floor_data.rooms
	run.portals = floor_data.portals
	run.current_room = "1,0"
	game.enter_room(Vector3(7, 0, 6))
	game.paused = true
	game.ui.toast_time = 0
	# Glows and paint pushed right up to the notch's corner must stay outside it.
	game.room.effects.mark(Vector3(9.4, 0, 7.4), Color("d6503f"), {"size": 2.4, "lifetime": 60.0, "alpha": .8})
	Geo.halo(game.room, Vector3(9.5, .03, 7.5), 6.0, Color(1, .6, .2, .6))
	game.update_camera(0, true)
	for setting in [true, false]:
		root.get_node("Settings").set_value("shadows", setting)
		var image = await save(output.path_join("l-room-shadows-" + ("on" if setting else "off") + ".png"))
		var notch = screen_pixel(game, image, Vector3(13.5, 0, 10.5))
		var floor_pixel = screen_pixel(game, image, Vector3(7.5, 0, 5.5))
		if notch.get_luminance() > .13 or floor_pixel.get_luminance() < .08:
			push_error("FAIL: L-room notch is lit by glow or paint, or the floor did not render.")
			failures += 1
		print("L_ROOM shadows=", setting, " notch_luminance=", notch.get_luminance(), " floor_luminance=", floor_pixel.get_luminance())
	return failures

## Half-resolution 3D keeps the canvas HUD pixel-identical and the world aligned.
func capture_render_scale(game, run, output: String) -> int:
	var failures = 0
	var settings = root.get_node("Settings")
	settings.set_value("render_scale", 1.0)
	var full = await save(output.path_join("render-scale-100.png"))
	var player_full: Vector2 = game.camera.unproject_position(game.player.global_position)
	settings.set_value("render_scale", .5)
	var half = await save(output.path_join("render-scale-50.png"))
	var player_half: Vector2 = game.camera.unproject_position(game.player.global_position)
	settings.set_value("render_scale", 1.0)
	var difference = 0.0
	for y in range(40, 160):
		for x in range(40, 380):
			difference += absf(full.get_pixel(x, y).get_luminance() - half.get_pixel(x, y).get_luminance())
	difference /= 120.0 * 340.0
	if difference > .02 or player_full.distance_to(player_half) > .5:
		push_error("FAIL: 50% render scale changed the HUD or the world framing.")
		failures += 1
	print("RENDER_SCALE hud_mean_difference=", difference, " player_offset=", player_full.distance_to(player_half))
	return failures

## The tower brightens as it is climbed: the same room on floors 1-3, and a
## foe in the dark cellar still standing out from the floor around it.
func capture_floors(game, run, output: String) -> int:
	var failures = 0
	var means: Array = []
	var room_id: String = run.current_room
	for floor in [1, 2, 3]:
		run.floor_number = floor
		run.current_room = room_id
		game.enter_room(Vector3(0, 0, 2.0))
		game.paused = true
		game.ui.toast_time = 0
		var foe = game.spawn_enemy(Vector3(-3.5, 0, -1.5), "mote")
		var image = await save(output.path_join("floor-%d.png" % floor))
		var total = 0.0
		var count = 0
		for y in range(int(image.get_height() * .28), int(image.get_height() * .94), 6):
			for x in range(0, image.get_width(), 6):
				total += image.get_pixel(x, y).get_luminance()
				count += 1
		means.append(total / count)
		if floor == 1:
			var body = screen_pixel(game, image, foe.global_position + Vector3(0, foe.radius * 1.1, 0)).get_luminance()
			var ground = screen_pixel(game, image, foe.global_position + Vector3(0, 0, 2.6)).get_luminance()
			print("FLOOR_LIGHT cellar foe=", body, " floor_beside=", ground)
			if body < ground * 1.6 or body < .08:
				push_error("FAIL: a foe in the cellar does not stand out from the dark floor.")
				failures += 1
	print("FLOOR_LIGHT mean_luminance=", means)
	if not (means[0] < means[1] * .6 and means[2] > means[1] * 1.25):
		push_error("FAIL: the tower does not brighten floor by floor (%s)." % str(means))
		failures += 1
	run.floor_number = 2
	run.current_room = room_id
	game.enter_room(Vector3(0, 0, 2.0))
	game.paused = true
	return failures

## A wide wall painting and a tall panel keep their proportions in place.
func capture_paintings(game, run, output: String) -> int:
	var failures = 0
	for pick in [["last_supper", "wide"], ["arnolfini_portrait", "tall"]]:
		game.start_run("candle", 5150, false)
		for id in run.rooms:
			if run.rooms[id].type == "rest":
				run.current_room = id
				run.rooms[id].mounts[0].painting = pick[0]
		game.enter_room(Vector3(0, 0, 2))
		var mount = run.rooms[run.current_room].mounts[0]
		game.player.place(Vector3(float(mount.view[0]), 0, float(mount.view[1])))
		game.paused = true
		game.ui.toast_time = 0
		game.update_camera(0, true)
		await save(output.path_join("painting-" + pick[1] + ".png"))
		var view = game.room.paintings[mount.id]
		var aspect = root.get_node("Content").record("paintings", pick[0]).aspect
		if absf(view.size.x / view.size.y - aspect) > .005:
			push_error("FAIL: a painting lost its proportions on the wall.")
			failures += 1
	return failures

func capture() -> void:
	var output = OS.get_environment("EMBERKEEP_RENDER_OUTPUT")
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("shadows", true)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_run("needle", 20261026, false)
	run.floor_number = 2
	run.generate_floor()
	for key in run.rooms:
		if run.rooms[key].type == "combat":
			run.current_room = key
			break
	run.rooms[run.current_room].cleared = true
	run.rooms[run.current_room].claimed = true
	game.enter_room(Vector3(0, 0, 2.0))
	game.paused = true
	game.ui.toast_time = 0
	game.make_marker("rest", Vector3(1.0, 0, -1.0))
	game.spawn_enemy(Vector3(-3, 0, 0), "mote")
	game.spawn_enemy(Vector3(3.5, 0, -.5), "brute")
	game.spawn_shot(Vector3(1, .65, 1), Vector3.RIGHT, 5, 10, {}, Color("ffc474"), true)
	var failures = 0
	for setting in [true, false]:
		settings.set_value("shadows", setting)
		game.room.apply_lighting_quality()
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		var image = root.get_texture().get_image()
		var path = output.path_join("lantern-shadows-" + ("on" if setting else "off") + ".png")
		if image.save_png(path) != OK:
			push_error("Could not save lighting capture: " + path)
			failures += 1
		# The reported solid halo planes painted the void just left of the room
		# yellow. Test the actual output, not merely the shader's source text.
		var outside = image.get_pixel(int(image.get_width() * 100.0 / 1280), int(image.get_height() * .5))
		var floor_pixel = image.get_pixel(image.get_width() / 2, image.get_height() / 2)
		if outside.get_luminance() > .13 or floor_pixel.get_luminance() < .1:
			push_error("Lighting pixel regression: bright halo outside the room, or an unrendered floor.")
			failures += 1
		var start = Time.get_ticks_usec()
		var calls = 0.0
		for frame in 30:
			await RenderingServer.frame_post_draw
			calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		print("LIGHTING_RENDER shadows=", setting, " frame_ms=", float(Time.get_ticks_usec() - start) / 30000.0,
			" draw_calls=", calls / 30.0, " image=", path)
	failures += await capture_floors(game, run, output)
	failures += await capture_l_room(game, run, output)
	failures += await capture_render_scale(game, run, output)
	failures += await capture_paintings(game, run, output)
	game.queue_free()
	root.get_node("Audio").music_player.stop()
	for player in root.get_node("Audio").players: player.stop()
	await process_frame
	await process_frame
	print("EMBERKEEP RENDER TEST RESULT: ", failures, " failures")
	quit(0 if failures == 0 else 1)
