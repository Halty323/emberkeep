class_name GameInterface
extends Control
const INK := Color("f5ead2")
const MUTED := Color("c4bda7")
const GOLD := Color("f1cc8a")
const PANEL := Color("44463e")
const EDGE := Color("9d8861")
# The logical canvas is 720 high and 1280 wide, or wider on screens wider
# than 16:9. The play HUD is laid out in three groups at 1280: the left group
# keeps its place, the middle group follows the centre and the right group the
# right edge (see widen()). Other screens are centred whole.
# Middle group.
const INTERACTION_RECT := Rect2(410, 564, 460, 78)
const TOAST_RECT := Rect2(420, 82, 440, 80)
const BOSS_RECT := Rect2(470, 16, 340, 50)
# Right group.
const DASH_CENTER := Vector2(973, 610)
const DASH_RADIUS := 48.0
# One hit-region table drives drawing, touch and mouse handling alike.
const ACTION_BUTTONS := {"dash": {"center": Vector2(973, 610), "radius": 48.0},
	"active": {"center": Vector2(904, 510), "radius": 44.0},
	"bomb": {"center": Vector2(1032, 486), "radius": 38.0},
	"fire": {"center": Vector2(1178, 552), "radius": 56.0},
	"jump": {"center": Vector2(1178, 660), "radius": 48.0}}
# The move stick rests here (left group) until a thumb takes it.
const MOVE_REST := Vector2(140, 574)
const MOVE_RADIUS := 66.0
const MINIMAP_RECT := Rect2(1032, 16, 164, 120)
const MINIMAP_AREA := Rect2(1040, 24, 148, 104)
const PAUSE_RECT := Rect2(1204, 16, 60, 56)
# Left group: one small slab for health, resources, weapon and held item.
const HUD_RECT := Rect2(16, 16, 292, 112)
const WEAPON_LABEL := Vector2(30, 97)
const JOURNAL_PAGE_SIZE := 6
const FLOOR_PAGE_SIZE := 4
const BAND_LABELS := {"first": "THE FIRST FLOOR", "middle": "THE MIDDLE FLOORS", "summit": "THE SUMMIT"}
const FULL_MAP_AREA := Rect2(180, 150, 920, 420)
# A floor's name spells itself across the screen, holds, then fades.
const TITLE_DELAY := .35
const TITLE_LETTER := .07
const TITLE_HOLD := 1.6
const TITLE_FADE := .9
# A newly walked cell is scribbled onto the map over this long.
const SCRIBBLE_TIME := .75
# The loading screen's words while a run is prepared.
const LOADING_TIPS := ["Frost on a soaked foe freezes it solid.", "Some relics answer each other. The journal keeps what you find.",
	"A spellbook sings with relics of its own element.", "Shoot a dead lantern to light it again.",
	"Dash past an enemy ember to catch it as a spark.", "Foes standing in lantern light take more damage.",
	"Water carries lightning to every foe standing in it.", "Fire meeting a chilled foe cracks it open."]
# Where the map helpers draw: this control, or the turning minimap view.
var loading_title := "The tower stirs"
var loading_progress := 0.0
# Screens laid out against the edges rather than centred whole.
const TITLE_MODES := ["play", "menu", "armory", "coop", "lobby"]
const REWARD_WIDTH := 340.0
const REWARD_GAP := 26.0
const SETTINGS_PAGES := [["display", "Display"], ["graphics", "Graphics"], ["controls", "Controls"], ["camera", "Camera"], ["sound", "Sound"], ["keys", "Keys"]]
const SETTINGS_NOTES := {"display": "Resolution scales only the dungeon; text and controls stay sharp. Your display or device can still cap the frame rate.",
	"graphics": "SSAO shades surface contacts on supported GPUs. Detail changes appearance; room collision and combat stay identical.",
	"camera": "Comfort settings affect presentation, never movement speed or spell damage.",
	"controls": "Touch controls show the on-screen sticks and action buttons on any device.",
	"sound": "Click a row to step it up; right-click steps it back down.",
	"keys": ""}
# The action whose key is being changed (Settings, Keys), or "".
var rebinding := ""
var settings_row_count := 0
const KEY_LABELS := {"move_up": "Forward", "move_down": "Back", "move_left": "Left", "move_right": "Right", "jump": "Jump",
	"dash": "Dash", "sprint": "Run", "interact": "Interact", "use_active": "Use item", "place_bomb": "Bomb", "map": "Map", "journal": "Journal"}
var game: Node3D
var body: Font = preload("res://assets/fonts/body.ttf")
var heading: Font = preload("res://assets/fonts/display.ttf")
var bold: Font = preload("res://assets/fonts/bold.ttf")
var content: Control
var surface_layer: Control
var backdrop: ColorRect
var surfaces: Array[DungeonUISurface] = []
var lighting_lamps := PackedVector4Array()
var lighting_colors := PackedColorArray()
var toast_surface: DungeonUISurface
var interaction_surface: DungeonUISurface
var boss_surface: DungeonUISurface
var minimap_clip: Control
var minimap_ink: Node2D
var minimap_pointer: Node2D
var room_ink_cache: Dictionary = {}
var mode = "menu"
var previous_mode = "menu"
var scale_value = 1.0
var offset = Vector2.ZERO
var starter_index = 0
# The seed the menu forges its weapons from when no seed is typed: rolled
# afresh whenever the title opens and after every run.
var menu_seed = 0
var selected_seed = ""
var seed_field: LineEdit
var offers: Array = []
var shop = false
var dark = false
# Death's bargain: the offer chosen from its right hand (-1 for none) and the
# price from its left ("curse", "trial" or "").
var bargain_pick := -1
var bargain_price := ""
const BARGAIN_TAKE := Rect2(48, 204, 400, 116)
const BARGAIN_STEP := 128.0
const CURSE_RECT := Rect2(832, 204, 400, 184)
const TRIAL_RECT := Rect2(832, 400, 400, 184)
var toast_text = ""
var toast_detail = ""
var toast_color = GOLD
var toast_time = 0.0
var floating_numbers: Array[Dictionary] = []
var left_touch = -1
var right_touch = -1
var left_origin = Vector2(140, 574)
# The touch layout being arranged (mode "layout"): {control: [x, y, scale]},
# the control chosen, and the one a finger is dragging and from where on it.
var layout_draft: Dictionary = {}
var layout_selected := ""
var layout_dragging := ""
var layout_grab := Vector2.ZERO
var layout_finger := -1
# A brief glow on the crosshair's dash arc when the dash comes back.
var dash_ready_glow := 0.0
var dash_was_cooling := false
var right_origin = Vector2(1112, 574)
var left_vector = Vector2.ZERO
var right_vector = Vector2.ZERO
var look_delta = Vector2.ZERO
var fire_touch := -1
var touch_used = false
# True while a mouse press that began on an action button is held, so the
# click can never turn into weapon fire.
var mouse_on_action = false
var journal_page = 0
var elapsed_ui = 0.0
var secret_taps = 0
var secret_key_buffer = ""
# Floor cell -> the moment it was uncovered, while its scribble is still drawing.
var scribbles: Dictionary = {}
var secret_field: LineEdit
var secret_feedback = ""
var settings_page = "display"
var journal_tab = "relics"
var painting_id = ""
var painting_back = "play"
var painting_texture: Texture2D
var painting_unlock = ""
var fps_frames = 0
var fps_time = 0.0
var fps_value = 0.0
var view_width = 1280.0
# When the current floor's title began, or below zero for none showing.
var floor_title_start = -100.0

func setup(owner_game: Node3D) -> void:
	game = owner_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop = ColorRect.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.show_behind_parent = true
	add_child(backdrop)
	surface_layer = Control.new()
	surface_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface_layer.show_behind_parent = true
	add_child(surface_layer)
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	get_viewport().size_changed.connect(resize)
	resize()
	show_screen("menu")

func is_touch_platform() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")

func resize() -> void:
	var size_value = get_viewport_rect().size
	var safe_rect = Rect2(Vector2.ZERO, size_value)
	if is_touch_platform():
		var safe_screen = Rect2(DisplayServer.get_display_safe_area())
		var window_size = Vector2(DisplayServer.window_get_size())
		if window_size.x > 0 and window_size.y > 0 and safe_screen.has_area():
			var ratio = size_value / window_size
			var candidate = Rect2(safe_screen.position * ratio, safe_screen.size * ratio)
			safe_rect = safe_rect.intersection(candidate)
			if not safe_rect.has_area(): safe_rect = Rect2(Vector2.ZERO, size_value)
	scale_value = minf(safe_rect.size.x / 1280.0, safe_rect.size.y / 720.0)
	var width = maxf(1280.0, safe_rect.size.x / scale_value)
	var widened = not is_equal_approx(width, view_width)
	view_width = width
	offset = safe_rect.position + (safe_rect.size - Vector2(view_width, 720) * scale_value) / 2.0
	for layer in [content, surface_layer]:
		if layer:
			layer.scale = Vector2.ONE * scale_value
			layer.size = Vector2(view_width, 720)
	place_layers()
	# Edge-anchored controls are placed when a screen is built.
	if widened and game and content and mode in TITLE_MODES: show_screen(mode)
	queue_redraw()

func local_point(at: Vector2) -> Vector2:
	return (at - offset) / scale_value

## How much wider than 1280 the logical canvas is.
func widen() -> float:
	return view_width - 1280.0

## A canvas point in the right group's 1280-wide layout.
func from_right(at: Vector2) -> Vector2:
	return at - Vector2(widen(), 0)

## A canvas point in the middle group's 1280-wide layout.
func from_middle(at: Vector2) -> Vector2:
	return at - Vector2(widen() / 2.0, 0)

func moved(rect: Rect2, by: float) -> Rect2:
	return Rect2(rect.position + Vector2(by, 0), rect.size)

## Play and the title place their own edge-anchored groups; every other
## screen is centred whole.
func layer_shift() -> float:
	return 0.0 if mode in TITLE_MODES else widen() / 2.0

func place_layers() -> void:
	var at = offset + Vector2(layer_shift() * scale_value, 0)
	for layer in [content, surface_layer]:
		if layer: layer.position = at
	for surface in surfaces:
		if is_instance_valid(surface): surface.set_logical_origin(Vector2(layer_shift(), 0))

## Draws the next items in a group's layout, moved by `by`.
func anchor(by: float) -> void:
	draw_set_transform(offset + Vector2(by * scale_value, 0), 0, Vector2.ONE * scale_value)

func show_screen(screen: String) -> void:
	mode = screen
	secret_taps = 0
	secret_key_buffer = ""
	secret_feedback = ""
	secret_field = null
	left_touch = -1
	right_touch = -1
	left_vector = Vector2.ZERO
	right_vector = Vector2.ZERO
	look_delta = Vector2.ZERO
	fire_touch = -1
	minimap_clip = null
	minimap_ink = null
	minimap_pointer = null
	for child in content.get_children():
		if child is CanvasItem: child.hide()
		if game.first_person: content.remove_child(child)
		child.queue_free()
	for child in surface_layer.get_children():
		child.hide()
		if game.first_person: surface_layer.remove_child(child)
		child.queue_free()
	surfaces.clear()
	toast_surface = null
	interaction_surface = null
	boss_surface = null
	backdrop.color = Color(.025, .035, .035, .74) if mode not in TITLE_MODES else Color(0, 0, 0, 0)
	if mode == "loading": backdrop.color = Color(.012, .016, .016, 1)
	if mode == "layout": backdrop.color = Color(.02, .03, .03, .5)
	# Death stays in view between its two hands.
	if mode == "bargain": backdrop.color = Color(.02, .01, .03, .38)
	place_layers()
	build_surfaces()
	seed_field = null
	match mode:
		"menu": build_menu()
		"armory": build_armory()
		"coop": CoopMenus.build_coop(self)
		"lobby": CoopMenus.build_lobby(self)
		"play":
			# The journal stays a key (Tab) or a pause-menu entry away.
			button("II", moved(PAUSE_RECT, widen()), func(): game.pause_game(), false)
			# The minimap itself opens the full floor map.
			var map_button = Button.new()
			map_button.name = "MapButton"
			map_button.position = moved(MINIMAP_RECT, widen()).position
			map_button.size = MINIMAP_RECT.size
			map_button.focus_mode = Control.FOCUS_NONE
			for state in ["normal", "hover", "pressed", "focus"]:
				map_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
			map_button.pressed.connect(func(): open_map("play"))
			content.add_child(map_button)
			if game.first_person: build_rotating_minimap()
		"map":
			button("← Back", Rect2(396, 590, 488, 58), func(): close_subscreen())
		"pause":
			button("Continue the journey", Rect2(430, 280, 420, 62), func(): game.resume_game(), true)
			button("Journal", Rect2(430, 358, 420, 58), func(): open_journal("pause"))
			button("Settings", Rect2(430, 432, 420, 58), func(): open_settings("pause"))
			button("Leave the party" if game.party.climbing() else "Return to title", Rect2(430, 506, 420, 58), func(): game.return_to_title())
			var trigger = Button.new()
			trigger.name = "SecretTrigger"
			trigger.position = Vector2(410, 146)
			trigger.size = Vector2(460, 76)
			trigger.focus_mode = Control.FOCUS_NONE
			for state in ["normal", "hover", "pressed", "focus"]:
				trigger.add_theme_stylebox_override(state, StyleBoxEmpty.new())
			trigger.pressed.connect(register_secret_tap)
			content.add_child(trigger)
		"secret": build_secret_code()
		"reward": build_rewards()
		"bargain": build_bargain()
		"journal": build_journal()
		"painting": button("← Back", Rect2(812, 598, 360, 58), func(): close_painting())
		"settings": build_settings()
		"layout": build_layout()
		"dead", "won":
			if Session.online and Session.hosting:
				button("Climb again together", Rect2(430, 457, 420, 62), func(): game.party.regroup(), true)
			elif not Session.online:
				button("One more little light", Rect2(430, 457, 420, 62), func():
					reforge()
					game.begin_run(starter_weapon().id, menu_seed, false), true)
			button("Leave the party" if Session.online else "Return to title", Rect2(430, 535, 420, 58), func(): game.return_to_title())
	sync_lighting()
	update_surface_visibility()
	sync_minimap()
	queue_redraw()

func make_surface(rect: Rect2, background := PANEL, accent := EDGE, compact := false) -> DungeonUISurface:
	var surface = DungeonUISurface.new()
	surface_layer.add_child(surface)
	surface.configure(rect, background, accent, compact)
	surface.set_logical_origin(Vector2(layer_shift(), 0))
	surfaces.append(surface)
	return surface

func reward_rect(index: int) -> Rect2:
	var total = offers.size() * REWARD_WIDTH + maxi(0, offers.size() - 1) * REWARD_GAP
	return Rect2((1280 - total) / 2.0 + index * (REWARD_WIDTH + REWARD_GAP), 196, REWARD_WIDTH, 366)

func journal_rect(slot: int) -> Rect2:
	return Rect2(64 + (slot % 2) * 588, 212 + (slot / 2) * 126, 564, 110)

func journal_page_count() -> int:
	if journal_tab == "floors": return maxi(1, ceili(float(Content.families.floors.size()) / FLOOR_PAGE_SIZE))
	if journal_tab == "combos": return maxi(1, ceili(float(Synergies.all_ids().size()) / JOURNAL_PAGE_SIZE))
	return maxi(1, ceili(float(Content.items.size()) / JOURNAL_PAGE_SIZE))

func floor_rect(slot: int) -> Rect2:
	return Rect2(64 + (slot % 2) * 588, 212 + (slot / 2) * 206, 564, 190)

