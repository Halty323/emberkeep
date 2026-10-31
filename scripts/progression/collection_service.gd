extends Node
## Permanent painting discoveries and the rewards they unlock. Progress lives
## in the profile, so it survives death and new runs. Rewards are reconciled
## on every profile load as well as on discovery, so a crash around the final
## notification cannot lose one. Collections are frozen: new artwork never
## enlarges an original requirement or relocks an earned reward.
signal discovered(painting_id: String, first_time: bool)
signal unlocked(weapon_id: String)
const FOUNDING := "world_classics_12_v1"

func _ready() -> void:
	reconcile()

func seen(painting_id: String) -> bool:
	return painting_id in Run.profile.paintings

## Records an inspection. Duplicates never add progress or repeat rewards.
func discover(painting_id: String) -> bool:
	if Content.record("paintings", painting_id).is_empty():
		return false
	var first_time = not seen(painting_id)
	if first_time:
		Run.profile.paintings.append(painting_id)
		Run.save_profile()
	discovered.emit(painting_id, first_time)
	reconcile()
	return first_time

func progress(collection_id := FOUNDING) -> Vector2i:
	var required: Array = Content.record("collections", collection_id).get("paintings", [])
	return Vector2i(required.filter(func(id): return seen(id)).size(), required.size())

## Grants every reward whose collection is complete; never removes one.
func reconcile() -> Array:
	var granted: Array = []
	for collection in Content.families.get("collections", []):
		var weapon: String = collection.get("unlocks", {}).get("weapon", "")
		if weapon == "" or weapon in Run.profile.unlocks:
			continue
		if collection.paintings.all(func(id): return seen(id)):
			Run.profile.unlocks.append(weapon)
			granted.append(weapon)
	if not granted.is_empty():
		Run.save_profile()
		for weapon in granted:
			unlocked.emit(weapon)
	return granted

## The single availability rule for starters, cycling, new and daily runs,
## shops, rewards and any future random weapon effect. Loading a saved run
## never consults it, so a known save keeps its equipped weapon.
func weapon_available(weapon_id: String) -> bool:
	if Forge.is_forged(weapon_id): return Forge.known(weapon_id)
	var weapon: Dictionary = Content.weapon_by_id.get(weapon_id, {})
	if weapon.is_empty():
		return false
	return not weapon.has("requires") or weapon_id in Run.profile.unlocks

func available_weapons() -> Array:
	return Content.weapons.filter(func(weapon): return weapon_available(weapon.id))

## What a run can start with: the weapons forged for its seed, then any
## catalog reward the profile has earned. The classic catalog weapons stay
## only for saves that already hold them.
func starters(seed_value: int) -> Array:
	var result: Array = Forge.starters(seed_value)
	for weapon in Content.weapons:
		if weapon.has("requires") and weapon_available(weapon.id): result.append(weapon)
	return result
