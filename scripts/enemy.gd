class_name DungeonEnemy
extends CharacterBody3D
## A foe's body: health, statuses, movement, light and the hooks each kind
## fills in (scripts/foes/). The six original kinds live here; Foes.create
## builds the right script for any kind.
var game: Node3D
var entity_id = 0
var kind = "mote"
var hp = 20.0
var max_hp = 20.0
var speed = 2.0
var alive = true
var visual: Node3D
var eyes: Node3D
var radius = .4
var hit_height := 1.5
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
var charges_left = 0
var windup = 0.0
var warning: MeshInstance3D
var boss = false
var color = Color("bb7667")
const ROOM_MARGIN := .45
# Original kinds: health, speed, radius and colour; health grows 30% a floor.
const KINDS := {"mote": [15, 2.0, .37, "bf8173"], "spitter": [19, 1.25, .4, "9caaa1"],
	"charger": [25, 1.5, .44, "c68e65"], "splitter": [27, 1.65, .5, "9f8eb2"], "brute": [48, 1.15, .62, "968b78"],
	"wisp": [9, 3.3, .26, "d1b6d6"]}
const FLOOR_HEALTH := .3
# Bosses grow more slowly with depth: a middle floor's boss may come second
# or fourth in the climb.
const BOSS_DEPTH := .16
# Foes standing in a burning lantern's pool take this much more damage.
const EXPOSED_DAMAGE := 1.25
# Stable reward identity: "<room>:e<n>" for an encounter's foes, with
# splitter children derived from their parent. Summons have none, so they
# can never become an unlimited source of loot or kill credit.
var source = ""
var slow_time = 0.0
var slow_factor = 0.0
var last_valid = Vector3.ZERO
var path := PackedVector2Array()
var path_timer = 0.0
var path_initialized := false
var path_queries := 0
var sight_timer = 0.0
var has_sight = true
# Shots, seeking and blasts pass a foe that is not targetable (on a ceiling,
# withdrawn). An inert foe is part of a fight's scenery (a post, a dropped
# lantern): it never holds the room shut and goes when the fight ends.
var targetable = true
var inert = false
var contact_damage = true
var shrouded = false
var exposed = false
# Elite twist: "", "gilded", "twinned", "volatile" or "warded".
var elite = ""
var twin: DungeonEnemy
var ward_up = false
var ward_mesh: MeshInstance3D
var thread: MeshInstance3D
var gilded_drops = 0
# Lampwright's light hastes foes inside it for as long as this runs.
var aura_haste = 0.0
# A mote in a brute's hand: flying along an arc to land by the player.
var thrown: Dictionary = {}
# Splitter children that may fly back together; merged ones cannot again.
var sibling: DungeonEnemy
var can_merge = true
var merge_time = 0.0
var rng := RandomNumberGenerator.new()
var halo: MeshInstance3D
var restless = false
# A rim of the foe's colour and a white flash when struck, drawn over its
# body (foe_rim.gdshader); every foe shares one overlay material.
static var overlay: ShaderMaterial
var skin: Array = []
var flash = 0.0

func setup(owner_game: Node3D, type: String, id: int) -> void:
	game = owner_game
	kind = type
	entity_id = id
	rng.seed = Content.stable_hash("foe:%d:%s" % [id, type])
	add_to_group("enemies")
	var spec: Array = stats()
	boss = is_boss()
	max_hp = spec[0] * (1.0 + (Run.floor_number - 1) * (BOSS_DEPTH if boss else FLOOR_HEALTH))
	# A swarming floor sends more foes, each a little frailer.
	if Run.has_twist("swarming") and not boss: max_hp *= .8
	hp = max_hp
	restless = Run.has_twist("restless")
	speed = spec[1] * (1.0 + (Run.floor_number - 1) * .08) * (1.15 if restless else 1.0)
	radius = spec[2]
	color = Color(spec[3])
	collision_layer = 4
	collision_mask = 7 | PropVisuals.FURNITURE_LAYER
	var shape = CollisionShape3D.new()
	var sphere: Shape3D = CapsuleShape3D.new() if game.first_person else SphereShape3D.new()
	sphere.radius = radius
	if game.first_person: sphere.height = maxf(1.5, radius * 3.5)
	shape.shape = sphere
	shape.position.y = maxf(1.5, radius * 3.5) / 2 if game.first_person else radius
	add_child(shape)
	visual = Node3D.new()
	add_child(visual)
	# Foes stay readable on the dark lower floors: a faint glow of their own.
	var light = FloorLight.current()
	build_body(light)
	eyes = Node3D.new()
	visual.add_child(eyes)
	for x in [-.12, .12]:
		Geo.box(eyes, Vector3(x * radius * 2.2, eye_height(), -radius * .95), Vector3(.07, .1, .04) * (1.6 if boss else 1.0), Color("ffb9a3"), 1.5)
	halo = Geo.halo(self, Vector3(0, .022, 0), radius * 3.8, Color(color.r, color.g, color.b, light.foe_glow))
	timer = 1.0 + float(entity_id % 5) * .23
	prepare()
	if game.first_person:
		var top = 0.0
		for mesh in visual.find_children("*", "MeshInstance3D", true, false):
			var transform = visual.global_transform.affine_inverse() * mesh.global_transform
			var bounds: AABB = transform * mesh.get_aabb()
			top = maxf(top, bounds.end.y)
		hit_height = maxf(maxf(1.5, top * 1.5), radius * 2)
		sphere.height = hit_height
		shape.position.y = hit_height / 2
	dress_skin()

