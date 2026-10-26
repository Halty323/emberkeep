class_name GameInterface
extends Control
const INK := Color("f5ead2")
const MUTED := Color("c4bda7")
const GOLD := Color("f1cc8a")
const PANEL := Color("44463e")
const EDGE := Color("9d8861")
const INTERACTION_RECT := Rect2(410, 564, 460, 78)
const DASH_CENTER := Vector2(973, 610)
const DASH_RADIUS := 48.0
const JOURNAL_PAGE_SIZE := 6
const TOAST_RECT := Rect2(400, 136, 480, 92)
const REWARD_WIDTH := 340.0
const REWARD_GAP := 26.0
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
var selected_seed = ""
var seed_field: LineEdit
var offers: Array = []
var shop = false
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
var journal_page = 0
var elapsed_ui = 0.0
var secret_taps = 0
var secret_key_buffer = ""
var secret_field: LineEdit
var secret_feedback = ""

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

func resize() -> void:
	var size_value = get_viewport_rect().size
	var safe_rect = Rect2(Vector2.ZERO, size_value)
	if OS.has_feature("android"):
		var safe_screen = Rect2(DisplayServer.get_display_safe_area())
		var window_size = Vector2(DisplayServer.window_get_size())
		if window_size.x > 0 and window_size.y > 0 and safe_screen.has_area():
			var ratio = size_value / window_size
			var candidate = Rect2(safe_screen.position * ratio, safe_screen.size * ratio)
			safe_rect = safe_rect.intersection(candidate)
			if not safe_rect.has_area(): safe_rect = Rect2(Vector2.ZERO, size_value)
	scale_value = minf(safe_rect.size.x / 1280.0, safe_rect.size.y / 720.0)
	offset = safe_rect.position + (safe_rect.size - Vector2(1280, 720) * scale_value) / 2.0
	if content:
		content.position = offset
		content.scale = Vector2.ONE * scale_value
		content.size = Vector2(1280, 720)
	if surface_layer:
		surface_layer.position = offset
		surface_layer.scale = Vector2.ONE * scale_value
		surface_layer.size = Vector2(1280, 720)
	queue_redraw()

func local_point(at: Vector2) -> Vector2:
	return (at - offset) / scale_value

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
	build_surfaces()
	seed_field = null
	match mode:
		"menu": build_menu()
		"play":
			button("II", Rect2(1180, 24, 76, 58), func(): game.pause_game(), false)
			button("RELICS", Rect2(1012, 24, 154, 58), func(): open_journal("pause"), false)
		"pause":
			button("Continue the journey", Rect2(430, 280, 420, 62), func(): game.resume_game(), true)
			button("Relic journal", Rect2(430, 358, 420, 58), func(): open_journal("pause"))
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
		"settings": build_settings()
		"dead", "won":
			button("One more little light", Rect2(430, 457, 420, 62), func(): game.start_run(Content.weapons[starter_index].id, 0, false), true)
			button("Return to title", Rect2(430, 535, 420, 58), func(): game.return_to_title())
	sync_lighting()
	update_surface_visibility()
	queue_redraw()

func make_surface(rect: Rect2, background := PANEL, accent := EDGE, compact := false) -> DungeonUISurface:
	var surface = DungeonUISurface.new()
	surface_layer.add_child(surface)
	surface.configure(rect, background, accent, compact)
	surfaces.append(surface)
	return surface

func reward_rect(index: int) -> Rect2:
	var total = offers.size() * REWARD_WIDTH + maxi(0, offers.size() - 1) * REWARD_GAP
	return Rect2((1280 - total) / 2.0 + index * (REWARD_WIDTH + REWARD_GAP), 196, REWARD_WIDTH, 366)

func journal_rect(slot: int) -> Rect2:
	return Rect2(64 + (slot % 2) * 588, 212 + (slot / 2) * 126, 564, 110)

func journal_page_count() -> int:
	return maxi(1, ceili(float(Content.items.size()) / JOURNAL_PAGE_SIZE))

func change_journal_page(step: int) -> void:
	journal_page = clampi(journal_page + step, 0, journal_page_count() - 1)
	show_screen("journal")