func change_journal_page(step: int) -> void:
	journal_page = clampi(journal_page + step, 0, journal_page_count() - 1)
	show_screen("journal")

func build_surfaces() -> void:
	match mode:
		"menu":
			if not game.first_person:
				make_surface(Rect2(36, 28, 474, 660))
				make_surface(moved(Rect2(762, 530, 472, 156), widen()))
		"play":
			make_surface(HUD_RECT)
			make_surface(moved(MINIMAP_RECT, widen()), Color("363c37"))
			toast_surface = make_surface(moved(TOAST_RECT, widen() / 2.0), Color("45483b"), GOLD)
			interaction_surface = make_surface(moved(INTERACTION_RECT, widen() / 2.0), PANEL, GOLD)
			boss_surface = make_surface(moved(BOSS_RECT, widen() / 2.0), Color("2e3430"), Color("bb8969"))
		"pause": make_surface(Rect2(376, 108, 528, 520))
		"secret": make_surface(Rect2(376, 140, 528, 448))
		"settings": make_surface(Rect2(300, 40, 680, 640))
		"reward":
			for i in offers.size():
				make_surface(reward_rect(i), PANEL, offer_info(offers[i]).color)
		"bargain":
			var calm := Color("5d5068")
			for i in offers.size():
				make_surface(bargain_rect(i), Color("2b2433") if i == bargain_pick else Color("1f1b25"), offer_info(offers[i]).color if i == bargain_pick else calm)
			make_surface(CURSE_RECT, Color("2b2433") if bargain_price == "curse" else Color("1f1b25"), DeathBargain.COLOR if bargain_price == "curse" else calm)
			make_surface(TRIAL_RECT, Color("2b2433") if bargain_price == "trial" else Color("1f1b25"), DeathBargain.COLOR if bargain_price == "trial" else calm)
		"painting": make_surface(Rect2(80, 40, 1120, 640))
		"journal" when journal_tab == "floors":
			for slot in FLOOR_PAGE_SIZE:
				var index = journal_page * FLOOR_PAGE_SIZE + slot
				if index >= Content.families.floors.size(): break
				make_surface(floor_rect(slot), PANEL, GOLD if Content.families.floors[index].id in Run.profile.floors else EDGE)
		"journal" when journal_tab == "combos":
			var ids: Array = Synergies.all_ids()
			for slot in JOURNAL_PAGE_SIZE:
				var index = journal_page * JOURNAL_PAGE_SIZE + slot
				if index >= ids.size(): break
				make_surface(journal_rect(slot), PANEL, Synergies.entry(ids[index])[4] if ids[index] in Run.profile.combos else EDGE)
		"journal" when journal_tab == "paintings":
			var required = gallery_ids()
			for i in required.size():
				make_surface(gallery_rect(i), PANEL, GOLD if Collection.seen(required[i]) else EDGE)
		"journal":
			for slot in JOURNAL_PAGE_SIZE:
				var index = journal_page * JOURNAL_PAGE_SIZE + slot
				if index >= Content.items.size(): break
				var item: Dictionary = Content.items[index]
				make_surface(journal_rect(slot), PANEL, Content.RARITY_COLORS[item.rarity] if item.id in Run.inventory else EDGE)
		"dead", "won": make_surface(Rect2(350, 96, 580, 540))
		"map": make_surface(Rect2(140, 60, 1000, 610))

func update_surface_visibility() -> void:
	if is_instance_valid(toast_surface): toast_surface.visible = mode == "play" and toast_time > 0
	if is_instance_valid(interaction_surface): interaction_surface.visible = mode == "play" and game.interaction_text != ""
	if is_instance_valid(boss_surface): boss_surface.visible = mode == "play" and is_instance_valid(game.get_boss())

func sync_lighting() -> void:
	# Project the SAME lanterns and directional key that illuminate the dungeon.
	# Relief is shaded in the canvas; this adds no 3D lights or shadow maps.
	if not is_instance_valid(game) or not is_instance_valid(game.camera): return
	lighting_lamps = PackedVector4Array()
	lighting_colors = PackedColorArray()
	var projected_lamps: Array=[]
	if is_instance_valid(game.room):
		projected_lamps=game.room.lamps
		if game.first_person and not game.in_menu and game.corridors and game.corridors.walking(): projected_lamps=game.corridors.active.lamps
		for lamp in projected_lamps:
			if lighting_lamps.size() == 4: break
			if not is_instance_valid(lamp): continue
			if game.first_person and not game.in_menu and game.camera.is_position_behind(lamp.global_position): continue
			var screen = game.camera.unproject_position(lamp.global_position)
			var range_edge = game.camera.unproject_position(lamp.global_position + game.camera.global_basis.x * lamp.omni_range)
			var point = local_point(screen)
			lighting_lamps.append(Vector4(point.x, point.y, clampf(screen.distance_to(range_edge) / scale_value, 16, 1100) if game.first_person else screen.distance_to(range_edge) / scale_value, lamp.light_energy if lamp.is_visible_in_tree() else 0.0))
			lighting_colors.append(lamp.light_color)
	while lighting_lamps.size() < 4:
		lighting_lamps.append(Vector4.ZERO)
		lighting_colors.append(Color.BLACK)
	var direction = Vector3(-.45, -.65, .7).normalized()
	var key_color = Color("99b4cf") * .22
	var ambient = .12
	if is_instance_valid(game.key_light):
		var local_direction = game.camera.global_basis.inverse() * game.key_light.global_basis.z
		direction = Vector3(local_direction.x, -local_direction.y, absf(local_direction.z)).normalized()
		key_color = game.key_light.light_color * game.key_light.light_energy
	if is_instance_valid(game.room_environment): ambient = game.room_environment.environment.ambient_light_energy
	for surface in surfaces:
		surface.set_lighting(lighting_lamps, lighting_colors, direction, key_color, ambient)

func register_secret_tap() -> void:
	if mode != "pause" or not Run.active:
		return
	secret_taps += 1
	if secret_taps >= 5:
		show_screen("secret")

func build_secret_code() -> void:
	secret_field = LineEdit.new()
	secret_field.name = "SecretCode"
	secret_field.position = Vector2(420, 306)
	secret_field.size = Vector2(440, 60)
	secret_field.placeholder_text = "Whisper a secret…"
	secret_field.max_length = 32
	secret_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	secret_field.add_theme_font_override("font", bold)
	secret_field.add_theme_font_size_override("font_size", 20)
	secret_field.add_theme_color_override("font_color", GOLD)
	secret_field.add_theme_stylebox_override("normal", style(Color("192428"), EDGE))
	secret_field.add_theme_stylebox_override("focus", style(Color("192428"), GOLD))
	secret_field.text_submitted.connect(submit_secret_code)
	content.add_child(secret_field)
	secret_field.grab_focus.call_deferred()
	button("Make a wish", Rect2(420, 422, 440, 60), func(): submit_secret_code(secret_field.text), true)
	button("← Back", Rect2(420, 498, 440, 56), close_secret_code)

func close_secret_code() -> void:
	if secret_field and is_instance_valid(secret_field):
		secret_field.release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()
	show_screen("pause")

func submit_secret_code(code: String) -> void:
	if not Run.active or game.in_menu:
		return
	if not game.redeem_secret_code(code):
		secret_feedback = "That secret did not catch a spark."
		if secret_field and is_instance_valid(secret_field):
			secret_field.select_all()
		queue_redraw()
		return
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()
	game.resume_game()

func build_menu() -> void:
	if not game.first_person:
		build_legacy_menu()
		return
	if menu_seed == 0: reforge()
	var y = 286.0 if Run.has_save() else 300.0
	if Run.has_save():
		title_button("Continue journey", Rect2(56,y,420,58), func(): game.begin_continue(), true)
		y += 68
	title_button("New journey", Rect2(56,y,420,58), func(): show_screen("armory"), not Run.has_save())
	y += 68
	title_button("Daily journey", Rect2(56,y,420,58), func(): game.begin_run(starter_weapon(Run.daily_seed()).id,Run.daily_seed(),true))
	y += 62
	# Two to four players on the same network.
	title_button("Climb together", Rect2(56,y,420,54), func(): show_screen("coop"))
	y += 54
	title_button("Journal", Rect2(56,y,420,54), func(): open_journal("menu"))
	y += 54
	title_button("Options", Rect2(56,y,420,54), func(): open_settings("menu"))
	y += 54
	if not is_touch_platform(): title_button("Leave the hearth", Rect2(56,y,420,54), func(): game.get_tree().quit())

func title_button(label: String, rect: Rect2, callback: Callable, primary := false) -> Button:
	var control = Button.new()
	control.text = label
	control.position = rect.position
	control.size = rect.size
	control.alignment = HORIZONTAL_ALIGNMENT_LEFT
	control.clip_text = true
	control.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	control.add_theme_font_override("font",heading)
	control.add_theme_font_size_override("font_size", 29 if mode == "menu" else 21)
	control.add_theme_color_override("font_color",GOLD if primary else INK)
	control.add_theme_color_override("font_hover_color",Color("ffe3aa"))
	control.add_theme_color_override("font_focus_color",Color("ffe3aa"))
	control.add_theme_constant_override("outline_size",2)
	control.add_theme_color_override("font_outline_color",Color(0,0,0,.6))
	for state in ["normal","disabled"]:
		control.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	for state in ["hover","focus","pressed"]:
		var fill = StyleBoxFlat.new()
		fill.bg_color = Color(.52,.36,.15,.15 if state != "pressed" else .25)
		fill.border_color = Color(.85,.67,.37,.8)
		fill.border_width_left = 2
		fill.content_margin_left = 14
		control.add_theme_stylebox_override(state,fill)
	control.pressed.connect(func(): Audio.play_sound("coin",.55); callback.call())
	content.add_child(control)
	if not content.get_children().any(func(child): return child != control and child is Button and not child.is_queued_for_deletion()): focus_title_control.call_deferred(control)
	return control

func focus_title_control(control: Control) -> void:
	if is_instance_valid(control) and control.is_inside_tree() and not control.is_queued_for_deletion() and control.is_visible_in_tree(): control.grab_focus()

func build_armory() -> void:
	if menu_seed == 0: reforge()
	var choices = Collection.starters(chosen_seed())
	for slot in choices.size():
		var weapon: Dictionary = choices[slot]
		var control = title_button(weapon.name,Rect2(58,208+slot*64,440,57),select_armament.bind(slot), slot == posmod(starter_index,choices.size()))
		control.name = "Armament%d" % slot
		control.set_meta("starter_slot",slot)
	seed_field = LineEdit.new()
	seed_field.name = "JourneySeed"
	seed_field.position = Vector2(60,550)
	seed_field.size = Vector2(250,50)
	seed_field.placeholder_text = "Seed %d" % menu_seed
	seed_field.text = selected_seed
	seed_field.max_length = 10
	seed_field.add_theme_font_override("font",body)
	seed_field.add_theme_font_size_override("font_size",17)
	seed_field.add_theme_color_override("font_color",MUTED)
	seed_field.add_theme_stylebox_override("normal",style(Color(.04,.045,.04,.6),Color(.55,.45,.29,.5),1))
	seed_field.add_theme_stylebox_override("focus",style(Color(.08,.075,.05,.8),GOLD,1))
	seed_field.text_changed.connect(func(value): selected_seed = value; refresh_armory_choices())
	content.add_child(seed_field)
	title_button("Reforge",Rect2(332,550,150,54),func(): reforge(); seed_field.text = ""; seed_field.placeholder_text = "Seed %d" % menu_seed; refresh_armory_choices())
	title_button("Enter the tower  →",Rect2(58,622,440,62),func(): game.begin_run(starter_weapon().id,chosen_seed(),false),true)
	var back = title_button("← Hearth",Rect2(60,64,200,54),func(): show_screen("menu"))
	back.add_theme_font_size_override("font_size",18)
	if is_instance_valid(game.title_scene): game.title_scene.preview_weapon(starter_weapon())

func select_armament(slot: int) -> void:
	starter_index = slot
	refresh_armory_choices()

func refresh_armory_choices() -> void:
	var choices = Collection.starters(chosen_seed())
	starter_index = posmod(starter_index,choices.size())
	for child in content.get_children():
		if child is Button and child.has_meta("starter_slot"):
			var slot = int(child.get_meta("starter_slot"))
			child.text = choices[slot].name
			child.add_theme_color_override("font_color",GOLD if slot == starter_index else INK)
	if is_instance_valid(game.title_scene): game.title_scene.preview_weapon(starter_weapon())
	queue_redraw()

func handle_title_back() -> bool:
	if not game.first_person or not game.in_menu or mode == "menu": return false
	if mode == "painting": close_painting()
	elif mode in ["journal","settings"]: close_subscreen()
	elif mode == "lobby":
		Session.leave_party()
		show_screen("coop")
	else:
		if mode == "coop": Session.stop_looking()
		show_screen("menu")
	return true

func build_legacy_menu() -> void:
	seed_field = LineEdit.new()
	seed_field.position = Vector2(64, 390)
	seed_field.size = Vector2(190, 52)
	if menu_seed == 0: reforge()
	seed_field.placeholder_text = "Seed %d" % menu_seed
	seed_field.text = selected_seed
	seed_field.max_length = 10
	seed_field.add_theme_font_override("font", body)
	seed_field.add_theme_font_size_override("font_size", 18)
	seed_field.add_theme_color_override("font_color", MUTED)
	seed_field.add_theme_stylebox_override("normal", style(Color(.08, .11, .12, .7), EDGE))
	seed_field.add_theme_stylebox_override("focus", style(Color(.1, .13, .14, .9), GOLD))
	seed_field.text_changed.connect(func(value):
		selected_seed = value
		queue_redraw())
	content.add_child(seed_field)
	button("‹", Rect2(64, 278, 56, 56), func(): cycle_weapon(-1))
	button("›", Rect2(426, 278, 56, 56), func(): cycle_weapon(1))
	button("New spellbooks ↻", Rect2(270, 388, 212, 56), func():
		reforge()
		seed_field.text = ""
		seed_field.placeholder_text = "Seed %d" % menu_seed
		Audio.play_sound("coin", .9)
		queue_redraw())
	button("Begin a run   →", Rect2(64, 458, 418, 60), func(): game.begin_run(starter_weapon().id, chosen_seed(), false), true)
	if Run.has_save():
		button("Continue saved run", Rect2(64, 530, 418, 56), func(): game.begin_continue())
		button("Today’s seed", Rect2(64, 598, 201, 54), func(): game.begin_run(starter_weapon(Run.daily_seed()).id, Run.daily_seed(), true))
		button("Journal", Rect2(281, 598, 201, 54), func(): open_journal("menu"))
	else:
		button("Today’s seed", Rect2(64, 536, 201, 56), func(): game.begin_run(starter_weapon(Run.daily_seed()).id, Run.daily_seed(), true))
		button("Journal", Rect2(281, 536, 201, 56), func(): open_journal("menu"))
	button("Settings", moved(Rect2(1080, 32, 154, 56), widen()), func(): open_settings("menu"))

func cycle_weapon(step: int) -> void:
	starter_index = posmod(starter_index + step, Collection.starters(chosen_seed()).size())
	Audio.play_sound("coin", .75)
	queue_redraw()

