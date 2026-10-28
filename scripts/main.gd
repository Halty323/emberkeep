extends Node3D
const CAMERA_GAME_SIZE = 14.4
const CAMERA_MENU_SIZE = 18.8
const CAMERA_FOLLOW_GAIN = .45
const CAMERA_FOCUS_LIMIT = Vector2(3.6, 2.8)
var room: DungeonRoom
var camera: Camera3D
var camera_focus = Vector3.ZERO
var room_environment: WorldEnvironment
var key_light: DirectionalLight3D
var player: Adventurer
var ui: GameInterface
var scene_root: Node3D
var marker: Node3D
var marker_visual: Node3D
var enemies: Array = []
var shots: Array = []
var pickups: Array = []
var paused = true
var in_menu = true
var sim_time = 0.0
var hitstop = 0.0
var shake = 0.0
var hurt_flash = 0.0
var request_dash = false
var interaction_text = ""
var interaction_kind = ""
var transition_cooldown = 0.0
var pending_portal = ""
# Doorways play out over 1.5 s: walk out and fade, slide, walk in and appear.
const TRANSITION_EXIT := .45
const TRANSITION_SLIDE := .6
const TRANSITION_ENTER := .45
const DOOR_STEP := .7
var transition: Dictionary = {}
# The departing room, kept on screen (and nothing else) during the slide.
var previous_view: Node3D
# The footprint the glow mask was last set to by a transition.
var view_mask: RoomGeometry
var fade_prewarm = 0
var entity_counter = 10
var chosen_reward_shop = false
var snapshot_timer = 0.0
var vignette: ShaderMaterial
var actions: GameActions
var interactions := InteractionRegistry.new()
var companions: Array = []
var bomb_views: Dictionary = {}
var item_views: Dictionary = {}
var chest_views: Dictionary = {}
var command_counter = 0
var last_result: Dictionary = {}
const PEDESTAL_ID := "pedestal"
const MAX_SHOTS := 200
const HOSTILE_SHOT_RESERVE := 50
var camera_home = Vector3(18, 23, 22)
var screen_right = Vector3(22, 0, -18).normalized()
var screen_down = Vector3(18, 0, 22).normalized()

func _ready() -> void:
	# Packaged-build diagnostic: report what the catalog actually loaded.
	if "--verify-catalog" in OS.get_cmdline_user_args():
		print("EMBERKEEP CATALOG REPORT " + JSON.stringify(Content.report()))
		# Quit lands after this frame; nothing below was built, so stay idle.
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)
		get_tree().quit(0 if Content.errors.is_empty() else 1)
		return
	setup_inputs()
	# Reserve a useful 512px tile for the single optional lantern shadow.
	get_viewport().positional_shadow_atlas_quad_0 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1
	room_environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("111d26")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9aaec2")
	env.ambient_light_energy = .12
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("142330")
	env.fog_density = .002
	env.fog_sky_affect = 0
	room_environment.environment = env
	add_child(room_environment)
	key_light = DirectionalLight3D.new()
	key_light.light_color = Color("99b4cf")
	key_light.light_cull_mask = 1
	key_light.light_energy = .22
	key_light.rotation_degrees = Vector3(-53, -35, 0)
	key_light.shadow_enabled = true
	key_light.shadow_bias = .1
	key_light.shadow_normal_bias = 1.0
	key_light.shadow_opacity = .95
	key_light.directional_shadow_max_distance = 50.0
	add_child(key_light)
	camera = Camera3D.new()
	add_child(camera)
	camera.position = camera_home
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_MENU_SIZE
	camera.near = .1
	camera.far = 100
	camera.current = true
	var fx_layer = CanvasLayer.new()
	fx_layer.layer = 2
	add_child(fx_layer)
	var overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette = ShaderMaterial.new()
	vignette.shader = preload("res://shaders/vignette.gdshader")
	overlay.material = vignette
	fx_layer.add_child(overlay)
	var layer = CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	ui = GameInterface.new()
	layer.add_child(ui)
	ui.setup(self)
	Run.item_gained.connect(on_item_gained)
	actions = GameActions.new(self)
	Session.command_received.connect(on_command)
	Collection.unlocked.connect(on_weapon_unlocked)
	get_tree().auto_accept_quit = false
	show_title_room()
	if "--quickstart" in OS.get_cmdline_user_args():
		start_run("candle", 421337, false)

func setup_inputs() -> void:
	var actions = {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"dash": [KEY_SPACE, KEY_SHIFT], "interact": [KEY_E], "pause_game": [KEY_ESCAPE, KEY_P], "journal": [KEY_TAB], "map": [KEY_M],
		"use_active": [KEY_F], "place_bomb": [KEY_B]}
	for action in actions:
		if not InputMap.has_action(action): InputMap.add_action(action)
		for key in actions[action]:
			var event = InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	var joy_actions = {"dash": JOY_BUTTON_RIGHT_SHOULDER, "interact": JOY_BUTTON_A, "pause_game": JOY_BUTTON_START,
		"use_active": JOY_BUTTON_LEFT_SHOULDER, "place_bomb": JOY_BUTTON_X}
	for action in joy_actions:
		var event = InputEventJoypadButton.new()
		event.button_index = joy_actions[action]
		InputMap.action_add_event(action, event)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and not in_menu and Run.active:
		if ui.mode == "play": pause_game()
		elif ui.mode == "pause": resume_game()
		elif ui.mode in ["journal", "settings", "map"]: ui.close_subscreen()
		elif ui.mode == "painting": ui.close_painting()
		elif ui.mode == "secret": ui.close_secret_code()
	elif event.is_action_pressed("map") and not in_menu and Run.active:
		if ui.mode == "map": ui.close_subscreen()
		elif is_playing(): ui.open_map("play")
	elif event.is_action_pressed("dash") and is_playing():
		request_dash = true
	elif event.is_action_pressed("interact") and is_playing():
		interact()
	# Actions fire on a fresh press only; a held key never repeats them.
	elif event.is_action_pressed("use_active", false) and is_playing():
		submit({"type": "use_active"})
	elif event.is_action_pressed("place_bomb", false) and is_playing():
		submit({"type": "place_bomb"})
	elif event.is_action_pressed("journal") and is_playing():
		ui.open_journal("pause")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and is_playing() and event.device != InputEvent.DEVICE_ID_EMULATION:
		var p = ui.local_point(event.position)
		if ui.INTERACTION_RECT.has_point(p) and interaction_text != "":
			interact()