func build_surfaces() -> void:
	match mode:
		"menu":
			make_surface(Rect2(36, 28, 474, 660))
			make_surface(Rect2(762, 530, 472, 156))
		"play":
			make_surface(Rect2(24, 24, 370, 150))
			make_surface(Rect2(424, 24, 420, 88), Color("3d423c"))
			make_surface(Rect2(1012, 100, 244, 192), Color("363c37"))
			toast_surface = make_surface(TOAST_RECT, Color("45483b"), GOLD)
			interaction_surface = make_surface(INTERACTION_RECT, PANEL, GOLD)
			boss_surface = make_surface(Rect2(430, 119, 420, 12), Color("2e3430"), Color("bb8969"), true)
		"pause": make_surface(Rect2(376, 108, 528, 520))
		"secret": make_surface(Rect2(376, 140, 528, 448))
		"settings": make_surface(Rect2(350, 72, 580, 588))
		"reward":
			for i in offers.size():
				var offer: Dictionary = offers[i]
				var is_weapon: bool = offer.get("kind", "item") == "weapon"
				var item: Dictionary = Content.weapon_by_id[offer.id] if is_weapon else Content.item_by_id[offer.id]
				make_surface(reward_rect(i), PANEL, Color(item.color) if is_weapon else Content.RARITY_COLORS[item.rarity])
		"journal":
			for slot in JOURNAL_PAGE_SIZE:
				var index = journal_page * JOURNAL_PAGE_SIZE + slot
				if index >= Content.items.size(): break
				var item: Dictionary = Content.items[index]
				make_surface(journal_rect(slot), PANEL, Content.RARITY_COLORS[item.rarity] if item.id in Run.inventory else EDGE)
		"dead", "won": make_surface(Rect2(350, 96, 580, 540))

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
	seed_field.placeholder_text = "Random seed"
	seed_field.text = selected_seed
	seed_field.max_length = 10
	seed_field.add_theme_font_override("font", body)
	seed_field.add_theme_font_size_override("font_size", 18)
	seed_field.add_theme_color_override("font_color", MUTED)
	seed_field.add_theme_stylebox_override("normal", style(Color(.08, .11, .12, .7), EDGE))
	seed_field.add_theme_stylebox_override("focus", style(Color(.1, .13, .14, .9), GOLD))
	seed_field.text_changed.connect(func(value): selected_seed = value)
	content.add_child(seed_field)
	button("‹", Rect2(64, 278, 56, 56), func(): cycle_weapon(-1))
	button("›", Rect2(426, 278, 56, 56), func(): cycle_weapon(1))
	button("Begin a run   →", Rect2(64, 458, 418, 60), func(): game.start_run(Content.weapons[starter_index].id, seed_field.text.to_int(), false), true)
	if Run.has_save():
		button("Continue saved run", Rect2(64, 530, 418, 56), func(): game.continue_run())
		button("Today’s seed", Rect2(64, 598, 201, 54), func(): game.start_run(Content.weapons[starter_index].id, Run.daily_seed(), true))
		button("Relic journal", Rect2(281, 598, 201, 54), func(): open_journal("menu"))
	else:
		button("Today’s seed", Rect2(64, 536, 201, 56), func(): game.start_run(Content.weapons[starter_index].id, Run.daily_seed(), true))
		button("Relic journal", Rect2(281, 536, 201, 56), func(): open_journal("menu"))
	button("Settings", Rect2(1080, 32, 154, 56), func(): open_settings("menu"))

func cycle_weapon(step: int) -> void:
	starter_index = posmod(starter_index + step, Content.weapons.size())
	Audio.play_sound("coin", .75)
	queue_redraw()

func build_rewards() -> void:
	for i in offers.size():
		var offer: Dictionary = offers[i]
		var rect = reward_rect(i)
		var price = int(offer.get("price", 0))
		var affordable = not shop or Run.coins >= price
		var label = "Take this relic" if not shop else "%d coins" % price
		if offer.get("kind", "item") == "weapon":
			label = "Equip weapon" if not shop else "%d coins · equip" % price
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
	button("←", Rect2(1044, 626, 76, 58), func(): change_journal_page(-1))
	button("→", Rect2(1136, 626, 76, 58), func(): change_journal_page(1))

func open_settings(back: String) -> void:
	previous_mode = back
	show_screen("settings")

func build_settings() -> void:
	button("← Back", Rect2(396, 572, 488, 58), func(): close_subscreen())
	var options = [["sound", "Sound effects"], ["music", "Ambient music"], ["shake", "Camera shake"], ["touch", "Touch controls"], ["quality", "Lantern shadows"]]
	for i in options.size():
		var option: Array = options[i]
		button("%s     %s" % [option[1], "ON" if Run.profile[option[0]] else "OFF"], Rect2(396, 206 + i * 70, 488, 56), func():
			Run.profile[option[0]] = not Run.profile[option[0]]
			Run.save_profile()
			Audio.refresh()
			show_screen("settings"))

