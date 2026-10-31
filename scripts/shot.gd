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
# The light of a shot: a hot core, a soft glow, a ribbon behind it and a pool
# on the floor below. Shots of one colour share each material; size,
# brightness and the ribbon's direction ride on the nodes' transforms. It
# blooms in when fired and flashes out when it ends; the light outlives the
# shot by a moment, but only the light.
const APPEAR := .09
const VANISH := .16
static var materials: Dictionary = {}
var lights: Array[MeshInstance3D] = []
var core: MeshInstance3D
var glow: MeshInstance3D
var streak: MeshInstance3D
var splat: MeshInstance3D
var appear = 0.0
var vanish = -1.0
# Forged traits: gathering speed, hanging as a mine, swelling, forking at
# the end of flight, and the residue a shot leaves where it flies.
var base_speed = 15.0
var trail_timer = 0.0
var forked = false

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
	base_speed = speed
	if float(stats.get("linger", 0)) > 0: lifetime *= 2.2
	radius = (.12 if friendly else .17) * float(stats.get("size", 1))
	build_light(color)
	if not friendly:
		Geo.ring(self, Vector3.ZERO, radius * 1.4, Color("f39b88"), .025)

static func material(name: String, color: Color) -> ShaderMaterial:
	var key = name + color.to_html()
	if not materials.has(key):
		var mat = ShaderMaterial.new()
		mat.shader = load("res://shaders/shot_%s.gdshader" % name)
		mat.set_shader_parameter("tint", color)
		materials[key] = mat
	return materials[key]

## The ribbon and the floor pool are cosmetic, so they follow effects detail.
func build_light(color: Color) -> void:
	var level = Look.quality()
	var sphere = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var shade = color.lightened(.15)
	core = add_light(sphere, "core", shade)
	glow = add_light(QuadMesh.new(), "glow", shade)
	if level >= 1:
		streak = add_light(QuadMesh.new(), "streak", shade)
		streak.top_level = true
	if level >= 2:
		var pool = PlaneMesh.new()
		pool.size = Vector2.ONE * radius * 14.0
		splat = add_light(pool, "splat", shade)
		splat.position = Vector3(0, -position.y + .04, 0)
	shine()

