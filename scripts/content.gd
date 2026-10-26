extends Node
var items: Array = []
var weapons: Array = []
var item_by_id: Dictionary = {}
var weapon_by_id: Dictionary = {}
const RARITY_COLORS = {"common": Color("c6d3bf"), "uncommon": Color("96d9ba"), "rare": Color("b9b2e9"), "mythic": Color("f1c579")}

func _ready() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data.json"))
	items = data.items
	weapons = data.weapons
	for item in items:
		item_by_id[item.id] = item
	for weapon in weapons:
		weapon_by_id[weapon.id] = weapon

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
