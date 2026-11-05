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
var light_radius := .14
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
# Mesh resources are immutable and shared by every projectile. Size/fade
# belong to node transforms; a volley never builds new render geometry.
static var core_mesh: SphereMesh
static var quad_mesh: QuadMesh
static var pool_mesh: PlaneMesh
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
# Co-op: a guest draws spells the host really casts. A drawn spell flies and
# stops where it would, but strikes nothing; the host's copy decides.
var cosmetic := false
var net_id := 0
# Whose spell this is (0 alone): their hit marker, heal and returning book.
var owner_peer := 0
# What it is (SpellForms): "" for a flying spell, or "ray", "lightning" or
# "eruption"; and how a flying one looks. Spells that do not fly draw
# themselves with SpellShapes pieces (fx) that outlive the blow a moment.
var mode := ""
var form := "orb"
var fx: Array = []
var tracing := false
var erupt_wait := -1.0
var pulses := 0
var erupt_radius := 1.45
# Spells that do not fly can stay a while after they strike: a lingering
# ray's beam, a storm cell where lightning struck, a returning bolt.
var hold := 0.0
var hold_tick := 0.0
var hold_linger := 0.0
var hold_path: Array = []
var returned := false
# How each look sizes its heart, its rune halo and its trail.
const FORM_GLOW := {"orb": 1.0, "shard": .7, "needle": .45, "comet": 1.3, "mote": .5, "disc": .9}
const FORM_TAIL := {"orb": 1.0, "shard": 1.1, "needle": 1.4, "comet": 1.9, "mote": .6, "disc": .8}

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
	light_radius = radius
	form = SpellForms.form(stats)
	if friendly:
		match SpellForms.archetype(stats):
			"ray":
				mode = "ray"
				speed = 72.0
				base_speed = speed
				lifetime = 14.0 * float(stats.get("range", 1)) * sqrt(maxf(.3, float(stats.get("shot_speed", 1)))) / speed
				radius = maxf(radius, .14)
				# A lingering ray leaves its beam burning instead of slowing.
				hold_linger = float(stats.get("linger", 0))
				stats.erase("linger")
			"lightning": mode = "lightning"
			"eruption": mode = "eruption"
	if mode != "": return
	build_light(color)
	if not friendly:
		Geo.ring(self, Vector3.ZERO, radius * 1.4, Color("f39b88"), .025)

static func material(name: String, color: Color, style := 0) -> ShaderMaterial:
	var key = name + color.to_html() + (":%d" % style if style > 0 else "")
	if not materials.has(key):
		var mat = ShaderMaterial.new()
		mat.shader = load("res://shaders/shot_%s.gdshader" % name)
		mat.set_shader_parameter("tint", color)
		if style > 0: mat.set_shader_parameter("style", style)
		materials[key] = mat
	return materials[key]

## The ribbon and the floor pool are cosmetic, so they follow effects detail.
func build_light(color: Color) -> void:
	var level = Look.quality()
	# A floor glow for every pellet adds a large transparent layer to GLES.
	# The safe mobile path retains the body, halo and direction ribbon.
	if RenderPolicy.current().lightweight_surfaces: level = mini(level, 1)
	if core_mesh == null:
		core_mesh = SphereMesh.new()
		core_mesh.radius = 1.0
		core_mesh.height = 2.0
		core_mesh.radial_segments = 18
		core_mesh.rings = 10
		quad_mesh = QuadMesh.new()
		pool_mesh = PlaneMesh.new()
		pool_mesh.size = Vector2.ONE
	var shade = color.lightened(.15)
	core = add_light(core_mesh, "core", shade)
	# A disc spins flat; every other look turns to its flight.
	glow = add_light(quad_mesh, "glow", shade, Forge.FORMS.find(form))
	if level >= 1:
		streak = add_light(quad_mesh, "streak", shade)
		streak.top_level = true
	if level >= 2:
		splat = add_light(pool_mesh, "splat", shade)
		splat.position = Vector3(0, -position.y + .04, 0)
	shine()

func add_light(mesh: Mesh, kind: String, color: Color, style := 0) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(kind, color, style)
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
	var heart := maxf(.001, light_radius * lerpf(1.8, 1.0, rise) * (1.0 - fall * .85))
	core.basis = form_basis(heart) if form != "orb" else Basis.from_scale(Vector3.ONE * heart)
	# The glow's X scale is its size, its Y scale (relative) its brightness.
	var size = radius * 7.5 * (lerpf(1.6, 1.0, rise) + fall * 1.4) * float(FORM_GLOW.get(form, 1.0))
	glow.scale = Vector3(size, size * fade, size)
	if splat:
		splat.scale = Vector3.ONE * maxf(.001, light_radius * 14.0 * fade)
		if game.first_person:
			splat.global_position = Vector3(global_position.x, game.room.floor_height(global_position) + .04, global_position.z)
	if streak:
		var tail = maxf(.001, clampf(speed * .045, .15, 1.3) * rise * (1.0 - fall) * float(FORM_TAIL.get(form, 1.0)))
		var flat = Vector3(direction.x, 0, direction.z).normalized() if Vector2(direction.x, direction.z).length() > .01 else Vector3.RIGHT
		var up = Vector3.UP
		if game.first_person:
			up = direction.cross(game.camera.global_basis.x).normalized()
			if up.length_squared() < .01: up = direction.cross(Vector3.FORWARD).normalized()
		streak.global_transform = Transform3D(Basis(direction * tail, up * fade, direction.cross(up).normalized() * radius * 2.4), global_position)

