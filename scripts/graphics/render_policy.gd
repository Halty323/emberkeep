class_name RenderPolicy
extends RefCounted
## Effective GPU capabilities, separate from saved player preferences.
## PowerVR GLES has rejected the MSAA/internal-buffer combination on Pixel 10
## (GL_FRAMEBUFFER_UNSUPPORTED, 0x8CDD). Avoid that path before any 3D draws;
## use bounded, single-pass materials on that driver family as well.
## This override is used only by automated device-policy regression fixtures.
static var device_override: Dictionary = {}
static var _detected: Dictionary = {}

static func for_device(platform: String, vendor: String, adapter: String, method: String) -> Dictionary:
	var mobile_gles = platform in ["Android", "iOS"] and method == "gl_compatibility"
	var gpu = (vendor + " " + adapter).to_lower()
	var powervr: bool = platform == "Android" and mobile_gles and ("powervr" in gpu or "imagination" in gpu)
	# Exynos phones: Mali (vendor ARM) and Samsung's Xclipse. Their GLES
	# drivers fall far behind on full-screen passes and heavy surfaces at
	# native resolution, so they take the same bounded path, without SSAO.
	var exynos: bool = platform == "Android" and mobile_gles and (vendor.to_lower().strip_edges() == "arm" or "mali" in gpu or "xclipse" in gpu or "samsung" in gpu)
	var conservative: bool = powervr or exynos
	return {
		"msaa": not mobile_gles,
		"post_processing": not conservative,
		# Contact AO reads depth only. It does not use the color-copy/MSAA
		# path that failed on PowerVR; keep a smaller finite sampling budget.
		"ambient_occlusion": not exynos,
		"ssao_samples": Vector2i(6,8) if conservative else Vector2i(8,12),
		"glow": not conservative,
		"reflections": not conservative,
		"refraction": not conservative,
		"lightweight_surfaces": conservative,
		"max_3d_pixels": 1280 * 720 if conservative else 0,
		"reflection_limit": Vector2i(640, 360) if mobile_gles else Vector2i(1280, 720),
		"reason": "PowerVR GLES compatibility" if powervr else ("Mali/Xclipse GLES performance" if exynos else "")
	}

static func current() -> Dictionary:
	if not device_override.is_empty(): return device_override
	if _detected.is_empty():
		_detected = for_device(OS.get_name(), RenderingServer.get_video_adapter_vendor(),
			RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method())
	return _detected

static func effective_scale(requested: float, pixels: Vector2i) -> float:
	var budget = int(current().max_3d_pixels)
	if budget <= 0 or pixels.x <= 0 or pixels.y <= 0: return requested
	return minf(requested, sqrt(float(budget) / (float(pixels.x) * pixels.y)))
