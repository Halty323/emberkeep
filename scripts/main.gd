extends Node3D
const CAMERA_GAME_SIZE = 14.4
const CAMERA_MENU_SIZE = 18.8
const CAMERA_FOLLOW_GAIN = .45
const CAMERA_FOCUS_LIMIT = Vector2(3.6, 2.8)
var first_person := OS.get_environment("EMBERKEEP_LEGACY_TEST") != "1" and not "--isometric" in OS.get_cmdline_user_args()
var fps: FirstPersonController
var corridors: CorridorTransit
var deferred_encounter: Dictionary={}
var title_scene: EmberkeepTitleScene
var stair_cinematic := StairCinematic.new()
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
# Death, behind a dark altar not yet bargained with.
var death_figure: DeathFigure
var trials: DeathTrials
# The Crimson Grail's kills this room.
var bloodlust := 0
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
# Each floor's shaders compile behind the veil, not mid-fight (ShaderPrewarm).
var prewarm: ShaderPrewarm
# The room a corridor leaves is deleted over the following frames.
var reaper := NodeReaper.new()
# A corridor arrival saves a couple of frames later, off the handoff frame.
var save_due := -1
# The way up: a stair that builds itself when the boss falls, climbed into
# the light from the floor above; the next floor opens at its stairwell.
const CLIMB_APPROACH := .5
const CLIMB_STEPS := 2.0
const ARRIVE_RISE := .8
const ARRIVE_STEP_OFF := .5
var stairs: Staircase
var well_spot := Vector3.ZERO
var light_veil: ColorRect
var entity_counter = 10
var chosen_reward_shop = false
var chosen_reward_dark = false
var snapshot_timer = 0.0
var vignette: ShaderMaterial
var screen_fx: ScreenFx
var mirror: WaterMirror
var actions: GameActions
# Co-op on the local network (scripts/coop/party.gd); idle when alone.
var party: Party
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
# What a fight leaves on the floor; one per room, rebuilt on entry.
var residue: ResidueField
var hazards: FloorHazards
# A windswept floor's draught: every shot in flight drifts with it.
var wind := Vector3.ZERO
# Combat state that outlives a room. Sparks are hostile embers caught by a
# grazing dash, released with the next shot. Kindle grows with quick kills
# and gutters with a hit. Noise is what sound-hunting foes follow.
var sparks = 0
var kindle_heat = 0.0
var kindle_quiet = 0.0
var noises: Array = []
const MAX_SPARKS := 3
const KINDLE_STEPS := [3, 6, 10]
const KINDLE_DAMAGE := [1.0, 1.15, 1.3, 1.5]
const KINDLE_FADE_AFTER := 3.5
const PLAYER_LIGHT := 3.6
var camera_home = Vector3(18, 23, 22)
var screen_right = Vector3(22, 0, -18).normalized()
var screen_down = Vector3(18, 0, 22).normalized()

func _ready() -> void:
	# Packaged-build diagnostic: report what the catalog actually loaded.
	if "--verify-catalog" in OS.get_cmdline_user_args():
		var report = Content.report().duplicate(true)
		report.errors.append_array(DungeonStyle.verify_material_assets())
		print("EMBERKEEP CATALOG REPORT " + JSON.stringify(report))
		# Quit lands after this frame; nothing below was built, so stay idle.
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)
		get_tree().quit(0 if report.errors.is_empty() else 1)
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
	key_light.light_cull_mask = Geo.LIT_LAYERS
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
	mirror = WaterMirror.new()
	add_child(mirror)
	mirror.setup(camera)
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
	screen_fx = ScreenFx.new()
	add_child(screen_fx)
	screen_fx.setup(self, overlay, vignette)
	light_veil = ColorRect.new()
	light_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	light_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	light_veil.color = Color(1, .95, .84, 0)
	fx_layer.add_child(light_veil)
	var layer = CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	ui = GameInterface.new()
	layer.add_child(ui)
	ui.setup(self)
	if first_person:
		fps = FirstPersonController.new()
		add_child(fps)
		fps.setup(self)
		corridors=CorridorTransit.new()
		add_child(corridors)
		corridors.setup(self)
		# Prewarm the shared ground maps for the current device budget. The
		# remaining masonry/wood maps load with the authored title room.
		for kind in 3: DungeonStyle.surface_maps(kind)
	Run.item_gained.connect(on_item_gained)
	actions = GameActions.new(self)
	trials = DeathTrials.new()
	add_child(trials)
	trials.setup(self)
	party = Party.new()
	add_child(party)
	party.setup(self)
	Session.command_received.connect(on_command)
	Collection.unlocked.connect(on_weapon_unlocked)
	get_tree().auto_accept_quit = false
	show_title_room()
	if "--quickstart" in OS.get_cmdline_user_args():
		start_run("candle", 421337, false)

func setup_inputs() -> void:
	var actions = {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"dash": [KEY_SHIFT], "jump": [KEY_SPACE], "interact": [KEY_E], "pause_game": [KEY_ESCAPE, KEY_P], "journal": [KEY_TAB], "map": [KEY_M],
		"use_active": [KEY_F], "place_bomb": [KEY_B]}
	for action in actions:
		if not InputMap.has_action(action): InputMap.add_action(action)
		for key in actions[action]:
			var event = InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	var joy_actions = {"jump": JOY_BUTTON_A, "dash": JOY_BUTTON_RIGHT_SHOULDER, "interact": JOY_BUTTON_Y, "pause_game": JOY_BUTTON_START,
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
		elif ui.mode == "bargain": close_reward()
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
		if ui.INTERACTION_RECT.has_point(ui.from_middle(p)) and interaction_text != "":
			interact()

## Local commands take the same path a remote peer's would: through Session
## to the validated action handlers, with a unique event id.
func submit(command: Dictionary) -> Dictionary:
	command_counter += 1
	command["event"] = "local:%d:%d" % [Run.seed_value, command_counter]
	last_result = {}
	Session.submit(command)
	return last_result

## Each player's own actions run on their own device, co-op included.
func on_command(peer_id: int, command: Dictionary) -> void:
	if peer_id == Session.local_peer_id or Session.is_authority():
		last_result = actions.perform(command, peer_id)

func _exit_tree() -> void:
	flush_save()
	reaper.flush()

func save_soon() -> void:
	save_due = 2

func flush_save() -> void:
	if save_due < 0: return
	save_due = -1
	FrameWatch.mark("saving")
	Run.save_run()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		flush_save()
		if is_instance_valid(ui) and is_playing():
			pause_game()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(ui) and in_menu and first_person:
			ui.handle_title_back()
		if is_instance_valid(ui) and not in_menu:
			if ui.mode == "play": pause_game()
			elif ui.mode == "pause": resume_game()
			elif ui.mode == "bargain": close_reward()
			elif ui.mode in ["settings", "journal", "map"]: ui.close_subscreen()
			elif ui.mode == "painting": ui.close_painting()
			elif ui.mode == "secret": ui.close_secret_code()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_due = -1
		if first_person and Run.active: Run.save_run()
		get_tree().quit()

func is_playing() -> bool:
	return Run.active and not paused and not in_menu

## Whether the tower moves this tick. Alone, a menu stops it; in co-op a
## menu only stops this player, and the party's world goes on.
func sim_live() -> bool:
	return Run.active and not in_menu and (not paused or party.climbing())

## Everyone foes can strike this tick: the player, and in co-op on the host
## every standing teammate's figure.
func party_bodies() -> Array:
	return party.bodies()

func nearest_body(at: Vector3) -> Node3D:
	var best: Node3D = player
	var best_distance := INF
	for body in party_bodies():
		var distance: float = body.global_position.distance_to(at)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best

## A hostile spell caught or blown away by this player.
func dispel(shot: EmberShot) -> void:
	party.dispel(shot)
	shot.remove()

## The last heart is gone: the end of a lone climb, a fall in co-op.
func player_fell() -> void:
	# Last breath: falling in the trial fails it instead.
	if trials.catch_fall(): return
	if party.climbing(): party.fall()
	else: end_run(false)

func screen_direction(value: Vector2) -> Vector3:
	if first_person and fps:
		return fps.right() * value.x + Vector3(0, 0, 1).rotated(Vector3.UP, fps.yaw) * value.y
	return screen_right * value.x + screen_down * value.y

func _physics_process(delta: float) -> void:
	if not sim_live(): return
	# A doorway transition owns the tick: foes, shots and timers wait for it.
	if not transition.is_empty():
		advance_transition(delta)
		party.tick(delta)
		return
	if hitstop > 0:
		hitstop -= delta
		party.tick(delta)
		return
	# A menu open in co-op, or a fallen player: the body stands still.
	var steering := is_playing() and not party.downed
	sim_time += delta
	Run.elapsed += delta
	transition_cooldown -= delta
	# Cooldowns, modifiers and fuses advance on this same unpaused clock.
	for bomb in Run.advance(delta):
		party.begin_world()
		actions.detonate(bomb)
		party.end_world()
		if not sim_live(): return
	var move_input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move_joy = Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if move_joy.length() > .18: move_input = move_joy.limit_length()
	if ui.left_vector.length() > .1: move_input = ui.left_vector
	var aim = Vector3.ZERO
	var shooting = false
	var aim_joy = Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if not steering:
		move_input = Vector2.ZERO
		request_dash = false
		if first_person:
			corridors.prepare()
			aim = fps.forward()
	elif first_person:
		corridors.prepare()
		fps.collect_look(delta)
		aim = fps.shot_direction(fps.shot_origin())
		shooting = ui.fire_touch >= 0 or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not ui.mouse_on_action and not fps.suppress_mouse_fire) or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > .25
	else:
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
	# Watching a teammate's trial: no spells, no dash.
	if trials.spectating():
		shooting = false
		request_dash = false
	if request_dash:
		if first_person:
			var dash_input = screen_direction(move_input)
			player.last_move = dash_input.normalized() if dash_input.length_squared() > .01 else Vector3.FORWARD.rotated(Vector3.UP, fps.yaw)
		player.dash()
		request_dash = false
	player.update_sim(delta, move_input, aim, shooting)
	advance_stair_assembly(delta)
	if party.client(): party.update_puppets(delta)
	elif party.climbing(): party.run_foes(delta)
	else:
		for enemy in enemies.duplicate():
			if is_instance_valid(enemy) and is_playing() and enemy.alive: enemy.update_sim(delta)
	enemies = enemies.filter(func(e): return is_instance_valid(e) and e.alive)
	if is_playing() or party.climbing(): trials.update(delta)
	party.begin_world()
	for shot in shots.duplicate():
		if is_instance_valid(shot) and sim_live():
			# Whose spell it is decides whose hit marker and heal it brings.
			party.shot_owner = 0 if party.spell_owner_local(shot) else shot.owner_peer
			shot.update_sim(delta)
	party.shot_owner = 0
	party.end_world()
	shots = shots.filter(func(s): return is_instance_valid(s) and s.alive)
	party.begin_world()
	# A guest's floor is the host's, sent tile by tile.
	if residue and not party.client(): residue.update_sim(delta)
	if hazards and deferred_encounter.is_empty(): hazards.update_sim(delta)
	party.end_world()
	# A streak cools once kills stop coming.
	kindle_quiet += delta
	# A draught takes the heat away faster.
	if kindle_quiet > KINDLE_FADE_AFTER: kindle_heat = maxf(0.0, kindle_heat - delta * (1.8 if Run.has_twist("windswept") else 1.0))
	sync_companions()
	for companion in companions:
		companion.update_sim(delta)
	for pickup in pickups.duplicate():
		if is_instance_valid(pickup): pickup.update_sim(delta)
	pickups = pickups.filter(func(p): return is_instance_valid(p) and not p.collected)
	if not Run.active: return
	track_exploration()
	# Posts and dropped lanterns never hold a room shut. A guest's room opens
	# when the host says its fight is won.
	if not party.client() and not room.open and deferred_encounter.is_empty() and not trials.holds_room() and enemies.all(func(e): return e.inert):
		for enemy in enemies:
			enemy.alive = false
			enemy.queue_free()
		enemies.clear()
		clear_room()
	update_interaction()
	if room.open and transition_cooldown <= 0:
		check_portals()
	snapshot_timer -= delta
	if snapshot_timer <= 0:
		snapshot_timer = .1
		Session.publish({"player": {"id": player.entity_id, "owner": player.owner_peer_id, "position": [player.position.x, player.position.z], "hp": Run.hp},
			"room": Run.current_room, "seed": Run.seed_value, "floor": Run.floor_number})
	party.tick(delta)
	# Room changes start only here, after every actor finished this tick.
	if pending_portal != "":
		var portal_id: String = pending_portal
		pending_portal = ""
		begin_transition(portal_id)
	if first_person: corridors.advance()

