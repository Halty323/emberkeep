extends Node
signal changed
signal item_gained(item: Dictionary)
const SAVE_VERSION := 2
const ALL_RELICS_CODE := "ALLRELICS"
const PROFILE_PATH := "user://profile.json"
const SAVE_PATH := "user://run.json"
var rng = RandomNumberGenerator.new()
var seed_value = 0
var floor_number = 1
var rooms: Dictionary = {}
var portals: Dictionary = {}
var current_room = "0,0"
# Where the player last entered the current room, in room-local coordinates.
var entry = {"room": "0,0", "position": [0.0, 2.0]}
var generator_version = FloorGenerator.VERSION
var inventory: Array = []
var weapon_id = "candle"
var stats: Dictionary = {}
var hp = 6.0
var coins = 0
var keys = 0
var bombs = 0
# Persistent protective hits, unlike the relic guard that refreshes per room.
var wards = 0
# One equipped slot: {"instance": "a3", "def": "gale_bell"}, or empty.
var active_item: Dictionary = {}
# Remaining gameplay seconds per active definition. Unequipped entries keep
# ticking and duplicate instances share an entry, so swapping never resets.
var cooldowns: Dictionary = {}
# Timed layers over relic stats: {"source", "remaining", "effects", "flags"}.
var modifiers: Array = []
# Placed bombs are durable actions: debit, id, room, position and fuse.
var pending_bombs: Array = []
var instance_counter = 0
var processed_events: Array = []
# Paint Sprayer's red-blue-green position: gameplay state, saved with the run.
var pigment = 0
# Paintings this run has placed in guaranteed slots, so each floor offers a
# different unseen work.
var painting_slots: Array = []
const START_BOMBS := 1
const EVENT_MEMORY := 64
var kills = 0
var cleared = 0
var elapsed = 0.0
var active = false
var daily = false
# Device preferences live in the Settings service, never in the profile.
const PROFILE_VERSION := 2
var profile = {"version": PROFILE_VERSION, "runs": 0, "wins": 0, "kills": 0, "best_floor": 0, "discovered": [],
	"paintings": [], "unlocks": []}

func _ready() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
		if saved is Dictionary:
			for key in profile:
				if saved.has(key) and key != "version":
					profile[key] = saved[key]
	stats = Content.base_stats()

func start_run(chosen_weapon: String, seed_input := 0, is_daily := false) -> void:
	seed_value = seed_input if seed_input != 0 else int(Time.get_unix_time_from_system()) % 99999999
	rng.seed = seed_value
	floor_number = 1
	generator_version = FloorGenerator.VERSION
	inventory = []
	# Locked weapons can never start a run, whatever asked for them.
	weapon_id = chosen_weapon if Collection.weapon_available(chosen_weapon) else "candle"
	pigment = 0
	painting_slots = []
	coins = 8
	keys = 0
	bombs = START_BOMBS
	wards = 0
	active_item = {}
	cooldowns = {}
	modifiers = []
	pending_bombs = []
	instance_counter = 0
	processed_events = []
	kills = 0
	cleared = 0
	elapsed = 0.0
	daily = is_daily
	active = true
	profile.runs += 1
	rebuild_stats()
	hp = stats.max_hp
	generate_floor()
	assign_paintings()
	save_profile()
	save_run()
	changed.emit()

func daily_seed() -> int:
	var date = Time.get_date_string_from_system(true).replace("-", "")
	return int(date)

func rebuild_stats() -> void:
	stats = Content.base_stats()
	for id in inventory:
		for key in Content.item_by_id[id].effects:
			stats[key] += float(Content.item_by_id[id].effects[key])
	# Temporary modifiers layer on top of relics; when they expire, the stats
	# are rebuilt from the inventory, so relics gained meanwhile are kept.
	for modifier in modifiers:
		for key in modifier.get("effects", {}):
			stats[key] += float(modifier.effects[key])
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