func _process(delta: float) -> void:
	if mode != "":
		# Its pieces play out; once it has struck and they are done, it goes.
		if not SpellShapes.animate(self, delta) and not alive: queue_free()
		return
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
	match mode:
		"ray":
			if hold > 0:
				hold_ray(delta)
				return
			if not tracing:
				trace_ray()
				return
		"lightning":
			if hold > 0: hold_storm(delta)
			else: strike()
			return
		"eruption":
			erupt_tick(delta)
			return
	if cosmetic:
		update_cosmetic(delta)
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
				# Homecoming: the way home strikes twice as hard.
				if float(stats.get("homecoming", 0)) > 0: damage *= 2.0
			var back: Vector3 = caster().global_position + Vector3.UP * .65 - global_position
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
		var quarry: Node3D = game.nearest_body(global_position) if game.has_method("nearest_body") else game.player
		var desired: Vector3 = quarry.global_position + Vector3.UP * .65 - global_position
		if not game.first_person: desired.y = 0
		direction = direction.lerp(desired.normalized(), minf(.5, delta * float(stats.homing) * .5)).normalized()
	if friendly: shape_flight(delta)
	var movement = direction * speed * delta + game.wind * delta
	if stats.get("wave", 0) > 0:
		movement += direction.cross(Vector3.UP) * cos(age * 15) * delta * 3.0
	var target_position = global_position + movement
	var query = PhysicsRayQueryParameters3D.create(global_position, target_position, (1 | PropVisuals.FURNITURE_LAYER) if game.first_person else 1)
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	# A shot through dead lantern glass lights it again, but cover wins when
	# it lies earlier on the sweep. Testing only the endpoint skips fast shots.
	if friendly and is_instance_valid(game.room):
		var lantern: int = -1
		if game.first_person:
			var nearest = global_position.distance_squared_to(hit.position) if not hit.is_empty() else INF
			for index in game.room.lanterns.size():
				var lamp: Dictionary = game.room.lanterns[index]
				if lamp.burning: continue
				var center: Vector3 = lamp.at + Vector3.UP * 1.6
				var point = Geometry3D.get_closest_point_to_segment(center, global_position, target_position)
				var reach = global_position.distance_squared_to(point)
				if point.distance_squared_to(center) < .36 and reach < nearest:
					nearest = reach
					lantern = index
		else:
			lantern = game.room.lantern_near(Vector2(target_position.x, target_position.z), .6, false)
		if lantern >= 0:
			game.relight(lantern)
			Effects.play("impact", global_position, Color("ffd08a"))
			remove()
			return
	# Glass splits a shot crossing it into three, once.
	var glass_end: Vector3 = hit.position if game.first_person and not hit.is_empty() else target_position
	if not stats.get("glassed", false) and game.residue and game.residue.crosses_glass(global_position, glass_end):
		stats["glassed"] = true
		for side in [-1, 1]:
			var copy = game.spawn_shot(global_position, direction.rotated(Vector3.UP, side * .32), damage * (.6 if friendly else 1.0), speed, stats, tint, friendly)
			if copy: copy.hit_ids = hit_ids.duplicate()
	if not friendly and game.first_person:
		var wall_distance = global_position.distance_to(hit.position) if not hit.is_empty() else INF
		# Any teammate standing in its way, not only the one it was aimed at.
		for body in NetHooks.bodies(game):
			var low: Vector3 = body.global_position + Vector3.UP * .32
			var high: Vector3 = body.global_position + Vector3.UP * 1.38
			var pair = Geometry3D.get_closest_points_between_segments(global_position, target_position, low, high)
			if pair[0].distance_to(pair[1]) < .32 + radius and global_position.distance_to(pair[0]) < wall_distance:
				body.hurt(damage, pair[0])
				remove()
				return
	if friendly and game.first_person:
		# Resolve swept body hits in distance order before a later wall hit.
		var start = global_position
		var wall_distance = start.distance_to(hit.position) if not hit.is_empty() else INF
		var candidates: Array = []
		var low_bound = start.min(target_position) - Vector3.ONE * radius
		var high_bound = start.max(target_position) + Vector3.ONE * radius
		for enemy in game.enemies:
			if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable or hit_ids.has(enemy.entity_id): continue
			# Scalar broad phase avoids allocating a closest-segments result
			# for every distant body in every pellet's simulation tick.
			var body: Vector3 = enemy.global_position
			if body.x + enemy.radius < low_bound.x or body.x - enemy.radius > high_bound.x or body.z + enemy.radius < low_bound.z or body.z - enemy.radius > high_bound.z or body.y + enemy.hit_height < low_bound.y or body.y > high_bound.y: continue
			var low: Vector3 = enemy.global_position + Vector3.UP * enemy.radius
			var high: Vector3 = enemy.global_position + Vector3.UP * (enemy.hit_height - enemy.radius)
			var pair = Geometry3D.get_closest_points_between_segments(start, target_position, low, high)
			var distance = start.distance_to(pair[0])
			if pair[0].distance_to(pair[1]) < enemy.radius + radius and distance < wall_distance:
				candidates.append({"enemy": enemy, "point": pair[0], "distance": distance})
		candidates.sort_custom(func(a, b): return a.distance < b.distance)
		for candidate in candidates:
			if not is_instance_valid(candidate.enemy) or not candidate.enemy.alive or not candidate.enemy.targetable: continue
			global_position = candidate.point
			if candidate.enemy.catch_shot(self): return
			hit_enemy(candidate.enemy)
			if not alive: return
		global_position = start
	var geometry: RoomGeometry = game.room.geometry
	var flat_from = Vector2(global_position.x, global_position.z)
	var flat_to = Vector2(target_position.x, target_position.z)
	var boundary = not game.walkable_at(flat_to,.1) if game.first_person else not geometry.contains(flat_to,.1)
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
			if not game.first_person: normal.y = 0
			direction = direction.bounce(normal.normalized()).normalized()
			if not hit.is_empty():
				global_position = hit.position + normal * .12
			if friendly: ricochet()
		else:
			if game.first_person and not hit.is_empty(): global_position = hit.position
			Effects.play("impact", global_position, tint)
			splash()
			finish()
			return
	else:
		global_position = target_position
	if friendly and not game.first_person:
		for enemy in game.enemies.duplicate():
			if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable or hit_ids.has(enemy.entity_id):
				continue
			var center: Vector3 = enemy.global_position + Vector3.UP * .65
			var closest = Geometry3D.get_closest_point_to_segment(center, global_position - movement, global_position)
			var separation = closest.distance_to(center)
			if game.first_person:
				var low: Vector3 = enemy.global_position + Vector3.UP * enemy.radius
				var high: Vector3 = enemy.global_position + Vector3.UP * (enemy.hit_height - enemy.radius)
				var pair = Geometry3D.get_closest_points_between_segments(global_position - movement, global_position, low, high)
				separation = pair[0].distance_to(pair[1])
			if separation < enemy.radius + radius:
				# Some foes absorb or turn a shot instead of taking it.
				if enemy.catch_shot(self):
					return
				hit_enemy(enemy)
				if not alive:
					return
	elif not friendly and not game.first_person:
		var center: Vector3 = game.player.global_position + Vector3.UP * .65
		if game.first_person:
			center.y = clampf(global_position.y, game.player.global_position.y + .32, game.player.global_position.y + 1.35)
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
		Effects.play("paint_splash", Vector3(global_position.x, (game.room.floor_height(global_position) if game.first_person else 0.0) + .02, global_position.z), tint)

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
	# Spyglass: the farther off the foe, the harder it lands (Deadeye: always critical from afar).
	var distance := RelicPowers.reach(self, enemy) if float(stats.get("focus", 0)) > 0 or float(stats.get("deadeye", 0)) > 0 else 0.0
	if float(stats.get("deadeye", 0)) > 0 and distance >= 8.0: critical = true
	var power = damage * (float(stats.get("crit_damage", 2.0)) if critical else 1.0)
	if float(stats.get("focus", 0)) > 0: power *= 1.0 + minf(.6, .06 * distance)
	# A swelling shot strikes harder the farther it has flown.
	if float(stats.get("grow", 0)) > 0: power *= 1.0 + .5 * age / lifetime
	if enemy.hp < enemy.max_hp * .35:
		power *= 1.0 + float(stats.get("execute", 0))
	# Hunter's Moon: weaving spells finish the badly wounded.
	if float(stats.get("moon", 0)) > 0 and float(stats.get("wave", 0)) > 0 and not enemy.boss and enemy.hp - power < enemy.max_hp * .25:
		power = enemy.hp * 2.0 + 1.0
		game.reaction_word(enemy.global_position + Vector3.UP * 1.8, "p:hunters_moon")
	# What a reaction on this foe is measured by, and whose heal a pairing pays.
	stats["hit"] = power
	stats["owner"] = owner_peer
	# Icicle: a piercing spell shatters a chilled foe as it passes through.
	if float(stats.get("icicle", 0)) > 0 and pierces > 0 and enemy.marks.has("frost") and enemy.reaction_wait <= 0:
		enemy.marks.erase("frost")
		enemy.react("shatter", "ember", power, stats)
		if not enemy.alive:
			pierces -= 1
			return
	enemy.apply_status(stats)
	if game.residue: game.residue.react(enemy.global_position, .7, stats)
	var own: bool = owner_peer == 0 or NetHooks.party(game) == null or game.party.spell_owner_local(self)
	if game.first_person:
		if own: game.fps.hit_time = .13
		else: game.party.tell(owner_peer, "hitmark")
	enemy.take_hit(power, direction * float(stats.get("knockback", 1)) * 2.0, critical, false, "shot")
	RelicPowers.on_hit(self, enemy, power)
	# Lucky Star: a critical hit leaps to a second foe at full strength.
	if critical and float(stats.get("lucky", 0)) > 0:
		var second = game.nearest_enemy(enemy.global_position + Vector3.UP * .65, 6.0, hit_ids)
		if second:
			Effects.beam(game, enemy.global_position + Vector3.UP * .65, second.global_position + Vector3.UP * .65, Color("ffe08a"))
			second.apply_status(stats)
			second.take_hit(power, Vector3.ZERO, true, false, "shot")
	if Run.rng.randf() < minf(.25, float(stats.get("lifesteal", 0))):
		if own: Run.heal(.5)
		else: game.party.tell(owner_peer, "heal", .5)
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
			# Northern Lights: lightning freezes the foes it leaps to.
			if float(stats.get("northern", 0)) > 0 and is_instance_valid(target) and target.alive: target.freeze(1.2)
			previous = at
		# Standing in water, the struck foe carries the lightning to the rest of the pool.
		if game.residue: game.residue.shock(enemy.global_position, power * .5, chained)
	if stats.get("explosion", 0) > 0:
		game.blast(global_position, minf(3.5, stats.explosion), power * .5, true, enemy)
	if stats.get("split", 0) > 0:
		var child_stats = SpellForms.flying(stats) if mode == "eruption" else stats.duplicate()
		if mode == "eruption": child_stats.form = float(Forge.FORMS.find("shard"))
		child_stats.split = 0
		child_stats.chain = 0
		# Fractal Seed: shards split again (Infinite Regress: once more, and they pierce).
		var generations := int(stats.get("fractal", 0)) + int(stats.get("regress", 0))
		if generations > 0:
			child_stats.split = float(stats.split)
			child_stats.fractal = float(generations - 1)
			child_stats.regress = 0.0
			if float(stats.get("regress", 0)) > 0 or float(stats.get("regressed", 0)) > 0:
				child_stats.regressed = 1.0
		if float(child_stats.get("regressed", 0)) > 0: child_stats.pierce = float(child_stats.get("pierce", 0)) + 2.0
		child_stats.size = float(child_stats.get("size", 1)) * .65
		# Starfall: every shard bursts; Facets: a glass book's shards cut deep.
		if float(stats.get("starfall", 0)) > 0: child_stats.explosion = maxf(float(child_stats.get("explosion", 0)), 1.3)
		var share := .8 if str(stats.get("element", "")) == "glass" and float(stats.get("resonance", 0)) > 0 else .45
		for side in [-1, 1]:
			var shot = game.spawn_shot(global_position + direction * .2, direction.rotated(Vector3.UP, side * .65), damage * share, speed * .85, child_stats, tint, true)
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
		if net_id != 0: game.party.shot_gone(self)

