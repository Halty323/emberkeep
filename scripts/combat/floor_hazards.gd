class_name FloorHazards
extends Node3D
## What a floor theme or twist builds into its rooms: lasting pools of water,
## wax, frost or moss laid into the residue, fire vents that breathe on a
## rhythm, and pendulum blades that swing across the floor. Everything is
## laid from the room's seed on its own stream, so a room always looks the
## same and neither encounters nor loot shift. Vents and pendulums run only
## while the room's fight is on; a cleared room is safe to cross.
const PATCHES := {"water": ["water", 2, 3, 1.3, 2.2], "flooded": ["water", 1, 2, 1.5, 2.6], "wax": ["wax", 2, 3, 1.2, 2.0],
	"frost": ["ice", 2, 3, 1.2, 2.0], "overgrown": ["moss", 2, 3, 1.0, 1.8]}
const VENT_REACH := 1.15
const VENT_WARNING := 1.0
const VENT_REST := [3.6, 5.6]
const VENT_DAMAGE := 8.0
const PENDULUM_SWING := 2.9
const PENDULUM_PERIOD := 3.4
const PENDULUM_BLADE := .75
const PENDULUM_DAMAGE := 18.0
# How far pools keep from the pedestal, doors and the stair.
const CLEAR_OF := 2.4
var game: Node3D
var data: Dictionary
var geometry: RoomGeometry
var vents: Array = []
var pendulums: Array = []
var time = 0.0

func setup(owner_game: Node3D, room_data: Dictionary, room_geometry: RoomGeometry, field: ResidueField, pedestal: Vector3) -> void:
	game = owner_game
	data = room_data
	geometry = room_geometry
	var gen = RandomNumberGenerator.new()
	gen.seed = Content.stable_hash("hazards:%d:%d:%s" % [Run.seed_value, Run.floor_number, str(room_data.get("id", ""))])
	var fight = room_data.get("type", "") in ["combat", "boss"]
	var hazard: String = Run.theme().get("hazard", "")
	var keep_clear: Array = [Vector2(pedestal.x, pedestal.z)]
	for key in ["stairs", "stairwell"]:
		if room_data.has(key): keep_clear.append(Vector2(float(room_data[key][0]), float(room_data[key][1])))
	for layer in [hazard, Run.twist_id()]:
		if PATCHES.has(layer): lay_patches(field, PATCHES[layer], gen, keep_clear)
	if not fight or room_data.get("cleared", false): return
	if hazard == "vents":
		for cell in geometry.cells:
			for i in 2: add_vent(spot(gen, cell, keep_clear), gen)
	elif hazard == "pendulums" and room_data.type == "combat":
		for cell in geometry.cells: add_pendulum(spot(gen, cell, keep_clear, 3.2), gen)

func lay_patches(field: ResidueField, spec: Array, gen: RandomNumberGenerator, keep_clear: Array) -> void:
	for cell in geometry.cells:
		for i in gen.randi_range(spec[1], spec[2]):
			var at = spot(gen, cell, keep_clear)
			var radius = gen.randf_range(spec[3], spec[4])
			# Two or three overlapping rounds make a pool look poured, not stamped.
			for lobe in gen.randi_range(2, 3):
				var offset = Vector2.RIGHT.rotated(gen.randf() * TAU) * radius * gen.randf_range(.2, .6)
				field.add(spec[0], Vector3(at.x + offset.x, 0, at.y + offset.y), radius * gen.randf_range(.55, .8), true)

## A floor point in a cell, clear of the pedestal and the stairs.
func spot(gen: RandomNumberGenerator, cell: Vector2i, keep_clear: Array, margin := 1.4) -> Vector2:
	var center = RoomGeometry.cell_center(cell)
	var best = center
	for attempt in 12:
		var at = center + Vector2(gen.randf_range(-6.5, 6.5), gen.randf_range(-4.5, 4.5))
		if not geometry.contains(at, margin): continue
		if game.first_person and game.room.floor_height(Vector3(at.x, 0, at.y)) > .05: continue
		if keep_clear.any(func(point): return point.distance_to(at) < CLEAR_OF): continue
		return at
	return best

func add_vent(at: Vector2, gen: RandomNumberGenerator) -> void:
	var node = Node3D.new()
	add_child(node)
	node.position = Vector3(at.x, 0, at.y)
	Geo.box(node, Vector3(0, .02, 0), Vector3(1.1, .05, 1.1), Color("2a2522"))
	var slits: Array = []
	for i in 4:
		slits.append(Geo.box(node, Vector3(-.36 + i * .24, .05, 0), Vector3(.08, .02, .9), Color("ff7a3a"), .3))
	var warning = Geo.ring(node, Vector3(0, .06, 0), VENT_REACH, Color("ff8a4a"), .05)
	warning.visible = false
	vents.append({"at": node.position, "node": node, "slits": slits, "warning": warning, "state": "rest",
		"timer": gen.randf_range(VENT_REST[0], VENT_REST[1]) * .6, "rest": gen.randf_range(VENT_REST[0], VENT_REST[1])})

