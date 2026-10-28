class_name EffectPool
extends Node3D
## Room-owned cosmetic effects. Particles live in three shared MultiMesh
## batches (ambient, transient, floor marks) with fixed active-room budgets;
## rings and beams come from small node pools. Nothing here allocates per
## spark, touches gameplay state or uses a gameplay random stream, and the
## whole pool disappears with its room.
enum Priority { ATMOSPHERE, FEEDBACK, ESSENTIAL }
const BUDGETS := {
	"low": {"ambient": 28, "transient": 96, "marks": 24},
	"balanced": {"ambient": 44, "transient": 160, "marks": 40},
	"high": {"ambient": 64, "transient": 256, "marks": 64},
}
const RING_POOL := 10
const BEAM_POOL := 10
## Muzzle flecks per second at most, however fast a weapon fires.
const MUZZLE_RATE := 14.0
const IMPACT_RATE := 30.0

var game: Node3D
var geometry: RoomGeometry
var rng := RandomNumberGenerator.new()
var budget: Dictionary
var time := 0.0
var transient_mesh: MultiMeshInstance3D
var ambient_mesh: MultiMeshInstance3D
var mark_mesh: MultiMeshInstance3D
# Transient particles, packed: index < transient_count is alive.
var t_pos := PackedVector3Array()
var t_vel := PackedVector3Array()
var t_life := PackedFloat32Array()
var t_max := PackedFloat32Array()
var t_size := PackedFloat32Array()
var t_gravity := PackedFloat32Array()
var t_color := PackedColorArray()
var t_priority := PackedInt32Array()
var transient_count := 0
# Ambient slots: kind, origin, phase, color.
var ambient: Array[Dictionary] = []
# Floor marks: ring buffer.
var marks: Array[Dictionary] = []
var mark_next := 0
var rings: Array[Dictionary] = []
var beams: Array[Dictionary] = []
var muzzle_tokens := 4.0
var impact_tokens := 8.0
## Spawn requests refused because their channel was full (diagnostics/tests).
var dropped := 0

func setup(owner_game: Node3D, room_geometry: RoomGeometry, seed_value: int) -> void:
	game = owner_game
	geometry = room_geometry
	top_level = true
	# Cosmetic randomness has its own stream; it never feeds layout or loot.
	rng.seed = seed_value * 31 + 7
	budget = BUDGETS[Settings.values.effects_detail]
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	transient_mesh = _batch(cube, budget.transient, false)
	var mote := SphereMesh.new()
	mote.radius = .5
	mote.height = 1.0
	mote.radial_segments = 4
	mote.rings = 3
	ambient_mesh = _batch(mote, budget.ambient, false)
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	mark_mesh = _batch(quad, budget.marks, true)
	for i in RING_POOL:
		var mesh := TorusMesh.new()
		mesh.inner_radius = .46
		mesh.outer_radius = .54
		mesh.rings = 24
		mesh.ring_segments = 6
		rings.append({"node": _pooled(mesh), "age": 1.0, "life": .26, "radius": 1.0, "at": Vector3.ZERO})
	for i in BEAM_POOL:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(.045, .045, 1.0)
		beams.append({"node": _pooled(mesh), "age": 1.0, "life": .17, "length": 1.0})
	Effects.active = self

