class_name Furnishing
extends RefCounted
## Deterministic, validated furniture layouts. Runs once at generation time;
## the resolved placements are saved with the room so later content edits can
## never move a bookcase onto an old saved spawn. Door lanes, entry circles,
## the reward spot and chests are reserved first, and every blocking prop must
## keep all required points reachable.
const WALL_GAP := .2
const CLEARANCE := .6
## Composite pieces: [definition, x, z, rotation] around the slot.
const GROUPS := {
	"table_set": [["table", 0.0, 0.0, 0], ["chair", -1.45, 0.0, 1], ["chair", 1.45, 0.0, 3]],
	"stool_pair": [["stool", -.65, 0.0, 0], ["stool", .65, 0.0, 0]],
}
const SLOT_KINDS := ["flank", "corner", "wall", "center", "scatter"]

## World footprint of a prop: rotations 1 and 3 swap width and depth.
static func footprint(def: Dictionary, position: Vector2, rotation: int) -> Rect2:
	var size := Vector2(float(def.size[0]), float(def.size[1]))
	if rotation % 2 == 1:
		size = Vector2(size.y, size.x)
	return Rect2(position - size / 2.0, size)

## Wall rotation: the prop's back faces the wall it stands against.
static func wall_rotation(dir: Vector2i) -> int:
	if dir == Vector2i(0, -1): return 0
	if dir == Vector2i(-1, 0): return 1
	if dir == Vector2i(0, 1): return 2
	return 3

static func record_rect(record: Dictionary) -> Rect2:
	return footprint(Content.get_def("furniture", record.def), Vector2(record.position[0], record.position[1]), int(record.rotation))

## Points that must stay reachable: doorway entries, the reward spot, chests.
static func required_points(geometry: RoomGeometry, layout: Dictionary, chests: Array) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for socket in layout.get("sockets", []):
		points.append(geometry.entry_point(socket.cell, socket.dir, 1.7))
	points.append(Vector2.ZERO)
	for chest in chests:
		points.append(Vector2(chest.position[0], chest.position[1] + 1.1))
	return points

static func reserved_circles(geometry: RoomGeometry, layout: Dictionary, chests: Array) -> Array:
	var circles: Array = [[Vector2(0, -.6), 3.2]]
	for socket in layout.get("sockets", []):
		for depth in [.8, 2.2, 3.6]:
			circles.append([geometry.entry_point(socket.cell, socket.dir, depth), 1.9])
	for p in lantern_points(geometry):
		circles.append([p, 1.0])
	for chest in chests:
		circles.append([Vector2(chest.position[0], chest.position[1]), 1.5])
		circles.append([Vector2(chest.position[0], chest.position[1] + 1.1), 1.0])
	return circles

## Lanterns stand in every cell corner that does not open onto the room.
static func lantern_points(geometry: RoomGeometry) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for cell in geometry.cells:
		var center := geometry.cell_center(cell)
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				if geometry.has_cell(cell + Vector2i(sx, 0)) and geometry.has_cell(cell + Vector2i(0, sz)):
					continue
				result.append(center + Vector2(sx * 7.65, sz * 5.65))
	return result

static func _rect_hits_circle(rect: Rect2, center: Vector2, radius: float) -> bool:
	var closest := Vector2(clampf(center.x, rect.position.x, rect.end.x), clampf(center.y, rect.position.y, rect.end.y))
	return closest.distance_to(center) < radius

static func _inside(geometry: RoomGeometry, rect: Rect2) -> bool:
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
		if not geometry.contains(corner, .05):
			return false
	return geometry.contains(rect.get_center(), .05)

static func reachable(geometry: RoomGeometry, obstacles: Array, points: Array[Vector2]) -> bool:
	return RoomNavigation.new(geometry, obstacles, CLEARANCE).connected(points)

static func pick_theme(role: String, gen: RandomNumberGenerator) -> Dictionary:
	var options: Array = Content.families.get("layouts", []).filter(func(t): return role in t.roles)
	if options.is_empty():
		return {}
	var total := 0.0
	for theme in options: total += float(theme.weight)
	var roll := gen.randf() * total
	for theme in options:
		roll -= float(theme.weight)
		if roll <= 0: return theme
	return options.back()