## The rim and flash overlay, from Balanced effects detail up.
func dress_skin() -> void:
	if Look.quality() == 0: return
	if overlay == null:
		overlay = ShaderMaterial.new()
		overlay.shader = preload("res://shaders/foe_rim.gdshader")
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		if node.get_parent() == eyes: continue
		node.material_overlay = overlay
		node.set_instance_shader_parameter("rim_tint", color.lightened(.35))
		skin.append(node)

func show_flash(delta: float) -> void:
	if flash <= 0: return
	flash = maxf(0, flash - delta * 9.0)
	for node in skin:
		if is_instance_valid(node): node.set_instance_shader_parameter("flash", flash)

## [health, speed, radius, colour] before floor scaling.
func stats() -> Array:
	return KINDS[kind]

func is_boss() -> bool:
	return false

func eye_height() -> float:
	return radius * 1.5

## The body; eyes, halo and collision are added around it.
func build_body(light: Dictionary) -> void:
	var body: MeshInstance3D
	if kind in ["brute", "charger"]:
		body = Geo.box(visual, Vector3(0, radius * 1.2, 0), Vector3(radius * 1.8, radius * 2.2, radius * 1.8), color, light.foe_body)
	else:
		body = Geo.sphere(visual, Vector3(0, radius * 1.1, 0), radius, color, light.foe_body)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## Called once the body exists.
func prepare() -> void:
	pass

func place(at: Vector3) -> void:
	position = at
	last_valid = at
	if game.first_person:
		path = PackedVector2Array()
		path_initialized = false
		path_timer = 0.0
		sight_timer = 0.0

func clearance() -> float:
	return 1.0 if radius > .7 else .5

## Direct pursuit while the way is clear; otherwise follow a staggered grid
## path so L bends and furniture never trap an enemy in a corner.
func steer_toward(target: Vector3, delta: float) -> Vector3:
	var direct = Vector3(target.x - position.x, 0, target.z - position.z).normalized()
	if not is_instance_valid(game.room) or not game.room.geometry:
		return direct
	var nav: RoomNavigation = game.room.navigation(clearance())
	var from = Vector2(position.x, position.z)
	var to = Vector2(target.x, target.z)
	sight_timer -= delta
	if sight_timer <= 0:
		sight_timer = .2
		has_sight = nav.line_clear(from, to)
	if has_sight:
		path = PackedVector2Array()
		path_initialized = false
		return direct
	path_timer -= delta
	# An empty result is still a completed search. Retrying it every frame
	# turns an unreachable target into dozens of full A* searches per foe.
	if path_timer <= 0 or (not path_initialized if game.first_person else path.is_empty()):
		path = nav.find_path(from, to)
		path_initialized = true
		path_queries += 1
		path_timer = .45 + float(entity_id % 7) * .06
	while path.size() > 1 and from.distance_to(path[0]) < .45:
		path.remove_at(0)
	if path.is_empty():
		return direct
	var step = path[0] - from
	return Vector3(step.x, 0, step.y).normalized() if step.length() > .01 else direct

