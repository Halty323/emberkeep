extends Node3D
var room: DungeonRoom
var camera: Camera3D
var player: Adventurer
var ui: GameInterface
var scene_root: Node3D
var marker: Node3D
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
var entity_counter = 10
var chosen_reward_shop = false
var snapshot_timer = 0.0
var vignette: ShaderMaterial
var camera_home = Vector3(18, 23, 22)
var screen_right = Vector3(22, 0, -18).normalized()
var screen_down = Vector3(18, 0, 22).normalized()

func _ready() -> void:
	setup_inputs()
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("111d26")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9aaec2")
	env.ambient_light_energy = .36
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("223743")
	env.fog_density = .004
	env.fog_sky_affect = 0
	environment.environment = env
	add_child(environment)
	var moon = DirectionalLight3D.new()
	moon.light_color = Color("aec9e2")
	moon.light_energy = .45
	moon.rotation_degrees = Vector3(-65, -35, 0)
	moon.shadow_enabled = true
	add_child(moon)
	camera = Camera3D.new()
	add_child(camera)
	camera.position = camera_home
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18.8
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
	get_tree().auto_accept_quit = false
	show_title_room()
	if "--quickstart" in OS.get_cmdline_user_args():
		start_run("candle", 421337, false)

func setup_inputs() -> void:
	var actions = {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"dash": [KEY_SPACE, KEY_SHIFT], "interact": [KEY_E], "pause_game": [KEY_ESCAPE, KEY_P], "journal": [KEY_TAB]}
	for action in actions:
		if not InputMap.has_action(action): InputMap.add_action(action)
		for key in actions[action]:
			var event = InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	var joy_actions = {"dash": JOY_BUTTON_RIGHT_SHOULDER, "interact": JOY_BUTTON_A, "pause_game": JOY_BUTTON_START}
	for action in joy_actions:
		var event = InputEventJoypadButton.new()
		event.button_index = joy_actions[action]
		InputMap.action_add_event(action, event)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and not in_menu and Run.active:
		if ui.mode == "play": pause_game()
		elif ui.mode == "pause": resume_game()
		elif ui.mode in ["journal", "settings"]: ui.close_subscreen()
	elif event.is_action_pressed("dash") and is_playing():
		request_dash = true
	elif event.is_action_pressed("interact") and is_playing():
		interact()
	elif event.is_action_pressed("journal") and is_playing():
		ui.open_journal("pause")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and is_playing():
		var p = ui.local_point(event.position)
		if Rect2(445, 580, 390, 58).has_point(p) and interaction_text != "":
			interact()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if is_instance_valid(ui) and is_playing():
			pause_game()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(ui) and not in_menu:
			if ui.mode == "play": pause_game()
			elif ui.mode == "pause": resume_game()
			elif ui.mode in ["settings", "journal"]: ui.close_subscreen()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()

func is_playing() -> bool:
	return Run.active and not paused and not in_menu

func screen_direction(value: Vector2) -> Vector3:
	return screen_right * value.x + screen_down * value.y

func _physics_process(delta: float) -> void:
	if not is_playing(): return
	if hitstop > 0:
		hitstop -= delta
		return
	sim_time += delta
	Run.elapsed += delta
	transition_cooldown -= delta
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
	elif not ui.touch_used and not OS.has_feature("android"):
		var mouse = get_viewport().get_mouse_position()
		var ray_origin = camera.project_ray_origin(mouse)
		var ray_direction = camera.project_ray_normal(mouse)
		var intersection = Plane(Vector3.UP, .65).intersects_ray(ray_origin, ray_direction)
		if intersection != null:
			aim = intersection - player.global_position - Vector3.UP * .65
			aim.y = 0
		shooting = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if request_dash:
		player.dash()
		request_dash = false
	player.update_sim(delta, move_input, aim, shooting)
	for enemy in enemies.duplicate():
		if is_instance_valid(enemy) and is_playing(): enemy.update_sim(delta)
	enemies = enemies.filter(func(e): return is_instance_valid(e) and e.alive)
	for shot in shots.duplicate():
		if is_instance_valid(shot) and is_playing(): shot.update_sim(delta)
	shots = shots.filter(func(s): return is_instance_valid(s) and s.alive)
	for pickup in pickups:
		if is_instance_valid(pickup): pickup.update_sim(delta)
	pickups = pickups.filter(func(p): return is_instance_valid(p) and not p.collected)
	if not Run.active: return
	if enemies.is_empty() and not room.open:
		clear_room()
	update_interaction()
	if room.open and transition_cooldown <= 0:
		check_doors()
	snapshot_timer -= delta
	if snapshot_timer <= 0:
		snapshot_timer = .1
		Session.publish({"player": {"id": player.entity_id, "owner": player.owner_peer_id, "position": [player.position.x, player.position.z], "hp": Run.hp},
			"room": Run.current_room, "seed": Run.seed_value, "floor": Run.floor_number})