## Candidate slots: {kind, position, rotation (or -1 for free), back (tall OK)}.
static func slots(geometry: RoomGeometry, gen: RandomNumberGenerator) -> Dictionary:
	var result := {}
	for kind in SLOT_KINDS: result[kind] = []
	for side in geometry.exposed_sides():
		var dir: Vector2i = side.dir
		var back := dir.x + dir.y < 0
		var offsets := [-6.0, -2.7, 2.7, 6.0] if dir.y != 0 else [-4.3, 4.3]
		for along in offsets:
			var axis := Vector2(1, 0) if dir.y != 0 else Vector2(0, 1)
			result.wall.append({"anchor": side.mid + axis * along, "dir": dir, "back": back})
		for i in 2:
			var along := gen.randf_range(-6.5, 6.5) if dir.y != 0 else gen.randf_range(-5.0, 5.0)
			var axis := Vector2(1, 0) if dir.y != 0 else Vector2(0, 1)
			result.scatter.append({"anchor": side.mid + axis * along, "dir": dir, "back": back})
	for cell in geometry.cells:
		var c := geometry.cell_center(cell)
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				if geometry.has_cell(cell + Vector2i(sx, 0)) or geometry.has_cell(cell + Vector2i(0, sz)):
					continue
				result.corner.append({"corner": c + Vector2(sx * RoomGeometry.HALF.x, sz * RoomGeometry.HALF.y), "sx": sx, "sz": sz, "back": sz < 0 or sx < 0})
		for offset in [Vector2.ZERO, Vector2(-4.6, 0), Vector2(4.6, 0)]:
			result.center.append({"anchor": c + offset})
		for sx in [-1, 1]:
			result.flank.append({"anchor": c + Vector2(sx * 3.6, -3.4)})
	for kind in result:
		var list: Array = result[kind]
		for i in range(list.size() - 1, 0, -1):
			var j := gen.randi_range(0, i)
			var t = list[i]
			list[i] = list[j]
			list[j] = t
	return result

## Placements of one piece (or group) in a slot; empty when it cannot fit there.
static func place_in_slot(name: String, kind: String, slot: Dictionary) -> Array:
	var pieces: Array = GROUPS.get(name, [[name, 0.0, 0.0, 0]])
	var result: Array = []
	for piece in pieces:
		var def: Dictionary = Content.get_def("furniture", piece[0])
		if def.is_empty(): return []
		var position: Vector2
		var rotation: int = piece[3]
		match kind:
			"wall", "scatter":
				if def.get("tall", false) and not slot.back: return []
				rotation = wall_rotation(slot.dir)
				var depth := float(def.size[1])
				position = slot.anchor - Vector2(slot.dir) * (depth / 2.0 + WALL_GAP + .25)
			"corner":
				if def.get("tall", false) and not slot.back: return []
				# Lanterns own the corner itself; corner pieces stand just beside one
				# against the north or south wall.
				rotation = 0 if slot.sz < 0 else 2
				var rect := footprint(def, Vector2.ZERO, rotation)
				position = slot.corner - Vector2(slot.sx * (rect.size.x / 2.0 + 2.1), slot.sz * (rect.size.y / 2.0 + WALL_GAP + .25))
			_:
				position = slot.anchor + Vector2(piece[1], piece[2])
		result.append({"def": def.id, "position": position, "rotation": rotation})
	return result

## Pillars keep the positions combat rooms have always used.
static func pillars(room: Dictionary, geometry: RoomGeometry) -> Array:
	var result: Array = []
	for index in geometry.cells.size():
		var center := geometry.cell_center(geometry.cells[index])
		var points = [Vector2(-3.5, -2.7), Vector2(3.5, 2.7)]
		if (int(room.seed) + index) % 2 == 0:
			points = [Vector2(-3.8, 2.7), Vector2(3.8, -2.7)]
		for p in points:
			result.append({"def": "pillar", "position": center + p, "rotation": 0})
	return result

const MOUNT_SIZE := Vector2(2.6, 1.9)
const MOUNT_HEIGHT := 1.55

static func mount_point(mount: Dictionary) -> Vector2:
	return Vector2(mount.position[0], mount.position[1])

static func mount_dir(mount: Dictionary) -> Vector2:
	return Vector2(mount.dir[0], mount.dir[1])

## Where a viewer stands to inspect the painting.
static func view_point(mount: Dictionary) -> Vector2:
	return mount_point(mount) - mount_dir(mount) * 2.2

static func mount_circles(mount: Dictionary) -> Array:
	var m := mount_point(mount)
	var d := mount_dir(mount)
	var along := Vector2(absf(d.y), absf(d.x))
	return [[m - d * .5 - along * .9, .9], [m - d * .5 + along * .9, .9], [m - d * .5, .9], [view_point(mount), 1.4]]

