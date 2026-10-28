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
const FAMILIES = ["rooms", "furniture", "layouts", "pickups", "actives", "effects", "drop_tables", "paintings", "collections"]
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
	if not by_family.get("rooms", {}).has("hall_single"):
		problems.append("rooms: the single-cell template hall_single is required")
	return problems

const PICKUP_EFFECTS = ["coins", "heal", "ward", "keys", "bombs", "recharge", "recharge_full"]
const PICKUP_VISUALS = ["coin", "heart", "ward", "key", "bomb", "battery"]
## Active handlers implemented by ItemSystem. A definition naming anything
## else is rejected rather than silently doing nothing.
const ACTIVE_HANDLERS = ["heal", "ember_burst"]

static func _number(value) -> bool:
	return value is float or value is int

func _validate_pickups(problems: Array[String], pickup: Dictionary) -> void:
	if pickup.get("effect") not in PICKUP_EFFECTS:
		problems.append("pickup %s has unknown effect %s" % [pickup.get("id"), str(pickup.get("effect"))])
	if not _number(pickup.get("amount")) or float(pickup.amount) < 0:
		problems.append("pickup %s needs a non-negative amount" % pickup.get("id"))
	if pickup.get("visual") not in PICKUP_VISUALS:
		problems.append("pickup %s has unknown visual" % pickup.get("id"))
	if pickup.has("cap") and (not _number(pickup.cap) or float(pickup.cap) < 1):
		problems.append("pickup %s has an impossible cap" % pickup.get("id"))

func _validate_drop_tables(problems: Array[String], table: Dictionary) -> void:
	if not _number(table.get("rolls")) or int(table.rolls) < 1:
		problems.append("drop table %s needs at least one roll" % table.get("id"))
	var entries = table.get("entries")
	if not entries is Array or entries.is_empty():
		problems.append("drop table %s has no entries" % table.get("id"))
		return
	for entry in entries:
		if not entry is Dictionary or not _number(entry.get("weight")) or float(entry.weight) <= 0:
			problems.append("drop table %s has an entry without a positive weight" % table.get("id"))
		elif entry.get("pickup", "") != "" and not by_family.get("pickups", {}).has(entry.pickup):
			problems.append("drop table %s references missing pickup %s" % [table.get("id"), str(entry.pickup)])

func _validate_actives(problems: Array[String], active: Dictionary) -> void:
	if active.get("handler") not in ACTIVE_HANDLERS:
		problems.append("active %s uses unknown handler %s" % [active.get("id"), str(active.get("handler"))])
	if not _number(active.get("cooldown")) or float(active.cooldown) <= 0:
		problems.append("active %s needs a positive cooldown" % active.get("id"))
	if not active.get("params") is Dictionary or not active.get("name") is String:
		problems.append("active %s needs a name and params" % active.get("id"))

const PROP_PLACEMENTS = ["wall", "corner", "center", "scatter", "flank"]

func _validate_furniture(problems: Array[String], prop: Dictionary) -> void:
	var size = prop.get("size")
	if not size is Array or size.size() != 2 or not _number(size[0]) or not _number(size[1]) or float(size[0]) <= 0 or float(size[1]) <= 0:
		problems.append("furniture %s needs a positive size" % prop.get("id"))
	if not _number(prop.get("height")) or float(prop.height) <= 0:
		problems.append("furniture %s needs a positive height" % prop.get("id"))
	if not prop.get("blocks") is bool or not prop.get("recipe") is String:
		problems.append("furniture %s needs blocks and a recipe" % prop.get("id"))
	if prop.get("placement") not in PROP_PLACEMENTS:
		problems.append("furniture %s has unknown placement" % prop.get("id"))
	if prop.has("breakable"):
		var breakable = prop.breakable
		if not breakable is Dictionary or not _number(breakable.get("hp")) or float(breakable.hp) <= 0:
			problems.append("furniture %s needs positive break health" % prop.get("id"))
		elif not by_family.get("drop_tables", {}).has(breakable.get("table", "")):
			problems.append("furniture %s references missing drop table" % prop.get("id"))
		if not prop.get("blocks", false):
			problems.append("furniture %s is breakable but has no collision" % prop.get("id"))

