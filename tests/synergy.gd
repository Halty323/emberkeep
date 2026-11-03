extends SceneTree
## Combinations: elements reacting on foes, relic pairings, spellbook
## resonance, items and the floor joining in, and how each is found and shown.
var checks := 0
var failures := 0
var game
var run
var S

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("exercise")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func exercise() -> void:
	S = load("res://scripts/items/synergies.gd")
	run = root.get_node("Run")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	data()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_run("candle", 31609250, false)
	game.set_physics_process(false)
	for i in 3: await process_frame
	reactions()
	pairings()
	resonance()
	floor_and_items()
	await presentation()
	game.queue_free()
	for i in 3: await process_frame
	print("SYNERGY: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func data() -> void:
	var content = root.get_node("Content")
	var missing: Array = []
	for id in S.PAIRINGS:
		for relic in [S.PAIRINGS[id][0], S.PAIRINGS[id][1]]:
			if not content.item_by_id.has(relic): missing.append("%s:%s" % [id, relic])
	for element in S.RESONANCE:
		for relic in S.RESONANCE[element][0]:
			if not content.item_by_id.has(relic): missing.append("%s:%s" % [element, relic])
	check(missing.is_empty(), "every pairing and resonance names real relics (%s)" % ", ".join(missing))
	check(S.PAIRINGS.size() >= 20 and S.REACTIONS.size() >= 12 and S.RESONANCE.size() == 8, "about twenty pairings, a dozen reactions, a resonance per element")
	check(S.all_ids().size() == S.PAIRINGS.size() + S.REACTIONS.size() + 8, "the journal lists every combination")
	var unhinted: Array = S.all_ids().filter(func(id): return S.entry(id)[3] == "" or S.entry(id)[2] == "")
	check(unhinted.is_empty(), "every combination has a hint and a description")
	for pair in [["frost", "ember", "shatter"], ["ember", "tide", "steam"], ["tide", "storm", "surge"], ["frost", "tide", "freeze"],
			["radiance", "glass", "prism"], ["radiance", "venom", "flare"], ["glass", "storm", "refract"], ["ember", "ember", ""], ["storm", "frost", ""]]:
		check(S.reaction(pair[0], pair[1]) == pair[2] and S.reaction(pair[1], pair[0]) == pair[2], "%s and %s make %s" % [pair[0], pair[1], pair[2] if pair[2] != "" else "nothing"])
	check(S.elements_of({"element": "frost", "burn": 1.0, "chain": 1.0}) == ["frost", "ember", "storm"], "a spell carries its book's element first, then its relics'")
	check(S.completes(["chili_oil"], "firecracker") == ["powder_keg"] and S.completes(["chili_oil", "firecracker"], "firecracker").is_empty(), "a relic completes a pairing only once")
	var flags: Dictionary = S.spell_stats(["chili_oil", "firecracker", "snowglobe", "second_wind", "copper_wire"], "storm")
	check(flags.get("keg") == 1.0 and not flags.has("freeze") and flags.get("chain") == 1.0 and flags.get("resonance") == 1.0, "spells carry pairing flags and resonance; the player's own pairings stay home")

func foe(at := Vector3(0, 0, -3), kind := "mote"):
	var spawned = game.spawn_enemy(game.player.position + at, kind)
	spawned.max_hp = 400.0
	spawned.hp = 400.0
	spawned.reaction_wait = 0.0
	return spawned

func clear_foes() -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy):
			enemy.alive = false
			enemy.queue_free()
	game.enemies.clear()
	for shot in game.shots:
		if is_instance_valid(shot): shot.queue_free()
	game.shots.clear()

func land(enemy, stats: Dictionary) -> void:
	enemy.age += .2
	enemy.apply_status(stats)