func _process(delta: float) -> void:
	shake = maxf(0, shake - delta * .9)
	hurt_flash = maxf(0, hurt_flash - delta * 1.6)
	if camera:
		var amount = shake if Run.profile.shake else 0.0
		# Cosmetic motion never consumes the seeded gameplay RNG.
		camera.position = camera_home + Vector3(sin(Time.get_ticks_msec() * .081), cos(Time.get_ticks_msec() * .067), 0) * amount
	vignette.set_shader_parameter("hurt", hurt_flash)
	if marker and is_instance_valid(marker):
		marker.rotation.y += delta * .5

func clean_room() -> void:
	for shot in shots:
		if is_instance_valid(shot): shot.queue_free()
	for enemy in enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	for pickup in pickups:
		if is_instance_valid(pickup): pickup.queue_free()
	shots.clear()
	enemies.clear()
	pickups.clear()
	if scene_root:
		remove_child(scene_root)
		scene_root.queue_free()
	scene_root = Node3D.new()
	add_child(scene_root)
	marker = null
	interaction_text = ""
	interaction_kind = ""

func show_title_room() -> void:
	in_menu = true
	paused = true
	camera.h_offset = -4.5
	clean_room()
	room = DungeonRoom.new()
	scene_root.add_child(room)
	room.build(self, {"type": "start", "seed": 81}, true)
	player = Adventurer.new()
	scene_root.add_child(player)
	player.setup(self)
	player.position = Vector3(0, 0, .1)
	player.visual.rotation_degrees.y = 150
	make_marker("treasure", Vector3(2.3, 0, -1.5))

func start_run(weapon: String, seed_input: int, is_daily: bool) -> void:
	Run.start_run(weapon, seed_input, is_daily)
	in_menu = false
	paused = false
	camera.h_offset = 0
	sim_time = 0
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
	enter_room(Vector3(0, 0, 2.0))
	ui.show_screen("play")
	ui.notify("Welcome back, little light", "Your last safe room remembers you.")

func enter_room(spawn: Vector3) -> void:
	clean_room()
	var data: Dictionary = Run.rooms[Run.current_room]
	data.visited = true
	room = DungeonRoom.new()
	scene_root.add_child(room)
	room.build(self, data)
	player = Adventurer.new()
	scene_root.add_child(player)
	player.setup(self)
	player.position = spawn
	player.invulnerability = 1.0
	transition_cooldown = .9
	var gen = RandomNumberGenerator.new()
	gen.seed = int(data.seed)
	if not data.cleared and data.type in ["combat", "boss"]:
		room.set_open(false)
		if data.type == "boss":
			spawn_enemy(Vector3(0, 0, -2.5), "boss")
		else:
			var choices = ["mote", "spitter", "charger", "splitter", "brute"]
			var count = 3 + Run.floor_number + mini(int(data.depth) / 3, 2)
			for i in count:
				var p = Vector3(gen.randf_range(-6, 6), 0, gen.randf_range(-4, 4))
				if p.distance_to(spawn) < 3.0: p = -p
				for obstacle in room.obstacles:
					if p.distance_to(obstacle.position) < 1.6: p.z = 0
				var kind: String = choices[gen.randi_range(0, mini(choices.size() - 1, 2 + Run.floor_number))]
				spawn_enemy(p, kind)
	else:
		room.set_open(true)
		if not data.cleared:
			data.cleared = true
		# Recover a checkpoint written just after the boss died but before its
		# offers were generated. The room seed makes regeneration repeatable.
		if data.type == "boss" and not data.claimed and not data.has("offers"):
			ensure_offers(true)
		if not data.claimed and data.type in ["treasure", "shop", "rest"]:
			make_marker(data.type)
		elif data.cleared and not data.claimed and data.has("offers"):
			make_marker("treasure")
		elif data.type == "boss":
			make_marker("exit", Vector3(0, 0, -1.5))
		for drop in data.get("pickups", []):
			spawn_pickup(Vector3(drop.position[0], 0, drop.position[1]), drop.kind, int(drop.value), int(drop.id))
		Run.save_run()
	if data.type == "boss" and not data.cleared:
		ui.notify("The hearth is stirring", "Watch the windup. Dash through danger.", Color("e0a18b"))