## Who cast it: this player, or (on the co-op host) a teammate's figure.
func caster() -> Node3D:
	return game.party.body_of(owner_peer) if owner_peer != 0 else game.player

## A drawn spell (co-op guest): the same flight, stopping at walls and at the
## foes it meets, but striking nothing and leaving nothing behind.
func update_cosmetic(delta: float) -> void:
	age += delta
	if age >= lifetime:
		remove()
		return
	if friendly:
		if stats.get("returning", 0) > 0 and age > lifetime * .48:
			if not returning:
				returning = true
				hit_ids.clear()
			var back: Vector3 = caster().global_position + Vector3.UP * .65 - global_position
			if back.length() < .5:
				remove()
				return
			direction = direction.lerp(back.normalized(), minf(1, delta * 8)).normalized()
		elif stats.get("homing", 0) > 0:
			var target = game.nearest_enemy(global_position, 7.0, hit_ids)
			if target:
				var desired: Vector3 = target.global_position + Vector3.UP * .65 - global_position
				direction = direction.lerp(desired.normalized(), minf(.85, delta * stats.homing)).normalized()
		var flown = age / lifetime
		if float(stats.get("accel", 0)) > 0: speed = minf(base_speed * 2.6, speed * (1.0 + 1.6 * delta))
		if float(stats.get("linger", 0)) > 0: speed = base_speed * clampf(1.0 - (flown - .2) / .2, 0.0, 1.0)
		if float(stats.get("grow", 0)) > 0:
			scale = Vector3.ONE * (1.0 + flown)
			radius = (.12 * float(stats.get("size", 1))) * (1.0 + flown)
	elif stats.get("homing", 0) > 0:
		var desired: Vector3 = game.player.global_position + Vector3.UP * .65 - global_position
		direction = direction.lerp(desired.normalized(), minf(.5, delta * float(stats.homing) * .5)).normalized()
	var movement = direction * speed * delta + game.wind * delta
	if stats.get("wave", 0) > 0:
		movement += direction.cross(Vector3.UP) * cos(age * 15) * delta * 3.0
	var target_position = global_position + movement
	var hit = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(global_position, target_position, 1 | PropVisuals.FURNITURE_LAYER))
	if friendly:
		var wall_distance = global_position.distance_to(hit.position) if not hit.is_empty() else INF
		for enemy in game.enemies:
			if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable or hit_ids.has(enemy.entity_id): continue
			var low: Vector3 = enemy.global_position + Vector3.UP * enemy.radius
			var high: Vector3 = enemy.global_position + Vector3.UP * (enemy.hit_height - enemy.radius)
			var pair = Geometry3D.get_closest_points_between_segments(global_position, target_position, low, high)
			if pair[0].distance_to(pair[1]) < enemy.radius + radius and global_position.distance_to(pair[0]) < wall_distance:
				hit_ids[enemy.entity_id] = true
				if pierces > 0: pierces -= 1
				else:
					global_position = pair[0]
					remove()
					return
	elif is_instance_valid(game.player):
		# A foe's spell reaching this player stops here; the host decides the blow.
		var low: Vector3 = game.player.global_position + Vector3.UP * .32
		var high: Vector3 = game.player.global_position + Vector3.UP * 1.38
		var pair = Geometry3D.get_closest_points_between_segments(global_position, target_position, low, high)
		if pair[0].distance_to(pair[1]) < .32 + radius:
			remove()
			return
	var boundary = not game.walkable_at(Vector2(target_position.x, target_position.z), .1)
	if not hit.is_empty() or boundary:
		if bounces > 0:
			bounces -= 1
			var normal: Vector3 = hit.normal if not hit.is_empty() else -direction
			direction = direction.bounce(normal.normalized()).normalized()
			if not hit.is_empty(): global_position = hit.position + normal * .12
		else:
			if not hit.is_empty(): global_position = hit.position
			remove()
	else:
		global_position = target_position

