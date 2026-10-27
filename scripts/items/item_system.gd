class_name ItemSystem
extends RefCounted
## Pickup effects, drop tables, the single active slot with its cooldown
## ledger, and durable bombs. Handlers validate and apply gameplay once; the
## HUD, audio and particles only react to the results.
const BOMB_FUSE := 2.2
const BOMB_RADIUS := 2.6
const BOMB_DAMAGE := 30.0
## Drops written by older saves used these kinds.
const LEGACY_PICKUPS := {"coin": "copper_coin", "heart": "half_heart"}
var game: Node3D

func _init(owner_game: Node3D) -> void:
	game = owner_game

# --- Pickups ---------------------------------------------------------------

static func pickup_def(kind: String) -> Dictionary:
	return Content.get_def("pickups", LEGACY_PICKUPS.get(kind, kind))

## A pickup that would do nothing stays on the ground.
func pickup_useful(kind: String) -> bool:
	var def := pickup_def(kind)
	match def.get("effect", ""):
		"coins": return true
		"heal": return Run.hp < Run.stats.max_hp
		"ward": return Run.wards < int(def.get("cap", 4))
		"keys": return Run.keys < int(def.get("cap", 9))
		"bombs": return Run.bombs < int(def.get("cap", 9))
		"recharge", "recharge_full": return not Run.active_item.is_empty() and cooldown_left() > 0
	return false

func apply_pickup(kind: String, value: int) -> void:
	var def := pickup_def(kind)
	match def.effect:
		"coins": Run.coins += value
		"heal": Run.heal(value)
		"ward": Run.wards = mini(int(def.get("cap", 4)), Run.wards + value)
		"keys": Run.keys = mini(int(def.get("cap", 9)), Run.keys + value)
		"bombs": Run.bombs = mini(int(def.get("cap", 9)), Run.bombs + value)
		"recharge":
			var id: String = Run.active_item.id
			Run.cooldowns[id] = maxf(0.0, float(Run.cooldowns.get(id, 0.0)) - float(def.amount))
		"recharge_full":
			Run.cooldowns[Run.active_item.id] = 0.0
	Run.changed.emit()

## Roll a drop table. Empty entries mean "nothing"; luck multiplies the
## table's favoured pickup. Uses the supplied (gameplay) random stream.
static func roll_table(table_id: String, rng: RandomNumberGenerator, luck := 0.0) -> Array[String]:
	var table: Dictionary = Content.get_def("drop_tables", table_id)
	var result: Array[String] = []
	for roll in int(table.get("rolls", 0)):
		var total := 0.0
		for entry in table.entries:
			total += _weight(table, entry, luck)
		var pick := rng.randf() * total
		for entry in table.entries:
			pick -= _weight(table, entry, luck)
			if pick <= 0:
				if entry.pickup != "": result.append(entry.pickup)
				break
	return result

static func _weight(table: Dictionary, entry: Dictionary, luck: float) -> float:
	var weight := float(entry.weight)
	if luck > 0 and entry.pickup != "" and entry.pickup == table.get("luck", ""):
		weight *= 1.0 + luck * .25
	return weight

# --- Active item -----------------------------------------------------------

func equipped_def() -> Dictionary:
	return {} if Run.active_item.is_empty() else Content.get_def("actives", Run.active_item.id)

func cooldown_left(id := "") -> float:
	if id == "":
		if Run.active_item.is_empty(): return 0.0
		id = Run.active_item.id
	return float(Run.cooldowns.get(id, 0.0))

## Equip a definition; returns the previous instance (or {}) so the caller can
## drop it. Duplicate instances share one cooldown entry per definition.
func equip(id: String, instance := -1) -> Dictionary:
	var previous := Run.active_item.duplicate()
	Run.active_item = {"id": id, "instance": instance if instance >= 0 else Run.new_entity_id()}
	if not Run.cooldowns.has(id):
		Run.cooldowns[id] = 0.0
	Run.changed.emit()
	return previous

## Why the equipped active cannot be used right now, or "" when it can.
func active_block_reason() -> String:
	var def := equipped_def()
	if def.is_empty(): return "no_active"
	if cooldown_left() > 0: return "cooling_down"
	var params: Dictionary = def.params
	match def.handler:
		"heal":
			if Run.hp >= Run.stats.max_hp: return "not_useful"
			if Run.coins < int(params.get("cost", 0)): return "insufficient_coins"
	return ""

func use_active() -> Dictionary:
	var reason := active_block_reason()
	if reason != "":
		return GameActions.fail(reason)
	var def := equipped_def()
	var params: Dictionary = def.params
	match def.handler:
		"heal":
			# A declared coin cost keeps waiting in a cleared room from becoming
			# unlimited free healing.
			Run.coins -= int(params.get("cost", 0))
			Run.heal(float(params.heal))
			Effects.ring_burst(game.scene_root, game.player.global_position, Color(def.color), 1.6)
		"ember_burst":
			var stats := Run.projectile_stats()
			stats.burn = float(stats.get("burn", 0)) + float(params.get("burn", 1))
			stats.split = 0
			var count := int(params.count)
			for i in count:
				var direction := Vector3.RIGHT.rotated(Vector3.UP, TAU * i / count)
				game.spawn_shot(game.player.global_position + Vector3(0, .6, 0), direction,
					float(params.damage) * float(Run.stats.damage), 12.0, stats, Color(def.color), true)
			Effects.ring_burst(game.scene_root, game.player.global_position, Color(def.color), 2.4)
	Run.cooldowns[def.id] = float(def.cooldown)
	Audio.play_sound("item", .9)
	Run.changed.emit()
	return GameActions.ok({"active": def.id})

# --- Gameplay clock --------------------------------------------------------

## Advance the cooldown ledger and pending bomb fuses on unpaused gameplay time.
## Returns the bomb records that detonated this step.
func tick(delta: float) -> Array:
	for id in Run.cooldowns:
		Run.cooldowns[id] = maxf(0.0, float(Run.cooldowns[id]) - delta)
	var detonated: Array = []
	for bomb in Run.pending_bombs:
		bomb.fuse = float(bomb.fuse) - delta
		if bomb.fuse <= 0:
			detonated.append(bomb)
	return detonated
