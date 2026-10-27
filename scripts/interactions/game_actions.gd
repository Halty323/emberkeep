class_name GameActions
extends RefCounted
## The one authority path for player actions: UseActive, PlaceBomb, Interact,
## InspectPainting, CollectPickup and EnterPortal. Every action validates,
## applies once, persists its debit and result together, then emits feedback.
## Commands carry an event id and the issuing peer, so a future host can run
## the same handlers for remote players and drop duplicate deliveries.
const BOMB_FUSE := 1.6
const BOMB_RADIUS := 2.6
const BOMB_DAMAGE := 34.0
# Separate from friendly weapon explosions, which never hurt the player.
const BOMB_SELF_DAMAGE := 1.0
const MAX_PENDING_BOMBS := 3
const INTERACT_SLACK := .4
var game

func _init(owner_game) -> void:
	game = owner_game

static func result(ok: bool, reason := "") -> Dictionary:
	return {"ok": ok, "reason": reason}

func perform(command: Dictionary, peer_id := 1) -> Dictionary:
	if not Run.active or game.in_menu or not is_instance_valid(game.player):
		return result(false, "no active run")
	if peer_id != game.player.owner_peer_id:
		return result(false, "not your character")
	if not Run.remember_event(str(command.get("event", ""))):
		return {"ok": false, "reason": "duplicate", "duplicate": true}
	match command.get("type", ""):
		"use_active": return use_active()
		"place_bomb": return place_bomb()
		"interact": return interact(str(command.get("target", "")))
		"inspect_painting": return interact(str(command.get("target", "")), "painting")
		"collect_pickup": return collect_pickup(str(command.get("target", "")))
		"enter_portal": return enter_portal(str(command.get("target", "")))
	return result(false, "unknown action")

func use_active() -> Dictionary:
	if not game.is_playing():
		return result(false, "paused")
	if Run.active_item.is_empty():
		return result(false, "No item in hand")
	var definition: Dictionary = Content.record("actives", Run.active_item.def)
	if Run.cooldown_remaining(definition.id) > 0:
		return result(false, "Still recharging")
	var cost := int(definition.get("cost", {}).get("coins", 0))
	if Run.coins < cost:
		return refuse("Needs %d coins" % cost)
	# Only a successful, useful activation spends anything or starts the timer.
	var outcome: Dictionary = ActiveItems.activate(game, definition)
	if not outcome.ok:
		return refuse(outcome.reason)
	Run.coins -= cost
	Run.cooldowns[definition.id] = float(definition.cooldown)
	Run.save_run()
	Run.changed.emit()
	Audio.play_sound("item", 1.4)
	return outcome

func refuse(reason: String) -> Dictionary:
	game.ui.notify(reason, "", Color("e8c39a"))
	Audio.play_sound("hurt", 1.6)
	return result(false, reason)

func place_bomb() -> Dictionary:
	if not game.is_playing():
		return result(false, "paused")
	if Run.bombs <= 0:
		return refuse("No bombs left")
	if Run.pending_bombs.filter(func(bomb): return bomb.room == Run.current_room).size() >= MAX_PENDING_BOMBS:
		return result(false, "Too many lit bombs")
	var at: Vector3 = game.player.position
	var record = {"id": Run.next_instance("b"), "room": Run.current_room, "position": [snappedf(at.x, .001), snappedf(at.z, .001)], "fuse": BOMB_FUSE}
	Run.bombs -= 1
	Run.pending_bombs.append(record)
	# The debit and the lit fuse are saved together: a reload neither refunds
	# the bomb nor forgets that it is about to go off.
	Run.save_run()
	Run.changed.emit()
	game.spawn_bomb_view(record)
	Audio.play_sound("dash", .7)
	return result(true)

## Resolves a bomb whose fuse ran out, whether or not its room is on screen.
## Walls, props and drops change in saved state; effects play only on screen.
func detonate(bomb: Dictionary) -> void:
	Run.pending_bombs.erase(bomb)
	var at = Vector3(float(bomb.position[0]), 0, float(bomb.position[1]))
	var live = bomb.room == Run.current_room and is_instance_valid(game.room)
	if live:
		game.bomb_exploded(bomb, at, BOMB_RADIUS)
		for enemy in game.enemies.duplicate():
			if is_instance_valid(enemy) and enemy.alive and Vector2(enemy.position.x, enemy.position.z).distance_to(Vector2(at.x, at.z)) < BOMB_RADIUS + enemy.radius:
				enemy.take_hit(BOMB_DAMAGE, (enemy.position - at).normalized() * 3.0, false)
		if is_instance_valid(game.player) and Vector2(game.player.position.x, game.player.position.z).distance_to(Vector2(at.x, at.z)) < BOMB_RADIUS:
			game.player.hurt(BOMB_SELF_DAMAGE, at)
	game.breach(bomb.room, at, BOMB_RADIUS, live)
	if Run.active:
		Run.save_run()
	Run.changed.emit()

