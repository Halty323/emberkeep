extends Node
signal changed
signal item_gained(item: Dictionary)
const SAVE_VERSION := 1
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
# Device preferences live in the Settings service, never in the profile.
const PROFILE_VERSION := 2
var profile = {"version": PROFILE_VERSION, "runs": 0, "wins": 0, "kills": 0, "best_floor": 0, "discovered": []}

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
	inventory = []
	weapon_id = chosen_weapon
	coins = 8
	kills = 0
	cleared = 0
	elapsed = 0.0
	daily = is_daily
	active = true
	profile.runs += 1
	rebuild_stats()
	hp = stats.max_hp
	generate_floor()
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

func neighbors(key: String) -> Array:
	var result: Array = []
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var next = room_key(coord(key) + direction)
		if rooms.has(next):
			result.append(next)
	return result

func generate_floor() -> void:
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
	current_room = "0,0"
	profile.best_floor = maxi(profile.best_floor, floor_number)

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
		"rng_state": str(rng.state)}

func save_run() -> void:
	if active:
		_atomic_json(SAVE_PATH, snapshot())

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func load_run() -> bool:
	if not has_save():
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not d is Dictionary or int(d.get("version", -1)) != SAVE_VERSION:
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
	rng.seed = seed_value
	rng.state = int(d.get("rng_state", str(rng.state)))
	rebuild_stats()
	hp = clampf(float(d.hp), 0.5, stats.max_hp)
	active = true
	changed.emit()
	return true

func _atomic_json(path: String, value: Dictionary) -> void:
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(value))
		file.close()
		DirAccess.rename_absolute(path + ".tmp", path)
