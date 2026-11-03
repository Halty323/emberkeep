extends SceneTree
## Native GLES capture of the real brazier recipe and bundled painting view.
## Run tools/render_fire_art.sh with an OpenGL display.
var failures := 0
var game

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("capture")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func picture(name: String) -> Image:
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(OS.get_environment("EMBERKEEP_FIRE_ART_CAPTURE").path_join(name + ".png"))
	return image

func capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run tools/render_fire_art.sh with a real OpenGL display")
		quit(1)
		return
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	Engine.max_fps = 60
	var policy = load("res://scripts/graphics/render_policy.gd")
	var style = load("res://scripts/graphics/dungeon_style.gd")
	var visuals = load("res://scripts/dungeon/prop_visuals.gd")
	var batch = load("res://scripts/dungeon/detail_batch.gd")
	var library = load("res://scripts/progression/painting_library.gd")
	var effects = load("res://scripts/effects/effects_pool.gd")
	# Exercise the mobile-safe GLES path used by the reported device.
	policy.device_override = policy.for_device("Android", "Imagination", "PowerVR", "gl_compatibility")
	settings.apply_render_policy()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_run("candle", 31609250, false)
	game.paused = true
	game.set_process(false)
	game.set_physics_process(false)
	game.room.resume_build(true)
	game.update_camera(.016, true)
	# Captures stop the startup controller, so also remove its fade cover.
	game.light_veil.visible = false
	# Retire the unseen material samples that the startup cover was hiding.
	# Their artificial pile must not appear in the rendered room or mirror.
	if is_instance_valid(game.prewarm):
		game.prewarm.show_residue(false)
		game.prewarm.free()
		game.prewarm = null
	if is_instance_valid(effects.current): effects.current.expire_transients()
	game.fps.weapon.visible = false
	game.ui.visible = false
	var definition: Dictionary = root.get_node("Content").record("furniture", "brazier")
	var prop: Dictionary = visuals.build(game.room, {"id": "fire-render-fixture", "position": [0, 0], "size": [.8, .8]}, definition, 2, batch.new(), Vector2i.ZERO, RandomNumberGenerator.new())
	prop.definition = definition
	game.room.props["fire-render-fixture"] = prop
	style.dress_props(game.room)
	var fire: MeshInstance3D = prop.node.get_node("Flame")
	check(fire.get_child_count() == 2, "brazier has three tongues rather than one cone")
	check(prop.node.get_node("Coals").material_override == style.brazier_coals(), "coals use dark fuel with hot seams")
	var light_count: int = game.room.lamps.size() + game.room.shadow_lamps.size()
	game.camera.global_position = Vector3(0, 1.65, 2.1)
	game.camera.look_at(Vector3(0, 1.24, 0))
	for detail in ["low", "balanced", "high"]:
		settings.set_value("effects_detail", detail)
		await picture("brazier-" + detail)
	var first := await picture("brazier-motion-a")
	for frame in 25: await process_frame
	var second := await picture("brazier-motion-b")
	var difference := 0.0
	var center: Vector2 = game.camera.unproject_position(Vector3(0, 1.4, 0))
	for x in range(-35, 36):
		for y in range(-65, 66):
			var ix := clampi(roundi(center.x) + x, 0, first.get_width() - 1)
			var iy := clampi(roundi(center.y) + y, 0, first.get_height() - 1)
			difference += absf(first.get_pixel(ix, iy).get_luminance() - second.get_pixel(ix, iy).get_luminance())
	check(difference / (71.0 * 131.0) > .002, "real GLES fire visibly moves over time")
	check(game.room.lamps.size() + game.room.shadow_lamps.size() == light_count, "fire adds no dynamic lights")
	# Looking down must leave flames standing above the bowl.
	game.camera.global_position = Vector3(.7, 2.6, 1.1)
	game.camera.look_at(Vector3(0, 1.15, 0))
	await picture("brazier-from-above")
	# Actual in-game viewer, with the full bundled image rather than a cover.
	game.ui.visible = true
	game.ui.open_painting("starry_night", "play")
	await picture("painting-starry-night")
	check(library.has_image("starry_night", "full"), "inspection uses bundled art on the mobile path")
	print("FIRE ART GLES RESULT: %d failures, motion difference %.5f, lights %d" % [failures, difference / (71.0 * 131.0), light_count])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
