class_name EffectsPool
extends Node3D
## Room-owned pool behind the Effects facade. Compact particles share one
## MultiMesh; rings, beams and floor marks reuse a fixed set of nodes, so
## effects never grow the scene. Budgets are active-room totals for the
## chosen detail level. Important feedback can displace atmosphere, which is
## dropped first; essential attack telegraphs are gameplay views and never
## pass through here. Cosmetic randomness has its own stream and never
## touches layout, loot, critical hits or weapon spread.
static var current: EffectsPool
const CHANNELS := {"important": 0, "atmosphere": 1, "ambient": 2}
const MAX_RINGS := 10
const MAX_BEAMS := 12
const DRAG := .985
var rng := RandomNumberGenerator.new()
var budgets: Dictionary = {}
var positions := PackedVector3Array()
var velocities := PackedVector3Array()
var colors := PackedColorArray()
var ages := PackedFloat32Array()
var lives := PackedFloat32Array()
var sizes := PackedFloat32Array()
var gravities := PackedFloat32Array()
var channels := PackedInt32Array()
var count := 0
var channel_counts := [0, 0, 0]
var dropped := [0, 0, 0]
var particles: MultiMeshInstance3D
var rings: Array = []
var beams: Array = []
var marks: Array = []
var emitters: Array = []
var last_emit: Dictionary = {}
var clock := 0.0
var ambient_reserved := 0
static var particle_material: StandardMaterial3D

func _init() -> void:
	rng.randomize()
	name = "Effects"

func _enter_tree() -> void:
	current = self
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	if budgets.is_empty():
		configure()

func _exit_tree() -> void:
	if current == self:
		current = null
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)

func _on_setting_changed(key: String) -> void:
	if key == "effects_detail":
		configure()

## Sizes the pool for the current detail level and clears live particles.
## `reserved_ambient` is spent by the room's own drifting embers.
func configure(reserved_ambient := ambient_reserved) -> void:
	ambient_reserved = reserved_ambient
	budgets = {"transient": Settings.effect_budget("transient"), "marks": Settings.effect_budget("marks"),
		"ambient": maxi(0, Settings.effect_budget("ambient") - ambient_reserved)}
	var capacity: int = budgets.transient + budgets.ambient
	for array in [positions, velocities, colors, ages, lives, sizes, gravities, channels]:
		array.resize(capacity)
	count = 0
	channel_counts = [0, 0, 0]
	if particles == null:
		particles = MultiMeshInstance3D.new()
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		particles.layers = 2
		particles.material_override = material()
		add_child(particles)
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Geo.shared_box(Vector3.ONE)
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	particles.multimesh = mm

static func material() -> StandardMaterial3D:
	if particle_material == null:
		particle_material = StandardMaterial3D.new()
		particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		particle_material.vertex_color_use_as_albedo = true
	return particle_material

func transient_count() -> int:
	return channel_counts[0] + channel_counts[1]

func has_room_for(channel: int) -> bool:
	if channel == CHANNELS.ambient:
		return channel_counts[channel] < budgets.ambient
	if transient_count() < budgets.transient:
		return true
	# Important feedback displaces atmosphere; atmosphere is simply dropped.
	if channel == CHANNELS.important and channel_counts[CHANNELS.atmosphere] > 0:
		for i in count:
			if channels[i] == CHANNELS.atmosphere:
				remove_particle(i)
				return true
	return false

func visible_point(at: Vector3) -> bool:
	var camera = get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera == null or camera.is_position_in_frustum(at)