func slow(duration: float, factor: float) -> void:
	slow_time = maxf(slow_time, duration)
	slow_factor = maxf(slow_factor if slow_time > 0 else 0.0, factor)

## What the floor underfoot (water, moss, ink) takes from this foe's pace.
func footing_drag() -> float:
	return game.residue.slows(global_position) if game.residue else 1.0

## How fast this foe's own clocks run: Lampwright's light hurries them, and
## so does a restless floor.
func tempo() -> float:
	return (1.35 if aura_haste > 0 else 1.0) * (1.15 if restless else 1.0)

func update_sim(delta: float) -> void:
	if not alive:
		return
	show_flash(delta)
	age += delta
	slow_time = maxf(0, slow_time - delta)
	aura_haste = maxf(0, aura_haste - delta)
	timer -= delta * tempo()
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
	if not thrown.is_empty():
		fly(delta)
		return
	update_light_state()
	var to_player: Vector3 = game.player.global_position - global_position
	to_player.y = 0
	var distance = to_player.length()
	var direction = to_player.normalized()
	var move_direction = behave(delta, distance, direction)
	# A gilded foe hurt past half runs from the player with its coins.
	if elite == "gilded" and hp < max_hp * .5 and charge_time <= 0:
		move_direction = -direction
	if windup > 0:
		windup -= delta * tempo()
		move_direction = Vector3.ZERO
		visual.scale = Vector3(1.0 + .12 * sin(age * 30), .88, 1.0)
		if windup <= 0:
			if is_instance_valid(warning):
				warning.queue_free()
			windup_done()
	if charge_time > 0:
		charge_time -= delta
		move_direction = charge_direction * charge_speed()
		if charge_time <= 0: charge_ended()
	else:
		for obstacle in game.room.obstacles:
			var away: Vector3 = global_position - obstacle.position
			var d = away.length()
			if d < 1.8 + radius and d > .01:
				move_direction += away.normalized() * (1.8 + radius - d) * 2.0
		# Local separation keeps a crowd from stacking into one blob.
		for other in game.enemies:
			if other == self or not is_instance_valid(other) or not other.alive or other.inert: continue
			var apart: Vector3 = global_position - other.global_position
			apart.y = 0
			var gap = apart.length()
			var wanted = radius + other.radius + .1
			if gap < wanted and gap > .01:
				move_direction += apart / gap * (wanted - gap) * 2.5
	var slow = maxf(.28, 1.0 - chill_power * .2) if chill_time > 0 else 1.0
	if slow_time > 0:
		slow *= 1.0 - slow_factor
	slow *= footing_drag()
	var wanted_velocity = move_direction * speed * slow * tempo()
	# On ice a foe keeps its momentum and turns wide.
	if game.residue and game.residue.kind_at(global_position) == "ice":
		velocity = (velocity - knock_velocity).lerp(wanted_velocity, minf(1.0, delta * 2.2)) + knock_velocity
	else:
		velocity = wanted_velocity + knock_velocity
	knock_velocity = knock_velocity.move_toward(Vector3.ZERO, delta * 20)
	if moves():
		var geometry: RoomGeometry = game.room.geometry
		if geometry.contains(Vector2(position.x, position.z), ROOM_MARGIN):
			last_valid = position
		move_and_slide()
		var kept = geometry.recover(Vector2(last_valid.x, last_valid.z), Vector2(position.x, position.z), ROOM_MARGIN)
		var walled = Vector2(kept.x, kept.y).distance_to(Vector2(position.x, position.z)) > .05
		for i in get_slide_collision_count():
			if get_slide_collision(i).get_collider() is StaticBody3D: walled = true
		position = Vector3(kept.x, game.room.floor_height(Vector3(kept.x, 0, kept.y)) if game.first_person else 0.0, kept.y)
		if charge_time > 0 and walled: hit_wall()
	if windup <= 0:
		visual.scale = visual.scale.lerp(Vector3.ONE, delta * 12)
	if game.first_person: visual.scale.y = maxf(visual.scale.y, 1.5)
	visual.position.y = sin(age * (4 if boss else 7) + entity_id) * .04
	if turns():
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), delta * 8)
	if is_instance_valid(thread) and is_instance_valid(twin) and twin.alive: stretch(thread, global_position + Vector3.UP * .6, twin.global_position + Vector3.UP * .6)
	if contact_damage and targetable and distance < radius + .45 and (not game.first_person or absf(game.player.global_position.y - global_position.y) < maxf(1.1, radius * 2.5)):
		game.player.hurt(1.0, global_position)
	after_move(delta, distance, direction)