## Local commands take the same path a remote peer's would: through Session
## to the validated action handlers, with a unique event id.
func submit(command: Dictionary) -> Dictionary:
	command_counter += 1
	command["event"] = "local:%d:%d" % [Run.seed_value, command_counter]
	last_result = {}
	Session.submit(command)
	return last_result

func on_command(peer_id: int, command: Dictionary) -> void:
	if Session.is_authority():
		last_result = actions.perform(command, peer_id)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if is_instance_valid(ui) and is_playing():
			pause_game()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(ui) and not in_menu:
			if ui.mode == "play": pause_game()
			elif ui.mode == "pause": resume_game()
			elif ui.mode in ["settings", "journal", "map"]: ui.close_subscreen()
			elif ui.mode == "painting": ui.close_painting()
			elif ui.mode == "secret": ui.close_secret_code()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()

func is_playing() -> bool:
	return Run.active and not paused and not in_menu

func screen_direction(value: Vector2) -> Vector3:
	return screen_right * value.x + screen_down * value.y

func _physics_process(delta: float) -> void:
	if not is_playing(): return
	# A doorway transition owns the tick: foes, shots and timers wait for it.
	if not transition.is_empty():
		advance_transition(delta)
		return
	if hitstop > 0:
		hitstop -= delta
		return
	sim_time += delta
	Run.elapsed += delta
	transition_cooldown -= delta
	# Cooldowns, modifiers and fuses advance on this same unpaused clock.
	for bomb in Run.advance(delta):
		actions.detonate(bomb)
		if not is_playing(): return
	var move_input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move_joy = Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if move_joy.length() > .18: move_input = move_joy.limit_length()
	if ui.left_vector.length() > .1: move_input = ui.left_vector
	var aim = Vector3.ZERO
	var shooting = false
	var aim_joy = Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if ui.right_vector.length() > .15:
		aim = screen_direction(ui.right_vector)
		shooting = true
	elif aim_joy.length() > .22:
		aim = screen_direction(aim_joy)
		shooting = true
	elif not ui.touch_used and not ui.is_touch_platform():
		var mouse = get_viewport().get_mouse_position()
		var ray_origin = camera.project_ray_origin(mouse)
		var ray_direction = camera.project_ray_normal(mouse)
		var intersection = Plane(Vector3.UP, .65).intersects_ray(ray_origin, ray_direction)
		if intersection != null:
			aim = intersection - player.global_position - Vector3.UP * .65
			aim.y = 0
		# A click that pressed an on-screen action button never becomes fire.
		shooting = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not ui.mouse_on_action
	if request_dash:
		player.dash()
		request_dash = false
	player.update_sim(delta, move_input, aim, shooting)
	for enemy in enemies.duplicate():
		if is_instance_valid(enemy) and is_playing() and enemy.alive: enemy.update_sim(delta)
	enemies = enemies.filter(func(e): return is_instance_valid(e) and e.alive)
	for shot in shots.duplicate():
		if is_instance_valid(shot) and is_playing(): shot.update_sim(delta)
	shots = shots.filter(func(s): return is_instance_valid(s) and s.alive)
	sync_companions()
	for companion in companions:
		companion.update_sim(delta)
	for pickup in pickups.duplicate():
		if is_instance_valid(pickup): pickup.update_sim(delta)
	pickups = pickups.filter(func(p): return is_instance_valid(p) and not p.collected)
	if not Run.active: return
	if enemies.is_empty() and not room.open:
		clear_room()
	update_interaction()
	if room.open and transition_cooldown <= 0:
		check_portals()
	snapshot_timer -= delta
	if snapshot_timer <= 0:
		snapshot_timer = .1
		Session.publish({"player": {"id": player.entity_id, "owner": player.owner_peer_id, "position": [player.position.x, player.position.z], "hp": Run.hp},
			"room": Run.current_room, "seed": Run.seed_value, "floor": Run.floor_number})
	# Room changes start only here, after every actor finished this tick.
	if pending_portal != "":
		var portal_id: String = pending_portal
		pending_portal = ""
		begin_transition(portal_id)

func in_transition() -> bool:
	return not transition.is_empty()

## The character walks through the doorway and fades. Everything runs on the
## simulation clock, so pausing holds it and every frame rate sees the same.
func begin_transition(portal_id: String) -> void:
	var side = Run.portal_side(portal_id, Run.current_room)
	var door = RoomGeometry.socket_point(side.cell, side.dir)
	transition = {"portal": portal_id, "phase": "exit", "time": 0.0, "from": player.position,
		"to": Vector3(door.x, 0, door.y) + Vector3(side.dir.x, 0, side.dir.y) * DOOR_STEP}
	player.velocity = Vector3.ZERO
	request_dash = false
	interaction_text = ""
	interaction_kind = ""

func advance_transition(delta: float) -> void:
	transition.time += delta
	match transition.phase:
		"exit":
			var t = phase_progress(TRANSITION_EXIT)
			player.walk_to(transition.from.lerp(transition.to, t))
			player.set_fade(1.0 - t)
			if t >= 1.0: slide_to(transition.portal)
		"slide":
			if phase_progress(TRANSITION_SLIDE) >= 1.0: finish_slide()
		"enter":
			var t = phase_progress(TRANSITION_ENTER)
			player.walk_to(transition.from.lerp(transition.to, t))
			player.set_fade(t)
			if t >= 1.0:
				player.place(transition.to)
				var gate = transition.get("reseal")
				if is_instance_valid(gate):
					gate.get_node("Barrier").visible = not room.open
					Audio.play_sound("door", .8)
				transition = {}

## Fixed ticks never land exactly on a phase length in floating point.
func phase_progress(duration: float, extra := 0.0) -> float:
	return clampf((transition.time + extra) / duration + .0001, 0.0, 1.0)

