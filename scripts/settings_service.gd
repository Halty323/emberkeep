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
const SSAO_LEVELS := ["off", "low", "high"]
const DEFAULTS := {"render_scale": 1.0, "fps_limit": 60, "vsync": true, "show_fps": false, "fullscreen": false, "ssao": "low",
	"effects_detail": "balanced", "small_details": "balanced",
	"fov": 78, "mouse_sensitivity": .0025, "touch_sensitivity": .004, "invert_y": false, "head_bob": false,
	"sound": true, "music": true, "shake": true, "touch": false, "shadows": true,
	# Opt out of a device's 3D pixel budget (PowerVR phones): sharper, slower.
	"full_resolution": false,
	# Phones: draw the dungeon smaller while the frame rate is falling short.
	"adaptive_resolution": true,
	# Touch: dragging to look also casts; and where each touch control sits
	# and how large it is ({control: [x, y, scale]}, empty for the defaults).
	"cast_while_aiming": true, "touch_layout": {},
	# How strongly spells, blasts and hurts warp the frame: full, reduced, off.
	"screen_effects": "full",
	# Touch and gamepad: the sight slows over a foe and spells bend onto one
	# just off the crosshair. Never applies to a mouse.
	"aim_assist": true,
	# Touch: pushing the movement stick to its edge runs.
	"touch_run": true,
	# Loudness of sound effects and of the music, 0-100 in tens.
	"sound_volume": 100, "music_volume": 100,
	# Rebound keys: {action: code}; a key's physical keycode, or a mouse
	# button as MOUSE_CODE + its index. Empty for the defaults.
	"keys": {}}
const SCREEN_EFFECTS := ["full", "reduced", "off"]
const VOLUMES := [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
# Keyboard actions and their default keys; the first of each may be rebound.
const KEY_DEFAULTS := {"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE], "dash": [KEY_SHIFT], "sprint": [KEY_CTRL], "interact": [KEY_E], "use_active": [KEY_F],
	"place_bomb": [KEY_B], "map": [KEY_M], "journal": [KEY_TAB], "pause_game": [KEY_ESCAPE, KEY_P]}
const REBINDABLE := ["move_up", "move_down", "move_left", "move_right", "jump", "dash", "sprint", "interact", "use_active", "place_bomb", "map", "journal"]
const MOUSE_CODE := 1 << 30
# Touch controls a layout may move and resize.
const TOUCH_CONTROLS := ["move", "fire", "jump", "dash", "active", "bomb"]
# Preferences previously stored in profile.json, migrated once.
const LEGACY_KEYS := {"sound": "sound", "music": "music", "shake": "shake", "touch": "touch", "quality": "shadows"}
# Provisional active-room totals; tune on real devices before changing.
const EFFECT_BUDGETS := {"low": {"ambient": 28, "transient": 96, "marks": 24},
	"balanced": {"ambient": 44, "transient": 160, "marks": 40},
	"high": {"ambient": 64, "transient": 256, "marks": 64}}
var values: Dictionary = DEFAULTS.duplicate()
var _applied: Dictionary = {}
var _windowed_size := Vector2i.ZERO
var _windowed_position := Vector2i.ZERO

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
		"screen_effects":
			return value if value is String and value in SCREEN_EFFECTS else null
		"sound_volume", "music_volume":
			if not (value is int or value is float) or float(value) != floorf(float(value)): return null
			return int(value) if int(value) in VOLUMES else null
		"keys":
			if not value is Dictionary: return null
			var keys := {}
			for action in value:
				var code = value[action]
				if str(action) in REBINDABLE and (code is int or code is float) and float(code) == floorf(float(code)) and int(code) > 0 and int(code) != KEY_ESCAPE:
					keys[str(action)] = int(code)
			return keys
		"ssao":
			return value if value is String and value in SSAO_LEVELS else null
		"touch_layout":
			if not value is Dictionary: return null
			var layout := {}
			for control in value:
				var spot = value[control]
				if not str(control) in TOUCH_CONTROLS or not spot is Array or spot.size() != 3: continue
				if not spot.all(func(number): return (number is int or number is float) and is_finite(float(number))): continue
				layout[str(control)] = [clampf(float(spot[0]), -400.0, 1680.0), clampf(float(spot[1]), 0.0, 720.0), clampf(float(spot[2]), .6, 1.6)]
			return layout
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
		"ssao": return SSAO_LEVELS
		"screen_effects": return SCREEN_EFFECTS
		"sound_volume", "music_volume": return VOLUMES
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
		"render_scale", "full_resolution", "adaptive_resolution":
			# Godot's built-in Compatibility bilinear scaling: only the 3D buffer
			# shrinks, so canvas text, input and camera projection stay native.
			apply_render_policy()
		"fps_limit":
			Engine.max_fps = values.fps_limit
		"fullscreen":
			apply_fullscreen()
		"vsync":
			if vsync_supported():
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)
		"keys":
			apply_keys()

