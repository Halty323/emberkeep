extends SceneTree
## Opt-in OpenGL captures of multi-cell rooms: ./tools/render.sh rooms
## Checks that glows stay clipped to the footprint and the HUD stays sharp
## when only the 3D world is rendered at reduced resolution.
var failures = 0
var game
var run

func _initialize() -> void:
	if OS.get_environment("EMBERKEEP_RENDER_TEST") != "1" or DisplayServer.get_name() == "headless":
		push_error("Use tools/render.sh rooms with a real display, not --headless.")
		quit(1)
		return
	call_deferred("capture")

func fail(message: String) -> void:
	failures += 1
	push_error("FAIL: " + message)

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

func shot(name: String) -> Image:
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	var path = OS.get_environment("EMBERKEEP_RENDER_OUTPUT").path_join(name + ".png")
	if image.save_png(path) != OK:
		fail("could not save " + path)
	print("ROOM_RENDER ", name, " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " image=", path)
	return image

func luminance_at(image: Image, world: Vector3) -> float:
	var p = game.camera.unproject_position(world)
	var scale = Vector2(image.get_size()) / game.get_viewport().get_visible_rect().size
	var q = Vector2i((p * scale).round())
	if not Rect2i(Vector2i.ZERO, image.get_size()).has_point(q): return -1.0
	return image.get_pixelv(q).get_luminance()

func capture() -> void:
	run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.values.shadows = true
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	for template in ["hall_long", "hall_corner"]:
		var found = find_room(template)
		if found.is_empty():
			fail("no seed produced " + template)
			continue
		game.start_run("candle", found[0], false)
		run.current_room = found[1]
		run.rooms[found[1]].cleared = true
		run.rooms[found[1]].claimed = true
		game.enter_room(Vector3(0, 0, 2))
		game.paused = true
		game.ui.toast_time = 0
		var geometry: RoomGeometry = game.room.geometry
		var index = 0
		for cell in geometry.cells:
			var center = geometry.cell_center(cell)
			game.player.position = Vector3(center.x, 0, center.y)
			game.update_camera(0, true)
			game.room.update_light_selection(game.player.position)
			var image = await shot("%s-cell%d" % [template, index])
			var floor_light = luminance_at(image, Vector3(center.x + 1.5, 0, center.y + 1.5))
			if floor_light >= 0 and floor_light < .05:
				fail("%s cell %d: the floor did not render" % [template, index])
			index += 1
		if template == "hall_corner":
			# Look at the concave corner: the void quadrant must stay dark.
			var bounds = geometry.bounds()
			for cell in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				var probe = geometry.cells[0] + cell
				if geometry.has_cell(probe) or not bounds.has_point(geometry.cell_center(probe)): continue
				var direction = Vector2(signf(cell.x), signf(cell.y))
				var inner = geometry.cell_center(probe) - direction * RoomGeometry.HALF
				game.player.position = Vector3(inner.x, 0, inner.y)
				var safe = geometry.nearest_inside(game.player.position - Vector3(direction.x, 0, direction.y) * 2, .5)
				game.player.position = Vector3(safe.x, 0, safe.y)
				game.update_camera(0, true)
				var image = await shot("hall_corner-void")
				for depth in [3.0, 4.5, 6.0]:
					var probe_point = inner + direction * depth
					var void_light = luminance_at(image, Vector3(probe_point.x, 0, probe_point.y))
					print("ROOM_RENDER void depth=", depth, " luminance=", void_light)
					if void_light > .13:
						fail("glow or floor leaked into the missing quadrant (luminance %.3f at depth %.1f)" % [void_light, depth])
				break
	# Reduced world resolution keeps the canvas HUD at display resolution.
	settings.set_value("render_scale", .5)
	var low = await shot("render-scale-50")
	settings.set_value("render_scale", 1.0)
	var full = await shot("render-scale-100")
	var text_rect = Rect2i(Vector2i(40, 100) * low.get_size() / Vector2i(1280, 720), Vector2i(160, 40) * low.get_size() / Vector2i(1280, 720))
	var diff = 0.0
	for x in range(text_rect.position.x, text_rect.end.x):
		for y in range(text_rect.position.y, text_rect.end.y):
			diff += absf(low.get_pixel(x, y).get_luminance() - full.get_pixel(x, y).get_luminance())
	diff /= float(text_rect.get_area())
	print("ROOM_RENDER hud_difference_50_vs_100=", diff)
	if diff > .04:
		fail("HUD text changed with 3D render scale (mean difference %.3f)" % diff)
	game.queue_free()
	root.get_node("Audio").music_player.stop()
	for player in root.get_node("Audio").players: player.stop()
	await process_frame
	await process_frame
	print("EMBERKEEP ROOM RENDER RESULT: ", failures, " failures")
	quit(0 if failures == 0 else 1)
