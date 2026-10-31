class_name RoomNavigation
extends RefCounted
## Coarse grid navigation for one room. Diagonal steps never cut a blocked
## corner, so enemies route around L bends and furniture instead of pressing
## into them. Blockers can be removed later (a broken crate) and only the
## affected cells are recomputed.
const STEP := .5
var geometry: RoomGeometry
var clearance := .5
var grid := AStarGrid2D.new()
var origin := Vector2.ZERO
var blockers: Dictionary = {}

func _init(room_geometry: RoomGeometry, actor_clearance := .5, initial_blockers: Dictionary = {}) -> void:
	geometry = room_geometry
	clearance = actor_clearance
	blockers = initial_blockers.duplicate()
	var area = geometry.bounds()
	origin = area.position
	grid.region = Rect2i(0, 0, ceili(area.size.x / STEP), ceili(area.size.y / STEP))
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	refresh_area(area)

func to_grid(point: Vector2) -> Vector2i:
	var cell = Vector2i(floori((point.x - origin.x) / STEP), floori((point.y - origin.y) / STEP))
	return cell.clamp(grid.region.position, grid.region.end - Vector2i.ONE)

func to_world(cell: Vector2i) -> Vector2:
	return origin + (Vector2(cell) + Vector2(.5, .5)) * STEP

func walkable(point: Vector2) -> bool:
	if not geometry.contains(point, clearance):
		return false
	if geometry.terrain and not geometry.terrain.traversable(point, clearance): return false
	for id in blockers:
		if blockers[id].grow(clearance).has_point(point):
			return false
	return true

func refresh_area(area: Rect2) -> void:
	var low = to_grid(area.position - Vector2.ONE * (clearance + STEP))
	var high = to_grid(area.end + Vector2.ONE * (clearance + STEP))
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			var cell = Vector2i(x, y)
			grid.set_point_solid(cell, not walkable(to_world(cell)))

func remove_blocker(id: String) -> void:
	if not blockers.has(id):
		return
	var area: Rect2 = blockers[id]
	blockers.erase(id)
	refresh_area(area)

func is_open(cell: Vector2i) -> bool:
	return grid.is_in_boundsv(cell) and not grid.is_point_solid(cell)

func nearest_open(cell: Vector2i) -> Variant:
	if is_open(cell):
		return cell
	for radius in range(1, 6):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) == radius and is_open(cell + Vector2i(x, y)):
					return cell + Vector2i(x, y)
	return null

## World-space waypoints, excluding the start. Empty when no route exists.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var start = nearest_open(to_grid(from))
	var goal = nearest_open(to_grid(to))
	var points := PackedVector2Array()
	if start == null or goal == null:
		return points
	var cells = grid.get_id_path(start, goal, true)
	for index in range(1, cells.size()):
		points.append(to_world(cells[index]))
	if not points.is_empty() and walkable(to):
		points[points.size() - 1] = to
	return points

## True when an actor of this clearance can travel straight between points.
func line_clear(from: Vector2, to: Vector2) -> bool:
	var distance = from.distance_to(to)
	var samples = maxi(1, ceili(distance / (STEP * .5)))
	for index in range(1, samples + 1):
		if not walkable(from.lerp(to, float(index) / samples)):
			return false
	return true

func reachable(from: Vector2, to: Vector2) -> bool:
	var start = nearest_open(to_grid(from))
	var goal = nearest_open(to_grid(to))
	if start == null or goal == null:
		return false
	if start == goal:
		return true
	var cells = grid.get_id_path(start, goal, false)
	return not cells.is_empty()