## Emits a recipe. `amount` overrides the recipe's particle count when >= 0.
## Returns the number of particles actually spawned.
func emit(recipe_id: String, at: Vector3, tint := Color(0, 0, 0, 0), amount := -1, strength := 1.0, direction := Vector3.ZERO) -> int:
	var recipe: Dictionary = Content.record("effects", recipe_id)
	if recipe.is_empty():
		return 0
	var channel: int = CHANNELS[recipe.channel]
	# High fire rates and multi-pellet volleys share one emission per interval.
	if recipe.has("min_interval"):
		if clock - float(last_emit.get(recipe_id, -INF)) < float(recipe.min_interval):
			return 0
		last_emit[recipe_id] = clock
	if not visible_point(at):
		return 0
	var color = tint if tint.a > 0 and recipe.color == "inherit" else (Color(recipe.color) if recipe.color != "inherit" else Color("ffd9a0"))
	var spawned = 0
	for i in (int(recipe.count) if amount < 0 else amount):
		if not has_room_for(channel):
			dropped[channel] += 1
			continue
		spawn(recipe, channel, at, color, strength, direction)
		spawned += 1
	if recipe.has("mark"):
		mark(at, color, recipe.mark)
	if recipe.has("ring"):
		ring(at, color, float(recipe.ring))
	return spawned

func spawn(recipe: Dictionary, channel: int, at: Vector3, color: Color, strength: float, direction: Vector3) -> void:
	var speed = rng.randf_range(recipe.speed[0], recipe.speed[1]) * strength
	var heading: Vector3
	match recipe.spread:
		"up": heading = Vector3(rng.randf_range(-.3, .3), 1, rng.randf_range(-.3, .3)).normalized()
		"ring": heading = Vector3.RIGHT.rotated(Vector3.UP, rng.randf() * TAU)
		"forward": heading = (direction.normalized() + Vector3(rng.randf_range(-.35, .35), rng.randf_range(-.1, .3), rng.randf_range(-.35, .35))).normalized() if direction != Vector3.ZERO else Vector3.UP
		_: heading = Vector3(rng.randf_range(-1, 1), rng.randf_range(-.2, 1), rng.randf_range(-1, 1)).normalized()
	var i = count
	positions[i] = at
	velocities[i] = heading * speed
	colors[i] = color
	ages[i] = 0.0
	lives[i] = rng.randf_range(recipe.lifetime[0], recipe.lifetime[1])
	sizes[i] = rng.randf_range(recipe.size[0], recipe.size[1]) * clampf(strength, .5, 1.6)
	gravities[i] = float(recipe.gravity)
	channels[i] = channel
	channel_counts[channel] += 1
	count += 1

func remove_particle(i: int) -> void:
	channel_counts[channels[i]] -= 1
	count -= 1
	if i != count:
		positions[i] = positions[count]
		velocities[i] = velocities[count]
		colors[i] = colors[count]
		ages[i] = ages[count]
		lives[i] = lives[count]
		sizes[i] = sizes[count]
		gravities[i] = gravities[count]
		channels[i] = channels[count]

## A few room anchors emit atmosphere: candle wisps, rare fireflies, shelf
## dust and brazier sparks. Not every object emits all the time.
func add_emitter(recipe_id: String, at: Vector3, radius := .1) -> void:
	emitters.append({"recipe": Content.record("effects", recipe_id), "id": recipe_id, "at": at, "radius": radius, "progress": rng.randf()})

func ring(at: Vector3, color: Color, radius: float) -> void:
	var entry: Dictionary
	if rings.size() < MAX_RINGS:
		var node = Geo.ring(self, Vector3.ZERO, .5, color, .04)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.layers = 2
		entry = {"node": node}
		rings.append(entry)
	else:
		entry = rings[0]
		for candidate in rings:
			if candidate.age >= candidate.life:
				entry = candidate
				break
			if candidate.age > entry.age: entry = candidate
	entry.merge({"age": 0.0, "life": .26, "radius": radius, "y": at.y + .06}, true)
	entry.node.material_override = Geo.material(color, .5)
	entry.node.position = at + Vector3(0, .06, 0)
	entry.node.scale = Vector3.ONE
	entry.node.visible = true

func beam(a: Vector3, b: Vector3, color: Color) -> void:
	var length = a.distance_to(b)
	if length < .01:
		return
	var entry: Dictionary
	if beams.size() < MAX_BEAMS:
		var node = Geo.box(self, Vector3.ZERO, Vector3(.045, .045, 1), color, 2.0)
		node.layers = 2
		entry = {"node": node}
		beams.append(entry)
	else:
		entry = beams[0]
		for candidate in beams:
			if candidate.age > entry.age: entry = candidate
	entry.merge({"age": 0.0, "life": .17, "length": length}, true)
	entry.node.material_override = Geo.material(color, 2.0)
	entry.node.position = (a + b) / 2.0
	entry.node.look_at(b, Vector3.UP if absf((b - a).normalized().y) < .99 else Vector3.RIGHT)
	entry.node.scale = Vector3(1, 1, length)
	entry.node.visible = true

