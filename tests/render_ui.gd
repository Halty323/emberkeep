extends SceneTree
## Opt-in native GUI and real-renderer capture. Never touches player saves.
var checks = 0
var failures = 0
var game
var run
var output = ""

func _initialize() -> void:
	if OS.get_environment("EMBERKEEP_UI_RENDER_TEST") != "1" or DisplayServer.get_name() == "headless":
		push_error("Use tools/render_ui.sh with a real display, not --headless.")
		quit(1)
		return
	output = OS.get_environment("EMBERKEEP_UI_RENDER_OUTPUT")
	call_deferred("capture")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func settle(frames := 3) -> void:
	for frame in frames: await process_frame
	await RenderingServer.frame_post_draw

func save_capture(label: String) -> Image:
	await settle()
	var image = root.get_texture().get_image()
	var path = output.path_join(label + ".png")
	check(not image.is_empty() and image.save_png(path) == OK, "rendered capture: " + label)
	print("UI_RENDER image=", path)
	return image

func click(at: Vector2) -> void:
	var screen_point: Vector2 = game.ui.offset + at * game.ui.scale_value
	var motion = InputEventMouseMotion.new()
	motion.position = screen_point
	motion.global_position = screen_point
	Input.parse_input_event(motion)
	var press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = screen_point
	press.global_position = screen_point
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release = press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame

func patch_luminance(image: Image, rect: Rect2i) -> float:
	var total = 0.0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			total += image.get_pixel(x, y).get_luminance()
	return total / float(rect.size.x * rect.size.y)

func text_peak(image: Image) -> float:
	# The weapon label is canvas text, independently readable above the relief.
	var levels: Array[float] = []
	for y in range(138, 158):
		for x in range(48, 220): levels.append(image.get_pixel(x, y).get_luminance())
	levels.sort()
	var total = 0.0
	for index in 20: total += levels[levels.size() - 1 - index]
	return total / 20.0

func capture() -> void:
	run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	settings.set_value("touch", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game.start_run("needle", 20261027, false)
	game.return_to_title()
	check(run.has_save(), "menu fixture includes a continue-save button")
	await save_capture("menu-saved-run")
	game.continue_run()
	game.paused = true
	run.floor_number = 2
	run.generate_floor()
	for key in run.rooms:
		if run.rooms[key].type == "combat":
			run.current_room = key
			break
	run.rooms[run.current_room].cleared = true
	run.rooms[run.current_room].claimed = true
	game.enter_room(Vector3(0, 0, 2))
	game.paused = true
	game.spawn_enemy(Vector3(-3, 0, 0), "mote")
	game.spawn_enemy(Vector3(3.5, 0, -.5), "brute")
	run.coins = 42
	for id in ["warm_wax", "firefly_jar", "twin_flame"]:
		if root.get_node("Content").item_by_id.has(id): run.gain_item(id)
	game.ui.toast_time = 0
	await save_capture("hud-desktop")
	settings.set_value("touch", true)
	await save_capture("hud-touch")
	settings.set_value("touch", false)
	# Click the actual native pause button, rather than emitting its signal.
	await click(Vector2(1218, 53))
	check(game.ui.mode == "pause" and game.paused, "native mouse click opens pause")
	await save_capture("pause")
	for tap in 5: await click(Vector2(640, 184))
	check(game.ui.mode == "secret", "five native title clicks open secret entry")
	await save_capture("secret-dialog")
	await click(Vector2(640, 526))
	check(game.ui.mode == "pause", "native secret Back button returns to pause")
	await click(Vector2(640, 461))
	check(game.ui.mode == "settings", "native settings button opens settings")
	await save_capture("settings")
	await click(Vector2(640, 601))
	check(game.ui.mode == "pause", "native settings Back returns to pause")
	game.ui.open_journal("pause")
	game.ui.change_journal_page(game.ui.journal_page_count())
	check(game.ui.journal_page == game.ui.journal_page_count() - 1, "journal reaches final page")
	await save_capture("journal-last-page")
	game.ui.offers = [{"id": "warm_wax"}, {"id": "needle", "kind": "weapon"}, {"id": "eternal_hearth"}]
	game.ui.shop = false
	game.ui.show_screen("reward")
	await save_capture("reward-three-offers")
	game.ui.show_screen("play")
	game.ui.toast_time = 0
	# Freeze only the room's flicker so actual lantern energies can be controlled.
	game.room.set_process(false)
	var lamp_values: Array = []
	for lamp in game.room.lamps:
		lamp_values.append([lamp.transform, lamp.light_energy, lamp.omni_range])
		lamp.light_energy = 0
	var original_key: float = game.key_light.light_energy
	game.key_light.light_energy = 0
	var dark = await save_capture("ui-relief-unlit-lanterns")
	var lamp = game.room.lamps[0]
	lamp.global_position = game.camera.project_position(game.ui.offset + Vector2(315, 125) * game.ui.scale_value, 30)
	lamp.omni_range = 12
	lamp.light_energy = 4
	var lit = await save_capture("ui-relief-warm-lantern")
	var patch = Rect2i(280, 118, 70, 24)
	var response = patch_luminance(lit, patch) - patch_luminance(dark, patch)
	check(response > .015, "real lantern change visibly illuminates the HUD stone")
	check(text_peak(dark) > .6 and text_peak(lit) > .6, "weapon text remains readable in both lighting extremes")
	check(absf(text_peak(lit) - text_peak(dark)) < .03, "surface lighting leaves the text brightness stable")
	print("UI_RENDER relief_luminance_response=", response, " text_peak_dark=", text_peak(dark), " text_peak_lit=", text_peak(lit))
	for index in game.room.lamps.size():
		var original: Array = lamp_values[index]
		game.room.lamps[index].transform = original[0]
		game.room.lamps[index].light_energy = original[1]
		game.room.lamps[index].omni_range = original[2]
	game.key_light.light_energy = original_key
	game.queue_free()
	var audio = root.get_node("Audio")
	audio.music_player.stop()
	audio.music_player.stream = null
	for voice in audio.players:
		voice.stop()
		voice.stream = null
	await process_frame
	await process_frame
	print("EMBERKEEP UI RENDER TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