func close_subscreen() -> void:
	if previous_mode == "menu":
		show_screen("menu")
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

func button(label: String, rect: Rect2, callback: Callable, primary := false) -> Button:
	var control = Button.new()
	control.text = label
	control.position = rect.position
	control.size = rect.size
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
	toast_time = maxf(0, toast_time - delta)
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
			secret_key_buffer = (secret_key_buffer + String.chr(event.unicode).to_upper()).right(Run.ALL_RELICS_CODE.length())
			if secret_key_buffer == Run.ALL_RELICS_CODE:
				submit_secret_code(secret_key_buffer)
				get_viewport().set_input_as_handled()
		return
	if mode != "play":
		return
	if event is InputEventScreenTouch:
		touch_used = true
		var p = local_point(event.position)
		if event.pressed:
			if p.distance_to(DASH_CENTER) < DASH_RADIUS:
				game.request_dash = true
				get_viewport().set_input_as_handled()
			elif INTERACTION_RECT.has_point(p) and game.interaction_text != "":
				game.interact()
				get_viewport().set_input_as_handled()
			elif p.y > 330 and p.x < 550 and left_touch == -1:
				left_touch = event.index
				left_origin = Vector2(clampf(p.x, 90, 420), clampf(p.y, 400, 620))
				left_vector = (p - left_origin).limit_length(58) / 58.0
				get_viewport().set_input_as_handled()
			elif p.y > 330 and p.x > 730 and right_touch == -1:
				right_touch = event.index
				right_origin = Vector2(clampf(p.x, 810, 1190), clampf(p.y, 400, 620))
				right_vector = (p - right_origin).limit_length(58) / 58.0
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
			right_vector = (p - right_origin).limit_length(58) / 58.0
			get_viewport().set_input_as_handled()

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
	draw_set_transform(offset, 0, Vector2.ONE * scale_value)
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
			hearth_emblem(Vector2(640, 109), 11)
			centered("Make yourself at home", 640, 169, 32, INK, heading)
		"journal": draw_journal()
		"dead", "won": draw_end()
	if mode == "play":
		for number in floating_numbers:
			var c = GOLD if number.critical else INK
			c.a = minf(1, (0.65 - number.age) * 4)
			text(number.text, number.at + Vector2(0, -number.age * 65), 26 if number.critical else 21, c, bold)
		if toast_time > 0:
			centered(toast_text, 640, 168, 22, toast_color, heading)
			draw_multiline_string(body, Vector2(424, 195), toast_detail, HORIZONTAL_ALIGNMENT_CENTER, 432, 17, 2, MUTED)
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
	var weapon: Dictionary = Content.weapons[starter_index]
	centered(weapon.name, 273, 314, 23, Color(weapon.color), heading)
	draw_multiline_string(body, Vector2(65, 357), weapon.description, HORIZONTAL_ALIGNMENT_LEFT, 418, 17, 2, MUTED)
	text("Optional seed", Vector2(274, 423), 18, MUTED)
	if not Run.has_save():
		text("%d runs  ·  %d victories" % [Run.profile.runs, Run.profile.wins], Vector2(66, 632), 17, MUTED)
	text("60 RELICS TO DISCOVER", Vector2(66, 671), 14, GOLD, bold)
	hearth_emblem(Vector2(798, 566), 10)
	text("A warm place. A wild little dungeon.", Vector2(826, 574), 21, GOLD, heading)
	text("60 stackable relics  ·  10 weapons  ·  3 floors", Vector2(789, 617), 18, INK)
	text("Strange combinations. One more little light.", Vector2(789, 650), 17, MUTED)

