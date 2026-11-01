extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("exercise")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
func exercise() -> void:
	var settings = root.get_node("Settings")
	check(settings.validate("fullscreen",true)==true and settings.validate("fullscreen","yes")==null,"fullscreen accepts only explicit booleans")
	check(settings.validate("ssao","high")=="high" and settings.validate("ssao","ultra")==null,"ambient occlusion accepts bounded quality modes")
	check(settings.options("ssao")==["off","low","high"],"ambient occlusion has an actual off switch and two bounded budgets")
	settings.set_value("fullscreen",true)
	settings.set_value("ssao","high")
	settings.load_settings()
	check(settings.values.fullscreen and settings.values.ssao=="high","new display preferences survive persistence")
	check(not settings.fullscreen_supported(),"headless mode never applies a window operation")
	RenderPolicy.device_override = RenderPolicy.for_device("Android","Imagination","PowerVR","gl_compatibility")
	check(not settings.ssao_supported() and settings.effective_ssao()=="off","known affected driver cannot allocate a depth/color pass")
	check(settings.values.ssao=="high","device safeguard preserves the saved requested quality")
	RenderPolicy.device_override = RenderPolicy.for_device("Linux","Mesa","llvmpipe","gl_compatibility")
	check(settings.ssao_supported() and settings.effective_ssao()=="high","capable Compatibility rendering exposes actual SSAO")
	var scene = Node3D.new()
	root.add_child(scene)
	var camera = Camera3D.new()
	scene.add_child(camera)
	var pass_node = ScreenAmbientOcclusion.create(camera)
	check(pass_node.get_parent()==camera and pass_node.layers==2,"pass follows its camera and stays out of mirrored lighting layers")
	check(pass_node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"occlusion never casts a fullscreen shadow")
	check(pass_node.surface.render_priority == -128,"opaque contacts are shaded before flames and transparent effects draw")
	pass_node.configure("low",true)
	check(pass_node.visible and pass_node.surface.get_shader_parameter("sample_count")==8,"low uses exactly eight view-space samples")
	var identity = pass_node.get_instance_id()
	pass_node.configure("high",true)
	check(pass_node.get_instance_id()==identity and pass_node.surface.get_shader_parameter("sample_count")==12,"higher quality reuses the same pass with twelve samples")
	pass_node.configure("off",true)
	check(not pass_node.visible,"off removes the draw and its framebuffer copies")
	pass_node.configure("high",false)
	check(not pass_node.visible,"driver policy overrides enabled quality")
	var code = pass_node.surface.shader.code
	check("hint_depth_texture" in code and "INV_PROJECTION_MATRIX" in code,"occlusion reconstructs actual view-space geometry from depth")
	check(not "SubViewport" in code and "distance_to_sample" in code,"sample radius rejects distant depth discontinuities without another viewport")
	check(not "hint_screen_texture" in code and "ALPHA=occlusion" in code,"depth-only darkening preserves the scene's existing tonemapping")
	scene.queue_free()
	await process_frame
	RenderPolicy.device_override = {}
	settings.set_value("fullscreen",false)
	settings.set_value("ssao","low")
	print("SSAO/FULLSCREEN: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