## The kind's intent this tick: where to move (the original kinds' rules).
func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	var move_direction = steer_toward(game.player.global_position, delta)
	match kind:
		"spitter":
			if has_sight:
				move_direction = direction * (1.0 if distance > 5.5 else (-.5 if distance < 3.5 else 0.0))
				if timer <= 0:
					shoot_fan(direction, 3 if Run.floor_number > 1 else 1, .32)
					timer = 2.2
		"charger":
			if timer <= 0 and windup <= 0 and charge_time <= 0:
				begin_windup(direction, .7, .75, Color("ed9b77"))
				# High in the tower a charger rebounds off walls twice more.
				charges_left = 2 if Run.floor_number >= 3 else 0
				timer = 3.6
		"brute":
			if Run.floor_number >= 2 and timer <= 0 and distance > 3.5 and distance < 10.0:
				throw_mote(direction, distance)
		"wisp":
			move_direction = seek_sibling(delta, move_direction)
	return move_direction

func after_move(_delta: float, _distance: float, _direction: Vector3) -> void:
	pass

func moves() -> bool:
	return true

func turns() -> bool:
	return true

func begin_windup(direction: Vector3, length: float, ring: float, ring_color: Color) -> void:
	if game.first_person: Audio.play_at("dash", self, global_position, .6)
	windup = length
	charge_direction = direction
	if is_instance_valid(warning): warning.queue_free()
	warning = Geo.ring(self, Vector3(0, .05, 0), ring, ring_color, .06)

## A wind-up ends: by default the foe charges.
func windup_done() -> void:
	charge_time = charge_length()

func charge_length() -> float:
	return .55

func charge_speed() -> float:
	return 6.0

func charge_ended() -> void:
	pass

## A charge stopped by a wall: a third-floor charger turns to the player
## and goes again.
func hit_wall() -> void:
	if charges_left > 0:
		charges_left -= 1
		var back: Vector3 = game.player.global_position - global_position
		back.y = 0
		charge_direction = back.normalized()
		charge_time = 0.0
		begin_windup(charge_direction, .25, .6, Color("ed9b77"))

## Ground waves have a visible low silhouette; jumping clears them. Other
## attacks keep their own volumes instead of flattening the player's height.
func ground_wave_reaches(height := .45) -> bool:
	return not game.first_person or absf(game.player.global_position.y - global_position.y) < height

## Keep horizontal fan patterns while aiming their centre at chest height.
func aimed_direction(direction: Vector3, muzzle_height := .65) -> Vector3:
	if not game.first_person: return direction
	var flat_distance = maxf(.5, Vector2(game.player.position.x - position.x, game.player.position.z - position.z).length())
	direction.y = (game.player.position.y + .95 - (position.y + muzzle_height)) / flat_distance
	return direction.normalized()

func shoot_fan(direction: Vector3, count: int, spread: float, shot_speed := 5.0) -> void:
	if game.first_person:
		direction = aimed_direction(direction, .6)
		Audio.play_at("shoot", self, global_position, .65)
	for i in count:
		var angle = (float(i) / maxf(count - 1, 1) - .5) * spread
		var d = direction.rotated(Vector3.UP, angle)
		game.spawn_shot(global_position + Vector3.UP * .6 + d * (radius + .2), d, 1, shot_speed, {}, Color("f29d8c"), false)

## Lantern light still exposes a foe to extra damage. Ordinary bodies remain
## in the scene, so the room's actual lights and shadows determine their look;
## crossing a light radius or a cloud must never make the mesh disappear.
func update_light_state() -> void:
	exposed = game.room.lit_at(global_position)
	set_shrouded(false)

## Reserved for kinds with an explicit concealment mechanic, such as the
## Mourner. Submerged or ceiling foes keep their own independent visibility.
func set_shrouded(value: bool) -> void:
	if value == shrouded: return
	shrouded = value
	for child in visual.get_children():
		if child != eyes: child.visible = not value
	if is_instance_valid(halo): halo.visible = not value

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