func in_transition() -> bool:
	return not transition.is_empty()

## The character walks through the doorway and fades. Everything runs on the
## simulation clock, so pausing holds it and every frame rate sees the same.
func begin_transition(portal_id: String) -> void:
	if first_person:
		corridors.arm(portal_id)
		return
	var side = Run.portal_side(portal_id, Run.current_room)
	var door = RoomGeometry.socket_point(side.cell, side.dir)
	transition = {"portal": portal_id, "phase": "exit", "time": 0.0, "from": player.position,
		"to": Vector3(door.x, 0, door.y) + Vector3(side.dir.x, 0, side.dir.y) * DOOR_STEP}
	player.velocity = Vector3.ZERO
	request_dash = false
	interaction_text = ""
	interaction_kind = ""

func advance_transition(delta: float) -> void:
	# A floor loading behind its screen holds the arrival until it is ready.
	if loading: return
	transition.time += delta
	if transition.get("kind", "") == "fps_floor":
		light_veil.color.a = clampf(transition.time / .35, 0, 1)
		if transition.time >= .35:
			if Run.last_floor(): end_run(true)
			else:
				Run.next_floor()
				enter_room(Vector3(0, 0, 2))
				light_veil.color.a = 1.0
				warm_shaders()
				ui.announce_floor()
		return
	if transition.get("kind", "") == "stairs":
		advance_climb()
		return
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

## Walks to the stair's foot and up every step, fading into the light that
## fills the view; the floor changes under it, then the figure comes up the
## new floor's stairwell as the light recedes. Simulation clock, like doorways.
func begin_climb() -> void:
	var path: Array = [player.position] + stairs.climb_path()
	var approach: float = StairCinematic.APPROACH if first_person else CLIMB_APPROACH
	var duration: float = StairCinematic.CLIMB if first_person else CLIMB_STEPS
	var times: Array = [approach * .6, approach * .4]
	for i in Staircase.STEPS: times.append(duration / Staircase.STEPS)
	if first_person:
		path.push_front(player.position)
		times.push_front(StairCinematic.PULLBACK)
	transition = {"kind": "stairs", "phase": "climb", "time": 0.0, "path": path, "times": times}
	if first_person: stair_cinematic.begin(self)
	player.velocity = Vector3.ZERO
	request_dash = false
	interaction_text = ""
	interaction_kind = ""

func advance_climb() -> void:
	var total: float = transition.times.reduce(func(sum, t): return sum + t, 0.0)
	var u = clampf(transition.time / total + .0001, 0.0, 1.0)
	player.walk_to(path_point(transition.path, transition.times, transition.time))
	if transition.phase == "climb":
		player.set_fade(1.0 - clampf((u - (.84 if first_person else .55)) / (.15 if first_person else .4), 0.0, 1.0))
		light_veil.color.a = pow(clampf((u - (.76 if first_person else .4)) / (.24 if first_person else .6), 0.0, 1.0), 1.6)
		if u >= 1.0: reach_next_floor()
	else:
		player.set_fade(clampf(transition.time / (ARRIVE_RISE * .8), 0.0, 1.0))
		light_veil.color.a = 1.0 - smoothstep(0.0, 1.0, transition.time / ARRIVE_RISE)
		if u >= 1.0:
			player.place(transition.path[-1])
			light_veil.color.a = 0.0
			transition = {}

## The top of the last floor is the end of the run; otherwise the next floor.
func reach_next_floor() -> void:
	if Run.last_floor():
		transition = {}
		light_veil.color.a = 0.0
		end_run(true)
		return
	if first_person and DisplayServer.get_name() != "headless" and not loading:
		# Every new floor loads behind its own screen: generated, its rooms
		# built and drawn once, its shaders compiled, before the arrival.
		transition = {"kind": "loading"}
		loading = true
		ui.loading_title = "The stair climbs on"
		ui.loading_progress = .05
		ui.show_screen("loading")
		for frame in 2: await get_tree().process_frame
		Run.next_floor()
		ui.loading_title = str(Run.theme().name)
		await prebuild_room()
		await warm_floor_rooms(Run.current_room)
		arrive_on_floor()
		await close_loading()
		ui.show_screen("play")
		ui.announce_floor()
		return
	Run.next_floor()
	arrive_on_floor()

## The new floor opens: the figure rises from its stairwell into the light.
func arrive_on_floor() -> void:
	enter_room(Vector3(0, 0, 2.0))
	party.floor_changed()
	var pedestal = Vector2(room.pedestal.x, room.pedestal.z)
	var out = (pedestal - Vector2(well_spot.x, well_spot.z)).normalized()
	var beside := Vector2(-out.y, out.x) * ((Session.local_slot() - 1.5) * .8 if party.climbing() else 0.0)
	var landing = room.geometry.safe_point(Vector2(well_spot.x, well_spot.z) + out * (Staircase.OUTER + .9) + beside, .5, room.blocked_at)
	var arrival = Vector3(landing.x, 0, landing.y)
	var path = Staircase.rise_path(well_spot, arrival)
	var times: Array = []
	for i in path.size() - 2: times.append(ARRIVE_RISE / (path.size() - 2))
	times.append(ARRIVE_STEP_OFF)
	transition = {"kind": "stairs", "phase": "arrive", "time": 0.0, "path": path, "times": times}
	player.position = path[0]
	player.face(path[1] - path[0])
	player.set_fade(0.0)
	light_veil.color.a = 1.0
	Run.entry = {"room": Run.current_room, "position": [snappedf(arrival.x, .001), snappedf(arrival.z, .001)]}
	if first_person: stair_cinematic.begin(self,true)
	warm_shaders()
	Run.save_run()
	# Behind a loading screen, the floor's name waits until it lifts.
	if not loading: ui.announce_floor()

