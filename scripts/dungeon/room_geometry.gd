class_name RoomGeometry
extends RefCounted
## Shared geometric queries for one logical room made of 18x14 cells. Local
## cell (0, 0) is centred on the room origin, exactly like the original single
## room, so 1x1 rooms keep their familiar coordinates. Actors, projectiles,
## furniture, the camera and effect clipping all ask this one object.
const CELL := Vector2(18, 14)
const HALF := Vector2(9, 7)
const SOCKET_HALF_WIDTH := 1.2
const WALL_OFFSET := .2
const WALL_THICKNESS := .45
const ENTRY_INSET := 1.7
const TRIGGER_DEPTH := .85
const TRIGGER_HALF_WIDTH := 1.1
const DIRECTIONS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
var terrain: FirstPersonTerrain
var cells: Array = []
var cell_set: Dictionary = {}
var min_cell := Vector2i.ZERO
var max_cell := Vector2i.ZERO

func _init(local_cells: Array) -> void:
	for value in local_cells:
		var cell = Vector2i(value)
		if cell_set.has(cell): continue
		cell_set[cell] = true
		cells.append(cell)
	min_cell = cells[0]
	max_cell = cells[0]
	for cell in cells:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))

static func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL.x, cell.y * CELL.y)

## Grid rotation by quarter turns in cell space, then normalised to a zero
## minimum. Turning the grid (not the world) keeps every cell 18x14.
static func rotate_cells(source: Array, quarter_turns: int) -> Array:
	var rotated: Array = []
	for value in source:
		rotated.append(rotate_cell(Vector2i(value), quarter_turns))
	var low = rotated[0]
	for cell in rotated:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
	return rotated.map(func(cell): return cell - low)

static func rotate_cell(cell: Vector2i, quarter_turns: int) -> Vector2i:
	var result = cell
	for turn in posmod(quarter_turns, 4):
		result = Vector2i(-result.y, result.x)
	return result

## Rotates a normalised in-cell anchor with the same quarter turns as its cell.
static func rotate_offset(offset: Vector2, quarter_turns: int) -> Vector2:
	var result = offset
	for turn in posmod(quarter_turns, 4):
		result = Vector2(-result.y, result.x)
	return result

## Resolves a template anchor (cell + offset in half-extent units) after the
## template's cells were rotated and normalised.
static func resolve_anchor(template_cells: Array, quarter_turns: int, anchor: Dictionary) -> Vector2:
	var low = rotate_cell(Vector2i(template_cells[0]), quarter_turns)
	for value in template_cells:
		var turned = rotate_cell(Vector2i(value), quarter_turns)
		low = Vector2i(mini(low.x, turned.x), mini(low.y, turned.y))
	var cell = rotate_cell(anchor.cell, quarter_turns) - low
	return cell_center(cell) + rotate_offset(anchor.offset, quarter_turns) * HALF

func has_cell(cell: Vector2i) -> bool:
	return cell_set.has(cell)

func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(floori((point.x + HALF.x) / CELL.x), floori((point.y + HALF.y) / CELL.y))

## True when the square of half-size `margin` around the point lies entirely on
## footprint cells. Open seams inside the room pass; exposed edges and the
## missing quadrant of an L do not.
func contains(point: Vector2, margin := 0.0) -> bool:
	var low = cell_at(point - Vector2(margin, margin))
	var high = cell_at(point + Vector2(margin, margin) - Vector2(.0001, .0001))
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			if not cell_set.has(Vector2i(x, y)): return false
	return true

func bounds() -> Rect2:
	return Rect2(cell_center(min_cell) - HALF, Vector2(max_cell - min_cell + Vector2i.ONE) * CELL)

func center() -> Vector2:
	return bounds().get_center()

func exposed_edges() -> Array:
	var result: Array = []
	for cell in cells:
		for direction in DIRECTIONS:
			if not cell_set.has(cell + direction):
				result.append({"cell": cell, "dir": direction})
	return result

## Midpoint of a cell edge; every exposed edge has one possible doorway socket.
static func socket_point(cell: Vector2i, direction: Vector2i) -> Vector2:
	return cell_center(cell) + Vector2(direction) * HALF

static func entry_point(cell: Vector2i, direction: Vector2i) -> Vector2:
	return socket_point(cell, direction) - Vector2(direction) * ENTRY_INSET

## The doorway trigger lies inside the room, against the socket.
static func in_trigger(point: Vector2, cell: Vector2i, direction: Vector2i) -> bool:
	var socket = socket_point(cell, direction)
	var inward = (socket - point).dot(Vector2(direction))
	var lateral = absf((point - socket).dot(Vector2(direction.y, direction.x)))
	return inward >= -.01 and inward < TRIGGER_DEPTH and lateral < TRIGGER_HALF_WIDTH

## Straight wall runs along exposed edges, merged across cells and then cut at
## every socket so doorways (or their plugs) keep their place in the run.
func wall_segments() -> Array:
	var lines := {}
	for edge in exposed_edges():
		var direction: Vector2i = edge.dir
		var horizontal = direction.x == 0
		var line = (edge.cell.y * CELL.y + direction.y * HALF.y) if horizontal else (edge.cell.x * CELL.x + direction.x * HALF.x)
		var along = cell_center(edge.cell).x if horizontal else cell_center(edge.cell).y
		var half = HALF.x if horizontal else HALF.y
		var key = "%d:%d:%.3f" % [direction.x, direction.y, line]
		if not lines.has(key): lines[key] = {"dir": direction, "line": line, "spans": []}
		lines[key].spans.append(Vector2(along - half, along + half))
	var segments: Array = []
	for key in lines:
		var entry: Dictionary = lines[key]
		var spans: Array = entry.spans
		spans.sort_custom(func(a, b): return a.x < b.x)
		var merged: Array = []
		for span in spans:
			if not merged.is_empty() and absf(merged.back().y - span.x) < .001:
				merged[merged.size() - 1] = Vector2(merged.back().x, span.y)
			else:
				merged.append(span)
		for run in merged:
			var start: float = run.x
			var length = HALF.x * 2 if entry.dir.x == 0 else HALF.y * 2
			var socket = run.x + length / 2.0
			while socket < run.y:
				segments.append({"dir": entry.dir, "line": entry.line, "from": start, "to": socket - SOCKET_HALF_WIDTH})
				start = socket + SOCKET_HALF_WIDTH
				socket += length
			segments.append({"dir": entry.dir, "line": entry.line, "from": start, "to": run.y})
	return segments