## A friendly spell glancing off a wall: Mirror Maze makes it stronger,
## Ricochet Arc throws lightning at the nearest foe.
func ricochet() -> void:
	if cosmetic: return
	if float(stats.get("maze", 0)) > 0: damage *= 1.3
	if float(stats.get("arc", 0)) > 0:
		var target = game.nearest_enemy(global_position, 6.0, {})
		if target:
			Effects.beam(game, global_position, target.global_position + Vector3.UP * .65, Color("c4c2ff"))
			var spark := {"chain": 1.0, "element": "storm", "hit": damage * .6, "owner": owner_peer}
			target.apply_status(spark)
			target.take_hit(damage * .6, Vector3.ZERO, false, false, "shot")

## A flying spell's heart, shaped by its look and turned to its flight.
func form_basis(size: float) -> Basis:
	if form == "disc":
		return Basis(Vector3.UP, age * 16.0) * Basis.from_scale(Vector3(2.2, .3, 2.2) * size)
	var forward: Vector3 = direction if direction.length_squared() > .001 else Vector3.FORWARD
	var turned := Basis.looking_at(forward, Vector3.UP if absf(forward.y) < .95 else Vector3.RIGHT)
	match form:
		"shard": return turned * Basis.from_scale(Vector3(.55, .55, 2.6) * size)
		"needle": return turned * Basis.from_scale(Vector3(.32, .32, 3.8) * size)
		"comet": return turned * Basis.from_scale(Vector3(1.25, 1.25, 1.7) * size)
		"mote": return turned * Basis.from_scale(Vector3.ONE * .7 * size)
	return turned * Basis.from_scale(Vector3.ONE * size)

