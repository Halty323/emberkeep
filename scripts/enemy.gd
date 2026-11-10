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
# When it was last hurt (its own age): a small health bar shows for a while.
var hurt_at := -100.0
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
var storey_path := PackedVector3Array()
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
# Co-op guest: the host's foe, drawn here. It never thinks for itself; every
# blow, status and shove it takes is sent to the host, which owns the foe.
var puppet := false
# Elements this foe carries (element -> seconds left) and when each landed.
# A different element landing on it sets off a reaction (Synergies).
var marks: Dictionary = {}
var marked_at: Dictionary = {}
var reaction_wait := 0.0
var frozen := 0.0
var brittle := 0.0
var flared := 0.0
var soak_bonus := 0.0
var frost_hits: Array = []
# Pairings and resonance riding on the statuses players put on it.
var keg := false
var jelly_owner := -1
var fire_leaps := 0
var mark_view: Node3D
var ice_shell: MeshInstance3D
const HEALTH_SCALE := 1.5
# A foe that has just appeared cannot hurt by touch yet: a moment to see it.
const SPAWN_GRACE := .6
static var pip_mesh: SphereMesh

## How much tougher foes are against the player's power: none with a
## starting spellbook, rising to HEALTH_SCALE as relics (eight) or doubled
## damage-and-rate arrive, whichever comes first.
static func health_scale() -> float:
	var power := float(Run.stats.get("damage", 1.0)) * float(Run.stats.get("rate", 1.0))
	var growth := maxf(Run.inventory.size() / 8.0, power - 1.0)
	return 1.0 + (HEALTH_SCALE - 1.0) * clampf(growth, 0.0, 1.0)

## A foe's name for the player: a boss as its floor calls it.
static func display_name(type: String) -> String:
	if type in Foes.BOSSES: return Foes.boss_name(type)
	return type.replace("_", " ").capitalize()

## The same name with its article: "A Spitter", "The Hearth Warden".
static func called(type: String) -> String:
	var name := display_name(type)
	if name.begins_with("The "): return name
	return ("An " if name.left(1) in ["A", "E", "I", "O", "U"] else "A ") + name

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
	if ExpeditionBalance.active_new_run(): max_hp *= ExpeditionBalance.foe_health(Run.floor_number,boss)
	# Combinations make players stronger; the upper floors answer.
	max_hp *= Synergies.TOUGHNESS[clampi(Run.floor_number, 0, Synergies.TOUGHNESS.size() - 1)]
	# Spells (and the relics that multiply them) hit hard: foes answer the
	# party's power, up to half again as much health.
	max_hp *= health_scale()
	hp = max_hp
	restless = Run.has_twist("restless")
	speed = spec[1] * (1.0 + (Run.floor_number - 1) * .08) * (1.15 if restless else 1.0)
	if ExpeditionBalance.active_new_run(): speed *= ExpeditionBalance.foe_speed(Run.floor_number)
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
	if ExpeditionBalance.active_new_run() and not inert:
		# Faster later patterns still give an entering player time to react.
		timer = maxf(timer,1.15*tempo())
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
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		if node.get_parent() == eyes: continue
		if gel(node):
			skin.append(node)
			continue
		# What cannot be gelatin (a crystal, a ghost, a flame) keeps the rim.
		if Look.quality() == 0: continue
		if overlay == null:
			overlay = ShaderMaterial.new()
			overlay.shader = preload("res://shaders/foe_rim.gdshader")
		node.material_overlay = overlay
		node.set_instance_shader_parameter("rim_tint", color.lightened(.35))
		skin.append(node)