## Position along a path of segments with their own durations.
static func path_point(path: Array, times: Array, time: float) -> Vector3:
	for i in times.size():
		if time <= times[i] or i == times.size() - 1:
			return path[i].lerp(path[i + 1], clampf(time / times[i], 0.0, 1.0))
		time -= times[i]
	return path[-1]

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
	FrameWatch.frame(delta)
	if fade_prewarm > 0:
		fade_prewarm -= 1
		if fade_prewarm == 0 and in_menu and is_instance_valid(player): player.set_fade(1.0)
	if first_person and transition.is_empty(): light_veil.color.a = move_toward(light_veil.color.a, 0, delta * 2)
	var warming: bool = is_instance_valid(prewarm) and prewarm.active()
	if warming:
		light_veil.color.a = 1.0
		prewarm.step()
	if reaper.pending() > 0:
		FrameWatch.mark("freeing the room left behind")
		reaper.step()
	if save_due > 0: save_due -= 1
	elif save_due == 0: flush_save()
	shake = maxf(0, shake - delta * .9)
	hurt_flash = maxf(0, hurt_flash - delta * 1.6)
	update_camera(delta)
	vignette.set_shader_parameter("hurt", hurt_flash)
	# The water's mirror runs only where there is water or ice to show it.
	var wet = not in_menu and residue != null and is_instance_valid(residue) and residue.reflective()
	if first_person and corridors.walking(): wet=false
	# The water mirror's own variants compile with the rest.
	if warming: wet = true
	mirror.follow(wet, get_viewport().get_visible_rect().size)
	if residue and is_instance_valid(residue):
		residue.set_mirror(mirror.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
		if not paused: residue.animate(delta)
	if marker_visual and is_instance_valid(marker_visual):
		# Animate the luminous relic alone; its pedestal and light stay static,
		# allowing the room's shadow maps to remain cached while idle.
		if marker_visual.has_meta("rest_y"): Reliquary.animate(marker_visual, Time.get_ticks_msec() * .001, delta)
		else: marker_visual.rotation.y += delta * .5
	for view in item_views.values():
		if is_instance_valid(view):
			var relic = view.get_node_or_null("Reliquary/Relic")
			if relic: Reliquary.animate(relic, Time.get_ticks_msec() * .001 + view.get_instance_id() % 7, delta)

func update_camera(delta: float, snap := false) -> void:
	if not camera:
		return
	if first_person and in_menu and is_instance_valid(title_scene):
		if fps: fps.update_view(delta)
		title_scene.pose(camera)
		return
	if first_person and stair_cinematic.pose(self): return
	if first_person and fps and not in_menu:
		fps.update_view(delta, snap)
		return
	if first_person and fps: fps.update_view(delta)
	var target = Vector3.ZERO
	if not in_menu and is_instance_valid(player):
		target = camera_target(player.position)
		# Rise with a climb so the figure stays framed on the stair.
		if transition.get("kind", "") == "stairs": target.y = player.position.y
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

func clean_room(keep_view := false, keep_corridor := false) -> void:
	flush_save()
	deferred_encounter={}
	party.room_changed()
	if corridors and not keep_corridor: corridors.reset()
	stair_cinematic.cancel(self)
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
	residue = null
	hazards = null
	if not keep_view:
		transition = {}
		if light_veil: light_veil.color.a = 0.0
	stairs = null
	if scene_root:
		if keep_view:
			previous_view = scene_root
		elif keep_corridor and first_person:
			# Leaving through a corridor: out of the world now, deleted over
			# the next frames instead of all on the handoff frame.
			reaper.reap(scene_root)
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
	if first_person:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		clean_room()
		player = null
		room = DungeonRoom.new()
		scene_root.add_child(room)
		room.geometry = RoomGeometry.new([Vector2i.ZERO])
		room.geometry.apply_shader_mask()
		room.set_process(false)
		apply_floor_light()
		title_scene = EmberkeepTitleScene.create(scene_root,self)
		title_scene.pose(camera)
		return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	apply_floor_light()
	update_camera(0.0, true)

func start_run(weapon: String, seed_input: int, is_daily: bool, prepared := false) -> void:
	if not prepared: Run.start_run(weapon, seed_input, is_daily)
	in_menu = false
	paused = prepared
	if first_person:
		fps.yaw = float(Run.view_angles[0])
		fps.pitch = float(Run.view_angles[1])
	camera.h_offset = 0
	camera.size = CAMERA_GAME_SIZE
	# Scene entity ids restart with each run, so a seed plays out identically.
	sim_time = 0
	entity_counter = 10
	reset_combat()
	# A party spreads out a little rather than standing in one spot.
	enter_room(Vector3((Session.local_slot() - 1.5) * .9, 0, 2.0) if party.online() else Vector3(0, 0, 2.0))
	warm_shaders()
	if not prepared: greet_run()

## The first words of a new run, once it can be seen.
func greet_run() -> void:
	ui.show_screen("play")
	var arrival: Array = Run.theme().arrival
	if first_person and not Run.profile.get("fps_tutorial_seen", false):
		ui.notify("Keep your little light close", "Swipe right to look · Hold CAST · Jump and dash to dodge" if ui.is_touch_platform() else "Mouse look · Click to cast · Space jump · Shift dash")
		Run.profile["fps_tutorial_seen"] = true
		Run.save_profile()
	else: ui.notify(arrival[0], arrival[1])
	ui.announce_floor()

## Draws one of everything this floor can show while the veil is up. Headless
## runs draw nothing, so there is nothing to compile.
func warm_shaders() -> void:
	if not first_person or in_menu or DisplayServer.get_name() == "headless": return
	if is_instance_valid(prewarm): prewarm.queue_free()
	FrameWatch.mark("preparing shaders")
	prewarm = ShaderPrewarm.begin(self)
	light_veil.color.a = 1.0

func continue_run(prepared := false) -> void:
	if not prepared and not Run.load_run():
		ui.notify("This save could not be loaded", "Start a fresh run.")
		return
	if first_person and VerticalPlans.upgrade_unvisited(Run.rooms,Run.portals,Run.floor_number): Run.save_run()
	in_menu = false
	paused = prepared
	if first_person:
		fps.yaw = float(Run.view_angles[0])
		fps.pitch = float(Run.view_angles[1])
	camera.h_offset = 0
	camera.size = CAMERA_GAME_SIZE
	reset_combat()
	enter_room(saved_entry())
	warm_shaders()
	if not prepared: greet_continue()

func greet_continue() -> void:
	ui.show_screen("play")
	ui.notify("Welcome back, little light", "Your last safe room remembers you.")
	ui.announce_floor()

# ---------------------------------------------------------------- loading
# A run begins behind a loading screen: the floor is generated, its first
# room built a slice per frame and its shaders compiled before play shows,
# so nothing freezes on an unexplained frame.
var loading := false
var prebuilt: DungeonRoom

func begin_run(weapon: String, seed_input: int, is_daily: bool) -> void:
	if not await open_loading("The tower stirs"):
		if not loading: start_run(weapon, seed_input, is_daily)
		return
	Run.start_run(weapon, seed_input, is_daily)
	ui.loading_title = str(Run.theme().name)
	ui.loading_progress = .1
	await prebuild_room()
	await warm_floor_rooms(Run.current_room)
	start_run(weapon, seed_input, is_daily, true)
	await close_loading()
	greet_run()

func begin_continue() -> void:
	if not await open_loading("Your light returns"):
		if not loading: continue_run()
		return
	if not Run.load_run():
		loading = false
		ui.show_screen("menu")
		ui.notify("This save could not be loaded", "Start a fresh run.")
		return
	ui.loading_progress = .1
	await prebuild_room()
	await warm_floor_rooms(Run.current_room)
	continue_run(true)
	await close_loading()
	greet_continue()

## Shows the loading screen and lets it draw; false where there is nothing
## to show (headless, the old overhead view) or a load is already under way.
func open_loading(title: String) -> bool:
	if loading or not first_person or DisplayServer.get_name() == "headless": return false
	loading = true
	ui.loading_title = title
	ui.loading_progress = .05
	ui.show_screen("loading")
	for i in 2: await get_tree().process_frame
	return true

## The first room, built hidden a slice per frame.
func prebuild_room() -> void:
	var staged := DungeonRoom.new()
	staged.visible = false
	staged.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(staged)
	staged.build(self, Run.rooms[Run.current_room], false, true)
	while staged.building:
		await get_tree().process_frame
		staged.resume_build()
		ui.loading_progress = minf(.3, ui.loading_progress + .02)
	remove_child(staged)
	staged.visible = true
	staged.process_mode = Node.PROCESS_MODE_INHERIT
	prebuilt = staged

## Every other room of the floor, built once and drawn for two frames in
## front of the camera under the loading screen: each of its materials
## meets the graphics driver now, not on the step into that room.
func warm_floor_rooms(skip: String) -> void:
	var ids: Array = Run.rooms.keys().filter(func(id): return id != skip)
	var start: float = ui.loading_progress
	for i in ids.size():
		var staged := DungeonRoom.new()
		staged.prepare_entry = false
		staged.visible = false
		staged.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(staged)
		staged.build(self, Run.rooms[ids[i]], false, true)
		while staged.building:
			await get_tree().process_frame
			staged.resume_build()
		var ahead := -camera.global_basis.z
		staged.global_position = camera.global_position + ahead * 55.0 + Vector3.DOWN * 3.0
		staged.visible = true
		FrameWatch.mark("loading: first draw of a room")
		for frame in 2: await get_tree().process_frame
		reaper.reap(staged)
		ui.loading_progress = lerpf(start, .9, float(i + 1) / ids.size())
	if is_instance_valid(room) and is_instance_valid(room.effects): EffectsPool.current = room.effects

## Waits for the floor's shaders to compile, then lets play begin.
func close_loading() -> void:
	ui.show_screen("loading")
	ui.loading_progress = maxf(ui.loading_progress, .7)
	while is_instance_valid(prewarm) and prewarm.active():
		await get_tree().process_frame
		ui.loading_progress = minf(.98, ui.loading_progress + .01)
	ui.loading_progress = 1.0
	await get_tree().process_frame
	loading = false
	paused = false

func saved_entry() -> Vector3:
	if Run.entry.get("room", "") == Run.current_room:
		return Vector3(float(Run.entry.position[0]), 0, float(Run.entry.position[1]))
	return Vector3(0, 0, 2.0)

func enter_room(spawn: Vector3, keep_view := false, walking_state: Dictionary = {}) -> void:
	RelicPowers.room_left(self)
	clean_room(keep_view,not walking_state.is_empty())
	var data: Dictionary = Run.rooms[Run.current_room]
	var first_visit: bool=not data.get("visited",false)
	data.visited = true
	if walking_state.get("room")!=null:
		room=walking_state.room
		scene_root.add_child(room)
		room.geometry.apply_shader_mask()
	elif is_instance_valid(prebuilt) and is_same(prebuilt.data, data):
		# Built behind the loading screen.
		room = prebuilt
		prebuilt = null
		scene_root.add_child(room)
		room.geometry.apply_shader_mask()
	else:
		room = DungeonRoom.new()
		scene_root.add_child(room)
		room.build(self, data)
	room.entry_portal=str(walking_state.get("portal",""))
	residue = ResidueField.new()
	scene_root.add_child(residue)
	residue.setup(self, room.geometry)
	hazards = FloorHazards.new()
	scene_root.add_child(hazards)
	hazards.setup(self, data, room.geometry, residue, room.pedestal)
	hazards.cosmetic = party.client()
	residue.logging = party.host()
	wind = Vector3.ZERO
	if Run.has_twist("windswept"):
		var bearing = float(Content.stable_hash("wind:%d:%d" % [Run.seed_value, Run.floor_number]) % 628) / 100.0
		wind = Vector3(cos(bearing), 0, sin(bearing)) * 2.4
	noises.clear()
	# A saved or requested spawn can be outside a rotated L: validate it.
	var safe = room.geometry.safe_point(Vector2(spawn.x, spawn.z), .5, room.blocked_at)
	spawn = Vector3(safe.x, 0, safe.y)
	Run.entry = {"room": Run.current_room, "position": [snappedf(safe.x, .001), snappedf(safe.y, .001)]}
	if walking_state.has("player"):
		player=walking_state.player
		scene_root.add_child(player)
	else:
		player = Adventurer.new()
		scene_root.add_child(player)
		player.setup(self)
	player.owner_peer_id = Session.local_peer_id
	if first_person:
		spawn.y = room.floor_height(spawn) + .03
		Run.entry["height"] = spawn.y
	if walking_state.has("player"):
		player.position=walking_state.position
		player.last_valid=walking_state.last_valid
		player.reset_physics_interpolation()
	else:
		player.place(spawn)
		player.invulnerability = 1.0
	transition_cooldown = .9
	if not data.cleared and data.type in ["combat", "boss"]:
		room.set_open(false)
		if walking_state.is_empty():
			# A guest's foes are the host's, drawn as they arrive.
			if not party.client(): spawn_room_encounter(data,spawn)
		else:
			deferred_encounter={"room":Run.current_room}
	else:
		room.set_open(true)
		if ExpeditionBalance.active_new_run() and data.type in ["combat","boss"] and data.cleared and data.has("clear_reward") and not data.get("clear_reward_paid",false): resolve_expedition_clear(data)
		if not data.cleared:
			data.cleared = true
		# Recover a checkpoint written just after the boss died but before its
		# offers were generated. The room seed makes regeneration repeatable.
		if data.type == "boss" and not data.claimed and not data.has("offers"):
			ensure_offers(true)
		if not data.claimed and data.type in ["treasure", "shop", "rest", "dark"]:
			make_marker(data.type, room.pedestal)
		elif data.cleared and not data.claimed and data.has("offers"):
			make_marker("treasure", room.pedestal)
		if data.type == "boss":
			raise_stairs(false)
		if walking_state.is_empty(): Run.save_run()
		else: save_soon()
	for drop in data.get("pickups", []):
		spawn_pickup(Vector3(float(drop.position[0]), float(drop.get("height",0)), float(drop.position[1])), drop.def, float(drop.get("value", -1)), str(drop.id))
	if data.type == "start" and Run.floor_number > 1:
		var spot = stair_spot(data, "stairwell")
		well_spot = Vector3(spot.x, 0, spot.y)
		Staircase.make_well(scene_root, well_spot)
		room.add_obstacle("stairwell", spot, Staircase.OUTER)
	if data.type == "secret" and not data.get("found", false):
		data["found"] = true
		ui.notify("A forgotten gallery" if data.get("variant", "") == "gallery" else "A hidden cache", "Few little lights ever find this room.", Color("d7c3e8"))
	for chest in data.get("chests", []): make_chest_view(chest)
	refresh_items()
	for mount_id in room.paintings:
		var mount = GameActions.find_record(data.get("mounts", []), mount_id)
		var view = Vector3(float(mount.view[0]), 0, float(mount.view[1]))
		interactions.register("painting:" + mount_id, "painting", view, 2.0, "", room.paintings[mount_id].node)
	for bomb in Run.pending_bombs:
		if bomb.room != Run.current_room: continue
		var carried_bombs: Dictionary=walking_state.get("bombs",{})
		if carried_bombs.has(bomb.id):
			var view: Node3D=carried_bombs[bomb.id]
			scene_root.add_child(view)
			bomb_views[bomb.id]=view
		else: spawn_bomb_view(bomb)
	sync_companions()
	if data.type == "boss" and not data.cleared:
		var line: Array = Run.theme().boss.intro
		ui.notify(line[0], line[1], Color("e0a18b"))
	apply_floor_light()
	update_camera(0.0, true)
	if first_visit and room.terrain and room.terrain.loft:
		ui.notify("A chamber on two floors", "Follow the stairs to the upper gallery.",Color("e8ca8b"))

func spawn_room_encounter(data: Dictionary, spawn: Vector3) -> void:
	var gen:=RandomNumberGenerator.new()
	gen.seed=int(data.seed)
	# The encounter restarts from its seed: each foe has a stable source id,
	# and the room's credit ledger stops a respawned foe paying out twice.
	if data.type == "boss":
		spawn_enemy(room.pedestal + Vector3(0, 0, -2.5), "boss", "%s:boss" % data.id)
	else:
		var cells: int = room.geometry.cells.size()
		var count = roundi((3 + mini(Run.floor_number, 4) + mini(int(data.depth) / 3, 2)) * (1.0 + .45 * (cells - 1)))
		if first_person: count = clampi(roundi(count * .75), 3, 12)
		if Run.has_twist("swarming"): count = roundi(count * 1.35)
		var roster = Foes.roster_for(Run.theme_id(), Run.floor_number, Run.floor_plan)
		var chance = Foes.elite_chance(Run.floor_number) + (.2 if Run.has_twist("gilded") else 0.0)
		var plan: Array = Foes.compose(roster, chance, count, gen)
		var spawned: Array = []
		for i in plan.size():
			var center = RoomGeometry.cell_center(room.geometry.cells[i % cells])
			var p = Vector3(gen.randf_range(-6, 6), 0, gen.randf_range(-4, 4))
			if p.distance_to(spawn - Vector3(center.x, 0, center.y)) < 3.0: p = -p
			p += Vector3(center.x, 0, center.y)
			# A rootling grows a few steps from its partner.
			if plan[i].partner >= 0 and plan[i].partner < i:
				p = spawned[plan[i].partner].global_position + Vector3(3.5, 0, 0).rotated(Vector3.UP, gen.randf() * TAU)
			for obstacle in room.obstacles:
				if p.distance_to(obstacle.position) < 1.6: p.z = center.y
			if p.distance_to(spawn) < 3.0:
				p = spawn + (p - spawn).normalized() * 3.5 if not p.is_equal_approx(spawn) else spawn + Vector3(3.5, 0, 0)
			if first_person and room.terrain and room.terrain.loft and i in [1,count-1]:
				var deck: Rect2=room.terrain.loft.deck
				var at:=deck.get_center()+Vector2(-1.8 if i==1 else 1.8,.6)
				p=Vector3(at.x,LoftRoom.RISE,at.y)
			spawned.append(spawn_enemy(p, plan[i].kind, "%s:e%d" % [data.id, i]))
		for i in plan.size():
			if plan[i].partner > i: spawned[i].bind_partner(spawned[plan[i].partner])
			if plan[i].elite == "twinned":
				if plan[i].twin > i: spawned[i].make_elite("twinned", spawned[plan[i].twin])
			elif plan[i].elite != "":
				spawned[i].make_elite(plan[i].elite)

func activate_corridor_encounter() -> void:
	if deferred_encounter.is_empty(): return
	var id: String=deferred_encounter.room
	deferred_encounter={}
	if id!=Run.current_room: return
	var data: Dictionary=Run.rooms[id]
	if not data.cleared and data.type in ["combat","boss"]:
		FrameWatch.mark("fight start")
		room.set_open(false)
		spawn_room_encounter(data,player.position)

## The tower brightens floor by floor; the title keeps its own warm light.
func apply_floor_light() -> void:
	var light := FloorLight.profile(0) if in_menu else FloorLight.current()
	if first_person and not in_menu: light = FloorLight.first_person(light)
	FloorLight.apply(light, room_environment.environment, key_light, vignette)
	if first_person: DungeonAtmosphere.configure(room_environment.environment, light)
	screen_fx.set_grade({} if in_menu else Run.theme())

## Where the air shimmers: burning floor, a hot clinker, the Kilnmother.
func heat_sources(limit: int) -> Array:
	var sources: Array = []
	for enemy in enemies:
		if sources.size() >= limit: break
		if not is_instance_valid(enemy) or not enemy.alive: continue
		if enemy.kind == "kilnmother": sources.append({"at": enemy.global_position + Vector3.UP * 1.5, "reach": 3.5, "power": 1.0})
		elif enemy.kind == "clinker" and enemy.burn_time > 0: sources.append({"at": enemy.global_position + Vector3.UP * .6, "reach": 1.4, "power": .7})
	if residue:
		var fields: Array=[residue]
		if is_instance_valid(residue.upper_field): fields.append(residue.upper_field)
		for field in fields:
			var fires: Array = field.tiles.keys().filter(func(tile): return field.tiles[tile].kind == "fire")
			var stride = maxi(1, fires.size() / maxi(1, limit - sources.size()))
			for i in range(0, fires.size(), stride):
				if sources.size() >= limit: break
				sources.append({"at": field.cell_center(fires[i]) + Vector3.UP * .4, "reach": 1.6, "power": .8})
	return sources

## Each doorway trigger names one specific portal; the transition itself is
## scheduled for the end of the physics tick.
func check_portals() -> void:
	if first_person: return # Walkable corridors own first-person room boundaries.
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

func enter_corridor_room(destination: String, portal_id: String, shift: Vector3) -> void:
	var carried:=player
	var at: Vector3=player.position-shift
	var last: Vector3=player.last_valid-shift
	var kept_shots: Array=[]
	for shot in shots:
		if is_instance_valid(shot) and shot.alive and corridors.contains_point(Vector2(shot.position.x-shift.x,shot.position.z-shift.z)):
			scene_root.remove_child(shot)
			shot.position-=shift
			shot.start_position-=shift
			kept_shots.append(shot)
	shots=shots.filter(func(shot): return shot not in kept_shots)
	var kept_bombs: Dictionary={}
	for bomb in Run.pending_bombs:
		if bomb.room!=Run.current_room: continue
		var point:=FloorGenerator.vec2(bomb.position)-Vector2(shift.x,shift.z)
		if not corridors.contains_point(point): continue
		bomb.room=destination
		bomb.position=FloorGenerator.point_array(point)
		var view: Node3D=bomb_views.get(bomb.id)
		if is_instance_valid(view):
			scene_root.remove_child(view)
			view.position-=shift
			view.reset_physics_interpolation()
			kept_bombs[bomb.id]=view
	scene_root.remove_child(carried)
	var prepared:=corridors.take_preloaded(destination)
	Run.current_room=destination
	var side:=Run.portal_side(portal_id,destination)
	var entry_point:=RoomGeometry.entry_point(side.cell,side.dir)
	enter_room(Vector3(entry_point.x,0,entry_point.y),false,{"player":carried,"position":at,"last_valid":last,"portal":portal_id,"room":prepared,"bombs":kept_bombs})
	for shot in kept_shots:
		scene_root.add_child(shot)
		shot.shine()
		shot.reset_physics_interpolation()
		shots.append(shot)
	camera.reset_physics_interpolation()
	Audio.play_sound("door",.5)

func walkable_at(point: Vector2, margin := .1) -> bool:
	if room.geometry.contains(point,margin): return true
	if not first_person or not corridors or not is_instance_valid(corridors.active): return false
	if corridors.contains_point(point,margin): return true
	# Clearance belongs to the UNION. Shrinking the room and corridor
	# separately creates an invisible two-radius wall at their shared seam.
	for offset in [Vector2.ZERO,Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(.707,.707),Vector2(-.707,.707),Vector2(.707,-.707),Vector2(-.707,-.707)]:
		var p: Vector2=point+offset*margin
		if not room.geometry.contains(p,0) and not corridors.contains_point(p,0): return false
	return true

func recover_player(previous: Vector2, proposed: Vector2, margin: float) -> Vector2:
	if walkable_at(proposed,margin): return proposed
	for candidate in [Vector2(proposed.x,previous.y),Vector2(previous.x,proposed.y),previous]:
		if walkable_at(candidate,margin): return candidate
	return room.geometry.safe_point(previous,margin)

func spawn_enemy(at: Vector3, kind: String, source := "") -> DungeonEnemy:
	# Each floor theme has its own boss.
	if kind == "boss": kind = Foes.boss_kind(Run.theme())
	var enemy: DungeonEnemy = Foes.create(kind)
	scene_root.add_child(enemy)
	entity_counter += 1
	# A foe's own body is built the same way on every guest's device.
	party.geo_paused += 1
	enemy.setup(self, kind, entity_counter)
	party.geo_paused -= 1
	enemy.source = source
	var safe = room.geometry.safe_point(Vector2(at.x, at.z), .5 + enemy.radius * .5, room.blocked_at)
	enemy.place(Vector3(safe.x, room.floor_height(Vector3(safe.x, at.y, safe.y)) if first_person else 0, safe.y))
	enemies.append(enemy)
	party.foe_spawned(enemy)
	return enemy

## Friendly volleys may not starve enemies of their attacks under the global
## cap: hostile projectiles keep a reserved share.
func spawn_shot(at: Vector3, direction: Vector3, damage: float, speed_value: float, stats: Dictionary, color: Color, friendly: bool) -> EmberShot:
	if party.client():
		# A guest casts only its own spells here; the host sends all others.
		return party.predict_shot(at, direction, damage, speed_value, stats, color) if friendly else null
	var shot := make_shot(at, direction, damage, speed_value, stats, color, friendly)
	if shot: party.shot_spawned(shot)
	return shot

func make_shot(at: Vector3, direction: Vector3, damage: float, speed_value: float, stats: Dictionary, color: Color, friendly: bool) -> EmberShot:
	if shots.size() >= MAX_SHOTS: return null
	if friendly:
		var friendly_count := 0
		for existing in shots:
			if is_instance_valid(existing) and existing.friendly:
				friendly_count += 1
				if friendly_count >= MAX_SHOTS - HOSTILE_SHOT_RESERVE: return null
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
		if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable or enemy.inert or excluded.has(enemy.entity_id): continue
		var d = at.distance_to(enemy.global_position + Vector3.UP * .65)
		if d < best:
			best = d
			result = enemy
	return result

func blast(at: Vector3, radius: float, damage: float, friendly: bool, excluded: DungeonEnemy) -> void:
	Effects.ring_burst(scene_root, Vector3(at.x, room.floor_height(at) if first_person else 0, at.z), Color("edbd7b"), radius)
	if residue: residue.ignite(Vector3(at.x, 0, at.z), radius * .7)
	if friendly:
		make_noise(at, 2.5)
		for enemy in enemies.duplicate():
			if is_instance_valid(enemy) and enemy.alive and enemy.targetable and enemy != excluded and (enemy.global_position + Vector3.UP * (enemy.hit_height * .4 if first_person else 0)).distance_to(at if first_person else Vector3(at.x, 0, at.z)) < radius + enemy.radius:
				enemy.take_hit(damage, (enemy.global_position - at).normalized() * 2, false, false, "blast")
	else:
		for body in party_bodies():
			if body.global_position.distance_to(at) < radius: body.hurt(1, at)

## A foe pays out once per run: its credit and its stable drop records are
## created together, so any later save holds both or neither.
## In co-op every player gets their own drops from each foe.
func on_enemy_killed(enemy: DungeonEnemy) -> void:
	var data: Dictionary = Run.rooms[Run.current_room]
	var credited: bool = enemy.source != "" and enemy.source not in data.get("credited", [])
	if credited:
		if not data.has("credited"): data.credited = []
		data.credited.append(enemy.source)
	var event := {"at": enemy.global_position, "boss": enemy.boss, "inert": enemy.inert, "loot": credited}
	party.foe_killed(enemy, event)
	if enemy.boss:
		for shot in shots:
			if is_instance_valid(shot) and not shot.friendly: shot.remove()
	award_kill(event)

## Pairings this player carries that answer any foe falling.
func kill_pairings(at: Vector3) -> void:
	RelicPowers.on_kill(self, at)
	if Run.has_pairing("frenzy"): Run.add_modifier("frenzy", 2.0, {"rate": 1.0})
	if Run.has_pairing("last_stand") and Run.hp <= Run.stats.max_hp / 2.0: Run.heal(.5)
	if Run.has_pairing("glass_cannon"):
		var stats := Run.projectile_stats()
		stats.element = "glass"
		for i in 4:
			var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 4.0 + randf())
			spawn_shot(at + Vector3.UP * .8 + direction * .3, direction, 6.0 * float(Run.stats.damage), 13.0, stats, Color("e0f8ff"), true)