## Display details for a relic, weapon or active item offer.
func offer_info(offer: Dictionary) -> Dictionary:
	match offer.get("kind", "item"):
		"weapon":
			var weapon: Dictionary = Forge.lookup(offer.id)
			var forged: bool = weapon.get("forged", false)
			var tag = "%s · %s" % [str(weapon.element).to_upper(), str(weapon.pattern).to_upper()] if forged else "NEW SCHOOL OF MAGIC"
			return {"name": weapon.name, "description": weapon.description, "color": Color(weapon.color),
				"label": "DARK-BOUND SPELLBOOK" if int(weapon.get("tier", 0)) > 0 else "SPELLBOOK", "tag": tag, "take": "Take up the spellbook", "buy": "%d coins · take up"}
		"active":
			var active: Dictionary = Content.record("actives", offer.id)
			return {"name": active.name, "description": active.description, "color": Color(active.color),
				"label": "ACTIVE ITEM", "tag": "RECHARGES IN %d SECONDS" % int(active.cooldown), "take": "Take this item", "buy": "%d coins · take"}
	var item: Dictionary = Content.item_by_id[offer.id]
	return {"name": item.name, "description": item.description, "color": Content.RARITY_COLORS[item.rarity],
		"label": item.rarity.to_upper() + " RELIC", "tag": item.tag, "take": "Take this relic", "buy": "%d coins"}

func build_rewards() -> void:
	for i in offers.size():
		var offer: Dictionary = offers[i]
		var info = offer_info(offer)
		var rect = reward_rect(i)
		var price = int(offer.get("price", 0))
		var affordable = not shop or Run.coins >= price
		var label: String = info.take if not shop else info.buy % price
		var control = button(label, Rect2(rect.position.x + 24, 478, REWARD_WIDTH - 48, 60), func(): game.choose_offer(i), affordable)
		control.disabled = not affordable
		if not affordable: control.get_meta("surface").modulate = Color(.7, .7, .65)
	button("Keep exploring", Rect2(460, 596, 360, 58), func(): game.close_reward())

func bargain_rect(index: int) -> Rect2:
	return Rect2(BARGAIN_TAKE.position + Vector2(0, index * BARGAIN_STEP), BARGAIN_TAKE.size)

## Death's bargain: pick from its right hand, then a price from its left.
func build_bargain() -> void:
	for i in offers.size():
		bargain_slot("Take_%d" % i, bargain_rect(i), func(): pick_bargain(i, bargain_price))
	bargain_slot("Curse", CURSE_RECT, func(): pick_bargain(bargain_pick, "curse"))
	bargain_slot("Trial", TRIAL_RECT, func(): pick_bargain(bargain_pick, "trial"))
	var ready := bargain_pick >= 0 and bargain_price != ""
	var seal := button("Seal the bargain", Rect2(470, 604, 340, 56), func(): game.seal_bargain(bargain_pick, bargain_price), ready)
	seal.disabled = not ready
	if not ready: seal.get_meta("surface").modulate = Color(.7, .7, .65)
	button("Walk away", Rect2(540, 668, 200, 44), func(): game.close_reward())

func bargain_slot(id: String, rect: Rect2, callback: Callable) -> void:
	var slot := Button.new()
	slot.name = id
	slot.position = rect.position
	slot.size = rect.size
	for state in ["normal", "hover", "pressed", "disabled"]:
		slot.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	slot.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), GOLD, 8))
	slot.pressed.connect(func():
		Audio.play_sound("coin", .55)
		callback.call()
		# A gamepad keeps its place on the rebuilt screen.
		if not Input.get_connected_joypads().is_empty():
			var again = content.get_node_or_null(id)
			if again: again.grab_focus())
	content.add_child(slot)

func pick_bargain(index: int, price: String) -> void:
	bargain_pick = index
	bargain_price = price
	show_screen("bargain")

func draw_bargain() -> void:
	var violet := Color("d8c0f0")
	centered("Death offers a bargain", 640, 92, 38, violet, heading)
	centered("Take one thing from its right hand. Pay for it with its left.", 640, 132, 19, MUTED)
	text("ITS RIGHT HAND · WHAT YOU TAKE", Vector2(52, 190), 14, DeathBargain.COLOR, bold)
	text("ITS LEFT HAND · THE PRICE", Vector2(836, 190), 14, DeathBargain.COLOR, bold)
	for i in offers.size():
		var offer: Dictionary = offers[i]
		var info := offer_info(offer)
		var rect := bargain_rect(i)
		var x := rect.position.x
		var y := rect.position.y
		var colour: Color = info.color
		var picked := i == bargain_pick
		diamond(Vector2(x + 34, y + 46), 15, Color("262f28"))
		diamond(Vector2(x + 34, y + 44), 13, colour, picked)
		diamond(Vector2(x + 34, y + 44), 13, colour, false)
		text(info.name, Vector2(x + 64, y + 36), 21, GOLD if picked else INK, heading)
		text(info.label, Vector2(x + 64, y + 57), 12, colour, bold)
		var hint := combination_hint(offer)
		if hint != "": text(hint, Vector2(x + 72 + bold.get_string_size(info.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, y + 57), 11, GOLD, bold)
		draw_multiline_string(body, Vector2(x + 64, y + 80), info.description, HORIZONTAL_ALIGNMENT_LEFT, 318, 14, 2, MUTED)
		# How strong it is, and so how heavy its curse.
		for p in 5:
			diamond(Vector2(x + 316 + p * 16, y + 24), 5, DeathBargain.COLOR, p < int(offer.get("power", 3)))
	var chosen: Dictionary = offers[bargain_pick] if bargain_pick >= 0 and bargain_pick < offers.size() else {}
	for card in [["curse", CURSE_RECT, "A CURSE"], ["trial", TRIAL_RECT, "A TRIAL"]]:
		var rect: Rect2 = card[1]
		var x := rect.position.x + 24
		var y := rect.position.y
		text(card[2], Vector2(x, y + 32), 13, DeathBargain.COLOR if bargain_price == card[0] else MUTED, bold)
		if bargain_price == card[0]: diamond(Vector2(rect.end.x - 26, y + 27), 7, DeathBargain.COLOR)
		if not chosen.has("curse"):
			var waiting := "The stronger the thing you take, the heavier its curse." if card[0] == "curse" else "Win Death's trial and no curse falls."
			draw_multiline_string(body, Vector2(x, y + 80), "Choose from its right hand first. " + waiting, HORIZONTAL_ALIGNMENT_LEFT, 352, 17, 3, MUTED)
		elif card[0] == "curse":
			text(DeathBargain.curse_name(chosen.curse), Vector2(x, y + 72), 26, violet, heading)
			draw_multiline_string(body, Vector2(x, y + 104), DeathBargain.curse_text(chosen.curse), HORIZONTAL_ALIGNMENT_LEFT, 352, 17, 2, INK)
			text("It falls now, and stays for the rest of the run.", Vector2(x, y + 162), 14, MUTED)
		else:
			text(DeathBargain.trial_name(chosen.trial), Vector2(x, y + 72), 26, violet, heading)
			draw_multiline_string(body, Vector2(x, y + 102), DeathBargain.trial_text(chosen.trial), HORIZONTAL_ALIGNMENT_LEFT, 352, 15, 3, INK)
			text("Fail, and the curse (%s) falls anyway." % DeathBargain.curse_name(chosen.curse), Vector2(x, y + 166), 14, MUTED)
	centered("What you take is yours either way. Death deals once.", 640, 590, 14, MUTED)

func open_journal(back: String) -> void:
	previous_mode = back
	game.paused = true
	journal_page = 0
	show_screen("journal")

func build_journal() -> void:
	button("← Back", Rect2(64, 36, 144, 56), func(): close_subscreen())
	button("Relics", Rect2(232, 36, 150, 56), func(): set_journal_tab("relics"), journal_tab == "relics")
	button("Paintings", Rect2(394, 36, 190, 56), func(): set_journal_tab("paintings"), journal_tab == "paintings")
	button("Floors", Rect2(596, 36, 160, 56), func(): set_journal_tab("floors"), journal_tab == "floors")
	button("Combos", Rect2(768, 36, 170, 56), func(): set_journal_tab("combos"), journal_tab == "combos")
	if journal_tab in ["relics", "floors", "combos"]:
		button("←", Rect2(1044, 626, 76, 58), func(): change_journal_page(-1))
		button("→", Rect2(1136, 626, 76, 58), func(): change_journal_page(1))
		return
	# Discovered works open in the viewer straight from the journal.
	var required = gallery_ids()
	for i in required.size():
		if not Collection.seen(required[i]): continue
		var id: String = required[i]
		var slot = Button.new()
		slot.name = "Gallery_" + id
		slot.position = gallery_rect(i).position
		slot.size = gallery_rect(i).size
		slot.focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed", "focus"]:
			slot.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		slot.pressed.connect(func(): open_painting(id, "journal"))
		content.add_child(slot)

func set_journal_tab(tab: String) -> void:
	journal_tab = tab
	journal_page = 0
	show_screen("journal")

func gallery_ids() -> Array:
	return Content.record("collections", Collection.FOUNDING).get("paintings", [])

func gallery_rect(index: int) -> Rect2:
	return Rect2(64 + (index % 6) * 196, 214 + (index / 6) * 206, 180, 192)

## The run's seed: the one typed in, or the menu's own.
func chosen_seed() -> int:
	var typed = selected_seed.strip_edges().to_int()
	return typed if typed != 0 else menu_seed

func reforge() -> void:
	menu_seed = 1 + randi() % 99999998
	selected_seed = ""

## The weapon picked from a seed's starters (the menu's seed by default).
func starter_weapon(seed_value := 0) -> Dictionary:
	if menu_seed == 0: reforge()
	var arsenal = Collection.starters(seed_value if seed_value != 0 else chosen_seed())
	return arsenal[posmod(starter_index, arsenal.size())]

## The full-composition viewer: image, title, artist and date, medium, the
## holding collection, an original caption, and the source credit. The large
## image loads now and is released on close.
func open_painting(id: String, back: String) -> void:
	painting_id = id
	painting_back = back
	painting_texture = PaintingLibrary.inspection_texture(id)
	game.paused = true
	show_screen("painting")

func close_painting() -> void:
	painting_texture = null
	painting_unlock = ""
	if painting_back == "journal":
		show_screen("journal")
	else:
		game.resume_game()

func open_settings(back: String) -> void:
	previous_mode = back
	settings_page = "display"
	show_screen("settings")

func settings_pages() -> Array:
	# Phones and tablets have no keys to rebind.
	return SETTINGS_PAGES.filter(func(page): return page[0] != "keys" or not is_touch_platform())

func build_settings() -> void:
	var pages := settings_pages()
	# Six tabs use the panel's whole width; four keep the rows' width.
	var span := 660.0 if pages.size() > 4 else 620.0
	var width := (span - 6.0 * (pages.size() - 1)) / pages.size()
	for i in pages.size():
		var page: Array = pages[i]
		var tab := button(page[1], Rect2(640.0 - span / 2.0 + i * (width + 6.0), 154, width, 56), func(): open_settings_page(page[0]), page[0] == settings_page)
		tab.add_theme_font_size_override("font_size", 18 if pages.size() > 4 else 20)
	if settings_page == "keys":
		build_keys()
		button("← Back", Rect2(330, 592, 304, 58), func(): close_subscreen())
		return
	else:
		var rows = settings_rows(settings_page)
		settings_row_count = rows.size()
		for i in rows.size():
			setting_row(Rect2(330, 218 + i * 61, 620, 54), rows[i])
		if settings_page == "controls":
			settings_row_count += 1
			button("Arrange touch controls", Rect2(330, 218 + rows.size() * 61, 620, 54), func(): open_layout())
	# Seven large rows still fit; keep Back beneath the last row.
	var back_y := maxf(592, 218 + (settings_row_count - 1) * 61 + 54 + 10)
	button("← Back", Rect2(396, back_y, 488, 58), func(): close_subscreen())

## Every rebindable action in two columns; click one, then press its key.
func build_keys() -> void:
	settings_row_count = 6
	var rows := settings_rows("keys")
	for i in rows.size():
		var action: String = rows[i][0]
		var rect := Rect2(330 + (i / 6) * 316, 218 + (i % 6) * 61, 304, 54)
		var row := setting_row(rect, rows[i], func():
			rebinding = "" if rebinding == action else action
			show_screen("settings"))
		row.value_size = 17
	button("Default keys", Rect2(646, 592, 304, 58), func():
		rebinding = ""
		Settings.set_value("keys", {})
		show_screen("settings"))

## While rebinding: the next key (or a mouse button other than the left)
## becomes the action's; Escape cancels.
func rebind_input(event: InputEvent) -> bool:
	if rebinding == "": return false
	var code := 0
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			rebinding = ""
			show_screen("settings")
			return true
		code = int(event.physical_keycode) if event.physical_keycode != KEY_NONE else int(event.keycode)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
		code = Settings.MOUSE_CODE + int(event.button_index)
	if code <= 0: return false
	Settings.bind_key(rebinding, code)
	rebinding = ""
	show_screen("settings")
	return true

func open_settings_page(page: String) -> void:
	settings_page = page
	rebinding = ""
	show_screen("settings")

func on_off(key: String) -> String:
	return "On" if Settings.values[key] else "Off"

## [setting key, label, value text, interactive]
func settings_rows(page: String) -> Array:
	match page:
		"display":
			var pixels = Settings.render_pixels()
			var scale = "%d%%" % roundi(Settings.values.render_scale * 100)
			if Settings.adaptive < .995: scale += " (adaptive)"
			elif get_viewport().scaling_3d_scale < float(Settings.values.render_scale) - .005:
				scale += " (limited)"
			var vsync = ["vsync", "VSync", on_off("vsync"), true]
			if not Settings.vsync_supported():
				vsync = ["vsync", "VSync", "System controlled", false]
			elif Settings.effective_vsync() != on_off("vsync").to_lower():
				vsync[2] += " · driver " + Settings.effective_vsync().capitalize()
			var last = ["fullscreen", "Fullscreen", on_off("fullscreen") if Settings.fullscreen_supported() else "System controlled", Settings.fullscreen_supported()]
			# A phone whose chip gets a 3D pixel budget may lift it, in place of
			# the fullscreen row it cannot change anyway.
			if not Settings.fullscreen_supported() and Settings.resolution_capped():
				last = ["full_resolution", "Full resolution", "On · may be slower" if Settings.values.full_resolution else "Off", true]
			return [["render_scale", "Render resolution", "%s  ·  %d×%d" % [scale, pixels.x, pixels.y], true],
				["fps_limit", "FPS limit", "Unlimited" if Settings.values.fps_limit == 0 else str(Settings.values.fps_limit), true],
				vsync, ["show_fps", "Show FPS", on_off("show_fps"), true], last]
		"camera":
			return [["fov", "Field of view", "%d°" % Settings.values.fov, true],
				["mouse_sensitivity", "Mouse sensitivity", "%d%%" % roundi(float(Settings.values.mouse_sensitivity) / float(Settings.DEFAULTS.mouse_sensitivity) * 100.0), true],
				["touch_sensitivity", "Touch sensitivity", "%d%%" % roundi(float(Settings.values.touch_sensitivity) / float(Settings.DEFAULTS.touch_sensitivity) * 100.0), true],
				["invert_y", "Invert vertical look", on_off("invert_y"), true],
				["head_bob", "Head bob", on_off("head_bob"), true]]
		"graphics":
			return [["effects_detail", "Effects detail", Settings.values.effects_detail.capitalize(), true],
				["bloom", "Bloom", str(Settings.values.bloom).capitalize(), true],
				["screen_effects", "Screen warps and flashes", str(Settings.values.screen_effects).capitalize() if RenderPolicy.current().post_processing else "Off · device safe mode", bool(RenderPolicy.current().post_processing)],
				["small_details", "Small details", Settings.values.small_details.capitalize(), true],
				["shadows", "Lantern shadows", on_off("shadows"), true],
				["ssao", "SSAO", Settings.values.ssao.capitalize() if Settings.ssao_supported() else "Off · device safe mode", Settings.ssao_supported()],
				["adaptive_resolution", "Adaptive resolution", on_off("adaptive_resolution") if Settings.adaptive_supported() else "Phones only", Settings.adaptive_supported()]]
		"keys":
			return Settings.REBINDABLE.map(func(action): return [action, KEY_LABELS.get(action, action), "Press a key…" if rebinding == action else Settings.key_label(action), true])
		"sound":
			return [["sound", "Sound effects", on_off("sound"), true],
				["sound_volume", "Effects volume", "%d%%" % int(Settings.values.sound_volume), bool(Settings.values.sound)],
				["music", "Ambient music", on_off("music"), true],
				["music_volume", "Music volume", "%d%%" % int(Settings.values.music_volume), bool(Settings.values.music)]]
	return [["shake", "Camera shake", on_off("shake"), true], ["touch", "Touch controls", on_off("touch"), true],
		["cast_while_aiming", "Drag to aim casts in fights", on_off("cast_while_aiming"), true],
		["aim_assist", "Aim assist (touch, gamepad)", on_off("aim_assist"), true],
		["touch_run", "Run at the stick's edge (touch)", on_off("touch_run"), true]]

func setting_row(rect: Rect2, row: Array, action := Callable()) -> SettingRow:
	var control = SettingRow.new()
	control.name = "Setting_" + row[0]
	control.setting_key = row[0]
	style_button(control, false)
	var padded = StyleBoxEmpty.new()
	padded.content_margin_left = SettingRow.PADDING
	for state in ["normal", "hover", "pressed", "disabled"]:
		control.add_theme_stylebox_override(state, padded)
	control.value_font = bold
	control.configure(rect, row[1], row[2], Color("41473f"), EDGE)
	control.disabled = not row[3]
	surfaces.append(control.surface)
	var slab = control.surface
	control.mouse_entered.connect(func(): slab.modulate = Color(.7, .7, .65) if control.disabled else Color(1.17, 1.12, 1.02))
	control.mouse_exited.connect(func(): slab.modulate = Color(.7, .7, .65) if control.disabled else Color.WHITE)
	if control.disabled: slab.modulate = Color(.7, .7, .65)
	var key: String = row[0]
	if action.is_valid():
		control.pressed.connect(func(): Audio.play_sound("coin", .7); action.call())
	else:
		control.pressed.connect(func(): Audio.play_sound("coin", .7); Settings.cycle(key); show_screen("settings"))
		# A right click steps a setting back.
		control.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and not control.disabled:
				Audio.play_sound("coin", .6)
				Settings.cycle(key, -1)
				show_screen("settings"))
	content.add_child(control)
	return control