func interact(target_id: String, required_kind := "") -> Dictionary:
	if not game.is_playing():
		return result(false, "paused")
	var target: Dictionary = game.interactions.targets.get(target_id, {})
	if target.is_empty() or (required_kind != "" and target.kind != required_kind):
		return result(false, "nothing there")
	if InteractionRegistry.flat_distance(game.player.position, target.position) > target.radius + INTERACT_SLACK:
		return result(false, "too far away")
	match target.kind:
		"treasure", "shop", "rest", "exit": return game.use_pedestal(target)
		"chest": return open_chest(target_id.trim_prefix("chest:"))
		"item": return take_item(target_id.trim_prefix("item:"))
		"painting": return game.inspect_painting(target)
	return result(false, "unknown target")

static func find_record(list: Array, id: String) -> Dictionary:
	for record in list:
		if str(record.id) == id: return record
	return {}

## Opening, the key spend and the loot records form one saved transaction.
func open_chest(chest_id: String) -> Dictionary:
	var data: Dictionary = Run.rooms[Run.current_room]
	var chest = find_record(data.get("chests", []), chest_id)
	if chest.is_empty() or chest.opened:
		return result(false, "already open")
	if not game.room.open:
		return result(false, "not safe yet")
	if chest.locked and Run.keys < 1:
		return refuse("This chest needs a key")
	if chest.locked:
		Run.keys -= 1
	chest.opened = true
	var loot = RandomNumberGenerator.new()
	loot.seed = Content.stable_hash("loot:%d:%d:%s" % [Run.seed_value, Run.floor_number, chest.id])
	var front = Vector3(float(chest.position[0]), 0, float(chest.position[1])) + Vector3(0, 0, 1.0)
	var drops = Drops.roll(chest.table, loot, Run.stats.luck, 0.0, Run.active_item.get("def", ""))
	for i in drops.size():
		var place = game.room.geometry.safe_point(Vector2(Drops.scatter(drops.size(), i, front).x, Drops.scatter(drops.size(), i, front).z), .4, game.room.blocked_at)
		if drops[i].has("active"):
			game.add_item_record(drops[i].active, Vector3(place.x, 0, place.y))
		else:
			game.spawn_pickup(Vector3(place.x, 0, place.y), drops[i].def)
	Run.save_run()
	Run.changed.emit()
	game.chest_opened(chest)
	return result(true)

## Taking a dropped item swaps it into the single slot; the item in hand is
## set down where the player stands, keeping its instance and its timer.
func take_item(instance_id: String) -> Dictionary:
	var data: Dictionary = Run.rooms[Run.current_room]
	var record = find_record(data.get("items", []), instance_id)
	if record.is_empty():
		return result(false, "gone")
	data.items.erase(record)
	var previous: Dictionary = Run.active_item
	if not previous.is_empty():
		data.items.append({"id": previous.instance, "def": previous.def,
			"position": [snappedf(game.player.position.x, .001), snappedf(game.player.position.z, .001)]})
	Run.active_item = {"instance": record.id, "def": record.def}
	if not Run.cooldowns.has(record.def):
		Run.cooldowns[record.def] = 0.0
	Run.save_run()
	Run.changed.emit()
	game.refresh_items()
	var definition = Content.record("actives", record.def)
	game.ui.notify(definition.name, definition.description, Color(definition.color))
	Audio.play_sound("item")
	return result(true)

func collect_pickup(drop_id: String) -> Dictionary:
	var data: Dictionary = Run.rooms[Run.current_room]
	var record = find_record(data.get("pickups", []), drop_id)
	var node = game.pickup_node(drop_id)
	if record.is_empty() or node == null:
		return result(false, "gone")
	if InteractionRegistry.flat_distance(game.player.position, node.position) > .9:
		return result(false, "too far away")
	var definition: Dictionary = Content.record("pickups", record.def)
	if not PickupRules.can_collect(definition):
		return result(false, "not needed")
	data.pickups.erase(record)
	PickupRules.apply(definition, float(record.get("value", definition.value)))
	node.collected = true
	node.queue_free()
	Audio.play_sound("coin" if definition.kind == "coin" else "item", 1.0 + float(record.get("value", 1)) * .05 if definition.kind == "coin" else 1.2)
	game.pickup_feedback(node.position, definition)
	Run.changed.emit()
	if data.cleared:
		Run.save_run()
	return result(true)

func enter_portal(portal_id: String) -> Dictionary:
	var data: Dictionary = Run.rooms[Run.current_room]
	if portal_id not in data.get("portals", []) or Run.portals[portal_id].state not in ["open", "revealed"]:
		return result(false, "no doorway")
	if not game.room.open:
		return result(false, "doorways are sealed")
	var side = Run.portal_side(portal_id, Run.current_room)
	if not RoomGeometry.in_trigger(Vector2(game.player.position.x, game.player.position.z), side.cell, side.dir):
		return result(false, "not at the doorway")
	game.pending_portal = portal_id
	return result(true)