func draw_hud() -> void:
	text("THE LITTLE LIGHT", Vector2(48, 52), 14, MUTED, bold)
	if game.player and game.player.shield > 0:
		text("%d guard" % game.player.shield, Vector2(287, 52), 15, Color("b7ddc0"), bold)
	var hearts = int(ceil(Run.stats.max_hp / 2.0))
	for i in mini(hearts, 10):
		var at = Vector2(54 + i * 29, 83)
		var fill = clampf((Run.hp - i * 2) / 2, 0, 1)
		diamond(at + Vector2(0, 2), 13, Color("252c27"))
		diamond(at, 12, Color("717061"))
		if fill > 0:
			diamond(at, 12 * (.58 if fill < 1 else 1.0), Color("f4c68c"))
			draw_line(at + Vector2(-4, -5), at + Vector2(0, -9), Color("fff0c9"), 1.3, true)
	if hearts > 10:
		text("+%d" % (hearts - 10), Vector2(340, 89), 17, GOLD)
	draw_circle(Vector2(55, 121), 8, Color("302f23"))
	draw_circle(Vector2(54, 119), 7, Color("ceab68"))
	draw_line(Vector2(54, 115), Vector2(54, 123), Color("f7dfa5"), 1.5)
	text("%02d coins" % Run.coins, Vector2(72, 126), 21, GOLD, bold)
	text(Content.weapon_by_id[Run.weapon_id].name, Vector2(48, 154), 19, INK)
	if Run.inventory.size() > 0:
		text("RELICS", Vector2(40, 203), 14, MUTED, bold)
		for i in mini(Run.inventory.size(), 10):
			var item: Dictionary = Content.item_by_id[Run.inventory[i]]
			diamond(Vector2(114 + i * 22, 197), 8, Content.RARITY_COLORS[item.rarity])
		if Run.inventory.size() > 10:
			text("+%d" % (Run.inventory.size() - 10), Vector2(342, 203), 16, GOLD)
	var floor_names = ["The Waking Cellar", "The Mosslit Halls", "The Last Hearth"]
	diamond(Vector2(454, 64), 15, Color("292f29"))
	centered(str(Run.floor_number), 454, 70, 18, GOLD, heading)
	centered(floor_names[mini(2, Run.floor_number - 1)], 652, 60, 24, INK, heading)
	var room_label: String = {"combat": "A room full of trouble", "start": "A safe little beginning", "treasure": "Something worth keeping", "shop": "The candle merchant", "rest": "A moment of warmth", "boss": "The hearth is stirring"}.get(Run.rooms[Run.current_room].type, "")
	var boss_enemy = game.get_boss()
	if boss_enemy:
		room_label = ["THE HEARTH WARDEN", "THE MOSSKEEPER", "THE LAST LIGHT"][mini(2, Run.floor_number - 1)]
	centered(room_label, 652, 88, 16, Color("efbd9f") if boss_enemy else MUTED)
	draw_minimap()
	if game.room and not game.room.open:
		var remaining = 0
		for enemy in game.enemies:
			if is_instance_valid(enemy) and enemy.alive: remaining += 1
		centered("%d little troubles remain" % remaining, 640, 693, 17, MUTED)
	else:
		centered("Doorways are open · keep exploring", 640, 693, 17, MUTED)
	if boss_enemy:
		draw_rect(Rect2(434, 122, 412 * maxf(0, boss_enemy.hp / boss_enemy.max_hp), 6), Color("d79275"))
	if game.interaction_text != "":
		centered(game.interaction_text, 640, 596, 21, GOLD, bold)
		centered("Tap to interact  ·  E / A", 640, 624, 16, MUTED)
	if touch_used or Run.profile.touch or OS.has_feature("android"):
		draw_stick(left_origin, left_vector, "MOVE", left_touch >= 0)
		draw_stick(right_origin, right_vector, "AIM + FIRE", right_touch >= 0)
		var ready: bool = game.player and game.player.dash_cooldown <= 0
		draw_circle(DASH_CENTER + Vector2(0, 4), DASH_RADIUS, Color(.02, .03, .03, .7))
		draw_circle(DASH_CENTER, DASH_RADIUS, Color(.18, .21, .18, .88))
		draw_arc(DASH_CENTER, DASH_RADIUS - 2, -PI / 2, TAU - PI / 2, 48, GOLD if ready else MUTED, 2, true)
		centered("DASH" if ready else "%.1f" % game.player.dash_cooldown, DASH_CENTER.x, DASH_CENTER.y + 7, 18, GOLD if ready else MUTED, bold)
	else:
		text("WASD move · Mouse fire · Space dash", Vector2(28, 660), 16, MUTED)
	text("SEED %d" % Run.seed_value, Vector2(28, 697), 14, MUTED)
	text("%d:%02d" % [int(Run.elapsed) / 60, int(Run.elapsed) % 60], Vector2(1182, 697), 16, MUTED)

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
	text("THE WAY HOME", Vector2(1034, 132), 14, GOLD, bold)
	text("N", Vector2(1220, 132), 13, MUTED)
	divider(Vector2(1034, 145), Vector2(1234, 145))
	var center = Vector2(1134, 213)
	var scale_map = 24.0
	var here = Run.coord(Run.current_room)
	for key in Run.rooms:
		var r: Dictionary = Run.rooms[key]
		if not r.visited and key not in Run.neighbors(Run.current_room): continue
		var p = center + Vector2(Run.coord(key) - here) * scale_map
		if absf(p.x - center.x) > 86 or absf(p.y - center.y) > 50: continue
		for neighbor in Run.neighbors(key):
			var n: Dictionary = Run.rooms[neighbor]
			if not n.visited and neighbor not in Run.neighbors(Run.current_room): continue
			var to = center + Vector2(Run.coord(neighbor) - here) * scale_map
			if absf(to.x - center.x) <= 86 and absf(to.y - center.y) <= 50:
				draw_line(p, to, Color("656752"), 2, true)
		var c = Color("9b9e82") if r.cleared else Color("626957")
		if r.type == "treasure": c = GOLD
		if r.type == "shop": c = Color("afcfaa")
		if r.type == "boss": c = Color("da9b80")
		if key == Run.current_room: c = INK
		draw_rect(Rect2(p - Vector2(7, 5), Vector2(14, 10)), Color("262e28"))
		draw_rect(Rect2(p - Vector2(6, 5), Vector2(12, 9)), c)
		if key == Run.current_room:
			draw_rect(Rect2(p - Vector2(10, 8), Vector2(20, 16)), GOLD, false, 1.5)

