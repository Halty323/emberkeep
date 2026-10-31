extends SceneTree
var checks := 0
var failures := 0
var game

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("exercise")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func exercise() -> void:
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_run("candle", 64217, false)
	await frames(20)
	game.update_camera(.016)
	check(game.first_person and game.fps != null, "first-person gameplay is the default")
	check(game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "game camera uses perspective")
	check(absf(game.camera.global_position.y - game.player.global_position.y - 1.5) < .04, "eye is at capsule head height")
	check(not game.player.visual.visible, "local body does not obscure the view")
	check(game.player.is_on_floor(), "player settles onto a physical floor")
	check(game.player.get_child(0).shape is CapsuleShape3D, "player uses upright capsule collision")
	game.fps.look(Vector2(0, -1000))
	check(game.fps.pitch <= deg_to_rad(85) and game.fps.forward().y > .9, "pitch is clamped without flattening vertical aim")
	game.fps.pitch = 0
	game.fps.yaw = 0
	var origin: Vector3 = game.player.position
	Input.action_press("move_up")
	await frames(15)
	Input.action_release("move_up")
	check(game.player.position.z < origin.z - .5, "forward movement follows camera yaw")
	game.fps.jump_buffer = .14
	var floor_y: float = game.player.position.y
	await frames(15)
	check(game.player.position.y > floor_y + .45, "jump rises above the floor")
	await frames(55)
	check(absf(game.player.position.y - floor_y) < .12, "gravity returns player to floor")
	game.fps.yaw = PI / 2
	var turned = game.screen_direction(Vector2(0, -1))
	check(turned.x < -.95, "movement basis rotates with view")
	game.fps.pitch = .65
	game.player.aim_direction = game.fps.forward()
	var shot_count: int = game.shots.size()
	game.player.fire_cooldown = 0
	game.player.fire()
	check(game.shots.size() > shot_count and absf(game.shots[-1].direction.y) > .3, "weapon volleys retain vertical aim")
	game.paused = true
	var remaining: float = game.player.dash_cooldown
	await frames(3)
	check(game.player.dash_cooldown == remaining, "pause holds movement timers")
	check(not settings.set_value("fov", 150), "comfort FOV rejects unsupported values")
	check(settings.set_value("fov", 85), "comfort FOV accepts a supported value")
	game.paused = false
	game.update_camera(.016)
	check(game.camera.fov == 85, "FOV reaches the perspective camera")
	run.view_angles = [1.2, .3]
	run.save_run()
	check(run.load_run() and run.view_angles == [1.2, .3], "view direction persists in versioned saves")
	var eligible_rooms = 0
	var raised_rooms = 0
	for seed_value in [64217, 81031, 52043]:
		game.start_run("candle", seed_value, false)
		for id in run.rooms:
			var data: Dictionary = run.rooms[id]
			if data.type != "combat" or data.cells.size() < 2: continue
			eligible_rooms += 1
			run.current_room = id
			game.enter_room(Vector3(0, 0, 2))
			if game.room.terrain and game.room.terrain.ledge.has_area(): raised_rooms += 1
			await process_frame
	print("FIRST PERSON GENERATED TERRAIN: ", raised_rooms, " raised / ", eligible_rooms, " eligible rooms")
	check(raised_rooms > 0, "furnished generated rooms actually include raised galleries")
	# A validated raised gallery remains reachable and stable after room rebuilds.
	var generator = load("res://scripts/dungeon/floor_generator.gd")
	var content = root.get_node("Content")
	var floor_data = {"rooms": {}, "portals": {}, "owners": {}, "generator": 2}
	generator.place_room(floor_data, content.record("rooms", "hall_2x1"), 0, Vector2i.ZERO, 472, 1)
	run.rooms = floor_data.rooms
	run.portals = {}
	run.current_room = "0,0"
	var record: Dictionary = run.rooms[run.current_room]
	record.type = "combat"
	record.cleared = true
	record.claimed = true
	record.props = []
	record.chests = []
	record.items = []
	game.enter_room(Vector3(0, 0, 2))
	var terrain = game.room.terrain
	check(terrain != null and terrain.ledge.has_area(), "multi-cell arena can build a raised gallery")
	if terrain and terrain.ledge.has_area():
		var top: Vector2 = terrain.ledge.get_center()
		var bottom = Vector2(terrain.ramp.get_center().x, terrain.ramp.end.y - .5)
		check(game.room.navigation(.45).reachable(bottom, top), "navigation reaches the gallery through its ramp")
		check(absf(terrain.height(top) - 1.2) < .01, "gallery has real elevation")
		var blueprint = JSON.stringify(record.fps_terrain)
		game.player.place(Vector3(top.x, 1.28, top.y))
		await frames(12)
		check(absf(game.player.position.y - 1.2) < .15, "player capsule stands on the raised collision surface")
		var pickup = game.spawn_pickup(Vector3(top.x, 1.2, top.y), "copper_coin")
		check(absf(pickup.position.y - 1.2) < .01, "drops rest on the raised gallery")
		game.enter_room(Vector3(0, 0, 2))
		check(game.pickups.any(func(drop): return absf(drop.position.y - 1.2) < .01), "gallery loot restores above its physical floor")
		check(JSON.stringify(record.fps_terrain) == blueprint, "re-entering a room preserves the terrain blueprint")
	# Every forged firing pattern can produce 3D shots without losing its stats.
	game.fps.pitch = .4
	game.player.aim_direction = game.fps.forward()
	var forge = load("res://scripts/items/forge.gd")
	for slot in 20:
		var weapon = forge.lookup(forge.id_for(42013, slot))
		var count: int = game.player.volley(weapon, run.projectile_stats(), 3.0, Color(weapon.color))
		check(count > 0, "forged pattern fires in first person: " + str(slot))
	# Independent touch ownership: move/look remain held while firing/jumping.
	var touch_points = [Vector2(200, 500), Vector2(800, 300), Vector2(1178, 552), Vector2(1178, 660)]
	for index in 4:
		var touch = InputEventScreenTouch.new()
		touch.index = 10 + index
		touch.pressed = true
		touch.position = touch_points[index] * game.ui.scale_value + game.ui.offset
		game.ui._input(touch)
	check(game.ui.left_touch == 10 and game.ui.right_touch == 11 and game.ui.fire_touch == 12,
		"move, look and fire keep independent touch pointers")
	check(game.fps.jump_buffer > 0, "a fourth touch requests jump without stealing a stick")
	var drag = InputEventScreenDrag.new()
	drag.index = 11
	drag.position = Vector2(840, 280) * game.ui.scale_value + game.ui.offset
	drag.relative = Vector2(40, -20) * game.ui.scale_value
	game.ui._input(drag)
	check(game.ui.look_delta.length() > 0 and game.ui.fire_touch == 12, "swipe-look works while fire is held")
	game.ui.look_delta = Vector2.ZERO
	drag.index = 12
	game.ui._input(drag)
	check(game.ui.look_delta.length() > 0 and game.ui.left_touch == 10, "dragging FIRE also aims for two-thumb play")
	for index in 4:
		var touch = InputEventScreenTouch.new()
		touch.index = 10 + index
		touch.pressed = false
		touch.position = touch_points[index] * game.ui.scale_value + game.ui.offset
		game.ui._input(touch)
	check(game.ui.fire_touch == -1 and game.ui.right_touch == -1, "releasing fingers cancels look and firing")
	# Old v2 saves migrate without changing inventory, health or generated rooms.
	var saved: Dictionary = run.snapshot()
	saved.version = 2
	var health: float = run.hp
	var old_rooms = JSON.stringify(saved.rooms)
	var file = FileAccess.open(run.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()
	check(run.load_run() and run.hp == health, "v2 migration preserves player resources")
	check(run.rooms.values().all(func(room): return room.get("fps_flat", false)), "legacy runs explicitly retain flat layouts")
	# A fast projectile cannot hit an enemy behind a nearer wall, but crosses
	# the same body when that wall is removed. This tests actual swept travel.
	game.paused = true
	for enemy in game.enemies.duplicate():
		enemy.alive = false
		enemy.queue_free()
	game.enemies.clear()
	var target = game.spawn_enemy(Vector3(0, 0, -3), "spitter")
	var cover = Geo.collider(game.scene_root, Vector3(0, 1.0, -.8), Vector3(3, 2, .3))
	await frames(3)
	var health_before: float = target.hp
	var blocked_shot = game.player.launch_shot(Vector3(0, 1, 1), Vector3.FORWARD, 2, 120, {}, Color.WHITE, true)
	blocked_shot.update_sim(.06)
	check(target.hp == health_before and not blocked_shot.alive, "nearer cover blocks a swept body hit")
	cover.queue_free()
	await frames(3)
	var clear_shot = game.spawn_shot(Vector3(0, 1, 1), Vector3.FORWARD, 2, 120, {}, Color.WHITE, true)
	clear_shot.update_sim(.06)
	check(target.hp < health_before, "fast shots sweep through full-height enemy bodies")
	game.player.place(Vector3(0, 1, 2))
	check(not target.ground_wave_reaches(), "jumping clears a low ground wave")
	game.player.place(Vector3(0, 0, 2))
	check(target.ground_wave_reaches(), "grounded player remains vulnerable to low waves")
	game.player.place(Vector3(0, 1.2, 2))
	check(target.aimed_direction(Vector3.BACK).y > .1, "aimed enemy fans account for elevation")
	# A solid chest is itself a valid target; a separate wall still occludes it.
	var chest_record = {"id": "fps:test", "position": [0.0, 0.0], "locked": false, "opened": false, "table": "locked_chest"}
	var views = load("res://scripts/items/item_views.gd")
	var chest_view = views.chest(game.scene_root, chest_record)
	var chest_target = {"kind": "chest", "position": Vector3.ZERO, "node": chest_view}
	game.room.set_open(true)
	game.player.place(Vector3(0, 0, 1.5))
	game.fps.yaw = 0
	game.fps.pitch = -.3
	game.update_camera(.016)
	await frames(3)
	check(game.interaction_eligible(chest_target), "a chest's own collider does not block its interaction")
	var divider = Geo.collider(game.scene_root, Vector3(0, 1, .8), Vector3(3, 2, .12))
	await frames(3)
	check(not game.interaction_eligible(chest_target), "a separate wall blocks chest interaction")
	divider.queue_free()
	chest_view.queue_free()
	# Run every boss's real simulation under the first-person controller.
	game.set_physics_process(false)
	for theme in content.families.floors:
		game.start_run("candle", 61003, false)
		run.floor_plan = [theme.id, theme.id, theme.id, theme.id, theme.id]
		run.floor_twists = ["", "", "", "", ""]
		run.floor_number = 3
		run.generate_floor()
		for id in run.rooms:
			if run.rooms[id].type != "boss": continue
			run.current_room = id
			game.enter_room(Vector3(0, 0, 4))
			break
		run.stats.max_hp = 900
		run.hp = 900
		game.player.invulnerability = 100
		var boss = game.enemies.filter(func(enemy): return enemy.boss)[0]
		for tick in 360: game._physics_process(1.0 / 60.0)
		check(boss.alive and boss.global_position.is_finite(), "six-second first-person encounter: " + theme.boss.kind)
		check(boss.hit_height >= boss.radius * 2, "valid upright boss hit volume: " + theme.boss.kind)
		await process_frame
	game.pause_game()
	game.queue_free()
	await process_frame
	print("EMBERKEEP FIRST PERSON RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
