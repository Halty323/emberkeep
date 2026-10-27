extends Node
## Immutable definitions with stable IDs. Relics and weapons are authored in
## tools/make_content.py (assets/data.json); newer families live in canonical
## res://content/<family>.json files. Nothing here holds per-run quantities.
var items: Array = []
var weapons: Array = []
var item_by_id: Dictionary = {}
var weapon_by_id: Dictionary = {}
## family name -> Array of definitions, and family name -> id -> definition.
var families: Dictionary = {}
var by_family: Dictionary = {}
var errors: Array[String] = []
const RARITY_COLORS = {"common": Color("c6d3bf"), "uncommon": Color("96d9ba"), "rare": Color("b9b2e9"), "mythic": Color("f1c579")}
const FAMILIES = ["rooms", "furniture", "pickups", "actives", "effects", "drop_tables", "paintings", "collections"]
const ID_PATTERN = "^[a-z0-9_]+$"

func _ready() -> void:
	load_catalog()
	if not errors.is_empty():
		for message in errors:
			push_error("Content: " + message)

func load_catalog(data_path := "res://assets/data.json", content_dir := "res://content") -> void:
	items = []
	weapons = []
	item_by_id = {}
	weapon_by_id = {}
	families = {}
	by_family = {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if data is Dictionary:
		items = data.get("items", [])
		weapons = data.get("weapons", [])
	for item in items:
		item_by_id[item.id] = item
	for weapon in weapons:
		weapon_by_id[weapon.id] = weapon
	for family in FAMILIES:
		var path = "%s/%s.json" % [content_dir, family]
		var records: Array = []
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary and parsed.get(family) is Array:
				records = parsed[family]
			else:
				records = [{"__invalid_file": path}]
		families[family] = records
		by_family[family] = {}
		for record in records:
			if record is Dictionary and record.get("id") is String:
				by_family[family][record.id] = record
	errors = validate()

func get_def(family: String, id: String) -> Dictionary:
	return by_family.get(family, {}).get(id, {})

func has_def(family: String, id: String) -> bool:
	return by_family.get(family, {}).has(id)

## Reference and schema validation. Returns human-readable problems; an empty
## array means every definition can be used safely at runtime.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var id_regex = RegEx.create_from_string(ID_PATTERN)
	var stats := base_stats()
	var seen := {}
	for item in items:
		_check_id(problems, id_regex, seen, "relic", item)
		if not RARITY_COLORS.has(item.get("rarity", "")):
			problems.append("relic %s has unknown rarity" % item.get("id"))
		for key in item.get("effects", {}):
			if not stats.has(key):
				problems.append("relic %s uses unknown effect %s" % [item.get("id"), key])
	seen = {}
	for weapon in weapons:
		_check_id(problems, id_regex, seen, "weapon", weapon)
		for key in ["damage", "cooldown", "speed", "count", "spread"]:
			if not (weapon.get(key) is float or weapon.get(key) is int) or float(weapon[key]) < 0:
				problems.append("weapon %s has invalid %s" % [weapon.get("id"), key])
		for key in weapon.get("effects", {}):
			if not stats.has(key):
				problems.append("weapon %s uses unknown effect %s" % [weapon.get("id"), key])
	for family in families:
		seen = {}
		for record in families[family]:
			if not record is Dictionary or record.has("__invalid_file"):
				problems.append("%s: file must contain an object with a \"%s\" array" % [family, family])
				continue
			_check_id(problems, id_regex, seen, family, record)
			var validator: String = "_validate_" + family
			if has_method(validator):
				call(validator, problems, record)
	return problems

func _check_id(problems: Array[String], id_regex: RegEx, seen: Dictionary, label: String, record: Dictionary) -> void:
	var id = record.get("id")
	if not id is String or id_regex.search(id) == null:
		problems.append("%s has missing or malformed id: %s" % [label, str(id)])
	elif seen.has(id):
		problems.append("duplicate %s id: %s" % [label, id])
	else:
		seen[id] = true

func roll_items(rng: RandomNumberGenerator, count: int, owned: Array = [], premium := false, luck_value := 0.0) -> Array:
	var result: Array = []
	var pool: Array = items.duplicate()
	for unused in count:
		var weights: Array[float] = []
		var total = 0.0
		for item in pool:
			var weight: float = {"common": 6.0, "uncommon": 3.5, "rare": 1.2, "mythic": 0.25}[item.rarity]
			if premium and item.rarity in ["rare", "mythic"]:
				weight *= 4.0
			if item.rarity in ["rare", "mythic"]:
				weight *= 1.0 + maxf(0, luck_value) * .3
			if item.id in owned:
				weight *= 0.25
			total += weight
			weights.append(total)
		var roll = rng.randf() * total
		for i in pool.size():
			if roll <= weights[i]:
				result.append(pool.pop_at(i))
				break
	return result

func base_stats() -> Dictionary:
	return {"damage": 1.0, "rate": 1.0, "speed": 1.0, "max_hp": 6.0,
		"shot_speed": 1.0, "range": 1.0, "shots": 0.0, "pierce": 0.0,
		"bounce": 0.0, "homing": 0.0, "burn": 0.0, "chill": 0.0,
		"poison": 0.0, "chain": 0.0, "explosion": 0.0, "split": 0.0,
		"size": 1.0, "crit": 0.05, "crit_damage": 2.0, "lifesteal": 0.0,
		"shield": 0.0, "orbitals": 0.0, "luck": 0.0, "magnet": 1.6,
		"dash_cd": 0.0, "dash_damage": 0.0, "dash_nova": 0.0,
		"thorns": 0.0, "coin_bonus": 0.0, "room_heal": 0.0,
		"kill_haste": 0.0, "low_hp": 0.0, "execute": 0.0,
		"knockback": 1.0, "backshot": 0.0, "side_shot": 0.0,
		"returning": 0.0, "wave": 0.0, "radial": 0.0, "heal_each_room": 0.0}