# ---------------------------------------------------------------- spells that do not fly
# Every relic means something to every kind of spell: what a flying bolt
# does with pierce, ricochet, seeking, weaving, returning, lingering,
# speed, swelling, forking and trails, a ray, lightning and an eruption do
# in their own way (docs/SPELLCRAFT.md).

## A ray flies its whole way in one tick, through the same flight a bolt
## takes (walls, pierce, ricochet, seeking, returning, forking, lanterns,
## glass, hits), then shows as a beam along the path it really took. A
## weaving ray zigzags; a lingering one leaves its beam burning a while; a
## trail is laid along it.
func trace_ray() -> void:
	tracing = true
	var path: Array = [global_position]
	var heading: Vector3 = direction
	var weave := float(stats.get("wave", 0)) > 0
	var side: Vector3 = direction.cross(Vector3.UP).normalized()
	var steps := 0
	while alive and steps < 160:
		steps += 1
		if cosmetic: update_cosmetic(1.0 / 120.0)
		else: update_sim(1.0 / 120.0)
		if weave and alive:
			global_position += side * cos(steps * .75) * .2
		# A bend (a wall glanced off, a foe sought, a weave) starts a new stretch.
		if weave or direction.angle_to(heading) > .08:
			path.append(global_position)
			heading = direction
	if global_position.distance_to(path.back()) > .01: path.append(global_position)
	SpellShapes.ray(self, path, tint, float(stats.get("size", 1)), 1.3 if hold_linger > 0 else .0)
	if not cosmetic: lay_trail(path)
	if hold_linger > 0 and not cosmetic:
		hold_path = path
		hold = 1.3
		hold_tick = 0.0
		alive = true
		return
	if alive: remove()

