class_name FirstPersonTerrain
extends RefCounted
## A validated raised side gallery and a broad ramp. Height is single-valued
## in XZ, allowing the existing navigation graph to remain deterministic.
var ledge := Rect2()
var ramp := Rect2()
const RISE := 1.2

func setup(room) -> void:
	if room.data.has("fps_terrain"):
		var saved = room.data.fps_terrain
		if saved is Dictionary and saved.is_empty(): return
		if valid_blueprint(saved, room.geometry, room.sockets):
			ledge = decode_rect(saved.ledge)
			ramp = decode_rect(saved.ramp)
			build(room)
		else:
			# A truncated/obsolete layout must never build a solid through a
			# doorway or throw while loading the player's existing run.
			room.data["fps_terrain"] = {}
		return
	if room.data.get("fps_flat", false) or room.data.get("type", "") != "combat" or room.geometry.cells.size() < 2: return
	var best: Dictionary = {}
	var fewest := 4
	for cell in room.geometry.cells:
		var center = RoomGeometry.cell_center(cell)
		for side in [-1, 1]:
			var candidate = Rect2(center + Vector2(side * 4.4 - 1.7, -4.6), Vector2(3.4, 2.6))
			var approach = Rect2(candidate.position + Vector2(0, 2.6), Vector2(3.4, 3.6))
			var area = candidate.merge(approach).grow(.5)
			var clear := true
			for point in [area.position, area.end, Vector2(area.position.x, area.end.y), Vector2(area.end.x, area.position.y)]:
				if not room.geometry.contains(point, .6): clear = false
			var displaced: Array = []
			for prop in room.data.get("props", []):
				var point = Vector2(float(prop.position[0]), float(prop.position[1]))
				var size = Vector2(float(prop.size[0]), float(prop.size[1])) if prop.has("size") else Vector2.ONE * 1.6
				if area.intersects(Rect2(point - size / 2, size)):
					displaced.append(prop.id)
			for point in room.data.get("lights", []):
				if area.grow(.3).has_point(Vector2(float(point[0]), float(point[1]))): clear = false
			if room.data.has("pedestal") and area.grow(1.0).has_point(Vector2(float(room.data.pedestal[0]), float(room.data.pedestal[1]))): clear = false
			for record in room.data.get("chests", []) + room.data.get("items", []):
				if area.grow(1.0).has_point(Vector2(float(record.position[0]), float(record.position[1]))): clear = false
			for socket in room.sockets.values():
				if area.grow(1.8).has_point(RoomGeometry.socket_point(socket.cell, socket.dir)): clear = false
			if clear and displaced.size() < fewest:
				fewest = displaced.size()
				best = {"ledge": candidate, "ramp": approach, "displaced": displaced}
	if best.is_empty():
		room.data["fps_terrain"] = {}
		return
	ledge = best.ledge
	ramp = best.ramp
	# Reserve this template's walkable gallery before scenery is built. Removing
	# at most three optional props only opens routes; chests, mounts, lights,
	# exits and the pedestal are never displaced. Persist the resolved layout.
	if room.data.has("props"):
		room.data.props.assign(room.data.props.filter(func(prop): return prop.id not in best.displaced))
	room.data["fps_terrain"] = {"version": 1, "ledge": [ledge.position.x, ledge.position.y, ledge.size.x, ledge.size.y], "ramp": [ramp.position.x, ramp.position.y, ramp.size.x, ramp.size.y]}
	build(room)

static func decode_rect(value: Array) -> Rect2:
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))

static func valid_rect(value: Variant) -> bool:
	return value is Array and value.size() == 4 and value.all(func(number): return (number is int or number is float) and is_finite(float(number))) and float(value[2]) >= 1.2 and float(value[3]) >= 1.2 and float(value[2]) <= 8.0 and float(value[3]) <= 8.0

