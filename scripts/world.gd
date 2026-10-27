class_name DungeonRoom
extends Node3D
## View of one logical room. Floors and walls are built from the union of its
## footprint cells; walls exist only on exposed edges and every edge keeps its
## doorway socket, filled either by a portal's gate or by a wall plug.
const MAX_LANTERN_SHADOWS = 1
const MAX_ACTIVE_FILLS = 5
const FILL_HYSTERESIS = 3.0
const WALL_BACK_HEIGHT = 2.8
const WALL_FRONT_HEIGHT = 1.8
const WALL_CUTAWAY_HEIGHT = .45
const CUTAWAY_REACH = 3.0
const PALETTE = [Color("49433d"), Color("45413b"), Color("4d463e"), Color("413e39"), Color("50473e")]
var game: Node3D
var data: Dictionary = {}
var geometry: RoomGeometry
var decor_rng = RandomNumberGenerator.new()
# Selected warm fill lights; large rooms move a small pool between lanterns.
var lamps: Array[OmniLight3D] = []
var lantern_points: Array[Vector3] = []
var lamp_assignment: Array[int] = []
var shadow_lamps: Array[SpotLight3D] = []
var _quality_enabled = null
var gates: Array[Node3D] = []
var sockets: Dictionary = {}
var open = true
var time = 0.0
var ember_mesh: MultiMeshInstance3D
var ember_origins: Array[Vector3] = []
var obstacles: Array[Dictionary] = []
var front_walls: Array[Dictionary] = []
var navigators: Dictionary = {}
var pedestal := Vector3.ZERO

func build(owner_game: Node3D, room: Dictionary, preview := false) -> void:
	game = owner_game
	data = room
	decor_rng.seed = int(room.get("seed", 53))
	geometry = RoomGeometry.new(Run.local_cells(room) if room.has("cells") else [Vector2i.ZERO])
	geometry.apply_shader_mask()
	if room.has("pedestal"):
		pedestal = Vector3(float(room.pedestal[0]), 0, float(room.pedestal[1]))
	collect_sockets(room, preview)
	build_floor()
	build_walls()
	var points: Array = room.get("lights", default_lights())
	for point in points:
		make_lantern(Vector3(float(point[0]), 0, float(point[1])))
	make_fill_lights()
	var room_type: String = room.get("type", "combat")
	if room_type in ["start", "treasure", "rest", "shop"] or preview:
		Geo.box(self, pedestal + Vector3(0, -.003, 0), Vector3(6.2, .03, 4.6), Color("514450") if room_type == "shop" else Color("5d4c3e"))
		Geo.ring(self, pedestal + Vector3(0, .035, 0), 1.65, Color("9e875c"), .025)
		Geo.ring(self, pedestal + Vector3(0, .035, 0), 1.45, Color("7c7359"), .018)
	if room_type in ["combat", "boss"] and not preview:
		var pattern = [Vector2(-3.5, -2.7), Vector2(3.5, 2.7)]
		if int(room.seed) % 2 == 0:
			pattern = [Vector2(-3.8, 2.7), Vector2(3.8, -2.7)]
		for cell in geometry.cells:
			for offset in pattern:
				var point = RoomGeometry.cell_center(cell) + offset
				if Vector2(pedestal.x, pedestal.z).distance_to(point) < 3.0: continue
				make_pillar(Vector3(point.x, 0, point.y))
	make_candles()
	make_embers()
	set_open(true)
	apply_lighting_quality()

static func default_lights() -> Array:
	return Content.record("rooms", "hearth_1x1").lights.map(func(anchor):
		var at = RoomGeometry.resolve_anchor([Vector2i.ZERO], 0, anchor)
		return [at.x, at.y])

