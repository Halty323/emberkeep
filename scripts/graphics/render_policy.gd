class_name RenderPolicy
extends RefCounted
## Effective GPU capabilities, separate from saved player preferences.
## PowerVR GLES has rejected the MSAA/internal-buffer combination on Pixel 10
## (GL_FRAMEBUFFER_UNSUPPORTED, 0x8CDD). Avoid that path before any 3D draws;
## use bounded, single-pass materials on that driver family as well.
## The renderer itself (Forward+, Mobile or Compatibility) is picked before
## any script runs; see RendererChoice.
## This override is used only by automated device-policy regression fixtures.
static var device_override: Dictionary = {}
static var _detected: Dictionary = {}

static func for_device(platform: String, vendor: String, adapter: String, method: String) -> Dictionary:
	var mobile: bool = platform in ["Android", "iOS"]
	var gles: bool = method == "gl_compatibility"
	var mobile_gles: bool = mobile and gles
	var gpu = (vendor + " " + adapter).to_lower()
	var powervr_chip: bool = platform == "Android" and ("powervr" in gpu or "imagination" in gpu)
	# The Pixel 10 failures were in PowerVR's GLES driver: on OpenGL the safe
	# path is a hard limit. On Vulkan it starts bounded but may be relaxed.
	var powervr: bool = powervr_chip and gles
	# Exynos phones: Mali (vendor ARM) and Samsung's Xclipse. Their GLES
	# drivers fall far behind on full-screen passes and heavy surfaces, so
	# they start on the bounded path; it is a default, not a lock: High
	# effects detail restores every pass (see current()).
	var exynos: bool = platform == "Android" and (vendor.to_lower().strip_edges() == "arm" or "mali" in gpu or "xclipse" in gpu or "samsung" in gpu)
	var conservative: bool = powervr_chip or exynos
	var reason := ""
	if powervr: reason = "PowerVR GLES compatibility"
	elif powervr_chip: reason = "PowerVR Vulkan performance"
	elif exynos: reason = "Mali/Xclipse %s performance" % ("GLES" if gles else "Vulkan")
	return {
		"renderer": method,
		# Forward+ (computers): the engine's own SSAO, SSIL and volumetric fog.
		"forward_plus": method == "forward_plus",
		# Phones never pay for MSAA: the Pixel 10's GLES driver rejected it,
		# and on tiled GPUs it costs more than the render scale it would save.
		"msaa": not mobile,
		"post_processing": not conservative,
		# Contact AO reads depth only. It does not use the color-copy/MSAA
		# path that failed on PowerVR; keep a smaller finite sampling budget.
		"ambient_occlusion": true,
		"ssao_samples": Vector2i(6,8) if conservative else Vector2i(8,12),
		# Bloom runs on every device: the PowerVR failure was the MSAA buffer
		# (kept off above), not the glow pass. The player's Bloom setting
		# (Off / Soft / Strong) is the only switch.
		"glow": true,
		"reflections": not conservative,
		"refraction": not conservative,
		"lightweight_surfaces": conservative,
		"max_3d_pixels": 1280 * 720 if conservative else 0,
		"reflection_limit": Vector2i(640, 360) if mobile else Vector2i(1280, 720),
		"reason": reason,
		"relaxable": conservative and not powervr
	}

static var _relaxed: Dictionary = {}

static func current() -> Dictionary:
	if not device_override.is_empty(): return device_override
	if _detected.is_empty():
		_detected = for_device(OS.get_name(), RenderingServer.get_video_adapter_vendor(),
			RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method())
	if _detected.get("relaxable", false) and chosen_high(): return relaxed(_detected)
	return _detected

## A performance default the player has overruled by choosing High effects.
static func relaxed(policy: Dictionary) -> Dictionary:
	if _relaxed.is_empty():
		_relaxed = policy.duplicate()
		for key in ["post_processing", "glow", "reflections", "refraction"]: _relaxed[key] = true
		_relaxed.lightweight_surfaces = false
		_relaxed.ssao_samples = Vector2i(8, 12)
	return _relaxed

static func chosen_high() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var settings = tree.root.get_node_or_null("Settings") if tree else null
	return settings != null and str(settings.values.get("effects_detail", "")) == "high"

static func effective_scale(requested: float, pixels: Vector2i) -> float:
	var budget = int(current().max_3d_pixels)
	if budget <= 0 or pixels.x <= 0 or pixels.y <= 0: return requested
	return minf(requested, sqrt(float(budget) / (float(pixels.x) * pixels.y)))
