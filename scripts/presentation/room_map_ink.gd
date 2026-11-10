class_name RoomMapInk
extends RefCounted
## A single, deterministic pencil trail inside a room's complete silhouette.
## Shared seams disappear before drawing; concave corners remain empty.
static func outline(cells: Array, size: float) -> PackedVector2Array:
	var pending: Array[PackedVector2Array] = []
	var inset := size * .2
	for cell in cells:
		var low := Vector2(inset if cell + Vector2i.LEFT not in cells else 0.0, inset if cell + Vector2i.UP not in cells else 0.0)
		var high := Vector2(inset if cell + Vector2i.RIGHT not in cells else 0.0, inset if cell + Vector2i.DOWN not in cells else 0.0)
		var rect := Rect2((Vector2(cell) - Vector2.ONE * .5) * size + low, Vector2.ONE * size - low - high)
		pending.append(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]))
	if pending.is_empty(): return PackedVector2Array()
	var polygon: PackedVector2Array = pending.pop_front()
	while not pending.is_empty():
		var joined := false
		for i in pending.size():
			var merged := Geometry2D.merge_polygons(polygon, pending[i])
			if merged.size() != 1: continue
			polygon = merged[0]
			pending.remove_at(i)
			joined = true
			break
		if not joined: break # Invalid/disconnected footprints cannot join.
	return polygon

static func path(polygon: PackedVector2Array) -> PackedVector2Array:
	if polygon.size() < 3: return PackedVector2Array()
	var along := Vector2(cos(.38), -sin(.38))
	var down := Vector2(sin(.38), cos(.38))
	var low := INF
	var high := -INF
	for point in polygon:
		low = minf(low, point.dot(along))
		high = maxf(high, point.dot(along))
	var count := maxi(2, ceili((high - low) / 3.4))
	var result := PackedVector2Array()
	for stripe in count:
		var u := lerpf(low, high, (float(stripe) + .5) / count)
		var hits: Array[float] = []
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			var au := a.dot(along)
			var bu := b.dot(along)
			if u < minf(au, bu) or u >= maxf(au, bu): continue
			hits.append(a.lerp(b, (u - au) / (bu - au)).dot(down))
		hits.sort()
		var spans: Array = []
		for i in range(0, hits.size() - 1, 2):
			spans.append([along * u + down * hits[i], along * u + down * hits[i + 1]])
		if stripe % 2: spans.reverse()
		for span in spans:
			var a: Vector2 = span[stripe % 2]
			var b: Vector2 = span[1 - stripe % 2]
			if not result.is_empty():
				if segment_inside(result[-1], a, polygon): result.append(a)
				else: result.append_array(boundary_route(result[-1], a, polygon))
			else: result.append(a)
			result.append(b)
	return result

static func segment_inside(a: Vector2, b: Vector2, polygon: PackedVector2Array) -> bool:
	var steps := maxi(2, ceili(a.distance_to(b) * 2.0))
	for i in range(1, steps):
		if not Geometry2D.is_point_in_polygon(a.lerp(b, float(i) / steps), polygon): return false
	return true

static func edge_at(point: Vector2, polygon: PackedVector2Array) -> int:
	var edge := 0
	var distance := INF
	for i in polygon.size():
		var near := Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])
		if near.distance_squared_to(point) < distance:
			distance = near.distance_squared_to(point)
			edge = i
	return edge

static func boundary_route(a: Vector2, b: Vector2, polygon: PackedVector2Array) -> PackedVector2Array:
	var start := edge_at(a, polygon)
	var finish := edge_at(b, polygon)
	var best := PackedVector2Array()
	var shortest := INF
	for direction in [-1, 1]:
		var route := PackedVector2Array([a])
		var edge := start
		for i in polygon.size():
			if edge == finish: break
			route.append(polygon[(edge + 1) % polygon.size()] if direction > 0 else polygon[edge])
			edge = posmod(edge + direction, polygon.size())
		route.append(b)
		var length := 0.0
		for i in range(1, route.size()): length += route[i - 1].distance_to(route[i])
		if length < shortest: shortest = length; best = route
	return best
