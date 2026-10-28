extends SceneTree
## Native UI layout, room-light propagation, and touch/mouse routing.
## Run through tools/test.sh so all persistence goes to disposable storage.
var checks = 0
var failures = 0
var game
var run
var catalog

func _initialize() -> void:
	call_deferred("test_ui")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func descendants(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child.is_queued_for_deletion(): continue
		result.append(child)
		result.append_array(descendants(child))
	return result

func validate_controls(screen: String) -> void:
	var controls: Array = descendants(game.ui.content).filter(func(node): return node is Button or node is LineEdit)
	var frame = Rect2(Vector2.ZERO, Vector2(1280, 720))
	check(not controls.is_empty(), screen + ": native controls are available")
	for control in controls:
		var rect = Rect2(control.position, control.size)
		check(frame.encloses(rect), screen + ": control stays in the safe logical frame: " + control.name)
		var minimum_height = 54 if control is Button else 50
		check(control.size.y >= minimum_height, screen + ": controls have comfortable touch height: " + control.name)
		if control is Button and not control.text.is_empty():
			var font_size: int = control.get_theme_font_size("font_size")
			check(font_size >= 18, screen + ": button text is readable: " + control.text)
			var font: Font = control.get_theme_font("font")
			check(font.get_string_size(control.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= control.size.x - 16,
				screen + ": label fits its button: " + control.text)
	for i in controls.size():
		for j in range(i + 1, controls.size()):
			check(not Rect2(controls[i].position, controls[i].size).intersects(Rect2(controls[j].position, controls[j].size)),
				screen + ": native hit targets do not overlap")

func validate_surfaces(screen: String) -> void:
	check(not game.ui.surfaces.is_empty(), screen + ": dungeon surfaces are present")
	for surface in game.ui.surfaces:
		check(is_instance_valid(surface) and not surface.is_queued_for_deletion(), screen + ": surface belongs to the current screen")
		check(surface.stone_material is ShaderMaterial, screen + ": surface uses the lit stone material")
		check(surface.mouse_filter == Control.MOUSE_FILTER_IGNORE, screen + ": surface does not intercept gameplay input")
		for child in descendants(surface):
			if child is Control:
				check(child.mouse_filter == Control.MOUSE_FILTER_IGNORE, screen + ": decorative children do not intercept input")

func light_count() -> int:
	return descendants(game).filter(func(node): return node is Light3D).size()

func shadow_count() -> int:
	return descendants(game).filter(func(node): return node is Light3D and node.shadow_enabled).size()

func test_ui() -> void:
	run = root.get_node("Run")
	catalog = root.get_node("Content")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	validate_controls("title")
	validate_surfaces("title")
	game.start_run("needle", 20261027, false)
	game.paused = true
	await process_frame
	game.room.set_process(false)
	var world_lights = light_count()
	var world_shadows = shadow_count()
	validate_controls("play")
	validate_surfaces("play")
	# The UI must follow existing room illumination rather than using a second
	# collection of real lights or expensive UI shadow-rendering viewports.
	game.ui.sync_lighting()
	# Four slots: burning lanterns first, the rest dark (the cellar has few).
	var shown = mini(4, game.room.lamps.size())
	check(shown > 0 and game.ui.lighting_lamps.size() == 4 and game.ui.lighting_colors.size() == 4, "room lanterns reach the UI lighting data")
	check(range(shown, 4).all(func(i): return is_zero_approx(game.ui.lighting_lamps[i].w)), "unused UI lighting slots stay dark")
	for i in shown:
		var lamp: OmniLight3D = game.room.lamps[i]
		var expected: Vector2 = game.ui.local_point(game.camera.unproject_position(lamp.global_position))
		var actual: Vector4 = game.ui.lighting_lamps[i]
		check(Vector2(actual.x, actual.y).distance_to(expected) < .1, "UI lantern aligns with its rendered room position")
		check(actual.z > 0 and is_equal_approx(actual.w, lamp.light_energy), "UI lantern preserves range and current room-light energy")
		check(game.ui.lighting_colors[i].is_equal_approx(lamp.light_color), "UI lantern preserves its room-light color")
	var before: Vector4 = game.ui.lighting_lamps[0]
	game.player.position = Vector3(6, 0, 4)
	game.update_camera(0, true)
	game.room.lamps[0].light_energy = .31
	game.room.lamps[0].light_color = Color("d9a875")
	game.ui.sync_lighting()
	var after: Vector4 = game.ui.lighting_lamps[0]
	check(Vector2(after.x, after.y).distance_to(Vector2(before.x, before.y)) > 1,
		"UI lighting projection tracks camera follow")
	check(is_equal_approx(after.w, .31) and game.ui.lighting_colors[0].is_equal_approx(Color("d9a875")),
		"live lantern intensity and color changes propagate to the UI")
	game.room.lamps[0].light_energy = 0
	game.ui.sync_lighting()
	check(is_zero_approx(game.ui.lighting_lamps[0].w), "an extinguished lantern cannot continue lighting UI surfaces")
	# Screen transitions must not disturb world shadow budgets or add UI lights.
	for screen in ["pause", "settings", "secret", "dead", "won", "menu"]:
		game.ui.show_screen(screen)
		await process_frame
		validate_controls(screen)
		validate_surfaces(screen)
		check(light_count() == world_lights and shadow_count() == world_shadows,
			screen + ": interface preserves the real-world light and shadow budget")
	game.ui.offers = [{"id": catalog.items[0].id}, {"id": catalog.items[1].id}, {"id": catalog.weapons[0].id, "kind": "weapon"}]
	for shopping in [false, true]:
		game.ui.shop = shopping
		game.ui.show_screen("reward")
		await process_frame
		validate_controls("shop" if shopping else "reward")
		validate_surfaces("reward")
	game.ui.open_journal("pause")
	await process_frame
	validate_controls("journal")
	validate_surfaces("journal")
	var pages: int = game.ui.journal_page_count()
	check(pages * game.ui.JOURNAL_PAGE_SIZE >= catalog.items.size(), "journal pagination can expose the whole relic catalog")
	check(game.ui.JOURNAL_PAGE_SIZE <= 6, "larger journal descriptions have room to breathe")
	for page in pages:
		check(game.ui.journal_page == page, "journal moves through every catalog page in sequence")
		game.ui.change_journal_page(1)
	check(game.ui.journal_page == pages - 1, "journal clamps at the last catalog page")
	game.ui.change_journal_page(-100)
	check(game.ui.journal_page == 0, "journal clamps at its first catalog page")
	# Preserve the native, touch-compatible hidden code entry under the new
	# decoration and larger title hit target.
	game.pause_game()
	await process_frame
	var triggers = descendants(game.ui.content).filter(func(node):
		return node is Button and node.is_connected("pressed", Callable(game.ui, "register_secret_tap")))
	check(triggers.size() == 1, "decorated pause title retains one native secret-code trigger")
	if not triggers.is_empty():
		for tap in 5: triggers[0].pressed.emit()
	check(game.ui.mode == "secret" and game.paused, "five title taps still open the hidden code entry")
	# Synthetic scaled coordinates exercise the exact production input mapping.
	# An edge point also catches an obsolete smaller mouse interaction rectangle.
	game.resume_game()
	await process_frame
	var original_offset: Vector2 = game.ui.offset
	var original_scale: float = game.ui.scale_value
	game.ui.offset = Vector2(31, 17)
	game.ui.scale_value = .75
	var touch = InputEventScreenTouch.new()
	touch.pressed = true
	touch.index = 4
	game.make_marker("rest", game.player.position)
	run.hp = 1
	game.update_interaction()
	touch.position = game.ui.offset + game.ui.INTERACTION_RECT.get_center() * game.ui.scale_value
	game.ui._input(touch)
	check(run.hp > 1 and game.marker == null, "scaled touch on the enlarged interaction panel performs the action")
	check(game.ui.left_touch == -1 and game.ui.right_touch == -1, "interaction tap does not capture a movement or aiming stick")
	game.make_marker("rest", game.player.position)
	run.hp = 1
	game.update_interaction()
	var mouse = InputEventMouseButton.new()
	mouse.pressed = true
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = game.ui.offset + (game.ui.INTERACTION_RECT.position + Vector2(12, 12)) * game.ui.scale_value
	game._unhandled_input(mouse)
	check(run.hp > 1 and game.marker == null, "mouse action uses the full enlarged interaction panel")
	game.request_dash = false
	touch.position = game.ui.offset + game.ui.DASH_CENTER * game.ui.scale_value
	game.ui._input(touch)
	check(game.request_dash, "scaled touch on the enlarged dash control requests a dash")
	check(game.ui.left_touch == -1 and game.ui.right_touch == -1, "dash tap does not capture a movement or aiming stick")
	game.ui.offset = original_offset
	game.ui.scale_value = original_scale
	game.return_to_title()
	game.queue_free()
	root.get_node("Audio").music_player.stop()
	for player in root.get_node("Audio").players: player.stop()
	await process_frame
	await process_frame
	print("EMBERKEEP UI PRESENTATION TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