## Adds a stable drop record to any room, on screen or not.
func add_drop(room_id: String, pickup_id: String, at: Vector2, value := -1.0) -> String:
	var room: Dictionary = rooms[room_id]
	if not room.has("pickups"): room.pickups = []
	var id = next_instance("d")
	room.pickups.append({"id": id, "def": pickup_id, "value": value if value > 0 else float(Content.record("pickups", pickup_id).value),
		"position": [snappedf(at.x, .001), snappedf(at.y, .001)]})
	return id

func next_instance(prefix: String) -> String:
	instance_counter += 1
	return "%s%d" % [prefix, instance_counter]

func cooldown_remaining(definition_id: String) -> float:
	return float(cooldowns.get(definition_id, 0.0))

func recharge(definition_id: String, seconds: float) -> void:
	cooldowns[definition_id] = maxf(0.0, cooldown_remaining(definition_id) - seconds)

func has_flag(flag: String) -> bool:
	return modifiers.any(func(modifier): return modifier.get("flags", {}).has(flag))

func flag_total(flag: String) -> int:
	var total = 0
	for modifier in modifiers:
		total += int(modifier.get("flags", {}).get(flag, 0))
	return total

## Refresh policy: re-applying a source restarts its timer; it never stacks.
func add_modifier(source: String, duration: float, effects := {}, flags := {}) -> void:
	modifiers = modifiers.filter(func(modifier): return modifier.source != source)
	modifiers.append({"source": source, "remaining": duration, "effects": effects, "flags": flags})
	rebuild_stats()
	hp = minf(hp, stats.max_hp)
	changed.emit()

## Advances every timer by unpaused gameplay time only; pause, menus,
## loading and time away from the app never reach this. Returns the pending
## bombs whose fuse has run out (the caller resolves and removes them).
func advance(delta: float) -> Array:
	for definition_id in cooldowns:
		cooldowns[definition_id] = maxf(0.0, float(cooldowns[definition_id]) - delta)
	var expired = false
	for modifier in modifiers:
		modifier.remaining = float(modifier.remaining) - delta
		expired = expired or modifier.remaining <= 0
	if expired:
		modifiers = modifiers.filter(func(modifier): return modifier.remaining > 0)
		rebuild_stats()
		hp = minf(hp, stats.max_hp)
		changed.emit()
	var due: Array = []
	for bomb in pending_bombs:
		bomb.fuse = float(bomb.fuse) - delta
		if bomb.fuse <= 0: due.append(bomb)
	return due

## Remembers handled command ids so a repeated delivery is never applied twice.
func remember_event(event_id: String) -> bool:
	if event_id.is_empty():
		return true
	if event_id in processed_events:
		return false
	processed_events.append(event_id)
	if processed_events.size() > EVENT_MEMORY:
		processed_events.pop_front()
	return true

func heal(amount: float) -> void:
	hp = minf(stats.max_hp, hp + amount)
	changed.emit()

func coord(key: String) -> Vector2i:
	return FloorGenerator.legacy_coord(key)

func room_key(p: Vector2i) -> String:
	return FloorGenerator.key_of(p)

## Rooms joined to this one by a doorway. Concealed passages are omitted, so
## hidden rooms never leak through neighbour lists, hints or the map.
func neighbors(key: String, include_concealed := false) -> Array:
	var result: Array = []
	for portal_id in rooms[key].get("portals", []):
		var portal: Dictionary = portals[portal_id]
		if portal.state == "concealed" and not include_concealed:
			continue
		var other: String = portal.b.room if portal.a.room == key else portal.a.room
		if other not in result:
			result.append(other)
	return result

## The portal endpoint on this room's side, in room-local cell coordinates.
func portal_side(portal_id: String, room_id: String) -> Dictionary:
	var portal: Dictionary = portals[portal_id]
	var side: Dictionary = portal.a if portal.a.room == room_id else portal.b
	return {"cell": FloorGenerator.vec(side.cell) - room_anchor(rooms[room_id]), "dir": FloorGenerator.vec(side.dir)}

