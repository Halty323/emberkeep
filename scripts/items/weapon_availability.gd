class_name WeaponAvailability
extends RefCounted
## The single gate for which weapons may be acquired: starters, starter
## cycling, new and daily runs, shops, rewards and any future random weapon
## effect all ask here. A weapon already in a saved run stays loadable.

## The collection whose completion unlocks this weapon, or "".
static func locked_by(id: String) -> String:
	for collection in Content.families.get("collections", []):
		if collection.get("unlocks", {}).get("weapon", "") == id:
			return collection.id
	return ""

static func is_available(id: String) -> bool:
	if not Content.weapon_by_id.has(id):
		return false
	return locked_by(id) == "" or id in Run.profile.get("unlocks", [])

static func available() -> Array:
	return Content.weapons.filter(func(w): return is_available(w.id))
