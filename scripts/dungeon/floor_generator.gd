class_name FloorGenerator
extends RefCounted
## Generator v2: multi-cell rooms joined only through explicit portals. Two
## rooms sharing a cell edge are not connected unless a portal says so.
## Order: mandatory graph with legal footprints, role assignment, validation.
## Retries are bounded; the last resort is a known-valid single-cell floor.
const VERSION := 2
const LEGACY_VERSION := 1
const BOUNDS := 5
const MAX_ATTEMPTS := 10
const EXTRA_PORTAL_CHANCE := .3
const SPECIAL_ROLES := ["boss", "treasure", "shop", "rest"]
const START_ID := "0,0"

static func generate(seed_value: int, floor_number: int) -> Dictionary:
	for attempt in MAX_ATTEMPTS:
		var floor_data = attempt_floor(seed_value, floor_number, attempt)
		if not floor_data.is_empty() and validate(floor_data).is_empty():
			return floor_data
	var fallback = from_legacy(legacy_rooms(seed_value, floor_number))
	fallback["fallback"] = true
	return fallback

static func vec(value) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))

static func key_of(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

static func room_cells(room: Dictionary) -> Array:
	return room.cells.map(func(value): return vec(value))

static func attempt_floor(seed_value: int, floor_number: int, attempt: int) -> Dictionary:
	var gen = RandomNumberGenerator.new()
	gen.seed = Content.stable_hash("topology:%d:%d:%d" % [seed_value, floor_number, attempt])
	var floor_data = {"rooms": {}, "portals": {}, "owners": {}, "generator": VERSION}
	place_room(floor_data, Content.record("rooms", "hearth_1x1"), 0, Vector2i.ZERO, seed_value, floor_number)
	var target = 11 + floor_number * 2
	var cell_budget = target + 6 + floor_number
	var cells_used = 1
	var templates = Content.families.rooms.filter(func(t): return "combat" in t.roles)
	var guard = 0
	while floor_data.rooms.size() < target and guard < 600:
		guard += 1
		var ids: Array = floor_data.rooms.keys()
		var parent: Dictionary = floor_data.rooms[ids[gen.randi_range(0, ids.size() - 1)]]
		var edges = free_edges(floor_data, parent)
		if edges.is_empty():
			continue
		var edge: Dictionary = edges[gen.randi_range(0, edges.size() - 1)]
		var template = pick_template(gen, templates, cell_budget - cells_used)
		var rotation: int = template.rotations[gen.randi_range(0, template.rotations.size() - 1)]
		var shape = RoomGeometry.rotate_cells(template.cells, rotation)
		var target_cell: Vector2i = edge.cell + edge.dir
		var anchors: Array = []
		for local in shape:
			if fits(floor_data, shape, target_cell - local):
				anchors.append(target_cell - local)
		if anchors.is_empty():
			continue
		place_room(floor_data, template, rotation, anchors[gen.randi_range(0, anchors.size() - 1)], seed_value, floor_number)
		add_portal(floor_data, edge.cell, edge.dir)
		cells_used += shape.size()
	if floor_data.rooms.size() < target:
		return {}
	# Some extra doorways create loops; adjacency alone never does.
	for room in floor_data.rooms.values():
		for edge in all_edges(room):
			var other = floor_data.owners.get(key_of(edge.cell + edge.dir), "")
			if other != "" and other != room.id and not connected(floor_data, room.id, other) and gen.randf() < EXTRA_PORTAL_CHANCE:
				add_portal(floor_data, edge.cell, edge.dir)
	if not floor_data.rooms.values().any(func(room): return room.cells.size() > 1):
		return {}
	if not assign_roles(floor_data):
		return {}
	return floor_data

static func pick_template(gen: RandomNumberGenerator, templates: Array, cells_left: int) -> Dictionary:
	var choices = templates.filter(func(t): return t.cells.size() <= maxi(1, cells_left))
	var total = 0.0
	for template in choices: total += template.weight
	var roll = gen.randf() * total
	for template in choices:
		roll -= template.weight
		if roll <= 0: return template
	return choices.back()

static func fits(floor_data: Dictionary, shape: Array, anchor: Vector2i) -> bool:
	for local in shape:
		var cell: Vector2i = anchor + local
		if absi(cell.x) > BOUNDS or absi(cell.y) > BOUNDS or floor_data.owners.has(key_of(cell)):
			return false
	return true

static func place_room(floor_data: Dictionary, template: Dictionary, rotation: int, anchor: Vector2i, seed_value: int, floor_number: int) -> String:
	var shape = RoomGeometry.rotate_cells(template.cells, rotation)
	var cells: Array = shape.map(func(local): return anchor + local)
	# A stable logical id: the room's first cell in row order. It never
	# collides because rooms never share cells.
	var first: Vector2i = cells[0]
	for cell in cells:
		if cell.y < first.y or (cell.y == first.y and cell.x < first.x): first = cell
	var id = key_of(first)
	var room = {"id": id, "template": template.id, "revision": template.revision, "rotation": rotation,
		"anchor": [anchor.x, anchor.y], "cells": cells.map(func(cell): return [cell.x, cell.y]),
		"type": "start" if id == START_ID else "combat", "depth": 0,
		"seed": seed_value + floor_number * 10007 + first.x * 719 + first.y * 1117,
		"visited": id == START_ID, "cleared": id == START_ID, "claimed": id == START_ID, "portals": [],
		# Resolved blueprint: later template edits cannot move saved anchors.
		"lights": template.lights.map(func(anchor_value): return point_array(RoomGeometry.resolve_anchor(template.cells, rotation, anchor_value))),
		"pedestal": point_array(RoomGeometry.resolve_anchor(template.cells, rotation, template.pedestal))}
	floor_data.rooms[id] = room
	for cell in cells:
		floor_data.owners[key_of(cell)] = id
	return id

static func point_array(point: Vector2) -> Array:
	return [snappedf(point.x, .001), snappedf(point.y, .001)]

static func all_edges(room: Dictionary) -> Array:
	var cells = room_cells(room)
	var result: Array = []
	for cell in cells:
		for direction in RoomGeometry.DIRECTIONS:
			if not cells.has(cell + direction):
				result.append({"cell": cell, "dir": direction})
	return result

static func free_edges(floor_data: Dictionary, room: Dictionary) -> Array:
	return all_edges(room).filter(func(edge):
		var next: Vector2i = edge.cell + edge.dir
		return absi(next.x) <= BOUNDS and absi(next.y) <= BOUNDS and not floor_data.owners.has(key_of(next)))

static func connected(floor_data: Dictionary, a: String, b: String) -> bool:
	for id in floor_data.rooms[a].portals:
		var portal = floor_data.portals[id]
		if portal.a.room == b or portal.b.room == b: return true
	return false

static func add_portal(floor_data: Dictionary, cell: Vector2i, direction: Vector2i, state := "open") -> String:
	var id = "p%d" % floor_data.portals.size()
	var other: Vector2i = cell + direction
	var room_a: String = floor_data.owners[key_of(cell)]
	var room_b: String = floor_data.owners[key_of(other)]
	floor_data.portals[id] = {"id": id, "state": state,
		"a": {"room": room_a, "cell": [cell.x, cell.y], "dir": [direction.x, direction.y]},
		"b": {"room": room_b, "cell": [other.x, other.y], "dir": [-direction.x, -direction.y]}}
	floor_data.rooms[room_a].portals.append(id)
	floor_data.rooms[room_b].portals.append(id)
	return id

static func distances(floor_data: Dictionary, include_concealed := false) -> Dictionary:
	var result = {START_ID: 0}
	var queue: Array = [START_ID]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		for portal_id in floor_data.rooms[id].portals:
			var portal = floor_data.portals[portal_id]
			if portal.state == "concealed" and not include_concealed: continue
			var other: String = portal.b.room if portal.a.room == id else portal.a.room
			if not result.has(other):
				result[other] = result[id] + 1
				queue.append(other)
	return result

static func assign_roles(floor_data: Dictionary) -> bool:
	var depth = distances(floor_data)
	var order: Array = floor_data.rooms.keys()
	var index := {}
	for i in order.size(): index[order[i]] = i
	order.sort_custom(func(a, b): return depth[a] > depth[b] or (depth[a] == depth[b] and index[a] < index[b]))
	for id in floor_data.rooms:
		floor_data.rooms[id].depth = depth.get(id, 0)
	for role in SPECIAL_ROLES:
		var chosen = ""
		for id in order:
			var room = floor_data.rooms[id]
			if room.type == "combat" and role in Content.record("rooms", room.template).get("roles", []):
				chosen = id
				break
		if chosen == "":
			return false
		floor_data.rooms[chosen].type = role
	return true

## Structural validation used after every generation attempt and by tests.
static func validate(floor_data: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var owners := {}
	for id in floor_data.rooms:
		var room = floor_data.rooms[id]
		for cell in room_cells(room):
			if owners.has(cell): problems.append("cell %s is occupied twice" % cell)
			owners[cell] = id
	var sockets := {}
	for portal_id in floor_data.portals:
		var portal = floor_data.portals[portal_id]
		var a_cell = vec(portal.a.cell)
		var b_cell = vec(portal.b.cell)
		var a_dir = vec(portal.a.dir)
		if owners.get(a_cell) != portal.a.room or owners.get(b_cell) != portal.b.room:
			problems.append("portal %s endpoints do not belong to their rooms" % portal_id)
		if a_cell + a_dir != b_cell or vec(portal.b.dir) != -a_dir:
			problems.append("portal %s is not reciprocal" % portal_id)
		if portal.a.room == portal.b.room:
			problems.append("portal %s connects a room to itself" % portal_id)
		for side in [portal.a, portal.b]:
			var socket = "%s:%s" % [str(side.cell), str(side.dir)]
			if sockets.has(socket): problems.append("socket %s holds two portals" % socket)
			sockets[socket] = true
			if portal_id not in floor_data.rooms[side.room].portals:
				problems.append("room %s does not list portal %s" % [side.room, portal_id])
	if not floor_data.rooms.has(START_ID) or floor_data.rooms[START_ID].type != "start":
		problems.append("floor has no start room at the origin")
		return problems
	var counts := {}
	for room in floor_data.rooms.values():
		counts[room.type] = counts.get(room.type, 0) + 1
		var template = Content.record("rooms", room.template)
		if not template.is_empty() and room.type not in template.roles:
			problems.append("room %s template does not allow role %s" % [room.id, room.type])
	for role in ["start"] + SPECIAL_ROLES:
		if counts.get(role, 0) != 1: problems.append("floor needs exactly one %s room" % role)
	var open_depth = distances(floor_data)
	var all_depth = distances(floor_data, true)
	for id in floor_data.rooms:
		var room = floor_data.rooms[id]
		if room.get("secret", false):
			if open_depth.has(id): problems.append("secret room %s is reachable without its concealed passage" % id)
			if not all_depth.has(id): problems.append("secret room %s is unreachable" % id)
		elif not open_depth.has(id):
			problems.append("room %s is unreachable without secrets" % id)
	var modern = floor_data.get("generator", VERSION) == VERSION and not floor_data.get("fallback", false)
	if modern and not floor_data.rooms.values().any(func(room): return room.cells.size() > 1):
		problems.append("floor has no larger room")
	return problems

## The original single-cell algorithm, kept verbatim for runs saved before
## generator v2 so their later floors are generated exactly as they would have been.
static func legacy_rooms(seed_value: int, floor_number: int) -> Dictionary:
	var gen = RandomNumberGenerator.new()
	gen.seed = seed_value + floor_number * 10007
	var rooms = {"0,0": {"type": "start", "cleared": true, "visited": true, "claimed": true}}
	var keys: Array = ["0,0"]
	var count = 11 + floor_number * 2
	while rooms.size() < count:
		var parent: String = keys[gen.randi_range(0, keys.size() - 1)]
		var directions = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
		var point = legacy_coord(parent) + directions[gen.randi_range(0, 3)]
		if absi(point.x) > 4 or absi(point.y) > 4:
			continue
		var key = key_of(point)
		if rooms.has(key):
			continue
		rooms[key] = {"type": "combat", "cleared": false, "visited": false, "claimed": false}
		keys.append(key)
	var depth = {"0,0": 0}
	var queue: Array = ["0,0"]
	while not queue.is_empty():
		var key: String = queue.pop_front()
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next = key_of(legacy_coord(key) + direction)
			if rooms.has(next) and not depth.has(next):
				depth[next] = depth[key] + 1
				queue.append(next)
	keys.sort_custom(func(a, b): return depth[a] > depth[b])
	rooms[keys[0]].type = "boss"
	rooms[keys[1]].type = "treasure"
	rooms[keys[2]].type = "shop"
	rooms[keys[3]].type = "rest"
	for key in keys:
		rooms[key]["depth"] = depth[key]
		rooms[key]["seed"] = seed_value + floor_number * 10007 + legacy_coord(key).x * 719 + legacy_coord(key).y * 1117
	return rooms

static func legacy_coord(key: String) -> Vector2i:
	var parts = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))