func open_map(back: String) -> void:
	previous_mode = back
	map_message = ""
	game.paused = true
	show_screen("map")

func close_subscreen() -> void:
	if previous_mode == "menu":
		show_screen("menu")
	elif previous_mode == "play":
		game.resume_game()
	else:
		show_screen("pause")

func style(background: Color, border: Color, radius := 7) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

func style_button(control: Button, primary: bool) -> void:
	control.add_theme_font_override("font", bold)
	control.add_theme_font_size_override("font_size", 20)
	control.add_theme_color_override("font_color", GOLD if primary else INK)
	control.add_theme_color_override("font_hover_color", Color("fff2cd"))
	control.add_theme_color_override("font_pressed_color", GOLD)
	control.add_theme_color_override("font_disabled_color", Color("8e907e"))
	control.add_theme_color_override("font_outline_color", Color("1c231f"))
	control.add_theme_constant_override("outline_size", 2)
	for state in ["normal", "hover", "pressed", "disabled"]:
		control.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	control.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), GOLD, 8))

func button(label: String, rect: Rect2, callback: Callable, primary := false) -> Button:
	var control = Button.new()
	control.text = label
	control.position = rect.position
	control.size = rect.size
	style_button(control, primary)
	var surface = make_surface(rect, Color("62533c") if primary else Color("41473f"), GOLD if primary else EDGE, true)
	control.set_meta("surface", surface)
	control.mouse_entered.connect(func(): surface.modulate = Color(.7, .7, .65) if control.disabled else Color(1.17, 1.12, 1.02))
	control.mouse_exited.connect(func(): surface.modulate = Color(.7, .7, .65) if control.disabled else Color.WHITE)
	control.button_down.connect(func(): surface.modulate = Color(.8, .82, .78))
	control.button_up.connect(func(): surface.modulate = Color.WHITE)
	control.pressed.connect(func(): Audio.play_sound("coin", .7); callback.call())
	content.add_child(control)
	return control

func notify(title: String, detail := "", color := GOLD) -> void:
	toast_text = title
	toast_detail = detail
	toast_color = color
	toast_time = 3.2

func damage_number(at: Vector2, amount: float, critical: bool) -> void:
	if floating_numbers.size() > 35:
		return
	floating_numbers.append({"at": local_point(at), "text": str(maxi(1, roundi(amount))) + ("!" if critical else ""), "critical": critical, "age": 0.0})

## A reaction's or pairing's name rising where it happened.
func word(at: Vector2, label: String, color: Color) -> void:
	if label == "" or floating_numbers.size() > 40: return
	floating_numbers.append({"at": local_point(at) - Vector2(heading.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x / 2.0, 0), "text": label, "critical": false, "age": 0.0, "life": 1.2, "color": color})

func _process(delta: float) -> void:
	elapsed_ui += delta
	fps_frames += 1
	fps_time += delta
	if fps_time >= .5:
		fps_value = fps_frames / fps_time
		fps_frames = 0
		fps_time = 0.0
	toast_time = maxf(0, toast_time - delta)
	dash_ready_glow = maxf(0.0, dash_ready_glow - delta)
	for cell in scribbles.keys():
		if elapsed_ui - scribbles[cell] > SCRIBBLE_TIME: scribbles.erase(cell)
	for number in floating_numbers:
		number.age += delta
	floating_numbers = floating_numbers.filter(func(n): return n.age < n.get("life", .65))
	sync_lighting()
	update_surface_visibility()
	sync_minimap()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if game.first_person and game.in_menu and event.is_action_pressed("ui_cancel") and handle_title_back():
		get_viewport().set_input_as_handled()
		return
	if mode == "settings" and rebind_input(event):
		get_viewport().set_input_as_handled()
		return
	if mode == "secret" and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_secret_code()
		get_viewport().set_input_as_handled()
		return
	if mode == "pause" and event is InputEventKey and event.pressed and not event.echo:
		if event.unicode > 0 and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			var longest: int = Run.SECRET_CODES.map(func(code): return code.length()).max()
			secret_key_buffer = (secret_key_buffer + String.chr(event.unicode).to_upper()).right(longest)
			for code in Run.SECRET_CODES:
				if secret_key_buffer.ends_with(code):
					submit_secret_code(code)
					get_viewport().set_input_as_handled()
					break
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		mouse_on_action = false
	if mode == "layout":
		layout_input(event)
		return
	if mode == "map" and map_input(event):
		get_viewport().set_input_as_handled()
		return
	if mode != "play":
		return
	# Emulated mouse events from touches were already handled as touches.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		var action = action_at(from_right(local_point(event.position)))
		if action != "" and touch_hud_visible():
			mouse_on_action = true
			trigger_action(action)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		touch_used = true
		var p = local_point(event.position)
		# The right stick and action buttons live in the right group's layout.
		var right = from_right(p)
		if event.pressed:
			# Buttons are hit-tested before a floating stick can capture the finger.
			var action = action_at(right)
			if action != "":
				if action == "fire": fire_touch = event.index
				trigger_action(action)
				get_viewport().set_input_as_handled()
			elif INTERACTION_RECT.has_point(from_middle(p)) and game.interaction_text != "" and not in_move_zone(p):
				game.interact()
				get_viewport().set_input_as_handled()
			elif left_touch == -1 and in_move_zone(p):
				left_touch = event.index
				# The stick floats to the thumb, near where the layout rests it.
				var rest: Vector2 = control_spot("move").center
				left_origin = Vector2(clampf(p.x, minf(rest.x, 90), maxf(rest.x, 420)), clampf(p.y, minf(rest.y, 400), maxf(rest.y, 620)))
				left_vector = (p - left_origin).limit_length(stick_reach()) / stick_reach()
				get_viewport().set_input_as_handled()
			elif right_touch == -1 and ((game.first_person and right.y > 145 and right.x > 600) or (not game.first_person and right.y > 330 and right.x > 730)):
				right_touch = event.index
				right_origin = Vector2(clampf(right.x, 810, 1190), clampf(right.y, 400, 620))
				right_vector = (right - right_origin).limit_length(58) / 58.0
				get_viewport().set_input_as_handled()
		else:
			if event.index == fire_touch: fire_touch = -1
			if event.index == left_touch:
				left_touch = -1
				left_vector = Vector2.ZERO
				left_origin = control_spot("move").center
				get_viewport().set_input_as_handled()
			if event.index == right_touch:
				right_touch = -1
				right_vector = Vector2.ZERO
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var p = local_point(event.position)
		if event.index == left_touch:
			left_vector = (p - left_origin).limit_length(stick_reach()) / stick_reach()
			get_viewport().set_input_as_handled()
		# Dragging FIRE also looks, supporting ordinary two-thumb play while
		# preserving a separate swipe finger for players who prefer it.
		if game.first_person and event.index == fire_touch:
			look_delta += event.relative / scale_value
			get_viewport().set_input_as_handled()
		if event.index == right_touch:
			if game.first_person: look_delta += event.relative / scale_value
			else: right_vector = (from_right(p) - right_origin).limit_length(58) / 58.0
			get_viewport().set_input_as_handled()

func stair_presentation_active() -> bool:
	return is_instance_valid(game) and game.first_person and game.transition.get("kind","") == "stairs"

func touch_hud_visible() -> bool:
	if stair_presentation_active(): return false
	return touch_used or Settings.values.touch or is_touch_platform()

func action_at(point: Vector2) -> String:
	for action in ACTION_BUTTONS:
		if action in ["fire", "jump"] and not game.first_person: continue
		var spot := control_spot(action)
		if point.distance_to(spot.center) < spot.radius:
			return action
	return ""

## Where a touch control sits and how large it is: the player's own layout
## (Settings "touch_layout", or the one being arranged) over the defaults.
## "move" is in the left group's layout, the rest in the right group's.
func control_spot(control: String) -> Dictionary:
	var base: Dictionary = {"center": MOVE_REST, "radius": MOVE_RADIUS} if control == "move" else ACTION_BUTTONS[control]
	var layout: Dictionary = layout_draft if mode == "layout" else Settings.values.get("touch_layout", {})
	var saved = layout.get(control)
	if saved is Array and saved.size() == 3:
		return {"center": Vector2(float(saved[0]), float(saved[1])), "radius": float(base.radius) * float(saved[2]), "scale": float(saved[2])}
	return {"center": base.center, "radius": base.radius, "scale": 1.0}

func stick_reach() -> float:
	return 58.0 * float(control_spot("move").scale)

## Where a thumb takes the movement stick; an interaction prompt never
## steals a touch from here.
func in_move_zone(p: Vector2) -> bool:
	return (p.y > 330 and p.x < 550) or p.distance_to(control_spot("move").center) < control_spot("move").radius * 1.4

## Dragging to look also casts while a fight is on, unless switched off:
## looking round a cleared room never fires.
func aiming_casts() -> bool:
	return game.first_person and right_touch >= 0 and bool(Settings.values.get("cast_while_aiming", true)) and game.fight_on()

# ---------------------------------------------------------------- arranging touch controls

func open_layout() -> void:
	layout_draft = Settings.values.get("touch_layout", {}).duplicate(true)
	layout_selected = ""
	layout_dragging = ""
	show_screen("layout")

func build_layout() -> void:
	button("Smaller", Rect2(330, 18, 140, 50), func(): resize_selected(-.1))
	button("Larger", Rect2(480, 18, 140, 50), func(): resize_selected(.1))
	button("Reset", Rect2(630, 18, 140, 50), func():
		layout_draft = {}
		layout_selected = ""
		queue_redraw())
	button("Done", Rect2(780, 18, 170, 50), func():
		Settings.set_value("touch_layout", layout_draft)
		show_screen("settings"), true)

func resize_selected(step: float) -> void:
	if layout_selected == "": return
	var spot := control_spot(layout_selected)
	layout_draft[layout_selected] = [spot.center.x, spot.center.y, clampf(float(spot.scale) + step, .6, 1.6)]
	queue_redraw()

## A control's point in its own group, from a screen point.
func layout_point(control: String, screen: Vector2) -> Vector2:
	var p := local_point(screen)
	return p if control == "move" else from_right(p)

func layout_input(event: InputEvent) -> void:
	# Touches arrive as touches; emulated mouse copies of them are ignored.
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == InputEvent.DEVICE_ID_EMULATION: return
	var pressed := false
	var released := false
	var finger := 0
	var at := Vector2.ZERO
	if event is InputEventScreenTouch:
		pressed = event.pressed
		released = not event.pressed
		finger = event.index
		at = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = event.pressed
		released = not event.pressed
		finger = -2
		at = event.position
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		finger = event.index if event is InputEventScreenDrag else -2
		if layout_dragging != "" and finger == layout_finger:
			var moved := layout_point(layout_dragging, event.position) + layout_grab
			var spot := control_spot(layout_dragging)
			layout_draft[layout_dragging] = [clampf(moved.x, 30.0 if layout_dragging == "move" else -300.0, 1250.0), clampf(moved.y, 60.0, 700.0), spot.scale]
			queue_redraw()
			get_viewport().set_input_as_handled()
		return
	else:
		return
	if pressed:
		var best := ""
		var best_gap := INF
		for control in Settings.TOUCH_CONTROLS:
			var spot := control_spot(control)
			var gap: float = layout_point(control, at).distance_to(spot.center)
			if gap < float(spot.radius) * 1.15 and gap < best_gap:
				best = control
				best_gap = gap
		if best == "": return
		layout_selected = best
		layout_dragging = best
		layout_finger = finger
		layout_grab = control_spot(best).center - layout_point(best, at)
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif released and finger == layout_finger:
		layout_dragging = ""
		layout_finger = -1

func draw_layout() -> void:
	anchor(widen() / 2.0)
	centered("Drag a control to move it. Choose one, then make it smaller or larger.", 640, 104, 18, INK, bold)
	centered("Fire, jump and the move stick are for first-person play.", 640, 130, 15, MUTED)
	anchor(0)
	var move := control_spot("move")
	draw_stick(move.center, Vector2.ZERO, "MOVE", layout_selected == "move", float(move.scale))
	if layout_selected == "move": draw_arc(move.center, float(move.radius) + 6, 0, TAU, 48, GOLD, 3, true)
	anchor(widen())
	draw_touch_buttons(true)
	if layout_selected != "" and layout_selected != "move":
		var spot := control_spot(layout_selected)
		draw_arc(spot.center, float(spot.radius) + 6, 0, TAU, 48, GOLD, 3, true)

func trigger_action(action: String) -> void:
	match action:
		"jump":
			if game.first_person: game.fps.jump_buffer = .14
		"dash": game.request_dash = true
		"active": game.submit({"type": "use_active"})
		"bomb": game.submit({"type": "place_bomb"})

