extends Node
signal changed
signal item_gained(item: Dictionary)
const SAVE_VERSION := 2
## Floor generator revisions. A run keeps the generator it started with, so a
## migrated save never regenerates its floor or advances its gameplay RNG.
const GENERATOR_LEGACY := 1
const GENERATOR_V2 := 2
const ALL_RELICS_CODE := "ALLRELICS"
const PROFILE_PATH := "user://profile.json"
const SAVE_PATH := "user://run.json"
var rng = RandomNumberGenerator.new()
var seed_value = 0
var floor_number = 1
var rooms: Dictionary = {}
var current_room = "0,0"
var inventory: Array = []
var weapon_id = "candle"
var stats: Dictionary = {}
var hp = 6.0
var coins = 0
var kills = 0
var cleared = 0
var elapsed = 0.0
var active = false
var daily = false
var generator = GENERATOR_LEGACY
## Exploration resources and equipment (save v2).
var keys = 0
var bombs = 0
var wards = 0
var active_item: Dictionary = {}
var cooldowns: Dictionary = {}
var modifiers: Array = []
## Deterministic source IDs that already granted loot or kill credit.
var reward_ledger: Dictionary = {}
var pending_bombs: Array = []
## Guaranteed paintings already placed this run, so its floors offer different
## unseen works.
var assigned_paintings: Dictionary = {}
## Paint Sprayer pigment cycle position (gameplay state, saved).
var pigment_index := 0
var next_entity = 1000
## Floor graph: explicit portals for v2 floors (derived for legacy floors).
var portals: Dictionary = {}
var cell_owner: Dictionary = {}
var room_portal_ids: Dictionary = {}
## Where Continue places the player: the room and the portal used to enter it.
var checkpoint: Dictionary = {}
## Device preferences moved to Settings (user://settings.json); the profile
## holds only progress that would follow a player between devices.
const PROFILE_DEFAULTS = {"version": 2, "runs": 0, "wins": 0, "kills": 0, "best_floor": 0, "discovered": [],
	"paintings": [], "unlocks": []}
var profile: Dictionary = PROFILE_DEFAULTS.duplicate(true)

func _ready() -> void:
	load_profile()
	stats = Content.base_stats()

func load_profile() -> void:
	profile = PROFILE_DEFAULTS.duplicate(true)
	if FileAccess.file_exists(PROFILE_PATH):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
		if saved is Dictionary:
			for key in profile:
				if key == "version" or not saved.has(key):
					continue
				if profile[key] is int and saved[key] is float:
					profile[key] = int(saved[key])
				elif typeof(saved[key]) == typeof(profile[key]):
					profile[key] = saved[key]
	# Unknown painting IDs (from newer content) are kept; unlocks are reconciled
	# here as well as on discovery so none can be lost.
	Gallery.reconcile()

func start_run(chosen_weapon: String, seed_input := 0, is_daily := false) -> void:
	seed_value = seed_input if seed_input != 0 else int(Time.get_unix_time_from_system()) % 99999999
	rng.seed = seed_value
	floor_number = 1
	inventory = []
	# New and daily runs only start with an acquirable weapon.
	weapon_id = chosen_weapon if WeaponAvailability.is_available(chosen_weapon) else "candle"
	coins = 8
	kills = 0
	cleared = 0
	elapsed = 0.0
	daily = is_daily
	reset_run_extras()
	active = true
	profile.runs += 1
	rebuild_stats()
	hp = stats.max_hp
	generate_floor()
	save_profile()
	save_run()
	changed.emit()

func reset_run_extras() -> void:
	generator = GENERATOR_V2
	checkpoint = {}
	keys = 0
	# One bomb to start exploring; the boss route never needs it.
	bombs = 1
	wards = 0
	active_item = {}
	cooldowns = {}
	modifiers = []
	reward_ledger = {}
	pending_bombs = []
	next_entity = 1000
	assigned_paintings = {}
	pigment_index = 0

## Stable, persisted identifiers for drops, props and other durable records.
func new_entity_id() -> int:
	next_entity += 1
	return next_entity

