class_name FirstPersonController
extends Node
## Input, eye-level presentation and fixed-step movement are independent of
## weapon damage and run state. Cosmetic motion never changes a firing ray.
const EYE := 1.5
const GRAVITY := 22.0
const JUMP_SPEED := 7.0
const COYOTE := .12
var game
var yaw := 0.0
var pitch := 0.0
var jump_buffer := 0.0
var coyote := 0.0
var weapon: Node3D
var weapon_shape: Node3D
var was_playing := false
var near_wall := false
var view_weapon_id := ""
var hit_time := 0.0
var damage_time := 0.0
var damage_angle := 0.0
var suppress_mouse_fire := false

func setup(owner_game) -> void:
	game = owner_game
	weapon = Node3D.new()
	game.camera.add_child(weapon)
	weapon_shape = Node3D.new()
	weapon_shape.position = Vector3(.05, -.12, -.18)
	weapon.add_child(weapon_shape)
	FirstPersonWeaponView.populate(weapon_shape)
	for mesh in weapon_shape.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	weapon.visible = false

func _input(event: InputEvent) -> void:
	if not game.is_playing(): return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.screen_relative * float(Settings.values.mouse_sensitivity))
	if event.is_action_pressed("jump", false): jump_buffer = .14

func look(delta: Vector2) -> void:
	yaw = wrapf(yaw - delta.x, -PI, PI)
	pitch = clampf(pitch - delta.y * (-1.0 if Settings.values.invert_y else 1.0), deg_to_rad(-85), deg_to_rad(85))

func forward() -> Vector3:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD

func right() -> Vector3:
	return Vector3.RIGHT.rotated(Vector3.UP, yaw)

func reset_input() -> void:
	jump_buffer = 0.0
	suppress_mouse_fire = true
	game.ui.look_delta = Vector2.ZERO
	game.ui.fire_touch = -1

func update_view(delta: float) -> void:
	hit_time = maxf(0, hit_time - delta)
	damage_time = maxf(0, damage_time - delta)
	var active: bool = not game.in_menu and is_instance_valid(game.player)
	weapon.visible = active and game.ui.mode == "play"
	if active and view_weapon_id != Run.weapon_id:
		view_weapon_id = Run.weapon_id
		var model = Run.weapon()
		var tint = Color(model.color)
		weapon_shape.get_child(2).material_override = Geo.material(tint, .35)
		weapon_shape.scale = Vector3(.8 if model.count > 1 else .7, .7, .85 if model.get("pattern", "") == "lance" else .7)
	var playing: bool = game.is_playing() and game.ui.mode == "play"
	if playing != was_playing:
		was_playing = playing
		reset_input()
		if not game.ui.is_touch_platform() and DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if playing else Input.MOUSE_MODE_VISIBLE
	if not game.ui.is_touch_platform() and DisplayServer.get_name() != "headless":
		var desired = Input.MOUSE_MODE_CAPTURED if playing else Input.MOUSE_MODE_VISIBLE
		if Input.mouse_mode != desired: Input.mouse_mode = desired
	if not active:
		game.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		return
	var player = game.player
	game.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	game.camera.keep_aspect = Camera3D.KEEP_HEIGHT
	game.camera.fov = Settings.values.fov
	game.camera.near = .045
	game.camera.far = 95
	game.camera.h_offset = 0
	var bob := sin(player.walk_time * 2.0) * .016 if Settings.values.head_bob and player.is_on_floor() else 0.0
	game.camera.global_position = player.global_position + Vector3(0, EYE + bob, 0)
	game.camera.rotation = Vector3(pitch, yaw, 0)
	player.visual.visible = false
	player.gun.visible = false
	player.shelter.visible = false
	var tucked := .25 if near_wall else 0.0
	var wanted = Vector3(0, -tucked, player.recoil * .16 + tucked)
	weapon.position = weapon.position.lerp(wanted, 1.0 - exp(-16.0 * delta))
	game.camera_focus = player.global_position
	game.room.update_light_selection(player.global_position)

func collect_look(delta: float) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): suppress_mouse_fire = false
	var eye: Vector3 = game.player.global_position + Vector3.UP * EYE
	near_wall = not game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + forward() * .9, 1 | PropVisuals.FURNITURE_LAYER)).is_empty()
	look(game.ui.look_delta * float(Settings.values.touch_sensitivity))
	game.ui.look_delta = Vector2.ZERO
	Run.view_angles = [yaw, pitch]
	var stick = Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > .18:
		look(stick * delta * 2.5)

