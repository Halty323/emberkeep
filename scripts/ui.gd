class_name GameInterface
extends Control
const INK := Color("eef0df")
const MUTED := Color("a6afa7")
const GOLD := Color("efc78b")
const PANEL := Color(.065, .09, .105, .96)
const EDGE := Color("384341")
var game: Node3D
var body: Font = preload("res://assets/fonts/body.ttf")
var heading: Font = preload("res://assets/fonts/display.ttf")
var bold: Font = preload("res://assets/fonts/bold.ttf")
var content: Control
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
		child.queue_free()
	seed_field = null
	match mode:
		"menu": build_menu()
		"play":
			button("II", Rect2(1200, 31, 48, 44), func(): game.pause_game(), false)
			button("RELICS", Rect2(1090, 31, 96, 44), func(): open_journal("pause"), false)
		"pause":
			button("Continue the journey", Rect2(455, 278, 370, 54), func(): game.resume_game(), true)
			button("Relic journal", Rect2(455, 345, 370, 48), func(): open_journal("pause"))
			button("Settings", Rect2(455, 406, 370, 48), func(): open_settings("pause"))
			button("Return to title", Rect2(455, 467, 370, 48), func(): game.return_to_title())
			var trigger = Button.new()
			trigger.name = "SecretTrigger"
			trigger.position = Vector2(425, 160)
			trigger.size = Vector2(430, 65)
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
			button("One more little light", Rect2(455, 441, 370, 56), func(): game.start_run(Content.weapons[starter_index].id, 0, false), true)
			button("Return to title", Rect2(455, 511, 370, 48), func(): game.return_to_title())
	queue_redraw()

func register_secret_tap() -> void:
	if mode != "pause" or not Run.active:
		return
	secret_taps += 1
	if secret_taps >= 5:
		show_screen("secret")

func build_secret_code() -> void:
	secret_field = LineEdit.new()
	secret_field.name = "SecretCode"
	secret_field.position = Vector2(455, 310)
	secret_field.size = Vector2(370, 54)
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
	button("Make a wish", Rect2(455, 412, 370, 52), func(): submit_secret_code(secret_field.text), true)
	button("← Back", Rect2(455, 482, 370, 44), close_secret_code)

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
	seed_field.position = Vector2(80, 365)
	seed_field.size = Vector2(180, 38)
	seed_field.placeholder_text = "Random seed"
	seed_field.text = selected_seed
	seed_field.max_length = 10
	seed_field.add_theme_font_override("font", body)
	seed_field.add_theme_font_size_override("font_size", 15)
	seed_field.add_theme_color_override("font_color", MUTED)
	seed_field.add_theme_stylebox_override("normal", style(Color(.08, .11, .12, .7), EDGE))
	seed_field.add_theme_stylebox_override("focus", style(Color(.1, .13, .14, .9), GOLD))
	seed_field.text_changed.connect(func(value): selected_seed = value)
	content.add_child(seed_field)
	button("<", Rect2(80, 305, 38, 38), func(): cycle_weapon(-1))
	button(">", Rect2(410, 305, 38, 38), func(): cycle_weapon(1))
	button("Begin a run   →", Rect2(80, 427, 368, 57), func(): game.start_run(Content.weapons[starter_index].id, seed_field.text.to_int(), false), true)
	if Run.has_save():
		button("Continue saved run", Rect2(80, 496, 368, 45), func(): game.continue_run())
		button("Today’s seed", Rect2(80, 553, 176, 43), func(): game.start_run(Content.weapons[starter_index].id, Run.daily_seed(), true))
		button("Relic journal", Rect2(272, 553, 176, 43), func(): open_journal("menu"))
	else:
		button("Today’s seed", Rect2(80, 498, 176, 45), func(): game.start_run(Content.weapons[starter_index].id, Run.daily_seed(), true))
		button("Relic journal", Rect2(272, 498, 176, 45), func(): open_journal("menu"))
	button("Settings", Rect2(80, 632, 110, 36), func(): open_settings("menu"))

func cycle_weapon(step: int) -> void:
	starter_index = posmod(starter_index + step, Content.weapons.size())
	Audio.play_sound("coin", .75)
	queue_redraw()