## A reaction's name where it happened (or a pairing's, when it acts). A
## reaction seen for the first time is written into the journal.
func reaction_word(at: Vector3, id: String) -> void:
	if party.recording > 0: party.share("word", [at, id])
	var combo := id if ":" in id else "r:" + id
	var info: Array = Synergies.entry(combo)
	if not camera.is_position_behind(at): ui.word(camera.unproject_position(at), info[0], info[4])
	if combo.begins_with("r:") and Run.discover(combo):
		ui.notify("New reaction · %s" % info[0], info[2], info[4])

## A heal a pairing pays to whoever earned it (this player, or a teammate).
func heal_player(owner: int, amount: float) -> void:
	if owner == 0 or owner == Session.local_peer_id: Run.heal(amount)
	else: party.tell(owner, "heal", amount)

## Announces the pairings and resonance a relic or spellbook brings.
func announce_combinations(relic := "") -> void:
	var element := Synergies.weapon_element(Run.weapon())
	for id in Synergies.pairings_for(Run.inventory):
		if relic != "" and relic not in [Synergies.PAIRINGS[id][0], Synergies.PAIRINGS[id][1]]: continue
		if relic != "" and Run.inventory.count(relic) > 1: continue
		Run.discover("p:" + id)
		var pairing: Array = Synergies.entry("p:" + id)
		ui.notify("Pairing · %s" % pairing[0], pairing[2], pairing[4])
		return
	if element != "" and Synergies.resonance(Run.inventory, element) > 0 and (relic == "" or Synergies.resonates(relic, element)):
		var first := Run.discover("e:" + element)
		var resonance: Array = Synergies.entry("e:" + element)
		if first or relic == "": ui.notify("Resonance · %s" % resonance[0], resonance[2], resonance[4])

