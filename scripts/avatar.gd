class_name Adventurer
extends CharacterBody3D
var game: Node3D
var owner_peer_id = 1
var entity_id = 1
var visual: Node3D
var gun: Node3D
var aim_direction = Vector3(1, 0, 0)
var last_move = Vector3(1, 0, 0)
var dash_direction = Vector3.ZERO
var dash_time = 0.0
var dash_cooldown = 0.0
var invulnerability = 0.0
var fire_cooldown = 0.0
var shield = 0
var haste_time = 0.0
var walk_time = 0.0
var recoil = 0.0
var orbit_meshes: Array[MeshInstance3D] = []
var shelter: MeshInstance3D
const ROOM_MARGIN := .3
const RUN_SPEED := 5.2
# A dash covers about 2.9 units, then leaves at running speed: no long glide.
const DASH_SPEED := 18.0
const DASH_TIME := .16
var leaving_dash := false
# A dash catches hostile embers that pass this close, and a moment after.
const GRAZE_RADIUS := .95
const GRAZE_GRACE := .12
var graze_grace = 0.0
var spark_meshes: Array[MeshInstance3D] = []
var glow_light: OmniLight3D
var glow_halo: MeshInstance3D
var last_valid = Vector3.ZERO
var fade_copies: Dictionary = {}

func setup(owner_game: Node3D) -> void:
	game = owner_game
	collision_layer = 2
	collision_mask = 5 | PropVisuals.FURNITURE_LAYER
	var collider = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = .36
	collider.shape = shape
	collider.position.y = .48
	add_child(collider)
	visual = Node3D.new()
	add_child(visual)
	Geo.cylinder(visual, Vector3(0, .4, 0), .32, .6, Color("d39d5e"))
	Geo.sphere(visual, Vector3(0, .94, 0), .35, Color("e5bd80"))
	Geo.sphere(visual, Vector3(0, .98, -.12), .28, Color("ead2a4"))
	Geo.box(visual, Vector3(-.12, 1.0, -.36), Vector3(.055, .075, .035), Color("32383a"))
	Geo.box(visual, Vector3(.12, 1.0, -.36), Vector3(.055, .075, .035), Color("32383a"))
	Geo.box(visual, Vector3(-.16, .12, 0), Vector3(.21, .22, .3), Color("645b4e"))
	Geo.box(visual, Vector3(.16, .12, 0), Vector3(.21, .22, .3), Color("645b4e"))
	Geo.ring(self, Vector3(0, .045, 0), .47, Color("e9ca8e"), .025)
	glow_halo = Geo.halo(self, Vector3(0, .025, 0), 4.2, Color(1, .64, .25, .16))
	glow_light = Geo.light(self, Vector3(0, 1.5, 0), Color("ffcb88"), .65, 3.8)
	for i in 3:
		var spark = Geo.sphere(self, Vector3.ZERO, .09, Color("fff3c4"), 2.0)
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spark.visible = false
		spark_meshes.append(spark)
	gun = Node3D.new()
	add_child(gun)
	Geo.box(gun, Vector3(0, .7, -.43), Vector3(.17, .18, .5), Color("b6a080"))
	Geo.sphere(gun, Vector3(0, .7, -.72), .09, Color("ffe5b4"), 1.6)
	shelter = Geo.sphere(self, Vector3(0, .65, 0), .95, Color(.78, .9, .96), .35)
	shelter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shelter.material_override = shelter_material()
	refresh_orbitals()
	refresh_shelter()
	reset_room()

static func shelter_material() -> StandardMaterial3D:
	var glass = StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_color = Color(.78, .92, 1.0, .16)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return glass

## The Bell Jar's glass is shown for exactly as long as its saved modifier.
func refresh_shelter() -> void:
	if shelter: shelter.visible = Run.has_flag("invulnerable")

func place(at: Vector3) -> void:
	position = at
	last_valid = at

## Scripted steps for doorway transitions: the walking bob and footfalls,
## without collision, input or firing.
func walk_to(at: Vector3) -> void:
	var step = at - position
	step.y = 0
	if step.length_squared() > .000001:
		face(step)
		var stride = floori(walk_time / PI)
		walk_time += step.length() * 2.7
		if floori(walk_time / PI) != stride:
			Effects.play("footstep", global_position + Vector3(0, .05, 0))
	position = at
	visual.position.y = absf(sin(walk_time)) * .055
	visual.rotation.z = 0.0
	visual.visible = true
	for i in orbit_meshes.size():
		orbit_meshes[i].position = orbit_position(i)

