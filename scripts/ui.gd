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
	"bomb": {"center": Vector2(1032, 486), "radius": 38.0}}
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
const REWARD_WIDTH := 340.0
const REWARD_GAP := 26.0
const SETTINGS_PAGES := [["display", "Display"], ["graphics", "Graphics"], ["controls", "Sound & Controls"]]
const SETTINGS_NOTES := {"display": "Resolution scales only the dungeon; text and controls stay sharp. Your display or device can still cap the frame rate.",
	"graphics": "Detail changes decoration and cosmetic effects only. Walls, furniture collision, loot and combat stay identical.",
	"controls": "Touch controls show the on-screen sticks and action buttons on any device."}
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
var toast_text = ""
var toast_detail = ""
var toast_color = GOLD
var toast_time = 0.0
var floating_numbers: Array[Dictionary] = []
var left_touch = -1
var right_touch = -1
var left_origin = Vector2(140, 574)
var right_origin = Vector2(1112, 574)
var left_vector = Vector2.ZERO
var right_vector = Vector2.ZERO
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
	if widened and game and content and mode in ["play", "menu"]: show_screen(mode)
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
	return 0.0 if mode in ["play", "menu"] else widen() / 2.0

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
	for child in content.get_children():
		if child is CanvasItem: child.hide()
		child.queue_free()
	for child in surface_layer.get_children():
		child.hide()
		child.queue_free()
	surfaces.clear()
	toast_surface = null
	interaction_surface = null
	boss_surface = null
	backdrop.color = Color(.025, .035, .035, .74) if mode not in ["play", "menu"] else Color(0, 0, 0, 0)
	place_layers()
	build_surfaces()
	seed_field = null
	match mode:
		"menu": build_menu()
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
		"map":
			button("← Back", Rect2(396, 590, 488, 58), func(): close_subscreen())
		"pause":
			button("Continue the journey", Rect2(430, 280, 420, 62), func(): game.resume_game(), true)
			button("Journal", Rect2(430, 358, 420, 58), func(): open_journal("pause"))
			button("Settings", Rect2(430, 432, 420, 58), func(): open_settings("pause"))
			button("Return to title", Rect2(430, 506, 420, 58), func(): game.return_to_title())
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
		"journal": build_journal()
		"painting": button("← Back", Rect2(812, 598, 360, 58), func(): close_painting())
		"settings": build_settings()
		"dead", "won":
			button("One more little light", Rect2(430, 457, 420, 62), func():
				reforge()
				game.start_run(starter_weapon().id, menu_seed, false), true)
			button("Return to title", Rect2(430, 535, 420, 58), func(): game.return_to_title())
	sync_lighting()
	update_surface_visibility()
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
	return maxi(1, ceili(float(Content.items.size()) / JOURNAL_PAGE_SIZE))

func floor_rect(slot: int) -> Rect2:
	return Rect2(64 + (slot % 2) * 588, 212 + (slot / 2) * 206, 564, 190)

func change_journal_page(step: int) -> void:
	journal_page = clampi(journal_page + step, 0, journal_page_count() - 1)
	show_screen("journal")

