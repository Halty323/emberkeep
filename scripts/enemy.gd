class_name DungeonEnemy
extends CharacterBody3D
var game: Node3D
var entity_id = 0
var kind = "mote"
var hp = 20.0
var max_hp = 20.0
var speed = 2.0
var alive = true
var visual: Node3D
var radius = .4
var timer = 1.0
var age = 0.0
var burn_time = 0.0
var burn_power = 0.0
var chill_time = 0.0
var chill_power = 0.0
var poison_time = 0.0
var poison_power = 0.0
var dot_tick = 0.0
var orbital_cooldown = 0.0
var knock_velocity = Vector3.ZERO
var charge_time = 0.0
var charge_direction = Vector3.ZERO
var windup = 0.0
var warning: MeshInstance3D
var boss = false
var boss_cycle = 0
var summon_timer = 9.0
var color = Color("bb7667")

func setup(owner_game: Node3D, type: String, id: int) -> void:
	game = owner_game
	kind = type
	entity_id = id
	add_to_group("enemies")
	boss = kind == "boss"
	var base: Array = {"mote": [15, 2.0, .37], "spitter": [19, 1.25, .4],
		"charger": [25, 1.5, .44], "splitter": [27, 1.65, .5], "brute": [48, 1.15, .62],
		"wisp": [9, 3.3, .26], "boss": [210, 1.15, 1.0]}[kind]
	max_hp = base[0] * (1.0 + (Run.floor_number - 1) * .48)
	hp = max_hp
	speed = base[1] * (1.0 + (Run.floor_number - 1) * .08)
	radius = base[2]
	color = {"mote": Color("bf8173"), "spitter": Color("9caaa1"), "charger": Color("c68e65"),
		"splitter": Color("9f8eb2"), "brute": Color("968b78"), "wisp": Color("d1b6d6"), "boss": Color("c4a27a")}[kind]
	collision_layer = 4
	collision_mask = 7
	var shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	shape.position.y = radius
	add_child(shape)
	visual = Node3D.new()
	add_child(visual)
	if kind in ["brute", "boss", "charger"]:
		Geo.box(visual, Vector3(0, radius * 1.2, 0), Vector3(radius * 1.8, radius * 2.2, radius * 1.8), color)
	else:
		Geo.sphere(visual, Vector3(0, radius * 1.1, 0), radius, color)
	for x in [-.12, .12]:
		Geo.box(visual, Vector3(x * radius * 2.2, radius * 1.5, -radius * .95), Vector3(.07, .1, .04) * (1.6 if boss else 1.0), Color("ffb9a3"), 1.5)
	if boss:
		Geo.cylinder(visual, Vector3(0, 2.4, 0), .65, .32, Color("72624b"))
		Geo.sphere(visual, Vector3(0, 2.75, 0), .34, Color("ffcb7d"), 1.5)
		Geo.light(visual, Vector3(0, 2.5, 0), Color("e69955"), 1.2, 5.0)
		Geo.ring(self, Vector3(0, .035, 0), 1.3, Color("b08361"), .055)
	Geo.halo(self, Vector3(0, .022, 0), radius * 3.8, Color(color.r, color.g, color.b, .09))
	timer = 1.0 + float(entity_id % 5) * .23