## The room changes (and saves) here. The new room is built at the origin as
## always and the old one stays on screen behind it along the way travelled:
## the camera pans from one to the other, like pushing to the next screen.
func slide_to(portal_id: String) -> void:
	var old_anchor: Vector2i = Run.room_anchor(Run.rooms[Run.current_room])
	var old_cells: Array = room.geometry.cells.duplicate()
	var old_focus = camera_focus
	var outward: Vector2i = Run.portal_side(portal_id, Run.current_room).dir
	travel(portal_id, true)
	var side = Run.portal_side(portal_id, Run.current_room)
	var door = RoomGeometry.socket_point(side.cell, side.dir)
	var start = Vector3(door.x, 0, door.y) + Vector3(side.dir.x, 0, side.dir.y) * DOOR_STEP
	var arrival: Vector3 = player.position
	var focus_to = camera_target(start)
	# Rooms float apart in the dark. Adjacent on the floor grid, each would
	# pop in or out beside the other's doorway, so the old room steps back
	# whole cells until neither shows while the other is framed.
	var adjacent: Vector2i = old_anchor - Run.room_anchor(Run.rooms[Run.current_room])
	var shift := adjacent
	var offset := Vector3.ZERO
	for gap in range(6):
		shift = adjacent - outward * gap
		offset = Vector3(shift.x * RoomGeometry.CELL.x, 0, shift.y * RoomGeometry.CELL.y)
		if not room_in_view(room.geometry.cells, Vector3.ZERO, old_focus + offset) and not room_in_view(old_cells, offset, focus_to):
			break
	previous_view.position = offset
	# Lantern glows and floor marks are masked to the room; cover both for now.
	view_mask = RoomGeometry.new(room.geometry.cells + old_cells.map(func(cell): return cell + shift))
	view_mask.apply_shader_mask()
	# Whole cells can leave a stretch of the pan where neither room shows.
	# Those frames are identical darkness, so the camera skips them.
	var focus_from = old_focus + offset
	var old_leaves = view_crossing(func(u): return room_in_view(old_cells, offset, focus_from.lerp(focus_to, u)))
	var new_arrives = view_crossing(func(u): return not room_in_view(room.geometry.cells, Vector3.ZERO, focus_from.lerp(focus_to, u)))
	transition.merge({"phase": "slide", "time": 0.0, "from": start, "to": arrival, "focus_from": focus_from,
		"focus_to": focus_to, "dark_from": old_leaves, "dark_skip": maxf(0.0, new_arrives - old_leaves)}, true)
	player.position = start
	player.face(arrival - start)
	player.set_fade(0.0)
	# A room that seals on entry keeps this doorway open until the figure is in.
	for gate in room.gates:
		if gate.get_meta("portal", "") == portal_id and not room.open:
			gate.get_node("Barrier").visible = false
			transition["reseal"] = gate

## Whether any of a room's cells (floor, walls with caps up to 2.9 units, wall
## faces 0.45 past the floor) would be on screen with the camera at this
## focus. Orthographic: each cell box projects to a convex hexagon, tested
## exactly against the view at the current aspect.
func room_in_view(cells: Array, offset: Vector3, focus: Vector3) -> bool:
	var view = get_viewport().get_visible_rect().size
	var half = Vector2(camera.size * view.x / view.y, camera.size) / 2.0
	var screen = PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
	var basis: Basis = camera.global_basis
	var eye = camera_home + focus
	for cell in cells:
		var box = Rect2(RoomGeometry.cell_center(cell) - RoomGeometry.HALF, RoomGeometry.CELL).grow(.5)
		var corners = PackedVector2Array()
		for x in [box.position.x, box.end.x]:
			for z in [box.position.y, box.end.y]:
				for y in [0.0, 3.0]:
					var relative = Vector3(x, y, z) + offset - eye
					corners.append(Vector2(relative.dot(basis.x), relative.dot(basis.y)))
		if not Geometry2D.intersect_polygons(Geometry2D.convex_hull(corners), screen).is_empty():
			return true
	return false

## Where along the pan (0..1) a test that holds at the start stops holding.
func view_crossing(holds: Callable) -> float:
	var low = 0.0
	var high = 1.0
	for i in 18:
		var middle = (low + high) / 2.0
		if holds.call(middle): low = middle
		else: high = middle
	return low

## Pan position for a slide progress: eased, with the dark stretch removed.
func slide_focus(progress: float) -> Vector3:
	var along = smoothstep(0.0, 1.0, progress) * (1.0 - transition.dark_skip)
	if along > transition.dark_from: along += transition.dark_skip
	return transition.focus_from.lerp(transition.focus_to, along)

func finish_slide() -> void:
	if is_instance_valid(previous_view): previous_view.queue_free()
	previous_view = null
	view_mask = room.geometry
	view_mask.apply_shader_mask()
	transition.phase = "enter"
	transition.time = 0.0

func _process(delta: float) -> void:
	if fade_prewarm > 0:
		fade_prewarm -= 1
		if fade_prewarm == 0 and in_menu and is_instance_valid(player): player.set_fade(1.0)
	shake = maxf(0, shake - delta * .9)
	hurt_flash = maxf(0, hurt_flash - delta * 1.6)
	update_camera(delta)
	vignette.set_shader_parameter("hurt", hurt_flash)
	if marker_visual and is_instance_valid(marker_visual):
		# Animate the luminous relic alone; its pedestal and light stay static,
		# allowing the room's shadow maps to remain cached while idle.
		marker_visual.rotation.y += delta * .5
	for view in item_views.values():
		if is_instance_valid(view):
			var orb = view.get_node_or_null("Orb")
			if orb: orb.position.y = .62 + sin(Time.get_ticks_msec() * .003) * .06

func update_camera(delta: float, snap := false) -> void:
	if not camera:
		return
	var target = Vector3.ZERO
	if not in_menu and is_instance_valid(player):
		target = camera_target(player.position)
		var actors: Array = []
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy.alive: actors.append(enemy.position)
		if is_instance_valid(room): room.update_wall_visibility(player.position, 0.0 if snap else delta, actors)
	if transition.get("phase", "") == "slide":
		# Interpolate between fixed ticks so the pan is smooth at any frame rate.
		var between = Engine.get_physics_interpolation_fraction() / Engine.physics_ticks_per_second if is_playing() else 0.0
		camera_focus = slide_focus(phase_progress(TRANSITION_SLIDE, between))
	else:
		camera_focus = target if snap else camera_focus.lerp(target, 1.0 - exp(-7.0 * delta))
	if not in_menu and is_instance_valid(room):
		room.update_light_selection(camera_focus)
	var amount = shake if Settings.values.shake else 0.0
	# Translate the camera without rotating it: movement and aiming axes stay fixed.
	camera.position = camera_home + camera_focus + Vector3(sin(Time.get_ticks_msec() * .081), cos(Time.get_ticks_msec() * .067), 0) * amount

