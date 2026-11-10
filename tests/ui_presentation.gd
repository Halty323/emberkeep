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
	var frame = Rect2(Vector2.ZERO, Vector2(game.ui.view_width, 720))
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
	if not OS.get_environment("EMBERKEEP_MINIMAP_CAPTURE").is_empty():
		root.size=Vector2i(1280,720)
		await test_rotating_minimap()
		print("MINIMAP RENDER RESULT: %d checks, %d failures" % [checks,failures])
		quit(0 if failures==0 else 1)
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	validate_controls("title")
	validate_surfaces("title")
	game.start_run("needle", 20261027, false)
	check(is_equal_approx(game.ui.floor_title_start, game.ui.elapsed_ui) and game.ui.floor_title_length() > 3.0,
		"a run opens with its floor's name spelled across the screen")
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
	# A screen wider than 16:9 widens the canvas instead of adding bars: the
	# slab keeps to the left edge and the right-hand controls follow the right.
	root.size = Vector2i(1680, 720)
	await process_frame
	await process_frame
	var ui = game.ui
	check(is_equal_approx(ui.view_width, 1680.0) and ui.offset == Vector2.ZERO and ui.mode == "play", "a 21:9 screen widens the canvas with no bars")
	validate_controls("wide play")
	var pause = descendants(ui.content).filter(func(node): return node is Button and node.text == "II")
	check(pause.size() == 1 and is_equal_approx(pause[0].position.x, ui.PAUSE_RECT.position.x + 400.0), "the pause button follows the right edge")
	check(ui.surfaces.any(func(surface): return surface.position == ui.HUD_RECT.position), "the player's slab keeps to the left edge")
	game.request_dash = false
	touch.index = 5
	touch.position = ui.DASH_CENTER + Vector2(400, 0)
	ui._input(touch)
	check(game.request_dash and ui.right_touch == -1, "the dash control follows the right edge")
	touch.index = 6
	touch.position = Vector2(1600, 600)
	ui._input(touch)
	check(ui.right_touch == 6 and ui.left_touch == -1, "the aiming stick sits under the right thumb")
	touch.pressed = false
	ui._input(touch)
	touch.pressed = true
	game.make_marker("rest", game.player.position)
	run.hp = 1
	game.update_interaction()
	touch.index = 7
	touch.position = ui.INTERACTION_RECT.get_center() + Vector2(200, 0)
	ui._input(touch)
	check(run.hp > 1 and game.marker == null, "the interaction prompt stays in the middle")
	game.pause_game()
	await process_frame
	validate_controls("wide pause")
	check(is_equal_approx(ui.content.position.x, 200.0), "other screens sit centred on a wide screen")
	game.resume_game()
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	check(is_equal_approx(game.ui.view_width, 1280.0), "returning to 16:9 restores the standard canvas")
	game.return_to_title()
	game.queue_free()
	root.get_node("Audio").music_player.stop()
	for player in root.get_node("Audio").players: player.stop()
	await process_frame
	await process_frame
	await test_rotating_minimap()
	print("EMBERKEEP UI PRESENTATION TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_rotating_minimap() -> void:
	var legacy_mode := OS.get_environment("EMBERKEEP_LEGACY_TEST")
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	if not OS.get_environment("EMBERKEEP_MINIMAP_CAPTURE").is_empty():
		var policy=load("res://scripts/graphics/render_policy.gd")
		policy.device_override=policy.for_device("Android","Imagination","PowerVR","gl_compatibility")
		root.get_node("Settings").apply_render_policy()
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.set_process(false)
	game.set_physics_process(false)
	game.start_run("candle",31609250,false)
	game.paused=true
	var ui=game.ui
	ui.set_process(false)
	check(game.first_person and is_instance_valid(ui.minimap_ink),"first-person play builds the rotating minimap")
	check(ui.minimap_clip.clip_contents and ui.minimap_clip.mouse_filter==Control.MOUSE_FILTER_IGNORE,"map ink is clipped without intercepting map-button input")
	check(not descendants(ui.minimap_clip).any(func(node):return node is Viewport),"the minimap adds no rendering viewport")
	var rng_before: int=run.rng.state
	var saved_position: Vector3 = game.player.position
	var saved_room: String = run.current_room
	for room_record in run.rooms.values():
		if room_record.cells.size() < 2: continue
		run.current_room = room_record.id
		game.player.position = Vector3.ZERO
		check(ui.map_player_position() == Vector2(run.room_anchor(room_record)), "map position uses the room anchor rather than its footprint center")
		for yaw in [0.0, PI*.5, -PI*.5, PI*.25]:
			game.fps.yaw = yaw
			game.update_camera(0, true)
			game.player.position = Vector3.ZERO
			ui.sync_minimap()
			var start: Vector2 = ui.minimap_pointer.position
			game.player.position = Vector3(18, 0, 0)
			ui.sync_minimap()
			check((ui.minimap_pointer.position-start).distance_to(Vector2(22,0).rotated(yaw)) < .001, "moving east moves the arrow by one rotated map cell")
			game.player.position = Vector3(0, 0, 14)
			ui.sync_minimap()
			check((ui.minimap_pointer.position-start).distance_to(Vector2(0,22).rotated(yaw)) < .001, "north/south movement uses the room's actual depth")
			var lower: Vector2 = ui.minimap_pointer.position
			game.player.position.y = 3.2
			ui.sync_minimap()
			check(ui.minimap_pointer.position.distance_to(lower) < .001, "jumping and changing storeys do not shift the map horizontally")
	run.current_room = saved_room
	game.player.position = saved_position
	for yaw in [0.0,PI*.25,PI*.5,PI*.75,PI,-PI*.5,-PI+.001,PI-.001]:
		game.fps.yaw=yaw
		game.update_camera(0,true)
		ui._process(0)
		var forward: Vector3=-game.camera.global_basis.z
		var right: Vector3=game.camera.global_basis.x
		var visible_forward: Vector2=ui.minimap_ink.global_transform.basis_xform(Vector2(forward.x,forward.z))
		var visible_right: Vector2=ui.minimap_ink.global_transform.basis_xform(Vector2(right.x,right.z))
		check(visible_forward.normalized().distance_to(Vector2.UP)<.0001,"the rendered view faces up on the minimap at yaw %.3f"%yaw)
		check(visible_right.normalized().distance_to(Vector2.RIGHT)<.0001,"camera-right remains map-right at yaw %.3f"%yaw)
		check(ui.minimap_pointer.global_transform.basis_xform(Vector2.UP).normalized().distance_to(Vector2.UP)<.0001,"the facing marker stays upright while the dungeon turns")
	for pitch in [deg_to_rad(-80),deg_to_rad(80)]:
		game.fps.pitch=pitch
		game.update_camera(0,true)
		ui._process(0)
		check(absf(angle_difference(ui.minimap_ink.rotation,game.fps.yaw))<.0001,"looking up or down preserves the compass bearing")
	game.fps.pitch=0
	# Track the actual rendered camera, including views controlled by a cinematic.
	game.camera.rotation=Vector3(0,1.2,0)
	ui._process(0)
	check(absf(angle_difference(ui.minimap_ink.rotation,1.2))<.0001,"map orientation follows the rendered camera rather than stale input")
	game.camera.rotation=Vector3(-PI*.5,0,0)
	ui._process(0)
	check(absf(angle_difference(ui.minimap_ink.rotation,1.2))<.0001,"a vertical view retains its last horizontal bearing")
	check(run.rng.state==rng_before,"camera-driven map drawing preserves gameplay randomness")
	var output: String=OS.get_environment("EMBERKEEP_MINIMAP_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		await capture_minimap(output)
	root.size=Vector2i(2424,1080)
	await process_frame
	await process_frame
	ui._process(0)
	var expected: Vector2=ui.content.global_position+(ui.MINIMAP_AREA.position+Vector2(ui.widen(),0))*ui.scale_value
	check(ui.minimap_clip.global_position.distance_to(expected)<.01,"the clipped minimap follows the right edge on a scaled ultrawide screen")
	check(ui.minimap_clip.size==ui.MINIMAP_AREA.size,"resizing preserves the logical map aperture")
	var clip_ref: WeakRef=weakref(ui.minimap_clip)
	var map_button: Button=ui.content.get_node("MapButton")
	map_button.pressed.emit()
	await process_frame
	await process_frame
	check(ui.mode=="map" and clip_ref.get_ref()==null,"the map button opens the full floor map and removes the HUD ink")
	ui.close_subscreen()
	await process_frame
	check(ui.mode=="play" and is_instance_valid(ui.minimap_ink),"returning from the full map rebuilds the rotating HUD")
	game.pause_game()
	await process_frame
	check(not is_instance_valid(ui.minimap_ink),"pausing removes the minimap overlay")
	game.queue_free()
	await process_frame
	await process_frame
	root.size=Vector2i(1280,720)
	OS.set_environment("EMBERKEEP_LEGACY_TEST",legacy_mode)

func capture_minimap(output: String) -> void:
	DirAccess.make_dir_recursive_absolute(output)
	for room in run.rooms.values():
		room.visited=true
		room.seen=room.cells.duplicate(true)
	game.ui.scribbles.clear()
	game.ui.floor_title_start=-100
	game.ui.toast_time=0
	var reports: Array=[]
	for pair in [["north",0.0],["west",PI*.5],["south",PI],["east",-PI*.5],["diagonal",PI*.25]]:
		game.fps.yaw=pair[1]
		game.update_camera(0,true)
		game.ui._process(0)
		game.ui.minimap_ink.hide()
		game.ui.minimap_pointer.hide()
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		var bare:=root.get_texture().get_image()
		game.ui.minimap_ink.show()
		game.ui.minimap_pointer.show()
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		var shown:=root.get_texture().get_image()
		var outer: Rect2i=Rect2i(game.ui.MINIMAP_RECT.grow(-5))
		var aperture: Rect2i=Rect2i(game.ui.MINIMAP_AREA)
		var outside:=0.0
		var inside:=0.0
		for y in range(outer.position.y,outer.end.y):
			for x in range(outer.position.x,outer.end.x):
				var a:=bare.get_pixel(x,y)
				var b:=shown.get_pixel(x,y)
				var difference: float=absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
				if aperture.has_point(Vector2i(x,y)): inside+=difference
				else: outside+=difference
		check(outside<.01,"rotated "+pair[0]+" map does not draw outside its aperture")
		check(inside>1.0,"rotated "+pair[0]+" map ink is actually rendered")
		shown.save_png(output.path_join(pair[0]+".png"))
		shown.get_region(aperture.grow(8)).save_png(output.path_join(pair[0]+"-map.png"))
		reports.append({"view":pair[0],"yaw":pair[1],"outside_difference":outside,"inside_difference":inside})
	FileAccess.open(output.path_join("measurements.json"),FileAccess.WRITE).store_string(JSON.stringify(reports,"  "))