func add_pendulum(at: Vector2, gen: RandomNumberGenerator) -> void:
	var node = Node3D.new()
	add_child(node)
	node.position = Vector3(at.x, 0, at.y)
	var axis = Vector3.RIGHT.rotated(Vector3.UP, [0.0, PI / 2, PI / 4, -PI / 4][gen.randi_range(0, 3)])
	# The groove it has worn into the floor shows the swing before it comes.
	var groove = Geo.box(node, Vector3(0, .015, 0), Vector3(PENDULUM_SWING * 2.2, .02, .16), Color("2a241c"))
	groove.rotation.y = atan2(-axis.z, axis.x)
	var rod = Geo.box(node, Vector3.ZERO, Vector3(.06, 3.4, .06), Color("8a7550"))
	var blade = Geo.box(node, Vector3.ZERO, Vector3(.22, .5, PENDULUM_BLADE * 2.0), Color("c9b48a"), .25)
	blade.rotation.y = atan2(-axis.z, axis.x)
	pendulums.append({"node": node, "axis": axis, "rod": rod, "blade": blade, "phase": gen.randf() * TAU, "struck": {}})

## Pendulums and vents stop once the room's fight is over.
func active() -> bool:
	return is_instance_valid(game.room) and not game.room.open

func update_sim(delta: float) -> void:
	time += delta
	var running = active()
	for vent in vents: update_vent(vent, delta, running)
	for pendulum in pendulums: update_pendulum(pendulum, running)

func update_vent(vent: Dictionary, delta: float, running: bool) -> void:
	if not running:
		vent.warning.visible = false
		return
	vent.timer -= delta
	var glow = 0.0
	match vent.state:
		"rest":
			if vent.timer <= 0:
				vent.state = "warn"
				vent.timer = VENT_WARNING
				vent.warning.visible = true
		"warn":
			glow = 1.0 - vent.timer / VENT_WARNING
			if vent.timer <= 0: erupt(vent)
	# Stepped, so the shared material cache stays small.
	var heat = snappedf(.3 + glow * 2.5, .5)
	for slit in vent.slits:
		slit.material_override = Geo.material(Color("ff7a3a"), heat)

func erupt(vent: Dictionary) -> void:
	vent.state = "rest"
	vent.timer = vent.rest
	vent.warning.visible = false
	var at: Vector3 = vent.at
	if game.residue: game.residue.scorch(at, VENT_REACH)
	Effects.burst(game.scene_root, at + Vector3.UP * .4, Color("ff9a4a"), 14, 1.6)
	Effects.ring_burst(game.scene_root, at, Color("ff8a4a"), VENT_REACH)
	game.make_noise(at, 1.5)
	if game.player.global_position.distance_to(at) < VENT_REACH: game.player.hurt(1.0, at)
	for enemy in game.enemies.duplicate():
		if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable: continue
		if enemy.global_position.distance_to(at) < VENT_REACH + enemy.radius:
			enemy.apply_status({"burn": 1.5})
			enemy.take_hit(VENT_DAMAGE, Vector3.ZERO, false, false, "blast")

## The blade is low, and dangerous, through the middle of its swing; at
## either end it rises over everyone's head.
func update_pendulum(pendulum: Dictionary, running: bool) -> void:
	var s = sin(time * TAU / PENDULUM_PERIOD + pendulum.phase) if running else 0.0
	var height = .45 + 1.25 * s * s
	var bob: Vector3 = pendulum.axis * PENDULUM_SWING * s
	pendulum.blade.position = bob + Vector3.UP * height
	pendulum.rod.position = (bob + Vector3.UP * height + Vector3.UP * 4.2) / 2.0
	pendulum.rod.rotation.z = 0.0
	if not running or height > 1.1: return
	var center: Vector3 = pendulum.node.position + bob
	var across: Vector3 = pendulum.axis.cross(Vector3.UP)
	var a = center - across * PENDULUM_BLADE
	var b = center + across * PENDULUM_BLADE
	var swing_dir = pendulum.axis * signf(cos(time * TAU / PENDULUM_PERIOD + pendulum.phase))
	var player_at: Vector3 = game.player.global_position
	if Geometry3D.get_closest_point_to_segment(player_at, a, b).distance_to(player_at) < .45:
		game.player.hurt(1.0, center)
	for enemy in game.enemies.duplicate():
		if not is_instance_valid(enemy) or not enemy.alive or not enemy.targetable or enemy.boss: continue
		var at: Vector3 = enemy.global_position
		if Geometry3D.get_closest_point_to_segment(at, a, b).distance_to(at) > .4 + enemy.radius: continue
		if pendulum.struck.get(enemy.entity_id, -9.0) > time - 1.0: continue
		pendulum.struck[enemy.entity_id] = time
		enemy.take_hit(PENDULUM_DAMAGE, swing_dir * 6.0, false, false, "blast")
