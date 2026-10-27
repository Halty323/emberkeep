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
	for x in grid.region.size.x:
		for y in grid.region.size.y:
			var id := Vector2i(x, y)
			grid.set_point_solid(id, not geometry.contains(to_world(id), clearance))
	for obstacle in obstacles:
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
