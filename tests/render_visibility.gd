extends SceneTree
## Actual GL captures of lit enemies and a non-stacking mist surface. Uses
## the mobile-safe policy on desktop GL; this is not a PowerVR driver test.
var failures := 0
var checks := 0
var game
var run
var output: String
var baseline := false
var measurements := {}

func _initialize() -> void:
	if OS.get_environment("EMBERKEEP_VISIBILITY_TEST") != "1" or DisplayServer.get_name() == "headless":
		push_error("Use tools/render_visibility.sh with an OpenGL display.")
		quit(1)
		return
	call_deferred("capture")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not baseline:
		failures += 1
		push_error("FAIL: " + message)

func image_at(name: String) -> Image:
	for frame in 3: await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	image.save_png(output.path_join(name + ".png"))
	return image

func pixel_at(image: Image, at: Vector3, radius := 2) -> Color:
	var point: Vector2 = game.camera.unproject_position(at)
	var scale = Vector2(image.get_width(), image.get_height()) / game.get_viewport().get_visible_rect().size
	point *= scale
	var color := Color(0, 0, 0, 0)
	var count := 0
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			color += image.get_pixel(clampi(roundi(point.x) + x, 0, image.get_width() - 1), clampi(roundi(point.y) + y, 0, image.get_height() - 1))
			count += 1
	return color / float(count)

func quiet_room(template_id := "hearth_1x1") -> void:
	var generator = load("res://scripts/dungeon/floor_generator.gd")
	var catalog = root.get_node("Content")
	var floor_data = {"rooms": {}, "portals": {}, "owners": {}, "generator": 2}
	var id = generator.place_room(floor_data, catalog.record("rooms", template_id), 0, Vector2i.ZERO, 531, 1)
	var room: Dictionary = floor_data.rooms[id]
	room.type = "combat"
	room.cleared = true
	room.claimed = true
	room.props = []
	room.chests = []
	room.mounts = []
	room.pickups = []
	# The test lantern faces the same visible hemisphere as the camera.
	room.lights = [[0.0, 1.5], [5.5, 4.0]]
	room.lit = []
	run.rooms = floor_data.rooms
	run.portals = {}
	run.current_room = id
	game.enter_room(Vector3(0, 0, 5.5))
	game.paused = true
	game.set_process(false)
	game.set_physics_process(false)
	game.ui.hide()
	game.room.set_process(false)
	game.room.ember_mesh.visible = false
	game.room.effects.set_process(false)
	game.room.effects.emitters.clear()
	game.room.effects.particles.multimesh.visible_instance_count = 0
	game.camera_focus = Vector3.ZERO
	game.camera.position = game.camera_home
	game.camera.look_at(Vector3.ZERO)
	game.camera.size = 14.4

func age_clouds() -> void:
	for cloud in game.residue.clouds: cloud.age = .35
	if game.residue.has_method("refresh_cloud_surface"): game.residue.refresh_cloud_surface()

func visible_body(foe) -> bool:
	for mesh in foe.visual.find_children("*", "MeshInstance3D", true, false):
		if mesh.get_parent() != foe.eyes and mesh.is_visible_in_tree(): return true
	return false