func text(value: String, at: Vector2, size_value := 18, color := INK, font: Font = null) -> void:
	var f = font if font else body
	draw_string(f, at + Vector2(0, 2), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value, Color(.025, .035, .025, color.a * .85))
	draw_string(f, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value, color)

func centered(value: String, x: float, y: float, size_value := 16, color := INK, font: Font = null) -> void:
	var f = font if font else body
	text(value, Vector2(x - f.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value).x / 2.0, y), size_value, color, f)

func diamond(at: Vector2, radius: float, color: Color, fill := true) -> void:
	var points = PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius * .7, 0), at + Vector2(0, radius), at + Vector2(-radius * .7, 0)])
	if fill:
		draw_colored_polygon(points, color)
	else:
		points.append(points[0])
		draw_polyline(points, color, 1.5, true)

func _draw() -> void:
	if not game:
		return
	anchor(layer_shift())
	match mode:
		"menu": draw_menu()
		"armory": draw_armory()
		"coop": CoopMenus.draw_coop(self)
		"lobby": CoopMenus.draw_lobby(self)
		"loading": draw_loading()
		"play":
			draw_hud()
			CoopMenus.draw_hud(self)
		"pause":
			hearth_emblem(Vector2(640, 144), 12)
			centered("Catch your breath", 640, 204, 34, INK, heading)
			centered("Even a little flame needs a moment.", 640, 245, 18, MUTED)
			centered("The party climbs on while you rest; co-op climbs are not saved." if game.party.climbing() else "Your last safe room is saved automatically.", 640, 604, 16, MUTED)
			if not Run.curses.is_empty():
				centered("Death's curses · " + " · ".join(Run.curses.map(func(curse): return DeathBargain.curse_text(curse))), 640, 660, 15, DeathBargain.COLOR, bold)
		"secret":
			hearth_emblem(Vector2(640, 177), 11)
			centered("A whispered wish", 640, 237, 34, INK, heading)
			centered("Some little sparks know a secret.", 640, 278, 18, MUTED)
			centered(secret_feedback, 640, 401, 17, Color("efbd9f"))
		"reward": draw_rewards()
		"bargain": draw_bargain()
		"layout": draw_layout()
		"settings":
			hearth_emblem(Vector2(640, 76), 11)
			centered("Make yourself at home", 640, 134, 32, INK, heading)
			if settings_row_count <= 5 and str(SETTINGS_NOTES.get(settings_page, "")) != "": draw_multiline_string(body, Vector2(340, 546), SETTINGS_NOTES[settings_page], HORIZONTAL_ALIGNMENT_CENTER, 600, 17, 2, MUTED)
		"journal":
			match journal_tab:
				"relics": draw_journal()
				"combos": draw_combos()
				"floors": draw_floors()
				_: draw_gallery()
		"painting": draw_painting()
		"map": draw_full_map()
		"dead", "won": draw_end()
	if mode == "play":
		anchor(0)
		for number in floating_numbers:
			if number.has("color"):
				var tint: Color = number.color
				tint.a = minf(1, (float(number.life) - number.age) * 3)
				text(number.text, number.at + Vector2(0, -number.age * 40), 24, tint, heading)
				continue
			var c = GOLD if number.critical else INK
			c.a = minf(1, (0.65 - number.age) * 4)
			text(number.text, number.at + Vector2(0, -number.age * 65), 26 if number.critical else 21, c, bold)
		draw_floor_title()
		anchor(widen() / 2.0)
		if toast_time > 0:
			centered(toast_text, 640, 112, 21, toast_color, heading)
			draw_multiline_string(body, Vector2(436, 138), toast_detail, HORIZONTAL_ALIGNMENT_CENTER, 408, 16, 2, MUTED)
	if Settings.values.show_fps:
		anchor(widen())
		text("%d FPS" % roundi(fps_value), Vector2(1072, 697), 15, GOLD, bold)
		# Long frames and their likely cause, to read off a phone.
		var hitches := FrameWatch.summary()
		text(hitches, Vector2(1140 - body.get_string_size(hitches, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 679), 12, GOLD, body)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func hearth_emblem(at: Vector2, radius: float) -> void:
	draw_arc(at, radius + 8, 0, TAU, 32, Color(GOLD, .27), 1.2, true)
	diamond(at + Vector2(0, 1), radius, Color("292e28"))
	diamond(at, radius * .8, GOLD)
	diamond(at + Vector2(0, 2), radius * .34, Color("fff0c6"))

func divider(from: Vector2, to: Vector2) -> void:
	draw_line(from + Vector2(0, 1), to + Vector2(0, 1), Color(.03, .04, .03, .8), 1)
	draw_line(from, to, Color(EDGE, .55), 1)

func draw_title_shade() -> void:
	# A continuous ink wash replaces the old stack of stone panel widgets.
	# No screen texture: native text stays sharp at every render scale.
	for strip in 40:
		var x = strip * 20.0
		var opacity = .92 * (1.0-smoothstep(260.0,790.0,x))
		draw_rect(Rect2(x,0,20,720),Color(.013,.019,.019,opacity))
	draw_rect(Rect2(0,0,view_width,2),Color(.55,.42,.24,.5))
	draw_rect(Rect2(0,718,view_width,2),Color(.55,.42,.24,.5))

func draw_menu() -> void:
	if not game.first_person:
		draw_legacy_menu()
		return
	draw_title_shade()
	hearth_emblem(Vector2(77,75),13)
	text("THE HEARTH IS WAITING",Vector2(102,80),13,GOLD,bold)
	text("Emberkeep",Vector2(53,180),78,INK,heading)
	text("The tower remembers your light.",Vector2(60,224),19,MUTED,heading)
	draw_line(Vector2(60,255),Vector2(174,255),Color(.73,.56,.31,.8),1)
	anchor(widen())
	text("A fire before the climb",Vector2(882,650),21,INK,heading)
	text("Return to the light. Begin again.",Vector2(884,681),14,MUTED)

func draw_armory() -> void:
	draw_title_shade()
	text("Prepare your light",Vector2(58,156),36,INK,heading)
	text("CHOOSE A SPELLBOOK",Vector2(61,188),12,GOLD,bold)
	var choices = Collection.starters(chosen_seed())
	for slot in choices.size():
		var selected = slot == posmod(starter_index,choices.size())
		diamond(Vector2(47,237+slot*64),4,GOLD if selected else Color(.42,.42,.34),selected)
	var weapon: Dictionary = starter_weapon()
	anchor(widen())
	# Keep the description readable over a moving fire highlight.
	for strip in 24:
		var y := 478.0 + strip * 8.0
		var opacity := .76 * smoothstep(478.0,510.0,y) * (1.0-smoothstep(638.0,670.0,y))
		draw_rect(Rect2(774,y,478,8),Color(.013,.019,.019,opacity))
	text("IN YOUR HAND",Vector2(794,514),12,GOLD,bold)
	var weapon_size = 29
	while weapon_size > 18 and heading.get_string_size(weapon.name,HORIZONTAL_ALIGNMENT_LEFT,-1,weapon_size).x > 430: weapon_size -= 1
	text(weapon.name,Vector2(790,551),weapon_size,Color(weapon.color),heading)
	draw_multiline_string(body,Vector2(793,583),weapon.description,HORIZONTAL_ALIGNMENT_LEFT,430,18,3,INK)

func draw_legacy_menu() -> void:
	hearth_emblem(Vector2(83, 73), 11)
	text("A LITTLE LIGHT. A DIFFERENT RUN.", Vector2(112, 79), 14, GOLD, bold)
	text("Emberkeep", Vector2(62, 164), 58, INK, heading)
	text("Every little light fights back.", Vector2(65, 209), 23, GOLD, heading)
	text("Find strange relics. Make beautiful trouble.", Vector2(65, 244), 17, MUTED)
	divider(Vector2(64, 262), Vector2(482, 262))
	var weapon: Dictionary = starter_weapon()
	centered(weapon.name, 273, 314, 23, Color(weapon.color), heading)
	draw_multiline_string(body, Vector2(65, 357), weapon.description, HORIZONTAL_ALIGNMENT_LEFT, 418, 17, 2, MUTED)
	if not Run.has_save():
		text("%d runs  ·  %d victories" % [Run.profile.runs, Run.profile.wins], Vector2(66, 632), 17, MUTED)
	text("%d RELICS · %d PAINTINGS TO DISCOVER" % [Content.items.size(), gallery_ids().size()], Vector2(66, 671), 14, GOLD, bold)
	anchor(widen())
	hearth_emblem(Vector2(798, 566), 10)
	text("A warm place. A wild little dungeon.", Vector2(826, 574), 21, GOLD, heading)
	text("%d stackable relics  ·  new spellbooks every seed  ·  %d floors" % [Content.items.size(), Content.record("climbs", Run.CLIMB).bands.size()], Vector2(789, 617), 18, INK)
	text("Strange combinations. One more little light.", Vector2(789, 650), 17, MUTED)

func draw_hud() -> void:
	anchor(0)
	# Watching a teammate's trial: the world a little paler, out of reach.
	var trials = game.get("trials")
	if trials and trials.spectating(): draw_rect(Rect2(-offset.x / scale_value, 0, view_width + offset.x * 2.0 / scale_value, 720), Color(.8, .86, .96, .08))
	draw_foe_bars()
	draw_hud_left()
	anchor(widen() / 2.0)
	draw_hud_middle()
	if game.first_person and not stair_presentation_active():
		var aim_center = Vector2(640, 360)
		draw_circle(aim_center, 2.0, GOLD if game.fps.hit_time > 0 else INK)
		if game.fps.hit_time > 0:
			for x in [-1, 1]:
				for y in [-1, 1]: draw_line(aim_center + Vector2(x, y) * 6, aim_center + Vector2(x, y) * 11, INK, 2)
		if game.fps.damage_time > 0:
			var angle: float = game.fps.damage_angle - PI / 2
			draw_arc(aim_center, 78, angle - .35, angle + .35, 14, Color(1, .42, .28, game.fps.damage_time), 3.5)
		for side in [-1, 1]:
			draw_line(aim_center + Vector2(side * 7, 0), aim_center + Vector2(side * 12, 0), GOLD, 1.5)
		draw_threats(aim_center)
		draw_dash_arc(aim_center)
		draw_stamina_arc(aim_center)
	anchor(widen())
	draw_hud_right()

## A small health bar over each foe hurt in the last few seconds (bosses keep
## their plate at the top).
const FOE_BAR_TIME := 3.0
func draw_foe_bars() -> void:
	if stair_presentation_active() or not is_instance_valid(game.camera): return
	var camera: Camera3D = game.camera
	var eye: Vector3 = camera.global_position
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or not enemy.alive or enemy.boss or enemy.inert or not enemy.targetable: continue
		var since: float = enemy.age - enemy.hurt_at
		if since > FOE_BAR_TIME or enemy.hp >= enemy.max_hp: continue
		var head: Vector3 = enemy.global_position + Vector3.UP * ((float(enemy.hit_height) if game.first_person else float(enemy.radius) * 2.4) + .3)
		var distance := eye.distance_to(head)
		if camera.is_position_behind(head) or distance > 26.0: continue
		var at := local_point(camera.unproject_position(head))
		var fade := clampf((FOE_BAR_TIME - since) / .6, 0.0, 1.0)
		var width := clampf(300.0 / maxf(1.0, distance), 24.0, 56.0)
		var bar := Rect2(at - Vector2(width / 2.0, 0), Vector2(width, 4))
		draw_rect(bar.grow(1.5), Color(.04, .05, .04, .75 * fade))
		draw_rect(Rect2(bar.position, Vector2(width * clampf(enemy.health_fraction(), 0.0, 1.0), 4)), Color(Color("eda07a"), fade))

## Danger the eye cannot see: a marker round the sight toward each foe close
## by and off screen (larger and pulsing while it winds up or charges), and
## toward each hostile spell flying at the player from out of view.
const THREAT_REACH := 6.0
func draw_threats(center: Vector2) -> void:
	var player = game.player
	if not is_instance_valid(player) or not is_instance_valid(game.camera): return
	var camera: Camera3D = game.camera
	var size := get_viewport_rect().size
	var screen := Rect2(Vector2.ZERO, size).grow(-size.y * .05)
	var feet: Vector3 = player.global_position
	var right: Vector3 = game.fps.right()
	var ahead := Vector3.FORWARD.rotated(Vector3.UP, game.fps.yaw)
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or not enemy.alive or enemy.inert or not enemy.targetable: continue
		var striking: bool = enemy.windup > 0 or enemy.charge_time > 0
		var reach := THREAT_REACH * (1.7 if striking else 1.0) + float(enemy.radius)
		var towards: Vector3 = enemy.global_position - feet
		var gap := Vector2(towards.x, towards.z).length()
		if gap > reach: continue
		var chest: Vector3 = enemy.global_position + Vector3.UP * .9
		if not camera.is_position_behind(chest) and screen.has_point(camera.unproject_position(chest)): continue
		var near := 1.0 - gap / reach
		var alpha := .35 + .6 * near
		if striking: alpha = .55 + .45 * absf(sin(elapsed_ui * 14.0))
		threat_mark(center, atan2(towards.dot(right), towards.dot(ahead)), Color(1.0, .42, .28, alpha), 1.3 if striking else .8 + .3 * near)
	for shot in game.shots:
		if not is_instance_valid(shot) or not shot.alive or shot.friendly: continue
		var to_player: Vector3 = feet + Vector3.UP * .9 - shot.global_position
		var distance := to_player.length()
		if distance > 8.0 or distance < .01 or shot.direction.dot(to_player / distance) < .82: continue
		if not camera.is_position_behind(shot.global_position) and screen.has_point(camera.unproject_position(shot.global_position)): continue
		var towards: Vector3 = shot.global_position - feet
		threat_mark(center, atan2(towards.dot(right), towards.dot(ahead)), Color(EmberShot.HOSTILE, .5 + .5 * (1.0 - distance / 8.0)), .7)

## One marker: a small arrowhead pointing out from the sight at `angle`
## (0 ahead, positive to the right).
func threat_mark(center: Vector2, angle: float, color: Color, size_value: float) -> void:
	var direction := Vector2(sin(angle), -cos(angle))
	var side := Vector2(-direction.y, direction.x)
	var tip := center + direction * (60.0 + 10.0 * size_value)
	var back := tip - direction * 11.0 * size_value
	draw_colored_polygon(PackedVector2Array([tip + direction, back + side * 8.0 * size_value + direction, back - side * 8.0 * size_value + direction]), Color(0.04, 0.03, 0.03, color.a * .6))
	draw_colored_polygon(PackedVector2Array([tip, back + side * 7.0 * size_value, back - side * 7.0 * size_value]), color)

## Stamina as a small arc left of the sight, shown only while it is not
## full; red while winded.
func draw_stamina_arc(aim_center: Vector2) -> void:
	var player = game.player
	if not is_instance_valid(player) or player.stamina >= player.STAMINA - .01: return
	var start := PI * .7
	var sweep := PI * .6
	var left: float = player.stamina / player.STAMINA
	var tint := Color("e07a5f") if player.winded else Color("b7ddc0")
	draw_arc(aim_center, 26, start, start + sweep, 20, Color(.05, .06, .05, .5), 4.5, true)
	draw_arc(aim_center, 26, start + sweep * (1.0 - left), start + sweep, 20, Color(tint, .9), 3.0, true)

## The dash's recharge as a small arc under the crosshair, where a thumb on
## the DASH button never hides it; it glows once as the dash comes back.
func draw_dash_arc(aim_center: Vector2) -> void:
	if not is_instance_valid(game.player): return
	var cooling: bool = game.player.dash_cooldown > 0
	if dash_was_cooling and not cooling: dash_ready_glow = .35
	dash_was_cooling = cooling
	var start := PI * .2
	var sweep := PI * .6
	if cooling:
		var back := 1.0 - clampf(game.player.dash_cooldown / maxf(.01, float(game.player.dash_cooldown_full)), 0.0, 1.0)
		draw_arc(aim_center, 22, start, start + sweep, 20, Color(.05, .06, .05, .5), 4.5, true)
		draw_arc(aim_center, 22, start, start + sweep, 20, Color(MUTED, .5), 3.0, true)
		draw_arc(aim_center, 22, start + sweep * (1.0 - back), start + sweep, 20, Color(GOLD, .95), 3.0, true)
	elif dash_ready_glow > 0:
		draw_arc(aim_center, 22, start, start + sweep, 20, Color(GOLD, dash_ready_glow / .35), 3.5, true)

## One small slab: health, resources, weapon and held item; relics beneath.
func draw_hud_left() -> void:
	var hearts = int(ceil(Run.stats.max_hp / 2.0))
	for i in mini(hearts, 10):
		var at = Vector2(36 + i * 24, 38)
		var fill = clampf((Run.hp - i * 2) / 2, 0, 1)
		diamond(at + Vector2(0, 2), 11, Color("252c27"))
		diamond(at, 10, Color("717061"))
		if fill > 0:
			diamond(at, 10 * (.58 if fill < 1 else 1.0), Color("f4c68c"))
			draw_line(at + Vector2(-3, -4), at + Vector2(0, -8), Color("fff0c9"), 1.2, true)
	if hearts > 10:
		text("+%d" % (hearts - 10), Vector2(274, 44), 15, GOLD)
	draw_kindle(Vector2(HUD_RECT.end.x - 26, 38))
	draw_circle(Vector2(37, 66), 7, Color("302f23"))
	draw_circle(Vector2(36, 64), 6, Color("ceab68"))
	draw_line(Vector2(36, 61), Vector2(36, 67), Color("f7dfa5"), 1.4)
	text("%02d" % Run.coins, Vector2(48, 71), 18, GOLD, bold)
	resource_icon("key", Vector2(100, 64))
	text("%d" % Run.keys, Vector2(114, 71), 18, INK if Run.keys > 0 else MUTED, bold)
	resource_icon("bomb", Vector2(152, 64))
	text("%d" % Run.bombs, Vector2(166, 71), 18, INK if Run.bombs > 0 else MUTED, bold)
	resource_icon("ward", Vector2(204, 64))
	text("%d" % Run.wards, Vector2(218, 71), 18, Color("b7ddc0") if Run.wards > 0 else MUTED, bold)
	if game.player and game.player.shield > 0:
		right_text("%d guard" % game.player.shield, Vector2(HUD_RECT.end.x - 14, 71), 14, Color("b7ddc0"), bold)
	text(Run.weapon().name, WEAPON_LABEL, 16, INK)
	draw_active_line()
	for i in mini(Run.inventory.size(), 12):
		var item: Dictionary = Content.item_by_id[Run.inventory[i]]
		diamond(Vector2(28 + i * 17, HUD_RECT.end.y + 16), 6, Content.RARITY_COLORS[item.rarity])
	if Run.inventory.size() > 12:
		text("+%d" % (Run.inventory.size() - 12), Vector2(232, HUD_RECT.end.y + 21), 14, GOLD)
	if not Run.curses.is_empty():
		text("CURSED · " + " · ".join(Run.curses.map(func(curse): return DeathBargain.curse_name(curse).to_upper())), Vector2(22, HUD_RECT.end.y + 42), 12, DeathBargain.COLOR, bold)
	if not touch_hud_visible() and not stair_presentation_active():
		text("%s move · %s run · Mouse aim/cast · %s jump · %s dash · %s interact" % [move_keys(), Settings.key_label("sprint"), Settings.key_label("jump"), Settings.key_label("dash"), Settings.key_label("interact")] if game.first_person else "%s move · Mouse cast · %s dash · %s item · %s bomb" % [move_keys(), Settings.key_label("dash"), Settings.key_label("use_active"), Settings.key_label("place_bomb")], Vector2(28, 668), 15, MUTED)
	text("SEED %d" % Run.seed_value, Vector2(28, 697), 13, MUTED)
	if touch_hud_visible():
		draw_stick(left_origin if left_touch >= 0 else control_spot("move").center, left_vector, "RUN" if game.player and game.player.sprinting else "MOVE", left_touch >= 0, float(control_spot("move").scale))

## The four movement keys as one word when they are letters ("WASD").
func move_keys() -> String:
	var keys: Array = ["move_up", "move_left", "move_down", "move_right"].map(func(action): return Settings.key_label(action))
	return "".join(keys) if keys.all(func(key): return str(key).length() == 1) else " ".join(keys)

## How to interact on this device: a tap, the bound key, a gamepad's Y.
func interact_hint() -> String:
	if touch_hud_visible(): return "Tap to interact"
	var hint := "Press %s" % Settings.key_label("interact")
	if not Input.get_connected_joypads().is_empty(): hint += "  ·  Y"
	return hint

## The boss's plate while it fights, the room's state and any interaction.
## The kindle as three small flames, lit one by one, and caught sparks as
## bright points beside them.
func draw_kindle(at: Vector2) -> void:
	var level: int = game.kindle_level()
	for i in 3:
		var flame = at - Vector2(i * 16, 0)
		var lit = (2 - i) < level
		var points = PackedVector2Array([flame + Vector2(0, -9), flame + Vector2(5, 1), flame + Vector2(0, 6), flame + Vector2(-5, 1)])
		if lit:
			draw_colored_polygon(points, Color("ffb14e") if level < 3 else Color("ffe08a"))
		else:
			points.append(points[0])
			draw_polyline(points, Color(MUTED, .5), 1.2, true)
	for i in game.sparks:
		draw_circle(at - Vector2(54 + i * 9, -1), 2.6, Color("fff3c4"))

func draw_hud_middle() -> void:
	if stair_presentation_active(): return
	var boss_enemy = game.get_boss()
	if boss_enemy:
		centered(Foes.boss_name(boss_enemy.kind), 640, 40, 15, Color("efbd9f"), bold)
		draw_rect(Rect2(486, 50, 308, 6), Color("252b27"))
		draw_rect(Rect2(486, 50, 308 * boss_enemy.health_fraction(), 6), Color("d79275"))
	if game.room and not game.room.open:
		var remaining = 0
		for enemy in game.enemies:
			if is_instance_valid(enemy) and enemy.alive and not enemy.inert: remaining += 1
		centered("1 little trouble remains" if remaining == 1 else "%d little troubles remain" % remaining, 640, 697, 15, MUTED)
	else:
		centered("Doorways are open · keep exploring", 640, 697, 15, MUTED)
	var trials = game.get("trials")
	var trial_line: String = trials.hud_line() if trials else ""
	if trial_line != "": centered(trial_line, 640, 672, 17, DeathBargain.COLOR, bold)
	if game.interaction_text != "":
		centered(game.interaction_text, 640, 596, 21, GOLD, bold)
		centered(interact_hint(), 640, 624, 16, MUTED)

func draw_hud_right() -> void:
	draw_minimap()
	text("%d:%02d" % [int(Run.elapsed) / 60, int(Run.elapsed) % 60], Vector2(1196, 697), 15, MUTED)
	if not touch_hud_visible(): return
	if not game.first_person: draw_stick(right_origin, right_vector, "AIM + CAST", right_touch >= 0)
	draw_touch_buttons(false)

## The action buttons where the layout puts them (all of them while arranging).
func draw_touch_buttons(arranging: bool) -> void:
	if game.first_person or arranging:
		for action in ["fire", "jump"]:
			var spot := control_spot(action)
			draw_action_ring(action, 1.0, GOLD)
			centered("CAST" if action == "fire" else "JUMP", spot.center.x, spot.center.y + 6, 18 if action == "fire" else 15, GOLD, bold)
	var ready: bool = arranging or (game.player and game.player.dash_cooldown <= 0)
	var dash := control_spot("dash")
	draw_action_ring("dash", 1.0 if ready else 0.0, GOLD if ready else MUTED)
	centered("DASH" if ready else "%.1f" % game.player.dash_cooldown, dash.center.x, dash.center.y + 7, 18, GOLD if ready else MUTED, bold)
	draw_active_button()
	var bomb := control_spot("bomb")
	var have_bombs: bool = arranging or Run.bombs > 0
	draw_action_ring("bomb", 1.0 if have_bombs else 0.0, GOLD if have_bombs else MUTED)
	resource_icon("bomb", bomb.center + Vector2(0, -8))
	centered("×%d" % Run.bombs, bomb.center.x, bomb.center.y + 22, 15, INK if have_bombs else MUTED, bold)

func right_text(value: String, at: Vector2, size_value := 18, color := INK, font: Font = null) -> void:
	var f = font if font else body
	text(value, at - Vector2(f.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value).x, 0), size_value, color, f)

