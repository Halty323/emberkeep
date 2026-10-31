extends SceneTree
## Device settings service: validation, one-time profile migration, engine
## application, and the three settings pages. Run through tools/test.sh.
var checks = 0
var failures = 0
var settings: Node
var run: Node
var game

func _initialize() -> void:
	call_deferred("test_settings")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func write_json(path: String, value) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func read_json(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(path))

## Screen rebuilds can rename replacements while the old row is queued for deletion.
func live_row(key: String) -> SettingRow:
	for node in game.ui.content.get_children():
		if node is SettingRow and not node.is_queued_for_deletion() and node.setting_key == key:
			return node
	return null

func test_settings() -> void:
	settings = root.get_node("Settings")
	run = root.get_node("Run")
	# Fresh storage: defaults keep existing players at full scale with a 60 FPS cap.
	check(is_equal_approx(settings.values.render_scale, 1.0), "default render scale stays at 100%")
	check(settings.values.fps_limit == 60, "default FPS limit is 60")
	check(Engine.max_fps == 60, "default FPS limit is applied to the engine")
	check(FileAccess.file_exists(settings.PATH), "settings are saved to their own versioned file")
	check(int(read_json(settings.PATH).version) == settings.VERSION, "settings file records its version")
	# One-time migration from preferences formerly kept in the profile.
	DirAccess.remove_absolute(settings.PATH)
	write_json(settings.LEGACY_PROFILE_PATH, {"version": 1, "runs": 4, "wins": 1, "kills": 30, "best_floor": 2,
		"discovered": ["warm_wax"], "sound": false, "music": false, "shake": false, "touch": true, "quality": false})
	settings.load_settings()
	check(settings.values.sound == false and settings.values.music == false and settings.values.shake == false,
		"audio and shake preferences migrate from the old profile")
	check(settings.values.touch == true and settings.values.shadows == false, "touch and lantern shadow preferences migrate")
	check(is_equal_approx(settings.values.render_scale, 1.0) and settings.values.fps_limit == 60,
		"migrated profiles retain full render scale and the default FPS limit")
	check(FileAccess.file_exists(settings.PATH), "migration writes the new settings file")
	# The profile keeps progress but no longer stores a second writable copy.
	run._ready()
	check(int(run.profile.runs) == 4 and run.profile.discovered == ["warm_wax"], "profile progress survives the split")
	for key in ["sound", "music", "shake", "touch", "quality"]:
		check(not run.profile.has(key), "profile no longer holds device preference: " + key)
	run.save_profile()
	var saved_profile = read_json(settings.LEGACY_PROFILE_PATH)
	check(int(saved_profile.version) == run.PROFILE_VERSION and not saved_profile.has("sound"),
		"saved profile is versioned and excludes device preferences")
	# Migration happens once: later profile values never overwrite settings.
	write_json(settings.LEGACY_PROFILE_PATH, {"version": 1, "sound": true})
	settings.load_settings()
	check(settings.values.sound == false, "migration runs only once")
	# Each field validates independently.
	write_json(settings.PATH, {"version": 1, "render_scale": 0.42, "fps_limit": 75, "vsync": "yes",
		"show_fps": true, "effects_detail": "ultra", "small_details": "low", "sound": 1, "music": true})
	settings.load_settings()
	check(is_equal_approx(settings.values.render_scale, 1.0), "unsupported render scale falls back alone")
	check(settings.values.fps_limit == 60, "unsupported FPS limit falls back alone")
	check(settings.values.vsync == true and settings.values.sound == true, "wrongly typed booleans fall back alone")
	check(settings.values.show_fps == true and settings.values.small_details == "low", "valid neighbouring fields are kept")
	check(settings.values.effects_detail == "balanced", "unknown detail level falls back alone")
	check(not settings.set_value("render_scale", 0.6), "setter rejects unsupported render scale")
	check(not settings.set_value("fps_limit", 144), "setter rejects unsupported FPS limit")
	# Values reach the engine only through supported, real setters.
	for scale in settings.RENDER_SCALES:
		check(settings.set_value("render_scale", scale), "render scale accepted: %s" % scale)
		check(root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "Compatibility uses built-in bilinear 3D scaling")
		check(is_equal_approx(root.scaling_3d_scale, scale), "root viewport 3D scale follows the setting")
	for limit in settings.FPS_LIMITS:
		settings.set_value("fps_limit", limit)
		check(Engine.max_fps == limit, "FPS limit applies to Engine.max_fps: %d" % limit)
	check(settings.effective_vsync() == "system", "headless/mobile VSync is reported as system controlled")
	for level in settings.DETAIL_LEVELS:
		settings.set_value("effects_detail", level)
		var budget = settings.EFFECT_BUDGETS[level]
		check(settings.effect_budget("ambient") == budget.ambient and settings.effect_budget("transient") == budget.transient,
			"effects detail selects its budget: " + level)
	check(settings.EFFECT_BUDGETS.low.transient < settings.EFFECT_BUDGETS.balanced.transient
		and settings.EFFECT_BUDGETS.balanced.transient < settings.EFFECT_BUDGETS.high.transient, "budgets grow with detail")
	var persisted = read_json(settings.PATH)
	check(int(persisted.fps_limit) == 0 and persisted.effects_detail == "high", "changes persist immediately")
	# Scaling the 3D buffer must not move the world under UI or input mapping.
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.start_run("candle", 777, false)
	game.paused = true
	game.update_camera(0, true)
	settings.set_value("render_scale", 1.0)
	var full = game.camera.unproject_position(game.player.global_position)
	var ray = game.camera.project_ray_origin(Vector2(400, 300))
	settings.set_value("render_scale", 0.5)
	await process_frame
	check(game.camera.unproject_position(game.player.global_position).distance_to(full) < .01,
		"50% render scale keeps world framing aligned with the HUD")
	check(game.camera.project_ray_origin(Vector2(400, 300)).distance_to(ray) < .001, "mouse aiming rays are unchanged")
	check(is_equal_approx(game.camera.size, game.CAMERA_GAME_SIZE), "render scale never changes the camera zoom")
	var pixels: Vector2i = settings.render_pixels()
	var native = Vector2(DisplayServer.window_get_size())
	if native.x <= 0: native = Vector2(root.size)
	check(pixels == Vector2i(roundi(native.x * .5), roundi(native.y * .5)), "reported pixel dimensions match the scale")
	# Three settings pages, each with rows that own their background and target.
	game.ui.open_settings("pause")
	for page in game.ui.SETTINGS_PAGES:
		game.ui.open_settings_page(page[0])
		await process_frame
		var rows = game.ui.content.get_children().filter(func(node): return node is SettingRow and not node.is_queued_for_deletion())
		check(rows.size() == game.ui.settings_rows(page[0]).size(), page[0] + ": every setting has a row")
		for row in rows:
			check(row.surface.get_parent() == row, page[0] + ": row owns its stone slab")
			check(row.surface.show_behind_parent, page[0] + ": slab draws behind the row label")
			check(row.surface.size == row.size, page[0] + ": slab covers the whole hit target")
			check(row.content_fits(), page[0] + ": label and value fit: " + row.text)
			check(row.size.y >= 54, page[0] + ": row is a comfortable touch target")
			check(row.surface in game.ui.surfaces, page[0] + ": row slab receives room lighting")
			var before_origin = row.surface.stone_material.get_shader_parameter("panel_origin")
			row.position += Vector2(0, 30)
			check(row.surface.stone_material.get_shader_parameter("panel_origin") == before_origin + Vector2(0, 30),
				page[0] + ": moving a row moves its lighting origin with it")
			row.position -= Vector2(0, 30)
	# Rows cycle real settings; VSync is non-interactive where it cannot work.
	settings.set_value("render_scale", 1.0)
	game.ui.open_settings_page("display")
	await process_frame
	var vsync_row = live_row("vsync")
	check(vsync_row != null and vsync_row.disabled and vsync_row.value_text == "System controlled",
		"unsupported VSync is shown as a noninteractive system-controlled row")
	var scale_row = live_row("render_scale")
	if scale_row:
		scale_row.pressed.emit()
		check(is_equal_approx(settings.values.render_scale, settings.RENDER_SCALES[0]), "render row cycles to the next scale")
		await process_frame
		scale_row = live_row("render_scale")
		var px: Vector2i = settings.render_pixels()
		check(scale_row != null and ("%d×%d" % [px.x, px.y]) in scale_row.value_text, "render row shows resulting pixel dimensions")
	game.ui.open_settings_page("controls")
	await process_frame
	var shake_row = live_row("shake")
	var shake_before: bool = settings.values.shake
	if shake_row: shake_row.pressed.emit()
	check(settings.values.shake != shake_before, "comfort rows toggle their setting")
	# FPS readout is smoothed over half-second windows.
	settings.set_value("show_fps", true)
	game.ui.fps_value = 0
	game.ui.fps_frames = 0
	game.ui.fps_time = 0.0
	for frame in 40: game.ui._process(1.0 / 60.0)
	check(absf(game.ui.fps_value - 60.0) < 1.0, "FPS readout reports a smoothed frame rate")
	settings.set_value("render_scale", 1.0)
	settings.set_value("fps_limit", 60)
	game.return_to_title()
	game.queue_free()
	await process_frame
	await process_frame
	print("EMBERKEEP SETTINGS TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
