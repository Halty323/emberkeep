class_name Furnisher
extends RefCounted
## Resolves a themed layout into prop records for one room. Placement is
## intentional rather than scattered: tall furniture backs onto rear walls,
## centre pieces gather in open floor, crates cluster, and loose books sit
## near walls. Doorway lanes, entries, the pedestal, painting viewing areas,
## lanterns and chests are reserved before anything is placed.
const WALL_GAP := .2
## Free-standing solid pieces keep this much open floor around them, so the
## room's free space stays connected by construction.
const OPEN_MARGIN := 1.5
# Cluster starts hug the walls between the corner lanterns and the doorways.
const CLUSTER_OFFSETS := [Vector2(-4.6, -5.0), Vector2(4.6, -5.0), Vector2(-4.6, 5.0), Vector2(4.6, 5.0),
	Vector2(-7.0, -2.8), Vector2(7.0, -2.8), Vector2(-7.0, 2.8), Vector2(7.0, 2.8)]
const CENTER_OFFSETS := [Vector2.ZERO, Vector2(-4.2, 0), Vector2(4.2, 0), Vector2(0, -3.2), Vector2(0, 3.2),
	Vector2(-4.2, -3.2), Vector2(4.2, 3.2), Vector2(-4.2, 3.2), Vector2(4.2, -3.2)]

## Footprint rectangle of a prop at a quarter-turn rotation (front faces +z at 0).
static func footprint(definition: Dictionary, at: Vector2, rotation: int) -> Rect2:
	var size = Vector2(float(definition.size[0]), float(definition.size[1]))
	if rotation % 2 == 1:
		size = Vector2(size.y, size.x)
	return Rect2(at - size / 2.0, size)

## Quarter turns that make a prop's front face the given direction.
static func facing(direction: Vector2i) -> int:
	match direction:
		Vector2i(0, 1): return 0
		Vector2i(-1, 0): return 1
		Vector2i(0, -1): return 2
	return 3

static func rect_inside(geometry: RoomGeometry, rect: Rect2, margin := 0.0) -> bool:
	for corner in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), rect.get_center()]:
		if not geometry.contains(corner, margin): return false
	return true

static func hits_zone(rect: Rect2, zones: Array, solid: bool, margin := 0.0) -> bool:
	for zone in zones:
		# Flat rugs may lie under a pedestal or a viewing spot, never in a doorway.
		if not solid and zone.get("kind", "") in ["pedestal", "view", "lantern"]:
			continue
		if zone.has("rect") and zone.rect.grow(margin).intersects(rect): return true
		if zone.has("circle"):
			var nearest = Vector2(clampf(zone.circle.x, rect.position.x, rect.end.x), clampf(zone.circle.y, rect.position.y, rect.end.y))
			if nearest.distance_to(zone.circle) < zone.radius + margin: return true
	return false

static func record_rect(record: Dictionary) -> Rect2:
	var size = Vector2(float(record.size[0]), float(record.size[1]))
	var at = Vector2(float(record.position[0]), float(record.position[1]))
	return Rect2(at - size / 2.0, size)

static func fits(geometry: RoomGeometry, definition: Dictionary, rect: Rect2, zones: Array, placed: Array, gap: float) -> bool:
	var solid: bool = definition.get("solid", false)
	# A small margin keeps records clear after their positions are snapped.
	if not rect_inside(geometry, rect, .05) or hits_zone(rect, zones, solid, .02):
		return false
	var is_rug: bool = definition.recipe == "rug"
	for other in placed:
		var other_definition = Content.record("furniture", other.kind)
		var other_solid: bool = other_definition.get("solid", true)
		# Rugs lie under furniture; nothing else may overlap.
		if is_rug != (other_definition.get("recipe", "") == "rug"):
			continue
		var spacing = gap if solid and other_solid else .05
		if rect.grow(spacing).intersects(record_rect(other)):
			return false
	return true

static func make_record(room_id: String, index: int, definition: Dictionary, rect: Rect2, rotation: int) -> Dictionary:
	var record = {"id": "%s:f%d" % [room_id, index], "kind": definition.id, "position": FloorGenerator.point_array(rect.get_center()),
		"rotation": rotation, "size": [snappedf(rect.size.x, .001), snappedf(rect.size.y, .001)]}
	if definition.has("breakable"):
		record["destroyed"] = false
	return record