func build_surfaces() -> void:
	match mode:
		"menu":
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
		"painting": make_surface(Rect2(80, 40, 1120, 640))
		"journal" when journal_tab == "floors":
			for slot in FLOOR_PAGE_SIZE:
				var index = journal_page * FLOOR_PAGE_SIZE + slot
				if index >= Content.families.floors.size(): break
				make_surface(floor_rect(slot), PANEL, GOLD if Content.families.floors[index].id in Run.profile.floors else EDGE)
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
	if is_instance_valid(game.room):
		for lamp in game.room.lamps:
			if lighting_lamps.size() == 4: break
			if not is_instance_valid(lamp): continue
			var screen = game.camera.unproject_position(lamp.global_position)
			var range_edge = game.camera.unproject_position(lamp.global_position + game.camera.global_basis.x * lamp.omni_range)
			var point = local_point(screen)
			lighting_lamps.append(Vector4(point.x, point.y, screen.distance_to(range_edge) / scale_value, lamp.light_energy if lamp.is_visible_in_tree() else 0.0))
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
	button("New weapons ↻", Rect2(270, 388, 212, 56), func():
		reforge()
		seed_field.text = ""
		seed_field.placeholder_text = "Seed %d" % menu_seed
		Audio.play_sound("coin", .9)
		queue_redraw())
	button("Begin a run   →", Rect2(64, 458, 418, 60), func(): game.start_run(starter_weapon().id, chosen_seed(), false), true)
	if Run.has_save():
		button("Continue saved run", Rect2(64, 530, 418, 56), func(): game.continue_run())
		button("Today’s seed", Rect2(64, 598, 201, 54), func(): game.start_run(starter_weapon(Run.daily_seed()).id, Run.daily_seed(), true))
		button("Journal", Rect2(281, 598, 201, 54), func(): open_journal("menu"))
	else:
		button("Today’s seed", Rect2(64, 536, 201, 56), func(): game.start_run(starter_weapon(Run.daily_seed()).id, Run.daily_seed(), true))
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
			var tag = "%s · %s" % [str(weapon.element).to_upper(), str(weapon.pattern).to_upper()] if forged else "NEW FIGHTING STYLE"
			return {"name": weapon.name, "description": weapon.description, "color": Color(weapon.color),
				"label": "DARK-FORGED WEAPON" if int(weapon.get("tier", 0)) > 0 else "WEAPON", "tag": tag, "take": "Equip weapon", "buy": "%d coins · equip"}
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
		var affordable = (not shop or Run.coins >= price) and (not dark or (Run.can_pay_life(price) and not offer.get("sold", false)))
		var label: String = info.take if not shop else info.buy % price
		if dark: label = "Taken" if offer.get("sold", false) else "Give %s" % life_text(price)
		var control = button(label, Rect2(rect.position.x + 24, 478, REWARD_WIDTH - 48, 60), func(): game.choose_offer(i), affordable)
		control.disabled = not affordable
		if not affordable: control.get_meta("surface").modulate = Color(.7, .7, .65)
	button("Keep exploring", Rect2(460, 596, 360, 58), func(): game.close_reward())

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
	if journal_tab in ["relics", "floors"]:
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

func build_settings() -> void:
	for i in SETTINGS_PAGES.size():
		var page: Array = SETTINGS_PAGES[i]
		button(page[1], Rect2(330 + i * 210, 154, 200, 56), func(): open_settings_page(page[0]), page[0] == settings_page)
	var rows = settings_rows(settings_page)
	for i in rows.size():
		setting_row(Rect2(330, 228 + i * 68, 620, 56), rows[i])
	button("← Back", Rect2(396, 572, 488, 58), func(): close_subscreen())

func open_settings_page(page: String) -> void:
	settings_page = page
	show_screen("settings")

func on_off(key: String) -> String:
	return "On" if Settings.values[key] else "Off"

## [setting key, label, value text, interactive]
func settings_rows(page: String) -> Array:
	match page:
		"display":
			var pixels = Settings.render_pixels()
			var vsync = ["vsync", "VSync", on_off("vsync"), true]
			if not Settings.vsync_supported():
				vsync = ["vsync", "VSync", "System controlled", false]
			elif Settings.effective_vsync() != on_off("vsync").to_lower():
				vsync[2] += " · driver " + Settings.effective_vsync().capitalize()
			return [["render_scale", "Render resolution", "%d%%  ·  %d×%d" % [roundi(Settings.values.render_scale * 100), pixels.x, pixels.y], true],
				["fps_limit", "FPS limit", "Unlimited" if Settings.values.fps_limit == 0 else str(Settings.values.fps_limit), true],
				vsync, ["show_fps", "Show FPS", on_off("show_fps"), true]]
		"graphics":
			return [["effects_detail", "Effects detail", Settings.values.effects_detail.capitalize(), true],
				["small_details", "Small details", Settings.values.small_details.capitalize(), true],
				["shadows", "Lantern shadows", on_off("shadows"), true]]
	return [["sound", "Sound effects", on_off("sound"), true], ["music", "Ambient music", on_off("music"), true],
		["shake", "Camera shake", on_off("shake"), true], ["touch", "Touch controls", on_off("touch"), true]]

func setting_row(rect: Rect2, row: Array) -> SettingRow:
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
	control.pressed.connect(func(): Audio.play_sound("coin", .7); Settings.cycle(key); show_screen("settings"))
	content.add_child(control)
	return control

func open_map(back: String) -> void:
	previous_mode = back
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