func draw_rewards() -> void:
	hearth_emblem(Vector2(640, 61), 12)
	centered("The candle merchant" if shop else "A small kindness", 640, 123, 38, INK, heading)
	centered("A good find is worth a few coins. You have %d." % Run.coins if shop else "Choose one. Let it change the way you play.", 640, 165, 20, MUTED)
	for i in offers.size():
		var offer: Dictionary = offers[i]
		var is_weapon: bool = offer.get("kind", "item") == "weapon"
		var item: Dictionary = Content.weapon_by_id[offer.id] if is_weapon else Content.item_by_id[offer.id]
		var color: Color = Color(item.color) if is_weapon else Content.RARITY_COLORS[item.rarity]
		var rect = reward_rect(i)
		var x = rect.position.x
		var middle = rect.get_center().x
		centered("WEAPON" if is_weapon else item.rarity.to_upper() + " RELIC", middle, 232, 15, color, bold)
		draw_circle(Vector2(middle, 291), 37, Color(.08, .10, .08, .5))
		diamond(Vector2(middle, 293), 27, Color("262f28"))
		diamond(Vector2(middle, 288), 25, color, false)
		diamond(Vector2(middle, 288), 15, color)
		draw_arc(Vector2(middle, 290), 44, -.7, 3.7, 32, Color(color, .32), 1.5, true)
		centered(item.name, middle, 361, 24, INK, heading)
		divider(Vector2(x + 28, 379), Vector2(x + REWARD_WIDTH - 28, 379))
		draw_multiline_string(body, Vector2(x + 26, 409), item.description, HORIZONTAL_ALIGNMENT_CENTER, REWARD_WIDTH - 52, 18, 3, MUTED)
		centered("NEW FIGHTING STYLE" if is_weapon else item.tag, middle, 465, 13, color, bold)
	centered("Relics stack. Find something beautifully strange.", 640, 692, 17, MUTED)

func draw_journal() -> void:
	text("The things we carry", Vector2(64, 146), 40, INK, heading)
	text("60 relics to find. Every effect stacks with your weapon and other relics.", Vector2(66, 184), 19, MUTED)
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
	text("%d / 60 found  ·  Filled diamonds are discovered relics" % Run.profile.discovered.size(), Vector2(66, 664), 17, MUTED)
	centered("%d / %d" % [journal_page + 1, journal_page_count()], 976, 664, 20, GOLD)

func draw_end() -> void:
	hearth_emblem(Vector2(640, 156), 22)
	centered("The hearth is yours." if mode == "won" else "A light goes out.", 640, 240, 38, INK, heading)
	centered("You carried a little warmth all the way home." if mode == "won" else "There is always another little spark.", 640, 284, 19, MUTED)
	centered("Floor %d  ·  %d rooms  ·  %d foes" % [mini(Run.floor_number, 3), Run.cleared, Run.kills], 640, 343, 22, GOLD)
	centered("%d relics  ·  %d:%02d  ·  seed %d" % [Run.inventory.size(), int(Run.elapsed) / 60, int(Run.elapsed) % 60, Run.seed_value], 640, 383, 18, MUTED)
	centered("Your next combination is still out there.", 640, 425, 17, MUTED)