## Turns one of a foe's meshes to gelatin (foe_jelly.gdshader), keeping its
## colour (made juicier) and its own glow. Only plain solid materials turn:
## glass, ghosts, crystals and anything that burns bright stay as they are.
## Safe to call again after a foe swaps a part's material.
static var jelly: ShaderMaterial
const JELLY_BRIGHT := 1.2
func gel(node: MeshInstance3D) -> bool:
	var source: Material = node.material_override
	if source == jelly and jelly != null: return true
	var plain := source as StandardMaterial3D
	if plain == null or plain.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: return false
	var shine: float = plain.emission_energy_multiplier if plain.emission_enabled else 0.0
	if shine > JELLY_BRIGHT: return false
	if jelly == null:
		jelly = ShaderMaterial.new()
		jelly.shader = preload("res://shaders/foe_jelly.gdshader")
	var tint: Color = plain.albedo_color
	tint.s = clampf(tint.s * 1.5 + .22, 0.0, 1.0)
	tint.v = clampf(tint.v * 1.12 + .06, 0.0, 1.0)
	node.material_override = jelly
	node.mesh = set_shape(node.mesh)
	node.set_instance_shader_parameter("jelly_tint", tint)
	node.set_instance_shader_parameter("glow", shine)
	node.set_instance_shader_parameter("lift", to_local(node.global_position).y if is_inside_tree() and node.is_inside_tree() else node.position.y)
	return true

## Gelatin is set in a mould: round shapes are smooth, and a block's edges
## and corners are rounded off. One shared mesh for each shape and size.
static var moulds: Dictionary = {}
static func set_shape(mesh: Mesh) -> Mesh:
	if mesh == null or mesh.has_meta("moulded"): return mesh
	var key := ""
	if mesh is SphereMesh: key = "s%.3f/%.3f" % [mesh.radius, mesh.height]
	elif mesh is CylinderMesh: key = "c%.3f/%.3f/%.3f" % [mesh.top_radius, mesh.bottom_radius, mesh.height]
	elif mesh is BoxMesh: key = "b%s" % str(mesh.size)
	else: return mesh
	if moulds.has(key): return moulds[key]
	var made: Mesh
	if mesh is SphereMesh:
		var ball := SphereMesh.new()
		ball.radius = mesh.radius
		ball.height = mesh.height
		ball.radial_segments = 28
		ball.rings = 14
		made = ball
	elif mesh is CylinderMesh:
		var drum := CylinderMesh.new()
		drum.top_radius = mesh.top_radius
		drum.bottom_radius = mesh.bottom_radius
		drum.height = mesh.height
		drum.radial_segments = 28
		drum.rings = 3
		made = drum
	else:
		made = rounded_block(mesh.size)
	made.set_meta("moulded", true)
	moulds[key] = made
	return made

## A block with its edges and corners rounded: each point of a subdivided
## box is pulled in to an inner box and pushed back out by the same radius.
static func rounded_block(size: Vector3) -> ArrayMesh:
	var source := BoxMesh.new()
	source.size = size
	source.subdivide_width = 5
	source.subdivide_height = 5
	source.subdivide_depth = 5
	var arrays: Array = source.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var radius := minf(minf(size.x, minf(size.y, size.z)) * .32, .13)
	var inner := size / 2.0 - Vector3.ONE * radius
	for i in points.size():
		var p := points[i]
		var core := Vector3(clampf(p.x, -inner.x, inner.x), clampf(p.y, -inner.y, inner.y), clampf(p.z, -inner.z, inner.z))
		var out := p - core
		if out.length() > .0001:
			normals[i] = out.normalized()
			points[i] = core + normals[i] * radius
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# A struck foe shudders for a moment after its flash has gone.
var wobble := 0.0
func show_flash(delta: float) -> void:
	if flash <= 0 and wobble <= 0: return
	flash = maxf(0, flash - delta * 9.0)
	wobble = maxf(0, wobble - delta * 1.8)
	for node in skin:
		if not is_instance_valid(node): continue
		node.set_instance_shader_parameter("flash", flash)
		node.set_instance_shader_parameter("jiggle", wobble)

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
		storey_path=PackedVector3Array()
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
	if game.first_person and game.room.terrain and game.room.terrain.loft:
		sight_timer-=delta
		if sight_timer<=0:
			sight_timer=.2
			has_sight=absf(target.y-position.y)<.75 and get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(position+Vector3.UP,target+Vector3.UP,1|PropVisuals.FURNITURE_LAYER)).is_empty()
		path_timer-=delta
		if path_timer<=0 or not path_initialized:
			storey_path=game.room.terrain.loft.route(game.room,position,target,clearance())
			path_initialized=true
			path_queries+=1
			path_timer=.45+float(entity_id%7)*.06
		while storey_path.size()>1 and Vector2(position.x-storey_path[0].x,position.z-storey_path[0].z).length()<.45 and absf(position.y-storey_path[0].y)<.6:
			storey_path.remove_at(0)
		if storey_path.is_empty(): return Vector3.ZERO
		return Vector3(storey_path[0].x-position.x,0,storey_path[0].z-position.z).normalized()
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
	if puppet:
		game.party.foe_slow(self, duration, factor)
		return
	slow_time = maxf(slow_time, duration)
	slow_factor = maxf(slow_factor if slow_time > 0 else 0.0, factor)