# ---------------------------------------------------------------- keys

## The keyboard and mouse half of every action: the defaults, with the first
## key of each replaced by the player's own. Gamepad buttons stay as they are.
func apply_keys() -> void:
	for action in KEY_DEFAULTS:
		if not InputMap.has_action(action): InputMap.add_action(action)
		for event in InputMap.action_get_events(action):
			if event is InputEventKey or event is InputEventMouseButton: InputMap.action_erase_event(action, event)
		var codes: Array = KEY_DEFAULTS[action].duplicate()
		if values.keys.has(action): codes[0] = int(values.keys[action])
		for code in codes:
			InputMap.action_add_event(action, input_for(code))

static func input_for(code: int) -> InputEvent:
	if code >= MOUSE_CODE:
		var click := InputEventMouseButton.new()
		click.button_index = code - MOUSE_CODE
		return click
	var key := InputEventKey.new()
	key.physical_keycode = code
	return key

## The key an action answers first, as the player reads it.
func key_label(action: String) -> String:
	var code := int(values.keys.get(action, KEY_DEFAULTS.get(action, [0])[0]))
	return code_label(code)

static func code_label(code: int) -> String:
	if code >= MOUSE_CODE:
		match code - MOUSE_CODE:
			MOUSE_BUTTON_RIGHT: return "Right click"
			MOUSE_BUTTON_MIDDLE: return "Middle click"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
		return "Mouse %d" % (code - MOUSE_CODE)
	var label := OS.get_keycode_string(code)
	return label if label != "" else "Key %d" % code

## Binds an action's first key; an action that had it takes the old one.
func bind_key(action: String, code: int) -> void:
	var keys: Dictionary = values.keys.duplicate()
	var old := int(keys.get(action, KEY_DEFAULTS[action][0]))
	for other in REBINDABLE:
		if other != action and int(keys.get(other, KEY_DEFAULTS[other][0])) == code:
			keys[other] = old
	keys[action] = code
	for other in keys.keys():
		if int(keys[other]) == int(KEY_DEFAULTS[other][0]): keys.erase(other)
	set_value("keys", keys)

func apply_render_policy() -> void:
	var viewport = get_tree().root
	if not RenderPolicy.current().msaa:
		viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var requested := float(values.render_scale)
	var scale := requested if values.full_resolution else RenderPolicy.effective_scale(requested, viewport.size)
	if not adaptive_active(): adaptive = 1.0
	viewport.scaling_3d_scale = maxf(.35, scale * adaptive)

# ---------------------------------------------------------------- adaptive resolution
# Phones measure their own frame rate in two-second windows. Falling short
# of the target lowers the dungeon's resolution a step (text and controls
# stay sharp); a steady margin raises it back, never above the chosen scale.
const ADAPT_WINDOW := 2.0
const ADAPT_FLOOR := .5
var adaptive := 1.0
var adapt_time := 0.0
var adapt_frames := 0
var adapt_calm := 0

func adaptive_active() -> bool:
	return bool(values.adaptive_resolution) and (OS.has_feature("android") or OS.has_feature("ios"))

func _process(delta: float) -> void:
	if not adaptive_active(): return
	adapt_time += delta
	adapt_frames += 1
	if adapt_time < ADAPT_WINDOW: return
	var fps := adapt_frames / adapt_time
	adapt_time = 0.0
	adapt_frames = 0
	var target := float(values.fps_limit) if int(values.fps_limit) > 0 else 60.0
	target = minf(target, 60.0)
	if fps < target * .85 and adaptive > ADAPT_FLOOR:
		adaptive = maxf(ADAPT_FLOOR, adaptive - .1)
		adapt_calm = 0
		apply_render_policy()
	elif fps >= target * .97 and adaptive < 1.0:
		adapt_calm += 1
		if adapt_calm >= 3:
			adapt_calm = 0
			adaptive = minf(1.0, adaptive + .05)
			apply_render_policy()
	else:
		adapt_calm = 0

## Whether this device caps the 3D resolution (the player may lift the cap).
func resolution_capped() -> bool:
	return int(RenderPolicy.current().max_3d_pixels) > 0

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

func fullscreen_supported() -> bool:
	return OS.get_name() not in ["Android", "iOS", "Web"] and DisplayServer.get_name() != "headless"

func apply_fullscreen() -> void:
	if not fullscreen_supported(): return
	var mode := DisplayServer.window_get_mode()
	if values.fullscreen:
		if mode not in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
			_windowed_size = DisplayServer.window_get_size()
			_windowed_position = DisplayServer.window_get_position()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		if mode in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			if _windowed_size.x>0:
				DisplayServer.window_set_size(_windowed_size)
				DisplayServer.window_set_position(_windowed_position)

func ssao_supported() -> bool:
	return bool(RenderPolicy.current().get("ambient_occlusion",true))

func effective_ssao() -> String:
	return str(values.ssao) if ssao_supported() else "off"

func adaptive_supported() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")