func reactions() -> void:
	var target = foe()
	land(target, {"chill": 1.0, "element": "frost", "hit": 10.0})
	check(target.marks.has("frost"), "frost leaves its mark on a foe")
	land(target, {"burn": 1.0, "element": "ember", "hit": 10.0})
	check(target.hp < 400.0 - 25.0 and not target.marks.has("frost"), "fire on a chilled foe shatters it (%.0f)" % target.hp)
	check("r:shatter" in run.profile.combos, "a reaction seen once is written into the journal")
	var before: float = target.hp
	land(target, {"chill": 1.0, "element": "frost", "hit": 10.0})
	land(target, {"burn": 1.0, "element": "ember", "hit": 10.0})
	check(target.hp == before, "a foe cannot react again straight away")
	clear_foes()
	var together = foe()
	together.apply_status({"burn": 1.0, "chill": 1.0, "hit": 10.0})
	check(together.hp == 400.0 and together.marks.has("ember") and together.marks.has("frost"), "elements landing in one blow never react with each other")
	clear_foes()
	var soaked = foe()
	land(soaked, {"wet": 1.0, "hit": 10.0})
	land(soaked, {"chill": 1.0, "hit": 10.0})
	check(soaked.frozen > 0, "frost on a soaked foe freezes it solid")
	var held: Vector3 = soaked.position
	soaked.update_sim(.2)
	check(soaked.position.is_equal_approx(held), "a frozen foe does not move")
	var struck: float = soaked.hp
	soaked.take_hit(10.0, Vector3.ZERO)
	check(is_equal_approx(struck - soaked.hp, 15.0) or struck - soaked.hp > 14.0, "a frozen foe takes half again as much damage")
	clear_foes()
	var first = foe(Vector3(0, 0, -3))
	var second = foe(Vector3(2.5, 0, -3))
	land(second, {"wet": 1.0, "hit": 1.0})
	land(first, {"wet": 1.0, "hit": 1.0})
	land(first, {"chain": 1.0, "element": "storm", "hit": 10.0})
	check(second.hp < 400.0 and first.hp < 400.0, "lightning on a soaked foe surges through every soaked foe")
	clear_foes()
	var glassy = foe()
	land(glassy, {"element": "glass", "hit": 10.0})
	var shots_before: int = game.shots.size()
	land(glassy, {"burn": 1.0, "hit": 10.0})
	check(game.shots.size() >= shots_before + 4, "fire meeting glass splinters into shards that carry it on")
	clear_foes()
	var lit = foe()
	land(lit, {"poison": 1.0, "hit": 10.0})
	land(lit, {"element": "radiance", "hit": 10.0})
	check(lit.flared > 0, "radiance on a poisoned foe lays it bare")
	clear_foes()
	var near = foe(Vector3(0, 0, -3))
	var beside = foe(Vector3(1.5, 0, -3))
	land(near, {"poison": 1.0, "hit": 10.0})
	land(near, {"burn": 1.0, "hit": 10.0})
	check(beside.burn_time > 0 and beside.poison_time > 0, "fire meeting poison spreads both to foes close by")
	clear_foes()

func pairings() -> void:
	run.inventory = ["chili_oil", "firecracker"]
	run.rebuild_stats()
	var stats: Dictionary = run.projectile_stats()
	check(stats.get("keg") == 1.0, "Chili Oil and Firecracker make Powder Keg")
	var keg = foe(Vector3(0, 0, -3))
	var neighbour = foe(Vector3(1.5, 0, -3))
	keg.apply_status(stats)
	keg.take_hit(9999.0, Vector3.ZERO)
	check(neighbour.hp < 400.0, "a foe set burning by Powder Keg explodes when it falls")
	clear_foes()
	run.inventory = ["honeycomb", "bitter_tea"]
	run.rebuild_stats()
	run.hp = 2.0
	var poisoned = foe()
	var jelly: Dictionary = run.projectile_stats()
	jelly["owner"] = 0
	poisoned.apply_status(jelly)
	poisoned.take_hit(9999.0, Vector3.ZERO)
	check(is_equal_approx(run.hp, 2.5), "Royal Jelly heals half a heart when a poisoned foe falls")
	clear_foes()
	run.inventory = ["copper_wire", "skipping_stone"]
	run.rebuild_stats()
	var target = foe(Vector3(0, 0, -2))
	var shot = game.make_shot(game.player.position + Vector3.UP, Vector3.FORWARD, 10.0, 12.0, run.projectile_stats(), Color.WHITE, true)
	shot.ricochet()
	check(target.hp < 400.0, "Ricochet Arc throws lightning when a spell glances off a wall")
	clear_foes()
	run.inventory = ["moon_shard", "hunters_mark"]
	run.rebuild_stats()
	var wounded = foe()
	wounded.hp = 90.0
	var weave = game.make_shot(wounded.global_position + Vector3.UP, Vector3.FORWARD, 5.0, 12.0, run.projectile_stats(), Color.WHITE, true)
	weave.hit_enemy(wounded)
	check(not wounded.alive, "Hunter's Moon finishes a foe below a quarter of its health")
	clear_foes()
	run.inventory = ["mirror_box", "long_match"]
	run.rebuild_stats()
	var mirrored = game.make_shot(game.player.position + Vector3.UP, Vector3.FORWARD, 10.0, 12.0, run.projectile_stats(), Color.WHITE, true)
	mirrored.ricochet()
	check(is_equal_approx(mirrored.damage, 13.0), "Mirror Maze makes a spell stronger with each ricochet")
	clear_foes()
	run.inventory = ["eternal_hearth", "dried_rose"]
	run.rebuild_stats()
	var wards: int = run.wards
	run.rooms[run.current_room].cleared = false
	game.clear_room()
	check(run.wards == wards + 1, "Hearthkeeper gives a ward for a room won")
	run.inventory = ["lodestone", "pocket_change"]
	run.rebuild_stats()
	var damage: float = run.stats.damage
	var coin = game.spawn_pickup(game.player.position, "copper_coin")
	game.actions.collect_pickup(coin.drop_id)
	check(run.stats.damage > damage + .15, "Magpie turns a coin into a moment's strength")
	run.inventory = ["sugar_rush", "hungry_flame", "heartstone", "last_light"]
	run.modifiers = []
	run.rebuild_stats()
	run.hp = 2.0
	game.award_kill({"at": game.player.position + Vector3(0, 0, -3), "boss": false, "inert": false, "loot": false})
	check(run.modifiers.any(func(modifier): return modifier.source == "frenzy"), "Frenzy quickens casting after a kill")
	check(is_equal_approx(run.hp, 2.5), "Last Stand heals a quarter heart for a kill at low health")
	run.inventory = []
	run.modifiers = []
	run.rebuild_stats()