## This player's share of a fallen foe: the kill's warmth and, once per foe,
## their own drops.
func award_kill(event: Dictionary) -> void:
	var at: Vector3 = event.at if event.get("at") is Vector3 else Vector3.ZERO
	if not bool(event.get("inert", false)): stoke()
	if bool(event.get("boss", false)):
		hitstop = .11
		shake = .3
		ScreenFx.wave(at, 7.0, 1.6)
	if not bool(event.get("inert", false)) and is_instance_valid(player): kill_pairings(at)
	if not bool(event.get("loot", false)) or not is_instance_valid(room): return
	Run.kills += 1
	var drops = Drops.roll("boss" if bool(event.get("boss", false)) else "enemy_common", Run.rng, Run.stats.luck, Run.coin_bonus())
	for i in drops.size():
		spawn_pickup(Drops.scatter(drops.size(), i, at), drops[i].def)

func spawn_pickup(at: Vector3, pickup_id: String, amount := -1.0, restored_id := "") -> DungeonPickup:
	var definition = Content.record("pickups", pickup_id)
	if definition.is_empty():
		push_warning("Unknown pickup '%s' was not spawned." % pickup_id)
		return null
	var safe = room.geometry.safe_point(Vector2(at.x, at.z), .3)
	var pickup = DungeonPickup.new()
	scene_root.add_child(pickup)
	pickup.setup(self, Vector3(safe.x, room.floor_height(Vector3(safe.x, at.y, safe.y)) if first_person else 0.0, safe.y), pickup_id, amount)
	if restored_id.is_empty():
		pickup.drop_id = Run.add_drop(Run.current_room, pickup_id, safe, pickup.value,pickup.position.y)
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

