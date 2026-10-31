extends SceneTree
## Opt-in real-renderer smoke for the startup path in the Pixel 10 report.
## A simulated policy exercises the fallback on desktop GL, not the Android
## driver. Run the exported game on the affected phone to confirm that driver.
var failures := 0
var frames := 0
var max_draws := 0
var samples: Array = []
var game
var settings: Node
var output: String

func _initialize() -> void:
	if OS.get_environment("EMBERKEEP_MOBILE_RENDER_TEST") != "1" or DisplayServer.get_name() == "headless":
		push_error("Use tools/render_mobile_startup.sh with a real display, not --headless.")
		quit(1)
		return
	call_deferred("exercise")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func render_frames(count: int) -> void:
	for frame in count:
		await RenderingServer.frame_post_draw
		frames += 1
		max_draws = maxi(max_draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))

func memory_sample() -> Dictionary:
	return {"texture_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))}

func exercise() -> void:
	output = OS.get_environment("EMBERKEEP_MOBILE_RENDER_OUTPUT")
	var started := Time.get_ticks_msec()
	settings = root.get_node("Settings")
	var native := OS.get_environment("EMBERKEEP_MOBILE_POLICY") == "native"
	if not native:
		RenderPolicy.device_override = RenderPolicy.for_device("Android", "Imagination Technologies", "PowerVR D-Series DXT-48-1536", "gl_compatibility")
	root.size = Vector2i(2424, 1080)
	settings.apply_render_policy()
	settings.set_value("sound", false)
	settings.set_value("music", false)
	settings.set_value("effects_detail", "high")
	settings.set_value("small_details", "high")
	settings.set_value("shadows", true)
	settings.set_value("render_scale", 1.0)
	settings.set_value("fps_limit", 120)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await render_frames(114)
	for detail in ["low", "balanced", "high"]:
		settings.set_value("effects_detail", detail)
		await render_frames(2)
		if not native:
			check(not game.room_environment.environment.glow_enabled, "quality change to " + detail + " preserves the glow safeguard")
			check(game.vignette.shader.resource_path.ends_with("/vignette.gdshader"), "quality change to " + detail + " preserves the post safeguard")
	check(game.in_menu, "startup sample actually rendered the title room")
	if not native:
		check(root.msaa_3d == Viewport.MSAA_DISABLED, "title root has no unsupported MSAA target")
		var pixels: Vector2i = settings.render_pixels()
		check(pixels.x * pixels.y <= 1280 * 720 + pixels.x + pixels.y, "wide-window 3D target stays within the pixel budget")
		check(not game.room_environment.environment.glow_enabled, "title fallback keeps glow disabled")
		check(game.vignette.shader.resource_path.ends_with("/vignette.gdshader"), "title fallback avoids screen-texture post processing")
	root.get_texture().get_image().save_png(output.path_join("mobile-title.png"))
	# Repeat the same content after caches warm. Persistent growth between
	# equivalent visits would otherwise hide behind one successful startup.
	for visit in 3:
		game.start_run("candle", 421337, false)
		game.paused = true
		game.residue.add("water", Vector3(-2, 0, 0), 2.0, true)
		game.residue.add("ice", Vector3(2, 0, 0), 1.5, true)
		# Simulation is paused for a deterministic image: upload dirty masks
		# explicitly so these surfaces really draw, rather than testing hidden nodes.
		for kind in ["water", "ice"]: game.residue.rebuild(kind)
		await render_frames(40)
		if not native:
			check(game.mirror.render_target_update_mode == SubViewport.UPDATE_DISABLED, "wet room %d cannot re-enable the incompatible reflection" % visit)
			for kind in ["water", "ice"]:
				check(game.residue.views[kind].material.shader.resource_path.ends_with("/residue.gdshader"), "wet room %d uses the screen-copy-free %s shader" % [visit, kind])
		samples.append(memory_sample())
	root.get_texture().get_image().save_png(output.path_join("mobile-water.png"))
	check(max_draws < 2000, "startup/one-cell room draw count remains bounded")
	check(samples[2].texture_mb <= samples[0].texture_mb + 16.0, "equivalent room visits do not retain growing texture allocations")
	check(samples[2].video_mb <= samples[0].video_mb + 32.0, "equivalent room visits do not retain growing GPU buffers")
	check(samples[2].nodes <= samples[0].nodes + 32, "equivalent room visits release old room nodes")
	var report := {"renderer": RenderingServer.get_video_adapter_name(), "native_policy": native,
		"frames": frames, "elapsed_ms": Time.get_ticks_msec() - started, "max_draw_calls": max_draws,
		"memory_samples": samples, "failures": failures}
	var report_file := FileAccess.open(output.path_join("mobile-startup.json"), FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	print("EMBERKEEP MOBILE STARTUP REPORT " + JSON.stringify(report))
	game.queue_free()
	await process_frame
	RenderPolicy.device_override = {}
	quit(0 if failures == 0 else 1)
