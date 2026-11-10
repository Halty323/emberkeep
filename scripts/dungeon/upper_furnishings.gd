class_name UpperFurnishings
extends RefCounted
## Resolve and save a complete upstairs layout using normal prop recipes.
## Its collision, breakables, tabletop dressing and emitters use the same
## pipeline as the ground floor. No gameplay RNG is consumed.
const KINDS := ["table", "bookcase", "bench", "crate", "barrel", "jar", "workbench", "cot", "brazier", "cupboard"]

static func resolve(room, records: Array) -> Array:
	if not room.terrain or not room.terrain.loft: return records
	if room.data.get("upper_furnished", false): return records
	var loft = room.terrain.loft
	var result := records.duplicate(true)
	var occupied: Array[Rect2] = []
	var gen := RandomNumberGenerator.new()
	gen.seed = Content.stable_hash("upstairs-furniture:%s:%s" % [room.data.get("seed", 0), room.data.get("id", "")])
	var candidates: Array[Vector2] = []
	for cell in room.geometry.cells:
		var center: Vector2 = RoomGeometry.cell_center(cell)
		for x in [-6.5, -4.0, -1.5, 1.5, 4.0, 6.5]:
			for z in [-4.8, -2.4, 0.0, 2.4, 4.8]: candidates.append(center + Vector2(x, z))
	# Existing ground-floor compositions supply the first choices upstairs.
	for record in records:
		if record.kind in KINDS: candidates.push_front(Vector2(record.position[0], record.position[1]))
	var target := maxi(8 * room.geometry.cells.size(), mini(records.size(), 14 * room.geometry.cells.size()))
	for point in candidates:
		if occupied.size() >= target: break
		var kind: String = KINDS[gen.randi_range(0, KINDS.size() - 1)]
		var definition: Dictionary = Content.record("furniture", kind)
		var size := Vector2(definition.size[0], definition.size[1])
		var area := Rect2(point - size * .5, size)
		var clear := area.grow(.6)
		if [clear.position, Vector2(clear.end.x, clear.position.y), clear.end, Vector2(clear.position.x, clear.end.y)].any(func(p): return not loft.on_deck(p, .2)): continue
		if clear.intersects(LoftRoom.reserved_area(loft.stairs, loft.facing)): continue
		if loft.upper_spots().any(func(p): return clear.grow(.65).has_point(p)): continue
		if room.navigation_blockers(LoftRoom.RISE).values().any(func(other): return other.grow(.5).intersects(clear)): continue
		if occupied.any(func(other): return other.grow(.7).intersects(clear)): continue
		if loft.upper_lanterns().any(func(p): return clear.grow(.4).has_point(Vector2(p.x, p.z))): continue
		result.append({"id": "%s:upper:%d" % [room.data.get("id", "room"), occupied.size()], "kind": kind,
			"position": [point.x, point.y], "height": LoftRoom.RISE, "rotation": 0, "size": [size.x, size.y]})
		occupied.append(area)
	room.data.props = result
	room.data.upper_furnished = true
	return result
