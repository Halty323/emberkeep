class_name ExpeditionBalance
extends RefCounted
## Versioned expedition rules. Existing generator-1/2 runs keep their old
## economy and combat cadence; new expeditions earn fewer, distinct rewards.
const VERSION := 3
const START_COINS := 4
const COMBAT_RELICS_PER_FLOOR := 1
const CHEST_TABLES := ["locked_chest", "secret_cache", "normal_chest", "locked_chest_hard", "secret_cache_hard"]
const HARD_TABLES := {
	"enemy_common": "enemy_common_hard", "boss": "boss_hard", "room_clear": "room_clear_hard",
	"breakable_small": "breakable_small_hard", "locked_chest": "locked_chest_hard", "secret_cache": "secret_cache_hard"
}

static func active_new_run(version := -1) -> bool:
	return (Run.generator_version if version < 0 else version) >= VERSION

static func table_id(id: String, version := -1) -> String:
	return str(HARD_TABLES.get(id,id)) if active_new_run(version) else id

static func allows_active(table: String, source: String) -> bool:
	return source == "chest" and table in CHEST_TABLES

static func foe_health(depth: int, boss: bool) -> float:
	return 1.0 + (.025 if boss else .04) + clampi(depth-1,0,4)*(.0125 if boss else .02)

static func foe_speed(depth: int) -> float:
	return 1.07 + clampi(depth-1,0,4)*.015

static func foe_tempo(depth: int) -> float:
	return 1.10 + clampi(depth-1,0,4)*.03

static func encounter_count(previous: int, depth: int) -> int:
	return clampi(previous + (1 if depth <= 2 else 2),4,16)

static func combat_relic_due(room: Dictionary, rooms: Dictionary) -> bool:
	if room.get("type", "") == "boss": return true
	if room.get("type", "") != "combat" or room.get("vertical_challenge", false): return false
	var awarded := 0
	for other in rooms.values():
		if other.get("clear_reward", "") == "relic": awarded += 1
	return awarded < COMBAT_RELICS_PER_FLOOR

## Older saves may contain an unclaimed active offer. Keep carried/swapped
## actives, but convert unopened pedestal/shop offers into passive relics.
## This private stream never shifts encounters or future drops.
static func sanitize_offers(offers: Array, room_seed: int) -> Array:
	if not offers.any(func(offer): return offer.get("kind", "") == "active"): return offers
	var result := offers.duplicate(true)
	var gen := RandomNumberGenerator.new()
	gen.seed = Content.stable_hash("passive-offers:%d" % room_seed)
	var excluded: Array = Run.inventory.duplicate()
	for offer in result:
		if offer.get("kind", "") == "item": excluded.append(offer.id)
	for offer in result:
		if offer.get("kind", "") != "active": continue
		var pool: Array = Content.roll_items(gen,1,excluded,false,Run.stats.get("luck",0.0))
		if pool.is_empty(): continue
		offer.kind = "item"
		offer.id = pool[0].id
		excluded.append(offer.id)
	return result