## Starts the current floor's title: its name spelled out letter by letter
## across the whole screen, held a moment, then faded.
func announce_floor() -> void:
	floor_title_start = elapsed_ui

func floor_title_length() -> float:
	var letters = str(Run.theme().name).length()
	# A little longer than the name alone, to read the epigraph under it.
	return TITLE_DELAY + letters * TITLE_LETTER + .3 + TITLE_HOLD + .9 + TITLE_FADE

func draw_floor_title() -> void:
	if game.first_person:
		var t = elapsed_ui - floor_title_start
		if t >= 0 and t < 2.6:
			var opacity = minf(clampf(t / .25, 0, 1), clampf((2.6 - t) / .6, 0, 1))
			centered(str(Run.theme().name), view_width / 2, 186, 25, Color(INK, opacity), heading)
		return
	var age = elapsed_ui - floor_title_start
	if age < 0 or age > floor_title_length(): return
	var theme: Dictionary = Run.theme()
	var twist: Dictionary = Content.record("twists", Run.twist_id())
	var name_text: String = str(theme.name).to_upper()
	var fade = 1.0 - clampf((age - (floor_title_length() - TITLE_FADE)) / TITLE_FADE, 0.0, 1.0)
	var size_value = 58
	# Spread the letters over most of the screen's width, whatever its shape.
	var span = view_width * .82
	var widths: Array = []
	var natural = 0.0
	for letter in name_text:
		var w = heading.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value).x
		widths.append(w)
		natural += w
	var gap = maxf(0.0, (span - natural) / maxf(1, name_text.length() - 1))
	var x = (view_width - (natural + gap * (name_text.length() - 1))) / 2.0
	var baseline = 268.0
	var caption = clampf(age / TITLE_DELAY, 0.0, 1.0) * fade
	var floor_caption = "FLOOR %d OF %d" % [Run.floor_number, Run.climb_length()]
	if not twist.is_empty(): floor_caption += "  ·  " + str(twist.name).to_upper()
	centered(floor_caption, view_width / 2.0, baseline - 74, 16, Color(GOLD, caption), bold)
	var shown = 0.0
	for i in name_text.length():
		var appear = clampf((age - TITLE_DELAY - i * TITLE_LETTER) / .3, 0.0, 1.0)
		if appear > 0:
			var rise = (1.0 - appear) * -12.0
			text(name_text[i], Vector2(x, baseline + rise), size_value, Color(INK, appear * fade), heading)
			shown = x + widths[i]
		x += widths[i] + gap
	# A thin gold rule follows the letters out from the middle.
	var reach = clampf((age - TITLE_DELAY) / (name_text.length() * TITLE_LETTER + .3), 0.0, 1.0) * span / 2.0
	if reach > 0:
		var middle = view_width / 2.0
		draw_line(Vector2(middle - reach, baseline + 24), Vector2(middle + reach, baseline + 24), Color(GOLD, .55 * fade), 1.5, true)
	# Once the name is spelled, the floor's epigraph and its twist settle in.
	var words = clampf((age - TITLE_DELAY - name_text.length() * TITLE_LETTER - .2) / .5, 0.0, 1.0) * fade
	if words > 0:
		centered(str(theme.epigraph), view_width / 2.0, baseline + 62, 19, Color(INK, words * .85), body)
		if not twist.is_empty(): centered(str(twist.line), view_width / 2.0, baseline + 92, 16, Color(GOLD, words * .8), body)

func resource_icon(kind: String, at: Vector2) -> void:
	match kind:
		"key":
			draw_arc(at + Vector2(-4, 0), 4.5, 0, TAU, 16, Color("e3c27a"), 2.2, true)
			draw_line(at + Vector2(0, 0), at + Vector2(9, 0), Color("e3c27a"), 2.4)
			draw_line(at + Vector2(7, 0), at + Vector2(7, 4), Color("e3c27a"), 2.2)
		"bomb":
			draw_circle(at + Vector2(0, 2), 7, Color("252c27"))
			draw_circle(at + Vector2(0, 1), 6.5, Color("8f9497"))
			draw_line(at + Vector2(3, -5), at + Vector2(6, -9), Color("c9b183"), 1.6)
			draw_circle(at + Vector2(6.5, -9.5), 1.8, Color("ffd38a"))
		"ward":
			var shield = PackedVector2Array([at + Vector2(-7, -7), at + Vector2(7, -7), at + Vector2(6, 2), at + Vector2(0, 8), at + Vector2(-6, 2)])
			draw_colored_polygon(shield, Color("a3dacf"))
			draw_line(at + Vector2(0, -5), at + Vector2(0, 5), Color("e9f5ef"), 1.2)

func active_state() -> Dictionary:
	if Run.active_item.is_empty():
		return {}
	var definition: Dictionary = Content.record("actives", Run.active_item.def)
	var remaining = Run.cooldown_remaining(definition.id)
	return {"definition": definition, "remaining": remaining, "fraction": 1.0 - clampf(remaining / float(definition.cooldown), 0, 1)}

func draw_active_line() -> void:
	var state = active_state()
	if state.is_empty():
		text("No item in hand", Vector2(30, 119), 15, MUTED)
		return
	diamond(Vector2(36, 114), 6, Color(state.definition.color))
	text(state.definition.name, Vector2(48, 119), 15, INK)
	var status = "ready · F" if state.remaining <= 0 else "%ds" % ceili(state.remaining)
	right_text(status, Vector2(HUD_RECT.end.x - 14, 119), 14, GOLD if state.remaining <= 0 else MUTED, bold)

func draw_action_ring(action: String, fraction: float, color: Color) -> void:
	var button_region: Dictionary = control_spot(action)
	var center: Vector2 = button_region.center
	var radius: float = button_region.radius
	draw_circle(center + Vector2(0, 4), radius, Color(.02, .03, .03, .7))
	draw_circle(center, radius, Color(.18, .21, .18, .88))
	draw_arc(center, radius - 2, 0, TAU, 48, Color(MUTED, .45), 2, true)
	if fraction > 0:
		draw_arc(center, radius - 2, -PI / 2, -PI / 2 + TAU * fraction, 48, color, 2.5, true)

## Item icon, cooldown ring and a seconds readout while recharging.
func draw_active_button() -> void:
	var center: Vector2 = control_spot("active").center
	var state = active_state()
	if state.is_empty():
		draw_action_ring("active", 0.0, MUTED)
		centered("ITEM", center.x, center.y + 6, 15, MUTED, bold)
		return
	var ready = state.remaining <= 0
	draw_action_ring("active", state.fraction, GOLD if ready else Color(state.definition.color))
	diamond(center + Vector2(0, -6), 13, Color(state.definition.color), ready)
	centered("USE" if ready else "%d" % ceili(state.remaining), center.x, center.y + 25, 15, GOLD if ready else INK, bold)