## A friendly shot reaching this foe. Returns true when the foe dealt with it
## (absorbed or turned it); otherwise the shot hits as usual.
func catch_shot(_shot: EmberShot) -> bool:
	return false

## This foe's share of incoming damage, by cause: "shot", "blast", "dot",
## "dash", "orbital" or "hit".
func damage_scale(_cause: String) -> float:
	return 1.0

func take_hit(damage: float, impulse: Vector3, critical := false, dot := false, cause := "hit") -> void:
	if not alive or not targetable:
		return
	if dot: cause = "dot"
	if ward_up:
		if cause == "blast" or cause == "dash": pop_ward()
		else:
			if not dot: Effects.play("ward", global_position + Vector3.UP * radius)
			return
	damage *= damage_scale(cause)
	if exposed and not dot: damage *= EXPOSED_DAMAGE
	if damage <= 0: return
	if elite == "twinned" and is_instance_valid(twin) and twin.alive:
		twin.hp -= damage
	hp -= damage
	knock_velocity += impulse / (2.5 if boss else 1.0)
	if not dot:
		visual.scale = Vector3(1.17, .85, 1.17)
		flash = 1.0
		Effects.play("hit_spark", global_position + Vector3.UP * radius, Color("ffe0a8") if critical else color)
		Audio.play_sound("hit", 1.3 if critical else 1)
		game.damage_number(global_position + Vector3.UP * 1.1, damage, critical)
		if elite == "gilded": shed_coin()
	if critical:
		game.shake = maxf(game.shake, .07)
	if hp <= 0:
		die()
	elif elite == "twinned" and is_instance_valid(twin) and twin.alive and twin.hp <= 0:
		twin.die()

func die() -> void:
	if not alive:
		return
	if not allow_death(): return
	alive = false
	collision_layer = 0
	collision_mask = 0
	if not inert:
		game.player.haste_time = 2.0
	Effects.play("death_puff", global_position + Vector3.UP * .5, color, 12 if boss else 8, 1.5 if boss else 1.0)
	Audio.play_sound("kill", .6 if boss else 1)
	if kind == "splitter":
		var children: Array = []
		for slot in 2:
			var child = game.spawn_enemy(global_position + Vector3((slot * 2 - 1) * .45, 0, 0), "wisp", "%s.s%d" % [source, slot] if source != "" else "")
			child.can_merge = can_merge and Run.floor_number >= 2
			children.append(child)
		children[0].sibling = children[1]
		children[1].sibling = children[0]
	if elite == "volatile":
		for i in 10:
			var d = Vector3.RIGHT.rotated(Vector3.UP, TAU * i / 10.0 + age)
			game.spawn_shot(global_position + Vector3.UP * .6 + d * (radius + .2), d, 1, 4.5, {}, Color("f29d8c"), false)
	if elite == "twinned" and is_instance_valid(twin) and twin.alive:
		twin.die()
	if is_instance_valid(thread): thread.queue_free()
	on_death()
	game.on_enemy_killed(self)
	queue_free()

## What the boss bar shows.
func health_fraction() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)

## A kind may refuse to die yet (a boss changing phase, a bulb wilting).
func allow_death() -> bool:
	return true

func on_death() -> void:
	pass

## Lightning reaching this foe through water (ResidueField.shock).
func shocked(damage: float) -> void:
	take_hit(damage, Vector3.ZERO, false, false, "shot")

## The player dashed right through this foe.
func dashed_through() -> void:
	if ward_up: pop_ward()

## The player relit a lantern (the Last Light loses radiance to it).
func on_relight(_index: int) -> void:
	pass

## A friendly shot ended without striking a foe (the Mosskeeper grows moss).
func on_shot_missed(_shot: EmberShot) -> void:
	pass

## Volatile, gilded, twinned or warded: chosen by the encounter, from floor 2.
func make_elite(twist: String, partner: DungeonEnemy = null) -> void:
	elite = twist
	var tint = {"gilded": Color("ffd36b"), "twinned": Color("c9a4ff"), "volatile": Color("ff8a6a"), "warded": Color("a3dacf")}[twist]
	Geo.ring(self, Vector3(0, .04, 0), radius + .28, tint, .05)
	match twist:
		"warded":
			ward_up = true
			ward_mesh = Geo.sphere(self, Vector3(0, radius, 0), radius + .45, Color(.64, .86, .81), .5)
			ward_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ward_mesh.material_override = ward_material()
		"twinned":
			twin = partner
			if partner:
				partner.elite = "twinned"
				partner.twin = self
				Geo.ring(partner, Vector3(0, .04, 0), partner.radius + .28, tint, .05)
				# One shared pool: both bodies show what is left of the two.
				var pool = hp + partner.hp
				hp = pool
				max_hp = pool
				partner.hp = pool
				partner.max_hp = pool
				thread = Geo.box(game.scene_root, Vector3.ZERO, Vector3(.05, .05, 1.0), tint, 1.2)
				thread.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func ward_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(.64, .9, .84, .22)
	return mat