## A lingering ray's beam burns whatever crosses it.
func hold_ray(delta: float) -> void:
	hold -= delta
	hold_tick -= delta
	if hold_tick <= 0:
		hold_tick = .3
		for enemy in game.enemies.duplicate():
			if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable: continue
			var body: Vector3 = enemy.global_position + Vector3.UP * .6
			for i in hold_path.size() - 1:
				if Geometry3D.get_closest_point_to_segment(body, hold_path[i], hold_path[i + 1]).distance_to(body) < enemy.radius + .35:
					enemy.apply_status(stats)
					enemy.take_hit(damage * .3, Vector3.ZERO, false, true, "shot")
					break
	if hold <= 0: remove()

## Wax, water or ice laid along a path on the floor beneath it.
func lay_trail(path: Array) -> void:
	var kind: String = stats.get("trail_kind", "")
	if kind == "" or not game.residue: return
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var count := maxi(1, int(a.distance_to(b)))
		for j in count:
			var at := a.lerp(b, float(j) / count)
			game.residue.add(kind, Vector3(at.x, 0, at.z), .6)

## Lightning: the nearest foe within a narrow cone ahead and in sight is
## struck at once; with none, it strikes where you aim. Seeking widens the
## cone; pierce carries it on to the next foe beyond; ricochet leaps it to
## other foes near; swelling strikes those beside the target too; forking
## strikes two more in a wider cone; a lingering bolt leaves a storm cell
## that keeps striking; a returning one comes back a moment later.
func strike() -> void:
	var from: Vector3 = global_position
	var reach := 12.0 * float(stats.get("range", 1)) * (1.4 if float(stats.get("accel", 0)) > 0 else 1.0) * (1.0 + (float(stats.get("shot_speed", 1)) - 1.0) * .5)
	var cone := .9 - minf(.35, float(stats.get("homing", 0)) * .08)
	var gen := RandomNumberGenerator.new()
	gen.randomize()
	var rough := .55 if float(stats.get("wave", 0)) > 0 else .32
	var target: DungeonEnemy = find_target(from, direction, reach, cone)
	var end: Vector3
	if target:
		end = aim_point(target)
	else:
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + direction * reach, ray_mask()))
		end = hit.position if not hit.is_empty() else from + direction * reach
	SpellShapes.bolt(self, from, end, tint, gen, 2, rough)
	global_position = end
	Effects.play("impact", end, tint)
	lay_trail([from, end])
	if cosmetic:
		remove()
		return
	if not target:
		# Struck water carries it; whatever lies here meets it.
		if game.residue: game.residue.shock(end, damage * .5, {})
		finish()
		return
	var through := int(stats.get("pierce", 0))
	var leaps := int(stats.get("bounce", 0))
	var forward: Vector3 = direction
	var struck := target
	while alive and struck:
		direction = (aim_point(struck) - from).normalized()
		# Kept in flight while there is more to strike (and Icicle can tell).
		pierces = through + leaps + 1
		hit_enemy(struck)
		if float(stats.get("grow", 0)) > 0: strike_beside(struck)
		var next: DungeonEnemy = null
		if through > 0:
			through -= 1
			next = find_target(aim_point(struck), forward, reach * .6, cone)
		elif leaps > 0:
			leaps -= 1
			next = game.nearest_enemy(aim_point(struck), 6.0, hit_ids)
			if next: ricochet()
		if next == null: break
		SpellShapes.bolt(self, aim_point(struck), aim_point(next), tint, gen, 1, rough)
		from = aim_point(struck)
		struck = next
	# Forking: two more bolts into a wider cone.
	if float(stats.get("fork", 0)) > 0 and not forked:
		forked = true
		for i in 2:
			var other: DungeonEnemy = find_target(global_position, forward, reach, .5)
			if other == null: break
			SpellShapes.bolt(self, end, aim_point(other), tint, gen, 1, rough)
			pierces = 1
			hit_enemy(other)
	global_position = end
	pierces = 0
	if float(stats.get("linger", 0)) > 0:
		hold = 1.4
		hold_tick = .2
		return
	if float(stats.get("returning", 0)) > 0 and not returned:
		hold = .25
		hold_tick = 99.0
		return
	remove()

func aim_point(enemy: DungeonEnemy) -> Vector3:
	return enemy.global_position + Vector3.UP * (minf(.9, enemy.hit_height * .55) if game.first_person else .65)

func ray_mask() -> int:
	return (1 | PropVisuals.FURNITURE_LAYER) if game.first_person else 1