func orbit_position(index: int) -> Vector3:
	var angle = game.sim_time * 2.4 + TAU * float(index) / orbit_meshes.size()
	return Vector3(cos(angle) * 1.35, .6, sin(angle) * 1.35)

func face(direction: Vector3) -> void:
	aim_direction = direction.normalized()
	visual.rotation.y = atan2(-aim_direction.x, -aim_direction.z)
	gun.rotation.y = visual.rotation.y
	gun.position = Vector3.ZERO

## Fades the whole figure, its glow and its lantern. The Compatibility
## renderer has no per-instance transparency, so while faded each mesh wears
## a transparent copy of its (shared) material; 1.0 restores the originals.
func set_fade(alpha: float) -> void:
	alpha = clampf(alpha, 0.0, 1.0)
	for mesh in find_children("*", "MeshInstance3D", true, false):
		var source: Material = mesh.get_meta("fade_source") if mesh.has_meta("fade_source") else mesh.material_override
		if source is ShaderMaterial:
			if not mesh.has_meta("fade_tint"): mesh.set_meta("fade_tint", source.get_shader_parameter("tint"))
			var tint: Color = mesh.get_meta("fade_tint")
			source.set_shader_parameter("tint", Color(tint, tint.a * alpha))
		elif source is BaseMaterial3D:
			if alpha >= 1.0:
				mesh.material_override = source
				mesh.remove_meta("fade_source")
				continue
			if not fade_copies.has(source):
				var made: BaseMaterial3D = source.duplicate()
				made.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				fade_copies[source] = made
			var copy: BaseMaterial3D = fade_copies[source]
			copy.albedo_color.a = source.albedo_color.a * alpha
			mesh.set_meta("fade_source", source)
			mesh.material_override = copy
	for light in find_children("*", "OmniLight3D", true, false):
		if not light.has_meta("fade_energy"): light.set_meta("fade_energy", light.light_energy)
		light.light_energy = light.get_meta("fade_energy") * alpha

func reset_room() -> void:
	shield = int(Run.stats.shield)
	invulnerability = .65
	velocity = Vector3.ZERO

func refresh_orbitals() -> void:
	for mesh in orbit_meshes:
		mesh.queue_free()
	orbit_meshes.clear()
	for i in mini(int(Run.stats.orbitals), 8):
		var mesh = Geo.sphere(self, Vector3.ZERO, .13, Color("ffd284"), 1.8)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		orbit_meshes.append(mesh)