func other_room(portal_id: String, room_id: String) -> String:
	var portal: Dictionary = portals[portal_id]
	return portal.b.room if portal.a.room == room_id else portal.a.room

func room_anchor(room: Dictionary) -> Vector2i:
	return FloorGenerator.vec(room.get("anchor", [0, 0]))

func local_cells(room: Dictionary) -> Array:
	var anchor = room_anchor(room)
	return room.get("cells", [[anchor.x, anchor.y]]).map(func(value): return FloorGenerator.vec(value) - anchor)

func generate_floor() -> void:
	var floor_data: Dictionary
	if generator_version == FloorGenerator.LEGACY_VERSION:
		# Runs saved before v2 keep the original generator for later floors.
		floor_data = FloorGenerator.from_legacy(FloorGenerator.legacy_rooms(seed_value, floor_number))
	else:
		floor_data = FloorGenerator.generate(seed_value, floor_number)
	rooms = floor_data.rooms
	portals = floor_data.portals
	current_room = FloorGenerator.START_ID
	entry = {"room": current_room, "position": [0.0, 2.0]}
	profile.best_floor = maxi(profile.best_floor, floor_number)

## Fills this floor's painting mounts from a dedicated stream that depends on
## collection progress, never the other way round: topology, encounters and
## loot ignore it. The guaranteed slot (the rest room) takes an unseen work
## not already placed this run, so a player inspecting every guaranteed
## painting completes twelve within four runs. Optional galleries add chances
## without removing anything from later floors' pool. Daily runs use a fixed
## seed-based schedule instead of each profile's progress.
func assign_paintings() -> void:
	var required: Array = Content.record("collections", Collection.FOUNDING).get("paintings", [])
	if required.is_empty():
		return
	var stream = RandomNumberGenerator.new()
	stream.seed = Content.stable_hash("paintings:%d:%d" % [seed_value, floor_number])
	var ids: Array = rooms.keys()
	ids.sort()
	var guaranteed = ids.filter(func(id): return rooms[id].type == "rest" and not rooms[id].get("mounts", []).is_empty())
	if not guaranteed.is_empty():
		var mount: Dictionary = rooms[guaranteed[0]].mounts[0]
		if mount.painting == "":
			var pick: String
			if daily:
				pick = required[posmod(seed_value + floor_number * 5, required.size())]
			else:
				var pool = required.filter(func(id): return not Collection.seen(id) and id not in painting_slots)
				if pool.is_empty(): pool = required.filter(func(id): return id not in painting_slots)
				if pool.is_empty(): pool = required
				pick = pool[stream.randi_range(0, pool.size() - 1)]
			mount.painting = pick
			painting_slots.append(pick)
	for id in ids:
		var room: Dictionary = rooms[id]
		var placed: Array = room.get("mounts", []).map(func(m): return m.painting).filter(func(p): return p != "")
		for mount in room.get("mounts", []):
			if mount.painting != "": continue
			var pool = required.filter(func(p): return p not in placed and (daily or not Collection.seen(p)))
			if pool.is_empty(): pool = required.filter(func(p): return p not in placed)
			if pool.is_empty(): break
			mount.painting = pool[stream.randi_range(0, pool.size() - 1)]
			placed.append(mount.painting)

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
	assign_paintings()
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
	return {"version": SAVE_VERSION, "generator": generator_version, "content_revision": Content.revision,
		"seed": seed_value, "floor": floor_number, "rooms": rooms, "portals": portals,
		"current_room": current_room, "entry": entry, "inventory": inventory, "weapon": weapon_id, "hp": hp,
		"coins": coins, "keys": keys, "bombs": bombs, "wards": wards, "active": active_item, "cooldowns": cooldowns,
		"modifiers": modifiers, "pending_bombs": pending_bombs, "instance_counter": instance_counter,
		"events": processed_events, "pigment": pigment, "painting_slots": painting_slots, "kills": kills, "cleared": cleared, "elapsed": elapsed, "daily": daily,
		"rng_state": str(rng.state)}