func _process(delta: float) -> void:
	elapsed_ui += delta
	fps_frames += 1
	fps_time += delta
	if fps_time >= .5:
		fps_value = fps_frames / fps_time
		fps_frames = 0
		fps_time = 0.0
	toast_time = maxf(0, toast_time - delta)
	for cell in scribbles.keys():
		if elapsed_ui - scribbles[cell] > SCRIBBLE_TIME: scribbles.erase(cell)
	for number in floating_numbers:
		number.age += delta
	floating_numbers = floating_numbers.filter(func(n): return n.age < .65)
	sync_lighting()
	update_surface_visibility()
	queue_redraw()

func _input(event: InputEvent) -> void:
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
				trigger_action(action)
				get_viewport().set_input_as_handled()
			elif INTERACTION_RECT.has_point(from_middle(p)) and game.interaction_text != "":
				game.interact()
				get_viewport().set_input_as_handled()
			elif p.y > 330 and p.x < 550 and left_touch == -1:
				left_touch = event.index
				left_origin = Vector2(clampf(p.x, 90, 420), clampf(p.y, 400, 620))
				left_vector = (p - left_origin).limit_length(58) / 58.0
				get_viewport().set_input_as_handled()
			elif right.y > 330 and right.x > 730 and right_touch == -1:
				right_touch = event.index
				right_origin = Vector2(clampf(right.x, 810, 1190), clampf(right.y, 400, 620))
				right_vector = (right - right_origin).limit_length(58) / 58.0
				get_viewport().set_input_as_handled()
		else:
			if event.index == left_touch:
				left_touch = -1
				left_vector = Vector2.ZERO
				get_viewport().set_input_as_handled()
			if event.index == right_touch:
				right_touch = -1
				right_vector = Vector2.ZERO
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var p = local_point(event.position)
		if event.index == left_touch:
			left_vector = (p - left_origin).limit_length(58) / 58.0
			get_viewport().set_input_as_handled()
		if event.index == right_touch:
			right_vector = (from_right(p) - right_origin).limit_length(58) / 58.0
			get_viewport().set_input_as_handled()

func touch_hud_visible() -> bool:
	return touch_used or Settings.values.touch or is_touch_platform()

func action_at(point: Vector2) -> String:
	for action in ACTION_BUTTONS:
		if point.distance_to(ACTION_BUTTONS[action].center) < ACTION_BUTTONS[action].radius:
			return action
	return ""

func trigger_action(action: String) -> void:
	match action:
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
		"play": draw_hud()
		"pause":
			hearth_emblem(Vector2(640, 144), 12)
			centered("Catch your breath", 640, 204, 34, INK, heading)
			centered("Even a little flame needs a moment.", 640, 245, 18, MUTED)
			centered("Your last safe room is saved automatically.", 640, 604, 16, MUTED)
		"secret":
			hearth_emblem(Vector2(640, 177), 11)
			centered("A whispered wish", 640, 237, 34, INK, heading)
			centered("Some little sparks know a secret.", 640, 278, 18, MUTED)
			centered(secret_feedback, 640, 401, 17, Color("efbd9f"))
		"reward": draw_rewards()
		"settings":
			hearth_emblem(Vector2(640, 76), 11)
			centered("Make yourself at home", 640, 134, 32, INK, heading)
			draw_multiline_string(body, Vector2(340, 516), SETTINGS_NOTES[settings_page], HORIZONTAL_ALIGNMENT_CENTER, 600, 17, 2, MUTED)
		"journal":
			match journal_tab:
				"relics": draw_journal()
				"floors": draw_floors()
				_: draw_gallery()
		"painting": draw_painting()
		"map": draw_full_map()
		"dead", "won": draw_end()
	if mode == "play":
		anchor(0)
		for number in floating_numbers:
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
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func hearth_emblem(at: Vector2, radius: float) -> void:
	draw_arc(at, radius + 8, 0, TAU, 32, Color(GOLD, .27), 1.2, true)
	diamond(at + Vector2(0, 1), radius, Color("292e28"))
	diamond(at, radius * .8, GOLD)
	diamond(at + Vector2(0, 2), radius * .34, Color("fff0c6"))

func divider(from: Vector2, to: Vector2) -> void:
	draw_line(from + Vector2(0, 1), to + Vector2(0, 1), Color(.03, .04, .03, .8), 1)
	draw_line(from, to, Color(EDGE, .55), 1)

func draw_menu() -> void:
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
	text("%d stackable relics  ·  new weapons every seed  ·  %d floors" % [Content.items.size(), Content.record("climbs", Run.CLIMB).bands.size()], Vector2(789, 617), 18, INK)
	text("Strange combinations. One more little light.", Vector2(789, 650), 17, MUTED)