static func furnish(room: Dictionary, geometry: RoomGeometry, zones: Array, placed: Array, gen: RandomNumberGenerator) -> Array:
	var layouts = Content.families.layouts.filter(func(layout): return room.type in layout.roles)
	if layouts.is_empty():
		return []
	var layout: Dictionary = layouts[gen.randi_range(0, layouts.size() - 1)]
	room["theme"] = layout.id
	var all: Array = placed.duplicate()
	var added: Array = []
	for piece in layout.pieces:
		var definition: Dictionary = Content.record("furniture", piece.prop)
		# Larger rooms get proportionally more furniture.
		var count = gen.randi_range(int(piece.count[0]), int(piece.count[1])) * (1 + (geometry.cells.size() - 1) / 2)
		var cluster_anchor = null
		for i in count:
			var record = place(room, geometry, definition, zones, all, gen, cluster_anchor)
			if record.is_empty():
				continue
			record.id = "%s:f%d" % [room.id, added.size()]
			all.append(record)
			added.append(record)
			if definition.placement == "cluster":
				cluster_anchor = record_rect(record).get_center()
			for companion_id in piece.get("with", []):
				var companion = place_companion(room, geometry, Content.record("furniture", companion_id), record, zones, all, gen)
				if not companion.is_empty():
					companion.id = "%s:f%d" % [room.id, added.size()]
					all.append(companion)
					added.append(companion)
	return added

static func place(room: Dictionary, geometry: RoomGeometry, definition: Dictionary, zones: Array, all: Array, gen: RandomNumberGenerator, cluster_anchor) -> Dictionary:
	var candidates: Array = []
	match definition.placement:
		"wall":
			for segment in geometry.wall_segments():
				# Tall pieces stand only against rear walls, so they never hide
				# the room from the camera.
				if definition.get("tall", false) and RoomGeometry.is_front(segment.dir): continue
				var rotation = facing(-segment.dir)
				var size = Vector2(float(definition.size[0]), float(definition.size[1]))
				var along = segment.from + size.x / 2.0 + .7
				while along <= segment.to - size.x / 2.0 - .7:
					var across = segment.line - (segment.dir.x + segment.dir.y) * (size.y / 2.0 + .06)
					var center = Vector2(across, along) if segment.dir.x != 0 else Vector2(along, across)
					candidates.append({"rect": footprint(definition, center, rotation), "rotation": rotation, "gap": WALL_GAP})
					along += .75
		"center", "floor":
			for cell in geometry.cells:
				for offset in CENTER_OFFSETS:
					var center = RoomGeometry.cell_center(cell) + offset
					var rotation = 0 if gen.randf() < .7 else 1
					var rect = footprint(definition, center, rotation)
					if definition.get("solid", false) and not rect_inside(geometry, rect.grow(OPEN_MARGIN)): continue
					candidates.append({"rect": rect, "rotation": rotation, "gap": OPEN_MARGIN})
		"cluster":
			if cluster_anchor != null:
				for angle in 8:
					var center = cluster_anchor + Vector2.RIGHT.rotated(TAU * angle / 8.0) * (float(definition.size[0]) + .25)
					candidates.append({"rect": footprint(definition, center, 0), "rotation": 0, "gap": .1})
			else:
				for cell in geometry.cells:
					for offset in CLUSTER_OFFSETS:
						candidates.append({"rect": footprint(definition, RoomGeometry.cell_center(cell) + offset, 0), "rotation": 0, "gap": OPEN_MARGIN})
		"scatter":
			for attempt in 12:
				var point = geometry.random_point(gen, .6)
				candidates.append({"rect": footprint(definition, point, gen.randi_range(0, 3)), "rotation": 0, "gap": .1})
	# Deterministic shuffle from the dressing stream.
	for i in range(candidates.size() - 1, 0, -1):
		var j = gen.randi_range(0, i)
		var swap = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	for candidate in candidates:
		if fits(geometry, definition, candidate.rect, zones, all, candidate.gap):
			return make_record(room.id, 0, definition, candidate.rect, candidate.rotation)
	return {}

## Chairs face their table from its long sides.
static func place_companion(room: Dictionary, geometry: RoomGeometry, definition: Dictionary, parent: Dictionary, zones: Array, all: Array, gen: RandomNumberGenerator) -> Dictionary:
	var parent_rect = record_rect(parent)
	var rotation = int(parent.rotation)
	var sides = [Vector2(0, -1), Vector2(0, 1)] if rotation % 2 == 0 else [Vector2(-1, 0), Vector2(1, 0)]
	if gen.randf() < .5: sides.reverse()
	for side in sides:
		var reach = (parent_rect.size.y if rotation % 2 == 0 else parent_rect.size.x) / 2.0 + float(definition.size[1]) / 2.0 + .12
		var center = parent_rect.get_center() + side * reach
		var turn = facing(Vector2i(-side))
		var rect = footprint(definition, center, turn)
		var others = all.filter(func(record): return record.id != parent.id)
		if fits(geometry, definition, rect, zones, others, .2) and not rect.intersects(parent_rect):
			if not all.any(func(record): return record.kind == definition.id and record_rect(record).intersects(rect)):
				return make_record(room.id, 0, definition, rect, turn)
	return {}