## Box for a wall segment: centre (x, z), size along x/z, outward normal.
static func segment_box(segment: Dictionary) -> Dictionary:
	var direction: Vector2i = segment.dir
	var mid = (segment.from + segment.to) / 2.0
	var length = segment.to - segment.from
	var offset = segment.line + (direction.x + direction.y) * WALL_OFFSET
	if direction.x == 0:
		return {"center": Vector2(mid, offset), "size": Vector2(length, WALL_THICKNESS)}
	return {"center": Vector2(offset, mid), "size": Vector2(WALL_THICKNESS, length)}

static func is_front(direction: Vector2i) -> bool:
	return direction.x > 0 or direction.y > 0

## When a segment leaves the footprint, the struck exposed edge's inward normal.
## Cells are walked in crossing order so an L bend reports the wall actually hit.
func exit_normal(from: Vector2, to: Vector2, margin := 0.0) -> Vector2:
	var cell = cell_at(from)
	var delta = to - from
	var step = Vector2i(int(signf(delta.x)), int(signf(delta.y)))
	for guard in 8:
		var next_x = INF
		var next_y = INF
		if step.x != 0:
			var edge_x = cell_center(cell).x + step.x * HALF.x
			next_x = (edge_x - from.x) / delta.x
		if step.y != 0:
			var edge_y = cell_center(cell).y + step.y * HALF.y
			next_y = (edge_y - from.y) / delta.y
		var t = minf(next_x, next_y)
		if t > 1.0:
			break
		var moved = Vector2i(step.x, 0) if next_x <= next_y else Vector2i(0, step.y)
		if not cell_set.has(cell + moved):
			return -Vector2(moved)
		cell += moved
	# The point stays on a footprint cell but within the margin of an edge.
	var best = Vector2.ZERO
	var best_distance = INF
	var target_cell = cell_at(to)
	for direction in DIRECTIONS:
		if cell_set.has(target_cell + direction): continue
		var edge = (cell_center(target_cell) + Vector2(direction) * HALF).dot(Vector2(direction).abs())
		var distance = absf(edge - to.dot(Vector2(direction).abs()))
		if distance < best_distance and distance <= margin + .0001:
			best_distance = distance
			best = -Vector2(direction)
	return best

## Last-valid-position recovery shared by every actor. Physics stays primary;
## this only undoes numerical escape. Axis-separated fallbacks keep sliding
## along a wall, and nothing ever jumps across an L's missing quadrant.
func recover(previous: Vector2, proposed: Vector2, margin: float) -> Vector2:
	if contains(proposed, margin):
		return proposed
	var keep_y = Vector2(proposed.x, previous.y)
	if contains(keep_y, margin):
		return keep_y
	var keep_x = Vector2(previous.x, proposed.y)
	if contains(keep_x, margin):
		return keep_x
	return previous if contains(previous, margin) else safe_point(previous, margin)

## Deterministic nearest valid point: the preferred point if it is clear,
## otherwise the closest point on a half-unit lattice. Never crosses into the
## missing quadrant of an L, because every candidate is checked by contains().
func safe_point(preferred: Vector2, margin: float, blocked: Callable = Callable()) -> Vector2:
	if contains(preferred, margin) and (not blocked.is_valid() or not blocked.call(preferred)):
		return preferred
	var area = bounds().grow(-margin)
	var best = cell_center(cells[0])
	var best_distance = INF
	var x = area.position.x
	while x <= area.end.x:
		var y = area.position.y
		while y <= area.end.y:
			var candidate = Vector2(x, y)
			var distance = candidate.distance_squared_to(preferred)
			if distance < best_distance and contains(candidate, margin) and (not blocked.is_valid() or not blocked.call(candidate)):
				best_distance = distance
				best = candidate
			y += .5
		x += .5
	return best

func random_point(rng: RandomNumberGenerator, margin: float) -> Vector2:
	for attempt in 24:
		var cell: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var point = cell_center(cell) + Vector2(rng.randf_range(-HALF.x, HALF.x), rng.randf_range(-HALF.y, HALF.y))
		if contains(point, margin): return point
	return cell_center(cells[0])

## Footprint mask shared by halos, glows and floor marks (one texel per cell).
func mask_image() -> Image:
	var size = max_cell - min_cell + Vector2i.ONE
	var image = Image.create(size.x, size.y, false, Image.FORMAT_R8)
	for cell in cells:
		image.set_pixel(cell.x - min_cell.x, cell.y - min_cell.y, Color(1, 0, 0))
	return image

func shader_mask_values() -> Dictionary:
	return {"room_footprint": ImageTexture.create_from_image(mask_image()),
		"room_grid_origin": cell_center(min_cell) - HALF,
		"room_grid_cells": Vector2(max_cell - min_cell + Vector2i.ONE)}

func apply_shader_mask() -> void:
	var values = shader_mask_values()
	for key in values:
		RenderingServer.global_shader_parameter_set(key, values[key])