func draw_stick(at: Vector2, value: Vector2, label: String, active_touch: bool, size := 1.0) -> void:
	draw_circle(at + Vector2(0, 4), 66 * size, Color(.02, .03, .025, .35))
	draw_circle(at, 66 * size, Color(.16, .19, .16, .48))
	draw_arc(at, 66 * size, 0, TAU, 48, Color(GOLD, .55 if active_touch else .3), 2, true)
	draw_arc(at, 59 * size, 0, TAU, 48, Color(.06, .08, .065, .6), 2, true)
	draw_circle(at + value * 48 * size + Vector2(0, 3), 28 * size, Color(.02, .03, .02, .45))
	draw_circle(at + value * 48 * size, 28 * size, Color(.65, .57, .39, .7 if active_touch else .4))
	draw_arc(at + value * 48 * size, 27 * size, PI, TAU, 24, Color(GOLD, .65), 2, true)
	centered(label, at.x, at.y + 91 * size, 14, Color(INK, .8), bold)

func draw_minimap() -> void:
	# Keep the shortcut fixed while the map and player marker move.
	if not game.first_person:
		draw_floor_map(MINIMAP_AREA, map_room_focus(), 22.0)
	if not touch_hud_visible():
		right_text("M", MINIMAP_RECT.end - Vector2(20, 11), 12, MUTED)

func map_room_focus() -> Vector2:
	var transit := map_corridor_progress()
	if not transit.is_empty():
		return map_room_center(transit.source).lerp(map_room_center(transit.destination),transit.progress)
	return map_room_center(Run.current_room)

func map_room_center(id: String) -> Vector2:
	var cells = FloorGenerator.room_cells(Run.rooms[id])
	var focus := Vector2.ZERO
	for cell in cells: focus += Vector2(cell)
	return focus / cells.size()

## Room-local metres become global floor cells, including multi-cell rooms.
## Height deliberately has no effect: upstairs and downstairs share a map.
func map_player_position() -> Vector2:
	var transit := map_corridor_progress()
	if not transit.is_empty():
		var source: Dictionary = Run.portal_side(transit.portal,transit.source)
		var destination: Dictionary = Run.portal_side(transit.portal,transit.destination)
		var a := Vector2(FloorGenerator.vec(source.cell))+Vector2(FloorGenerator.vec(source.dir))*.5
		var b := Vector2(FloorGenerator.vec(destination.cell))+Vector2(FloorGenerator.vec(destination.dir))*.5
		# The floor chart compresses the physical connector into the doorway gap.
		return a.lerp(b,transit.progress)
	var anchor := Vector2(Run.room_anchor(Run.rooms[Run.current_room]))
	if not is_instance_valid(game.player): return map_room_focus()
	var at: Vector3 = game.player.position
	return anchor + Vector2(at.x, at.z) / RoomGeometry.CELL

## Project against the same corridor path before and after origin rebasing.
## Room ownership changes at the elbow; chart position must not change with it.
func map_corridor_progress() -> Dictionary:
	if not game.first_person or not game.corridors or not game.corridors.walking(): return {}
	var transit = game.corridors
	var at: Vector3 = game.player.position-transit.active.position
	var length := CorridorPlan.distance(transit.active.path,0,transit.active.path.size()-1)
	return {"source":transit.source_room,"destination":transit.destination_room,
		"portal":transit.portal_id,"progress":clampf(CorridorPlan.project(transit.active.path,Vector2(at.x,at.z))/maxf(length,.001),0,1)}

func build_rotating_minimap() -> void:
	minimap_clip = Control.new()
	minimap_clip.name = "MinimapClip"
	minimap_clip.position = moved(MINIMAP_AREA, widen()).position
	minimap_clip.size = MINIMAP_AREA.size
	minimap_clip.clip_contents = true
	minimap_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(minimap_clip)
	minimap_ink = Node2D.new()
	minimap_ink.name = "MapInk"
	minimap_ink.position = MINIMAP_AREA.size * .5
	minimap_clip.add_child(minimap_ink)
	minimap_ink.draw.connect(draw_rotating_minimap.bind(minimap_ink))
	minimap_pointer = Node2D.new()
	minimap_pointer.name = "ViewDirection"
	minimap_pointer.position = minimap_ink.position
	minimap_clip.add_child(minimap_pointer)
	minimap_pointer.draw.connect(draw_minimap_pointer.bind(minimap_pointer))
	sync_minimap()

func sync_minimap() -> void:
	if not is_instance_valid(minimap_ink): return
	var forward: Vector3 = -game.camera.global_basis.z
	var bearing := Vector2(forward.x, forward.z)
	# Use the rendered view's horizontal bearing, including camera transitions.
	# Looking straight up/down retains the last meaningful compass direction.
	if bearing.length_squared() > .0001: minimap_ink.rotation = bearing.angle_to(Vector2.UP)
	var offset := (map_player_position() - map_room_focus()) * 22.0
	minimap_pointer.position = minimap_ink.position + offset.rotated(minimap_ink.rotation)
	minimap_ink.queue_redraw()
	minimap_pointer.queue_redraw()

func draw_rotating_minimap(target: CanvasItem) -> void:
	if not Run.rooms.has(Run.current_room): return
	# Cover the rectangular aperture at every angle, including complete edge
	# segments whose endpoints fall outside it. The parent canvas clips ink.
	var radius := MINIMAP_AREA.size.length() * .5 + 44.0
	draw_floor_map(Rect2(-Vector2.ONE * radius, Vector2.ONE * radius * 2), map_room_focus(), 22.0, target)

func draw_minimap_pointer(target: CanvasItem) -> void:
	draw_map_arrow(target, Vector2.ZERO, 0.0)

func draw_map_arrow(target: CanvasItem, at: Vector2, angle: float) -> void:
	var outline := PackedVector2Array()
	var fill := PackedVector2Array()
	for point in [Vector2(0,-7),Vector2(-5,5),Vector2(0,3),Vector2(5,5)]: outline.append(at + point.rotated(angle))
	for point in [Vector2(0,-5),Vector2(-3,3),Vector2(0,1),Vector2(3,3)]: fill.append(at + point.rotated(angle))
	target.draw_colored_polygon(outline, Color("202724"))
	target.draw_colored_polygon(fill, GOLD)

## Rooms the player may know about: those walked through, and every room
## glimpsed through one of their open doorways, so the map shows each way on
## that is still unexplored. A concealed passage reveals nothing until opened.
func map_rooms() -> Array:
	var known := {}
	for id in Run.rooms:
		if not Run.rooms[id].visited and id != Run.current_room: continue
		known[id] = true
		for next in Run.neighbors(id): known[next] = true
	return Run.rooms.keys().filter(func(id): return known.has(id))

func map_color(id: String) -> Color:
	var room: Dictionary = Run.rooms[id]
	if id == Run.current_room: return INK
	if room.type == "treasure": return GOLD
	if room.type == "shop": return Color("afcfaa")
	if room.type == "dark": return Color("b98ae0")
	if room.type == "boss": return Color("da9b80")
	if room.get("secret", false): return Color("b9a2c9")
	return Color("9b9e82") if room.cleared else Color("626957")

## Draws each room's whole footprint as one shape: cells merge across their
## own seams, and short connectors mark actual doorways, not adjacency.
func draw_floor_map(area: Rect2, focus: Vector2, cell_size: float, target: CanvasItem = null) -> void:
	if target == null: target = self
	var known = map_rooms()
	var origin = area.get_center() - focus * cell_size
	var inset = maxf(3.0, cell_size * .2)
	for portal in Run.portals.values():
		if portal.state == "concealed" or portal.a.room not in known or portal.b.room not in known: continue
		var a = Vector2(FloorGenerator.vec(portal.a.cell))
		var direction = Vector2(FloorGenerator.vec(portal.a.dir))
		var start = origin + (a + direction * (.5 - inset / cell_size)) * cell_size
		var end = origin + (a + direction * (.5 + inset / cell_size)) * cell_size
		if area.has_point(start) and area.has_point(end):
			target.draw_line(start, end, Color("9d9878"), maxf(2.0, cell_size * .12), true)
	for id in known:
		var data: Dictionary = Run.rooms[id]
		var cells = FloorGenerator.room_cells(data)
		var color = map_color(id)
		var explored: bool = cells.any(func(cell): return Run.is_seen(data, cell))
		if explored: draw_room_scribbled(cells, origin, area, color, cell_size, target)
		for cell in cells:
			var low = Vector2(inset if not cells.has(cell + Vector2i.LEFT) else 0.0, inset if not cells.has(cell + Vector2i.UP) else 0.0)
			var high = Vector2(inset if not cells.has(cell + Vector2i.RIGHT) else 0.0, inset if not cells.has(cell + Vector2i.DOWN) else 0.0)
			var rect = Rect2(origin + (Vector2(cell) - Vector2(.5, .5)) * cell_size + low, Vector2.ONE * cell_size - low - high)
			if not explored:
				# Known but not yet walked: a faint pencil outline, merged across
				# the room's own unexplored seams.
				for direction in RoomGeometry.DIRECTIONS:
					var next: Vector2i = cell + direction
					if cells.has(next) and not Run.is_seen(data, next): continue
					var edge = ghost_edge(rect, direction)
					if area.has_point(edge[0]) and area.has_point(edge[1]):
						target.draw_dashed_line(edge[0], edge[1], Color(color, .5), maxf(1.0, cell_size * .05), maxf(2.5, cell_size * .12), true, true)
		if data.get("fps_terrain",{}).get("kind","")=="loft":
			var mark: Vector2=origin+Vector2(FloorGenerator.vec(data.anchor))*cell_size+Vector2(2,-2)
			if area.grow(-5).has_point(mark):
				target.draw_rect(Rect2(mark-Vector2(4,4),Vector2(8,8)),Color("202724"))
				for y in [-2,2]: target.draw_line(mark+Vector2(-3,y),mark+Vector2(3,y),GOLD,1.0,true)
				target.draw_line(mark+Vector2(-2,2),mark+Vector2(2,-2),GOLD,1.0,true)
		if id == Run.current_room:
			# One outline around the whole footprint, drawn on exposed edges only.
			var reach = cell_size * .5 - inset + 2.5
			for cell in cells:
				var center = origin + Vector2(cell) * cell_size
				for direction in RoomGeometry.DIRECTIONS:
					if cells.has(cell + direction): continue
					var across = Vector2i(absi(direction.y), absi(direction.x))
					var mid = center + Vector2(direction) * reach
					var start = mid - Vector2(across) * (cell_size * .5 if cells.has(cell - across) else reach)
					var end = mid + Vector2(across) * (cell_size * .5 if cells.has(cell + across) else reach)
					if area.has_point(start) and area.has_point(end):
						target.draw_line(start, end, GOLD, 1.5, true)

func draw_room_scribbled(cells: Array, origin: Vector2, area: Rect2, color: Color, cell_size: float, target: CanvasItem) -> void:
	var key := str(cells) + ":" + str(cell_size)
	if not room_ink_cache.has(key):
		if room_ink_cache.size() >= 64: room_ink_cache.clear()
		var polygon := RoomMapInk.outline(cells, cell_size)
		var inner := Geometry2D.offset_polygon(polygon, -cell_size * .065)
		room_ink_cache[key] = {"outline": polygon, "path": RoomMapInk.path(inner[0] if not inner.is_empty() else polygon)}
	var ink: Dictionary = room_ink_cache[key]
	var progress := 1.0
	for cell in cells: progress = minf(progress, scribble_progress(cell))
	var aperture := PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)])
	var silhouette := PackedVector2Array()
	var shadow := PackedVector2Array()
	for point in ink.outline:
		silhouette.append(point + origin)
		shadow.append(point + origin + Vector2(0, 2))
	for polygon in Geometry2D.intersect_polygons(shadow, aperture): target.draw_colored_polygon(polygon, Color("262e28"))
	for polygon in Geometry2D.intersect_polygons(silhouette, aperture): target.draw_colored_polygon(polygon, Color(color.darkened(.5), .45 * progress))
	var points := partial_path(ink.path, progress)
	for i in points.size(): points[i] += origin
	for line in Geometry2D.intersect_polyline_with_polygon(points, aperture):
		if line.size() >= 2: target.draw_polyline(line, Color(color, .8), 1.05, true)

func scribble(cell: Vector2i) -> void:
	scribbles[cell] = elapsed_ui

## How far a cell's scribble has been drawn (eased); old cells are complete.
func scribble_progress(cell: Vector2i) -> float:
	if not scribbles.has(cell): return 1.0
	var t = clampf((elapsed_ui - scribbles[cell]) / SCRIBBLE_TIME, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 2.0)

static func ghost_edge(rect: Rect2, direction: Vector2i) -> Array:
	match direction:
		Vector2i.UP: return [rect.position, Vector2(rect.end.x, rect.position.y)]
		Vector2i.DOWN: return [Vector2(rect.position.x, rect.end.y), rect.end]
		Vector2i.LEFT: return [rect.position, Vector2(rect.position.x, rect.end.y)]
	return [Vector2(rect.end.x, rect.position.y), rect.end]

## The first `progress` of a path's length, ending part-way along a segment.
static func partial_path(points: PackedVector2Array, progress: float) -> PackedVector2Array:
	if progress >= 1.0 or points.size() < 2: return points.duplicate()
	var total = 0.0
	for i in range(1, points.size()): total += points[i - 1].distance_to(points[i])
	var left = total * maxf(progress, 0.0)
	var out = PackedVector2Array([points[0]])
	for i in range(1, points.size()):
		var length = points[i - 1].distance_to(points[i])
		if left >= length:
			out.append(points[i])
			left -= length
		else:
			if length > 0.0: out.append(points[i - 1].lerp(points[i], left / length))
			break
	return out

## The full map's focus and cell size: [focus, cell size].
func full_map_frame() -> Array:
	var low = Vector2(INF, INF)
	var high = -low
	for id in map_rooms():
		for cell in FloorGenerator.room_cells(Run.rooms[id]):
			low = Vector2(minf(low.x, cell.x), minf(low.y, cell.y))
			high = Vector2(maxf(high.x, cell.x), maxf(high.y, cell.y))
	var span = high - low + Vector2.ONE
	return [(low + high) / 2.0, minf(48.0, minf(FULL_MAP_AREA.size.x / (span.x + 1), FULL_MAP_AREA.size.y / (span.y + 1)))]

## The room drawn under a point of the full map, or "".
func map_room_at(point: Vector2) -> String:
	var frame := full_map_frame()
	var cell_size: float = frame[1]
	var origin: Vector2 = FULL_MAP_AREA.get_center() - frame[0] * cell_size
	for id in map_rooms():
		for cell in FloorGenerator.room_cells(Run.rooms[id]):
			if Rect2(origin + (Vector2(cell) - Vector2(.5, .5)) * cell_size, Vector2.ONE * cell_size).has_point(point): return id
	return ""

## A tap or click on a room of the full map walks back there, when it can.
var map_message := ""
func map_input(event: InputEvent) -> bool:
	var at := Vector2.ZERO
	if event is InputEventScreenTouch and event.pressed: at = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION: at = event.position
	else: return false
	var point := local_point(at) - Vector2(layer_shift(), 0)
	if not FULL_MAP_AREA.has_point(point) or not Run.active: return false
	var id := map_room_at(point)
	if id == "": return false
	var why: String = game.travel_block(id)
	if why != "":
		map_message = why
		queue_redraw()
		return true
	map_message = ""
	game.travel_to(id)
	return true

