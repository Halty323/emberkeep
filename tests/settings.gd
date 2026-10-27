extends SceneTree
## Device settings: migration, validation, engine application and the paged screen.
## Run through tools/test.sh so settings and profiles use disposable storage.
var checks = 0
var failures = 0
var settings
var run
var game

func _initialize() -> void:
	call_deferred("test_settings")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func write_json(path: String, value: Dictionary) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func read_json(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func descendants(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child.is_queued_for_deletion(): continue
		result.append(child)
		result.append_array(descendants(child))
	return result

func named_button(name: String) -> Button:
	for node in descendants(game.ui.content):
		if node is Button and node.get_meta("control_id", "") == name: return node
	return null

func test_settings() -> void:
	settings = root.get_node("Settings")
	run = root.get_node("Run")
	# One-time migration of the old profile-held preferences.
	DirAccess.remove_absolute(settings.PATH)
	write_json(settings.LEGACY_PROFILE_PATH, {"version": 1, "runs": 4, "wins": 1, "kills": 30, "best_floor": 2,
		"discovered": ["warm_wax"], "sound": false, "music": false, "shake": false, "touch": true, "quality": false})
	settings.load_settings()
	check(not settings.values.sound and not settings.values.music and not settings.values.shake, "old audio and shake choices migrate")
	check(settings.values.touch and not settings.values.shadows, "old touch and lantern-shadow choices migrate")
	check(is_equal_approx(settings.values.render_scale, 1.0), "existing players keep full render resolution")
	check(settings.values.fps_limit == 60, "default frame limit is 60")
	check(FileAccess.file_exists(settings.PATH), "migration writes the versioned settings file")
	check(int(read_json(settings.PATH).version) == settings.VERSION, "settings file records its version")
	write_json(settings.LEGACY_PROFILE_PATH, {"version": 1, "sound": true, "quality": true})
	settings.load_settings()
	check(not settings.values.sound and not settings.values.shadows, "migration runs once; the profile no longer overrides settings")
	# The profile loader keeps progress and drops device keys.
	write_json(settings.LEGACY_PROFILE_PATH, {"version": 1, "runs": 4, "wins": 1, "kills": 30, "best_floor": 2,
		"discovered": ["warm_wax"], "sound": false, "quality": false})
	run.load_profile()
	check(run.profile.runs == 4 and run.profile.discovered == ["warm_wax"], "profile progress survives the settings split")
	check(not run.profile.has("sound") and not run.profile.has("quality"), "profile no longer carries device preferences")
	run.save_profile()
	check(not read_json(run.PROFILE_PATH).has("sound"), "saved profile has one source of truth for device settings")
	# Individual field validation: one bad value never discards the rest.
	write_json(settings.PATH, {"version": 1, "render_scale": .3, "fps_limit": 45, "vsync": "yes", "show_fps": true,
		"effects_detail": "ultra", "small_details": "low", "sound": 1, "music": true, "shake": true, "touch": false, "shadows": true})
	settings.load_settings()
	check(is_equal_approx(settings.values.render_scale, 1.0) and settings.values.fps_limit == 60, "unsupported numeric values fall back individually")
	check(settings.values.effects_detail == "balanced" and settings.values.sound == true, "invalid detail and boolean values fall back individually")
	check(settings.values.show_fps and settings.values.small_details == "low", "valid neighbouring fields are retained")
	check(not settings.set_value("render_scale", .2), "set_value rejects unsupported resolution scales")
	check(not settings.set_value("fps_limit", 75), "set_value rejects unsupported frame limits")
	check(not settings.set_value("unknown", true), "set_value rejects unknown keys")
	# Engine application: 3D scale on the root viewport, frame cap via Engine.
	settings.apply_all()
	for scale in settings.RENDER_SCALES:
		check(settings.set_value("render_scale", scale), "render scale accepted: %s" % scale)
		check(root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "Compatibility uses built-in bilinear 3D scaling")
		check(is_equal_approx(root.scaling_3d_scale, scale), "root viewport receives the render scale")
		var expected := Vector2i((Vector2(root.size) * scale).round())
		check(settings.render_size() == expected, "resulting pixel dimensions are reported")
		check(settings.render_scale_label().contains("%d×%d" % [expected.x, expected.y]), "label shows resulting pixels")
	for limit in settings.FPS_LIMITS:
		settings.set_value("fps_limit", limit)
		check(Engine.max_fps == limit, "Engine.max_fps follows the limit: %d" % limit)
	check(settings.fps_label() == "Unlimited", "zero is presented as Unlimited")
	settings.load_settings()
	check(settings.values.fps_limit == 0, "frame limit persists")
	settings.set_value("fps_limit", 60)
	# VSync: honest capability reporting.
	settings.capability_override = {"mobile": true}
	check(not settings.vsync_supported(), "mobile GL reports VSync as system controlled")
	check(settings.effective_vsync_label() == "System controlled", "unsupported VSync is labelled, not toggled")
	var vsync_before: bool = settings.values.vsync
	check(not settings.set_value("vsync", not vsync_before) and settings.values.vsync == vsync_before, "unsupported VSync cannot be silently toggled")
	settings.capability_override = {"vsync": true}
	check(settings.set_value("vsync", false) and settings.effective_vsync_label() == "Off", "desktop VSync can be requested off")
	settings.set_value("vsync", true)
	settings.capability_override = {}
	# Cosmetic budgets scale with the setting; they never change layout.
	settings.set_value("effects_detail", "low")
	var low_scale: float = settings.effects_scale()
	settings.set_value("effects_detail", "high")
	check(low_scale < 1.0 and settings.effects_scale() > 1.0, "effects detail changes cosmetic density")
	var counts := {}
	for level in settings.DETAIL_LEVELS:
		settings.set_value("small_details", level)
		settings.set_value("effects_detail", level)
		var stage = Node3D.new()
		root.add_child(stage)
		var room = load("res://scripts/world.gd").new()
		stage.add_child(room)
		room.build(stage, {"type": "combat", "seed": 77}, true)
		var candles = descendants(room).filter(func(node): return node is MeshInstance3D and node.mesh is CylinderMesh and is_equal_approx(node.mesh.top_radius, .12)).size()
		counts[level] = [candles, room.ember_mesh.multimesh.instance_count, room.obstacles.size(),
			descendants(room).filter(func(node): return node is StaticBody3D).size()]
		stage.free()
	check(counts.low[0] < counts.balanced[0] and counts.balanced[0] < counts.high[0], "small details changes decorative candles")
	check(counts.low[1] < counts.balanced[1] and counts.balanced[1] < counts.high[1], "effects detail changes ambient embers")
	check(counts.low[2] == counts.high[2] and counts.low[3] == counts.high[3], "detail levels keep collision identical")
	settings.set_value("effects_detail", "balanced")
	settings.set_value("small_details", "balanced")
	# Paged screen with native, lit rows.
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	var ui_scale: float = game.ui.scale_value
	var ui_offset: Vector2 = game.ui.offset
	settings.set_value("render_scale", .5)
	await process_frame
	check(is_equal_approx(game.ui.scale_value, ui_scale) and game.ui.offset == ui_offset, "scaled 3D leaves UI layout and input mapping unchanged")
	check(is_equal_approx(game.camera.size, game.CAMERA_MENU_SIZE), "scaled 3D keeps camera framing")
	settings.set_value("render_scale", 1.0)
	game.ui.open_settings("menu")
	for page in game.ui.SETTINGS_PAGES:
		var tab = named_button("SettingsTab_" + page[0])
		check(tab != null, "settings tab exists: " + page[1])
		if tab: tab.pressed.emit()
		check(game.ui.settings_page == page[0], "tab opens its page: " + page[1])
		for row in game.ui.SETTINGS_ROWS[page[0]]:
			var control = named_button("Setting_" + row[0])
			check(control != null, "row exists: " + row[1])
			if control and row[0] != "vsync":
				check(not control.disabled and control.text.contains(game.ui.settings_value_label(row[0])), "row shows its live value: " + row[1])
	named_button("SettingsTab_display").pressed.emit()
	var vsync_row = named_button("Setting_vsync")
	check(vsync_row.disabled and vsync_row.text.contains("System controlled"), "headless/mobile VSync row is noninteractive")
	named_button("Setting_fps_limit").pressed.emit()
	check(settings.values.fps_limit == 90 and Engine.max_fps == 90, "pressing the FPS row cycles and applies the limit")
	var fps_shown: bool = settings.values.show_fps
	named_button("Setting_show_fps").pressed.emit()
	check(settings.values.show_fps != fps_shown, "pressing Show FPS toggles the readout")
	named_button("SettingsTab_controls").pressed.emit()
	var shake_before: bool = settings.values.shake
	named_button("Setting_shake").pressed.emit()
	check(settings.values.shake != shake_before and read_json(settings.PATH).shake == settings.values.shake, "sound and controls rows save immediately")
	named_button("Setting_shake").pressed.emit()
	game.ui.close_subscreen()
	check(game.ui.mode == "menu", "Back returns to the title")
	game.queue_free()
	# Leave defaults behind for any later suite sharing this disposable storage.
	settings.values = settings.DEFAULTS.duplicate()
	settings.save_settings()
	settings.load_settings()
	settings.apply_all()
	root.get_node("Audio").music_player.stop()
	await process_frame
	await process_frame
	print("EMBERKEEP SETTINGS TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