## Adapter for v1 floors: every saved room keeps its key, type, flags, offers,
## drops and seed; it gains a 1x1 footprint and the doorways v1 implied
## between every pair of neighbouring rooms. Nothing is regenerated.
static func from_legacy(old_rooms: Dictionary) -> Dictionary:
	var template = Content.record("rooms", "hearth_1x1")
	var floor_data = {"rooms": {}, "portals": {}, "owners": {}, "generator": LEGACY_VERSION}
	for key in old_rooms:
		var cell = legacy_coord(key)
		var room: Dictionary = old_rooms[key].duplicate(true)
		room.merge({"id": key, "template": "hearth_1x1", "revision": template.revision, "rotation": 0,
			"anchor": [cell.x, cell.y], "cells": [[cell.x, cell.y]], "portals": [],
			"lights": template.lights.map(func(anchor_value): return point_array(RoomGeometry.resolve_anchor(template.cells, 0, anchor_value))),
			"pedestal": [0.0, 0.0]}, true)
		room["depth"] = int(room.get("depth", 0))
		room["seed"] = int(room.get("seed", 0))
		floor_data.rooms[key] = room
		floor_data.owners[key] = key
	for key in old_rooms:
		for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
			if old_rooms.has(key_of(legacy_coord(key) + direction)):
				add_portal(floor_data, legacy_coord(key), direction)
	return floor_data