func daily_seed() -> int:
	var date = Time.get_date_string_from_system(true).replace("-", "")
	return int(date)

func rebuild_stats() -> void:
	stats = Content.base_stats()
	for id in inventory:
		for key in Content.item_by_id[id].effects:
			stats[key] += float(Content.item_by_id[id].effects[key])
	# Temporary layers sit on top of relics: expiry rebuilds from the inventory,
	# so a relic picked up during a buff is never lost with it.
	for modifier in modifiers:
		for key in modifier.stats:
			stats[key] += float(modifier.stats[key])
	stats.max_hp = maxf(2.0, stats.max_hp)
	stats.damage = maxf(0.3, stats.damage)
	stats.rate = clampf(stats.rate, 0.35, 5.0)
	stats.speed = clampf(stats.speed, 0.55, 2.2)
	stats.size = clampf(stats.size, 0.5, 3.0)

func projectile_stats() -> Dictionary:
	var result: Dictionary = stats.duplicate()
	for key in Content.weapon_by_id[weapon_id].effects:
		result[key] += float(Content.weapon_by_id[weapon_id].effects[key])
	return result

func gain_item(id: String) -> void:
	var old_max: float = stats.max_hp
	inventory.append(id)
	rebuild_stats()
	if stats.max_hp > old_max:
		hp = minf(stats.max_hp, hp + stats.max_hp - old_max)
	hp = minf(hp, stats.max_hp)
	if id not in profile.discovered:
		profile.discovered.append(id)
	save_profile()
	save_run()
	item_gained.emit(Content.item_by_id[id])
	changed.emit()

func grant_all_relics() -> int:
	if not active:
		return 0
	var old_max: float = stats.max_hp
	var added = 0
	var discoveries_changed = false
	for item in Content.items:
		if item.id not in inventory:
			inventory.append(item.id)
			added += 1
		if item.id not in profile.discovered:
			profile.discovered.append(item.id)
			discoveries_changed = true
	if discoveries_changed:
		save_profile()
	if added > 0:
		rebuild_stats()
		hp = clampf(hp + maxf(0, stats.max_hp - old_max), 0, stats.max_hp)
		# Batch the grant: one rebuild and save, without sixty item popups.
		save_run()
		changed.emit()
	return added

func heal(amount: float) -> void:
	hp = minf(stats.max_hp, hp + amount)
	changed.emit()

func coord(key: String) -> Vector2i:
	var parts = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))

func room_key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]

## Rooms connected to `key` through a known, passable portal.
func neighbors(key: String, include_hidden := false) -> Array:
	var result: Array = []
	for pid in room_portal_ids.get(key, []):
		var portal: Dictionary = portals[pid]
		if not include_hidden and portal.get("state", "open") == "concealed":
			continue
		var other: String = portal.b if portal.a == key else portal.a
		if other not in result:
			result.append(other)
	return result