## What the floor underfoot (water, moss, ink) takes from this foe's pace.
func footing_drag() -> float:
	return game.residue.slows(global_position) if game.residue else 1.0

## How fast this foe's own clocks run: Lampwright's light hurries them, and
## so does a restless floor.
func tempo() -> float:
	return (1.35 if aura_haste > 0 else 1.0) * (1.15 if restless else 1.0) * (ExpeditionBalance.foe_tempo(Run.floor_number) if ExpeditionBalance.active_new_run() else 1.0)

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
	reaction_wait = maxf(0, reaction_wait - delta)
	brittle = maxf(0, brittle - delta)
	flared = maxf(0, flared - delta)
	fade_marks(delta)
	dot_tick -= delta
	if dot_tick <= 0:
		dot_tick = .4
		var damage = (burn_power if burn_time > 0 else 0.0) + (poison_power if poison_time > 0 else 0.0)
		if damage > 0:
			take_hit(damage, Vector3.ZERO, false, true)
			if not alive:
				return
		# What it stands in clings to it: water soaks, wax coats, ice chills.
		if game.residue and (not game.first_person or game.residue.touches_floor(global_position)):
			match game.residue.kind_at(global_position):
				"water": mark("tide", 1.2)
				"wax": mark("wax", 1.2)
				"ice": mark("frost", 1.2)
	if frozen > 0:
		# Frozen solid: it neither moves nor strikes until it thaws.
		frozen -= delta
		velocity = Vector3.ZERO
		knock_velocity = Vector3.ZERO
		if frozen <= 0: thaw()
		return
	if not thrown.is_empty():
		fly(delta)
		return
	update_light_state()
	var to_player: Vector3 = game.player.global_position - global_position
	to_player.y = 0
	var distance = to_player.length()
	var direction = to_player.normalized()
	# All mobile kinds must use the staircase before their individual attack
	# rules take over. Several subclasses otherwise lunge at the player below
	# the slab or orbit the same horizontal position on the wrong floor.
	var changing_storey: bool = game.first_person and game.room.terrain and game.room.terrain.loft and moves() and (absf(game.player.position.y-position.y)>.75 or game.room.terrain.loft.stairs.has_point(Vector2(position.x,position.z)))
	var move_direction: Vector3
	if changing_storey:
		move_direction=steer_toward(game.player.global_position,delta)
		charge_time=0
		windup=0
		if is_instance_valid(warning): warning.queue_free()
	else:
		move_direction=behave(delta,distance,direction)
	# A gilded foe hurt past half runs from the player with its coins.
	if elite == "gilded" and hp < max_hp * .5 and charge_time <= 0:
		move_direction = -direction
	if windup > 0:
		# Difficulty accelerates cooldowns, not the visible warning itself.
		windup -= delta * tempo() / (ExpeditionBalance.foe_tempo(Run.floor_number) if ExpeditionBalance.active_new_run() else 1.0)
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
			if game.first_person and absf(other.global_position.y-global_position.y)>.8: continue
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
	# Difficulty cadence accelerates attacks, not walking a second time.
	var movement_tempo = tempo() / (ExpeditionBalance.foe_tempo(Run.floor_number) if ExpeditionBalance.active_new_run() else 1.0)
	var wanted_velocity = move_direction * speed * slow * movement_tempo
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
		var floor_y: float = game.room.floor_height(Vector3(kept.x,0,kept.y)) if game.first_person else 0.0
		if game.first_person and game.room.terrain:
			floor_y = game.room.terrain.standing_height(kept,radius,position.y)
		position = Vector3(kept.x,floor_y,kept.y)
		if charge_time > 0 and walled: hit_wall()
	if windup <= 0:
		visual.scale = visual.scale.lerp(Vector3.ONE, delta * 12)
	if game.first_person: visual.scale.y = maxf(visual.scale.y, 1.5)
	visual.position.y = sin(age * (4 if boss else 7) + entity_id) * .04
	if turns():
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), delta * 8)
	if is_instance_valid(thread) and is_instance_valid(twin) and twin.alive: stretch(thread, global_position + Vector3.UP * .6, twin.global_position + Vector3.UP * .6)
	if contact_damage and targetable and age > SPAWN_GRACE and distance < radius + .45 and (not game.first_person or absf(game.player.global_position.y - global_position.y) < maxf(1.1, radius * 2.5)):
		game.player.hurt(1.0, global_position)
	after_move(delta, distance, direction)