func move_player(player, delta: float, move_input: Vector2) -> void:
	jump_buffer = maxf(0, jump_buffer - delta)
	if player.is_on_floor(): coyote = COYOTE
	else: coyote = maxf(0, coyote - delta)
	var direction = right() * move_input.x + Vector3(0, 0, 1).rotated(Vector3.UP, yaw) * move_input.y
	if direction.length_squared() > .01: player.last_move = direction.normalized()
	var flat = Vector3(player.velocity.x, 0, player.velocity.z)
	if player.dash_time > 0:
		player.dash_time = maxf(0, player.dash_time - delta)
		player.leaving_dash = player.dash_time <= 0
		flat = player.dash_direction * player.DASH_SPEED
		player.graze_grace = player.GRAZE_GRACE
	else:
		var drag: float = game.residue.slows(player.global_position) if game.residue else 1.0
		var speed: float = player.RUN_SPEED * Run.stats.speed * drag
		if player.leaving_dash:
			# A short dodge must end at running pace rather than carrying
			# another few metres of slide off the far edge of a gallery.
			flat = flat.limit_length(speed)
			player.leaving_dash = false
		var icy: bool = game.residue and game.residue.kind_at(player.global_position) == "ice"
		flat = flat.move_toward(direction * speed, delta * (4.5 if icy else (42.0 if player.is_on_floor() else 17.0)))
	player.velocity.x = flat.x
	player.velocity.z = flat.z
	player.velocity.y -= GRAVITY * delta
	if jump_buffer > 0 and coyote > 0:
		player.velocity.y = JUMP_SPEED
		jump_buffer = 0
		coyote = 0
	player.collision_mask = (1 if player.dash_time > 0 else 5) | PropVisuals.FURNITURE_LAYER
	player.graze_grace = maxf(0, player.graze_grace - delta)
	for enemy in game.enemies.duplicate():
		if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable: continue
		if player.dash_time > 0 and player.global_position.distance_to(enemy.global_position) < enemy.radius + .7:
			enemy.dashed_through()
			if Run.stats.dash_damage > 0: enemy.take_hit(float(Run.stats.dash_damage) * delta * 8, Vector3.ZERO, false, false, "dash")
	if player.dash_time > 0 or player.graze_grace > 0:
		for shot in game.shots.duplicate():
			if is_instance_valid(shot) and shot.alive and not shot.friendly and shot.global_position.distance_to(player.global_position + Vector3.UP * .85) < player.GRAZE_RADIUS:
				game.catch_spark(shot)
	player.velocity += player.push
	player.move_and_slide()
	player.velocity -= player.push
	player.push = player.push.move_toward(Vector3.ZERO, delta * 14)
	var kept: Vector2 = game.room.geometry.recover(Vector2(player.last_valid.x, player.last_valid.z), Vector2(player.position.x, player.position.z), .34)
	player.position.x = kept.x
	player.position.z = kept.y
	# Repair penetration from an old checkpoint or a changed solid surface.
	# This never moves the player across a wall or teleports ordinary blocked
	# movement; it only lifts feet that are already inside the terrain solid.
	var ground: float = game.room.floor_height(player.position)
	if player.position.y < ground - .12:
		player.position.y = ground + .03
		player.velocity.y = maxf(0, player.velocity.y)
	if player.position.y < -3:
		player.position = player.last_valid + Vector3.UP * .3
		player.velocity = Vector3.ZERO
	if player.is_on_floor() and absf(player.position.y - ground) < .15: player.last_valid = player.position
	var old_stride = floori(player.walk_time / PI)
	player.walk_time += flat.length() * delta * 2.7
	if old_stride != floori(player.walk_time / PI) and player.is_on_floor():
		Effects.play("footstep", player.global_position + Vector3.UP * .05)
		Audio.play_at("step", player, player.global_position, .95)

func shot_origin() -> Vector3:
	var eye: Vector3 = game.player.global_position + Vector3.UP * EYE
	var muzzle = eye + forward() * (.12 if near_wall else .45) + right() * .16 - Vector3.UP * .12
	var hit = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, muzzle, 1 | PropVisuals.FURNITURE_LAYER))
	return eye if not hit.is_empty() else muzzle

func shot_direction(muzzle: Vector3) -> Vector3:
	var from: Vector3 = game.player.global_position + Vector3.UP * EYE
	var to = from + forward() * 80
	var query = PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | PropVisuals.FURNITURE_LAYER)
	var hit = game.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): to = hit.position
	return (to - muzzle).normalized()