func _batch(mesh: Mesh, capacity: int, transparent: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		# Soft round marks rather than square decals.
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(.55, Color(1, 1, 1, .8))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(.5, .5)
		texture.fill_to = Vector2(1.0, .5)
		texture.width = 64
		texture.height = 64
		mat.albedo_texture = texture
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Unlit effects stay out of per-light and shadow passes.
	instance.layers = 2
	add_child(instance)
	return instance

func _pooled(mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.layers = 2
	node.visible = false
	add_child(node)
	return node

# --- Ambient ---------------------------------------------------------------

## Fill the ambient budget: a few candle wisps, rare lantern fireflies, shelf
## dust, and drifting embers for the rest. Not every object emits.
func populate_ambient(candles: Array, lanterns: Array, shelves: Array) -> void:
	ambient.clear()
	var total: int = budget.ambient
	var wisps := mini(candles.size(), total / 5)
	var flies := mini(lanterns.size(), maxi(1, total / 14))
	var dust := mini(shelves.size() * 2, total / 8)
	for i in wisps:
		ambient.append({"kind": "wisp", "origin": candles[(i * 7) % candles.size()], "phase": rng.randf() * 10.0})
	for i in flies:
		ambient.append({"kind": "firefly", "origin": lanterns[(i * 5) % lanterns.size()] + Vector3(0, 1.4, 0), "phase": rng.randf() * TAU})
	for i in dust:
		var shelf: Vector3 = shelves[i % shelves.size()]
		ambient.append({"kind": "dust", "origin": shelf + Vector3(rng.randf_range(-.6, .6), 0, rng.randf_range(-.3, .3)), "phase": rng.randf() * 10.0})
	while ambient.size() < total:
		var cell := geometry.cell_center(geometry.cells[ambient.size() % geometry.cells.size()])
		ambient.append({"kind": "ember", "origin": Vector3(cell.x + rng.randf_range(-9, 9), rng.randf_range(.1, 4.0), cell.y + rng.randf_range(-7, 7)), "phase": rng.randf() * TAU})
	ambient_mesh.multimesh.visible_instance_count = ambient.size()

func _update_ambient() -> void:
	var mm := ambient_mesh.multimesh
	for i in ambient.size():
		var slot: Dictionary = ambient[i]
		var p: Vector3 = slot.origin
		var size := .05
		var color := Color("efbc78")
		match slot.kind:
			"ember":
				p.y = fposmod(p.y + time * .16, 4.0)
				p.x += sin(time * .35 + i) * .25
			"wisp":
				var t := fposmod(time * .45 + slot.phase, 1.0)
				p += Vector3(sin(time * 2.0 + slot.phase) * .05, .2 + t * .9, 0)
				size = .06 * (1.0 - t)
				color = Color("ffd9a0")
			"firefly":
				# Rare: lit only briefly in a slow cycle.
				var glow := pow(maxf(0.0, sin(time * .21 + slot.phase)), 6.0)
				p += Vector3(sin(time * .7 + slot.phase) * 1.4, sin(time * 1.3 + slot.phase) * .4, cos(time * .5 + slot.phase) * 1.4)
				size = .07 * glow
				color = Color("e8f0a0")
			"dust":
				var t := fposmod(time * .08 + slot.phase, 1.0)
				p += Vector3(sin(time * .5 + slot.phase) * .2, 1.8 - t * 1.7, 0)
				size = .03 * sin(t * PI)
				color = Color("c9b99a")
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * maxf(size, .0001)), p))
		mm.set_instance_color(i, color)

# --- Transient -------------------------------------------------------------

func capacity() -> int:
	return budget.transient

## Emit one transient particle. When the batch is full, atmosphere is dropped
## and feedback replaces the oldest particle of equal or lower priority.
func emit(at: Vector3, velocity: Vector3, color: Color, size: float, life: float, priority := Priority.FEEDBACK, gravity := 4.0) -> bool:
	var index := transient_count
	if transient_count >= budget.transient:
		if priority == Priority.ATMOSPHERE:
			dropped += 1
			return false
		index = -1
		var best := INF
		for i in transient_count:
			if t_priority[i] > priority: continue
			var score := float(t_priority[i]) * 10.0 + t_life[i] / maxf(.01, t_max[i])
			if score < best:
				best = score
				index = i
		if index < 0:
			dropped += 1
			return false
	else:
		transient_count += 1
		if t_pos.size() < transient_count:
			t_pos.append(Vector3.ZERO); t_vel.append(Vector3.ZERO); t_life.append(0.0); t_max.append(0.0)
			t_size.append(0.0); t_gravity.append(0.0); t_color.append(Color.WHITE); t_priority.append(0)
	t_pos[index] = at
	t_vel[index] = velocity
	t_life[index] = life
	t_max[index] = life
	t_size[index] = minf(size, .35)
	t_gravity[index] = gravity
	t_color[index] = color
	t_priority[index] = priority
	return true

func _update_transient(delta: float) -> void:
	var i := 0
	while i < transient_count:
		t_life[i] -= delta
		if t_life[i] <= 0:
			transient_count -= 1
			if i != transient_count:
				t_pos[i] = t_pos[transient_count]; t_vel[i] = t_vel[transient_count]; t_life[i] = t_life[transient_count]
				t_max[i] = t_max[transient_count]; t_size[i] = t_size[transient_count]; t_gravity[i] = t_gravity[transient_count]
				t_color[i] = t_color[transient_count]; t_priority[i] = t_priority[transient_count]
			continue
		t_vel[i] = t_vel[i] * (1.0 - delta * 3.0) + Vector3.DOWN * t_gravity[i] * delta
		var p: Vector3 = t_pos[i] + t_vel[i] * delta
		if p.y < .03:
			p.y = .03
			t_vel[i] = Vector3(t_vel[i].x * .5, 0, t_vel[i].z * .5)
		t_pos[i] = p
		i += 1
	var mm := transient_mesh.multimesh
	for j in transient_count:
		var fade := t_life[j] / t_max[j]
		mm.set_instance_transform(j, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * t_size[j] * (.25 + .75 * fade)), t_pos[j]))
		mm.set_instance_color(j, t_color[j])
	mm.visible_instance_count = transient_count