func collect_sockets(room: Dictionary, preview: bool) -> void:
	for edge in geometry.exposed_edges():
		sockets[socket_key(edge.cell, edge.dir)] = {"cell": edge.cell, "dir": edge.dir, "portal": "", "state": "wall"}
	if preview:
		for direction in RoomGeometry.DIRECTIONS:
			sockets[socket_key(Vector2i.ZERO, direction)].state = "open"
		return
	for portal_id in room.get("portals", []):
		var side = Run.portal_side(portal_id, room.id)
		var key = socket_key(side.cell, side.dir)
		if sockets.has(key):
			sockets[key].portal = portal_id
			sockets[key].state = Run.portals[portal_id].state

static func socket_key(cell: Vector2i, direction: Vector2i) -> String:
	return "%d,%d,%d,%d" % [cell.x, cell.y, direction.x, direction.y]

func build_floor() -> void:
	# Batches are chunked per cell so a large room's floor is not one giant
	# mesh receiving every distant lantern's lighting pass.
	for cell in geometry.cells:
		var center = RoomGeometry.cell_center(cell)
		for color_index in PALETTE.size():
			var points: Array[Vector3] = []
			for x in range(int(center.x) - 9, int(center.x) + 9):
				for z in range(int(center.y) - 7, int(center.y) + 7):
					if posmod(x * 37 + z * 19 + x * z, 5) == color_index:
						points.append(Vector3(x + .5, -.16, z + .5))
			var mm = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = Geo.shared_box(Vector3(.975, .25, .975))
			mm.instance_count = points.size()
			for i in points.size():
				mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i]))
			var mesh = MultiMeshInstance3D.new()
			mesh.multimesh = mm
			mesh.material_override = Geo.material(PALETTE[color_index])
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mesh)
		Geo.box(self, Vector3(center.x, -.55, center.y), Vector3(18.6, .7, 14.6), Color("242d31"))
		Geo.box(self, Vector3(center.x, -.96, center.y), Vector3(17.9, .25, 13.9), Color("19232b"))

func build_walls() -> void:
	for segment in geometry.wall_segments():
		var box = RoomGeometry.segment_box(segment)
		var front = RoomGeometry.is_front(segment.dir)
		var height = WALL_FRONT_HEIGHT if front else WALL_BACK_HEIGHT
		make_wall(Vector3(box.center.x, height / 2, box.center.y), Vector3(box.size.x, height, box.size.y),
			segment.dir if front else Vector2i.ZERO, segment.line, segment.from, segment.to)
	for key in sockets:
		var socket: Dictionary = sockets[key]
		if socket.state in ["open", "locked", "revealed"]:
			make_gate(socket)
		else:
			make_plug(socket)

func make_plug(socket: Dictionary) -> void:
	var direction: Vector2i = socket.dir
	var front = RoomGeometry.is_front(direction)
	var height = WALL_FRONT_HEIGHT if front else WALL_BACK_HEIGHT
	var point = RoomGeometry.socket_point(socket.cell, direction)
	var at = point + Vector2(direction) * .15
	var line = point.dot(Vector2(direction).abs())
	var along = point.dot(Vector2(absi(direction.y), absi(direction.x)))
	socket["walls"] = make_wall(Vector3(at.x, height / 2, at.y), Vector3(.45, height, 2.5) if direction.x != 0 else Vector3(2.5, height, .45),
		direction if front else Vector2i.ZERO, line, along - 1.25, along + 1.25)