func check_doors() -> void:
	var direction = Vector2i.ZERO
	if absf(player.position.x) > 8.15 and absf(player.position.z) < 1.1:
		direction = Vector2i(int(signf(player.position.x)), 0)
	elif absf(player.position.z) > 6.15 and absf(player.position.x) < 1.1:
		direction = Vector2i(0, int(signf(player.position.z)))
	if direction == Vector2i.ZERO: return
	var key = Run.room_key(Run.coord(Run.current_room) + direction)
	if Run.rooms.has(key):
		Run.current_room = key
		Audio.play_sound("door")
		enter_room(Vector3(-direction.x * 7.3, 0, -direction.y * 5.3))

func spawn_enemy(at: Vector3, kind: String) -> DungeonEnemy:
	var enemy = DungeonEnemy.new()
	scene_root.add_child(enemy)
	entity_counter += 1
	enemy.setup(self, kind, entity_counter)
	enemy.position = at
	enemies.append(enemy)
	return enemy

func spawn_shot(at: Vector3, direction: Vector3, damage: float, speed_value: float, stats: Dictionary, color: Color, friendly: bool) -> EmberShot:
	if shots.size() >= 200: return null
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

func on_enemy_killed(enemy: DungeonEnemy) -> void:
	var expected = 1.35 * (1.0 + Run.stats.coin_bonus)
	var amount = int(floor(expected)) + int(Run.rng.randf() < fposmod(expected, 1.0))
	if enemy.boss:
		amount = maxi(4, roundi(12 * (1.0 + Run.stats.coin_bonus)))
		hitstop = .11
		shake = .3
		for shot in shots:
			if is_instance_valid(shot) and not shot.friendly: shot.remove()
	for i in (4 if enemy.boss else 1):
		spawn_pickup(enemy.global_position + Vector3(sin(i * 2.4) * .4, 0, cos(i * 2.4) * .4), "coin", amount / 4 if enemy.boss else amount)
	if Run.rng.randf() < .10 + Run.stats.luck * .025:
		spawn_pickup(enemy.global_position + Vector3(.4, 0, -.3), "heart", 1)

func spawn_pickup(at: Vector3, kind: String, amount: int, restored_id := -1) -> void:
	var pickup = DungeonPickup.new()
	scene_root.add_child(pickup)
	pickup.setup(self, at, kind, amount)
	var data: Dictionary = Run.rooms[Run.current_room]
	if restored_id < 0:
		entity_counter += 1
		pickup.drop_id = entity_counter
		if not data.has("pickups"): data.pickups = []
		data.pickups.append({"id": pickup.drop_id, "kind": kind, "value": amount, "position": [at.x, at.z]})
	else:
		pickup.drop_id = restored_id
		entity_counter = maxi(entity_counter, restored_id)
	pickups.append(pickup)

