extends SceneTree
## Versioned scarcity, strictly chest-sourced actives, and once-only vertical
## reward transactions. Legacy rules remain available for existing runs.
var checks := 0
var failures := 0
var game
var run
var content
var Balance
var DropTables
var Actions

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("exercise")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func currency(drops: Array) -> int:
	var total := 0
	for drop in drops:
		if not drop.has("def"): continue
		var definition: Dictionary = content.record("pickups",drop.def)
		if definition.kind == "coin": total += int(definition.value)
	return total

func exercise() -> void:
	run = root.get_node("Run")
	content = root.get_node("Content")
	Balance = load("res://scripts/items/expedition_balance.gd")
	DropTables = load("res://scripts/items/drops.gd")
	Actions = load("res://scripts/interactions/game_actions.gd")
	var settings = root.get_node("Settings")
	settings.set_value("sound",false)
	settings.set_value("music",false)
	var original_rng: int = run.rng.state
	for version in [1,2]:
		check(not Balance.active_new_run(version),"older expeditions keep their rules")
		check(Balance.table_id("enemy_common",version)=="enemy_common","old source table retains its identity")
	check(Balance.active_new_run(3),"new expeditions use scarcity")
	var old_coins := 0
	var new_coins := 0
	var old_heals := 0
	var new_heals := 0
	var previous := RandomNumberGenerator.new()
	var modern := RandomNumberGenerator.new()
	previous.seed = 66122
	modern.seed = 66122
	for i in 10000:
		var old: Array = DropTables.roll("enemy_common",previous,0,0,"",2)
		var fresh: Array = DropTables.roll("enemy_common",modern,0,0,"",3)
		old_coins += currency(old)
		new_coins += currency(fresh)
		old_heals += old.filter(func(drop):return drop.get("def","")=="half_heart").size()
		new_heals += fresh.filter(func(drop):return drop.get("def","")=="half_heart").size()
	check(old_coins>3700 and old_coins<4300,"legacy expected coin rate stays about .4")
	check(new_coins>1750 and new_coins<2250,"new enemy coin rate is about .2")
	check(new_coins<old_coins*.6,"combat money is materially scarcer")
	check(new_heals<old_heals*.4,"incidental combat healing is materially scarcer")
	var active_count := 0
	var blank_count := 0
	modern.seed = 92674
	for i in 4000:
		var chest: Array = DropTables.roll("normal_chest",modern,0,0,"",3,"chest")
		if chest.any(func(drop): return drop.has("active")): active_count += 1
		else: blank_count += 1
	check(active_count>600 and active_count<850,"normal challenge chest has a chance of active equipment")
	check(blank_count>3000,"optional room does not guarantee active equipment")
	for table in content.families.drop_tables:
		var rng := RandomNumberGenerator.new()
		rng.seed = 394
		for i in 8:
			check(DropTables.roll(table.id,rng,0,0,"",3).all(func(drop):return not drop.has("active")),"ordinary drop call cannot create active equipment: "+table.id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for source in ["enemy","room_clear","breakable",""]:
		check(DropTables.roll("secret_cache",rng,0,0,"",3,source).all(func(drop):return not drop.has("active")),"chest table alone cannot bypass acquisition source")
	check(run.rng.state==original_rng,"balance simulation does not spend gameplay RNG")
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.set_physics_process(false)
	game.set_process(false)
	game.start_run("candle",90217,false)
	run.generator_version=3
	game.paused=false
	await process_frame
	var data: Dictionary=run.rooms[run.current_room]
	data.cleared=true
	game.room.set_open(true)
	var at: Vector3=game.player.position+Vector3(1.8,0,0)
	var chest: Dictionary=game.actions.award_clear_chest(data,at)
	check(not chest.is_empty() and chest.table=="normal_chest" and not chest.locked,"vertical challenge awards an ordinary unlocked chest")
	check(chest.height==snappedf(at.y,.001),"chest reward persists its actual level height")
	var count: int=data.chests.size()
	check(game.actions.award_clear_chest(data,at).id==chest.id and data.chests.size()==count,"repeated clear notification cannot duplicate its chest")
	check(run.coins==Balance.START_COINS,"new expeditions start with scarce spending money")
	var before_gild: int=data.get("pickups",[]).size()
	var gilded = game.spawn_enemy(game.player.position+Vector3(3,0,0),"mote","scarcity:gilded")
	for hit in 6: gilded.shed_coin()
	check(gilded.gilded_drops==2 and data.get("pickups",[]).size()==before_gild+2,"new gilded foe sheds at most two coins")
	var repeated = game.spawn_enemy(game.player.position+Vector3(3,0,1),"mote","scarcity:gilded")
	for hit in 6: repeated.shed_coin()
	check(data.get("pickups",[]).size()==before_gild+2,"restarted gilded foe cannot repeat credited coins")
	check(gilded.timer/gilded.tempo()>=1.14,"higher cadence preserves an entering player's first reaction window")
	var modern_health: float=gilded.max_hp
	var modern_speed: float=gilded.speed
	var modern_tempo: float=gilded.tempo()
	run.generator_version=2
	var legacy_foe=game.spawn_enemy(game.player.position+Vector3(-3,0,0),"mote","scarcity:legacy")
	check(modern_health>legacy_foe.max_hp and modern_health<legacy_foe.max_hp*1.13,"actual newer foe health grows modestly from the legacy setup")
	check(modern_speed>legacy_foe.speed and modern_speed<legacy_foe.speed*1.14,"actual newer foe running speed remains bounded")
	check(modern_tempo>legacy_foe.tempo() and modern_tempo<=legacy_foe.tempo()*1.23,"actual newer attacks have higher cadence")
	for hit in 6: legacy_foe.shed_coin()
	check(legacy_foe.gilded_drops==4,"older runs retain the four-coin gilded cap")
	run.generator_version=3
	gilded.restless=false
	gilded.aura_haste=0
	gilded.windup=.6
	gilded.update_sim(.3)
	check(absf(gilded.windup-.3)<.001,"difficulty accelerates attack spacing without shortening visible warnings")
	var before_coins: int=run.coins
	check(game.actions.open_chest(chest.id).ok,"cleared challenge chest can be opened")
	var drop_count: int=data.get("pickups",[]).size()+data.get("items",[]).size()
	check(not game.actions.open_chest(chest.id).ok,"opened reward chest cannot pay twice")
	check(data.get("pickups",[]).size()+data.get("items",[]).size()==drop_count and run.coins==before_coins,"duplicate opening creates no loot or currency")
	check(data.chests.filter(func(record):return record.id==chest.id).size()==1,"reward ledger contains exactly one chest")
	check(run.load_run(),"reward transaction reloads")
	check(run.rooms[run.current_room].challenge_chest_awarded and Actions.find_record(run.rooms[run.current_room].chests,chest.id).opened,"saved clear chest remains opened with its ledger")
	var separated_drop=game.spawn_pickup(game.player.position,"copper_coin")
	separated_drop.position=game.player.position-Vector3.UP*2.6
	var separated_coins: int=run.coins
	check(not game.actions.collect_pickup(separated_drop.drop_id).ok and run.coins==separated_coins,"a cellar pickup cannot be collected through the floor above")
	separated_drop.position=game.player.position+Vector3.UP*.2
	check(game.actions.collect_pickup(separated_drop.drop_id).ok and run.coins==separated_coins+1,"the same pickup collects at the player's actual level")
	# Exercise the real offer builders, rather than only their shared sanitizer.
	data=run.rooms[run.current_room]
	var original_type: String=data.type
	for kind in ["combat","boss","treasure","shop","dark"]:
		data.type=kind
		data.erase("offers")
		if kind=="dark": game.ensure_dark_offers()
		else: game.ensure_offers(kind=="boss")
		check(data.offers.all(func(offer): return offer.kind in ["item","weapon"]),"actual "+kind+" rewards keep actives in the chest channel")
		check(data.offers.all(func(offer): return content.item_by_id.has(offer.id) if offer.kind=="item" else root.get_node("Collection").weapon_available(offer.id) or offer.id.begins_with("forged:")),"actual "+kind+" offers resolve to valid equipment")
		data.offers=[{"kind":"active","id":"moth_jar","price":15},{"kind":"weapon","id":"candle","price":14}]
		if kind=="dark": game.ensure_dark_offers()
		else: game.ensure_offers()
		check(data.offers[0].kind=="item" and data.offers[1].kind=="weapon","cached "+kind+" active offer migrates without replacing a weapon")
	data.type=original_type
	data.erase("offers")
	var carried: Dictionary={"instance":"legacy-carried","def":"moth_jar","source":"legacy"}
	run.active_item=carried.duplicate(true)
	run.cooldowns["moth_jar"]=17.0
	var before_inventory: int=run.inventory.size()
	var before_active_drops: int=data.get("items",[]).size()
	data.claimed=false
	data.offers=[{"kind":"active","id":"gale_bell","price":15}]
	run.coins=20
	game.chosen_reward_shop=true
	game.chosen_reward_dark=false
	game.choose_offer(0)
	check(run.inventory.size()==before_inventory+1 and run.coins==5,"stale shop selection is sanitized before payment and grants only a passive relic")
	check(run.active_item==carried and run.cooldowns["moth_jar"]==17.0 and data.get("items",[]).size()==before_active_drops,"source separation preserves carried equipment and its cooldown")
	data.erase("offers")
	check(not Balance.combat_relic_due({"type":"combat"},{}) and Balance.combat_relic_due({"type":"boss"},{}),"ordinary fights never award relics; the boss always does")
	check(not Balance.combat_relic_due({"type":"combat"},{"combat":{"clear_reward":"relic"}}),"one combat relic exhausts the floor allowance")
	check(not Balance.combat_relic_due({"type":"combat","vertical_challenge":true},{}),"vertical chest reward does not also create a passive-relic pedestal")
	var state_before: int=run.rng.state
	var old_offers: Array=[{"kind":"active","id":"moth_jar","price":15},{"kind":"weapon","id":"candle","price":14}]
	var sanitized: Array=Balance.sanitize_offers(old_offers,413)
	check(sanitized[0].kind=="item" and content.item_by_id.has(sanitized[0].id),"old unopened active offer becomes a passive relic")
	check(sanitized[1]==old_offers[1] and old_offers[0].kind=="active","migration preserves weapon offer and input record")
	check(Balance.sanitize_offers(old_offers,413)==sanitized and run.rng.state==state_before,"offer separation is deterministic and does not shift run RNG")
	for depth in range(1,6):
		check(Balance.foe_health(depth,false)<=1.13,"difficulty avoids inflated enemy bullet sponges")
		check(Balance.foe_tempo(depth)>1 and Balance.foe_tempo(depth)<=1.23,"pressure grows through bounded attack cadence")
		check(Balance.foe_speed(depth)<1.14,"chasing speed remains bounded")
	# Remove incidental relic healing before checking the floor transition.
	run.inventory=[]
	run.rebuild_stats()
	run.hp=1.0
	game.use_pedestal({"kind":"rest"})
	check(run.hp==2.0,"a modern rest hearth restores only one health")
	run.hp=1.0
	run.next_floor()
	check(run.hp==1.0,"new floor transitions no longer supply free healing")
	run.generator_version=2
	run.hp=1.0
	run.next_floor()
	check(run.hp==3.0,"older expeditions retain their original floor-transition heal")
	game.queue_free()
	await process_frame
	print("EXPEDITION REWARDS: %d checks, %d failures; enemy coins old=%d new=%d /10000, chest actives=%d/4000" % [checks,failures,old_coins,new_coins,active_count])
	quit(0 if failures==0 else 1)