func draw_hud() -> void:
	anchor(0)
	draw_hud_left()
	anchor(widen() / 2.0)
	draw_hud_middle()
	anchor(widen())
	draw_hud_right()

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
	if not touch_hud_visible():
		text("WASD move · Mouse fire · Space dash · F item · B bomb", Vector2(28, 668), 15, MUTED)
	text("SEED %d" % Run.seed_value, Vector2(28, 697), 13, MUTED)
	if touch_hud_visible():
		draw_stick(left_origin, left_vector, "MOVE", left_touch >= 0)

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
	if game.interaction_text != "":
		centered(game.interaction_text, 640, 596, 21, GOLD, bold)
		centered("Tap to interact  ·  E / A", 640, 624, 16, MUTED)

func draw_hud_right() -> void:
	draw_minimap()
	text("%d:%02d" % [int(Run.elapsed) / 60, int(Run.elapsed) % 60], Vector2(1196, 697), 15, MUTED)
	if not touch_hud_visible(): return
	draw_stick(right_origin, right_vector, "AIM + FIRE", right_touch >= 0)
	var ready: bool = game.player and game.player.dash_cooldown <= 0
	draw_action_ring("dash", 1.0 if ready else 0.0, GOLD if ready else MUTED)
	centered("DASH" if ready else "%.1f" % game.player.dash_cooldown, DASH_CENTER.x, DASH_CENTER.y + 7, 18, GOLD if ready else MUTED, bold)
	draw_active_button()
	var bomb: Dictionary = ACTION_BUTTONS.bomb
	draw_action_ring("bomb", 1.0 if Run.bombs > 0 else 0.0, GOLD if Run.bombs > 0 else MUTED)
	resource_icon("bomb", bomb.center + Vector2(0, -8))
	centered("×%d" % Run.bombs, bomb.center.x, bomb.center.y + 22, 15, INK if Run.bombs > 0 else MUTED, bold)

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
	var button_region: Dictionary = ACTION_BUTTONS[action]
	var center: Vector2 = button_region.center
	var radius: float = button_region.radius
	draw_circle(center + Vector2(0, 4), radius, Color(.02, .03, .03, .7))
	draw_circle(center, radius, Color(.18, .21, .18, .88))
	draw_arc(center, radius - 2, 0, TAU, 48, Color(MUTED, .45), 2, true)
	if fraction > 0:
		draw_arc(center, radius - 2, -PI / 2, -PI / 2 + TAU * fraction, 48, color, 2.5, true)

## Item icon, cooldown ring and a seconds readout while recharging.
func draw_active_button() -> void:
	var center: Vector2 = ACTION_BUTTONS.active.center
	var state = active_state()
	if state.is_empty():
		draw_action_ring("active", 0.0, MUTED)
		centered("ITEM", center.x, center.y + 6, 15, MUTED, bold)
		return
	var ready = state.remaining <= 0
	draw_action_ring("active", state.fraction, GOLD if ready else Color(state.definition.color))
	diamond(center + Vector2(0, -6), 13, Color(state.definition.color), ready)
	centered("USE" if ready else "%d" % ceili(state.remaining), center.x, center.y + 25, 15, GOLD if ready else INK, bold)

func draw_stick(at: Vector2, value: Vector2, label: String, active_touch: bool) -> void:
	draw_circle(at + Vector2(0, 4), 66, Color(.02, .03, .025, .35))
	draw_circle(at, 66, Color(.16, .19, .16, .48))
	draw_arc(at, 66, 0, TAU, 48, Color(GOLD, .55 if active_touch else .3), 2, true)
	draw_arc(at, 59, 0, TAU, 48, Color(.06, .08, .065, .6), 2, true)
	draw_circle(at + value * 48 + Vector2(0, 3), 28, Color(.02, .03, .02, .45))
	draw_circle(at + value * 48, 28, Color(.65, .57, .39, .7 if active_touch else .4))
	draw_arc(at + value * 48, 27, PI, TAU, 24, Color(GOLD, .65), 2, true)
	centered(label, at.x, at.y + 91, 14, Color(INK, .8), bold)