func clear_room() -> void:
	room.set_open(true)
	Run.mark_cleared()
	var data: Dictionary = Run.rooms[Run.current_room]
	Audio.play_sound("door", 1.3)
	ui.notify("A little more warmth", "The doorways are open.")
	if data.type == "boss" or Run.cleared % 2 == 0:
		ensure_offers(data.type == "boss")
		make_marker("treasure")
	else:
		data.claimed = true
		if Run.rng.randf() < .4: spawn_pickup(Vector3.ZERO, "heart", 1)
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
		var weapon: Dictionary = Content.weapons[gen.randi_range(0, Content.weapons.size() - 1)]
		offers[2] = {"kind": "weapon", "id": weapon.id, "price": 14}
	data.offers = offers
	Run.save_run()

func make_marker(kind: String, at := Vector3.ZERO) -> void:
	if marker and is_instance_valid(marker): marker.queue_free()
	marker = Node3D.new()
	scene_root.add_child(marker)
	marker.position = at
	marker.set_meta("kind", kind)
	if kind == "exit":
		Geo.ring(marker, Vector3(0, .09, 0), 1.05, Color("a3d5c2"), .09)
		Geo.halo(marker, Vector3(0, .02, 0), 5.0, Color(.35, .8, .6, .32))
		Geo.light(marker, Vector3(0, .6, 0), Color("a7d8bd"), 1.3, 4.0)
	elif kind == "rest":
		Geo.cylinder(marker, Vector3(0, .2, 0), .65, .4, Color("86775f"))
		Geo.sphere(marker, Vector3(0, .75, 0), .25, Color("ffd28d"), 1.8)
		Geo.halo(marker, Vector3(0, .03, 0), 4, Color(1, .6, .2, .3))
	else:
		Geo.cylinder(marker, Vector3(0, .22, 0), .5, .44, Color("656454"))
		var relic = Geo.box(marker, Vector3(0, 1.0, 0), Vector3(.43, .43, .43), Color("d4b580") if kind == "treasure" else Color("a9c4ad"), .7)
		relic.rotation_degrees = Vector3(45, 35, 30)
		Geo.ring(marker, Vector3(0, .035, 0), .95, Color("d9b97a"), .035)
		Geo.halo(marker, Vector3(0, .03, 0), 4, Color(1, .65, .22, .22))
		Geo.light(marker, Vector3(0, 1.5, 0), Color("f0c68c"), 1.2, 4.0)

func update_interaction() -> void:
	interaction_text = ""
	interaction_kind = ""
	if marker and is_instance_valid(marker) and player.position.distance_to(marker.position) < 2.1:
		interaction_kind = marker.get_meta("kind")
		interaction_text = {"treasure": "Choose a little treasure", "shop": "Browse the merchant’s wares", "rest": "Warm your hands · heal 3", "exit": "Carry the light home" if Run.floor_number == 3 else "Descend to the next floor"}.get(interaction_kind, "")

func interact() -> void:
	if not is_playing() or interaction_kind == "": return
	var data: Dictionary = Run.rooms[Run.current_room]
	match interaction_kind:
		"treasure", "shop":
			ensure_offers(data.type == "treasure")
			chosen_reward_shop = interaction_kind == "shop"
			ui.offers = data.offers
			ui.shop = chosen_reward_shop
			paused = true
			ui.show_screen("reward")
		"rest":
			Run.heal(3)
			data.claimed = true
			marker.queue_free()
			marker = null
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
	update_interaction()

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
	else:
		Run.gain_item(offer.id)
	if marker and is_instance_valid(marker): marker.queue_free()
	marker = null
	if data.type == "boss": make_marker("exit", Vector3(0, 0, -1.5))
	Run.save_run()
	close_reward()

func close_reward() -> void:
	paused = false
	ui.show_screen("play")
	if Run.rooms[Run.current_room].type == "boss" and not Run.rooms[Run.current_room].claimed:
		# Reward remains on its pedestal until selected; descending requires choosing.
		pass

func on_item_gained(item: Dictionary) -> void:
	if player and is_instance_valid(player): player.refresh_orbitals()
	Audio.play_sound("item")
	ui.notify(item.name, item.description, Content.RARITY_COLORS[item.rarity])

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