## Drop records name a pickup definition. Version 1 records used a bare kind;
## those are resolved explicitly, and an unknown kind is dropped with a
## warning instead of silently becoming some other pickup.
static func normalize_drops(saved_rooms: Dictionary) -> void:
	for room in saved_rooms.values():
		var kept: Array = []
		for drop in room.get("pickups", []):
			if drop.id is float or drop.id is int:
				drop.id = "%d" % int(drop.id)
			if not drop.has("def"):
				drop["def"] = Content.LEGACY_PICKUPS.get(drop.get("kind", ""), "")
				drop.erase("kind")
			if Content.record("pickups", drop.def).is_empty():
				push_warning("Removed a saved drop with unknown pickup '%s'." % drop.def)
				continue
			kept.append(drop)
		if room.has("pickups"):
			room.pickups = kept

## v1 saves predate multi-cell rooms. Their graph, room types, offers, drops,
## health, inventory, weapon and RNG state are carried over untouched; only
## footprints and the doorways v1 implied are added. Nothing is regenerated.
static func migrate_v1(d: Dictionary) -> Dictionary:
	var migrated: Dictionary = d.duplicate(true)
	var floor_data = FloorGenerator.from_legacy(d.rooms)
	migrated.rooms = floor_data.rooms
	migrated.portals = floor_data.portals
	migrated.generator = FloorGenerator.LEGACY_VERSION
	migrated.entry = {"room": d.current_room, "position": [0.0, 2.0]}
	migrated.version = SAVE_VERSION
	return migrated

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
	if int(d.get("version", -1)) == 1 and d.get("rooms") is Dictionary and d.has("current_room"):
		d = migrate_v1(d)
	if int(d.get("version", -1)) != SAVE_VERSION:
		return false
	for key in ["seed", "floor", "rooms", "portals", "current_room", "entry", "inventory", "weapon", "hp", "coins", "kills", "cleared", "elapsed"]:
		if not d.has(key):
			return false
	if not Content.weapon_by_id.has(d.weapon) or not d.rooms.has(d.current_room):
		return false
	for portal in d.portals.values():
		if not d.rooms.has(portal.a.room) or not d.rooms.has(portal.b.room):
			return false
	for id in d.inventory:
		if not Content.item_by_id.has(id):
			return false
	seed_value = int(d.seed)
	floor_number = int(d.floor)
	normalize_drops(d.rooms)
	if not d.get("active", {}).is_empty() and Content.record("actives", d.active.get("def", "")).is_empty():
		push_warning("The saved active item is no longer known; it was set aside.")
		d.active = {}
	rooms = d.rooms
	portals = d.portals
	current_room = d.current_room
	entry = d.entry
	generator_version = int(d.get("generator", FloorGenerator.VERSION))
	inventory = d.inventory
	weapon_id = d.weapon
	coins = int(d.coins)
	keys = int(d.get("keys", 0))
	bombs = int(d.get("bombs", START_BOMBS))
	wards = int(d.get("wards", 0))
	active_item = d.get("active", {})
	cooldowns = d.get("cooldowns", {})
	modifiers = d.get("modifiers", [])
	pending_bombs = d.get("pending_bombs", [])
	instance_counter = int(d.get("instance_counter", 0))
	processed_events = d.get("events", [])
	pigment = int(d.get("pigment", 0))
	painting_slots = d.get("painting_slots", [])
	kills = int(d.kills)
	cleared = int(d.cleared)
	elapsed = float(d.elapsed)
	daily = d.get("daily", false)
	rng.seed = seed_value
	rng.state = int(d.get("rng_state", str(rng.state)))
	rebuild_stats()
	hp = clampf(float(d.hp), 0.5, stats.max_hp)
	# Floors saved before galleries existed gain their paintings once.
	assign_paintings()
	active = true
	changed.emit()
	return true

func _atomic_json(path: String, value: Dictionary) -> void:
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(value))
		file.close()
		DirAccess.rename_absolute(path + ".tmp", path)