func draw_full_map() -> void:
	hearth_emblem(Vector2(640, 96), 11)
	centered("The way home", 640, 140, 32, INK, heading)
	var frame := full_map_frame()
	draw_floor_map(FULL_MAP_AREA, frame[0], frame[1])
	if game.first_person and is_instance_valid(game.player):
		var at: Vector2 = FULL_MAP_AREA.get_center() + (map_player_position() - frame[0]) * frame[1]
		var forward: Vector3 = -game.camera.global_basis.z
		var bearing := Vector2(forward.x, forward.z)
		var angle: float = bearing.angle() + PI * .5 if bearing.length_squared() > .0001 else -game.fps.yaw
		if FULL_MAP_AREA.grow(-7).has_point(at): draw_map_arrow(self, at, angle)
	if map_message != "": centered(map_message, 640, 166, 15, Color("efbd9f"), bold)
	else: centered(("Tap" if touch_hud_visible() else "Click") + " a room you have cleared to go back to it", 640, 166, 15, MUTED)
	var main_rooms = Run.rooms.values().filter(func(room): return not room.get("secret", false))
	var twist_name = str(Content.record("twists", Run.twist_id()).get("name", ""))
	centered("%s  ·  Floor %d of %d%s  ·  %d of %d rooms visited  ·  Outlined: you are here" % [Run.theme().name, Run.floor_number, Run.climb_length(),
		"  ·  " + twist_name if twist_name != "" else "", main_rooms.filter(func(room): return room.visited).size(), main_rooms.size()], 640, 578, 17, MUTED)

func draw_rewards() -> void:
	hearth_emblem(Vector2(640, 61), 12)
	centered("The candle merchant" if shop else "A small kindness", 640, 123, 38, INK, heading)
	centered("A good find is worth a few coins. You have %d." % Run.coins if shop else "Choose one. Let it change the way you play.", 640, 165, 20, MUTED)
	for i in offers.size():
		var item = offer_info(offers[i])
		var color: Color = item.color
		var rect = reward_rect(i)
		var x = rect.position.x
		var middle = rect.get_center().x
		centered(item.label, middle, 232, 15, color, bold)
		draw_circle(Vector2(middle, 291), 37, Color(.08, .10, .08, .5))
		diamond(Vector2(middle, 293), 27, Color("262f28"))
		diamond(Vector2(middle, 288), 25, color, false)
		diamond(Vector2(middle, 288), 15, color)
		draw_arc(Vector2(middle, 290), 44, -.7, 3.7, 32, Color(color, .32), 1.5, true)
		centered(item.name, middle, 361, 24, INK, heading)
		divider(Vector2(x + 28, 379), Vector2(x + REWARD_WIDTH - 28, 379))
		draw_multiline_string(body, Vector2(x + 26, 409), item.description, HORIZONTAL_ALIGNMENT_CENTER, REWARD_WIDTH - 52, 18, 3, MUTED)
		centered(item.tag, middle, 465, 13, color, bold)
		var hint := combination_hint(offers[i])
		if hint != "": centered(hint, middle, 556, 12, GOLD, bold)
	centered("Relics stack. Find something beautifully strange.", 640, 692, 17, MUTED)

func draw_journal() -> void:
	text("The things we carry", Vector2(64, 146), 40, INK, heading)
	text("%d relics to find. Every effect stacks with your spellbook and other relics." % Content.items.size(), Vector2(66, 184), 19, MUTED)
	var start = journal_page * JOURNAL_PAGE_SIZE
	for slot in JOURNAL_PAGE_SIZE:
		var index = start + slot
		if index >= Content.items.size(): break
		var item: Dictionary = Content.items[index]
		var rect = journal_rect(slot)
		var x = rect.position.x
		var y = rect.position.y
		var owned: bool = item.id in Run.inventory
		var found: bool = item.id in Run.profile.discovered
		var color: Color = Content.RARITY_COLORS[item.rarity]
		diamond(Vector2(x + 31, y + 34), 11, color, found or owned)
		text(item.name, Vector2(x + 57, y + 41), 21, color if owned else INK, bold)
		if owned: text("×%d" % Run.inventory.count(item.id), Vector2(x + 504, y + 41), 18, GOLD)
		draw_multiline_string(body, Vector2(x + 27, y + 73), item.description, HORIZONTAL_ALIGNMENT_LEFT, 510, 18, 2, MUTED)
	text("%d / %d found  ·  Filled diamonds are discovered relics" % [Run.profile.discovered.size(), Content.items.size()], Vector2(66, 664), 17, MUTED)
	centered("%d / %d" % [journal_page + 1, journal_page_count()], 976, 664, 20, GOLD)

## While a run is prepared: the hearth's emblem breathing, a line of advice
## and how far along it is.
func draw_loading() -> void:
	var breath := .5 + .5 * sin(elapsed_ui * 2.6)
	hearth_emblem(Vector2(640, 262), 17.0 + breath * 3.0)
	centered(loading_title, 640, 350, 40, INK, heading)
	centered(LOADING_TIPS[int(elapsed_ui / 4.0) % LOADING_TIPS.size()], 640, 394, 18, MUTED)
	draw_rect(Rect2(440, 440, 400, 6), Color(.2, .18, .14, .85))
	draw_rect(Rect2(440, 440, 400 * clampf(loading_progress, 0, 1), 6), GOLD)

## What an offer would combine with: a pairing it completes (named once
## found, hinted before), or the spellbook's element it sings with.
func combination_hint(offer: Dictionary) -> String:
	var element := Synergies.weapon_element(Run.weapon())
	if offer.get("kind", "item") == "weapon":
		var count := Synergies.resonance(Run.inventory, Synergies.weapon_element(Forge.lookup(offer.id)))
		return "%d OF YOUR RELICS SING WITH IT" % count if count > 0 else ""
	if offer.get("kind", "item") != "item": return ""
	var completed := Synergies.completes(Run.inventory, str(offer.id))
	if not completed.is_empty():
		var id: String = completed[0]
		return "COMPLETES " + Synergies.PAIRINGS[id][2].to_upper() if "p:" + id in Run.profile.combos else "SOMETHING YOU CARRY ANSWERS THIS"
	return "SINGS WITH YOUR SPELLBOOK" if Synergies.resonates(str(offer.id), element) else ""

## Reactions, pairings and resonance: named once found, a riddle before.
func draw_combos() -> void:
	text("What meets, and what it makes", Vector2(64, 146), 40, INK, heading)
	var ids: Array = Synergies.all_ids()
	var found = ids.filter(func(id): return id in Run.profile.combos).size()
	text("%d / %d found  ·  Elements meet on foes, relics pair, relics sing with a spellbook" % [found, ids.size()], Vector2(66, 184), 19, MUTED)
	for slot in JOURNAL_PAGE_SIZE:
		var index = journal_page * JOURNAL_PAGE_SIZE + slot
		if index >= ids.size(): break
		var id: String = ids[index]
		var info: Array = Synergies.entry(id)
		var rect = journal_rect(slot)
		var x = rect.position.x
		var y = rect.position.y
		var known: bool = id in Run.profile.combos
		var kind: String = {"r": "REACTION", "p": "PAIRING", "e": "RESONANCE"}[id.get_slice(":", 0)]
		var recipe: String = info[1]
		if id.begins_with("p:"):
			var pair: Array = Synergies.PAIRINGS[id.get_slice(":", 1)]
			recipe = "%s + %s" % [Content.item_by_id[pair[0]].name, Content.item_by_id[pair[1]].name]
		diamond(Vector2(x + 31, y + 34), 11, info[4], known)
		text(info[0] if known else "???", Vector2(x + 57, y + 41), 21, info[4] if known else MUTED, bold)
		right_text(kind + ("  ·  " + recipe.to_upper() if known else ""), Vector2(x + 540, y + 38), 12, Color(GOLD, .8), bold)
		draw_multiline_string(body, Vector2(x + 27, y + 73), info[2] if known else "“%s”" % info[3], HORIZONTAL_ALIGNMENT_LEFT, 510, 17, 2, INK if known else MUTED)
	centered("%d / %d" % [journal_page + 1, journal_page_count()], 976, 664, 20, GOLD)

## Every floor theme of the tower, its words revealed once reached.
func draw_floors() -> void:
	text("The tower we climb", Vector2(64, 146), 40, INK, heading)
	var themes: Array = Content.families.floors
	var reached = themes.filter(func(theme): return theme.id in Run.profile.floors).size()
	text("%d / %d floors reached  ·  A run climbs %d of them, from the dark below to the hearth" % [reached, themes.size(), Content.record("climbs", Run.CLIMB).bands.size()], Vector2(66, 184), 19, MUTED)
	for slot in FLOOR_PAGE_SIZE:
		var index = journal_page * FLOOR_PAGE_SIZE + slot
		if index >= themes.size(): break
		var theme: Dictionary = themes[index]
		var rect = floor_rect(slot)
		var x = rect.position.x
		var y = rect.position.y
		var known: bool = theme.id in Run.profile.floors
		text(theme.name if known else "An unknown floor", Vector2(x + 26, y + 38), 21, GOLD if known else MUTED, bold)
		right_text(BAND_LABELS.get(theme.band, ""), Vector2(x + 540, y + 36), 12, Color(GOLD, .8), bold)
		if not known:
			draw_multiline_string(body, Vector2(x + 26, y + 72), "Not yet reached. Somewhere in the tower, %s." % BAND_LABELS.get(theme.band, "").to_lower(), HORIZONTAL_ALIGNMENT_LEFT, 512, 16, 2, MUTED)
			continue
		draw_multiline_string(body, Vector2(x + 26, y + 66), theme.epigraph, HORIZONTAL_ALIGNMENT_LEFT, 512, 17, 2, INK)
		draw_multiline_string(body, Vector2(x + 26, y + 112), theme.lore, HORIZONTAL_ALIGNMENT_LEFT, 512, 14, 3, MUTED)
		text("Kept by " + str(theme.boss.name).capitalize(), Vector2(x + 26, y + 176), 13, Color("efbd9f"), bold)

func draw_gallery() -> void:
	text("The gallery we keep", Vector2(64, 146), 40, INK, heading)
	var progress = Collection.progress()
	var reward = "Paint Sprayer unlocked" if "paint_sprayer" in Run.profile.unlocks else "Find all twelve to unlock the Paint Sprayer"
	text("%d / %d classics found  ·  %s" % [progress.x, progress.y, reward], Vector2(66, 184), 19, MUTED)
	var required = gallery_ids()
	for i in required.size():
		var rect = gallery_rect(i)
		var painting: Dictionary = Content.record("paintings", required[i])
		var found = Collection.seen(painting.id)
		var image_box = Rect2(rect.position + Vector2(14, 14), Vector2(152, 112))
		if found:
			var texture = PaintingLibrary.wall_texture(painting.id)
			var size = PaintingLibrary.fit(float(painting.aspect), image_box.size)
			var placed = Rect2(image_box.get_center() - size / 2, size)
			draw_rect(placed.grow(3), Color("6d5232"))
			if texture: draw_texture_rect(texture, placed, false)
			else: draw_rect(placed, Color("5c5348"))
			draw_multiline_string(bold, Vector2(rect.position.x + 10, rect.position.y + 148), painting.title, HORIZONTAL_ALIGNMENT_CENTER, 160, 15, 2, INK)
			draw_string(body, Vector2(rect.position.x + 10, rect.end.y - 10), painting.artist, HORIZONTAL_ALIGNMENT_CENTER, 160, 13, MUTED)
		else:
			draw_rect(image_box, Color(.06, .08, .07, .7))
			diamond(image_box.get_center(), 16, Color(EDGE, .6), false)
			centered("?", image_box.get_center().x, image_box.get_center().y + 8, 20, MUTED, heading)
			centered("Undiscovered", rect.get_center().x, rect.position.y + 160, 15, MUTED)

func draw_painting() -> void:
	var painting: Dictionary = Content.record("paintings", painting_id)
	if painting.is_empty():
		return
	var area = Rect2(116, 76, 660, 560)
	var size = PaintingLibrary.fit(float(painting.aspect), area.size)
	var image = Rect2(area.get_center() - size / 2, size)
	draw_rect(image.grow(10), Color("6d5232"))
	draw_rect(image.grow(4), Color("2e2a24"))
	if painting_texture:
		draw_texture_rect(painting_texture, image, false)
	else:
		draw_rect(image, Color("4d463e"))
		centered("Reproduction awaiting import", image.get_center().x, image.get_center().y - 8, 20, INK, bold)
		draw_multiline_string(body, Vector2(image.position.x + 16, image.get_center().y + 22), "The approved image is fetched with tools/import_paintings.py and bundled with the game.",
			HORIZONTAL_ALIGNMENT_CENTER, image.size.x - 32, 15, 3, MUTED)
	var x = 812.0
	draw_multiline_string(heading, Vector2(x, 112), painting.title, HORIZONTAL_ALIGNMENT_LEFT, 360, 30, 2, INK)
	text("%s · %s" % [painting.artist, painting.date], Vector2(x, 186), 18, GOLD, bold)
	draw_multiline_string(body, Vector2(x, 214), painting.medium, HORIZONTAL_ALIGNMENT_LEFT, 360, 16, 2, MUTED)
	draw_multiline_string(body, Vector2(x, 256), painting.holding, HORIZONTAL_ALIGNMENT_LEFT, 360, 16, 2, MUTED)
	divider(Vector2(x, 290), Vector2(x + 360, 290))
	draw_multiline_string(body, Vector2(x, 318), painting.caption, HORIZONTAL_ALIGNMENT_LEFT, 360, 17, 6, INK)
	draw_multiline_string(body, Vector2(x, 470), "Source: " + painting.source.page, HORIZONTAL_ALIGNMENT_LEFT, 360, 12, 3, MUTED)
	draw_multiline_string(body, Vector2(x, 516), painting.rights, HORIZONTAL_ALIGNMENT_LEFT, 360, 12, 3, MUTED)
	var progress = Collection.progress()
	text("Twelve Classics  ·  %d / %d" % [progress.x, progress.y], Vector2(x, 584), 15, GOLD, bold)
	if painting_unlock != "":
		centered("%s unlocked" % painting_unlock, area.get_center().x, 668, 20, GOLD, heading)

func draw_end() -> void:
	hearth_emblem(Vector2(640, 156), 22)
	centered("The hearth is yours." if mode == "won" else "A light goes out.", 640, 240, 38, INK, heading)
	centered("You carried a little warmth all the way home." if mode == "won" else "There is always another little spark.", 640, 284, 19, MUTED)
	centered("Floor %d of %d  ·  %d rooms  ·  %d foes" % [mini(Run.floor_number, Run.climb_length()), Run.climb_length(), Run.cleared, Run.kills], 640, 343, 22, GOLD)
	centered("%d relics  ·  %d:%02d  ·  seed %d" % [Run.inventory.size(), int(Run.elapsed) / 60, int(Run.elapsed) % 60, Run.seed_value], 640, 383, 18, MUTED)
	var harm: String = str(game.get("last_harm")) if game.get("last_harm") != null else ""
	if mode == "dead" and harm != "":
		centered("Felled by %s" % (harm.left(1).to_lower() + harm.substr(1) if not harm.begins_with("The ") else harm), 640, 425, 19, Color("efbd9f"), bold)
	else:
		centered("Your next combination is still out there.", 640, 425, 17, MUTED)