func capture() -> void:
	output = OS.get_environment("EMBERKEEP_VISIBILITY_OUTPUT")
	baseline = OS.get_environment("EMBERKEEP_VISUAL_BASELINE") == "1"
	run = root.get_node("Run")
	var settings = root.get_node("Settings")
	RenderPolicy.device_override = RenderPolicy.for_device("Android", "Imagination Technologies", "PowerVR", "gl_compatibility")
	settings.apply_render_policy()
	for key in ["sound", "music", "shake"]: settings.set_value(key, false)
	settings.set_value("effects_detail", "high")
	settings.set_value("small_details", "high")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_run("candle", 64872557, false)
	run.plan_climb("legacy_tower")
	run.floor_number = 1
	quiet_room()
	var foe = game.spawn_enemy(Vector3(-2.3, 0, -1.3), "spitter")
	var second = game.spawn_enemy(Vector3(2.4, 0, -.5), "charger")
	foe.update_light_state()
	second.update_light_state()
	var body_at: Vector3 = foe.global_position + Vector3(0, foe.radius * 1.1, 0)
	var dark = await image_at("enemies-dark")
	var dark_color = pixel_at(dark, body_at)
	check(visible_body(foe) and visible_body(second), "ordinary enemy bodies remain present beyond the player's light")
	check(dark_color.get_luminance() > .025, "a shaded enemy is readable in the cellar")
	measurements["dark_body_luminance"] = dark_color.get_luminance()
	game.room.set_lantern(0, true)
	foe.update_light_state()
	second.update_light_state()
	var warm = await image_at("enemies-warm")
	var warm_color = pixel_at(warm, body_at)
	check(warm_color.get_luminance() > dark_color.get_luminance() + .01, "the same body brightens under a nearby lantern")
	check(warm_color.r - dark_color.r > warm_color.b - dark_color.b, "lantern warmth changes the body colour")
	measurements["warm_body_luminance"] = warm_color.get_luminance()
	measurements["lantern_red_gain"] = warm_color.r - dark_color.r
	measurements["lantern_blue_gain"] = warm_color.b - dark_color.b
	game.residue.add_cloud(Vector3(0, 0, 0), 2.5, "steam")
	age_clouds()
	var single = await image_at("mist-single")
	game.residue.add_cloud(Vector3(0, 0, 0), 2.5, "steam")
	age_clouds()
	var duplicate = await image_at("mist-duplicate")
	var cloud_at = Vector3(0, .62, 0)
	var single_color = pixel_at(single, cloud_at, 10)
	var duplicate_color = pixel_at(duplicate, cloud_at, 10)
	var clear_color = pixel_at(warm, cloud_at, 10)
	var presence = (absf(single_color.r - clear_color.r) + absf(single_color.g - clear_color.g) + absf(single_color.b - clear_color.b)) / 3.0
	check(presence > .0015, "steam is actually visible rather than passing the overlap check while absent")
	var duplicate_gain = duplicate_color.get_luminance() - single_color.get_luminance()
	check(absf(duplicate_gain) < .008, "coincident steam clouds do not accumulate white opacity")
	measurements["mist_mean_channel_change"] = presence
	measurements["coincident_mist_luminance_gain"] = duplicate_gain
	game.residue.add_cloud(Vector3(-2.3, 0, -1.3), 1.5, "spores")
	age_clouds()
	foe.update_light_state()
	check(visible_body(foe), "mist does not switch an enemy's body off")
	await image_at("mist-overlap")
	game.residue.add("water", Vector3(-1, 0, 0), 3.8, true)
	game.residue.add("ice", Vector3(2.3, 0, -.5), 1.8, true)
	for kind in ["water", "ice"]: game.residue.rebuild(kind)
	await image_at("wet-room-mist")
	# An L's empty quadrant must remain unchanged even when a cloud spans it.
	quiet_room("bend_l3")
	game.player.place(Vector3(6, 0, 4))
	game.camera.position = game.camera_home + Vector3(6, 0, 4)
	game.camera.look_at(Vector3(6, 0, 4))
	var clear_notch = await image_at("l-room-clear")
	game.residue.add_cloud(Vector3(8.7, 0, 6.7), 6.0, "steam")
	age_clouds()
	var mist_notch = await image_at("l-room-mist")
	var outside = Vector3(12.5, .62, 10.5)
	var before = pixel_at(clear_notch, outside, 3)
	var after = pixel_at(mist_notch, outside, 3)
	var notch_gain = absf(after.get_luminance() - before.get_luminance())
	check(notch_gain < .003, "mist does not render in the L-room's missing quadrant")
	measurements["l_notch_luminance_change"] = notch_gain
	check(root.msaa_3d == Viewport.MSAA_DISABLED, "visual fixes keep the safe mobile MSAA policy")
	var report = {"checks": checks, "failures": failures, "baseline": baseline,
		"renderer": RenderingServer.get_video_adapter_name(), "measurements": measurements}
	var file = FileAccess.open(output.path_join("visibility.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("EMBERKEEP VISIBILITY REPORT " + JSON.stringify(report))
	game.queue_free()
	await process_frame
	RenderPolicy.device_override = {}
	quit(0 if failures == 0 else 1)