## Keeps the close zoom in every room. A 1x1 room follows 45% of movement
## within ±3.6/±2.8; larger rooms widen the same edge margins so the player
## stays framed at every wall, bend and door without shrinking combat.
func camera_target(at: Vector3) -> Vector3:
	var area: Rect2 = room.geometry.bounds() if is_instance_valid(room) and room.geometry else Rect2(-9, -7, 18, 14)
	var center = area.get_center()
	var half = area.size / 2.0
	var margin = RoomGeometry.HALF - CAMERA_FOCUS_LIMIT
	var limit = Vector2(maxf(0, half.x - margin.x), maxf(0, half.y - margin.y))
	var gain = Vector2(maxf(CAMERA_FOLLOW_GAIN, limit.x / maxf(half.x - .3, .1)), maxf(CAMERA_FOLLOW_GAIN, limit.y / maxf(half.y - .3, .1)))
	return Vector3(center.x + clampf((at.x - center.x) * gain.x, -limit.x, limit.x), 0,
		center.y + clampf((at.z - center.y) * gain.y, -limit.y, limit.y))

func clean_room(keep_view := false) -> void:
	for shot in shots:
		if is_instance_valid(shot): shot.queue_free()
	for enemy in enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	for pickup in pickups:
		# Kept views show their drops as they slide away; nothing collects them.
		if is_instance_valid(pickup) and not keep_view: pickup.queue_free()
	shots.clear()
	enemies.clear()
	pickups.clear()
	companions.clear()
	bomb_views.clear()
	item_views.clear()
	chest_views.clear()
	interactions.clear()
	if is_instance_valid(previous_view): previous_view.queue_free()
	previous_view = null
	if not keep_view: transition = {}
	if scene_root:
		if keep_view:
			previous_view = scene_root
		else:
			remove_child(scene_root)
			scene_root.queue_free()
	scene_root = Node3D.new()
	add_child(scene_root)
	marker = null
	marker_visual = null
	interaction_text = ""
	interaction_kind = ""
	pending_portal = ""

func show_title_room() -> void:
	in_menu = true
	paused = true
	camera.h_offset = -4.5
	camera.size = CAMERA_MENU_SIZE
	clean_room()
	room = DungeonRoom.new()
	scene_root.add_child(room)
	room.build(self, {"type": "start", "seed": 81}, true)
	player = Adventurer.new()
	scene_root.add_child(player)
	player.setup(self)
	player.place(Vector3(0, 0, .1))
	player.visual.rotation_degrees.y = 150
	# Draw the faded variant for a few title frames: its shaders then compile
	# here rather than mid-transition, which would stall on phones.
	player.set_fade(.99)
	fade_prewarm = 3
	make_marker("treasure", Vector3(2.3, 0, -1.5))
	update_camera(0.0, true)

func start_run(weapon: String, seed_input: int, is_daily: bool) -> void:
	Run.start_run(weapon, seed_input, is_daily)
	in_menu = false
	paused = false
	camera.h_offset = 0
	camera.size = CAMERA_GAME_SIZE
	# Scene entity ids restart with each run, so a seed plays out identically.
	sim_time = 0
	entity_counter = 10
	enter_room(Vector3(0, 0, 2.0))
	ui.show_screen("play")
	ui.notify("A little light wakes up", "Clear rooms. Find relics. Follow the hearth.")

func continue_run() -> void:
	if not Run.load_run():
		ui.notify("This save could not be loaded", "Start a fresh run.")
		return
	in_menu = false
	paused = false
	camera.h_offset = 0
	camera.size = CAMERA_GAME_SIZE
	enter_room(saved_entry())
	ui.show_screen("play")
	ui.notify("Welcome back, little light", "Your last safe room remembers you.")

func saved_entry() -> Vector3:
	if Run.entry.get("room", "") == Run.current_room:
		return Vector3(float(Run.entry.position[0]), 0, float(Run.entry.position[1]))
	return Vector3(0, 0, 2.0)