func make_gate(socket: Dictionary) -> void:
	var direction: Vector2i = socket.dir
	var at = RoomGeometry.socket_point(socket.cell, direction) + Vector2(direction) * .15
	var gate = Node3D.new()
	add_child(gate)
	gate.position = Vector3(at.x, 0, at.y)
	var rotated = direction.x != 0
	var post_height = WALL_BACK_HEIGHT - .25 if direction.x + direction.y < 0 else 1.5
	Geo.box(gate, Vector3(0, -.015, 0), Vector3(.8, .08, 2.25) if rotated else Vector3(2.25, .08, .8), Color("b69c6a"))
	for s in [-1, 1]:
		Geo.box(gate, Vector3(0, post_height / 2, s * 1.1) if rotated else Vector3(s * 1.1, post_height / 2, 0), Vector3(.25, post_height, .25), Color("797263"))
	if post_height > 1.5:
		Geo.box(gate, Vector3(0, post_height, 0), Vector3(.3, .18, 2.5) if rotated else Vector3(2.5, .18, .3), Color("797263"))
	var barrier = Geo.box(gate, Vector3(0, .75, 0), Vector3(.16, 1.45, 2.0) if rotated else Vector3(2.0, 1.45, .16), Color("b85e4c"), .7)
	barrier.name = "Barrier"
	Geo.halo(gate, Vector3(0, .035, 0), 3.5, Color(.92, .62, .25, .28))
	gate.set_meta("portal", socket.portal)
	socket["gate"] = gate
	gates.append(gate)

func make_wall(at: Vector3, dimensions: Vector3, front_side := Vector2i.ZERO, line := 0.0, from := 0.0, to := 0.0) -> Dictionary:
	var body = Geo.box(self, at, dimensions, Color("394148"))
	var cap = Geo.box(self, at + Vector3(0, dimensions.y / 2 + .035, 0), Vector3(dimensions.x + .06, .09, dimensions.z + .06), Color("656358"))
	var collider = Geo.collider(self, at, dimensions + Vector3(0, 2, 0))
	var entry = {"body": body, "cap": cap, "collider": collider}
	if front_side != Vector2i.ZERO:
		# Keep a static full-height occluder while the visible wall cuts away.
		# This avoids transparent wall passes and moving shadow-map casters.
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var caster = Geo.box(self, at, dimensions, Color("394148"))
		caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		entry.merge({"shadow_caster": caster, "side": front_side, "height": dimensions.y,
			"line": line, "from": from, "to": to})
		front_walls.append(entry)
	return entry

## Front segments lower when an actor stands within reach of their inner face
## along the boundary normal; collision and shadow occluders never move.
func wall_obstructs(wall: Dictionary, point: Vector3) -> bool:
	var side: Vector2i = wall.side
	var across = point.x if side.x != 0 else point.z
	var along = point.z if side.x != 0 else point.x
	var inward = wall.line - across
	return inward > -1.0 and inward < CUTAWAY_REACH and along > wall.from - CUTAWAY_REACH and along < wall.to + CUTAWAY_REACH

func update_wall_visibility(focus: Vector3, delta: float, others: Array = []) -> void:
	for wall in front_walls:
		var near = wall_obstructs(wall, focus)
		if not near:
			for actor in others:
				if wall_obstructs(wall, actor):
					near = true
					break
		var target = WALL_CUTAWAY_HEIGHT if near else WALL_FRONT_HEIGHT
		var height = target if delta <= 0 else move_toward(wall.height, target, delta * 7.0)
		if is_equal_approx(height, wall.height): continue
		wall.height = height
		wall.body.scale.y = height / WALL_FRONT_HEIGHT
		wall.body.position.y = height / 2
		wall.cap.position.y = height + .035

func make_pillar(p: Vector3) -> void:
	Geo.box(self, p + Vector3(0, .6, 0), Vector3(1.2, 1.2, 1.2), Color("4f5855"))
	Geo.box(self, p + Vector3(0, 1.22, 0), Vector3(1.35, .14, 1.35), Color("747b68"))
	Geo.collider(self, p + Vector3(0, 1.0, 0), Vector3(1.3, 2.0, 1.3))
	obstacles.append({"position": p, "radius": 1.05, "rect": Rect2(p.x - .65, p.z - .65, 1.3, 1.3)})
	make_candle(p + Vector3(0, 1.32, 0), .6)