func update_sim(delta: float, move_input: Vector2, aim_input: Vector3, shooting: bool) -> void:
	invulnerability = maxf(0, invulnerability - delta)
	refresh_shelter()
	dash_cooldown = maxf(0, dash_cooldown - delta)
	fire_cooldown -= delta
	haste_time = maxf(0, haste_time - delta)
	recoil = move_toward(recoil, 0.0, delta * 3.0)
	if aim_input.length_squared() > .01:
		aim_direction = aim_input.normalized()
	var direction: Vector3 = game.screen_direction(move_input)
	if direction.length_squared() > .01:
		last_move = direction.normalized()
	graze_grace = maxf(0, graze_grace - delta)
	if dash_time > 0 or graze_grace > 0:
		var chest = global_position + Vector3(0, .65, 0)
		for shot in game.shots.duplicate():
			if is_instance_valid(shot) and shot.alive and not shot.friendly and shot.global_position.distance_to(chest) < GRAZE_RADIUS:
				game.catch_spark(shot)
	if dash_time > 0:
		dash_time -= delta
		velocity = dash_direction * DASH_SPEED
		leaving_dash = dash_time <= 0
		if leaving_dash: graze_grace = GRAZE_GRACE
		# Dashing slips past foes but never through walls or furniture.
		collision_mask = 1 | PropVisuals.FURNITURE_LAYER
		for enemy in game.enemies.duplicate():
			if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable: continue
			var reach = global_position.distance_to(enemy.global_position)
			# Dashing through a ward pops it; through a prism shatters it.
			if reach < enemy.radius + .7: enemy.dashed_through()
			if Run.stats.dash_damage > 0 and reach < 1.1 and enemy.alive:
				enemy.take_hit(float(Run.stats.dash_damage) * delta * 8, Vector3.ZERO, false, false, "dash")
	else:
		collision_mask = 5 | PropVisuals.FURNITURE_LAYER
		# Moss and spores drag at the feet; ice keeps whatever speed you had.
		var footing: ResidueField = game.residue
		var top_speed = RUN_SPEED * float(Run.stats.speed) * (footing.slows(global_position) if footing else 1.0)
		var slippery = footing != null and footing.kind_at(global_position) == "ice"
		if leaving_dash:
			velocity = velocity.limit_length(top_speed)
			leaving_dash = false
		var target = direction * top_speed
		velocity = velocity.move_toward(target, delta * (4.5 if slippery else 47.0))
	var geometry: RoomGeometry = game.room.geometry
	if geometry.contains(Vector2(position.x, position.z), ROOM_MARGIN):
		last_valid = position
	move_and_slide()
	var kept = geometry.recover(Vector2(last_valid.x, last_valid.z), Vector2(position.x, position.z), ROOM_MARGIN)
	position = Vector3(kept.x, 0, kept.y)
	var stride = floori(walk_time / PI)
	walk_time += delta * velocity.length() * 2.7
	if floori(walk_time / PI) != stride and dash_time <= 0:
		Effects.play("footstep", global_position + Vector3(0, .05, 0))
	visual.position.y = absf(sin(walk_time)) * .055
	visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-aim_direction.x, -aim_direction.z), delta * 18)
	visual.rotation.z = -direction.x * .07
	visual.visible = not (invulnerability > 0 and dash_time <= 0 and int(invulnerability * 18) % 2 == 0)
	gun.rotation.y = atan2(-aim_direction.x, -aim_direction.z)
	gun.position = -aim_direction * recoil
	if shooting and fire_cooldown <= 0 and dash_time <= 0:
		fire()
	show_flame(delta)
	for i in orbit_meshes.size():
		orbit_meshes[i].position = orbit_position(i)
		for enemy in game.enemies:
			if is_instance_valid(enemy) and enemy.alive and enemy.orbital_cooldown <= 0 and enemy.global_position.distance_to(orbit_meshes[i].global_position - Vector3(0, .6, 0)) < .65:
				enemy.orbital_cooldown = .25
				enemy.take_hit(5 * Run.stats.damage, Vector3.ZERO, false)

func fire() -> void:
	var weapon: Dictionary = Content.weapon_by_id[Run.weapon_id]
	var stats = Run.projectile_stats()
	var tint = Color(weapon.color)
	# Pigment is gameplay state: each burst takes the next colour in turn.
	if weapon.has("cycle"):
		var pigment: Dictionary = weapon.cycle[posmod(Run.pigment, weapon.cycle.size())]
		Run.pigment += 1
		for key in pigment.effects:
			stats[key] = float(stats.get(key, 0)) + float(pigment.effects[key])
		tint = Color(pigment.color)
	var damage: float = weapon.damage * stats.damage * game.kindle_damage()
	if Run.hp <= Run.stats.max_hp / 2.0:
		damage *= 1.0 + float(stats.low_hp)
	# At full kindle every ember carries flame.
	if game.kindle_level() >= 3:
		stats.burn = float(stats.get("burn", 0)) + .6
	release_sparks(damage, stats)
	var count = mini(int(weapon.count + stats.shots), 15)
	var spread: float = weapon.spread
	if count > int(weapon.count) and stats.radial <= 0:
		spread += (count - int(weapon.count)) * .115
	for i in count:
		var angle = TAU * float(i) / count if stats.radial > 0 else (float(i) / maxf(1, count - 1) - .5) * spread
		var direction = aim_direction.rotated(Vector3.UP, angle)
		game.spawn_shot(global_position + Vector3(0, .65, 0) + direction * .5, direction, damage, float(weapon.speed) * stats.shot_speed, stats, tint, true)
	if stats.backshot > 0:
		game.spawn_shot(global_position + Vector3(0, .65, 0), -aim_direction, damage, weapon.speed * stats.shot_speed, stats, tint, true)
	if stats.side_shot > 0:
		for side in [-1, 1]:
			game.spawn_shot(global_position + Vector3(0, .65, 0), aim_direction.rotated(Vector3.UP, side * PI / 2), damage * .75, weapon.speed * stats.shot_speed, stats, tint, true)
	Effects.play("muzzle", global_position + Vector3(0, .7, 0) + aim_direction * .75, tint, -1, 1.0, aim_direction)
	game.make_noise(global_position, 1.0)
	fire_cooldown = maxf(.07, weapon.cooldown / (stats.rate + (stats.kill_haste if haste_time > 0 else 0)))
	recoil = .17
	Audio.play_sound("shoot", 1.0 + float(count) * .015)