## The map takes in a whole room the moment the player steps into it, every
## cell scribbled in together under one soft pass of the quill. A safe room
## keeps it at once; in a fight, the room's own save at the end keeps it.
func track_exploration() -> void:
	var local = room.geometry.cell_at(Vector2(player.position.x, player.position.z))
	if not room.geometry.cell_set.has(local): return
	var anchor: Vector2i = Run.room_anchor(Run.rooms[Run.current_room])
	var fresh := false
	for each in room.geometry.cells:
		var cell: Vector2i = each + anchor
		if Run.uncover(cell):
			ui.scribble(cell)
			fresh = true
	if not fresh: return
	Audio.play_sound("scribble", randf_range(.95, 1.03))
	if room.open: Run.save_run()

## The room's stair (or stairwell) spot. Rooms generated before the stairs
## existed find one now, clear of their saved furniture, and keep it.
func stair_spot(data: Dictionary, key: String) -> Vector2:
	if not data.has(key):
		var zones = FloorGenerator.reserved_zones({"portals": Run.portals}, data)
		var blockers = room.obstacles.map(func(obstacle): return obstacle.rect)
		data[key] = FloorGenerator.point_array(Staircase.find_spot(room.geometry, zones, Vector2(room.pedestal.x, room.pedestal.z), blockers))
	return FloorGenerator.vec2(data[key])

func raise_stairs(animated: bool) -> void:
	var spot = stair_spot(Run.rooms[Run.current_room], "stairs")
	stairs = Staircase.new()
	scene_root.add_child(stairs)
	stairs.position = Vector3(spot.x, 0, spot.y)
	stairs.setup(Vector2(room.pedestal.x, room.pedestal.z), not animated)
	if stairs.built: stairs_ready(false)

func stairs_ready(announce: bool) -> void:
	stairs.make_solid()
	room.add_obstacle("stairs", Vector2(stairs.position.x, stairs.position.z), Staircase.OUTER)
	interactions.register("stairs", "exit", stairs.approach_point(), 2.1, "", stairs)
	if announce:
		if Run.last_floor(): ui.notify("The last stair", "It climbs out into the light.", Color("f3dfb8"))
		else: ui.notify("A stair winds upward", "Climb it toward the light above.", Color("f3dfb8"))

## Assembly is scenery on the ordinary simulation clock, not a transition.
## Keep input, timers and actions live; add solid collision only once the
## player has cleared the stair's footprint, even on its final build tick.
func advance_stair_assembly(delta: float) -> void:
	if not is_instance_valid(stairs) or interactions.targets.has("stairs"): return
	ease_from_stairs(delta)
	stairs.advance(delta)
	var away := Vector2(player.position.x-stairs.position.x,player.position.z-stairs.position.z)
	if stairs.built and away.length() >= Staircase.OUTER+.4:
		stairs_ready(true)

## Gently clear the assembling stair without taking ownership of movement.
func ease_from_stairs(delta: float) -> void:
	var away = Vector2(player.position.x - stairs.position.x, player.position.z - stairs.position.z)
	var room_needed = Staircase.OUTER + .5 - away.length()
	if room_needed <= 0: return
	var direction = away.normalized() if away.length() > .01 else Vector2(0, 1)
	var moved = direction * minf(room_needed, 6.0 * delta)
	var motion := Vector3(moved.x, 0, moved.y)
	if first_person: player.move_and_collide(motion)
	else: player.position += motion

func clear_room() -> void:
	var data: Dictionary = Run.rooms[Run.current_room]
	if data.cleared: return
	# Every player's own rewards follow on their own device.
	party.share("clear", Run.current_room)
	trials.on_room_cleared()
	room.set_open(true)
	# New expeditions persist clear credit and its reward together, so a
	# reload cannot lose or duplicate the chest/relic between two writes.
	Run.mark_cleared(not ExpeditionBalance.active_new_run())
	# Lanterns relit or put out in the fight stay that way.
	if room.lanterns_changed: data["lit"] = room.burning_indices()
	Audio.play_sound("door", 1.3)
	ui.notify("A little more warmth", "The doorways are open.")
	if data.type == "boss":
		# The exit assembles in the background while the player keeps control.
		raise_stairs(true)
	# Hearthkeeper: a ward for every room won.
	if Run.has_pairing("hearthkeeper"):
		Run.wards += 1
		Run.changed.emit()
	if ExpeditionBalance.active_new_run():
		resolve_expedition_clear(data)
	elif data.type == "boss" or Run.cleared % 2 == 0:
		ensure_offers(data.type == "boss")
		make_marker("treasure", room.pedestal)
	else:
		data.claimed = true
		for drop in Drops.roll("room_clear", Run.rng, Run.stats.luck):
			spawn_pickup(room.pedestal, drop.def)
	Run.save_run()

func resolve_expedition_clear(data: Dictionary) -> void:
	if data.get("clear_reward_paid",false): return
	if not data.has("clear_reward"):
		if data.type == "boss": data["clear_reward"] = "boss_relic"
		elif room.terrain and room.terrain.challenge(): data["clear_reward"] = "chest"
		elif ExpeditionBalance.combat_relic_due(data,Run.rooms): data["clear_reward"] = "relic"
		else: data["clear_reward"] = "supplies"
	match data.clear_reward:
		"boss_relic", "relic":
			ensure_offers(data.type=="boss",false)
			make_marker("treasure",room.pedestal)
		"chest":
			var at: Vector3 = room.terrain.reward_point()
			# Do not materialize solid loot around the player's capsule.
			for offset in [Vector2.ZERO,Vector2(-1.1,-.9),Vector2(1.1,-.9),Vector2(-1.1,.9),Vector2(1.1,.9)]:
				var candidate := at + Vector3(offset.x,0,offset.y)
				var flat := Vector2(candidate.x,candidate.z)
				if not room.terrain.ledge.grow(-.55).has_point(flat) or room.blocked_at(flat): continue
				if Vector2(player.position.x,player.position.z).distance_to(flat)<1.25: continue
				at=candidate
				break
			var chest: Dictionary = actions.award_clear_chest(data,at)
			if not chest.is_empty():
				make_chest_view(chest)
				room.add_obstacle(str(chest.id),Vector2(at.x,at.z),.55,at.y)
				refresh_items()
				ui.notify("A chest earned", "The chamber's supplies are yours.")
			data.claimed=true
		_:
			data.claimed=true
			for drop in Drops.roll("room_clear",Run.rng,Run.stats.luck): spawn_pickup(room.pedestal,drop.def)
	data["clear_reward_paid"]=true

func ensure_offers(premium := false, persist := true) -> void:
	var data: Dictionary = Run.rooms[Run.current_room]
	if data.has("offers"):
		data.offers = ExpeditionBalance.sanitize_offers(data.offers,int(data.seed))
		return
	var gen = RandomNumberGenerator.new()
	# In co-op each player is offered their own pick.
	gen.seed = int(data.seed) + 991 + party.loot_salt()
	var items = Content.roll_items(gen, 3, Run.inventory, premium, Run.stats.luck)
	var offers: Array = []
	for item in items:
		# Fewer, stronger relics are dearer at the merchant too.
		var price: int = {"common": 12, "uncommon": 18, "rare": 26, "mythic": 36}[item.rarity]
		offers.append({"kind": "item", "id": item.id, "price": price})
	if gen.randf() < .5 or data.type == "shop":
		# Every weapon on offer is forged here, for this room alone.
		offers[2] = {"kind": "weapon", "id": Forge.id_for(Content.stable_hash("shop:%d:%s" % [Run.seed_value + party.loot_salt(), data.id]), gen.randi_range(0, 99)), "price": 14}

	data.offers = offers
	if persist: Run.save_run()