func draw_minimap() -> void:
	var cells = FloorGenerator.room_cells(Run.rooms[Run.current_room])
	var focus = Vector2.ZERO
	for cell in cells: focus += Vector2(cell)
	draw_floor_map(MINIMAP_AREA, focus / cells.size(), 22.0)
	if not touch_hud_visible():
		right_text("M", MINIMAP_RECT.end - Vector2(20, 11), 12, MUTED)

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
func draw_floor_map(area: Rect2, focus: Vector2, cell_size: float) -> void:
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
			draw_line(start, end, Color("9d9878"), maxf(2.0, cell_size * .12), true)
	for id in known:
		var data: Dictionary = Run.rooms[id]
		var cells = FloorGenerator.room_cells(data)
		var color = map_color(id)
		for cell in cells:
			var low = Vector2(inset if not cells.has(cell + Vector2i.LEFT) else 0.0, inset if not cells.has(cell + Vector2i.UP) else 0.0)
			var high = Vector2(inset if not cells.has(cell + Vector2i.RIGHT) else 0.0, inset if not cells.has(cell + Vector2i.DOWN) else 0.0)
			var rect = Rect2(origin + (Vector2(cell) - Vector2(.5, .5)) * cell_size + low, Vector2.ONE * cell_size - low - high)
			if Run.is_seen(data, cell):
				var shadow = Rect2(rect.position + Vector2(0, 2), rect.size).intersection(area)
				if shadow.has_area(): draw_rect(shadow, Color("262e28"))
				draw_scribbled(rect, area, cell, color, cell_size)
			else:
				# Known but not yet walked: a faint pencil outline, merged across
				# the room's own unexplored seams.
				for direction in RoomGeometry.DIRECTIONS:
					var next: Vector2i = cell + direction
					if cells.has(next) and not Run.is_seen(data, next): continue
					var edge = ghost_edge(rect, direction)
					if area.has_point(edge[0]) and area.has_point(edge[1]):
						draw_dashed_line(edge[0], edge[1], Color(color, .5), maxf(1.0, cell_size * .05), maxf(2.5, cell_size * .12), true, true)
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
						draw_line(start, end, GOLD, 1.5, true)

func scribble(cell: Vector2i) -> void:
	scribbles[cell] = elapsed_ui

## How far a cell's scribble has been drawn (eased); old cells are complete.
func scribble_progress(cell: Vector2i) -> float:
	if not scribbles.has(cell): return 1.0
	var t = clampf((elapsed_ui - scribbles[cell]) / SCRIBBLE_TIME, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 2.0)

## An explored cell: a soft wash under a crayon's zig-zag, drawn only as far
## as its scribble has got. The trail is all there is; no crayon is shown.
func draw_scribbled(rect: Rect2, area: Rect2, cell: Vector2i, color: Color, cell_size: float) -> void:
	var shown = rect.intersection(area)
	if not shown.has_area(): return
	var progress = scribble_progress(cell)
	draw_rect(shown, Color(color.darkened(.5), .45 * progress))
	var inner = rect.grow(-cell_size * .08)
	var points = scribble_path(inner, cell, Run.floor_number)
	for i in points.size(): points[i] = points[i].clamp(area.position, area.end)
	var drawn = partial_path(points, progress)
	# About a third of their spacing, so each line of the zig-zag stands apart.
	if drawn.size() >= 2: draw_polyline(drawn, Color(color, .85), scribble_spacing(inner) * .37, true)

static func ghost_edge(rect: Rect2, direction: Vector2i) -> Array:
	match direction:
		Vector2i.UP: return [rect.position, Vector2(rect.end.x, rect.position.y)]
		Vector2i.DOWN: return [Vector2(rect.position.x, rect.end.y), rect.end]
		Vector2i.LEFT: return [rect.position, Vector2(rect.position.x, rect.end.y)]
	return [Vector2(rect.end.x, rect.position.y), rect.end]

## Strokes sit a fixed few pixels apart, so the minimap and the full map
## scribble with the same density.
static func scribble_spacing(rect: Rect2) -> float:
	return rect.size.x / clampi(roundi(rect.size.x / 3.2), 3, 14)