func update_sim(delta: float) -> void:
	if not alive:
		return
	age += delta
	timer -= delta
	orbital_cooldown -= delta
	burn_time = maxf(0, burn_time - delta)
	chill_time = maxf(0, chill_time - delta)
	poison_time = maxf(0, poison_time - delta)
	dot_tick -= delta
	if dot_tick <= 0:
		dot_tick = .4
		var damage = (burn_power if burn_time > 0 else 0.0) + (poison_power if poison_time > 0 else 0.0)
		if damage > 0:
			take_hit(damage, Vector3.ZERO, false, true)
			if not alive:
				return
	var to_player: Vector3 = game.player.global_position - global_position
	to_player.y = 0
	var distance = to_player.length()
	var direction = to_player.normalized()
	var move_direction = direction
	if kind == "spitter":
		move_direction = direction * (1.0 if distance > 5.5 else (-.5 if distance < 3.5 else 0.0))
		if timer <= 0:
			shoot_fan(direction, 3 if Run.floor_number > 1 else 1, .32)
			timer = 2.2
	elif kind == "charger":
		if timer <= 0 and windup <= 0 and charge_time <= 0:
			windup = .7
			charge_direction = direction
			warning = Geo.ring(self, Vector3(0, .05, 0), .75, Color("ed9b77"), .06)
			timer = 3.6
	elif boss:
		summon_timer -= delta
		if timer <= 0 and windup <= 0 and charge_time <= 0:
			boss_cycle += 1
			if boss_cycle % 3 == 0:
				windup = .85
				charge_direction = direction
				warning = Geo.ring(self, Vector3(0, .06, 0), 1.6, Color("eaa16f"), .1)
			else:
				var count = 10 + Run.floor_number * 2
				for i in count:
					var d = Vector3.RIGHT.rotated(Vector3.UP, TAU * i / count + age * .4)
					game.spawn_shot(global_position + Vector3.UP * .6 + d * 1.1, d, 1, 4.0 + Run.floor_number * .45, {}, Color("f29d8c"), false)
				shoot_fan(direction, 3 + Run.floor_number, .7)
			timer = 1.8 if hp / max_hp > .4 else 1.25
		if summon_timer <= 0:
			summon_timer = 9.0
			for side in [-1, 1]:
				game.spawn_enemy(global_position + Vector3(side * 1.8, 0, 1.0), "mote")
	if windup > 0:
		windup -= delta
		move_direction = Vector3.ZERO
		visual.scale = Vector3(1.0 + .12 * sin(age * 30), .88, 1.0)
		if windup <= 0:
			charge_time = .7 if boss else .55
			if is_instance_valid(warning):
				warning.queue_free()
	if charge_time > 0:
		charge_time -= delta
		move_direction = charge_direction * (5.0 if boss else 6.0)
	else:
		for obstacle in game.room.obstacles:
			var away: Vector3 = global_position - obstacle.position
			var d = away.length()
			if d < 1.8 + radius and d > .01:
				move_direction += away.normalized() * (1.8 + radius - d) * 2.0
	var slow = maxf(.28, 1.0 - chill_power * .2) if chill_time > 0 else 1.0
	velocity = move_direction * speed * slow + knock_velocity
	knock_velocity = knock_velocity.move_toward(Vector3.ZERO, delta * 20)
	move_and_slide()
	position.y = 0
	position.x = clampf(position.x, -8.55, 8.55)
	position.z = clampf(position.z, -6.55, 6.55)
	if windup <= 0:
		visual.scale = visual.scale.lerp(Vector3.ONE, delta * 12)
	visual.position.y = sin(age * (4 if boss else 7) + entity_id) * .04
	visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), delta * 8)
	if distance < radius + .45:
		game.player.hurt(1.0, global_position)

func shoot_fan(direction: Vector3, count: int, spread: float) -> void:
	for i in count:
		var angle = (float(i) / maxf(count - 1, 1) - .5) * spread
		var d = direction.rotated(Vector3.UP, angle)
		game.spawn_shot(global_position + Vector3.UP * .6 + d * (radius + .2), d, 1, 5.0, {}, Color("f29d8c"), false)

func apply_status(stats: Dictionary) -> void:
	if stats.get("burn", 0) > 0:
		burn_time = 3.0
		burn_power = maxf(burn_power, stats.burn * 1.8)
	if stats.get("chill", 0) > 0:
		chill_time = 2.5
		chill_power = maxf(chill_power, stats.chill)
	if stats.get("poison", 0) > 0:
		poison_time = 4.0
		poison_power = maxf(poison_power, stats.poison * 2.1)

func take_hit(damage: float, impulse: Vector3, critical := false, dot := false) -> void:
	if not alive:
		return
	hp -= damage
	knock_velocity += impulse / (2.5 if boss else 1.0)
	if not dot:
		visual.scale = Vector3(1.17, .85, 1.17)
		Effects.burst(game, global_position + Vector3.UP * radius, Color("ffe0a8") if critical else color, 3, .55)
		Audio.play_sound("hit", 1.3 if critical else 1)
		game.damage_number(global_position + Vector3.UP * 1.1, damage, critical)
	if critical:
		game.shake = maxf(game.shake, .07)
	if hp <= 0:
		die()

func die() -> void:
	if not alive:
		return
	alive = false
	collision_layer = 0
	collision_mask = 0
	Run.kills += 1
	game.player.haste_time = 2.0
	Effects.burst(game, global_position + Vector3.UP * .5, color, 9 if boss else 6, 1.5 if boss else 1)
	Audio.play_sound("kill", .6 if boss else 1)
	if kind == "splitter":
		for side in [-1, 1]:
			game.spawn_enemy(global_position + Vector3(side * .45, 0, 0), "wisp")
	game.on_enemy_killed(self)
	queue_free()