func make_marker(kind: String, at := Vector3.ZERO) -> void:
	if marker and is_instance_valid(marker): marker.queue_free()
	marker_visual = null
	death_figure = null
	marker = Node3D.new()
	scene_root.add_child(marker)
	marker.position = at
	marker.set_meta("kind", kind)
	if kind == "exit":
		Geo.ring(marker, Vector3(0, .09, 0), 1.05, Color("a3d5c2"), .09)
		Geo.halo(marker, Vector3(0, .02, 0), 5.0, Color(.35, .8, .6, .32))
		Geo.light(marker, Vector3(0, .6, 0), Color("a7d8bd"), .65, 3.5)
	elif kind == "dark":
		var altar_body = Geo.box(marker, Vector3(0, .35, 0), Vector3(1.1, .7, .8), Color("1e1a22"))
		var altar_cap = Geo.box(marker, Vector3(0, .74, 0), Vector3(1.3, .08, 1.0), Color("3a2a3e"))
		if first_person:
			altar_body.material_override = DungeonStyle.wall_material(Color("37303e"))
			altar_cap.material_override = DungeonStyle.wall_material(Color("4f4053"),true)
		# A small cold flame, low enough not to hide Death behind it.
		var flame = Geo.sphere(marker, Vector3(0, .94, 0), .11, Color("9b74c9"), 1.3)
		flame.scale = Vector3(.8, 1.5, .8)
		marker_visual = flame
		Geo.halo(marker, Vector3(0, .03, 0), 4.5, Color(.55, .3, .8, .3))
		Geo.light(marker, Vector3(0, 1.4, 0), Color("b98ae0"), .9, 5.0)
		# Death waits behind the altar, on the side away from the way in.
		death_figure = DeathFigure.new()
		marker.add_child(death_figure)
		var away: Vector3 = at - player.position if is_instance_valid(player) else Vector3.FORWARD
		away.y = 0
		death_figure.position = (away.normalized() if away.length_squared() > .01 else Vector3.FORWARD) * 1.3
		death_figure.rotation.y = atan2(-away.x, -away.z)
		death_figure.setup(self)
	elif kind == "rest":
		var rest_base = Geo.cylinder(marker, Vector3(0, .2, 0), .65, .4, Color("86775f"))
		if first_person: rest_base.material_override = DungeonStyle.wall_material(Color("86775f"))
		Geo.sphere(marker, Vector3(0, .75, 0), .25, Color("ffd28d"), 1.8)
		Geo.halo(marker, Vector3(0, .03, 0), 4, Color(1, .6, .2, .3))
	else:
		# A relic waits in a reliquary; the merchant's wares glow cooler.
		marker_visual = Reliquary.build(marker, Color("ffc874") if kind == "treasure" else Color("9fd8c4"), first_person)
		Geo.halo(marker, Vector3(0, .03, 0), 4, Color(1, .65, .22, .22))
	if first_person:
		for child in marker.get_children():
			if child is MeshInstance3D and child.material_override is ShaderMaterial and child.material_override.shader == preload("res://shaders/halo.gdshader"):
				child.visible = false
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
		"dark": return "Bargain with Death"
		"rest": return "Warm your hands · heal %d" % (1 if ExpeditionBalance.active_new_run() else 3)
		"exit":
			if party.climbing(): return "Waiting for the party…" if party.waiting_at_stair else "Climb with the party"
			return "Carry the light home" if Run.last_floor() else "Climb to the next floor"
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
	if first_person:
		var point: Vector3 = target.position + Vector3.UP * (.9 if target.kind != "painting" else 1.3)
		if target.kind == "painting" and is_instance_valid(target.get("node")):
			point = target.node.global_position
		var view: Vector3 = point - camera.global_position
		if view.length() > .15 and fps.forward().dot(view.normalized()) < .65: return false
		var ray = PhysicsRayQueryParameters3D.create(camera.global_position, point, 1 | PropVisuals.FURNITURE_LAYER)
		# The object's own chest/altar collider must not hide its prompt.
		var own: Node = target.get("node")
		var ignored: Array[RID] = []
		if is_instance_valid(own):
			if own is CollisionObject3D: ignored.append(own.get_rid())
			for body in own.find_children("*", "CollisionObject3D", true, false): ignored.append(body.get_rid())
		ray.exclude = ignored
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return false
	var from = Vector2(player.position.x, player.position.z)
	var to = Vector2(target.position.x, target.position.z)
	for step in 6:
		if not room.geometry.contains(from.lerp(to, step / 5.0)): return false
	return true

func update_interaction() -> void:
	if in_transition() or trials.spectating():
		interaction_text = ""
		interaction_kind = ""
		return
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
		"dark": open_bargain()
		"treasure", "shop":
			ensure_offers(data.type == "treasure")
			chosen_reward_shop = target.kind == "shop"
			chosen_reward_dark = false
			ui.offers = data.offers
			ui.shop = chosen_reward_shop
			ui.dark = false
			paused = true
			ui.show_screen("reward")
		"rest":
			# The hearth's marker is the gate: it is removed once used.
			var restored := 1.0 if ExpeditionBalance.active_new_run() else 3.0
			Run.heal(restored)
			data.claimed = true
			remove_marker()
			Run.save_run()
			Audio.play_sound("item")
			ui.notify("A moment of warmth", "Recovered %d health." % restored)
		"exit":
			if not is_instance_valid(stairs) or not stairs.built:
				return GameActions.result(false, "the stair is still rising")
			# The party climbs together, once everyone standing is at the stair.
			if party.climbing(): return party.at_the_stair()
			begin_climb()
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
	if not data.has("offers"): return
	data.offers = ExpeditionBalance.sanitize_offers(data.offers,int(data.seed))
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
		ui.notify(Forge.lookup(offer.id).name, "A new way to carry the light.")
		Audio.play_sound("item")
		announce_combinations()
	elif offer.kind == "active":
		# The new item goes into the slot; the one in hand is set beside the
		# pedestal, keeping its instance and its running cooldown.
		var item_id = Run.next_instance("a")
		if not data.has("items"): data.items = []
		data.items.append({"id": item_id, "def": offer.id, "position": [snappedf(player.position.x, .001), snappedf(player.position.z, .001)]})
		actions.take_item(item_id)
	else:
		Run.gain_item(offer.id)
	if data.claimed: remove_marker()
	Run.save_run()
	close_reward()

func game_shake_dark() -> void:
	shake = maxf(shake, .12)
	Effects.burst(scene_root, player.global_position + Vector3.UP * .8, Color("b98ae0"), 12, 1.4)

## Death rises behind its altar.
func death_rises(figure: DeathFigure) -> void:
	Audio.play_sound("door", .45)
	Effects.play("death_puff", figure.global_position + Vector3.UP * .4, DeathBargain.COLOR, 14, 1.6)

## Death's bargain: one thing from its right hand, paid for with its left.
func open_bargain() -> void:
	var data: Dictionary = Run.rooms[Run.current_room]
	if data.claimed: return
	ensure_dark_offers()
	if is_instance_valid(death_figure):
		death_figure.appear()
		# Face Death across its altar.
		if first_person and fps:
			var towards: Vector3 = death_figure.global_position - player.global_position
			if towards.length_squared() > .01: fps.yaw = atan2(-towards.x, -towards.z)
	chosen_reward_shop = false
	chosen_reward_dark = true
	ui.offers = data.offers
	ui.bargain_pick = -1
	ui.bargain_price = ""
	paused = true
	ui.show_screen("bargain")

## Seals one bargain per altar: what is taken is the player's at once; the
## price is a curse now, or a trial that holds the curse back.
func seal_bargain(index: int, price: String) -> Dictionary:
	var data: Dictionary = Run.rooms[Run.current_room]
	if data.type != "dark" or data.claimed or not data.has("offers"): return GameActions.result(false, "no bargain here")
	if index < 0 or index >= data.offers.size() or price not in ["curse", "trial"]: return GameActions.result(false, "no such bargain")
	# Death faces one challenger at a time.
	var other: int = party.challenger()
	if price == "trial" and other != 0 and other != Session.local_peer_id and str(data.offers[index].get("trial", "")) in DeathBargain.AT_ONCE:
		ui.notify("Death is busy", "Wait until %s's trial is done." % Session.name_of(other), DeathBargain.COLOR)
		return GameActions.result(false, "another trial is under way")
	var offer: Dictionary = data.offers[index]
	data.claimed = true
	offer["sealed"] = price
	interactions.unregister(PEDESTAL_ID)
	if is_instance_valid(death_figure): death_figure.vanish()
	if is_instance_valid(marker_visual): marker_visual.visible = false
	close_reward()
	game_shake_dark()
	if offer.kind == "weapon":
		Run.weapon_id = offer.id
		Run.changed.emit()
		announce_combinations()
	else:
		Run.gain_item(offer.id)
	var taken: String = Forge.lookup(offer.id).name if offer.kind == "weapon" else Content.item_by_id[offer.id].name
	if price == "curse":
		Run.add_curse(offer.curse)
		ui.notify("%s · %s" % [taken, DeathBargain.curse_name(offer.curse)], DeathBargain.curse_text(offer.curse) + " For the rest of the run.", DeathBargain.COLOR)
		Audio.play_sound("hurt", .5)
		Run.save_run()
	else:
		trials.begin(str(offer.trial), offer.curse)
	return GameActions.result(true)