## The kind's intent this tick: where to move (the original kinds' rules).
func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	var move_direction = steer_toward(game.player.global_position, delta)
	if game.first_person and game.room.terrain and game.room.terrain.loft and absf(game.player.position.y-position.y)>.75: return move_direction
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
	if puppet:
		game.party.foe_status(self, stats)
		return
	if stats.get("burn", 0) > 0:
		burn_time = 3.0
		burn_power = maxf(burn_power, stats.burn * 1.8)
	if stats.get("chill", 0) > 0:
		chill_time = 2.5
		chill_power = maxf(chill_power, stats.chill)
	if stats.get("poison", 0) > 0:
		poison_time = 4.0
		var dose: float = stats.poison * 2.1
		# Virulence: a venom book's resonance lets poison build.
		if str(stats.get("element", "")) == "venom" and float(stats.get("resonance", 0)) > 0:
			poison_power = minf(poison_power + dose * .5, dose * (1.0 + float(stats.resonance)))
		poison_power = maxf(poison_power, dose)
	touch(stats)

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
	if puppet:
		game.party.foe_hit(self, damage, impulse, critical, dot, cause)
		return
	# Whoever struck it, the guests see it struck.
	var net = NetHooks.party(game)
	if net: net.begin_world()
	receive_hit(damage, impulse, critical, dot, cause)
	if net: net.end_world()

## A push away from something (a gust, a gale); on a guest, sent to the host.
func shove(force: Vector3) -> void:
	if puppet: game.party.foe_shove(self, force)
	else: knock_velocity += force

func receive_hit(damage: float, impulse: Vector3, critical: bool, dot: bool, cause: String) -> void:
	if dot: cause = "dot"
	if ward_up:
		if cause == "blast" or cause == "dash": pop_ward()
		else:
			if not dot: Effects.play("ward", global_position + Vector3.UP * radius)
			return
	damage *= damage_scale(cause)
	if exposed and not dot: damage *= EXPOSED_DAMAGE
	# Reactions that leave a foe open: frozen, brittle, laid bare, soaked.
	if frozen > 0: damage *= 1.5
	if brittle > 0: damage *= 1.4
	if flared > 0: damage *= 1.3
	if soak_bonus > 0 and marks.has("tide"): damage *= 1.0 + soak_bonus
	if damage <= 0: return
	if elite == "twinned" and is_instance_valid(twin) and twin.alive:
		twin.hp -= damage
	hp -= damage
	hurt_at = age
	knock_velocity += impulse / (2.5 if boss else 1.0)
	if not dot:
		visual.scale = Vector3(1.17, .85, 1.17)
		flash = 1.0
		wobble = 1.0
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
	last_rites()
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
	if puppet:
		game.party.foe_dashed(self)
		return
	if ward_up: pop_ward()