func make_lantern(p: Vector3) -> void:
	Geo.box(self, p + Vector3(0, .28, 0), Vector3(.85, .55, .85), Color("424d4c"))
	Geo.box(self, p + Vector3(0, .61, 0), Vector3(1.0, .12, 1.0), Color("716f5d"))
	Geo.cylinder(self, p + Vector3(0, 1.03, 0), .14, .8, Color("ac9061"))
	Geo.box(self, p + Vector3(0, 1.6, 0), Vector3(.5, .55, .5), Color("f7bb6d"), 1.05)
	Geo.box(self, p + Vector3(0, 1.94, 0), Vector3(.68, .12, .68), Color("826d51"))
	for x in [-.22, .22]:
		for z in [-.22, .22]:
			var bar = Geo.box(self, p + Vector3(x, 1.6, z), Vector3(.035, .65, .035), Color("6e6654"))
			bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lantern_points.append(p)
	Geo.halo(self, p + Vector3(0, .03, 0), 7.5, Color(1, .57, .17, .2))
	var glow = Geo.halo(self, p + Vector3(0, 1.65, 0), 2.0, Color(1, .6, .2, .4))
	glow.rotation_degrees.x = 58

func make_fill_lights() -> void:
	# Unshadowed fills preserve warm lantern pools in both quality modes. A
	# small pool serves big rooms; it moves only when the selection changes.
	for i in mini(MAX_ACTIVE_FILLS, lantern_points.size()):
		lamps.append(Geo.light(self, lantern_points[i] + Vector3(0, 2.2, 0), Color("ffbc71"), .6, 7.0))
		lamp_assignment.append(i)
	# Keep one warm key shadow; the other lanterns are inexpensive fills. Four
	# overlapping shadow lights still cost too much on mobile GLES3 renderers.
	if not lantern_points.is_empty() and shadow_lamps.size() < MAX_LANTERN_SHADOWS:
		make_shadow_light(lantern_points[0])

func lantern_distance(index: int, flat: Vector2) -> float:
	return Vector2(lantern_points[index].x, lantern_points[index].z).distance_to(flat)

## Chooses the lanterns nearest the view. A lantern replaces a selected one
## only when it is clearly closer, so lights do not flap at the boundary.
func update_light_selection(focus: Vector3) -> bool:
	if lantern_points.size() <= lamps.size():
		return false
	var flat = Vector2(focus.x, focus.z)
	var changed = false
	for candidate in lantern_points.size():
		if candidate in lamp_assignment: continue
		var worst = 0
		for slot in lamp_assignment.size():
			if lantern_distance(lamp_assignment[slot], flat) > lantern_distance(lamp_assignment[worst], flat): worst = slot
		if lantern_distance(candidate, flat) + FILL_HYSTERESIS < lantern_distance(lamp_assignment[worst], flat):
			lamp_assignment[worst] = candidate
			lamps[worst].position = lantern_points[candidate] + Vector3(0, 2.2, 0)
			changed = true
	if changed and not shadow_lamps.is_empty():
		var nearest = lamp_assignment[0]
		for index in lamp_assignment:
			if lantern_distance(index, flat) < lantern_distance(nearest, flat): nearest = index
		place_shadow_light(shadow_lamps[0], lantern_points[nearest])
	return changed

func make_shadow_light(p: Vector3) -> void:
	# A fixed inward-facing spotlight needs one map instead of six cube faces.
	var shadow_light = SpotLight3D.new()
	shadow_light.light_color = Color("ffbc71")
	shadow_light.light_cull_mask = 1
	shadow_light.light_energy = 1.5
	shadow_light.spot_range = 13.0
	shadow_light.spot_angle = 58.0
	shadow_light.spot_angle_attenuation = 1.5
	shadow_light.shadow_bias = .06
	shadow_light.shadow_normal_bias = .7
	shadow_light.shadow_opacity = 1.0
	shadow_light.visible = false
	add_child(shadow_light)
	place_shadow_light(shadow_light, p)
	shadow_lamps.append(shadow_light)

