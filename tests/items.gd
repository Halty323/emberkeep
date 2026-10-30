extends SceneTree
## Pickups, drop tables, keys and chests, bombs, the single active slot with
## its gameplay-time ledger, timed modifiers, reward credit, action routing
## and touch controls. Run through tools/test.sh with disposable storage.
var checks = 0
var failures = 0
var run
var catalog
var game
var Rules
var Actives
var Registry
var DropTables

func _initialize() -> void:
	call_deferred("test_items")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func step(frames := 1) -> void:
	for frame in frames:
		game._physics_process(1.0 / 60.0)

func clear_combat() -> void:
	for enemy in game.enemies.duplicate():
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	for shot in game.shots.duplicate():
		if is_instance_valid(shot): shot.queue_free()
	game.shots.clear()

## Puts the player in a cleared room of the requested type.
func go_to(kind: String, cleared := true, single := false) -> String:
	for id in run.rooms:
		var room = run.rooms[id]
		if room.type == kind and (not single or room.cells.size() == 1):
			room.cleared = cleared
			run.current_room = id
			game.enter_room(Vector3(0, 0, 2))
			return id
	return ""

func test_items() -> void:
	run = root.get_node("Run")
	catalog = root.get_node("Content")
	Rules = load("res://scripts/items/pickup_rules.gd")
	Actives = load("res://scripts/items/active_items.gd")
	Registry = load("res://scripts/interactions/interaction_registry.gd")
	DropTables = load("res://scripts/items/drops.gd")
	test_catalog()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	test_drop_tables()
	test_pickups()
	test_actions()
	test_chests()
	test_credit_ledger()
	await test_bombs()
	test_actives()
	test_timers()
	await test_touch()
	test_registry()
	game.end_run(false)
	game.queue_free()
	await process_frame
	print("EMBERKEEP ITEMS TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func rejected(family: String, records: Array, label: String) -> void:
	catalog.errors = PackedStringArray()
	catalog.ingest(family, records)
	var problems: PackedStringArray = catalog.errors
	problems.append_array(catalog.validate())
	check(not problems.is_empty(), "validator rejects " + label)
	catalog.load_catalog()

func test_catalog() -> void:
	check(catalog.families.pickups.size() == 9, "nine pickup definitions")
	check(catalog.families.actives.size() == 8, "eight active items")
	var kinds := {}
	for pickup in catalog.families.pickups: kinds[pickup.kind] = true
	for kind in ["coin", "heal", "ward", "key", "bomb", "battery", "battery_full"]:
		check(kinds.has(kind), "pickup kind shipped: " + kind)
	check(Rules.KINDS == catalog.PICKUP_KINDS, "every registered pickup kind has rules")
	check(Actives.HANDLERS == catalog.ACTIVE_HANDLERS.keys(), "every registered active handler is implemented")
	for active in catalog.families.actives:
		check(active.cooldown > 0 and active.handler in Actives.HANDLERS, "active is valid: " + active.id)
	var pickup = catalog.record("pickups", "copper_coin").duplicate(true)
	pickup.kind = "mystery"
	rejected("pickups", [pickup], "unknown pickup kinds instead of defaulting to hearts")
	var active = catalog.record("actives", "gale_bell").duplicate(true)
	active.handler = "summon_dragon"
	rejected("actives", [active], "unknown active handlers")
	var missing = catalog.record("actives", "pocket_hearth").duplicate(true)
	missing.params = {}
	rejected("actives", [missing], "handlers missing required parameters")
	var costly = catalog.record("actives", "pocket_hearth").duplicate(true)
	costly.cost = {"coins": -3}
	rejected("actives", [costly], "impossible costs")
	var table = {"id": "x", "rolls": [{"pickup": "gold_bar", "chance": .5}]}
	rejected("drop_tables", [table], "drop tables naming missing pickups")
	rejected("drop_tables", [{"id": "y", "rolls": [{"pickup": "bomb", "chance": 1.5}]}], "impossible chances")
	check(catalog.errors.is_empty(), "catalog restores after negative checks")

func test_drop_tables() -> void:
	var drops = DropTables.coins(12)
	check(drops.filter(func(d): return d.def == "silver_coin").size() == 2 and drops.filter(func(d): return d.def == "copper_coin").size() == 2,
		"coin amounts split into silver and copper pickups")
	var a = RandomNumberGenerator.new()
	a.seed = 99
	var b = RandomNumberGenerator.new()
	b.seed = 99
	check(DropTables.roll("locked_chest", a) == DropTables.roll("locked_chest", b), "drop tables are deterministic for a given stream")
	var total = 0
	for value in catalog.families.pickups:
		check(value.value > 0, "pickup value is data: " + value.id)
	for i in 200:
		for drop in DropTables.roll("enemy_common", a):
			if drop.has("def"): total += int(catalog.record("pickups", drop.def).value) if catalog.record("pickups", drop.def).kind == "coin" else 0
	check(total > 45 and total < 125, "enemy coin drops keep their expected value (%d over 200 kills)" % total)

func test_pickups() -> void:
	game.start_run("candle", 51001, false)
	game.paused = false
	check(run.bombs == 1 and run.keys == 0 and run.wards == 0, "new runs start with one bomb")
	var player = game.player
	var collect = func(id: String) -> bool:
		var before = game.pickups.size()
		var pickup = game.spawn_pickup(player.position + Vector3(.2, 0, 0), id)
		pickup.age = 1
		pickup.update_sim(0)
		return pickup.collected
	run.hp = run.stats.max_hp
	check(not collect.call("half_heart"), "hearts at full health stay on the ground")
	run.hp = 2
	check(collect.call("half_heart") and run.hp == 3, "half heart heals 1")
	check(collect.call("full_heart") and run.hp == 5, "full heart heals 2")
	var coins = run.coins
	check(collect.call("copper_coin") and collect.call("silver_coin") and run.coins == coins + 6, "coins add their values")
	for i in 3: collect.call("ward")
	check(run.wards == 3 and not collect.call("ward"), "wards stop at their cap and stay on the ground")
	check(collect.call("key") and run.keys == 1, "keys are collected")
	check(collect.call("bomb") and run.bombs == 2, "bombs are collected")
	check(not collect.call("small_battery"), "batteries stay put without an equipped active")
	run.active_item = {"instance": "a900", "def": "gale_bell"}
	run.cooldowns = {"gale_bell": 0.0}
	check(not collect.call("small_battery"), "batteries stay put while the active is ready")
	run.cooldowns.gale_bell = 30.0
	check(collect.call("small_battery") and is_equal_approx(run.cooldown_remaining("gale_bell"), 15.0), "small battery removes 15 seconds")
	check(collect.call("full_battery") and run.cooldown_remaining("gale_bell") == 0, "full battery readies the active")
	# Collection removes the record once; a second attempt grants nothing.
	var pickup = game.spawn_pickup(player.position, "silver_coin")
	var record_id: String = pickup.drop_id
	coins = run.coins
	var first = game.actions.perform({"type": "collect_pickup", "target": record_id, "event": "t:1"})
	var second = game.actions.perform({"type": "collect_pickup", "target": record_id, "event": "t:2"})
	check(first.ok and not second.ok and run.coins == coins + 5, "a drop record grants its effect exactly once")
	check(not run.rooms[run.current_room].pickups.any(func(d): return d.id == record_id), "collected record is removed from the room")
	# Unknown kinds never silently become hearts.
	check(game.spawn_pickup(player.position, "mystery") == null, "unknown pickups are refused at spawn")
	var saved = {"0,0": {"pickups": [{"id": 5, "kind": "heart", "value": 1, "position": [0, 0]},
		{"id": 6, "kind": "mystery", "value": 1, "position": [0, 0]}]}}
	run.normalize_drops(saved)
	check(saved["0,0"].pickups.size() == 1 and saved["0,0"].pickups[0].def == "half_heart" and saved["0,0"].pickups[0].id == "5",
		"legacy drops resolve explicitly and unknown kinds are removed")

func test_actions() -> void:
	game.start_run("candle", 51002, false)
	game.paused = false
	var result = game.actions.perform({"type": "place_bomb", "event": "dup:1"})
	var again = game.actions.perform({"type": "place_bomb", "event": "dup:1"})
	check(result.ok and again.get("duplicate", false) and run.bombs == 0, "a repeated event id is applied once")
	check(not game.actions.perform({"type": "place_bomb", "event": "x"}, 2).ok, "another peer cannot act for this player")
	check(not game.actions.perform({"type": "nonsense", "event": "y"}).ok, "unknown actions are rejected")
	run.pending_bombs.clear()
	clear_combat()
	# Hostile attacks keep a reserved share of the projectile cap.
	for i in game.MAX_SHOTS:
		game.spawn_shot(Vector3(0, .6, 0), Vector3.RIGHT, 1, 0, {}, Color.WHITE, true)
	var friendly = game.shots.size()
	check(friendly == game.MAX_SHOTS - game.HOSTILE_SHOT_RESERVE, "friendly volleys stop at their share of the cap")
	check(game.spawn_shot(Vector3(0, .6, 0), Vector3.RIGHT, 1, 0, {}, Color.WHITE, false) != null, "enemies can still attack under a maximum volley")
	clear_combat()

func test_chests() -> void:
	game.start_run("candle", 51003, false)
	game.paused = false
	var room_id = go_to("treasure")
	var data = run.rooms[room_id]
	data["chests"] = [{"id": room_id + ":c9", "position": [3.0, 3.0], "locked": true, "opened": false, "table": "locked_chest"}]
	game.enter_room(Vector3(0, 0, 2))
	game.player.place(Vector3(3, 0, 4.3))
	run.keys = 0
	game.update_interaction()
	check(game.interactions.focused == "chest:" + room_id + ":c9", "the chest becomes the interaction target")
	check(game.interaction_text.contains("key"), "locked chest prompt asks for a key")
	game.interact()
	check(not data.chests[0].opened and run.keys == 0, "a locked chest stays shut without a key")
	run.keys = 2
	var drops_before = data.get("pickups", []).size() + data.get("items", []).size()
	game.interact()
	check(data.chests[0].opened and run.keys == 1, "opening spends exactly one key")
	var created = data.get("pickups", []).size() + data.get("items", []).size() - drops_before
	check(created > 0, "chest loot becomes stable drop records")
	var reopened = game.actions.open_chest(room_id + ":c9")
	check(not reopened.ok and run.keys == 1 and data.get("pickups", []).size() + data.get("items", []).size() - drops_before == created,
		"reopening cannot spend or pay twice")
	var saved = JSON.parse_string(FileAccess.get_file_as_string("user://run.json"))
	check(saved.rooms[room_id].chests[0].opened and int(saved.keys) == 1, "the key spend and opened chest are saved together")
	check(run.load_run(), "chest checkpoint reloads")
	game.enter_room(Vector3(0, 0, 2))
	check(run.rooms[room_id].chests[0].opened and not game.interactions.targets.has("chest:" + room_id + ":c9"), "reload cannot replenish an opened chest")
	# Chests in a room still in combat wait until it is safe.
	var combat = go_to("combat", false)
	run.rooms[combat]["chests"] = [{"id": combat + ":c9", "position": [3.0, 3.0], "locked": false, "opened": false, "table": "locked_chest"}]
	game.enter_room(Vector3(0, 0, 2))
	game.player.place(Vector3(3, 0, 4.3))
	game.update_interaction()
	check(game.interactions.focused != "chest:" + combat + ":c9", "a chest cannot be opened during combat")
	clear_combat()

func test_credit_ledger() -> void:
	game.start_run("candle", 51004, false)
	game.paused = false
	var combat = go_to("combat", false, true)
	var data = run.rooms[combat]
	var foes = game.enemies.duplicate()
	check(foes.all(func(e): return e.source.begins_with(combat + ":e")), "encounter foes carry stable source ids")
	var victim = foes[0]
	var source: String = victim.source
	var kills = run.kills
	victim.take_hit(100000, Vector3.ZERO)
	check(run.kills == kills + 1 and source in data.credited, "a kill is credited once with its source id")
	var drops_after_first = data.get("pickups", []).size()
	# Saving mid-combat (a bomb debit) then reloading restarts the encounter.
	game.actions.perform({"type": "place_bomb", "event": "ledger:1"})
	check(run.load_run(), "mid-combat checkpoint loads")
	game.enter_room(Vector3(0, 0, 2))
	var again = game.enemies.filter(func(e): return e.source == source)
	check(again.size() == 1, "the credited foe respawns with the encounter")
	var kills_now = run.kills
	var drops_now = run.rooms[combat].get("pickups", []).size()
	again[0].take_hit(100000, Vector3.ZERO)
	check(run.kills == kills_now and run.rooms[combat].get("pickups", []).size() == drops_now, "a respawned foe grants no second kill credit or loot")
	check(drops_now >= drops_after_first, "earlier drops survive the reload")
	# Splitter children derive ids from their parent; summons pay nothing.
	var splitter = game.spawn_enemy(Vector3(2, 0, 0), "splitter", combat + ":e99")
	splitter.take_hit(100000, Vector3.ZERO)
	var wisps = game.enemies.filter(func(e): return is_instance_valid(e) and e.alive and e.kind == "wisp")
	check(wisps.size() >= 2 and wisps.any(func(w): return w.source == combat + ":e99.s0"), "splitter children have derived ids")
	var summon = game.spawn_enemy(Vector3(-2, 0, 0), "mote")
	kills_now = run.kills
	summon.take_hit(100000, Vector3.ZERO)
	check(run.kills == kills_now, "summoned foes are not a reward source")
	clear_combat()
	run.pending_bombs.clear()

func test_bombs() -> void:
	game.start_run("candle", 51005, false)
	game.paused = false
	var room_id = go_to("combat", false, true)
	clear_combat()
	run.bombs = 2
	var foe = game.spawn_enemy(Vector3(1.2, 0, 2), "brute")
	foe.hp = 20
	foe.speed = 0
	game.player.place(Vector3(0, 0, 2))
	game.player.invulnerability = 0
	game.player.shield = 0
	run.wards = 0
	run.hp = 6
	var placed = game.submit({"type": "place_bomb"})
	check(placed.ok and run.bombs == 1 and run.pending_bombs.size() == 1, "placing a bomb debits it and lights a fuse")
	var saved = JSON.parse_string(FileAccess.get_file_as_string("user://run.json"))
	check(int(saved.bombs) == 1 and saved.pending_bombs.size() == 1, "debit and pending bomb are saved together")
	# Reload mid-fuse: no refund, same remaining fuse, no wall-clock catch-up.
	for frame in 30: step()
	var fuse = float(run.pending_bombs[0].fuse)
	run.save_run()
	check(run.load_run(), "pending bomb reloads")
	check(run.bombs == 1 and run.pending_bombs.size() == 1 and is_equal_approx(float(run.pending_bombs[0].fuse), fuse), "reload neither refunds nor advances the fuse")
	game.enter_room(Vector3(0, 0, 2))
	clear_combat()
	foe = game.spawn_enemy(Vector3(1.2, 0, 2), "brute")
	foe.hp = 20
	foe.speed = 0
	game.player.place(Vector3(0, 0, 2))
	game.player.invulnerability = 0
	game.player.shield = 0
	# Pausing freezes the fuse.
	game.paused = true
	for frame in 120: step()
	check(is_equal_approx(float(run.pending_bombs[0].fuse), fuse), "a paused game does not advance the fuse")
	game.paused = false
	var hp_before = run.hp
	for frame in 120:
		step()
		if run.pending_bombs.is_empty(): break
	check(run.pending_bombs.is_empty(), "the fuse burns down in gameplay time")
	check(not is_instance_valid(foe) or not foe.alive, "the blast damages nearby foes")
	check(run.hp == hp_before - 1, "standing in the blast costs exactly the bomb's self-damage")
	saved = JSON.parse_string(FileAccess.get_file_as_string("user://run.json"))
	check(saved.pending_bombs.is_empty() and int(saved.bombs) == 1, "detonation is saved and never repeats on reload")
	# A bomb left behind still resolves offscreen without effects.
	clear_combat()
	run.rooms[room_id].cleared = true
	game.enter_room(Vector3(0, 0, 2))
	game.submit({"type": "place_bomb"})
	var other = run.neighbors(room_id)[0]
	run.current_room = other
	game.enter_room(Vector3(0, 0, 2))
	clear_combat()
	game.paused = false
	for frame in 150: step()
	check(run.pending_bombs.is_empty(), "an offscreen bomb resolves on the same clock")
	check(game.bomb_views.is_empty(), "offscreen detonation creates no view in the current room")
	await process_frame

func test_actives() -> void:
	game.start_run("candle", 51006, false)
	game.paused = false
	go_to("combat", false, true)
	check(not game.submit({"type": "use_active"}).ok, "nothing happens with an empty slot")
	run.rooms[run.current_room]["items"] = [{"id": "a501", "def": "pocket_hearth", "position": [0.0, 2.0]}]
	game.refresh_items()
	game.room.set_open(true)
	game.player.place(Vector3(0, 0, 2.3))
	check(game.actions.take_item("a501").ok and run.active_item.def == "pocket_hearth", "a dropped item fills the slot")
	# Pocket Hearth: no use at full health or without coins; never free.
	run.hp = run.stats.max_hp
	var coins = run.coins
	check(not game.submit({"type": "use_active"}).ok and run.cooldown_remaining("pocket_hearth") == 0 and run.coins == coins,
		"healing at full health is refused without starting the cooldown")
	run.hp = 2
	run.coins = 1
	check(not game.submit({"type": "use_active"}).ok and run.hp == 2 and run.cooldown_remaining("pocket_hearth") == 0, "insufficient coins refuse the heal")
	run.coins = 10
	check(game.submit({"type": "use_active"}).ok and run.hp == 4 and run.coins == 7, "a successful heal costs its declared coins")
	check(is_equal_approx(run.cooldown_remaining("pocket_hearth"), 60), "only a successful use starts the cooldown")
	check(not game.submit({"type": "use_active"}).ok and run.hp == 4, "a recharging item cannot fire again")
	var saved = JSON.parse_string(FileAccess.get_file_as_string("user://run.json"))
	check(int(saved.coins) == 7 and is_equal_approx(float(saved.cooldowns.pocket_hearth), 60), "ledger and coins are saved with the action")
	clear_combat()
	# Swapping keeps each definition's timer; unequipped entries keep ticking.
	run.rooms[run.current_room].items.append({"id": "a502", "def": "gale_bell", "position": [0.0, 2.3]})
	game.refresh_items()
	game.actions.take_item("a502")
	check(run.active_item.def == "gale_bell" and run.rooms[run.current_room].items.any(func(r): return r.def == "pocket_hearth" and r.id == "a501"),
		"swapping sets the held item down with its instance id")
	game.paused = false
	for frame in 120: step()
	check(absf(run.cooldown_remaining("pocket_hearth") - 58.0) < .1, "an unequipped item keeps recharging in gameplay time")
	game.actions.take_item("a501")
	check(run.active_item.def == "pocket_hearth" and absf(run.cooldown_remaining("pocket_hearth") - 58.0) < .1, "swapping back never resets the timer")
	run.rooms[run.current_room].items.append({"id": "a777", "def": "pocket_hearth", "position": [0.0, 2.3]})
	game.actions.take_item("a777")
	check(absf(run.cooldown_remaining("pocket_hearth") - 58.0) < .1, "duplicate instances share one ledger entry")
	# Batteries touch only the equipped item.
	run.cooldowns["gale_bell"] = 20.0
	run.recharge(run.active_item.def, 15)
	check(is_equal_approx(run.cooldown_remaining("gale_bell"), 20.0), "a battery leaves unequipped timers alone")
	# Each handler: useful activations only.
	clear_combat()
	var refusals := {"gale_bell": "nothing nearby", "ember_flask": "no foes", "winter_globe": "no foes", "copper_kettle": "no foes",
		"moth_jar": "no foes", "miners_lantern": "no seam", "bell_jar": "no danger"}
	for id in refusals:
		run.active_item = {"instance": "t" + id, "def": id}
		run.cooldowns[id] = 0.0
		check(not game.submit({"type": "use_active"}).ok and run.cooldown_remaining(id) == 0, "%s refuses with %s" % [id, refusals[id]])
	var foe = game.spawn_enemy(Vector3(3, 0, 2), "brute")
	var boss = game.spawn_enemy(Vector3(-3, 0, -2), "boss")
	game.spawn_shot(game.player.position + Vector3(1.5, .6, 0), Vector3.LEFT, 1, 0, {}, Color.WHITE, false)
	for id in ["gale_bell", "ember_flask", "winter_globe", "copper_kettle", "moth_jar", "bell_jar"]:
		run.active_item = {"instance": "t" + id, "def": id}
		run.cooldowns[id] = 0.0
		if id == "gale_bell":
			game.spawn_shot(game.player.position + Vector3(1.5, .6, 0), Vector3.LEFT, 1, 0, {}, Color.WHITE, false)
		var shots_before = game.shots.size()
		var damage_before = run.stats.damage
		check(game.submit({"type": "use_active"}).ok and run.cooldown_remaining(id) > 0, id + " activates with foes present")
		match id:
			"gale_bell": check(not game.shots.any(func(s): return is_instance_valid(s) and s.alive and not s.friendly), "Gale Bell clears hostile embers")
			"ember_flask": check(game.shots.size() >= shots_before + 10, "Ember Flask releases a ring of embers")
			"winter_globe": check(foe.slow_factor > boss.slow_factor and boss.slow_factor > 0, "Winter Globe slows bosses less")
			"copper_kettle": check(run.stats.damage > damage_before, "Copper Kettle layers a temporary buff")
			"moth_jar": check(game.companions.size() == 2, "Moth Jar releases two moths")
			"bell_jar":
				var hp = run.hp
				game.player.invulnerability = 0
				game.player.shield = 0
				run.wards = 0
				game.player.hurt(1, Vector3.ZERO)
				check(run.hp == hp and game.player.shelter.visible, "Bell Jar shelters the player under visible glass")
	run.active_item = {"instance": "tmoth2", "def": "moth_jar"}
	run.cooldowns["moth_jar"] = 0.0
	check(not game.submit({"type": "use_active"}).ok, "companion capacity refuses a second Moth Jar")
	# A fresh press is required: key auto-repeat never fires again.
	run.active_item = {"instance": "tg", "def": "gale_bell"}
	run.cooldowns["gale_bell"] = 0.0
	var key = InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	key.echo = true
	game._unhandled_input(key)
	check(run.cooldown_remaining("gale_bell") == 0, "a held key's repeat does not activate the item")
	clear_combat()

func test_timers() -> void:
	game.start_run("candle", 51007, false)
	game.paused = false
	go_to("start")
	run.active_item = {"instance": "a1", "def": "winter_globe"}
	run.cooldowns = {"winter_globe": 30.0}
	# Relic gained during a buff survives its expiry.
	run.add_modifier("copper_kettle", 2.0, {"damage": .35})
	var buffed = run.stats.damage
	run.gain_item("warm_wax")
	check(run.stats.damage > buffed, "a relic gained during a buff applies immediately")
	run.add_modifier("bell_jar", 2.0, {}, {"invulnerable": 1})
	run.save_run()
	check(run.load_run(), "modifiers save and load")
	check(run.modifiers.size() == 2 and is_equal_approx(float(run.modifiers[0].remaining), 2.0), "modifier time restores without catch-up")
	# Pause, menus and app suspension do not advance any timer.
	game.paused = true
	for frame in 300: step()
	check(is_equal_approx(run.cooldown_remaining("winter_globe"), 30.0), "paused time never advances cooldowns")
	game.paused = false
	game._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(game.paused and game.ui.mode == "pause", "backgrounding the app pauses the game")
	for frame in 300: step()
	check(is_equal_approx(run.cooldown_remaining("winter_globe"), 30.0), "background time never advances cooldowns")
	game.resume_game()
	for frame in 180: step()
	check(absf(run.cooldown_remaining("winter_globe") - 27.0) < .05, "cooldowns advance only with unpaused gameplay time")
	check(run.modifiers.is_empty() and run.inventory.has("warm_wax"), "buffs expire and relics remain")
	check(is_equal_approx(run.stats.damage, catalog.base_stats().damage + catalog.item_by_id.warm_wax.effects.damage), "stats rebuild from relics after expiry")
	# Re-entering or clearing a room never resets a timer.
	game.enter_room(Vector3(0, 0, 2))
	check(absf(run.cooldown_remaining("winter_globe") - 27.0) < .05, "room transitions keep the timer")
	# Reload restores the saved remaining time, not a wall-clock catch-up.
	run.save_run()
	check(run.load_run() and absf(run.cooldown_remaining("winter_globe") - 27.0) < .05, "reload restores the saved remaining time")

func touch(index: int, at: Vector2, pressed := true) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = game.ui.offset + at * game.ui.scale_value
	game.ui._input(event)

func drag(index: int, at: Vector2) -> void:
	var event = InputEventScreenDrag.new()
	event.index = index
	event.position = game.ui.offset + at * game.ui.scale_value
	game.ui._input(event)

func test_touch() -> void:
	game.start_run("candle", 51008, false)
	go_to("combat", false, true)
	game.paused = false
	game.ui.show_screen("play")
	var buttons: Dictionary = game.ui.ACTION_BUTTONS
	check(buttons.dash.center == game.ui.DASH_CENTER, "dash uses the shared hit region")
	for a in buttons:
		for b in buttons:
			if a < b: check(buttons[a].center.distance_to(buttons[b].center) > buttons[a].radius + buttons[b].radius, "action buttons do not overlap")
		var center: Vector2 = buttons[a].center
		check(not game.ui.INTERACTION_RECT.grow(4).intersects(Rect2(center - Vector2.ONE * buttons[a].radius, Vector2.ONE * buttons[a].radius * 2)),
			"action button clears the interaction prompt: " + a)
	run.active_item = {"instance": "a1", "def": "gale_bell"}
	run.cooldowns = {"gale_bell": 0.0}
	run.bombs = 3
	game.spawn_shot(game.player.position + Vector3(1.5, .6, 0), Vector3.LEFT, 1, 0, {}, Color.WHITE, false)
	# Move and aim are held while three more fingers tap actions.
	touch(0, Vector2(140, 574))
	touch(1, Vector2(1180, 640))
	drag(0, Vector2(188, 574))
	drag(1, Vector2(1180, 560))
	touch(2, buttons.active.center)
	touch(3, buttons.bomb.center)
	touch(4, buttons.dash.center)
	check(game.ui.left_touch == 0 and game.ui.right_touch == 1, "both sticks stay captured through action taps")
	check(game.ui.left_vector.x > .7 and game.ui.right_vector.length() > .5, "stick vectors keep updating")
	check(run.cooldown_remaining("gale_bell") > 0, "the Active button uses the item")
	check(run.bombs == 2 and run.pending_bombs.size() == 1, "the Bomb button places exactly one bomb")
	check(game.request_dash, "the Dash button still dashes")
	touch(2, buttons.active.center, false)
	touch(3, buttons.bomb.center, false)
	check(game.ui.left_touch == 0 and game.ui.right_touch == 1, "releasing action fingers leaves the sticks alone")
	touch(0, Vector2(188, 574), false)
	touch(1, Vector2(1180, 560), false)
	check(game.ui.left_touch == -1 and game.ui.right_touch == -1, "sticks release independently")
	# Mouse on a visible action button acts once and never becomes fire.
	root.get_node("Settings").set_value("touch", true)
	var click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = game.ui.offset + buttons.bomb.center * game.ui.scale_value
	game.ui._input(click)
	check(run.bombs == 1 and game.ui.mouse_on_action, "a mouse click on the Bomb button places a bomb and suppresses fire")
	var emulated = click.duplicate()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	game.ui._input(emulated)
	check(run.bombs == 1, "a touch's emulated mouse press is not a second action")
	click.pressed = false
	game.ui._input(click)
	check(not game.ui.mouse_on_action, "releasing the mouse restores normal firing")
	root.get_node("Settings").set_value("touch", false)
	run.pending_bombs.clear()
	clear_combat()
	await process_frame

func test_registry() -> void:
	var registry = Registry.new()
	var always = func(_target): return true
	registry.register("painting:1", "painting", Vector3(0, 0, 0), 2.0, "")
	registry.register("pedestal", "exit", Vector3(1.5, 0, 0), 2.0, "")
	check(registry.choose(Vector3(.2, 0, 0), always).id == "pedestal", "a painting never steals the exit prompt")
	registry.clear()
	registry.register("chest:b", "chest", Vector3(1, 0, 0), 2.0, "")
	registry.register("chest:a", "chest", Vector3(-1, 0, 0), 2.0, "")
	check(registry.choose(Vector3.ZERO, always).id == "chest:a", "exact ties resolve deterministically by id")
	registry.focused = "chest:b"
	check(registry.choose(Vector3(-.1, 0, 0), always).id == "chest:b", "focus is kept when another target is only slightly closer")
	check(registry.choose(Vector3(-.8, 0, 0), always).id == "chest:a", "focus moves when another target is clearly closer")
	check(registry.choose(Vector3(-.8, 0, 0), func(t): return t.id != "chest:a").id == "chest:b", "ineligible targets are skipped")
	check(registry.choose(Vector3(10, 0, 0), always).is_empty(), "nothing is chosen out of reach")