## The player relit a lantern (the Last Light loses radiance to it).
func on_relight(_index: int) -> void:
	pass

## A friendly shot ended without striking a foe (the Mosskeeper grows moss).
func on_shot_missed(_shot: EmberShot) -> void:
	pass

## Volatile, gilded, twinned or warded: chosen by the encounter, from floor 2.
func make_elite(twist: String, partner: DungeonEnemy = null) -> void:
	var net = NetHooks.party(game)
	if net: net.geo_paused += 1
	dress_elite(twist, partner)
	if net:
		net.geo_paused -= 1
		net.foe_elite(self, twist, partner)

func dress_elite(twist: String, partner: DungeonEnemy) -> void:
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
	if gilded_drops >= (2 if ExpeditionBalance.active_new_run() else 4) or source == "": return
	var data: Dictionary = Run.rooms[Run.current_room]
	var key = "%s:gild%d" % [source, gilded_drops]
	gilded_drops += 1
	if key in data.get("credited", []): return
	if not data.has("credited"): data.credited = []
	data.credited.append(key)
	var at := global_position + Vector3(rng.randf_range(-.6, .6), 0, rng.randf_range(-.6, .6))
	game.spawn_pickup(at, "copper_coin")
	# Every teammate gets a coin of their own.
	if NetHooks.party(game): game.party.loot(at, "copper_coin")

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
		var height: float = game.room.floor_height(Vector3(safe.x, game.player.position.y, safe.y)) if game.first_person else 0.0
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

# ---------------------------------------------------------------- combinations

## A status, spell or blast lands: it leaves its elements on the foe, or, if
## the foe already carries a different one, sets off their reaction.
func touch(stats: Dictionary) -> void:
	if not alive: return
	var element := str(stats.get("element", ""))
	var resonance := float(stats.get("resonance", 0))
	if float(stats.get("keg", 0)) > 0 and float(stats.get("burn", 0)) > 0: keg = true
	if float(stats.get("jelly", 0)) > 0 and float(stats.get("poison", 0)) > 0: jelly_owner = int(stats.get("owner", 0))
	if float(stats.get("burn", 0)) > 0 and element == "ember" and resonance > 0: fire_leaps = maxi(fire_leaps, int(resonance))
	if float(stats.get("freeze", 0)) > 0: freeze(1.6)
	if resonance > 0:
		match element:
			"radiance": flared = maxf(flared, 1.5 + resonance)
			"wax": slow(1.5, minf(.5, .15 * resonance))
			"tide": soak_bonus = maxf(soak_bonus, .12 * resonance)
			"frost":
				# Deep Cold: frost hits in quick succession freeze solid.
				frost_hits = frost_hits.filter(func(at): return age - at < 3.0)
				frost_hits.append(age)
				if frost_hits.size() >= maxi(2, 4 - int(resonance)):
					frost_hits.clear()
					freeze(1.4)
	var incoming: Array = Synergies.elements_of(stats)
	if incoming.is_empty(): return
	if reaction_wait <= 0:
		for arriving in incoming:
			for carried in marks.keys():
				# Elements that landed together in one blow never react.
				if carried == arriving or age - float(marked_at.get(carried, -9.0)) < .05: continue
				var reaction := Synergies.reaction(arriving, carried)
				if reaction == "": continue
				marks.erase(carried)
				show_marks()
				react(reaction, arriving, float(stats.get("hit", 0)), stats)
				return
	for arriving in incoming: mark(arriving, Synergies.MARK_TIME)

func mark(element: String, seconds: float) -> void:
	var fresh := not marks.has(element)
	if fresh: marked_at[element] = age
	marks[element] = maxf(float(marks.get(element, 0.0)), seconds)
	if fresh: show_marks()

func fade_marks(delta: float) -> void:
	if marks.is_empty(): return
	var changed := false
	for element in marks.keys():
		marks[element] = float(marks[element]) - delta
		if marks[element] <= 0:
			marks.erase(element)
			changed = true
	if changed: show_marks()

