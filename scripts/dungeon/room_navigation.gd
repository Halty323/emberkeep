class_name RoomNavigation
extends RefCounted
## Coarse grid navigation for concave rooms. One-unit cells, actor clearance,
## and no diagonal corner cutting. Direct pursuit remains the fast path; paths
## are only needed when the straight line leaves the floor (an L-shaped bend).
const STEP := 1.0
var geometry: RoomGeometry
var grid := AStarGrid2D.new()
var origin := Vector2.ZERO
var clearance := .6
## Grid points covered by furniture or pillars themselves (no clearance), for
## cheap line-of-travel checks.
var blocked: Dictionary = {}

func _init(room_geometry: RoomGeometry, obstacles: Array = [], actor_clearance := .6) -> void:
	geometry = room_geometry
	clearance = actor_clearance
	var area := geometry.bounds()
	origin = area.position
	grid.region = Rect2i(0, 0, ceili(area.size.x / STEP), ceili(area.size.y / STEP))
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	# Same result as testing geometry.contains(point, clearance) per point,
	# filled a block of cells at a time.
	grid.fill_solid_region(grid.region, true)
	for rect in geometry.rectangles():
		var inner := rect.grow(-clearance + .0001)
		var low := Vector2i(ceili((inner.position.x - origin.x) / STEP - .5), ceili((inner.position.y - origin.y) / STEP - .5))
		var high := Vector2i(floori((inner.end.x - origin.x) / STEP - .5), floori((inner.end.y - origin.y) / STEP - .5))
		low = low.clamp(Vector2i.ZERO, grid.region.size - Vector2i.ONE)
		high = high.clamp(Vector2i.ZERO, grid.region.size - Vector2i.ONE)
		if high.x >= low.x and high.y >= low.y:
			grid.fill_solid_region(Rect2i(low, high - low + Vector2i.ONE), false)
	for obstacle in obstacles:
		if obstacle.has("rect"):
			block_rect(obstacle.rect)
		else:
			block_circle(RoomGeometry.flat(obstacle.position), float(obstacle.radius))

func to_world(id: Vector2i) -> Vector2:
	return origin + (Vector2(id) + Vector2(.5, .5)) * STEP

func to_grid(p: Vector2) -> Vector2i:
	var id := Vector2i(floori((p.x - origin.x) / STEP), floori((p.y - origin.y) / STEP))
	return id.clamp(grid.region.position, grid.region.end - Vector2i.ONE)

func block_circle(center: Vector2, radius: float, solid := true) -> void:
	var r := radius + clearance
	var low := to_grid(center - Vector2.ONE * r)
	var high := to_grid(center + Vector2.ONE * r)
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			var id := Vector2i(x, y)
			if to_world(id).distance_to(center) <= r:
				grid.set_point_solid(id, solid or not geometry.contains(to_world(id), clearance))
				if to_world(id).distance_to(center) <= radius + .3:
					if solid: blocked[id] = true
					else: blocked.erase(id)

## Block a furniture footprint. Returns the points that became solid so a
## planner can undo a trial placement cheaply.
func block_rect(rect: Rect2) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	var grown := rect.grow(clearance)
	var low := to_grid(grown.position)
	var high := to_grid(grown.end)
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			var id := Vector2i(x, y)
			var p := to_world(id)
			if grown.has_point(p):
				if not grid.is_point_solid(id):
					changed.append(id)
					grid.set_point_solid(id, true)
				if rect.grow(.3).has_point(p): blocked[id] = true
	return changed

func unblock(ids: Array[Vector2i]) -> void:
	for id in ids:
		grid.set_point_solid(id, false)
		blocked.erase(id)

## True when every point can reach the first one.
func connected(points: Array[Vector2]) -> bool:
	if points.size() < 2:
		return true
	var start := nearest_open(to_grid(points[0]))
	for i in range(1, points.size()):
		var goal := nearest_open(to_grid(points[i]))
		if goal != start and grid.get_id_path(start, goal).is_empty():
			return false
	return true

## True when the straight line a→b crosses no furniture or pillar.
func line_clear(a: Vector2, b: Vector2) -> bool:
	if blocked.is_empty():
		return true
	var count := maxi(1, ceili(a.distance_to(b) / (STEP * .5)))
	for i in count + 1:
		if blocked.has(to_grid(a.lerp(b, float(i) / count))):
			return false
	return true

func nearest_open(id: Vector2i) -> Vector2i:
	if not grid.is_point_solid(id):
		return id
	for ring in range(1, 6):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				var candidate := (id + Vector2i(dx, dy)).clamp(grid.region.position, grid.region.end - Vector2i.ONE)
				if not grid.is_point_solid(candidate):
					return candidate
	return id

## World-space XZ waypoints from a to b, excluding the start; empty if blocked.
func find_path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var start := nearest_open(to_grid(a))
	var goal := nearest_open(to_grid(b))
	var ids := grid.get_id_path(start, goal, true)
	var result := PackedVector2Array()
	for i in range(1, ids.size()):
		result.append(to_world(ids[i]))
	if not result.is_empty():
		result[result.size() - 1] = b if geometry.contains(b, clearance) else result[result.size() - 1]
	return result
