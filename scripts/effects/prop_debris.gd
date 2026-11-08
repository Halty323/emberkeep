class_name PropDebris
extends Node3D
## A broken crate, barrel or jar crumbling apart. The body buckles and sinks
## in a tenth of a second while chunks of its own material burst out:
## planks from a crate, staves and both iron hoops from a barrel, curved
## shards from a jar. They tumble, bounce on the floor once or twice, settle
## and shrink away. Purely visual; the prop's collider is gone at once.
const LIFE := 1.5
const GRAVITY := 15.0
const BUCKLE := .12
var age := 0.0
var floor_y := 0.0
var body: Node3D
var body_scale := Vector3.ONE
# {"node", "velocity", "spin" (axis * rad/s), "half" (resting half height), "bounces"}
var pieces: Array = []

## Crumbles a prop's visual node (it is freed when the body has buckled).
static func crumble(parent: Node3D, kind: String, node: Node3D, size: Vector3) -> PropDebris:
	var debris := PropDebris.new()
	parent.add_child(debris)
	debris.global_transform = node.global_transform
	debris.floor_y = node.global_position.y
	debris.body = node
	debris.body_scale = node.scale
	var looks := materials_of(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(node.global_position)
	match kind:
		"barrel": debris.barrel(size, looks, rng)
		"jar": debris.jar(size, looks, rng)
		_: debris.crate(size, looks, rng)
	return debris

## The materials the prop wears, so its pieces match it in every renderer.
static func materials_of(node: Node3D) -> Array:
	var found: Array = []
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var look: Material = mesh.material_override if mesh.material_override else (mesh.mesh.surface_get_material(0) if mesh.mesh and mesh.mesh.get_surface_count() > 0 else null)
		if look and not found.has(look): found.append(look)
	return found

func piece(mesh: MeshInstance3D, look: Material, at: Vector3, out: Vector3, rng: RandomNumberGenerator, half: float, speed := 1.0) -> void:
	if look: mesh.material_override = look
	mesh.position = at
	mesh.rotation = Vector3(rng.randf_range(-.4, .4), rng.randf() * TAU, rng.randf_range(-.4, .4))
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flat := Vector3(out.x, 0, out.z).normalized() if Vector2(out.x, out.z).length() > .01 else Vector3.RIGHT.rotated(Vector3.UP, rng.randf() * TAU)
	var velocity := flat * rng.randf_range(1.4, 3.2) * speed + Vector3.UP * rng.randf_range(1.2, 3.4) * speed
	var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
	pieces.append({"node": mesh, "velocity": velocity, "spin": axis * rng.randf_range(5.0, 13.0), "half": half, "bounces": 0, "scale": mesh.scale})

func pick(looks: Array, index: int) -> Material:
	return looks[index % looks.size()] if not looks.is_empty() else null

## Planks and splinters, with the corner posts falling last.
func crate(size: Vector3, looks: Array, rng: RandomNumberGenerator) -> void:
	for i in 11:
		var long := rng.randf_range(.35, .95) * maxf(size.x, size.z)
		var at := Vector3(rng.randf_range(-.4, .4) * size.x, rng.randf_range(.15, .9) * size.y, rng.randf_range(-.4, .4) * size.z)
		piece(Geo.box(self, Vector3.ZERO, Vector3(long, .05, rng.randf_range(.1, .17)), PropVisuals.LIGHT_WOOD), pick(looks, i), at, at, rng, .03)
	for i in 6:
		var at := Vector3(rng.randf_range(-.4, .4) * size.x, rng.randf_range(.1, .8) * size.y, rng.randf_range(-.4, .4) * size.z)
		piece(Geo.box(self, Vector3.ZERO, Vector3(rng.randf_range(.06, .14), .04, rng.randf_range(.04, .08)), PropVisuals.DARK_WOOD), pick(looks, i + 1), at, at, rng, .02, 1.3)

## Staves spring out round the waist; the two hoops drop and roll.
func barrel(size: Vector3, looks: Array, rng: RandomNumberGenerator) -> void:
	var radius := size.x / 2.0 - .06
	for i in 10:
		var around := Vector3.RIGHT.rotated(Vector3.UP, TAU * i / 10.0 + rng.randf_range(-.1, .1))
		var stave := Geo.box(self, Vector3.ZERO, Vector3(.13, size.y * rng.randf_range(.55, .9), .045), PropVisuals.WOOD)
		piece(stave, pick(looks, i), around * radius + Vector3.UP * size.y * .5, around, rng, .025, .9)
		stave.rotation.y = -atan2(around.z, around.x) + PI / 2.0
	for y in [.18, size.y - .18]:
		var hoop := Geo.ring(self, Vector3.ZERO, radius, Color("5d5a52"), .03)
		piece(hoop, null, Vector3.UP * y, Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), rng, .03, .6)
	for i in 5:
		var at := Vector3(rng.randf_range(-.3, .3), rng.randf_range(.2, .9) * size.y, rng.randf_range(-.3, .3))
		piece(Geo.box(self, Vector3.ZERO, Vector3(.08, .04, .05), PropVisuals.DARK_WOOD), pick(looks, i), at, at, rng, .02, 1.3)