static func valid_blueprint(value: Variant, geometry: RoomGeometry, sockets: Dictionary = {}) -> bool:
	if not value is Dictionary or value.get("version", -1) != 1: return false
	if not valid_rect(value.get("ledge")) or not valid_rect(value.get("ramp")): return false
	var deck = decode_rect(value.ledge)
	var slope = decode_rect(value.ramp)
	if absf(deck.position.x - slope.position.x) > .015 or absf(deck.size.x - slope.size.x) > .015 or absf(deck.end.y - slope.position.y) > .015: return false
	if RISE / slope.size.y > .8: return false
	var occupied = deck.merge(slope).grow(2.3)
	for socket in sockets.values():
		if occupied.has_point(RoomGeometry.socket_point(socket.cell, socket.dir)): return false
	# Test the occupied footprint, including bends and missing cells. Layout
	# validation is independent of graphics quality and never consumes RNG.
	for area in [deck, slope]:
		var samples = Vector2i(ceili(area.size.x / .5), ceili(area.size.y / .5))
		for x in samples.x + 1:
			for y in samples.y + 1:
				var point: Vector2 = area.position + area.size * Vector2(float(x) / samples.x, float(y) / samples.y)
				if not geometry.contains(point, .3): return false
	return true

func height(point: Vector2) -> float:
	if ledge.has_area() and ledge.has_point(point): return RISE
	if ramp.has_area() and ramp.has_point(point): return RISE * (1.0 - (point.y - ramp.position.y) / ramp.size.y)
	return 0.0

func traversable(point: Vector2, clearance: float) -> bool:
	var here = height(point)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		if absf(height(point + direction * clearance) - here) > .65: return false
	return true

func build(room) -> void:
	var at = ledge.get_center()
	var deck = Geo.box(room, Vector3(at.x, RISE / 2, at.y), Vector3(ledge.size.x, RISE, ledge.size.y), Color("514c42"))
	deck.material_override = DungeonStyle.wall_material(Color(room.look.get("wall", "514c42")))
	Geo.collider(room, deck.position, Vector3(ledge.size.x, RISE, ledge.size.y))
	var paving = MeshInstance3D.new()
	var paving_mesh = PlaneMesh.new()
	paving_mesh.size = ledge.size
	paving.mesh = paving_mesh
	paving.position = Vector3(at.x, RISE + .003, at.y)
	paving.material_override = DungeonStyle.floor_material(room.look)
	room.add_child(paving)
	var tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points = [Vector3(ramp.position.x, RISE, ramp.position.y), Vector3(ramp.end.x, RISE, ramp.position.y), Vector3(ramp.end.x, 0, ramp.end.y), Vector3(ramp.position.x, 0, ramp.end.y)]
	for i in [0, 1, 2, 0, 2, 3]:
		tool.set_uv(Vector2(points[i].x, points[i].z))
		tool.add_vertex(points[i])
	tool.generate_normals()
	var mesh: ArrayMesh = tool.commit()
	var view = MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = DungeonStyle.floor_material(room.look)
	room.add_child(view)
	var collider = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	# A solid convex wedge has a walkable top and cannot admit actors beneath
	# a one-sided sheet. Clockwise render triangles keep the visible face up.
	var wedge = ConvexPolygonShape3D.new()
	wedge.points = PackedVector3Array(points + [Vector3(ramp.position.x, -.08, ramp.position.y), Vector3(ramp.end.x, -.08, ramp.position.y), Vector3(ramp.end.x, -.08, ramp.end.y), Vector3(ramp.position.x, -.08, ramp.end.y)])
	shape.shape = wedge
	collider.add_child(shape)
	room.add_child(collider)
	# The convex collision has thickness; give its exposed sides the same
	# stone facing so the ramp never reads as a floating paper sheet.
	var underside: Array = points.map(func(point): return Vector3(point.x, -.08, point.z))
	var facing = SurfaceTool.new()
	facing.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [[points[0], points[3], underside[3], underside[0]], [points[1], underside[1], underside[2], points[2]],
		[points[0], underside[0], underside[1], points[1]], [points[3], points[2], underside[2], underside[3]]]:
		for index in [0, 1, 2, 0, 2, 3]:
			facing.add_vertex(face[index])
	facing.generate_normals()
	var sides = MeshInstance3D.new()
	sides.mesh = facing.commit()
	sides.material_override = DungeonStyle.wall_material(Color(room.look.get("wall", "514c42")))
	room.add_child(sides)
	# Low guard rails frame the gallery; the wide ramp stays open.
	for side in [ledge.position.x, ledge.end.x]:
		Geo.box(room, Vector3(side, RISE + .7, at.y), Vector3(.1, .1, ledge.size.y), Color("9b845e"))
