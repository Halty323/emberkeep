extends Node
## Device-local preferences. These never travel with profile progress, run saves
## or a future cloud merge. Each field is validated on its own, and engine
## setters run only when the applied value actually changes.
signal changed(key: String)
const PATH := "user://settings.json"
const LEGACY_PROFILE_PATH := "user://profile.json"
const VERSION := 1
const RENDER_SCALES := [.5, .67, .75, 1.0]
const FPS_LIMITS := [30, 60, 90, 120, 0]
const DETAIL_LEVELS := ["low", "balanced", "high"]
const DEFAULTS := {"render_scale": 1.0, "fps_limit": 60, "vsync": true, "show_fps": false,
	"effects_detail": "balanced", "small_details": "balanced",
	"sound": true, "music": true, "shake": true, "touch": false, "shadows": true}
## Profile keys that held device preferences before settings had their own file.
const LEGACY_KEYS := {"sound": "sound", "music": "music", "shake": "shake", "touch": "touch", "quality": "shadows"}
var values: Dictionary = DEFAULTS.duplicate()
## Tests may pin platform capabilities; production always asks the platform.
var capability_override: Dictionary = {}
var _applied: Dictionary = {}

func _ready() -> void:
	load_settings()
	apply_all()

func load_settings() -> void:
	values = DEFAULTS.duplicate()
	_applied.clear()
	if FileAccess.file_exists(PATH):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if saved is Dictionary:
			for key in DEFAULTS:
				if saved.has(key) and is_valid(key, saved[key]):
					values[key] = normalize(key, saved[key])
		return
	# First launch after the split: carry the profile's old choices across once.
	if FileAccess.file_exists(LEGACY_PROFILE_PATH):
		var profile = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_PROFILE_PATH))
		if profile is Dictionary:
			for old_key in LEGACY_KEYS:
				var key: String = LEGACY_KEYS[old_key]
				if profile.has(old_key) and is_valid(key, profile[old_key]):
					values[key] = profile[old_key]
	save_settings()

func save_settings() -> void:
	var data := values.duplicate()
	data["version"] = VERSION
	var file = FileAccess.open(PATH + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
		DirAccess.rename_absolute(PATH + ".tmp", PATH)

func is_valid(key: String, value) -> bool:
	match key:
		"render_scale":
			return (value is float or value is int) and RENDER_SCALES.any(func(s): return is_equal_approx(s, float(value)))
		"fps_limit":
			return (value is float or value is int) and int(value) == value and int(value) in FPS_LIMITS
		"effects_detail", "small_details":
			return value is String and value in DETAIL_LEVELS
		_:
			return DEFAULTS.has(key) and value is bool

func normalize(key: String, value):
	match key:
		"render_scale":
			for s in RENDER_SCALES:
				if is_equal_approx(s, float(value)): return s
		"fps_limit": return int(value)
	return value

func get_value(key: String):
	return values[key]

func set_value(key: String, value) -> bool:
	if not DEFAULTS.has(key) or not is_valid(key, value):
		return false
	value = normalize(key, value)
	if key == "vsync" and not vsync_supported():
		return false
	if typeof(values[key]) == typeof(value) and values[key] == value:
		return true
	values[key] = value
	save_settings()
	apply(key)
	changed.emit(key)
	return true

func choices(key: String) -> Array:
	match key:
		"render_scale": return RENDER_SCALES
		"fps_limit": return FPS_LIMITS
		"effects_detail", "small_details": return DETAIL_LEVELS
	return [false, true]

func cycle(key: String, step := 1) -> void:
	var options := choices(key)
	var index := options.find(values[key])
	set_value(key, options[posmod(index + step, options.size())])

func apply_all() -> void:
	for key in ["render_scale", "fps_limit", "vsync"]:
		apply(key)

func apply(key: String) -> void:
	var value = values[key]
	if _applied.has(key) and _applied[key] == value:
		return
	match key:
		"render_scale":
			# Godot's built-in bilinear 3D scaling: the world buffer shrinks while
			# canvas text and the HUD stay at full display resolution.
			var root := get_tree().root
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			root.scaling_3d_scale = value
		"fps_limit":
			Engine.max_fps = value
		"vsync":
			if not vsync_supported():
				return
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
		_:
			return
	_applied[key] = value

func is_mobile() -> bool:
	if capability_override.has("mobile"): return capability_override.mobile
	return OS.has_feature("android") or OS.has_feature("ios")

## Android/iOS GL cannot honour an application VSync Off request in 4.6.3, and
## headless servers have no swapchain. Those platforms show "System controlled".
func vsync_supported() -> bool:
	if capability_override.has("vsync"): return capability_override.vsync
	return not is_mobile() and not OS.has_feature("web") and DisplayServer.get_name() != "headless"

func effective_vsync_label() -> String:
	if not vsync_supported():
		return "System controlled"
	if DisplayServer.get_name() == "headless":
		return "On" if values.vsync else "Off"
	return "Off" if DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED else "On"

func render_size() -> Vector2i:
	var window := Vector2(get_tree().root.size)
	return Vector2i((window * float(values.render_scale)).round())

func render_scale_label() -> String:
	var size := render_size()
	return "%d%% · %d×%d" % [roundi(float(values.render_scale) * 100), size.x, size.y]

func fps_label() -> String:
	return "Unlimited" if int(values.fps_limit) == 0 else str(values.fps_limit)

## Cosmetic density multiplier for the current effects budget.
func effects_scale() -> float:
	return {"low": .6, "balanced": 1.0, "high": 1.4}[values.effects_detail]

func detail_level() -> int:
	return DETAIL_LEVELS.find(values.small_details)