## The foe a bolt goes for: in sight, inside the cone, near and near the
## line; one another bolt of this same volley already took is a last resort.
func find_target(from: Vector3, forward: Vector3, reach: float, cone: float) -> DungeonEnemy:
	var space := get_world_3d().direct_space_state
	var best: DungeonEnemy = null
	var best_score := INF
	var frame := Engine.get_physics_frames()
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable or hit_ids.has(enemy.entity_id): continue
		var center := aim_point(enemy)
		var to := center - from
		var distance := to.length()
		if distance > reach or distance < .05: continue
		var facing := to.normalized().dot(forward)
		if facing < cone: continue
		var blocked := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, center, ray_mask()))
		if not blocked.is_empty() and from.distance_to(blocked.position) < distance - .4: continue
		var score := distance * (1.0 + (1.0 - facing) * 8.0)
		if int(enemy.get_meta("bolted", -1)) == frame: score += 50.0
		if score < best_score:
			best_score = score
			best = enemy
	if best: best.set_meta("bolted", frame)
	return best

## A swelling bolt strikes those beside its target too.
func strike_beside(struck: DungeonEnemy) -> void:
	for enemy in game.enemies.duplicate():
		if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable or hit_ids.has(enemy.entity_id): continue
		if enemy.global_position.distance_to(struck.global_position) > 1.4 + enemy.radius: continue
		hit_ids[enemy.entity_id] = true
		enemy.apply_status(stats)
		enemy.take_hit(damage * .5, Vector3.ZERO, false, false, "shot")

## After lightning: a storm cell striking near, or the bolt coming home.
func hold_storm(delta: float) -> void:
	hold -= delta
	hold_tick -= delta
	if hold_tick <= 0 and float(stats.get("linger", 0)) > 0:
		hold_tick = .35
		var near = game.nearest_enemy(global_position, 2.6, {})
		if near:
			var gen := RandomNumberGenerator.new()
			gen.randomize()
			SpellShapes.bolt(self, global_position + Vector3.UP * 1.6, aim_point(near), tint, gen, 0)
			near.apply_status(stats)
			near.take_hit(damage * .35, Vector3.ZERO, false, false, "shot")
	if hold > 0: return
	if float(stats.get("returning", 0)) > 0 and not returned:
		# Homecoming: the way home strikes twice as hard.
		returned = true
		if float(stats.get("homecoming", 0)) > 0: damage *= 2.0
		hit_ids.clear()
		var back: Vector3 = caster().global_position + Vector3.UP * 1.2
		var home: DungeonEnemy = game.nearest_enemy(global_position, 4.0, {})
		if home:
			var gen := RandomNumberGenerator.new()
			gen.randomize()
			SpellShapes.bolt(self, back, aim_point(home), tint, gen, 1)
			pierces = 1
			hit_enemy(home)
	remove()

## An eruption: a rune glows on the floor where you aim (beneath the first
## foe in the way, or the nearest one if it seeks), then it rises, striking
## everything over the rune; a lingering one rises twice. Pierce runs it on
## as a fissure of eruptions; ricochet leaps it to another foe; weaving sends
## a ripple wider; returning raises one at your own feet; speed hastens the
## rune; forking throws three small ones around it.
func erupt_tick(delta: float) -> void:
	if erupt_wait < 0:
		place_eruption()
		return
	erupt_wait -= delta
	if erupt_wait > 0: return
	rise()
	pulses -= 1
	if pulses > 0:
		erupt_wait = .6
		if float(stats.get("wave", 0)) > 0 and pulses == 1 and not ripples_done:
			ripples_done = true
			erupt_radius *= 1.8
			erupt_wait = .2
		SpellShapes.rune(self, global_position, erupt_radius, tint, erupt_wait)
	elif cosmetic: remove()
	else: finish()

var ripples_done := false

func place_eruption() -> void:
	var from: Vector3 = global_position
	var reach := (3.5 if float(stats.get("radial", 0)) > 0 else 10.0) * float(stats.get("range", 1))
	var point: Vector3 = from
	var hit := {}
	if float(stats.get("anchor", 0)) <= 0:
		hit = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + direction * reach, ray_mask()))
		point = hit.position if not hit.is_empty() else from + direction * reach
		var stop := from.distance_to(point)
		for enemy in game.enemies:
			if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable: continue
			var pair = Geometry3D.get_closest_points_between_segments(from, point, enemy.global_position, enemy.global_position + Vector3.UP * enemy.hit_height)
			if pair[0].distance_to(pair[1]) < enemy.radius + .35 and from.distance_to(pair[0]) < stop:
				stop = from.distance_to(pair[0])
				point = enemy.global_position
		if float(stats.get("homing", 0)) > 0:
			var near = game.nearest_enemy(point, 3.0, {})
			if near: point = near.global_position
	# Off the wall it struck, and down to the floor beneath.
	if not hit.is_empty() and absf(hit.normal.y) < .5 and point.distance_to(hit.position) < .01:
		point += Vector3(hit.normal.x, 0, hit.normal.z).normalized() * .5
	global_position = ground(point)
	erupt_radius = 1.45 * float(stats.get("size", 1)) * (1.4 if float(stats.get("grow", 0)) > 0 else 1.0)
	pulses = (2 if float(stats.get("linger", 0)) > 0 else 1) + (1 if float(stats.get("wave", 0)) > 0 else 0)
	var haste := 1.0 + float(stats.get("accel", 0)) * .6 + maxf(0.0, float(stats.get("shot_speed", 1)) - 1.0) * .5
	erupt_wait = clampf(.34 / haste, .12, .34)
	SpellShapes.rune(self, global_position, erupt_radius, tint, erupt_wait)
	if int(stats.get("erupt", 1)) - 1 == RelicPowers.METEOR: SpellShapes.falling_star(self, global_position, erupt_wait, tint)
	if cosmetic: return
	# Pierce: a fissure of further eruptions on along the aim.
	var flat := Vector3(direction.x, 0, direction.z).normalized()
	for i in mini(int(stats.get("pierce", 0)), 4):
		sow(global_position + flat * 2.4 * (i + 1), .8)