func enter_room(spawn: Vector3, keep_view := false) -> void:
	clean_room(keep_view)
	var data: Dictionary = Run.rooms[Run.current_room]
	data.visited = true
	room = DungeonRoom.new()
	scene_root.add_child(room)
	room.build(self, data)
	# A saved or requested spawn can be outside a rotated L: validate it.
	var safe = room.geometry.safe_point(Vector2(spawn.x, spawn.z), .5, room.blocked_at)
	spawn = Vector3(safe.x, 0, safe.y)
	Run.entry = {"room": Run.current_room, "position": [snappedf(safe.x, .001), snappedf(safe.y, .001)]}
	player = Adventurer.new()
	scene_root.add_child(player)
	player.setup(self)
	player.place(spawn)
	player.invulnerability = 1.0
	transition_cooldown = .9
	var gen = RandomNumberGenerator.new()
	gen.seed = int(data.seed)
	if not data.cleared and data.type in ["combat", "boss"]:
		room.set_open(false)
		# The encounter restarts from its seed: each foe has a stable source id,
		# and the room's credit ledger stops a respawned foe paying out twice.
		if data.type == "boss":
			spawn_enemy(room.pedestal + Vector3(0, 0, -2.5), "boss", "%s:boss" % data.id)
		else:
			var choices = ["mote", "spitter", "charger", "splitter", "brute"]
			var cells: int = room.geometry.cells.size()
			var count = roundi((3 + Run.floor_number + mini(int(data.depth) / 3, 2)) * (1.0 + .45 * (cells - 1)))
			for i in count:
				var center = RoomGeometry.cell_center(room.geometry.cells[i % cells])
				var p = Vector3(gen.randf_range(-6, 6), 0, gen.randf_range(-4, 4))
				if p.distance_to(spawn - Vector3(center.x, 0, center.y)) < 3.0: p = -p
				p += Vector3(center.x, 0, center.y)
				for obstacle in room.obstacles:
					if p.distance_to(obstacle.position) < 1.6: p.z = center.y
				if p.distance_to(spawn) < 3.0:
					p = spawn + (p - spawn).normalized() * 3.5 if not p.is_equal_approx(spawn) else spawn + Vector3(3.5, 0, 0)
				var kind: String = choices[gen.randi_range(0, mini(choices.size() - 1, 2 + Run.floor_number))]
				spawn_enemy(p, kind, "%s:e%d" % [data.id, i])
	else:
		room.set_open(true)
		if not data.cleared:
			data.cleared = true
		# Recover a checkpoint written just after the boss died but before its
		# offers were generated. The room seed makes regeneration repeatable.
		if data.type == "boss" and not data.claimed and not data.has("offers"):
			ensure_offers(true)
		if not data.claimed and data.type in ["treasure", "shop", "rest"]:
			make_marker(data.type, room.pedestal)
		elif data.cleared and not data.claimed and data.has("offers"):
			make_marker("treasure", room.pedestal)
		elif data.type == "boss":
			make_marker("exit", room.pedestal + Vector3(0, 0, -1.5))
		Run.save_run()
	for drop in data.get("pickups", []):
		spawn_pickup(Vector3(float(drop.position[0]), 0, float(drop.position[1])), drop.def, float(drop.get("value", -1)), str(drop.id))
	if data.type == "secret" and not data.get("found", false):
		data["found"] = true
		ui.notify("A forgotten gallery" if data.get("variant", "") == "gallery" else "A hidden cache", "Few little lights ever find this room.", Color("d7c3e8"))
	for chest in data.get("chests", []):
		chest_views[chest.id] = ItemViews.chest(scene_root, chest)
	refresh_items()
	for mount_id in room.paintings:
		var mount = GameActions.find_record(data.get("mounts", []), mount_id)
		var view = Vector3(float(mount.view[0]), 0, float(mount.view[1]))
		interactions.register("painting:" + mount_id, "painting", view, 2.0, "", room.paintings[mount_id].node)
	for bomb in Run.pending_bombs:
		if bomb.room == Run.current_room: spawn_bomb_view(bomb)
	sync_companions()
	if data.type == "boss" and not data.cleared:
		ui.notify("The hearth is stirring", "Watch the windup. Dash through danger.", Color("e0a18b"))
	update_camera(0.0, true)

## Each doorway trigger names one specific portal; the transition itself is
## scheduled for the end of the physics tick.
func check_portals() -> void:
	var at = Vector2(player.position.x, player.position.z)
	for portal_id in Run.rooms[Run.current_room].get("portals", []):
		if Run.portals[portal_id].state not in ["open", "revealed"]: continue
		var side = Run.portal_side(portal_id, Run.current_room)
		if RoomGeometry.in_trigger(at, side.cell, side.dir):
			submit({"type": "enter_portal", "target": portal_id})
			return

## Enter the paired room at the entry anchor of the portal's other side.
func travel(portal_id: String, keep_view := false) -> void:
	var destination = Run.other_room(portal_id, Run.current_room)
	var side = Run.portal_side(portal_id, destination)
	Run.current_room = destination
	Audio.play_sound("door")
	var point = RoomGeometry.entry_point(side.cell, side.dir)
	enter_room(Vector3(point.x, 0, point.y), keep_view)

func spawn_enemy(at: Vector3, kind: String, source := "") -> DungeonEnemy:
	var enemy = DungeonEnemy.new()
	scene_root.add_child(enemy)
	entity_counter += 1
	enemy.setup(self, kind, entity_counter)
	enemy.source = source
	var safe = room.geometry.safe_point(Vector2(at.x, at.z), .5 + enemy.radius * .5, room.blocked_at)
	enemy.place(Vector3(safe.x, 0, safe.y))
	enemies.append(enemy)
	return enemy

## Friendly volleys may not starve enemies of their attacks under the global
## cap: hostile projectiles keep a reserved share.
func spawn_shot(at: Vector3, direction: Vector3, damage: float, speed_value: float, stats: Dictionary, color: Color, friendly: bool) -> EmberShot:
	if shots.size() >= MAX_SHOTS: return null
	var hostile = shots.filter(func(s): return is_instance_valid(s) and not s.friendly).size()
	if friendly and shots.size() - hostile >= MAX_SHOTS - HOSTILE_SHOT_RESERVE: return null
	var shot = EmberShot.new()
	scene_root.add_child(shot)
	entity_counter += 1
	shot.entity_id = entity_counter
	shot.setup(self, at, direction, damage, speed_value, stats, color, friendly)
	shots.append(shot)
	return shot

func nearest_enemy(at: Vector3, distance: float, excluded: Dictionary = {}) -> DungeonEnemy:
	var result: DungeonEnemy = null
	var best = distance
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.alive or excluded.has(enemy.entity_id): continue
		var d = at.distance_to(enemy.global_position + Vector3.UP * .65)
		if d < best:
			best = d
			result = enemy
	return result

func blast(at: Vector3, radius: float, damage: float, friendly: bool, excluded: DungeonEnemy) -> void:
	Effects.ring_burst(scene_root, Vector3(at.x, 0, at.z), Color("edbd7b"), radius)
	if friendly:
		for enemy in enemies.duplicate():
			if is_instance_valid(enemy) and enemy.alive and enemy != excluded and enemy.global_position.distance_to(Vector3(at.x, 0, at.z)) < radius + enemy.radius:
				enemy.take_hit(damage, (enemy.global_position - at).normalized() * 2, false)
	else:
		if player.global_position.distance_to(at) < radius:
			player.hurt(1, at)

## A foe pays out once per run: its credit and its stable drop records are
## created together, so any later save holds both or neither.
func on_enemy_killed(enemy: DungeonEnemy) -> void:
	if enemy.boss:
		hitstop = .11
		shake = .3
		for shot in shots:
			if is_instance_valid(shot) and not shot.friendly: shot.remove()
	var data: Dictionary = Run.rooms[Run.current_room]
	if enemy.source == "" or enemy.source in data.get("credited", []):
		return
	if not data.has("credited"): data.credited = []
	data.credited.append(enemy.source)
	Run.kills += 1
	var drops = Drops.roll("boss" if enemy.boss else "enemy_common", Run.rng, Run.stats.luck, Run.stats.coin_bonus)
	for i in drops.size():
		var at = Drops.scatter(drops.size(), i, enemy.global_position)
		spawn_pickup(at, drops[i].def)