## Curved shards of fired clay and the jar's neck.
func jar(size: Vector3, looks: Array, rng: RandomNumberGenerator) -> void:
	var radius := size.x / 2.0
	for i in 12:
		var around := Vector3.RIGHT.rotated(Vector3.UP, rng.randf() * TAU)
		var shard := Geo.sphere(self, Vector3.ZERO, rng.randf_range(.07, .13), Color("a7684a"))
		shard.scale = Vector3(1.0, rng.randf_range(.7, 1.2), .25)
		piece(shard, pick(looks, i), around * radius * .8 + Vector3.UP * rng.randf_range(.1, .55), around, rng, .025, 1.1)
	var neck := Geo.cylinder(self, Vector3.ZERO, .1, .14, Color("b97a58"))
	piece(neck, pick(looks, 1), Vector3.UP * .62, Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), rng, .07, .5)

func _process(delta: float) -> void:
	age += delta
	if is_instance_valid(body):
		# The body buckles: it squashes, splays and sinks, then is gone.
		var t := clampf(age / BUCKLE, 0.0, 1.0)
		body.scale = body_scale * Vector3(1.0 + .25 * t, 1.0 - .8 * t * t, 1.0 + .25 * t)
		if t >= 1.0: body.queue_free()
	var fade := clampf((LIFE - age) / .35, 0.0, 1.0)
	for entry in pieces:
		var mesh: MeshInstance3D = entry.node
		var velocity: Vector3 = entry.velocity
		velocity.y -= GRAVITY * delta
		var at := mesh.position + velocity * delta
		var ground := floor_y - global_position.y + float(entry.half)
		if at.y < ground and velocity.y < 0:
			at.y = ground
			entry.bounces += 1
			if entry.bounces > 2 or absf(velocity.y) < 1.0:
				velocity = Vector3.ZERO
				entry.spin = Vector3.ZERO
				# Lying down: flatten the tumble onto the floor.
				mesh.rotation.x = lerpf(mesh.rotation.x, 0.0, .8)
				mesh.rotation.z = lerpf(mesh.rotation.z, 0.0, .8)
			else:
				velocity = Vector3(velocity.x * .55, -velocity.y * .38, velocity.z * .55)
				entry.spin = entry.spin * .5
		entry.velocity = velocity
		mesh.position = at
		var spin: Vector3 = entry.spin
		if spin.length_squared() > 0: mesh.rotate(spin.normalized(), spin.length() * delta)
		mesh.scale = entry.scale * fade
	if age >= LIFE:
		if is_instance_valid(body): body.queue_free()
		queue_free()