## The floor beneath a point, inside where one can stand.
func ground(point: Vector3) -> Vector3:
	var flat := Vector2(point.x, point.z)
	if game.first_person and not game.walkable_at(flat, .2): flat = game.room.geometry.safe_point(flat, .3, game.room.blocked_at)
	var floor_y: float = game.room.floor_height(Vector3(flat.x, point.y, flat.y)) if game.first_person else 0.0
	return Vector3(flat.x, floor_y, flat.y)

## Another eruption of this one's kind, rising at a spot of its own.
func sow(at: Vector3, share: float, extra: Dictionary = {}) -> void:
	var child := stats.duplicate()
	for key in ["pierce", "bounce", "fork", "returning", "wave", "linger"]: child.erase(key)
	child.anchor = 1.0
	child.merge(extra, true)
	game.spawn_shot(ground(at) + Vector3.UP * .5, direction, damage * share, 1.0, child, tint, true)

func rise() -> void:
	var center: Vector3 = global_position
	var element: int = int(stats.get("erupt", 1)) - 1
	var gen := RandomNumberGenerator.new()
	gen.randomize()
	SpellShapes.erupt(self, center, erupt_radius, element, tint, gen)
	Effects.play("impact", center + Vector3.UP * .3, tint, 14, 1.4)
	if cosmetic: return
	game.make_noise(center, 1.6)
	if owner_peer == 0 or owner_peer == Session.local_peer_id: game.shake = maxf(game.shake, .06)
	var kept: int = pierces
	pierces = 999
	var struck := 0
	for enemy in game.enemies.duplicate():
		if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable: continue
		var gap := Vector2(enemy.global_position.x - center.x, enemy.global_position.z - center.z)
		if gap.length() > erupt_radius + enemy.radius or absf(enemy.global_position.y - center.y) > 2.2: continue
		var out := Vector3(gap.x, 0, gap.y).normalized() if gap.length() > .05 else Vector3(direction.x, 0, direction.z).normalized()
		direction = (out + Vector3.UP * .35).normalized()
		global_position = enemy.global_position + Vector3.UP * .5
		hit_enemy(enemy)
		global_position = center
		struck += 1
	pierces = kept
	# What rose stays a while: water, wax or ice where it came up.
	if game.residue:
		if element < Forge.ELEMENTS.size():
			var element_id: String = Forge.ELEMENTS.keys()[element]
			if Forge.TRAILS.has(element_id): game.residue.add(Forge.TRAILS[element_id], Vector3(center.x, 0, center.z), erupt_radius * .7)
		var kind: String = stats.get("trail_kind", "")
		if kind != "": game.residue.add(kind, Vector3(center.x, 0, center.z), erupt_radius * .6)
		game.residue.react(center, erupt_radius, stats)
	# Only the first rising of a lingering eruption sends anything on.
	if spread_done: return
	spread_done = true
	# Ricochet: leap to another foe near.
	if int(stats.get("bounce", 0)) > 0:
		var next = game.nearest_enemy(center, 6.0, hit_ids)
		if next:
			ricochet()
			Effects.beam(game, center + Vector3.UP * .4, next.global_position + Vector3.UP * .4, tint)
			sow(next.global_position, .8, {"bounce": float(int(stats.bounce) - 1)})
	# Returning: one more at the caster's feet (Homecoming: twice as hard).
	if float(stats.get("returning", 0)) > 0:
		sow(caster().global_position, 2.0 if float(stats.get("homecoming", 0)) > 0 else 1.0)
	# Forking: three small ones around it.
	if float(stats.get("fork", 0)) > 0:
		for i in 3:
			sow(center + Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 3.0 + gen.randf()) * erupt_radius * 1.9, .5, {"size": float(stats.get("size", 1)) * .6})
	# Pyroclasm: four burning shards fly out.
	if float(stats.get("pyro", 0)) > 0:
		var shard := SpellForms.flying(stats)
		shard.form = float(Forge.FORMS.find("comet"))
		shard.anchor = 0.0
		shard.pyro = 0.0
		for i in 4:
			game.spawn_shot(center + Vector3.UP * .7, Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 4.0 + gen.randf()), damage * .5, 13.0, shard, tint, true)

var spread_done := false