func spawn_pickup(at: Vector3, pickup_id: String, amount := -1.0, restored_id := "") -> DungeonPickup:
	var definition = Content.record("pickups", pickup_id)
	if definition.is_empty():
		push_warning("Unknown pickup '%s' was not spawned." % pickup_id)
		return null
	var safe = room.geometry.safe_point(Vector2(at.x, at.z), .3)
	var pickup = DungeonPickup.new()
	scene_root.add_child(pickup)
	pickup.setup(self, Vector3(safe.x, 0, safe.y), pickup_id, amount)
	if restored_id.is_empty():
		pickup.drop_id = Run.add_drop(Run.current_room, pickup_id, safe, pickup.value)
	else:
		pickup.drop_id = restored_id
	pickups.append(pickup)
	return pickup

func pickup_node(drop_id: String) -> DungeonPickup:
	for pickup in pickups:
		if is_instance_valid(pickup) and pickup.drop_id == drop_id and not pickup.collected: return pickup
	return null

func pickup_feedback(at: Vector3, definition: Dictionary) -> void:
	Effects.play("pickup", at + Vector3(0, .35, 0), Color(definition.color))

func clear_room() -> void:
	room.set_open(true)
	Run.mark_cleared()
	var data: Dictionary = Run.rooms[Run.current_room]
	Audio.play_sound("door", 1.3)
	ui.notify("A little more warmth", "The doorways are open.")
	if data.type == "boss" or Run.cleared % 2 == 0:
		ensure_offers(data.type == "boss")
		make_marker("treasure", room.pedestal)
	else:
		data.claimed = true
		for drop in Drops.roll("room_clear", Run.rng, Run.stats.luck):
			spawn_pickup(room.pedestal, drop.def)
	Run.save_run()

func ensure_offers(premium := false) -> void:
	var data: Dictionary = Run.rooms[Run.current_room]
	if data.has("offers"): return
	var gen = RandomNumberGenerator.new()
	gen.seed = int(data.seed) + 991
	var items = Content.roll_items(gen, 3, Run.inventory, premium, Run.stats.luck)
	var offers: Array = []
	for item in items:
		var price: int = {"common": 8, "uncommon": 12, "rare": 17, "mythic": 24}[item.rarity]
		offers.append({"kind": "item", "id": item.id, "price": price})
	if gen.randf() < .5 or data.type == "shop":
		var arsenal = Collection.available_weapons()
		var weapon: Dictionary = arsenal[gen.randi_range(0, arsenal.size() - 1)]
		offers[2] = {"kind": "weapon", "id": weapon.id, "price": 14}
	if gen.randf() < (.6 if data.type == "shop" else .3):
		var pool = Content.families.actives.filter(func(active): return active.id != Run.active_item.get("def", ""))
		offers[1] = {"kind": "active", "id": pool[gen.randi_range(0, pool.size() - 1)].id, "price": 15}
	data.offers = offers
	Run.save_run()

func make_marker(kind: String, at := Vector3.ZERO) -> void:
	if marker and is_instance_valid(marker): marker.queue_free()
	marker_visual = null
	marker = Node3D.new()
	scene_root.add_child(marker)
	marker.position = at
	marker.set_meta("kind", kind)
	if kind == "exit":
		Geo.ring(marker, Vector3(0, .09, 0), 1.05, Color("a3d5c2"), .09)
		Geo.halo(marker, Vector3(0, .02, 0), 5.0, Color(.35, .8, .6, .32))
		Geo.light(marker, Vector3(0, .6, 0), Color("a7d8bd"), .65, 3.5)
	elif kind == "rest":
		Geo.cylinder(marker, Vector3(0, .2, 0), .65, .4, Color("86775f"))
		Geo.sphere(marker, Vector3(0, .75, 0), .25, Color("ffd28d"), 1.8)
		Geo.halo(marker, Vector3(0, .03, 0), 4, Color(1, .6, .2, .3))
	else:
		Geo.cylinder(marker, Vector3(0, .22, 0), .5, .44, Color("656454"))
		var relic = Geo.box(marker, Vector3(0, 1.0, 0), Vector3(.43, .43, .43), Color("d4b580") if kind == "treasure" else Color("a9c4ad"), .7)
		marker_visual = relic
		relic.rotation_degrees = Vector3(45, 35, 30)
		Geo.ring(marker, Vector3(0, .035, 0), .95, Color("d9b97a"), .035)
		Geo.halo(marker, Vector3(0, .03, 0), 4, Color(1, .65, .22, .22))
		Geo.light(marker, Vector3(0, 1.5, 0), Color("f0c68c"), .55, 3.5)
	interactions.register(PEDESTAL_ID, kind, at, 2.1, "", marker)

func remove_marker() -> void:
	if marker and is_instance_valid(marker): marker.queue_free()
	marker = null
	marker_visual = null
	interactions.unregister(PEDESTAL_ID)

func prompt_for(target: Dictionary) -> String:
	match target.kind:
		"treasure": return "Choose a little treasure"
		"shop": return "Browse the merchant’s wares"
		"rest": return "Warm your hands · heal 3"
		"exit": return "Carry the light home" if Run.floor_number == 3 else "Descend to the next floor"
		"chest":
			var chest = GameActions.find_record(Run.rooms[Run.current_room].get("chests", []), target.id.trim_prefix("chest:"))
			if not chest.get("locked", false): return "Open the chest"
			return "Unlock the chest · 1 key" if Run.keys > 0 else "Locked · it needs a key"
		"item":
			var record = GameActions.find_record(Run.rooms[Run.current_room].get("items", []), target.id.trim_prefix("item:"))
			var definition = Content.record("actives", record.get("def", ""))
			return ("Swap for " if not Run.active_item.is_empty() else "Take ") + definition.get("name", "item")
		"painting":
			var painting_id: String = room.paintings.get(target.id.trim_prefix("painting:"), {}).get("painting", "")
			return "Look at " + Content.record("paintings", painting_id).title if Collection.seen(painting_id) else "Look at the painting"
	return target.prompt

