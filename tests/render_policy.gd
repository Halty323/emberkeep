extends SceneTree
## Regression coverage for device-specific GLES safeguards. Uses a simulated
## device policy, not a simulated GPU: real Android validation remains separate.
var checks := 0
var failures := 0
var settings: Node
var game

func _initialize() -> void:
	call_deferred("test_policy")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func test_policy() -> void:
	settings = root.get_node("Settings")
	var affected := RenderPolicy.for_device("Android", "Imagination Technologies", "PowerVR D-Series DXT-48-1536", "gl_compatibility")
	check(not affected.msaa, "Android GLES never requests the unsupported MSAA render target")
	for key in ["post_processing", "glow", "reflections", "refraction"]:
		check(not affected[key], "PowerVR Android omits the incompatible pass: " + key)
	check(affected.lightweight_surfaces, "PowerVR Android selects the bounded surface shader")
	check(affected.reflection_limit == Vector2i(640, 360), "mobile reflection target has a fixed upper bound")
	check(affected.max_3d_pixels == 1280 * 720, "PowerVR main 3D target has a fixed pixel budget")
	var fixtures := [
		["Android", "QUALCOMM", "Adreno 830", "gl_compatibility", false, true],
		["Android", "ARM", "Mali-G720", "gl_compatibility", false, true],
		["iOS", "Apple", "Apple GPU", "gl_compatibility", false, true],
		["Linux", "Imagination Technologies", "PowerVR", "gl_compatibility", true, true],
		["Android", "Imagination Technologies", "PowerVR", "mobile", true, true],
		["Android", "imagINATION Technologies", "unknown", "gl_compatibility", false, false],
		["Android", "unknown", "powerVR", "gl_compatibility", false, false]]
	for fixture in fixtures:
		var policy := RenderPolicy.for_device(fixture[0], fixture[1], fixture[2], fixture[3])
		var name := "%s / %s / %s" % [fixture[0], fixture[2], fixture[3]]
		check(policy.msaa == fixture[4], name + ": MSAA follows the renderer policy")
		check(policy.post_processing == fixture[5] and policy.reflections == fixture[5], name + ": unrelated renderers retain their passes")
		check(policy.lightweight_surfaces == not fixture[5], name + ": surface fallback follows the affected device")
	check(RenderPolicy.for_device("Linux", "Mesa", "llvmpipe", "gl_compatibility").reflection_limit == Vector2i(1280, 720), "desktop reflection target is bounded separately")
	check(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d.mobile", -1)) == 0, "project disables mobile MSAA before the first frame")

	RenderPolicy.device_override = affected
	root.msaa_3d = Viewport.MSAA_2X
	settings.apply_render_policy()
	check(root.msaa_3d == Viewport.MSAA_DISABLED, "runtime safeguard also disables an existing MSAA viewport")
	settings.set_value("effects_detail", "high")
	settings.set_value("small_details", "high")
	settings.set_value("fps_limit", 120)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.screen_fx.apply_quality()
	check(game.vignette.shader.resource_path.ends_with("/vignette.gdshader"), "affected title uses the screen-copy-free vignette")
	check(not game.room_environment.environment.glow_enabled, "affected title does not allocate glow buffers")
	check(settings.values.effects_detail == "high" and settings.values.small_details == "high" and settings.values.fps_limit == 120, "device safeguards preserve the player's saved preferences")
	game.mirror.follow(true, Vector2(2424, 1080))
	check(game.mirror.render_target_update_mode == SubViewport.UPDATE_DISABLED, "requesting water reflection cannot bypass the device safeguard")
	check(game.mirror.msaa_3d == Viewport.MSAA_DISABLED, "reflection viewport never inherits 3D MSAA")
	var look = load("res://scripts/graphics/look.gd")
	var floor_material: ShaderMaterial = look.floor_material({})
	check(floor_material.shader.resource_path.ends_with("/floor_stone_mobile.gdshader"), "affected floors use the lightweight surface shader")
	var mobile_mesh: PlaneMesh = look.floor_mesh()
	check(mobile_mesh.subdivide_width == 0 and mobile_mesh.subdivide_depth == 0, "high-detail fallback floor remains two triangles without vertex displacement")

	game.start_run("candle", 421337, false)
	game.paused = true
	game.residue.add("water", Vector3(-2, 0, 0), 1.2, true)
	game.residue.add("ice", Vector3(2, 0, 0), 1.2, true)
	for kind in ["water", "ice"]:
		check(game.residue.views[kind].material.shader.resource_path.ends_with("/residue.gdshader"), kind + " keeps its visual and gameplay coverage without screen copies")
	check(not game.residue.reflective(), "affected water never requests the reflection viewport")
	check(game.residue.kind_at(Vector3(-2, 0, 0)) == "water", "water gameplay remains present under the visual fallback")
	check(game.residue.kind_at(Vector3(2, 0, 0)) == "ice", "ice gameplay remains present under the visual fallback")

	var old_size := root.size
	root.size = Vector2i(2424, 1080)
	for requested in [1.0, .75, .5]:
		settings.set_value("render_scale", requested)
		settings.apply_render_policy()
		var pixels: Vector2i = settings.render_pixels()
		check(pixels.x * pixels.y <= affected.max_3d_pixels + pixels.x + pixels.y, "PowerVR effective render target stays within budget at requested scale %s" % requested)
		check(root.scaling_3d_scale <= requested + .001, "pixel cap never increases requested render resolution")
		check(is_equal_approx(settings.values.render_scale, requested), "pixel cap leaves the requested scale saved")
	settings.set_value("render_scale", 1.0)
	game.ui.open_settings("pause")
	game.ui.open_settings_page("display")
	await process_frame
	var resolution_row
	for row in game.ui.content.get_children():
		if not row.is_queued_for_deletion() and row.get("setting_key") == "render_scale":
			resolution_row = row
	var display_rows: Array = game.ui.settings_rows("display")
	check("(limited)" in str(display_rows[0][2]), "display settings clearly label the effective device resolution cap")
	check(resolution_row != null and resolution_row.content_fits(), "limited resolution text fits its complete wide-screen settings row")
	root.size = old_size
	settings.apply_render_policy()

	# A different device still gets the full visual path, with a bounded mirror.
	RenderPolicy.device_override = RenderPolicy.for_device("Android", "Qualcomm", "Adreno", "gl_compatibility")
	settings.apply_render_policy()
	game.screen_fx.apply_quality()
	check(game.vignette.shader.resource_path.ends_with("/post.gdshader"), "unaffected Android retains its high-detail post pass")
	check(game.room_environment.environment.glow_enabled, "unaffected Android retains glow")
	var full_material: ShaderMaterial = look.floor_material({})
	check(full_material != floor_material and full_material.shader.resource_path.ends_with("/floor_stone.gdshader"), "surface cache keeps unaffected materials separate from the mobile fallback")
	var full_mesh: PlaneMesh = look.floor_mesh()
	check(full_mesh != mobile_mesh and full_mesh.subdivide_width > 0 and full_mesh.subdivide_depth > 0, "surface cache preserves full-detail meshes on unaffected devices")
	root.size = Vector2i(6000, 4000)
	settings.apply_render_policy()
	game.mirror.follow(true, Vector2(6000, 4000))
	check(game.mirror.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "unaffected Android can render water reflections")
	check(game.mirror.size.x <= 640 and game.mirror.size.y <= 360, "even oversized windows cannot allocate an unbounded mobile reflection")
	root.size = old_size
	settings.apply_render_policy()
	game.mirror.follow(true, Vector2(1280, 720))
	var full_mirror: Vector2i = game.mirror.size
	settings.set_value("render_scale", .5)
	game.mirror.follow(true, Vector2(1280, 720))
	check(game.mirror.size.x < full_mirror.x and game.mirror.size.y < full_mirror.y, "lower main render scale also lowers reflection resolution")
	game.mirror.follow(false, Vector2(1280, 720))
	check(game.mirror.render_target_update_mode == SubViewport.UPDATE_DISABLED, "dry rooms stop the reflection pass")
	game.queue_free()
	await process_frame
	RenderPolicy.device_override = {}
	settings.apply_render_policy()
	print("RENDER POLICY: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