## A crayon's zig-zag fill: one run of strokes across the cell, a little loose
## at the turns, the whole scribble leaning about 22° the way a hand's does,
## its turns rising to the right. A turn that would fall outside the cell
## slides in along its stroke to the edge. Always the same per cell.
static func scribble_path(rect: Rect2, cell: Vector2i, floor_number: int) -> PackedVector2Array:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash([cell.x, cell.y, floor_number])
	var tilt = deg_to_rad(22.0 + rng.randf_range(-3.0, 3.0))
	# Along the line of turns, and down a stroke.
	var along = Vector2(cos(tilt), -sin(tilt))
	var down = Vector2(sin(tilt), cos(tilt))
	var half = rect.size * .5
	# Far enough along to reach every corner of the cell.
	var reach = half.x * along.x + half.y * down.x
	var strokes = maxi(roundi(reach * 2.0 / scribble_spacing(rect)), 2)
	var step = reach * 2.0 / strokes
	var points = PackedVector2Array()
	for i in strokes + 1:
		var u = -reach + i * step + rng.randf_range(-.15, .15) * step
		var side = -1.0 if i % 2 == 0 else 1.0
		var v = side * (half.y - rng.randf_range(0.0, .06) * rect.size.y)
		# Swing round in a short hook rather than a sharp point.
		var dip = -side * rect.size.y * .07
		for hook in [Vector2(u - step * .3, v + dip), Vector2(u, v), Vector2(u + step * .3, v + dip)]:
			points.append(scribble_point(rect, along, down, clampf(hook.x, -reach, reach), hook.y))
	return points

## A point of the leaning scribble, `u` along its turns and `v` down its
## strokes from the cell's centre, kept inside the cell along the stroke.
static func scribble_point(rect: Rect2, along: Vector2, down: Vector2, u: float, v: float) -> Vector2:
	var half = rect.size * .5
	var low = maxf((-half.x - u * along.x) / down.x, (-half.y - u * along.y) / down.y)
	var high = minf((half.x - u * along.x) / down.x, (half.y - u * along.y) / down.y)
	var point = rect.get_center() + along * u + down * clampf(v, low, maxf(low, high))
	return point.clamp(rect.position, rect.end)

## The first `progress` of a path's length, ending part-way along a segment.
static func partial_path(points: PackedVector2Array, progress: float) -> PackedVector2Array:
	if progress >= 1.0 or points.size() < 2: return points
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

func draw_full_map() -> void:
	hearth_emblem(Vector2(640, 96), 11)
	centered("The way home", 640, 140, 32, INK, heading)
	var known = map_rooms()
	var low = Vector2(INF, INF)
	var high = -low
	for id in known:
		for cell in FloorGenerator.room_cells(Run.rooms[id]):
			low = Vector2(minf(low.x, cell.x), minf(low.y, cell.y))
			high = Vector2(maxf(high.x, cell.x), maxf(high.y, cell.y))
	var span = high - low + Vector2.ONE
	var cell_size = minf(48.0, minf(FULL_MAP_AREA.size.x / (span.x + 1), FULL_MAP_AREA.size.y / (span.y + 1)))
	draw_floor_map(FULL_MAP_AREA, (low + high) / 2.0, cell_size)
	var main_rooms = Run.rooms.values().filter(func(room): return not room.get("secret", false))
	var twist_name = str(Content.record("twists", Run.twist_id()).get("name", ""))
	centered("%s  ·  Floor %d of %d%s  ·  %d of %d rooms visited  ·  Outlined: you are here" % [Run.theme().name, Run.floor_number, Run.climb_length(),
		"  ·  " + twist_name if twist_name != "" else "", main_rooms.filter(func(room): return room.visited).size(), main_rooms.size()], 640, 578, 17, MUTED)

## Half-hearts of maximum health, said in hearts.
static func life_text(half_hearts: int) -> String:
	var whole = half_hearts / 2
	var half = "½" if half_hearts % 2 == 1 else ""
	if half_hearts <= 0: return "nothing"
	if whole == 0: return "½ heart"
	return "%d%s heart%s" % [whole, half, "" if whole == 1 and half == "" else "s"]

func draw_rewards() -> void:
	hearth_emblem(Vector2(640, 61), 12)
	if dark:
		centered("The dark merchant", 640, 123, 38, Color("d8c0f0"), heading)
		centered("It takes maximum health, for the rest of the run. You have %s to give." % life_text(maxi(0, int(Run.stats.max_hp - Run.LIFE_FLOOR))), 640, 165, 20, MUTED)
	else:
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
	centered("What you give stays given until the run ends." if dark else "Relics stack. Find something beautifully strange.", 640, 692, 17, MUTED)

func draw_journal() -> void:
	text("The things we carry", Vector2(64, 146), 40, INK, heading)
	text("%d relics to find. Every effect stacks with your weapon and other relics." % Content.items.size(), Vector2(66, 184), 19, MUTED)
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
	centered("Your next combination is still out there.", 640, 425, 17, MUTED)