## Caught sparks leave with the next shot as homing embers.
func release_sparks(damage: float, stats: Dictionary) -> void:
	if game.sparks <= 0: return
	var spark_stats = stats.duplicate()
	spark_stats.homing = maxf(float(spark_stats.get("homing", 0)), 5.0)
	spark_stats.pierce = 0
	for i in game.sparks:
		var d = aim_direction.rotated(Vector3.UP, (i - (game.sparks - 1) / 2.0) * .35)
		game.spawn_shot(global_position + Vector3(0, .65, 0) + d * .5, d, damage * 1.5, 15.0, spark_stats, Color("fff3c4"), true)
	game.sparks = 0

## The flame follows the kindle: a wider, warmer light, and caught sparks
## circling the head.
func show_flame(delta: float) -> void:
	var level = game.kindle_level()
	glow_light.omni_range = move_toward(glow_light.omni_range, 3.8 + level * 1.1, delta * 4.0)
	glow_light.light_energy = move_toward(glow_light.light_energy, .65 + level * .22, delta)
	glow_halo.scale = glow_halo.scale.move_toward(Vector3.ONE * (1.0 + level * .3), delta * 2.0)
	for i in spark_meshes.size():
		spark_meshes[i].visible = i < game.sparks
		var angle = game.sim_time * 3.0 + TAU * i / 3.0
		spark_meshes[i].position = Vector3(cos(angle) * .55, 1.45 + sin(game.sim_time * 5.0 + i) * .06, sin(angle) * .55)

func dash() -> void:
	if dash_cooldown > 0 or dash_time > 0:
		return
	dash_direction = last_move
	dash_time = DASH_TIME
	dash_cooldown = 1.35 * (1.0 - clampf(Run.stats.dash_cd, 0, .75))
	invulnerability = .32
	Audio.play_sound("dash")
	game.make_noise(global_position, 2.0)
	Effects.ring_burst(game, global_position, Color("efd1a0"), 1.1)
	Effects.play("dash_dust", global_position + Vector3(0, .1, 0))
	if Run.stats.dash_nova > 0:
		var effects = Run.projectile_stats()
		effects.chill += 1
		for i in 12:
			var direction = Vector3.RIGHT.rotated(Vector3.UP, TAU * i / 12)
			game.spawn_shot(global_position + Vector3(0, .5, 0), direction, 5.0 * Run.stats.dash_nova, 10.0, effects, Color("b6e2e5"), true)

func hurt(amount: float, source: Vector3) -> void:
	if invulnerability > 0 or not Run.active or Run.has_flag("invulnerable"):
		return
	# Relic guard refreshes each room and is spent first; wards persist.
	if shield > 0 or Run.wards > 0:
		if shield > 0:
			shield -= 1
		else:
			Run.wards -= 1
			Run.changed.emit()
		invulnerability = .55
		Effects.play("ward", global_position + Vector3(0, .6, 0))
		Audio.play_sound("coin", .7)
		return
	Run.hp = maxf(0, Run.hp - amount)
	game.gutter()
	invulnerability = 1.0
	game.shake = .22
	game.hurt_flash = .75
	Audio.play_sound("hurt")
	Effects.play("hit_spark", global_position + Vector3.UP * .6, Color("ef9f7e"), 8)
	if Run.stats.thorns > 0:
		game.blast(global_position, 2.5, Run.stats.thorns * 3, true, null)
	velocity += (global_position - source).normalized() * 5
	Run.changed.emit()
	if Run.hp <= 0:
		game.end_run(false)
