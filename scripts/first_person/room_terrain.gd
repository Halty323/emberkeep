class_name FirstPersonTerrain
extends RefCounted
## A validated raised side gallery and a broad ramp. Height is single-valued
## in XZ, allowing the existing navigation graph to remain deterministic.
var ledge := Rect2()
var ramp := Rect2()
const RISE := 1.2

func setup(room) -> void:
	if room.data.has("fps_terrain"):
		var saved: Dictionary = room.data.fps_terrain
		if saved.has("ledge"):
			var a: Array = saved.ledge
			var b: Array = saved.ramp
			ledge = Rect2(a[0], a[1], a[2], a[3])
			ramp = Rect2(b[0], b[1], b[2], b[3])
			build(room)
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
	deck.material_override = Look.wall_material(Color("514c42"), true)
	Geo.collider(room, deck.position, Vector3(ledge.size.x, RISE, ledge.size.y))
	var tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points = [Vector3(ramp.position.x, RISE, ramp.position.y), Vector3(ramp.end.x, RISE, ramp.position.y), Vector3(ramp.end.x, 0, ramp.end.y), Vector3(ramp.position.x, 0, ramp.end.y)]
	for i in [0, 2, 1, 0, 3, 2]:
		tool.set_uv(Vector2(points[i].x, points[i].z))
		tool.add_vertex(points[i])
	tool.generate_normals()
	var mesh: ArrayMesh = tool.commit()
	var view = MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = Geo.material(Color("5b5549"))
	room.add_child(view)
	var collider = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	collider.add_child(shape)
	room.add_child(collider)
	# Low guard rails frame the gallery; the wide ramp stays open.
	for side in [ledge.position.x, ledge.end.x]:
		Geo.box(room, Vector3(side, RISE + .7, at.y), Vector3(.1, .1, ledge.size.y), Color("9b845e"))