func resonance() -> void:
	run.inventory = ["copper_wire", "storm_lantern"]
	run.rebuild_stats()
	var storm: Dictionary = run.stats.duplicate()
	run.weapon_id = forge_book("storm")
	var stats: Dictionary = run.projectile_stats()
	check(stats.get("element") == "storm" and stats.get("resonance") == 2.0, "a storm book resonates with two storm relics")
	check(float(stats.get("chain", 0)) >= float(storm.chain) + 2.0, "Thunderhead: lightning leaps further with resonance")
	run.inventory = ["winter_mint", "deep_freeze"]
	run.rebuild_stats()
	run.weapon_id = forge_book("frost")
	var cold: Dictionary = run.projectile_stats()
	var target = foe()
	land(target, cold)
	land(target, cold)
	check(target.frozen > 0, "Deep Cold: quick frost hits freeze a foe solid")
	clear_foes()
	run.inventory = ["chili_oil"]
	run.rebuild_stats()
	run.weapon_id = forge_book("ember")
	var burning = foe(Vector3(0, 0, -3))
	var next = foe(Vector3(2.0, 0, -3))
	burning.apply_status(run.projectile_stats())
	burning.take_hit(9999.0, Vector3.ZERO)
	check(next.burn_time > 0, "Spreading Fire: a burning foe's fire leaps when it falls")
	clear_foes()
	run.inventory = []
	run.rebuild_stats()
	run.weapon_id = "candle"

func forge_book(element: String) -> String:
	var forge = load("res://scripts/items/forge.gd")
	for seed_value in range(1, 400):
		var id: String = forge.id_for(seed_value, 0)
		if forge.lookup(id).element == element: return id
	return "candle"

func floor_and_items() -> void:
	var wading = foe()
	game.residue.add("water", wading.global_position, 1.5, true)
	wading.dot_tick = 0.0
	wading.update_sim(.05)
	check(wading.marks.has("tide"), "a foe standing in water is soaked")
	land(wading, {"chill": 1.0, "hit": 10.0})
	check(wading.frozen > 0, "frost on a foe standing in water freezes it")
	clear_foes()
	var kettle: Dictionary = root.get_node("Content").record("actives", "copper_kettle")
	check(float(kettle.params.effects.get("wet", 0)) > 0, "the Copper Kettle soaks what its holder strikes")
	var waiting = foe()
	land(waiting, {"wet": 1.0, "hit": 1.0})
	var globe: Dictionary = root.get_node("Content").record("actives", "winter_globe")
	waiting.age += .2
	load("res://scripts/items/active_items.gd").activate(game, globe)
	check(waiting.frozen > 0, "the Winter Globe freezes soaked foes")
	clear_foes()

func presentation() -> void:
	var ui = game.ui
	run.inventory = ["chili_oil"]
	run.profile.combos.erase("p:powder_keg")
	check(ui.combination_hint({"kind": "item", "id": "firecracker"}) == "SOMETHING YOU CARRY ANSWERS THIS", "an unfound pairing is only hinted at on its card")
	run.discover("p:powder_keg")
	check(ui.combination_hint({"kind": "item", "id": "firecracker"}) == "COMPLETES POWDER KEG", "a found pairing is named on its card")
	run.weapon_id = forge_book("ember")
	check(ui.combination_hint({"kind": "item", "id": "living_coal"}) == "SINGS WITH YOUR SPELLBOOK", "a resonant relic says so on its card")
	run.inventory = ["chili_oil", "firecracker"]
	game.fps.update_view(.016)
	check(game.fps.weapon_shape.get_node("Marks").has_node("Pairing_powder_keg"), "a completed pairing turns as a sigil above the book")
	ui.journal_tab = "combos"
	ui.journal_page = 0
	ui.show_screen("journal")
	await process_frame
	check(ui.journal_page_count() == ceili(S.all_ids().size() / 6.0), "the journal pages through every combination")
	ui.show_screen("play")
	run.inventory = []
	run.weapon_id = "candle"
