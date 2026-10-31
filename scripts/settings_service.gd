extends Node
## Device-local display, graphics and comfort preferences. They are versioned
## separately from the profile so a future cloud-progress merge never touches
## them. Engine setters run only when a value actually changes.
signal changed(key: String)
const VERSION := 1
const PATH := "user://settings.json"
const LEGACY_PROFILE_PATH := "user://profile.json"
const RENDER_SCALES := [0.5, 0.67, 0.75, 1.0]
const FPS_LIMITS := [30, 60, 90, 120, 0]
const DETAIL_LEVELS := ["low", "balanced", "high"]
const DEFAULTS := {"render_scale": 1.0, "fps_limit": 60, "vsync": true, "show_fps": false,
	"effects_detail": "balanced", "small_details": "balanced",
	"fov": 78, "mouse_sensitivity": .0025, "touch_sensitivity": .004, "invert_y": false, "head_bob": false,
	"sound": true, "music": true, "shake": true, "touch": false, "shadows": true}
# Preferences previously stored in profile.json, migrated once.
const LEGACY_KEYS := {"sound": "sound", "music": "music", "shake": "shake", "touch": "touch", "quality": "shadows"}
# Provisional active-room totals; tune on real devices before changing.
const EFFECT_BUDGETS := {"low": {"ambient": 28, "transient": 96, "marks": 24},
	"balanced": {"ambient": 44, "transient": 160, "marks": 40},
	"high": {"ambient": 64, "transient": 256, "marks": 64}}
var values: Dictionary = DEFAULTS.duplicate()
var _applied: Dictionary = {}

func _ready() -> void:
	load_settings()
	# Apply device constraints before the scene creates any render targets.
	apply_render_policy()
	get_tree().root.size_changed.connect(apply_render_policy)
	apply_all()
	var policy = RenderPolicy.current()
	if policy.reason != "":
		print("EMBERKEEP RENDER POLICY v1: %s; MSAA off, screen passes off, 3D budget %d pixels" % [policy.reason, policy.max_3d_pixels])

func load_settings() -> void:
	values = DEFAULTS.duplicate()
	if FileAccess.file_exists(PATH):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if saved is Dictionary:
			# Each field is validated on its own: one bad value never resets the rest.
			for key in DEFAULTS:
				var value = validate(key, saved.get(key))
				if value != null: values[key] = value
			return
	if FileAccess.file_exists(LEGACY_PROFILE_PATH):
		var profile = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_PROFILE_PATH))
		if profile is Dictionary:
			for old_key in LEGACY_KEYS:
				var value = validate(LEGACY_KEYS[old_key], profile.get(old_key))
				if value != null: values[LEGACY_KEYS[old_key]] = value
	save()

func validate(key: String, value) -> Variant:
	if value == null or not DEFAULTS.has(key):
		return null
	match key:
		"fov":
			return float(value) if (value is int or value is float) and value >= 60 and value <= 100 else null
		"mouse_sensitivity", "touch_sensitivity":
			return float(value) if (value is int or value is float) and value >= .0005 and value <= .012 else null
		"render_scale":
			if not (value is float or value is int): return null
			for option in RENDER_SCALES:
				if absf(float(value) - option) < .005: return option
			return null
		"fps_limit":
			if not (value is float or value is int) or float(value) != floorf(float(value)): return null
			return int(value) if int(value) in FPS_LIMITS else null
		"effects_detail", "small_details":
			return value if value is String and value in DETAIL_LEVELS else null
		_:
			return value if value is bool else null

func get_value(key: String) -> Variant:
	return values[key]

func set_value(key: String, value) -> bool:
	var checked = validate(key, value)
	if checked == null:
		push_warning("Rejected setting %s=%s" % [key, str(value)])
		return false
	if values[key] == checked:
		return true
	values[key] = checked
	save()
	apply(key)
	changed.emit(key)
	return true

func options(key: String) -> Array:
	match key:
		"fov": return [65, 72, 78, 85, 90, 100]
		"mouse_sensitivity": return [.001, .0018, .0025, .0035, .005]
		"touch_sensitivity": return [.002, .003, .004, .006, .008]
		"render_scale": return RENDER_SCALES
		"fps_limit": return FPS_LIMITS
		"effects_detail", "small_details": return DETAIL_LEVELS
	return [false, true]

func cycle(key: String, step := 1) -> void:
	var choices = options(key)
	set_value(key, choices[posmod(choices.find(values[key]) + step, choices.size())])

func save() -> void:
	var data = values.duplicate()
	data["version"] = VERSION
	var file = FileAccess.open(PATH + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
		DirAccess.rename_absolute(PATH + ".tmp", PATH)

func apply_all() -> void:
	for key in values: apply(key)

func apply(key: String) -> void:
	if _applied.get(key) == values[key]:
		return
	_applied[key] = values[key]
	match key:
		"render_scale":
			# Godot's built-in Compatibility bilinear scaling: only the 3D buffer
			# shrinks, so canvas text, input and camera projection stay native.
			apply_render_policy()
		"fps_limit":
			Engine.max_fps = values.fps_limit
		"vsync":
			if vsync_supported():
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)

func apply_render_policy() -> void:
	var viewport = get_tree().root
	if not RenderPolicy.current().msaa:
		viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = RenderPolicy.effective_scale(float(values.render_scale), viewport.size)

func vsync_supported() -> bool:
	# Godot 4.6 routes the Android/iOS VSync setter through RenderingDevice; the
	# GLES renderer used here cannot honor it, so mobile is system controlled.
	if OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("web"):
		return false
	return DisplayServer.get_name() != "headless"

func effective_vsync() -> String:
	if not vsync_supported():
		return "system"
	return "off" if DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED else "on"

func render_pixels() -> Vector2i:
	var size = Vector2(get_tree().root.size)
	if size.x <= 0 or size.y <= 0:
		size = Vector2(DisplayServer.window_get_size())
	return Vector2i(roundi(size.x * get_tree().root.scaling_3d_scale), roundi(size.y * get_tree().root.scaling_3d_scale))

func effect_budget(channel: String) -> int:
	return EFFECT_BUDGETS[values.effects_detail][channel]

func detail_level() -> int:
	return DETAIL_LEVELS.find(values.small_details)