## A spray of particles; `count` already scaled by the caller's recipe.
func spray(at: Vector3, color: Color, count: int, speed: float, size: float, life: float, priority := Priority.FEEDBACK, up := .6, gravity := 4.0) -> void:
	count = maxi(1, roundi(count * Settings.effects_scale()))
	for i in count:
		var angle := rng.randf() * TAU
		var direction := Vector3(cos(angle), up + rng.randf_range(-.3, .5), sin(angle))
		emit(at, direction * speed * rng.randf_range(.5, 1.0), color.lightened(rng.randf_range(-.08, .12)), size * rng.randf_range(.7, 1.1), life * rng.randf_range(.7, 1.0), priority, gravity)

# --- Rings, beams and floor marks -------------------------------------------

func ring(at: Vector3, color: Color, radius: float, life := .26) -> void:
	var slot: Dictionary = rings[0]
	for candidate in rings:
		if candidate.age >= candidate.life:
			slot = candidate
			break
		if candidate.age / candidate.life > slot.age / slot.life:
			slot = candidate
	slot.age = 0.0
	slot.life = life
	slot.radius = radius
	slot.at = at + Vector3(0, .06, 0)
	slot.node.material_override.albedo_color = color
	slot.node.position = slot.at
	slot.node.scale = Vector3(1, 1, 1)
	slot.node.visible = true

func beam(a: Vector3, b: Vector3, color: Color) -> void:
	var length := a.distance_to(b)
	if length < .01:
		return
	var slot: Dictionary = beams[0]
	for candidate in beams:
		if candidate.age >= candidate.life:
			slot = candidate
			break
		if candidate.age > slot.age:
			slot = candidate
	slot.age = 0.0
	slot.length = length
	slot.node.material_override.albedo_color = color
	slot.node.position = (a + b) / 2.0
	slot.node.look_at_from_position((a + b) / 2.0, b, Vector3.UP if absf((b - a).normalized().y) < .99 else Vector3.RIGHT)
	slot.node.scale = Vector3(1, 1, length)
	slot.node.visible = true

## A temporary floor-aligned mark, clipped to the room footprint.
func mark(at: Vector3, color: Color, radius: float, life := 6.0) -> bool:
	if not geometry.contains(at, radius * .7):
		dropped += 1
		return false
	var record := {"at": Vector3(at.x, .012 + float(mark_next % 8) * .0015, at.z), "color": color, "radius": radius, "age": 0.0, "life": life,
		"angle": rng.randf() * TAU}
	if marks.size() < budget.marks:
		marks.append(record)
	else:
		marks[mark_next % marks.size()] = record
	mark_next += 1
	return true

func _update_nodes(delta: float) -> void:
	for slot in rings:
		if not slot.node.visible: continue
		slot.age += delta
		if slot.age >= slot.life:
			slot.node.visible = false
			continue
		var t: float = slot.age / slot.life
		var s: float = lerpf(.5, slot.radius * 2.0, 1.0 - pow(1.0 - t, 2.0))
		slot.node.scale = Vector3(s, 1, s)
		slot.node.position.y = slot.at.y - .14 * t
	for slot in beams:
		if not slot.node.visible: continue
		slot.age += delta
		if slot.age >= slot.life:
			slot.node.visible = false
			continue
		var w: float = 1.0 - slot.age / slot.life
		slot.node.scale = Vector3(maxf(.05, w), maxf(.05, w), slot.length)
	var mm := mark_mesh.multimesh
	var live := 0
	var i := 0
	while i < marks.size():
		var record: Dictionary = marks[i]
		record.age += delta
		if record.age >= record.life:
			marks.remove_at(i)
			continue
		var fade: float = 1.0 - pow(record.age / record.life, 3.0)
		var basis := Basis(Vector3.UP, record.angle).scaled(Vector3(record.radius * 2.0, 1, record.radius * 2.0))
		mm.set_instance_transform(live, Transform3D(basis, record.at))
		mm.set_instance_color(live, Color(record.color, record.color.a * fade))
		live += 1
		i += 1
	mm.visible_instance_count = live

func _process(delta: float) -> void:
	# Effects freeze with the game; they never run gameplay.
	if is_instance_valid(game) and "paused" in game and game.paused and not game.in_menu:
		return
	time += delta
	muzzle_tokens = minf(4.0, muzzle_tokens + delta * MUZZLE_RATE)
	impact_tokens = minf(8.0, impact_tokens + delta * IMPACT_RATE)
	_update_ambient()
	_update_transient(delta)
	_update_nodes(delta)

func active_counts() -> Dictionary:
	return {"transient": transient_count, "ambient": ambient.size(), "marks": marks.size(),
		"rings": rings.filter(func(r): return r.node.visible).size(), "beams": beams.filter(func(b): return b.node.visible).size()}