## Loot, swaps and paintings wait until the room is safe; nothing interacts
## through a wall.
func interaction_eligible(target: Dictionary) -> bool:
	if target.kind in ["chest", "item", "painting"] and not room.open:
		return false
	var from = Vector2(player.position.x, player.position.z)
	var to = Vector2(target.position.x, target.position.z)
	for step in 6:
		if not room.geometry.contains(from.lerp(to, step / 5.0)): return false
	return true

func update_interaction() -> void:
	var target = interactions.choose(player.position, interaction_eligible)
	interaction_kind = target.get("kind", "")
	interaction_text = prompt_for(target) if not target.is_empty() else ""

func interact() -> void:
	if not is_playing(): return
	update_interaction()
	if interactions.focused == "": return
	submit({"type": "interact", "target": interactions.focused})
	if is_playing(): update_interaction()

## Pedestal uses: rewards, the merchant, the rest hearth and the floor exit.
func use_pedestal(target: Dictionary) -> Dictionary:
	var data: Dictionary = Run.rooms[Run.current_room]
	match target.kind:
		"treasure", "shop":
			ensure_offers(data.type == "treasure")
			chosen_reward_shop = target.kind == "shop"
			ui.offers = data.offers
			ui.shop = chosen_reward_shop
			paused = true
			ui.show_screen("reward")
		"rest":
			# The hearth's marker is the gate: it is removed once used.
			Run.heal(3)
			data.claimed = true
			remove_marker()
			Run.save_run()
			Audio.play_sound("item")
			ui.notify("A moment of warmth", "Recovered 3 health.")
		"exit":
			if Run.floor_number >= 3:
				end_run(true)
			else:
				Run.next_floor()
				enter_room(Vector3(0, 0, 2.0))
				ui.notify("A little deeper", "A new floor. A fresh breath of warmth.")
	return GameActions.result(true)

## Inspecting discovers the work for good. The viewer pauses solo play.
func inspect_painting(target: Dictionary) -> Dictionary:
	var view: Dictionary = room.paintings.get(target.id.trim_prefix("painting:"), {})
	if view.is_empty():
		return GameActions.result(false, "no painting here")
	var painting: Dictionary = Content.record("paintings", view.painting)
	var unlocks_before: Array = Run.profile.unlocks.duplicate()
	if Collection.discover(painting.id):
		Effects.play("discovery_glint", view.node.global_position + Vector3(0, 0, 0))
		var progress = Collection.progress()
		ui.notify("A painting found · %d / %d" % [progress.x, progress.y], painting.title, Color("e9d6a8"))
		Audio.play_sound("item", .85)
	ui.painting_unlock = ""
	for weapon in Run.profile.unlocks:
		if weapon not in unlocks_before: ui.painting_unlock = Content.weapon_by_id[weapon].name
	ui.open_painting(painting.id, "play")
	return GameActions.result(true)

## A newly earned weapon is announced; it never replaces the one in hand.
func on_weapon_unlocked(weapon_id: String) -> void:
	if is_instance_valid(ui):
		ui.notify("%s unlocked" % Content.weapon_by_id[weapon_id].name, "Twelve classics found. Choose it when you begin a run.", Color("e7d9c8"))

func choose_offer(index: int) -> void:
	var data: Dictionary = Run.rooms[Run.current_room]
	if data.claimed or index < 0 or index >= data.offers.size(): return
	var offer: Dictionary = data.offers[index]
	if chosen_reward_shop:
		if Run.coins < int(offer.price):
			Audio.play_sound("hurt", 1.5)
			return
		Run.coins -= int(offer.price)
	data.claimed = true
	if offer.kind == "weapon":
		Run.weapon_id = offer.id
		Run.changed.emit()
		ui.notify(Content.weapon_by_id[offer.id].name, "A new way to carry the light.")
		Audio.play_sound("item")
	elif offer.kind == "active":
		# The new item goes into the slot; the one in hand is set beside the
		# pedestal, keeping its instance and its running cooldown.
		var item_id = Run.next_instance("a")
		if not data.has("items"): data.items = []
		data.items.append({"id": item_id, "def": offer.id, "position": [snappedf(player.position.x, .001), snappedf(player.position.z, .001)]})
		actions.take_item(item_id)
	else:
		Run.gain_item(offer.id)
	remove_marker()
	if data.type == "boss": make_marker("exit", room.pedestal + Vector3(0, 0, -1.5))
	Run.save_run()
	close_reward()

func close_reward() -> void:
	paused = false
	ui.show_screen("play")

func add_item_record(definition_id: String, at: Vector3) -> void:
	var data: Dictionary = Run.rooms[Run.current_room]
	if not data.has("items"): data.items = []
	data.items.append({"id": Run.next_instance("a"), "def": definition_id, "position": [snappedf(at.x, .001), snappedf(at.z, .001)]})
	refresh_items()

## Rebuilds the views and interaction targets for dropped items and chests.
func refresh_items() -> void:
	var data: Dictionary = Run.rooms[Run.current_room]
	for view in item_views.values():
		if is_instance_valid(view): view.queue_free()
	item_views.clear()
	for id in interactions.targets.keys():
		if id.begins_with("item:") or id.begins_with("chest:"): interactions.unregister(id)
	for record in data.get("items", []):
		var view = ItemViews.item(scene_root, record)
		item_views[record.id] = view
		interactions.register("item:" + record.id, "item", view.position, 1.6, "", view)
	for chest in data.get("chests", []):
		if chest.opened: continue
		var at = Vector3(float(chest.position[0]), 0, float(chest.position[1]))
		interactions.register("chest:" + chest.id, "chest", at, 1.9, "", chest_views.get(chest.id))

func chest_opened(chest: Dictionary) -> void:
	interactions.unregister("chest:" + chest.id)
	if chest_views.has(chest.id): ItemViews.set_open(chest_views[chest.id])
	var at = Vector3(float(chest.position[0]), .7, float(chest.position[1]))
	Effects.play("chest_open", at)
	Audio.play_sound("item", .9)

