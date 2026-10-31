class_name PickupRules
extends RefCounted
## Effects of each registered pickup kind. A pickup that cannot help stays on
## the ground: hearts at full health, wards and supplies at their caps, and
## batteries while no equipped active item is recharging.
const KINDS := ["coin", "heal", "ward", "key", "bomb", "battery", "battery_full"]

static func can_collect(definition: Dictionary) -> bool:
	var cap := int(definition.get("cap", 99))
	match definition.kind:
		"coin": return true
		"heal": return Run.hp < Run.stats.max_hp
		"ward": return Run.wards < cap
		"key": return Run.keys < cap
		"bomb": return Run.bombs < cap
		"battery", "battery_full":
			return not Run.active_item.is_empty() and Run.cooldown_remaining(Run.active_item.def) > 0
	return false

static func apply(definition: Dictionary, value: float) -> void:
	var cap := int(definition.get("cap", 99))
	match definition.kind:
		"coin": Run.coins += int(value)
		"heal": Run.heal(value)
		"ward": Run.wards = mini(cap, Run.wards + int(value))
		"key": Run.keys = mini(cap, Run.keys + int(value))
		"bomb": Run.bombs = mini(cap, Run.bombs + int(value))
		"battery": Run.recharge(Run.active_item.def, value)
		"battery_full": Run.recharge(Run.active_item.def, INF)