func build_rewards() -> void:
	for i in offers.size():
		var offer: Dictionary = offers[i]
		var x = 142 + i * 338
		var price = int(offer.get("price", 0))
		var affordable = not shop or Run.coins >= price
		var label = "Take this relic" if not shop else "%d coins" % price
		if offer.get("kind", "item") == "weapon":
			label = "Equip weapon" if not shop else "%d coins · equip" % price
		button(label, Rect2(x + 22, 475, 266, 48), func(): game.choose_offer(i), affordable)
	button("Keep exploring", Rect2(490, 588, 300, 44), func(): game.close_reward())

func open_journal(back: String) -> void:
	previous_mode = back
	game.paused = true
	journal_page = 0
	show_screen("journal")

func build_journal() -> void:
	button("← Back", Rect2(76, 48, 110, 40), func(): close_subscreen())
	button("←", Rect2(1050, 632, 64, 40), func(): journal_page = maxi(0, journal_page - 1); queue_redraw())
	button("→", Rect2(1130, 632, 64, 40), func(): journal_page = mini(4, journal_page + 1); queue_redraw())

func open_settings(back: String) -> void:
	previous_mode = back
	show_screen("settings")

func build_settings() -> void:
	button("← Back", Rect2(455, 556, 370, 46), func(): close_subscreen())
	var options = [["sound", "Sound effects"], ["music", "Ambient music"], ["shake", "Camera shake"], ["touch", "Always show touch controls"], ["quality", "Lantern shadows"]]
	for i in options.size():
		var option: Array = options[i]
		button("%s     %s" % [option[1], "ON" if Run.profile[option[0]] else "OFF"], Rect2(455, 231 + i * 57, 370, 44), func():
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
	return box

func button(label: String, rect: Rect2, callback: Callable, primary := false) -> Button:
	var control = Button.new()
	control.text = label
	control.position = rect.position
	control.size = rect.size
	control.add_theme_font_override("font", bold)
	control.add_theme_font_size_override("font_size", 16 if rect.size.y > 45 else 14)
	control.add_theme_color_override("font_color", Color("273033") if primary else INK)
	control.add_theme_color_override("font_hover_color", Color("273033") if primary else GOLD)
	control.add_theme_color_override("font_pressed_color", Color("273033") if primary else GOLD)
	control.add_theme_stylebox_override("normal", style(GOLD if primary else Color(.10, .14, .15, .9), GOLD if primary else EDGE))
	control.add_theme_stylebox_override("hover", style(Color("f6d69d") if primary else Color("263b3b"), GOLD))
	control.add_theme_stylebox_override("pressed", style(Color("d6ac70") if primary else Color("304444"), GOLD))
	control.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), GOLD))
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
			if p.distance_to(Vector2(973, 620)) < 47:
				game.request_dash = true
				get_viewport().set_input_as_handled()
			elif Rect2(445, 580, 390, 58).has_point(p) and game.interaction_text != "":
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

func text(value: String, at: Vector2, size_value := 16, color := INK, font: Font = null) -> void:
	draw_string(font if font else body, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value, color)

func centered(value: String, x: float, y: float, size_value := 16, color := INK, font: Font = null) -> void:
	var f = font if font else body
	text(value, Vector2(x - f.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value).x / 2.0, y), size_value, color, f)

func card(rect: Rect2, background := PANEL, border := EDGE) -> void:
	draw_style_box(style(background, border, 10), rect)

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
			shade()
			card(Rect2(405, 135, 470, 440))
			centered("Catch your breath", 640, 203, 29, INK, heading)
			centered("Even a little flame needs a moment.", 640, 241, 15, MUTED)
			centered("Your last safe room is saved automatically.", 640, 548, 13, MUTED)
		"secret":
			shade()
			card(Rect2(405, 165, 470, 400))
			centered("A whispered wish", 640, 228, 30, INK, heading)
			centered("Some little sparks know a secret.", 640, 270, 15, MUTED)
			centered(secret_feedback, 640, 391, 14, Color("e9b398"))
		"reward": draw_rewards()
		"settings":
			shade()
			card(Rect2(405, 117, 470, 525))
			centered("Make yourself at home", 640, 183, 26, INK, heading)
		"journal": draw_journal()
		"dead", "won": draw_end()
	if mode == "play":
		for number in floating_numbers:
			var c = GOLD if number.critical else INK
			c.a = minf(1, (0.65 - number.age) * 4)
			text(number.text, number.at + Vector2(0, -number.age * 65), 22 if number.critical else 16, c, bold)
		if toast_time > 0:
			card(Rect2(440, 113, 400, 72), Color(.055, .075, .08, .94), Color(toast_color, .45))
			centered(toast_text, 640, 142, 18, toast_color, bold)
			centered(toast_detail, 640, 167, 13, MUTED)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func shade() -> void:
	draw_rect(Rect2(-offset / scale_value, get_viewport_rect().size / scale_value), Color(.025, .04, .05, .81))

