extends DungeonEnemy
## The Hour Keeper, the clock at the top of the belfry. Its two hands sweep
## the floor around it, the long one slow and the short one quick, and every
## time they meet the hour strikes: a ring that crosses the whole room. Dash
## through it. Chill stiffens its works and slows the hands. From half
## health time starts to slip: the hands lurch backwards, and every strike
## winds up a pair of cogs.
const HOUR_LENGTH := 7.5
const MINUTE_LENGTH := 5.0
const HOUR_SPEED := .32
const MINUTE_SPEED := 1.05
const HAND_REACH := .45
const STRIKE_SPEED := 5.0
const STRIKE_REACH := 11.0
var hour = 0.0
var minute = 2.0
var running = 1.0
var reverse = 0.0
var reverse_cooldown = 6.0
var touch_cooldown = 0.0
var strikes: Array = []
var hour_hand: Node3D
var minute_hand: Node3D

func is_boss() -> bool:
	return true

func stats() -> Array:
	return [300, 1.0, 1.1, "c9a860"]

func eye_height() -> float:
	return 1.6

func build_body(light: Dictionary) -> void:
	var face = Geo.cylinder(visual, Vector3(0, .9, 0), 1.15, 1.8, color, light.foe_body)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geo.cylinder(visual, Vector3(0, 1.85, 0), .9, .12, Color("efe0b0"), light.foe_body)
	hour_hand = make_hand(HOUR_LENGTH, .32, Color("8a6a3a"))
	minute_hand = make_hand(MINUTE_LENGTH, .22, Color("b08a4a"))

func make_hand(length: float, width: float, tint: Color) -> Node3D:
	var pivot = Node3D.new()
	add_child(pivot)
	var bar = Geo.box(pivot, Vector3(length / 2.0 + .6, .12, 0), Vector3(length, .1, width), tint, .6)
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return pivot

func moves() -> bool:
	return false

func turns() -> bool:
	return false

func behave(delta: float, _distance: float, _direction: Vector3) -> Vector3:
	touch_cooldown = maxf(0, touch_cooldown - delta)
	var slowed = .5 if chill_time > 0 else 1.0
	if hp <= max_hp * .5:
		reverse_cooldown -= delta
		if reverse_cooldown <= 0:
			reverse_cooldown = 7.0
			reverse = 1.6
	var flow = slowed * (-1.4 if reverse > 0 else 1.0)
	reverse = maxf(0, reverse - delta)
	var before = wrapf(minute - hour, -PI, PI)
	hour += HOUR_SPEED * flow * delta
	minute += MINUTE_SPEED * flow * delta
	var after = wrapf(minute - hour, -PI, PI)
	# The hands meet: the hour strikes.
	if signf(before) != signf(after) and absf(after) < 1.0: strike()
	hour_hand.rotation.y = -hour
	minute_hand.rotation.y = -minute
	for hand in [[hour, HOUR_LENGTH], [minute, MINUTE_LENGTH]]: sweep(hand[0], hand[1])
	for i in range(strikes.size() - 1, -1, -1):
		if spread_strike(strikes[i], delta): strikes.remove_at(i)
	return Vector3.ZERO

func sweep(angle: float, length: float) -> void:
	var along = Vector3(cos(angle), 0, sin(angle))
	var a: Vector3 = global_position + along * .6
	var b: Vector3 = global_position + along * (length + .6)
	var player_at: Vector3 = game.player.global_position
	player_at.y = global_position.y
	if ground_wave_reaches(.4) and touch_cooldown <= 0 and Geometry3D.get_closest_point_to_segment(player_at, a, b).distance_to(player_at) < HAND_REACH:
		touch_cooldown = .8
		game.player.hurt(1.0, global_position)

func strike() -> void:
	var node = Geo.ring(game.scene_root, Vector3(global_position.x, .09, global_position.z), 1.0, Color("f0d890"), .05)
	strikes.append({"node": node, "radius": 1.2, "hit": false})
	Audio.play_sound("coin", .35)
	game.shake = maxf(game.shake, .15)
	if hp <= max_hp * .5:
		for side in [-1, 1]: game.spawn_enemy(global_position + Vector3(side * 2.2, 0, 1.4), "cog")

## Returns true once the ring has crossed the room.
func spread_strike(ring_state: Dictionary, delta: float) -> bool:
	ring_state.radius += STRIKE_SPEED * delta
	ring_state.node.scale = Vector3(ring_state.radius, 1, ring_state.radius)
	var to: Vector3 = game.player.global_position - global_position
	to.y = 0
	if ground_wave_reaches() and not ring_state.hit and absf(to.length() - ring_state.radius) < .35:
		ring_state.hit = true
		game.player.hurt(1.0, global_position)
	if ring_state.radius > STRIKE_REACH:
		ring_state.node.queue_free()
		return true
	return false

func on_death() -> void:
	for ring_state in strikes:
		if is_instance_valid(ring_state.node): ring_state.node.queue_free()
	strikes.clear()