func pop_ward() -> void:
	ward_up = false
	if is_instance_valid(ward_mesh): ward_mesh.queue_free()
	Effects.play("ward", global_position + Vector3.UP * radius)
	Audio.play_sound("coin", .6)

## A gilded foe sheds a coin with each hit, a few at most, once per run.
func shed_coin() -> void:
	if gilded_drops >= 4 or source == "": return
	var data: Dictionary = Run.rooms[Run.current_room]
	var key = "%s:gild%d" % [source, gilded_drops]
	gilded_drops += 1
	if key in data.get("credited", []): return
	if not data.has("credited"): data.credited = []
	data.credited.append(key)
	game.spawn_pickup(global_position + Vector3(rng.randf_range(-.6, .6), 0, rng.randf_range(-.6, .6)), "copper_coin")

static func stretch(mesh: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var length = a.distance_to(b)
	mesh.visible = length > .05
	if length <= .05: return
	mesh.global_position = (a + b) / 2.0
	mesh.look_at(b, Vector3.UP if absf((b - a).normalized().y) < .99 else Vector3.RIGHT)
	mesh.scale = Vector3(1, 1, length)

## A brute on floor 2 and above picks up a nearby mote and hurls it to land
## beside the player.
func throw_mote(direction: Vector3, distance: float) -> void:
	timer = 5.5
	for other in game.enemies:
		if not is_instance_valid(other) or not other.alive or other.kind != "mote" or not other.thrown.is_empty(): continue
		if other.global_position.distance_to(global_position) > 3.0: continue
		var land: Vector3 = game.player.global_position - direction * minf(1.2, distance * .2)
		var safe = game.room.geometry.safe_point(Vector2(land.x, land.z), .5, game.room.blocked_at)
		var height: float = game.room.floor_height(Vector3(safe.x, 0, safe.y)) if game.first_person else 0.0
		other.thrown = {"from": other.global_position, "to": Vector3(safe.x, height, safe.y), "time": 0.0, "length": .9,
			"mark": Geo.ring(game.scene_root, Vector3(safe.x, height + .05, safe.y), 1.1, Color("ed9b77"), .06)}
		visual.scale = Vector3(1.2, .8, 1.2)
		return

func fly(delta: float) -> void:
	thrown.time += delta
	var t = clampf(thrown.time / thrown.length, 0.0, 1.0)
	position = thrown.from.lerp(thrown.to, t) + Vector3.UP * sin(t * PI) * 2.6
	if t >= 1.0:
		position = thrown.to
		last_valid = position
		if is_instance_valid(thrown.mark): thrown.mark.queue_free()
		thrown = {}
		Effects.ring_burst(game.scene_root, position, Color("d2a58a"), 1.1)
		if game.player.global_position.distance_to(position) < 1.1: game.player.hurt(1.0, position)

## Splitter children that both survive reach for each other and fuse back
## into a splitter (once).
func seek_sibling(delta: float, move_direction: Vector3) -> Vector3:
	if not can_merge or not is_instance_valid(sibling) or not sibling.alive: return move_direction
	merge_time += delta
	if merge_time < 4.0: return move_direction
	var to: Vector3 = sibling.global_position - global_position
	to.y = 0
	if to.length() < .6 and entity_id < sibling.entity_id:
		var fused = game.spawn_enemy((global_position + sibling.global_position) / 2.0, "splitter")
		fused.hp = fused.max_hp * .7
		fused.can_merge = false
		Effects.ring_burst(game.scene_root, fused.global_position, color, 1.2)
		for wisp in [self, sibling]:
			wisp.alive = false
			wisp.collision_layer = 0
			wisp.queue_free()
		return Vector3.ZERO
	return to.normalized() * 1.6