func spawn_bomb_view(record: Dictionary) -> void:
	var view = BombView.new()
	scene_root.add_child(view)
	view.setup(record, GameActions.BOMB_RADIUS)
	bomb_views[record.id] = view

func bomb_exploded(record: Dictionary, at: Vector3, radius: float) -> void:
	if bomb_views.has(record.id):
		if is_instance_valid(bomb_views[record.id]): bomb_views[record.id].queue_free()
		bomb_views.erase(record.id)
	Effects.ring_burst(scene_root, at, Color("f0a46b"), radius)
	Effects.burst(scene_root, at + Vector3(0, .5, 0), Color("f6c27a"), 12, 1.6)
	shake = maxf(shake, .25)
	Audio.play_sound("kill", .55)

## A bomb's breach capability: breakable props and concealed seams in range.
## Offscreen rooms resolve from their saved state without any effects.
func breach(room_id: String, at: Vector3, radius: float, live: bool) -> void:
	var data: Dictionary = Run.rooms[room_id]
	var flat = Vector2(at.x, at.z)
	for record in data.get("props", []):
		if record.get("destroyed", false) or not Content.record("furniture", record.kind).has("breakable"): continue
		var rect = Furnisher.record_rect(record)
		var nearest = Vector2(clampf(flat.x, rect.position.x, rect.end.x), clampf(flat.y, rect.position.y, rect.end.y))
		if nearest.distance_to(flat) <= radius:
			destroy_prop(room_id, record, live)
	for portal_id in data.get("portals", []):
		var portal: Dictionary = Run.portals[portal_id]
		if portal.state != "concealed": continue
		var side = Run.portal_side(portal_id, room_id)
		if RoomGeometry.socket_point(side.cell, side.dir).distance_to(flat) <= radius + .6:
			# Revealed for good: saved with the blast, never resealed on reload.
			portal.state = "revealed"
			if live:
				room.reveal_socket(portal_id)
				ui.notify("A hidden passage", "The old wall gives way.", Color("d7c3e8"))
				Audio.play_sound("door", .7)

## Friendly shots chip at breakable furniture.
func hit_prop(id: String, damage: float) -> void:
	if room.damage_prop(id, damage):
		var record = GameActions.find_record(Run.rooms[Run.current_room].get("props", []), id)
		if not record.is_empty():
			destroy_prop(Run.current_room, record, true)
			if Run.rooms[Run.current_room].cleared: Run.save_run()

## Breaking marks the prop destroyed, creates its drops from a per-prop loot
## stream exactly once, and updates navigation; dust is purely cosmetic.
func destroy_prop(room_id: String, record: Dictionary, live: bool) -> void:
	if record.get("destroyed", false):
		return
	record.destroyed = true
	var definition: Dictionary = Content.record("furniture", record.kind)
	var loot = RandomNumberGenerator.new()
	loot.seed = Content.stable_hash("loot:%d:%d:%s" % [Run.seed_value, Run.floor_number, record.id])
	var drops = Drops.roll(definition.breakable.drops, loot, Run.stats.luck)
	var at = Vector3(float(record.position[0]), 0, float(record.position[1]))
	for i in drops.size():
		var point = Drops.scatter(drops.size(), i, at)
		if drops[i].has("active"):
			if not Run.rooms[room_id].has("items"): Run.rooms[room_id].items = []
			Run.rooms[room_id].items.append({"id": Run.next_instance("a"), "def": drops[i].active, "position": [point.x, point.z]})
		elif live:
			spawn_pickup(point, drops[i].def)
		else:
			Run.add_drop(room_id, drops[i].def, Vector2(point.x, point.z))
	if live:
		room.break_prop(record.id)
		Effects.play("prop_dust", at + Vector3(0, .5, 0))
		Audio.play_sound("hit", .7)
		if drops.any(func(drop): return drop.has("active")): refresh_items()

## Companion views follow the saved Moth Jar modifier, so they survive room
## changes and reloads with their remaining time.
func sync_companions() -> void:
	var wanted = Run.flag_total("companions") if Run.active else 0
	companions = companions.filter(func(c): return is_instance_valid(c))
	while companions.size() > wanted:
		companions.pop_back().queue_free()
	var bite = 6.0
	for modifier in Run.modifiers:
		if modifier.get("flags", {}).has("companion_damage"): bite = float(modifier.flags.companion_damage)
	while companions.size() < wanted and is_instance_valid(player):
		var moth = MothCompanion.new()
		scene_root.add_child(moth)
		moth.setup(self, companions.size(), bite)
		moth.global_position = player.global_position + Vector3(0, .9, 0)
		companions.append(moth)

func on_item_gained(item: Dictionary) -> void:
	if player and is_instance_valid(player): player.refresh_orbitals()
	Audio.play_sound("item")
	ui.notify(item.name, item.description, Content.RARITY_COLORS[item.rarity])

func redeem_secret_code(code: String) -> bool:
	if not Run.active or in_menu or code.strip_edges().to_upper() != Run.ALL_RELICS_CODE:
		return false
	var added = Run.grant_all_relics()
	if added > 0 and player and is_instance_valid(player):
		player.refresh_orbitals()
		player.shield = maxi(player.shield, int(Run.stats.shield))
	Audio.play_sound("item")
	if added > 0:
		ui.notify("Every little light, all at once", "%d relics awakened. You carry all %d." % [added, Content.items.size()])
	else:
		ui.notify("Every little light is already yours", "You already carry all %d relics." % Content.items.size())
	return true

func pause_game() -> void:
	if not Run.active or in_menu: return
	paused = true
	ui.show_screen("pause")

func resume_game() -> void:
	paused = false
	ui.show_screen("play")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func return_to_title() -> void:
	if Run.active and Run.rooms[Run.current_room].cleared:
		Run.save_run()
	Run.active = false
	show_title_room()
	ui.show_screen("menu")

func end_run(won: bool) -> void:
	Run.finish(won)
	paused = true
	ui.show_screen("won" if won else "dead")

func get_boss() -> DungeonEnemy:
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.alive and enemy.boss: return enemy
	return null

func damage_number(at: Vector3, damage: float, critical: bool) -> void:
	if camera.is_position_behind(at): return
	ui.damage_number(camera.unproject_position(at), damage, critical)