func draw_menu() -> void:
	for i in 60:
		draw_rect(Rect2(i * 12, 0, 12, 720), Color(.035, .053, .064, .98 * (1.0 - float(i) / 60)))
	diamond(Vector2(89, 65), 14, GOLD, false)
	diamond(Vector2(89, 65), 6, GOLD)
	text("A LITTLE LIGHT. A DIFFERENT RUN.", Vector2(117, 70), 12, MUTED, bold)
	text("Emberkeep", Vector2(76, 194), 61, INK, heading)
	text("Every little light fights back.", Vector2(81, 235), 21, GOLD, heading)
	text("Find strange relics. Make beautiful trouble.", Vector2(81, 271), 15, MUTED)
	var weapon: Dictionary = Content.weapons[starter_index]
	centered(weapon.name, 264, 330, 21, Color(weapon.color), heading)
	draw_multiline_string(body, Vector2(82, 354), weapon.description, HORIZONTAL_ALIGNMENT_LEFT, 370, 13, 1, MUTED)
	text("Optional seed", Vector2(278, 390), 13, MUTED)
	text("START WITH ANY OF THE 10 WEAPONS", Vector2(82, 413), 10, MUTED, bold)
	text("%d runs     %d victories     %d / 60 relics found" % [Run.profile.runs, Run.profile.wins, Run.profile.discovered.size()], Vector2(82, 615), 12, MUTED)
	text("EARLY PLAYABLE  /  ALL PLACEHOLDER GEOMETRY", Vector2(211, 655), 10, Color("737f78"))
	card(Rect2(805, 566, 394, 108), Color(.06, .09, .1, .9), Color("4d5145"))
	text("A warm place. A wild little dungeon.", Vector2(827, 601), 18, GOLD, heading)
	text("60 stackable relics  ·  10 weapons  ·  3 floors", Vector2(827, 631), 14, INK)
	text("Seeded rooms. Ridiculous combinations. One more run.", Vector2(827, 654), 12, MUTED)
	text("GODOT  /  ANDROID + DESKTOP", Vector2(947, 60), 11, MUTED, bold)

