extends SceneTree
var checks := 0
var failures := 0
var game
func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("exercise")
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+label)
func find_button(label: String):
	for child in game.ui.content.get_children():
		if child is Button and child.text == label: return child
	return null
func settle() -> void:
	for i in 3: await process_frame
func exercise() -> void:
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound",false)
	settings.set_value("music",false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	check(game.in_menu and is_instance_valid(game.title_scene),"authored hearth vignette is the default title")
	check(game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE,"title has an eye-level perspective composition")
	check(game.player == null and game.marker == null,"title is not an empty gameplay arena with reward pedestals")
	check(game.ui.surfaces.is_empty(),"home has no stacked placeholder stone slabs")
	check(root.gui_get_focus_owner() != null and root.gui_get_focus_owner().is_inside_tree(),"home exposes live gamepad focus")
	check(game.title_scene.find_children("*","OmniLight3D",true,false).size() == 3,"title uses three bounded local lights")
	check(game.title_scene.get_node("HearthFireCard").mesh is QuadMesh,"period-style flame card replaces placeholder pods")
	for label in ["New journey","Daily journey","Journal","Options"]: check(find_button(label)!=null,"home navigation: "+label)
	find_button("New journey").pressed.emit()
	await settle()
	check(game.ui.mode == "armory","new journey leads to deliberate armament selection")
	var collection = root.get_node("Collection")
	var original_seed = game.ui.menu_seed
	var starters = collection.starters(game.ui.chosen_seed())
	check(starters.filter(func(weapon): return weapon.get("forged",false)).size() == 4,"four seeded choices remain available")
	for slot in starters.size():
		var button = game.ui.content.get_node("Armament%d"%slot)
		button.pressed.emit()
		check(game.ui.starter_weapon().id == starters[slot].id,"armament selects the intended forged weapon")
	game.ui.seed_field.text = "18523427"
	game.ui.seed_field.text_changed.emit("18523427")
	check(game.ui.chosen_seed() == 18523427,"custom seed is preserved")
	check(game.ui.content.get_node("Armament0").text == collection.starters(18523427)[0].name,"seed changes refresh visible armament names")
	game.ui.starter_index = 0
	if "paint_sprayer" not in run.profile.unlocks: run.profile.unlocks.append("paint_sprayer")
	game.ui.show_screen("armory")
	await settle()
	check(game.ui.content.get_node_or_null("Armament4") != null,"the unlocked Paint Sprayer is selectable")
	game.ui.content.get_node("Armament4").pressed.emit()
	check(game.ui.starter_weapon().id == "paint_sprayer","paint unlock uses the same availability rule")
	check(game.title_scene.armament_view.get_child(2).material_override.albedo_color.is_equal_approx(Color(game.ui.starter_weapon().color)),"prepared weapon previews the selected pigment")
	check(game.ui.handle_title_back() and game.ui.mode == "menu","Back returns from preparation to home")
	find_button("Journal").pressed.emit()
	check(game.ui.mode == "journal","journal remains reachable")
	game.ui.handle_title_back()
	find_button("Options").pressed.emit()
	check(game.ui.mode == "settings","options remain reachable")
	game.ui.handle_title_back()
	for screen in ["menu","armory"]:
		game.ui.show_screen(screen)
		await settle()
		var frame = Rect2(Vector2.ZERO,Vector2(game.ui.view_width,720))
		var controls = game.ui.content.get_children().filter(func(node): return node is Button or node is LineEdit)
		for control in controls:
			check(frame.encloses(Rect2(control.position,control.size)),"title controls stay inside safe frame")
			check(control.size.y >= (50 if control is LineEdit else 54),"title targets keep touch-friendly heights")
		check(root.gui_get_focus_owner() != null and root.gui_get_focus_owner().is_inside_tree(),"rebuilt title screen restores controller focus")
	game.ui.show_screen("menu")
	await settle()
	# Prepare and start a real run, then confirm a resumable journey is exposed.
	find_button("New journey").pressed.emit()
	await settle()
	game.ui.seed_field.text = "18523427"
	game.ui.seed_field.text_changed.emit("18523427")
	find_button("Enter the tower  →").pressed.emit()
	await settle()
	check(not game.in_menu and game.ui.mode == "play" and run.active,"begin creates an actual run")
	game.return_to_title()
	await settle()
	check(find_button("Continue journey") != null,"safe save exposes Continue at the top of the home navigation")
	find_button("Continue journey").pressed.emit()
	await settle()
	check(run.active and not game.in_menu,"Continue resumes the saved journey")
	game.queue_free()
	await settle()
	print("EMBERKEEP TITLE PRESENTATION: %d checks, %d failures"%[checks,failures])
	quit(0 if failures == 0 else 1)