func add_light(mesh: Mesh, kind: String, color: Color) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(kind, color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.layers = 2
	add_child(node)
	lights.append(node)
	return node

## Fade, swell and ribbon length for this frame of the shot's light.
func shine() -> void:
	var rise = ease(clampf(appear, 0.0, 1.0), .4)
	var fall = clampf(vanish, 0.0, 1.0) if vanish >= 0 else 0.0
	var fade = maxf(.001, rise * (1.0 - fall))
	core.scale = Vector3.ONE * maxf(.001, lerpf(1.8, 1.0, rise) * (1.0 - fall * .85))
	# The glow's X scale is its size, its Y scale (relative) its brightness.
	var size = radius * 7.5 * (lerpf(1.6, 1.0, rise) + fall * 1.4)
	glow.scale = Vector3(size, size * fade, size)
	if splat: splat.scale = Vector3.ONE * maxf(.001, fade)
	if streak:
		var tail = maxf(.001, clampf(speed * .045, .15, 1.3) * rise * (1.0 - fall))
		var flat = Vector3(direction.x, 0, direction.z).normalized() if Vector2(direction.x, direction.z).length() > .01 else Vector3.RIGHT
		streak.global_transform = Transform3D(Basis(direction * tail, Vector3.UP * fade, flat.cross(Vector3.UP) * radius * 2.4), global_position)

func _process(delta: float) -> void:
	if vanish >= 0:
		vanish += delta / VANISH
		if vanish >= 1.0:
			queue_free()
			return
	elif appear < 1.0:
		appear = minf(1.0, appear + delta / APPEAR)
	elif streak == null:
		return
	shine()

func update_sim(delta: float) -> void:
	if not alive:
		return
	age += delta
	if age >= lifetime:
		finish()
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
	elif stats.get("homing", 0) > 0:
		# A mirrored volley seeks the player, more gently.
		var desired: Vector3 = game.player.global_position + Vector3.UP * .65 - global_position
		desired.y = 0
		direction = direction.lerp(desired.normalized(), minf(.5, delta * float(stats.homing) * .5)).normalized()
	if friendly: shape_flight(delta)
	var movement = direction * speed * delta + game.wind * delta
	if stats.get("wave", 0) > 0:
		movement += direction.cross(Vector3.UP) * cos(age * 15) * delta * 3.0
	var target_position = global_position + movement
	# A shot through a dead lantern's glass lights it again.
	if friendly and is_instance_valid(game.room):
		var lantern: int = game.room.lantern_near(Vector2(target_position.x, target_position.z), .6, false)
		if lantern >= 0:
			game.relight(lantern)
			Effects.play("impact", global_position, Color("ffd08a"))
			remove()
			return
	# Glass splits a shot crossing it into three, once.
	if not stats.get("glassed", false) and game.residue and game.residue.crosses_glass(global_position, target_position):
		stats["glassed"] = true
		for side in [-1, 1]:
			var copy = game.spawn_shot(global_position, direction.rotated(Vector3.UP, side * .32), damage * (.6 if friendly else 1.0), speed, stats, tint, friendly)
			if copy: copy.hit_ids = hit_ids.duplicate()
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
			finish()
			return
	else:
		global_position = target_position
	if friendly:
		for enemy in game.enemies.duplicate():
			if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable or hit_ids.has(enemy.entity_id):
				continue
			var center: Vector3 = enemy.global_position + Vector3.UP * .65
			var closest = Geometry3D.get_closest_point_to_segment(center, global_position - movement, global_position)
			if closest.distance_to(center) < enemy.radius + radius:
				# Some foes absorb or turn a shot instead of taking it.
				if enemy.catch_shot(self):
					return
				hit_enemy(enemy)
				if not alive:
					return
	else:
		var center: Vector3 = game.player.global_position + Vector3.UP * .65
		var closest = Geometry3D.get_closest_point_to_segment(center, global_position - movement, global_position)
		if closest.distance_to(center) < .32 + radius:
			game.player.hurt(damage, global_position)
			remove()

func shape_flight(delta: float) -> void:
	var flown = age / lifetime
	if float(stats.get("accel", 0)) > 0:
		speed = minf(base_speed * 2.6, speed * (1.0 + 1.6 * delta))
	if float(stats.get("linger", 0)) > 0:
		# Slows to a stop partway, then waits as a mine for whatever comes.
		speed = base_speed * clampf(1.0 - (flown - .2) / .2, 0.0, 1.0)
	if float(stats.get("grow", 0)) > 0:
		scale = Vector3.ONE * (1.0 + flown)
		radius = (.12 * float(stats.get("size", 1))) * (1.0 + flown)
	var kind: String = stats.get("trail_kind", "")
	if kind != "" and game.residue:
		trail_timer -= delta
		if trail_timer <= 0:
			trail_timer = .12
			# Wide enough to always cover a tile centre.
			game.residue.add(kind, Vector3(global_position.x, 0, global_position.z), .6)

## The end of a shot's flight: what it carries meets what lies here, and a
## friendly shot that struck nothing is a miss.
func finish() -> void:
	if not alive: return
	if game.residue: game.residue.ripple(global_position, 1.0)
	if friendly and float(stats.get("fork", 0)) > 0 and not forked and age >= lifetime:
		fork()
	if game.residue and friendly: game.residue.react(global_position, .7, stats)
	if friendly and hit_ids.is_empty(): game.shot_missed(self)
	remove()

## Paint lands as a short-lived, budgeted floor mark; it deals no damage.
func splash() -> void:
	if friendly and float(stats.get("paint", 0)) > 0:
		Effects.play("paint_splash", Vector3(global_position.x, .02, global_position.z), tint)

## A forking shot splits three ways where its flight runs out.
func fork() -> void:
	forked = true
	var child_stats = stats.duplicate()
	child_stats.fork = 0
	child_stats.linger = 0
	for side in [-1, 0, 1]:
		var shot = game.spawn_shot(global_position, direction.rotated(Vector3.UP, side * .55), damage * .5, base_speed * .9, child_stats, tint, true)
		if shot:
			shot.forked = true
			shot.lifetime *= .6
			shot.hit_ids = hit_ids.duplicate()

func hit_enemy(enemy: DungeonEnemy) -> void:
	hit_ids[enemy.entity_id] = true
	splash()
	var critical = Run.rng.randf() < float(stats.get("crit", .05))
	var power = damage * (float(stats.get("crit_damage", 2.0)) if critical else 1.0)
	# A swelling shot strikes harder the farther it has flown.
	if float(stats.get("grow", 0)) > 0: power *= 1.0 + .5 * age / lifetime
	if enemy.hp < enemy.max_hp * .35:
		power *= 1.0 + float(stats.get("execute", 0))
	enemy.apply_status(stats)
	if game.residue: game.residue.react(enemy.global_position, .7, stats)
	enemy.take_hit(power, direction * float(stats.get("knockback", 1)) * 2.0, critical, false, "shot")
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
			target.take_hit(power * .6, Vector3.ZERO, false, false, "shot")
			previous = at
		# Standing in water, the struck foe carries the lightning to the rest of the pool.
		if game.residue: game.residue.shock(enemy.global_position, power * .5, chained)
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

## The shot is gone at once; its light flashes out a moment longer.
func remove() -> void:
	if alive:
		alive = false
		vanish = 0.0