## A small glint above the foe for each element it carries.
func show_marks() -> void:
	if not is_instance_valid(mark_view):
		mark_view = Node3D.new()
		mark_view.name = "ElementMarks"
		add_child(mark_view)
		mark_view.position.y = maxf(hit_height, radius * 2.5) + .25
	for child in mark_view.get_children(): child.queue_free()
	var shown: Array = Synergies.ELEMENT_ORDER.filter(func(element): return marks.has(element))
	if pip_mesh == null:
		pip_mesh = SphereMesh.new()
		pip_mesh.radius = .07
		pip_mesh.height = .14
		pip_mesh.radial_segments = 8
		pip_mesh.rings = 4
	for i in shown.size():
		var pip := MeshInstance3D.new()
		pip.mesh = pip_mesh
		pip.material_override = Geo.material(Synergies.element_color(shown[i]), .9)
		pip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pip.position = Vector3((i - (shown.size() - 1) / 2.0) * .2, 0, 0)
		mark_view.add_child(pip)

## The elements carried, as bits for the co-op snapshot.
func mark_bits() -> int:
	var bits := 0
	for i in Synergies.ELEMENT_ORDER.size():
		if marks.has(Synergies.ELEMENT_ORDER[i]): bits |= 1 << i
	return bits

func show_mark_bits(bits: int) -> void:
	var before := mark_bits()
	if before == bits: return
	marks.clear()
	for i in Synergies.ELEMENT_ORDER.size():
		if bits & (1 << i): marks[Synergies.ELEMENT_ORDER[i]] = Synergies.MARK_TIME
	show_marks()

## Two elements meet on this foe.
func react(id: String, arriving: String, power: float, stats: Dictionary) -> void:
	reaction_wait = Synergies.BOSS_REACTION_COOLDOWN if boss else Synergies.REACTION_COOLDOWN
	var blow := maxf(power, 6.0 + 3.0 * Run.floor_number)
	var center := global_position + Vector3.UP * minf(hit_height * .5, 1.2)
	var color := Synergies.reaction_color(id)
	game.reaction_word(center + Vector3.UP * .8, id)
	Effects.ring_burst(game.scene_root, global_position + Vector3.UP * .05, color, 1.5)
	Effects.burst(game.scene_root, center, color, 12, 1.4)
	match id:
		"shatter":
			for foe in nearby(2.0): foe.take_hit(blow, (foe.global_position - global_position).normalized() * 2.0, false, false, "reaction")
			take_hit(blow * 3.0, Vector3.ZERO, true, false, "reaction")
		"steam":
			if game.residue: game.residue.add_cloud(global_position, 1.8, "steam")
			for foe in nearby(2.6, true):
				foe.slow(2.0, .5)
				foe.take_hit(blow * 1.5, Vector3.ZERO, false, false, "reaction")
		"blight":
			for foe in nearby(3.2, true):
				foe.burn_time = maxf(foe.burn_time, 3.0)
				foe.burn_power = maxf(foe.burn_power, 2.4)
				foe.poison_time = maxf(foe.poison_time, 4.0)
				foe.poison_power = maxf(foe.poison_power, 2.4)
				foe.take_hit(blow * 1.2, Vector3.ZERO, false, false, "reaction")
		"overload":
			game.blast(center, 2.8, blow * 2.4, true, null)
		"wildfire":
			burn_time = 6.0
			burn_power = maxf(burn_power * 2.0, 4.0)
			if game.residue:
				game.residue.add("wax", global_position, 1.3)
				game.residue.ignite(global_position, 1.3, true)
			take_hit(blow, Vector3.ZERO, false, false, "reaction")
		"freeze": freeze(2.6)
		"brittle":
			brittle = 5.0
			take_hit(blow * .5, Vector3.ZERO, false, false, "reaction")
		"set": slow(2.2, .4 if boss else 1.0)
		"surge":
			var struck := 0
			for foe in game.enemies.duplicate():
				if not is_instance_valid(foe) or not foe.alive or not foe.targetable or foe == self: continue
				var soaked: bool = foe.marks.has("tide") or (game.residue and game.residue.kind_at(foe.global_position) == "water")
				if not soaked: continue
				struck += 1
				Effects.beam(game.scene_root, center, foe.global_position + Vector3.UP * .8, Color("c4c2ff"))
				foe.take_hit(blow * 1.8, Vector3.ZERO, false, false, "reaction")
			take_hit(blow * (1.8 + .2 * struck), Vector3.ZERO, false, false, "reaction")
		"flare":
			flared = 5.0
			take_hit(blow * .6, Vector3.ZERO, false, false, "reaction")
		"refract": shards(4, Synergies.element_stats(arriving), blow * .7, .55)
		"prism":
			var beams := Synergies.element_stats("radiance")
			beams.homing = 4.0
			shards(6, beams, blow * .8, TAU / 6.0)
	if float(stats.get("northern", 0)) > 0 and id in ["surge", "overload"]: freeze(1.2)