func place_shadow_light(shadow_light: SpotLight3D, p: Vector3) -> void:
	# Aim inward toward the lantern's own cell, as the 1x1 room always did.
	var center = RoomGeometry.cell_center(geometry.cell_at(Vector2(p.x, p.z)))
	shadow_light.position = p + Vector3(0, 2.2, 0)
	shadow_light.look_at(Vector3(center.x + (p.x - center.x) * .3, 0, center.y + (p.z - center.y) * .3))

func make_candle(p: Vector3, height: float) -> void:
	var wax = Geo.cylinder(self, p + Vector3(0, height / 2, 0), .12, height, Color("c9ad7e"))
	wax.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flame = Geo.sphere(self, p + Vector3(0, height + .1, 0), .11, Color("ffe0a1"), 2.0)
	flame.scale = Vector3(.7, 1.5, .7)
	Geo.halo(self, p + Vector3(0, .025, 0), 2.3, Color(1, .5, .13, .14))

func make_candles() -> void:
	# Candles line the exposed rear and front walls, alternating between them.
	var edges = geometry.exposed_edges().filter(func(edge): return edge.dir.x == 0)
	var rear = edges.filter(func(edge): return edge.dir.y < 0)
	var front = edges.filter(func(edge): return edge.dir.y > 0)
	var ordered: Array = []
	for i in maxi(rear.size(), front.size()):
		if i < rear.size(): ordered.append(rear[i])
		if i < front.size(): ordered.append(front[i])
	for i in 5 * ordered.size():
		var edge: Dictionary = ordered[i % ordered.size()]
		var center = RoomGeometry.cell_center(edge.cell)
		var p = Vector3(decor_rng.randf_range(-6.5, 6.5), 0, edge.dir.y * 6.2)
		if absf(p.x) < 1.7:
			p.x += 3.0
		make_candle(p + Vector3(center.x, 0, center.y), decor_rng.randf_range(.45, .85))

func make_embers() -> void:
	ember_mesh = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh = SphereMesh.new()
	mesh.radius = .025
	mesh.height = .05
	mesh.radial_segments = 4
	mesh.rings = 3
	mm.mesh = mesh
	var count = 40
	mm.instance_count = count
	for i in count:
		var floor_point = geometry.random_point(decor_rng, .2)
		ember_origins.append(Vector3(floor_point.x, decor_rng.randf_range(.1, 4.0), floor_point.y))
	ember_mesh.multimesh = mm
	ember_mesh.material_override = Geo.material(Color("efbc78"), 1.2)
	ember_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ember_mesh)

## Lazily built navigation per actor clearance class.
func navigation(clearance := .5) -> RoomNavigation:
	var key = snappedf(clearance, .05)
	if not navigators.has(key):
		var blockers := {}
		for i in obstacles.size():
			blockers["obstacle%d" % i] = obstacles[i].rect
		navigators[key] = RoomNavigation.new(geometry, clearance, blockers)
	return navigators[key]

func blocked_at(point: Vector2) -> bool:
	for obstacle in obstacles:
		if obstacle.rect.grow(.4).has_point(point): return true
	return false

func set_open(value: bool) -> void:
	open = value
	for gate in gates:
		gate.get_node("Barrier").visible = not value

func apply_lighting_quality() -> void:
	var enabled: bool = Settings.values.shadows
	if _quality_enabled == enabled:
		return
	_quality_enabled = enabled
	for light in shadow_lamps:
		light.shadow_enabled = enabled
		light.visible = enabled

func _process(delta: float) -> void:
	time += delta
	apply_lighting_quality()
	for i in lamps.size():
		lamps[i].light_energy = .6 + sin(time * 3.1 + i * 2.4) * .025 + sin(time * 7.2 + i) * .012
	if ember_mesh:
		for i in ember_origins.size():
			var p: Vector3 = ember_origins[i]
			p.y = fposmod(p.y + time * .16, 4.0)
			p.x += sin(time * .35 + i) * .25
			ember_mesh.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