func draw_hud() -> void:
	card(Rect2(28, 27, 312, 91), Color(.055, .08, .09, .92), Color("4d5145"))
	text("THE LITTLE LIGHT", Vector2(47, 51), 10, MUTED, bold)
	var hearts = int(ceil(Run.stats.max_hp / 2.0))
	var shown = mini(hearts, 10)
	for i in shown:
		var at = Vector2(55 + i * 24, 73)
		var fill = clampf((Run.hp - i * 2) / 2, 0, 1)
		diamond(at, 9, Color("4c4e47"))
		if fill > 0:
			diamond(at, 9 * (.58 if fill < 1 else 1.0), Color("eebf88"))
	if hearts > 10:
		text("+%d" % (hearts - 10), Vector2(294, 78), 12, GOLD)
	text("%02d coins" % Run.coins, Vector2(47, 102), 13, GOLD, bold)
	text("%s" % Content.weapon_by_id[Run.weapon_id].name, Vector2(150, 102), 13, INK)
	if game.player and game.player.shield > 0:
		text("%d guard" % game.player.shield, Vector2(47, 136), 12, Color("9bd5c2"))
	var floor_names = ["The Waking Cellar", "The Mosslit Halls", "The Last Hearth"]
	centered("FLOOR %d  /  %s" % [Run.floor_number, floor_names[mini(2, Run.floor_number - 1)].to_upper()], 640, 46, 12, GOLD, bold)
	var room_label: String = {"combat": "A room full of trouble", "start": "A safe little beginning", "treasure": "Something worth keeping", "shop": "The candle merchant", "rest": "A moment of warmth", "boss": "The hearth is stirring"}.get(Run.rooms[Run.current_room].type, "")
	centered(room_label, 640, 70, 14, MUTED)
	draw_minimap()
	if game.room and not game.room.open:
		var remaining = 0
		for enemy in game.enemies:
			if is_instance_valid(enemy) and enemy.alive:
				remaining += 1
		centered("%d little troubles remain" % remaining, 640, 691, 13, MUTED)
	else:
		centered("Doorways are open · keep exploring", 640, 691, 12, MUTED)
	var boss_enemy = game.get_boss()
	if boss_enemy:
		var title: String = ["THE HEARTH WARDEN", "THE MOSSKEEPER", "THE LAST LIGHT"][mini(2, Run.floor_number - 1)]
		centered(title, 640, 99, 12, Color("edb39c"), bold)
		card(Rect2(430, 109, 420, 9), Color("333a38"), EDGE)
		draw_rect(Rect2(432, 111, 416 * maxf(0, boss_enemy.hp / boss_enemy.max_hp), 5), Color("d78d72"))
	if game.interaction_text != "":
		card(Rect2(445, 580, 390, 58), Color(.06, .085, .09, .96), Color("8d805f"))
		centered(game.interaction_text, 640, 604, 16, GOLD, bold)
		centered("Tap here  /  E or A on controller", 640, 625, 11, MUTED)
	if touch_used or Run.profile.touch or OS.has_feature("android"):
		draw_stick(left_origin, left_vector, "MOVE", left_touch >= 0)
		draw_stick(right_origin, right_vector, "AIM + FIRE", right_touch >= 0)
		var ready: bool = game.player and game.player.dash_cooldown <= 0
		draw_circle(Vector2(973, 620), 38, Color(.13, .17, .18, .75))
		draw_arc(Vector2(973, 620), 38, -PI / 2, TAU - PI / 2, 40, GOLD if ready else MUTED, 1.5, true)
		centered("DASH" if ready else "%.1f" % game.player.dash_cooldown, 973, 625, 12, GOLD if ready else MUTED, bold)
	else:
		text("WASD move  ·  Mouse aim + fire  ·  Space dash  ·  E interact", Vector2(30, 661), 11, MUTED)
	text("SEED %d" % Run.seed_value, Vector2(30, 697), 10, Color("78867e"))
	text("%d:%02d" % [int(Run.elapsed) / 60, int(Run.elapsed) % 60], Vector2(1200, 697), 11, MUTED)
	if Run.inventory.size() > 0:
		for i in mini(Run.inventory.size(), 12):
			var item: Dictionary = Content.item_by_id[Run.inventory[i]]
			diamond(Vector2(49 + i * 24, 162), 6, Content.RARITY_COLORS[item.rarity])

func draw_stick(at: Vector2, value: Vector2, label: String, active_touch: bool) -> void:
	draw_circle(at, 62, Color(.10, .14, .15, .35))
	draw_arc(at, 62, 0, TAU, 48, Color(.83, .83, .7, .45 if active_touch else .22), 1.3, true)
	draw_circle(at + value * 48, 25, Color(.87, .76, .55, .36 if active_touch else .15))
	draw_arc(at + value * 48, 25, 0, TAU, 24, Color(.9, .8, .6, .6), 1.2, true)
	centered(label, at.x, at.y + 89, 10, Color(.8, .82, .74, .6), bold)

func draw_minimap() -> void:
	card(Rect2(1075, 91, 174, 159), Color(.055, .08, .09, .85), EDGE)
	var center = Vector2(1161, 173)
	var scale_map = 17.0
	var here = Run.coord(Run.current_room)
	for key in Run.rooms:
		var r: Dictionary = Run.rooms[key]
		if not r.visited and key not in Run.neighbors(Run.current_room):
			continue
		var p = center + Vector2(Run.coord(key) - here) * scale_map
		if absf(p.x - center.x) > 70 or absf(p.y - center.y) > 60:
			continue
		var c = Color("747c70") if r.cleared else Color("454f4a")
		if r.type == "treasure": c = GOLD
		if r.type == "shop": c = Color("a8cdb8")
		if r.type == "boss": c = Color("c58a7b")
		if key == Run.current_room: c = INK
		draw_rect(Rect2(p - Vector2(5, 4), Vector2(10, 8)), c)
		if key == Run.current_room:
			draw_rect(Rect2(p - Vector2(7, 6), Vector2(14, 12)), GOLD, false, 1)
	text("FIND THE HEARTH", Vector2(1095, 113), 9, MUTED, bold)