func _validate_layouts(problems: Array[String], layout: Dictionary) -> void:
	var roles = layout.get("roles")
	if not roles is Array or roles.is_empty() or roles.any(func(r): return r not in ROOM_ROLES):
		problems.append("layout %s has unknown roles" % layout.get("id"))
	if not _number(layout.get("weight")) or float(layout.weight) <= 0:
		problems.append("layout %s needs a positive weight" % layout.get("id"))
	for kind in PROP_PLACEMENTS:
		var names = layout.get(kind, [])
		if not names is Array:
			problems.append("layout %s %s must be a list" % [layout.get("id"), kind])
			continue
		for name in names:
			if not by_family.get("furniture", {}).has(name) and not Furnishing.GROUPS.has(name):
				problems.append("layout %s references missing furniture %s" % [layout.get("id"), str(name)])

func _validate_paintings(problems: Array[String], painting: Dictionary) -> void:
	for key in ["title", "artist", "date", "institution", "caption", "image", "kind"]:
		if not painting.get(key) is String or painting[key] == "":
			problems.append("painting %s needs %s" % [painting.get("id"), key])
	if not _number(painting.get("aspect")) or float(painting.aspect) <= 0:
		problems.append("painting %s needs a positive aspect" % painting.get("id"))
	var source = painting.get("source")
	if not source is Dictionary or source.get("kind") not in ["commons", "artic"]:
		problems.append("painting %s needs a documented source" % painting.get("id"))
	var provenance = painting.get("provenance", {})
	if provenance is Dictionary and not provenance.is_empty():
		for key in ["source_page", "image_url", "sha256", "retrieved", "rights"]:
			if not provenance.has(key):
				problems.append("painting %s provenance lacks %s" % [painting.get("id"), key])

func _validate_collections(problems: Array[String], collection: Dictionary) -> void:
	var ids = collection.get("paintings")
	if not ids is Array or ids.is_empty():
		problems.append("collection %s has no paintings" % collection.get("id"))
		return
	var seen := {}
	for id in ids:
		if not by_family.get("paintings", {}).has(id):
			problems.append("collection %s references missing painting %s" % [collection.get("id"), str(id)])
		if seen.has(id):
			problems.append("collection %s repeats %s" % [collection.get("id"), str(id)])
		seen[id] = true
	var weapon = collection.get("unlocks", {}).get("weapon", "")
	if weapon != "" and not weapon_by_id.has(weapon):
		problems.append("collection %s unlocks missing weapon %s" % [collection.get("id"), str(weapon)])

const ROOM_ROLES = ["start", "combat", "treasure", "shop", "rest", "boss", "secret"]

func _validate_rooms(problems: Array[String], room: Dictionary) -> void:
	var cells = room.get("cells")
	var set := {}
	if not cells is Array or cells.is_empty() or cells.size() > 4:
		problems.append("room %s needs one to four footprint cells" % room.get("id"))
		return
	for c in cells:
		if not c is Array or c.size() != 2 or not (c[0] is float or c[0] is int) or not (c[1] is float or c[1] is int):
			problems.append("room %s has an invalid cell" % room.get("id"))
			return
		var cell := Vector2i(int(c[0]), int(c[1]))
		if set.has(cell):
			problems.append("room %s repeats a footprint cell" % room.get("id"))
		set[cell] = true
	if not set.has(Vector2i.ZERO):
		problems.append("room %s footprint must include its origin cell" % room.get("id"))
	# Footprint cells must form one 4-connected shape.
	var seen := {Vector2i.ZERO: true}
	var queue: Array = [Vector2i.ZERO]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if set.has(at + d) and not seen.has(at + d):
				seen[at + d] = true
				queue.append(at + d)
	if seen.size() != set.size():
		problems.append("room %s footprint is not connected" % room.get("id"))
	var rotations = room.get("rotations")
	if not rotations is Array or rotations.is_empty() or rotations.any(func(r): return not (r is float or r is int) or int(r) < 0 or int(r) > 3):
		problems.append("room %s has invalid rotations" % room.get("id"))
	var roles = room.get("roles")
	if not roles is Array or roles.is_empty() or roles.any(func(r): return r not in ROOM_ROLES):
		problems.append("room %s has unknown roles" % room.get("id"))
	if not (room.get("weight") is float or room.get("weight") is int) or float(room.weight) <= 0:
		problems.append("room %s needs a positive weight" % room.get("id"))
	if not (room.get("revision") is float or room.get("revision") is int):
		problems.append("room %s needs a revision" % room.get("id"))

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
