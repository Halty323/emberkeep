class_name EmberShot
extends Node3D
var game: Node3D
var entity_id = 0
var direction = Vector3.RIGHT
var speed = 15.0
var damage = 5.0
var friendly = true
var stats: Dictionary = {}
var tint = Color("ffd18c")
var age = 0.0
var lifetime = 1.1
var pierces = 0
var bounces = 0
var hit_ids: Dictionary = {}
var radius = .14
var alive = true
var returning = false
var start_position = Vector3.ZERO
var trail: Array[MeshInstance3D] = []

func setup(owner_game: Node3D, at: Vector3, travel: Vector3, power: float, velocity_value: float, effects: Dictionary, color: Color, is_friendly: bool) -> void:
	game = owner_game
	position = at
	start_position = at
	direction = travel.normalized()
	damage = power
	speed = velocity_value
	stats = effects.duplicate()
	tint = color
	friendly = is_friendly
	pierces = int(stats.get("pierce", 0))
	bounces = int(stats.get("bounce", 0))
	lifetime = (1.15 if friendly else 4.0) * float(stats.get("range", 1))
	radius = (.12 if friendly else .17) * float(stats.get("size", 1))
	Geo.sphere(self, Vector3.ZERO, radius, color.lightened(.4), 1.6)
	Geo.halo(self, Vector3(0, -.02, 0), radius * 7, Color(color.r, color.g, color.b, .42))
	if not friendly:
		Geo.ring(self, Vector3.ZERO, radius * 1.4, Color("f39b88"), .025)
	else:
		for i in 3:
			var mesh = Geo.sphere(self, -direction * (i + 1) * .14, radius * (.65 - i * .15), color, 1.0)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			trail.append(mesh)

func update_sim(delta: float) -> void:
	if not alive:
		return
	age += delta
	if age >= lifetime:
		remove()
		return
	if friendly:
		if stats.get("returning", 0) > 0 and age > lifetime * .48:
			if not returning:
				returning = true
				hit_ids.clear()
			var back: Vector3 = game.player.global_position + Vector3.UP * .65 - global_position
			if back.length() < .5:
				remove()
				return
			direction = direction.lerp(back.normalized(), minf(1, delta * 8)).normalized()
		elif stats.get("homing", 0) > 0:
			var target = game.nearest_enemy(global_position, 7.0, hit_ids)
			if target:
				var desired: Vector3 = target.global_position + Vector3.UP * .65 - global_position
				direction = direction.lerp(desired.normalized(), minf(.85, delta * stats.homing)).normalized()
	var movement = direction * speed * delta
	if stats.get("wave", 0) > 0:
		movement += direction.cross(Vector3.UP) * cos(age * 15) * delta * 3.0
	var target_position = global_position + movement
	var query = PhysicsRayQueryParameters3D.create(global_position, target_position, 1)
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	var geometry: RoomGeometry = game.room.geometry
	var flat_from = Vector2(global_position.x, global_position.z)
	var flat_to = Vector2(target_position.x, target_position.z)
	var boundary = not geometry.contains(flat_to, .1)
	if friendly and not hit.is_empty() and is_instance_valid(hit.collider) and hit.collider.has_meta("prop_id"):
		game.hit_prop(hit.collider.get_meta("prop_id"), damage)
	if not hit.is_empty() or boundary:
		if bounces > 0:
			bounces -= 1
			# Ricochet off the wall actually struck: the physics hit, or the
			# exposed footprint edge crossed (an open doorway, an L bend).
			var normal: Vector3 = hit.normal if not hit.is_empty() else Vector3.ZERO
			if hit.is_empty():
				var edge = geometry.exit_normal(flat_from, flat_to, .1)
				normal = Vector3(edge.x, 0, edge.y) if edge != Vector2.ZERO else -direction
			normal.y = 0
			direction = direction.bounce(normal.normalized()).normalized()
			if not hit.is_empty():
				global_position = hit.position + normal * .12
		else:
			Effects.play("impact", global_position, tint)
			splash()
			remove()
			return
	else:
		global_position = target_position
	for i in trail.size():
		trail[i].position = -direction * (i + 1) * .17
	if friendly:
		for enemy in game.enemies.duplicate():
			if not is_instance_valid(enemy) or not enemy.alive or hit_ids.has(enemy.entity_id):
				continue
			var center: Vector3 = enemy.global_position + Vector3.UP * .65
			var closest = Geometry3D.get_closest_point_to_segment(center, global_position - movement, global_position)
			if closest.distance_to(center) < enemy.radius + radius:
				hit_enemy(enemy)
				if not alive:
					return
	else:
		var center: Vector3 = game.player.global_position + Vector3.UP * .65
		var closest = Geometry3D.get_closest_point_to_segment(center, global_position - movement, global_position)
		if closest.distance_to(center) < .32 + radius:
			game.player.hurt(damage, global_position)
			remove()

## Paint lands as a short-lived, budgeted floor mark; it deals no damage.
func splash() -> void:
	if friendly and float(stats.get("paint", 0)) > 0:
		Effects.play("paint_splash", Vector3(global_position.x, .02, global_position.z), tint)

func hit_enemy(enemy: DungeonEnemy) -> void:
	hit_ids[enemy.entity_id] = true
	splash()
	var critical = Run.rng.randf() < float(stats.get("crit", .05))
	var power = damage * (float(stats.get("crit_damage", 2.0)) if critical else 1.0)
	if enemy.hp < enemy.max_hp * .35:
		power *= 1.0 + float(stats.get("execute", 0))
	enemy.apply_status(stats)
	enemy.take_hit(power, direction * float(stats.get("knockback", 1)) * 2.0, critical)
	if Run.rng.randf() < minf(.25, float(stats.get("lifesteal", 0))):
		Run.heal(.5)
	if stats.get("chain", 0) > 0:
		var previous: Vector3 = enemy.global_position + Vector3.UP * .65
		var chained = hit_ids.duplicate()
		for i in mini(int(stats.chain), 6):
			var target = game.nearest_enemy(previous, 4.5, chained)
			if target == null:
				break
			chained[target.entity_id] = true
			var at: Vector3 = target.global_position + Vector3.UP * .65
			Effects.beam(game, previous, at, Color("c4c2ff"))
			target.apply_status(stats)
			target.take_hit(power * .6, Vector3.ZERO, false)
			previous = at
	if stats.get("explosion", 0) > 0:
		game.blast(global_position, minf(3.5, stats.explosion), power * .5, true, enemy)
	if stats.get("split", 0) > 0:
		var child_stats = stats.duplicate()
		child_stats.split = 0
		child_stats.chain = 0
		child_stats.size = float(child_stats.get("size", 1)) * .65
		for side in [-1, 1]:
			var shot = game.spawn_shot(global_position + direction * .2, direction.rotated(Vector3.UP, side * .65), damage * .45, speed * .85, child_stats, tint, true)
			if shot:
				shot.hit_ids[enemy.entity_id] = true
	if pierces > 0:
		pierces -= 1
	else:
		remove()

func remove() -> void:
	if alive:
		alive = false
		queue_free()