func draw_rewards() -> void:
	shade()
	centered("The candle merchant" if shop else "A small kindness", 640, 129, 34, INK, heading)
	centered("A good find is worth a few coins. You have %d." % Run.coins if shop else "Choose one. Let it change the way you play.", 640, 169, 16, MUTED)
	for i in offers.size():
		var offer: Dictionary = offers[i]
		var is_weapon: bool = offer.get("kind", "item") == "weapon"
		var item: Dictionary = Content.weapon_by_id[offer.id] if is_weapon else Content.item_by_id[offer.id]
		var color: Color = Color(item.color) if is_weapon else Content.RARITY_COLORS[item.rarity]
		var x = 142 + i * 338
		card(Rect2(x, 213, 310, 334), PANEL, Color(color, .5))
		centered("WEAPON" if is_weapon else item.rarity.to_upper() + " RELIC", x + 155, 245, 11, color, bold)
		diamond(Vector2(x + 155, 306), 29, color, false)
		diamond(Vector2(x + 155, 306), 17, color)
		draw_arc(Vector2(x + 155, 306), 44, -.7, 3.7, 32, Color(color, .18), 1.0, true)
		centered(item.name, x + 155, 378, 23, INK, heading)
		draw_multiline_string(body, Vector2(x + 27, 412), item.description, HORIZONTAL_ALIGNMENT_CENTER, 256, 15, 3, MUTED)
		centered("NEW FIGHTING STYLE" if is_weapon else item.tag, x + 155, 465, 10, color, bold)
	centered("Relics stack. The most interesting runs happen between the rules.", 640, 670, 12, MUTED)

func draw_journal() -> void:
	shade()
	text("The things we carry", Vector2(76, 145), 36, INK, heading)
	text("60 relics to find. Every effect stacks with your weapon and other relics.", Vector2(78, 180), 15, MUTED)
	var start = journal_page * 12
	for slot in 12:
		var index = start + slot
		if index >= Content.items.size(): break
		var item: Dictionary = Content.items[index]
		var x = 76 + (slot % 3) * 382
		var y = 213 + (slot / 3) * 95
		var owned: bool = item.id in Run.inventory
		var found: bool = item.id in Run.profile.discovered
		var color: Color = Content.RARITY_COLORS[item.rarity]
		card(Rect2(x, y, 366, 83), PANEL, Color(color, .5) if owned else EDGE)
		diamond(Vector2(x + 24, y + 31), 9, color, found or owned)
		text(item.name, Vector2(x + 45, y + 29), 16, color if owned else INK, bold)
		if owned: text("×%d" % Run.inventory.count(item.id), Vector2(x + 319, y + 29), 13, GOLD)
		draw_multiline_string(body, Vector2(x + 17, y + 52), item.description, HORIZONTAL_ALIGNMENT_LEFT, 335, 12, 2, MUTED)
	text("%d / 60 found  ·  Filled diamonds are discovered relics" % Run.profile.discovered.size(), Vector2(78, 658), 13, MUTED)
	centered("%d / 5" % (journal_page + 1), 1000, 659, 14, GOLD)

func draw_end() -> void:
	shade()
	card(Rect2(377, 116, 526, 500))
	diamond(Vector2(640, 175), 19, GOLD, mode == "won")
	centered("The hearth is yours." if mode == "won" else "A light goes out.", 640, 238, 34, INK, heading)
	centered("You carried a little warmth all the way home." if mode == "won" else "There is always another little spark.", 640, 278, 15, MUTED)
	centered("Floor %d  ·  %d rooms  ·  %d foes" % [mini(Run.floor_number, 3), Run.cleared, Run.kills], 640, 331, 17, GOLD)
	centered("%d relics  ·  %d:%02d  ·  seed %d" % [Run.inventory.size(), int(Run.elapsed) / 60, int(Run.elapsed) % 60, Run.seed_value], 640, 364, 14, MUTED)
	centered("Your next combination is still out there.", 640, 405, 13, MUTED)