## Death's offers: a dark relic, a dark-forged spellbook or a precious relic,
## and a second dark relic. Each carries its terms: a curse as heavy as the
## offer is strong, and a trial (scripts/items/death_bargain.gd).
func ensure_dark_offers() -> void:
	var data: Dictionary = Run.rooms[Run.current_room]
	var gen = RandomNumberGenerator.new()
	gen.seed = int(data.seed) + 6661 + party.loot_salt()
	if data.has("offers"):
		data.offers = ExpeditionBalance.sanitize_offers(data.offers,int(data.seed))
		# Offers saved by the old dark store gain Death's terms.
		if data.offers.any(func(offer): return not offer.has("curse")):
			gen.seed = int(data.seed) + 6662 + party.loot_salt()
			for offer in data.offers: DeathBargain.terms(offer, gen)
		return
	var dark: Array = Content.items.filter(func(item): return item.rarity == "dark")
	var relic: Dictionary = dark[gen.randi_range(0, dark.size() - 1)]
	var offers: Array = [{"kind": "item", "id": relic.id, "price": int(relic.cost)}]
	if gen.randf() < .55:
		offers.append({"kind": "weapon", "id": Forge.id_for(Content.stable_hash("dark:%d:%s" % [Run.seed_value, data.id]), gen.randi_range(0, 99), 1), "price": 4})
	else:
		var precious: Dictionary = Content.roll_items(gen, 1, Run.inventory, true, Run.stats.luck)[0]
		offers.append({"kind": "item", "id": precious.id, "price": {"common": 2, "uncommon": 2, "rare": 3, "mythic": 4}[precious.rarity]})
	var others: Array = dark.filter(func(item): return item.id != relic.id)
	var second: Dictionary = others[gen.randi_range(0, others.size() - 1)]
	offers.append({"kind": "item", "id": second.id, "price": int(second.cost)})
	for offer in offers: DeathBargain.terms(offer, gen)
	data.offers = offers
	Run.save_run()

func close_reward() -> void:
	paused = false
	ui.show_screen("play")

func add_item_record(definition_id: String, at: Vector3) -> void:
	var data: Dictionary = Run.rooms[Run.current_room]
	if not data.has("items"): data.items = []
	data.items.append({"id": Run.next_instance("a"), "def": definition_id, "position": [snappedf(at.x, .001), snappedf(at.z, .001)], "height": at.y if first_person else 0.0})
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
		if first_person: view.position.y = float(record.get("height", room.floor_height(view.position)))
		item_views[record.id] = view
		interactions.register("item:" + record.id, "item", view.position, 1.6, "", view)
	for chest in data.get("chests", []):
		if chest.opened: continue
		var at = Vector3(float(chest.position[0]), 0, float(chest.position[1]))
		if first_person: at.y = float(chest.get("height",room.floor_height(at)))
		interactions.register("chest:" + chest.id, "chest", at, 1.9, "", chest_views.get(chest.id))

func make_chest_view(chest: Dictionary) -> Node3D:
	if chest_views.has(chest.id) and is_instance_valid(chest_views[chest.id]): return chest_views[chest.id]
	var view := ItemViews.chest(scene_root,chest)
	if first_person: view.position.y = float(chest.get("height",room.floor_height(view.position)))
	chest_views[chest.id] = view
	return view

func chest_opened(chest: Dictionary) -> void:
	interactions.unregister("chest:" + chest.id)
	if chest_views.has(chest.id): ItemViews.set_open(chest_views[chest.id])
	var at = Vector3(float(chest.position[0]), .7 + float(chest.get("height",0)), float(chest.position[1]))
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
			party.share("portal", [portal_id, "revealed"])
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
	# Broken for everyone; each player gets their own drops from it.
	party.share("prop", [room_id, record.id])
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
	# A pairing completed or a resonance found outshines the relic's own line.
	announce_combinations(item.id)

func redeem_secret_code(code: String) -> bool:
	if not Run.active or in_menu:
		return false
	var wish = code.strip_edges().to_upper()
	if wish == Run.ALL_RELICS_CODE: wish_all_relics()
	elif wish == Run.PAINT_SPRAYER_CODE: wish_paint_sprayer()
	else: return false
	Audio.play_sound("item")
	return true

func wish_all_relics() -> void:
	var added = Run.grant_all_relics()
	if added > 0 and player and is_instance_valid(player):
		player.refresh_orbitals()
		player.shield = maxi(player.shield, int(Run.stats.shield))
	if added > 0:
		ui.notify("Every little light, all at once", "%d relics awakened. You carry all %d." % [added, Content.items.size()])
	else:
		ui.notify("Every little light is already yours", "You already carry all %d relics." % Content.items.size())

## Skips the twelve paintings: the weapon is in hand now and on the starting
## rack from now on. The journal's own progress is left as it was.
func wish_paint_sprayer() -> void:
	if Run.grant_weapon("paint_sprayer"):
		ui.notify("Paint Sprayer in hand", "Red, blue, green. Choose it when you begin any run.", Color("e7d9c8"))
	else:
		ui.notify("The Paint Sprayer is already yours", "It is in your hands and on the starting rack.", Color("e7d9c8"))

func pause_game() -> void:
	if not Run.active or in_menu: return
	paused = true
	if first_person: Run.save_run()
	ui.show_screen("pause")

func resume_game() -> void:
	paused = false
	ui.show_screen("play")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func return_to_title() -> void:
	if Run.active and Run.rooms[Run.current_room].cleared:
		Run.save_run()
	Run.active = false
	if Session.online:
		# Leaving a co-op climb leaves its party; a host's leaving ends it.
		Session.leave_party()
		party.reset()
	show_title_room()
	ui.show_screen("menu")

func end_run(won: bool) -> void:
	stair_cinematic.cancel(self)
	transition = {}
	if light_veil: light_veil.color.a = 0.0
	if party.climbing(): party.ended()
	Run.finish(won)
	paused = true
	ui.show_screen("won" if won else "dead")

func reset_combat() -> void:
	hitstop = 0.0
	sparks = 0
	kindle_heat = 0.0
	kindle_quiet = 0.0
	noises.clear()

func kindle_level() -> int:
	var level = 0
	for step in KINDLE_STEPS:
		if kindle_heat >= step: level += 1
	return level

func kindle_damage() -> float:
	return KINDLE_DAMAGE[kindle_level()]

## How far the player's own light reaches: it grows with the kindle.
func player_light_radius() -> float:
	return PLAYER_LIGHT + kindle_level()

## A kill feeds the flame.
func stoke() -> void:
	var before = kindle_level()
	kindle_heat = minf(kindle_heat + 1.0, 12.0)
	kindle_quiet = 0.0
	if kindle_level() > before and is_instance_valid(player):
		Effects.ring_burst(scene_root, player.global_position, Color("ffcf7a"), 1.2 + kindle_level() * .4)
		Audio.play_sound("coin", 1.2 + kindle_level() * .1)

## A hit gutters it back to nothing.
func gutter() -> void:
	if kindle_heat <= 0: return
	kindle_heat = 0.0
	if is_instance_valid(player): Effects.play("death_puff", player.global_position + Vector3.UP * .9, Color("6a5a48"), 6)

## A hostile ember caught in a grazing dash.
func catch_spark(shot: EmberShot) -> void:
	dispel(shot)
	if sparks >= MAX_SPARKS: return
	sparks += 1
	Effects.play("pickup", shot.global_position, Color("fff3c4"))
	Audio.play_sound("coin", 1.5 + sparks * .08)

func make_noise(at: Vector3, loudness: float) -> void:
	# The host's foes hear a guest's casting and dashing too.
	party.world_noise(at, loudness)
	noises.append({"at": Vector3(at.x, 0, at.z), "loudness": loudness, "time": sim_time})
	while noises.size() > 12: noises.pop_front()

## The newest noise at least this loud, no older than `within` seconds.
func latest_noise(loudness := 1.0, within := 3.0) -> Dictionary:
	for i in range(noises.size() - 1, -1, -1):
		if sim_time - noises[i].time > within: break
		if noises[i].loudness >= loudness: return noises[i]
	return {}

## A shot through a dead lantern's glass lights it again.
func relight(index: int) -> void:
	if not room.set_lantern(index, true): return
	party.share("lamp", [index, true])
	make_noise(room.lanterns[index].at, 1.5)
	Audio.play_sound("item", 1.3)
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.alive: enemy.on_relight(index)
	save_lanterns()

func snuff(index: int) -> void:
	if not room.set_lantern(index, false): return
	party.share("lamp", [index, false])
	Audio.play_sound("door", .6)
	save_lanterns()

## In a room already won, the lanterns are kept as they are left.
func save_lanterns() -> void:
	var data: Dictionary = Run.rooms[Run.current_room]
	if not room.open: return
	data["lit"] = room.burning_indices()
	Run.save_run()

## A friendly shot that ended without striking a foe.
func shot_missed(shot: EmberShot) -> void:
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.alive: enemy.on_shot_missed(shot)

func get_boss() -> DungeonEnemy:
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.alive and enemy.boss: return enemy
	return null

func damage_number(at: Vector3, damage: float, critical: bool) -> void:
	if party.recording > 0: party.share("dmg", [at, damage, critical])
	if camera.is_position_behind(at): return
	ui.damage_number(camera.unproject_position(at), damage, critical)