## Absolute map cells occupied by a room. Legacy rooms are a single cell.
func room_cells(key: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var room: Dictionary = rooms.get(key, {})
	if room.has("cells"):
		for c in room.cells:
			result.append(Vector2i(int(c[0]), int(c[1])))
	else:
		result.append(coord(key))
	return result

## Room-local cells (origin cell at 0,0) and doorway sockets for building a room.
func room_layout(key: String) -> Dictionary:
	var origin := coord(key)
	var cells: Array = []
	for c in room_cells(key):
		cells.append(c - origin)
	var sockets: Array = []
	for pid in room_portal_ids.get(key, []):
		var portal: Dictionary = portals[pid]
		var mine := _cell(portal.cell_a if portal.a == key else portal.cell_b)
		var other := _cell(portal.cell_b if portal.a == key else portal.cell_a)
		sockets.append({"portal": pid, "cell": mine - origin, "dir": other - mine,
			"other": portal.b if portal.a == key else portal.a, "state": portal.get("state", "open")})
	return {"cells": cells, "sockets": sockets}

static func _cell(value) -> Vector2i:
	return value if value is Vector2i else Vector2i(int(value[0]), int(value[1]))

static func rotate_cells(cells: Array, rotation: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for c in cells:
		var v := _cell(c)
		for i in posmod(rotation, 4):
			v = Vector2i(-v.y, v.x)
		result.append(v)
	return result

static func portal_id(a: Vector2i, b: Vector2i) -> String:
	var first := a if a.x < b.x or (a.x == b.x and a.y < b.y) else b
	var second := b if first == a else a
	return "%d,%d>%d,%d" % [first.x, first.y, second.x, second.y]

## Derived caches only: cell ownership and per-room portal lists. Legacy floors
## derive their doors from adjacency exactly as the old game did.
func rebuild_floor_index() -> void:
	cell_owner = {}
	room_portal_ids = {}
	for key in rooms:
		room_portal_ids[key] = []
		for c in room_cells(key):
			cell_owner[c] = key
	if generator == GENERATOR_LEGACY:
		portals = {}
		for key in rooms:
			for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
				var other := room_key(coord(key) + direction)
				if rooms.has(other):
					var a := coord(key)
					var b := coord(other)
					portals[portal_id(a, b)] = {"a": key, "b": other, "cell_a": [a.x, a.y], "cell_b": [b.x, b.y], "state": "open"}
	for pid in portals:
		var portal: Dictionary = portals[pid]
		if room_portal_ids.has(portal.a): room_portal_ids[portal.a].append(pid)
		if room_portal_ids.has(portal.b): room_portal_ids[portal.b].append(pid)
	for key in room_portal_ids:
		room_portal_ids[key].sort()

func generate_floor() -> void:
	if generator == GENERATOR_LEGACY:
		generate_floor_legacy()
	else:
		var built := false
		for attempt in 12:
			if _generate_v2(attempt, false):
				built = true
				break
		if not built:
			# Known-valid fallback: single-cell rooms always fit the bounds.
			_generate_v2(99, true)
	current_room = "0,0"
	checkpoint = {}
	profile.best_floor = maxi(profile.best_floor, floor_number)

func generate_floor_legacy() -> void:
	var gen = RandomNumberGenerator.new()
	gen.seed = seed_value + floor_number * 10007
	rooms = {"0,0": {"type": "start", "cleared": true, "visited": true, "claimed": true}}
	var keys: Array = ["0,0"]
	var count = 11 + floor_number * 2
	while rooms.size() < count:
		var parent: String = keys[gen.randi_range(0, keys.size() - 1)]
		var directions = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
		var point = coord(parent) + directions[gen.randi_range(0, 3)]
		if absi(point.x) > 4 or absi(point.y) > 4:
			continue
		var key = room_key(point)
		if rooms.has(key):
			continue
		rooms[key] = {"type": "combat", "cleared": false, "visited": false, "claimed": false}
		keys.append(key)
	rebuild_floor_index()
	var distances = {"0,0": 0}
	var queue: Array = ["0,0"]
	while not queue.is_empty():
		var key: String = queue.pop_front()
		for next in neighbors(key):
			if not distances.has(next):
				distances[next] = distances[key] + 1
				queue.append(next)
	keys.sort_custom(func(a, b): return distances[a] > distances[b])
	rooms[keys[0]].type = "boss"
	rooms[keys[1]].type = "treasure"
	rooms[keys[2]].type = "shop"
	rooms[keys[3]].type = "rest"
	for key in keys:
		rooms[key]["depth"] = distances[key]
		rooms[key]["seed"] = seed_value + floor_number * 10007 + coord(key).x * 719 + coord(key).y * 1117

func _pick_template(gen: RandomNumberGenerator, singles_only: bool, cells_left: int) -> Dictionary:
	var choices: Array = []
	var total := 0.0
	for template in Content.families.get("rooms", []):
		if "combat" not in template.roles or (singles_only and template.cells.size() > 1):
			continue
		if template.cells.size() - 1 > cells_left:
			continue
		choices.append(template)
		total += float(template.weight)
	var roll := gen.randf() * total
	for template in choices:
		roll -= float(template.weight)
		if roll <= 0:
			return template
	return choices.back()

## Generator v2: real multi-cell footprints joined by explicit portals.
## Bounded retries; the caller falls back to single cells if nothing fits.
func _generate_v2(attempt: int, singles_only: bool) -> bool:
	var gen = RandomNumberGenerator.new()
	gen.seed = seed_value + floor_number * 10007 + attempt * 7919
	var single: Dictionary = Content.get_def("rooms", "hall_single")
	rooms = {"0,0": {"type": "start", "cleared": true, "visited": true, "claimed": true,
		"template": single.id, "revision": int(single.revision), "rotation": 0, "cells": [[0, 0]]}}
	portals = {}
	var owner := {Vector2i.ZERO: "0,0"}
	var keys: Array = ["0,0"]
	var count = 11 + floor_number * 2
	var cell_budget = count + 6
	var used_cells := 1
	var tries := 0
	while keys.size() < count and tries < 4000:
		tries += 1
		var parent: String = keys[gen.randi_range(0, keys.size() - 1)]
		var parent_cells: Array = rooms[parent].cells
		var from := _cell(parent_cells[gen.randi_range(0, parent_cells.size() - 1)])
		var direction: Vector2i = RoomGeometry.DIRECTIONS[gen.randi_range(0, 3)]
		var target := from + direction
		if owner.has(target) or absi(target.x) > 4 or absi(target.y) > 4:
			continue
		var template := _pick_template(gen, singles_only, cell_budget - used_cells - (count - keys.size() - 1))
		var rotations: Array = template.rotations
		var rotation := int(rotations[gen.randi_range(0, rotations.size() - 1)])
		var shape := rotate_cells(template.cells, rotation)
		var anchor := target - shape[gen.randi_range(0, shape.size() - 1)]
		var placed: Array[Vector2i] = []
		var fits := true
		for c in shape:
			var cell := anchor + c
			if owner.has(cell) or absi(cell.x) > 4 or absi(cell.y) > 4:
				fits = false
				break
			placed.append(cell)
		if not fits:
			continue
		var key := room_key(anchor)
		var cell_list: Array = []
		for cell in placed:
			owner[cell] = key
			cell_list.append([cell.x, cell.y])
		rooms[key] = {"type": "combat", "cleared": false, "visited": false, "claimed": false,
			"template": template.id, "revision": int(template.revision), "rotation": rotation, "cells": cell_list}
		keys.append(key)
		used_cells += placed.size()
		portals[portal_id(from, target)] = {"a": parent, "b": key, "cell_a": [from.x, from.y], "cell_b": [target.x, target.y], "state": "open"}
	if keys.size() < count:
		return false
	# A few extra doors between touching rooms form loops; one per room pair.
	var linked := {}
	for pid in portals:
		linked[[portals[pid].a, portals[pid].b]] = true
		linked[[portals[pid].b, portals[pid].a]] = true
	var cells_sorted: Array = owner.keys()
	cells_sorted.sort()
	for cell in cells_sorted:
		for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
			var other_cell: Vector2i = cell + direction
			if not owner.has(other_cell) or owner[other_cell] == owner[cell]:
				continue
			var pair = [owner[cell], owner[other_cell]]
			if linked.has(pair) or gen.randf() > .22:
				continue
			linked[pair] = true
			linked[[pair[1], pair[0]]] = true
			portals[portal_id(cell, other_cell)] = {"a": pair[0], "b": pair[1], "cell_a": [cell.x, cell.y], "cell_b": [other_cell.x, other_cell.y], "state": "open"}
	rebuild_floor_index()
	var distances = {"0,0": 0}
	var queue: Array = ["0,0"]
	while not queue.is_empty():
		var key: String = queue.pop_front()
		for next in neighbors(key):
			if not distances.has(next):
				distances[next] = distances[key] + 1
				queue.append(next)
	if distances.size() != rooms.size():
		return false
	keys.sort_custom(func(a, b): return distances[a] > distances[b] or (distances[a] == distances[b] and a < b))
	for role in ["boss", "treasure", "shop", "rest"]:
		var assigned := false
		for key in keys:
			var room: Dictionary = rooms[key]
			if room.type == "combat" and role in Content.get_def("rooms", room.template).roles:
				room.type = role
				assigned = true
				break
		if not assigned:
			return false
	var large := 0
	for key in keys:
		rooms[key]["depth"] = distances[key]
		rooms[key]["seed"] = seed_value + floor_number * 10007 + coord(key).x * 719 + coord(key).y * 1117
		if rooms[key].cells.size() > 1: large += 1
	if not singles_only and large < 1:
		return false
	# Optional content after the mandatory graph validates: the secret, then
	# chests, then furniture around everything that must stay reachable.
	_place_secret(gen)
	_choose_gallery(gen)
	for key in rooms:
		_place_chests(key)
	for key in rooms:
		rooms[key]["props"] = Furnishing.plan(key, rooms[key], room_layout(key))
	_ensure_gallery_mount()
	assign_paintings()
	return true

## One guaranteed, accessible painting room per floor (never the secret, never
## the boss), chosen by the layout stream so it never depends on progress.
## Secret galleries add an optional second chance.
func _choose_gallery(gen: RandomNumberGenerator) -> void:
	var keys: Array = rooms.keys().filter(func(k): return rooms[k].type in ["combat", "treasure", "rest", "shop", "start"])
	keys.sort()
	if not keys.is_empty():
		rooms[keys[gen.randi_range(0, keys.size() - 1)]]["gallery"] = "guaranteed"
	for key in rooms:
		if rooms[key].type == "secret" and rooms[key].get("variant") == "gallery":
			rooms[key]["gallery"] = "optional"

## If the chosen room had no legal wall for a painting, move the guaranteed
## slot to the next eligible room so every floor keeps its opportunity.
func _ensure_gallery_mount() -> void:
	var guaranteed: Array = rooms.keys().filter(func(k): return rooms[k].get("gallery") == "guaranteed")
	if guaranteed.is_empty() or rooms[guaranteed[0]].has("mount"):
		return
	rooms[guaranteed[0]].erase("gallery")
	rooms[guaranteed[0]]["props"] = Furnishing.plan(guaranteed[0], rooms[guaranteed[0]], room_layout(guaranteed[0]))
	var keys: Array = rooms.keys().filter(func(k): return rooms[k].type in ["combat", "treasure", "rest", "shop", "start"] and k != guaranteed[0])
	keys.sort()
	for key in keys:
		rooms[key]["gallery"] = "guaranteed"
		rooms[key]["props"] = Furnishing.plan(key, rooms[key], room_layout(key))
		if rooms[key].has("mount"):
			return
		rooms[key].erase("gallery")
		rooms[key]["props"] = Furnishing.plan(key, rooms[key], room_layout(key))

## Resolve artworks into room state. Guaranteed slots pick first, from works
## this profile has not seen (and this run has not placed); optional secret
## slots never remove a work from later floors' pool. A separate stream keeps
## layout, enemies and loot independent of collection progress. Daily runs
## follow a fixed schedule instead of the profile.
func assign_paintings() -> void:
	var ids: Array = Content.get_def("collections", Gallery.COLLECTION).get("paintings", [])
	if ids.is_empty():
		return
	var art := RandomNumberGenerator.new()
	art.seed = hash("art:%d:%d" % [seed_value, floor_number])
	var slots: Array = rooms.keys().filter(func(k): return rooms[k].has("mount"))
	slots.sort_custom(func(a, b):
		var ga: bool = rooms[a].gallery == "guaranteed"
		var gb: bool = rooms[b].gallery == "guaranteed"
		return ga if ga != gb else a < b)
	# Works placed on the run's other floors; regenerating this floor replaces its own.
	var elsewhere: Array = []
	for other in assigned_paintings:
		if int(other) != floor_number: elsewhere.append(assigned_paintings[other])
	for i in slots.size():
		var room: Dictionary = rooms[slots[i]]
		var choice: String
		if daily:
			choice = ids[posmod(seed_value + floor_number * 5 + i * 7, ids.size())]
		else:
			var seen: Array = profile.get("paintings", [])
			var pool: Array = ids.filter(func(id): return id not in seen and id not in elsewhere)
			if pool.is_empty(): pool = ids.filter(func(id): return id not in seen)
			if pool.is_empty(): pool = ids
			choice = pool[art.randi_range(0, pool.size() - 1)]
			if room.gallery == "guaranteed": assigned_paintings[str(floor_number)] = choice
		room["painting"] = choice

## One optional secret room per floor: a single cell behind a concealed seam
## of a non-boss room. It is a leaf, so it is never on the required route.
func _place_secret(gen: RandomNumberGenerator) -> void:
	var candidates: Array = []
	var cells: Array = cell_owner.keys()
	cells.sort()
	for cell in cells:
		var parent: String = cell_owner[cell]
		if rooms[parent].type == "boss":
			continue
		for direction in RoomGeometry.DIRECTIONS:
			var target: Vector2i = cell + direction
			if cell_owner.has(target) or absi(target.x) > 4 or absi(target.y) > 4:
				continue
			candidates.append([cell, target, parent])
	if candidates.is_empty():
		return
	var pick: Array = candidates[gen.randi_range(0, candidates.size() - 1)]
	var cell: Vector2i = pick[1]
	var key := room_key(cell)
	var single: Dictionary = Content.get_def("rooms", "hall_single")
	rooms[key] = {"type": "secret", "variant": "cache" if gen.randf() < .5 else "gallery",
		"cleared": true, "visited": false, "claimed": false, "template": single.id,
		"revision": int(single.revision), "rotation": 0, "cells": [[cell.x, cell.y]],
		"depth": int(rooms[pick[2]].get("depth", 0)) + 1,
		"seed": seed_value + floor_number * 10007 + cell.x * 719 + cell.y * 1117}
	portals[portal_id(pick[0], cell)] = {"a": pick[2], "b": key, "cell_a": [pick[0].x, pick[0].y],
		"cell_b": [cell.x, cell.y], "state": "concealed"}
	rebuild_floor_index()

## Locked chests, rolled from each room's own seed so they never disturb the
## layout stream. They sit beside the north wall, clear of the door lane.
func _place_chests(key: String) -> void:
	var room: Dictionary = rooms[key]
	if room.type == "secret":
		# The cache sits across from the seam it was found through.
		var socket: Dictionary = room_layout(key).sockets[0]
		var away := -Vector2(socket.dir) * Vector2(4.5, 3.0)
		room["chests"] = [{"id": "%s:0" % key, "position": [away.x, away.y], "locked": false, "opened": false, "table": "secret_cache"}]
		return
	var chance: float = {"combat": .2, "treasure": .5}.get(room.type, 0.0)
	var gen := RandomNumberGenerator.new()
	gen.seed = int(room.seed) + 31337
	if gen.randf() >= chance:
		return
	var side := -1 if gen.randf() < .5 else 1
	room["chests"] = [{"id": "%s:0" % key, "position": [side * 5.5, -3.8], "locked": true, "opened": false, "table": "chest"}]

func mark_cleared() -> void:
	if rooms[current_room].cleared:
		return
	rooms[current_room].cleared = true
	cleared += 1
	if stats.room_heal > 0 and cleared % 3 == 0:
		heal(stats.room_heal)
	if stats.heal_each_room > 0:
		heal(stats.heal_each_room)
	save_run()
	changed.emit()

func next_floor() -> void:
	floor_number += 1
	heal(2)
	generate_floor()
	save_profile()
	save_run()
	changed.emit()

func finish(won: bool) -> void:
	active = false
	profile.kills += kills
	if won:
		profile.wins += 1
	save_profile()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	changed.emit()

func save_profile() -> void:
	_atomic_json(PROFILE_PATH, profile)

func snapshot() -> Dictionary:
	return {"version": SAVE_VERSION, "seed": seed_value, "floor": floor_number, "rooms": rooms,
		"current_room": current_room, "inventory": inventory, "weapon": weapon_id, "hp": hp,
		"coins": coins, "kills": kills, "cleared": cleared, "elapsed": elapsed, "daily": daily,
		"rng_state": str(rng.state), "generator": generator, "keys": keys, "bombs": bombs, "wards": wards,
		"active_item": active_item, "cooldowns": cooldowns, "modifiers": modifiers,
		"reward_ledger": reward_ledger, "pending_bombs": pending_bombs, "next_entity": next_entity,
		"assigned_paintings": assigned_paintings, "pigment_index": pigment_index,
		"portals": portals if generator != GENERATOR_LEGACY else {}, "checkpoint": checkpoint}

func save_run() -> void:
	if active:
		_atomic_json(SAVE_PATH, snapshot())

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func load_run() -> bool:
	if not has_save():
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not d is Dictionary:
		return false
	d = migrate_save(d)
	if d.is_empty():
		return false
	for key in ["seed", "floor", "rooms", "current_room", "inventory", "weapon", "hp", "coins", "kills", "cleared", "elapsed"]:
		if not d.has(key):
			return false
	if not Content.weapon_by_id.has(d.weapon) or not d.rooms.has(d.current_room):
		return false
	for id in d.inventory:
		if not Content.item_by_id.has(id):
			return false
	seed_value = int(d.seed)
	floor_number = int(d.floor)
	rooms = d.rooms
	current_room = d.current_room
	inventory = d.inventory
	weapon_id = d.weapon
	coins = int(d.coins)
	kills = int(d.kills)
	cleared = int(d.cleared)
	elapsed = float(d.elapsed)
	daily = d.get("daily", false)
	generator = int(d.generator)
	keys = int(d.keys)
	bombs = int(d.bombs)
	wards = int(d.wards)
	active_item = d.active_item
	cooldowns = d.cooldowns
	modifiers = d.modifiers
	reward_ledger = d.reward_ledger
	pending_bombs = d.pending_bombs
	next_entity = int(d.next_entity)
	assigned_paintings = d.get("assigned_paintings", {})
	pigment_index = int(d.get("pigment_index", 0))
	portals = d.get("portals", {})
	checkpoint = d.get("checkpoint", {})
	rebuild_floor_index()
	rng.seed = seed_value
	rng.state = int(d.get("rng_state", str(rng.state)))
	rebuild_stats()
	hp = clampf(float(d.hp), 0.5, stats.max_hp)
	active = true
	changed.emit()
	return true

## Upgrade an older run save one version at a time. Returns {} when the save
## cannot be understood. Migration never regenerates rooms or touches RNG state.
func migrate_save(d: Dictionary) -> Dictionary:
	d = d.duplicate(true)
	var version = int(d.get("version", -1))
	if version == 1:
		# Legacy 1×1 floors: keep the graph, rooms, offers, drops and RNG as saved.
		d.generator = GENERATOR_LEGACY
		d.keys = 0
		d.bombs = 0
		d.wards = 0
		d.active_item = {}
		d.cooldowns = {}
		d.modifiers = []
		d.reward_ledger = {}
		d.pending_bombs = []
		var highest = 1000
		for room in d.get("rooms", {}).values():
			for drop in room.get("pickups", []):
				highest = maxi(highest, int(drop.get("id", 0)))
		d.next_entity = highest
		d.portals = {}
		d.checkpoint = {}
		d.version = 2
		version = 2
	if version != SAVE_VERSION:
		return {}
	for key in ["generator", "keys", "bombs", "wards", "active_item", "cooldowns", "modifiers", "reward_ledger", "pending_bombs", "next_entity"]:
		if not d.has(key):
			return {}
	if not d.active_item is Dictionary or not d.cooldowns is Dictionary or not d.reward_ledger is Dictionary:
		return {}
	if not d.get("portals", {}) is Dictionary or not d.get("rooms") is Dictionary:
		return {}
	for portal in d.get("portals", {}).values():
		if not portal is Dictionary or not d.rooms.has(portal.get("a", "")) or not d.rooms.has(portal.get("b", "")):
			return {}
	return d

func _atomic_json(path: String, value: Dictionary) -> void:
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(value))
		file.close()
		DirAccess.rename_absolute(path + ".tmp", path)