## Foes within reach of this one (and this one too, if asked).
func nearby(reach: float, include_self := false) -> Array:
	var result: Array = []
	for foe in game.enemies.duplicate():
		if not is_instance_valid(foe) or not foe.alive or not foe.targetable: continue
		if foe == self and not include_self: continue
		if foe.global_position.distance_to(global_position) <= reach + foe.radius: result.append(foe)
	return result

## Shards burst outward from this foe, carrying an element on.
func shards(count: int, stats: Dictionary, power: float, step: float) -> void:
	var start := randf() * TAU
	for i in count:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, start + i * step)
		var at: Vector3 = global_position + Vector3.UP * minf(hit_height * .5, 1.1) + direction * (radius + .25)
		var shot = game.spawn_shot(at, direction, power, 13.0, stats, Synergies.element_color(str(stats.get("element", "glass"))), true)
		if shot: shot.hit_ids[entity_id] = true

## Frozen solid: no movement, no attacks, more damage taken.
func freeze(seconds: float) -> void:
	if not alive: return
	frozen = maxf(frozen, seconds * (.3 if boss else 1.0))
	windup = 0.0
	charge_time = 0.0
	if is_instance_valid(warning): warning.queue_free()
	show_ice(true)

func thaw() -> void:
	frozen = 0.0
	show_ice(false)

func show_ice(on: bool) -> void:
	if on and not is_instance_valid(ice_shell):
		var mesh := SphereMesh.new()
		mesh.radius = maxf(radius * 1.5, .5)
		mesh.height = maxf(hit_height * 1.1, mesh.radius * 2.0)
		ice_shell = MeshInstance3D.new()
		ice_shell.mesh = mesh
		var glass := StandardMaterial3D.new()
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.albedo_color = Color(.75, .93, 1.0, .38)
		glass.emission_enabled = true
		glass.emission = Color("9fdcf0")
		glass.emission_energy_multiplier = .4
		glass.roughness = .1
		ice_shell.material_override = glass
		ice_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ice_shell.position.y = mesh.height * .5
		add_child(ice_shell)
	elif not on and is_instance_valid(ice_shell):
		ice_shell.queue_free()
		ice_shell = null

## What a foe's fall sets off: Powder Keg, Spreading Fire, Royal Jelly.
func last_rites() -> void:
	if inert: return
	var center := global_position + Vector3.UP * .5
	if keg and burn_time > 0:
		game.reaction_word(center + Vector3.UP * .8, "p:powder_keg")
		game.blast(center, 2.6, maxf(16.0, 8.0 + 4.0 * Run.floor_number), true, self)
	if fire_leaps > 0 and burn_time > 0:
		var near := nearby(4.5)
		near.sort_custom(func(a, b): return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
		for foe in near.slice(0, fire_leaps):
			Effects.beam(game.scene_root, center, foe.global_position + Vector3.UP * .6, Color("ff9a5a"))
			foe.apply_status({"burn": burn_power / 1.8, "element": "ember"})
	if jelly_owner >= 0 and poison_time > 0: game.heal_player(jelly_owner, .5)