## Floor-aligned temporary marks, budgeted; the oldest is recycled.
func mark(at: Vector3, color: Color, spec: Dictionary) -> void:
	if budgets.marks <= 0:
		return
	var entry: Dictionary
	if marks.size() < budgets.marks:
		var node = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = Vector2.ONE
		node.mesh = plane
		var shader_material = ShaderMaterial.new()
		shader_material.shader = preload("res://shaders/floor_mark.gdshader")
		node.material_override = shader_material
		node.layers = 2
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		entry = {"node": node, "material": shader_material}
		marks.append(entry)
	else:
		entry = marks[0]
		for candidate in marks:
			if candidate.age > entry.age: entry = candidate
	var size = float(spec.size) * rng.randf_range(.75, 1.2)
	entry.merge({"age": 0.0, "life": float(spec.lifetime), "alpha": float(spec.alpha), "color": color}, true)
	var floor_height = 0.0
	var owner_game = get_parent().get("game") if is_instance_valid(get_parent()) else null
	if owner_game != null and owner_game.get("first_person") == true and is_instance_valid(owner_game.get("room")):
		floor_height = owner_game.room.floor_height(at)
	entry.node.position = Vector3(at.x, floor_height + .012 + .001 * marks.find(entry), at.z)
	entry.node.scale = Vector3(size, 1, size)
	entry.node.rotation.y = rng.randf() * TAU
	entry.material.set_shader_parameter("seed", rng.randf())
	entry.material.set_shader_parameter("tint", Color(color.darkened(.25), entry.alpha))
	entry.node.visible = true

func live_marks() -> int:
	return marks.filter(func(entry): return entry.node.visible).size()

func _process(delta: float) -> void:
	clock += delta
	for emitter in emitters:
		emitter.progress += delta * float(emitter.recipe.rate)
		while emitter.progress >= 1.0:
			emitter.progress -= 1.0
			var jitter = Vector3(rng.randf_range(-1, 1), rng.randf_range(0, .5), rng.randf_range(-1, 1)) * emitter.radius
			emit(emitter.id, emitter.at + jitter)
	var i = 0
	while i < count:
		ages[i] += delta
		if ages[i] >= lives[i]:
			remove_particle(i)
			continue
		velocities[i] = Vector3(velocities[i].x, velocities[i].y + gravities[i] * delta, velocities[i].z) * DRAG
		positions[i] += velocities[i] * delta
		i += 1
	var mm: MultiMesh = particles.multimesh
	for index in count:
		var fade = sqrt(1.0 - ages[index] / lives[index])
		mm.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ONE * sizes[index] * fade), positions[index]))
		mm.set_instance_color(index, colors[index])
	mm.visible_instance_count = count
	for entry in rings:
		if not entry.node.visible: continue
		entry.age += delta
		var t = clampf(entry.age / entry.life, 0, 1)
		var eased = 1.0 - (1.0 - t) * (1.0 - t)
		entry.node.scale = Vector3(1 + (entry.radius * 2 - 1) * eased, 1, 1 + (entry.radius * 2 - 1) * eased)
		entry.node.position.y = entry.y - .14 * t
		entry.node.visible = entry.age < entry.life
	for entry in beams:
		if not entry.node.visible: continue
		entry.age += delta
		var t = clampf(entry.age / entry.life, 0, 1)
		entry.node.scale = Vector3(1 - .95 * t, 1 - .95 * t, entry.length)
		entry.node.visible = entry.age < entry.life
	for entry in marks:
		if not entry.node.visible: continue
		entry.age += delta
		var remaining = clampf(1.0 - entry.age / entry.life, 0, 1)
		entry.material.set_shader_parameter("tint", Color(entry.color.darkened(.25), entry.alpha * minf(1.0, remaining * 3.0)))
		entry.node.visible = entry.age < entry.life
