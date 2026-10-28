class_name RoomGeometry
extends RefCounted
## Shared geometric queries for one logical room built from 18×14 map cells.
## Coordinates are room-local XZ: the origin cell is centered on (0, 0), and the
## other cells are offset by whole cell sizes. Actors, projectiles, furniture,
## camera bounds, navigation and effect clipping all ask this one object.
const CELL := Vector2(18, 14)
const HALF := Vector2(9, 7)
const DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
## Half-width of a doorway opening along its wall.
const DOOR_HALF_WIDTH := 1.2
var cells: Array[Vector2i] = []
var _cell_set: Dictionary = {}

func _init(local_cells: Array = [Vector2i.ZERO]) -> void:
	for cell in local_cells:
		var c := Vector2i(cell)
		if not _cell_set.has(c):
			cells.append(c)
			_cell_set[c] = true

func has_cell(cell: Vector2i) -> bool:
	return _cell_set.has(cell)

func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL.x, cell.y * CELL.y)

func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(cell_center(cell) - HALF, CELL)

func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / CELL.x), roundi(p.y / CELL.y))

func bounds() -> Rect2:
	var result := cell_rect(cells[0])
	for cell in cells:
		result = result.merge(cell_rect(cell))
	return result

## Every axis-aligned block of occupied cells (1×1, 2×1, 2×2, ...). A square
## smaller than a cell lies in the footprint exactly when it lies in one of
## these, which lets navigation fill whole regions instead of testing points.
func rectangles() -> Array[Rect2]:
	var result: Array[Rect2] = []
	var low := cells[0]
	var high := cells[0]
	for cell in cells:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	for x0 in range(low.x, high.x + 1):
		for y0 in range(low.y, high.y + 1):
			for x1 in range(x0, high.x + 1):
				for y1 in range(y0, high.y + 1):
					var full := true
					for x in range(x0, x1 + 1):
						for y in range(y0, y1 + 1):
							if not _cell_set.has(Vector2i(x, y)):
								full = false
					if full:
						result.append(cell_rect(Vector2i(x0, y0)).merge(cell_rect(Vector2i(x1, y1))))
	return result

static func flat(p) -> Vector2:
	return Vector2(p.x, p.z) if p is Vector3 else Vector2(p)

func _point_in_union(p: Vector2) -> bool:
	var cell := cell_at(p)
	for dx in [0, -1, 1]:
		for dy in [0, -1, 1]:
			var c := cell + Vector2i(dx, dy)
			if _cell_set.has(c) and cell_rect(c).grow(.0001).has_point(p):
				return true
	return false

## True when a square of half-size `margin` around p lies inside the floor
## footprint. For grid-aligned cells larger than the square this is exact,
## including the missing quadrant of an L-shaped room.
func contains(p, margin := 0.0) -> bool:
	var q := flat(p)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		if not _point_in_union(q + corner * margin):
			return false
	return true

## Closest footprint point that keeps `margin` clearance. Used as a geometry-
## validated safe spawn and as a recovery fallback, never to cross a void.
func nearest_inside(p, margin := .4) -> Vector2:
	var q := flat(p)
	if contains(q, margin):
		return q
	var best := Vector2.ZERO
	var best_distance := INF
	for cell in cells:
		var r := cell_rect(cell).grow(-margin)
		var candidate := Vector2(clampf(q.x, r.position.x, r.end.x), clampf(q.y, r.position.y, r.end.y))
		var d := candidate.distance_squared_to(q)
		if d < best_distance:
			best_distance = d
			best = candidate
	return best

## Exposed boundary segments, one per missing neighbour of each cell side.
## Each entry: cell, dir (outward), from, to (XZ endpoints), mid (socket point).
func exposed_sides() -> Array:
	var result: Array = []
	for cell in cells:
		for dir in DIRECTIONS:
			if _cell_set.has(cell + dir):
				continue
			var c := cell_center(cell)
			var mid := c + Vector2(dir.x * HALF.x, dir.y * HALF.y)
			var along := Vector2(absf(dir.y), absf(dir.x))
			var half_length := HALF.x if dir.y != 0 else HALF.y
			result.append({"cell": cell, "dir": dir, "mid": mid,
				"from": mid - along * half_length, "to": mid + along * half_length})
	return result

func socket_point(cell: Vector2i, dir: Vector2i) -> Vector2:
	return cell_center(cell) + Vector2(dir.x * HALF.x, dir.y * HALF.y)

## Entry anchor just inside a doorway, facing into the room.
func entry_point(cell: Vector2i, dir: Vector2i, depth := 1.7) -> Vector2:
	return socket_point(cell, dir) - Vector2(dir) * depth

## Inward normal of the nearest exposed boundary segment: the wall a projectile
## actually struck when it left the footprint.
func boundary_normal(p) -> Vector2:
	var q := flat(p)
	var best := Vector2.ZERO
	var best_distance := INF
	for side in exposed_sides():
		var closest := Geometry2D.get_closest_point_to_segment(q, side.from, side.to)
		var d := closest.distance_squared_to(q)
		if d < best_distance:
			best_distance = d
			best = -Vector2(side.dir)
	return best

## True when the straight segment stays on the floor with `margin` clearance.
func segment_clear(a, b, margin := .3, step := .5) -> bool:
	var p := flat(a)
	var q := flat(b)
	var count := maxi(1, ceili(p.distance_to(q) / step))
	for i in count + 1:
		if not contains(p.lerp(q, float(i) / count), margin):
			return false
	return true

## Packed cell rectangles for shaders: (x0, z0, x1, z1) per cell, up to four.
func shader_rects() -> PackedVector4Array:
	var result := PackedVector4Array()
	for cell in cells:
		if result.size() == 4: break
		var r := cell_rect(cell)
		var low := r.position
		var high := r.end
		# Extend shared sides so the mask has no seam between cells.
		if has_cell(cell + Vector2i(-1, 0)): low.x -= .3
		if has_cell(cell + Vector2i(1, 0)): high.x += .3
		if has_cell(cell + Vector2i(0, -1)): low.y -= .3
		if has_cell(cell + Vector2i(0, 1)): high.y += .3
		result.append(Vector4(low.x, low.y, high.x, high.y))
	while result.size() < 4:
		result.append(Vector4(0, 0, 0, 0))
	return result