## Paintings hang only on back walls, which stay visible when the near walls
## cut away, clear of doorways, seams, chests and pillars.
static func choose_mount(geometry: RoomGeometry, layout: Dictionary, chests: Array, placed: Array, gen: RandomNumberGenerator) -> Dictionary:
	var candidates: Array = []
	for side in geometry.exposed_sides():
		var dir: Vector2i = side.dir
		if dir.x + dir.y >= 0:
			continue
		var axis := Vector2(1, 0) if dir.y != 0 else Vector2(0, 1)
		for along in ([-4.5, 4.5, -2.8, 2.8] if dir.y != 0 else [-3.4, 3.4]):
			candidates.append({"cell": side.cell, "dir": dir, "point": side.mid + axis * along - Vector2(dir) * .05})
	for i in range(candidates.size() - 1, 0, -1):
		var j := gen.randi_range(0, i)
		var t = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = t
	for c in candidates:
		var mount := {"cell": [c.cell.x, c.cell.y], "position": [c.point.x, c.point.y], "dir": [c.dir.x, c.dir.y],
			"size": [MOUNT_SIZE.x, MOUNT_SIZE.y]}
		var view := view_point(mount)
		if not geometry.contains(view, .8):
			continue
		var clear := true
		for socket in layout.get("sockets", []):
			if geometry.socket_point(socket.cell, socket.dir).distance_to(c.point) < 2.9:
				clear = false
		for chest in chests:
			if Vector2(chest.position[0], chest.position[1]).distance_to(view) < 2.4 or Vector2(chest.position[0], chest.position[1]).distance_to(c.point) < 2.2:
				clear = false
		for p in lantern_points(geometry):
			if p.distance_to(c.point) < 1.9: clear = false
		for piece in placed:
			for circle in mount_circles(mount):
				if _rect_hits_circle(footprint(Content.get_def("furniture", piece.def), piece.position, piece.rotation), circle[0], circle[1]):
					clear = false
		if clear:
			return mount
	return {}

## Plan a room's furniture. Returns saved prop records.
static func plan(key: String, room: Dictionary, layout: Dictionary) -> Array:
	var geometry := RoomGeometry.new(layout.cells)
	var gen := RandomNumberGenerator.new()
	gen.seed = int(room.seed) + 7717
	var chests: Array = room.get("chests", [])
	var reserved := reserved_circles(geometry, layout, chests)
	var required := required_points(geometry, layout, chests)
	var placed: Array = []
	var nav := RoomNavigation.new(geometry, [], CLEARANCE)
	if room.type in ["combat", "boss"]:
		for pillar in pillars(room, geometry):
			placed.append(pillar)
			nav.block_rect(footprint(Content.get_def("furniture", "pillar"), pillar.position, 0))
	# A painting mount is reserved before any furniture, with its viewing spot.
	room.erase("mount")
	if room.get("gallery", "") != "":
		var mount := choose_mount(geometry, layout, chests, placed, gen)
		if not mount.is_empty():
			room["mount"] = mount
			reserved.append_array(mount_circles(mount))
			required.append(view_point(mount))
	var theme := pick_theme(room.type, gen)
	room["theme"] = theme.get("id", "")
	if not theme.is_empty():
		var all_slots := slots(geometry, gen)
		# Larger rooms get proportionally more furniture.
		for kind in SLOT_KINDS:
			var wanted: Array = []
			for i in geometry.cells.size():
				wanted.append_array(theme.get(kind, []))
			var free: Array = all_slots[kind]
			for name in wanted:
				for s in free.size():
					var pieces := place_in_slot(name, kind, free[s])
					if pieces.is_empty() or not _fits(geometry, pieces, placed, reserved):
						continue
					# Trial-block the pieces; undo them if a required point is cut off.
					var changed: Array[Vector2i] = []
					for piece in pieces:
						if Content.get_def("furniture", piece.def).blocks:
							changed.append_array(nav.block_rect(footprint(Content.get_def("furniture", piece.def), piece.position, piece.rotation)))
					if not changed.is_empty() and not nav.connected(required):
						nav.unblock(changed)
						continue
					placed.append_array(pieces)
					free.remove_at(s)
					break
	var records: Array = []
	for i in placed.size():
		var piece: Dictionary = placed[i]
		records.append({"id": "%s:p%d" % [key, i], "def": piece.def,
			"position": [piece.position.x, piece.position.y],
			"rotation": int(piece.rotation), "destroyed": false})
	return records

static func _fits(geometry: RoomGeometry, pieces: Array, placed: Array, reserved: Array) -> bool:
	for piece in pieces:
		var def: Dictionary = Content.get_def("furniture", piece.def)
		var rect := footprint(def, piece.position, piece.rotation)
		# Flat rugs may sit under other pieces and inside reserved paths; nothing
		# solid may.
		var flat: bool = piece.def == "rug"
		for circle in (reserved.slice(0, 1) if flat else reserved):
			if _rect_hits_circle(rect, circle[0], circle[1]):
				return false
		for other in placed:
			if flat != (other.def == "rug"):
				continue
			var other_rect := footprint(Content.get_def("furniture", other.def), other.position, other.rotation)
			if rect.grow(.25).intersects(other_rect):
				return false
		if not _inside(geometry, rect):
			return false
	return true
