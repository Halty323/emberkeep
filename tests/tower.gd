extends SceneTree
## The climb and what fills it: seeded five-floor plans from eight floor
## themes, twists, theme hazards and residue, every new foe and boss, forged
## weapons, the dark store and the coin economy. Run through tools/test.sh
## with disposable storage.
var checks = 0
var failures = 0
var run
var catalog
var game
var Forge
var Foes
var Light
var Generator
var Enemy
var Drops

func _initialize() -> void:
	call_deferred("test_tower")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func step(frames := 1) -> void:
	for frame in frames:
		game._physics_process(1.0 / 60.0)

func clear_combat(keep := true) -> void:
	for enemy in game.enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.alive = false
			enemy.queue_free()
	game.enemies.clear()
	for shot in game.shots.duplicate():
		if is_instance_valid(shot): shot.queue_free()
	game.shots.clear()
	if keep:
		var keeper = game.spawn_enemy(Vector3(-7.5, 0, -5.5), "ember")
		keeper.timer = 1.0e9

## A sealed room of a floor theme at a depth, its own foes cleared away.
func arena(theme: String, depth := 2, kind := "combat", twist := "", keep_foes := false) -> String:
	game.start_run("candle", 61000 + depth, false)
	run.floor_plan = [theme, theme, theme, theme, theme]
	run.floor_twists = [twist, twist, twist, twist, twist]
	run.floor_number = depth
	run.generate_floor()
	for id in run.rooms:
		var data = run.rooms[id]
		if data.type != kind or (data.cells.size() != 1 and kind != "boss"): continue
		data.cleared = false
		run.current_room = id
		game.enter_room(Vector3(0, 0, 2))
		if kind != "boss" and not keep_foes: clear_combat()
		for prop in game.room.props.keys(): game.room.break_prop(prop)
		await process_frame
		game.player.place(Vector3(0, 0, 4))
		run.stats.max_hp = 900
		run.hp = 900
		return id
	return ""

## Fells a foe whatever it is doing (hanging, submerged or warded).
func slay(foe) -> void:
	for blow in 4:
		if is_instance_valid(foe) and foe.alive:
			foe.targetable = true
			foe.take_hit(1.0e6, Vector3.ZERO, false, false, "shot")
	if is_instance_valid(foe) and foe.alive:
		foe.hp = 0.0
		foe.die()

func spawn(kind: String, at := Vector3(0, 0, -2)):
	var foe = game.spawn_enemy(at, kind)
	foe.place(at)
	return foe

func tiles_of(kind: String) -> int:
	return game.residue.tiles.values().filter(func(tile): return tile.kind == kind).size()

func test_tower() -> void:
	run = root.get_node("Run")
	catalog = root.get_node("Content")
	Forge = load("res://scripts/items/forge.gd")
	Foes = load("res://scripts/foes/foes.gd")
	Light = load("res://scripts/dungeon/floor_light.gd")
	Generator = load("res://scripts/dungeon/floor_generator.gd")
	Enemy = load("res://scripts/enemy.gd")
	Drops = load("res://scripts/items/drops.gd")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	test_catalog()
	test_climb()
	test_light()
	test_rosters()
	await test_hazards()
	await test_residue()
	await test_foes()
	await test_bosses()
	await test_twists()
	test_forge()
	await test_firing()
	await test_archetypes()
	await test_relic_powers()
	await test_dark_store()
	test_coins()
	game.queue_free()
	await process_frame
	await process_frame
	print("EMBERKEEP TOWER TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_catalog() -> void:
	check(catalog.errors.is_empty(), "the content catalog loads cleanly: %s" % "; ".join(catalog.errors))
	var floors: Array = catalog.families.floors
	check(floors.size() == 8, "eight floor themes")
	check(floors.filter(func(t): return t.band == "first").size() == 2 and floors.filter(func(t): return t.band == "middle").size() == 5
		and floors.filter(func(t): return t.band == "summit").size() == 1, "two first floors, five middle floors and one summit")
	var bosses := {}
	for theme in floors:
		bosses[theme.boss.kind] = true
		check(Foes.known(theme.boss.kind) and Foes.SCRIPTS.has(theme.boss.kind), "floor %s has a scripted boss" % theme.id)
		check(theme.roster.any(func(entry): return entry[0] not in Foes.CLASSICS), "floor %s brings foes of its own" % theme.id)
	check(bosses.size() == 8, "every floor has its own boss")
	check(catalog.record("climbs", "tower").bands.size() == 5, "a climb is five floors")
	# Broken data is rejected rather than played.
	var saved: Array = catalog.families.floors.duplicate(true)
	var broken: Dictionary = saved[0].duplicate(true)
	broken.roster = [["no_such_foe", 1.0, 2]]
	broken.hazard = "lava"
	broken.boss = {"kind": "nobody", "name": "", "intro": []}
	var problems = catalog.validate_floor(broken)
	check(problems.size() >= 3, "unknown foes, hazards and bosses are rejected")
	var short_climb = catalog.validate_climb({"id": "x", "bands": ["summit", "summit"]})
	check(not short_climb.is_empty(), "a climb that needs more themes than exist is rejected")
	check(catalog.items.filter(func(item): return item.rarity == "dark").size() == 9, "nine dark relics")

func test_climb() -> void:
	var plans := {}
	var seen := {}
	for seed_value in range(1, 301):
		run.seed_value = seed_value
		run.plan_climb("tower")
		var plan: Array = run.floor_plan.duplicate()
		plans[str(plan)] = true
		for id in plan: seen[id] = true
		if seed_value <= 40:
			check(plan.size() == 5, "seed %d climbs five floors" % seed_value)
			check(catalog.record("floors", plan[0]).band == "first" and plan[4] == "hearth", "seed %d starts low and ends at the hearth" % seed_value)
			var middle = plan.slice(1, 4)
			check(middle.all(func(id): return catalog.record("floors", id).band == "middle"), "seed %d climbs middle floors between" % seed_value)
			var unique := {}
			for id in plan: unique[id] = true
			check(unique.size() == 5, "seed %d never repeats a floor" % seed_value)
			var twists: Array = run.floor_twists
			check(twists.slice(1).all(func(t): return t != ""), "seed %d draws a twist on every floor past the first" % seed_value)
			var named := {}
			for t in twists:
				if t != "":
					check(not named.has(t), "seed %d never repeats a twist" % seed_value)
					named[t] = true
			for i in plan.size():
				check(twists[i] not in catalog.record("floors", plan[i]).get("exclude_twists", []), "seed %d floor %d twist suits its theme" % [seed_value, i + 1])
		var again = run.floor_plan.duplicate()
		run.plan_climb("tower")
		if seed_value <= 40: check(run.floor_plan == again, "seed %d plans the same climb every time" % seed_value)
	check(seen.size() == 8, "every theme turns up across many seeds")
	check(plans.size() > 60, "climbs vary widely by seed (%d different)" % plans.size())
	var first_twists = 0
	for seed_value in range(1, 301):
		run.seed_value = seed_value
		run.plan_climb("tower")
		if run.floor_twists[0] != "": first_twists += 1
	check(first_twists > 60 and first_twists < 160, "a first floor sometimes draws a twist (%d of 300)" % first_twists)
	# A run saves its climb, and a save from before themes climbs the old tower.
	game.start_run("candle", 4242, false)
	var plan: Array = run.floor_plan.duplicate()
	var twists: Array = run.floor_twists.duplicate()
	run.save_run()
	run.floor_plan = []
	check(run.load_run() and run.floor_plan == plan and run.floor_twists == twists, "the climb survives save and load")
	check(run.climb_length() == 5 and not run.last_floor(), "a new run is five floors deep")
	var saved = JSON.parse_string(FileAccess.get_file_as_string("user://run.json"))
	saved.erase("floor_plan")
	saved.erase("floor_twists")
	var file = FileAccess.open("user://run.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()
	check(run.load_run() and run.floor_plan == ["cellar", "halls", "hearth"] and run.climb_length() == 3, "a save from before themes climbs the old three floors")
	run.floor_number = 3
	check(run.last_floor() and run.theme_id() == "hearth", "the old tower still ends at the hearth")
	saved.floor_plan = ["cellar", "atlantis"]
	file = FileAccess.open("user://run.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()
	check(not run.load_run(), "a save naming an unknown floor is refused")
	game.start_run("candle", 4243, false)
	check(run.theme().arrival.size() == 2, "the first floor names its arrival")
	run.next_floor()
	check(run.floor_number == 2 and run.theme_id() == run.floor_plan[1] and run.theme_id() in run.profile.floors, "climbing reaches the planned theme and records it")

func test_light() -> void:
	var plain := {"light": {}}
	for pair in [[0.0, 1], [.5, 2], [1.0, 3]]:
		var blended = Light.for_floor(pair[0], plain)
		var reference: Dictionary = Light.profile(pair[1])
		check(blended.keys().all(func(key): return str(blended[key]) == str(reference[key])), "height %.1f matches the old floor %d light" % [pair[0], pair[1]])
	var quarter = Light.for_floor(.25, plain)
	check(quarter.ambient > Light.profile(1).ambient and quarter.ambient < Light.profile(2).ambient, "the tower brightens between floors")
	var tinted = Light.for_floor(.25, catalog.record("floors", "kiln"))
	check(tinted.ambient_color == Color("c0846a") and is_equal_approx(tinted.ambient, quarter.ambient), "a theme tints colours but not brightness")
	var dim = Light.for_floor(1.0, plain, "dim")
	check(dim.lit < Light.profile(3).lit and dim.ambient < Light.profile(3).ambient, "a guttering floor has fewer lanterns and less light")
	for theme in catalog.families.floors:
		for height in [0.0, .25, .5, .75, 1.0]:
			var light = Light.for_floor(height, theme)
			check(light.ambient < .36 and light.key < .45, "%s at height %.2f keeps the contrast limit" % [theme.id, height])

func test_rosters() -> void:
	var plan = ["cistern", "kiln", "crypt", "belfry", "hearth"]
	var roster: Array = Foes.roster_for("crypt", 3, plan)
	var kinds = roster.map(func(entry): return entry[0])
	check("lurker" in kinds and "clinker" in kinds and "mourner" in kinds, "a floor brings back the foes of floors climbed before it")
	check("cog" not in kinds, "foes of floors still above do not appear")
	var lurker = roster.filter(func(entry): return entry[0] == "lurker")[0]
	check(lurker[2] == 1 and lurker[1] < 1.0, "returning foes come rarely, one at a time")
	var gen = RandomNumberGenerator.new()
	var elites = 0
	for i in 300:
		gen.seed = i * 31 + 7
		for entry in Foes.compose(Foes.roster_for("archive", 4, plan), Foes.elite_chance(4), 6, gen):
			check(entry.kind not in Foes.BOSSES, "encounters never place a boss")
			if entry.kind == "pages": check(entry.elite == "", "a flock of pages is never an elite")
			if entry.elite != "": elites += 1
	check(elites > 300, "deeper floors dress many foes as elites (%d)" % elites)
	check(Foes.elite_chance(1) == 0.0 and Foes.elite_chance(5) > Foes.elite_chance(2), "elites grow with depth")
	check(Foes.boss_name("sluice") == "THE SLUICE MOTHER", "a boss is named by its floor")

func test_hazards() -> void:
	await arena("cistern")
	check(tiles_of("water") > 20, "the cistern lays standing water")
	check(game.residue.tiles.values().all(func(tile): return tile.life < 0), "a floor's own pools last")
	await arena("crypt")
	check(tiles_of("wax") > 12, "the crypt lays wax")
	await arena("archive")
	check(tiles_of("ice") > 20, "the archive lays ice")
	var ice = tiles_of("ice")
	step(60 * 12)
	check(tiles_of("ice") >= ice, "the archive's ice never melts by itself")
	await arena("kiln")
	check(game.hazards.vents.size() >= 2, "the kiln's fights have vents")
	var erupted = false
	for i in 60 * 8:
		step()
		if tiles_of("fire") > 0: erupted = true
	check(erupted, "vents breathe fire on their rhythm")
	await arena("belfry")
	check(game.hazards.pendulums.size() >= 1, "the belfry's fights have pendulums")
	var pendulum: Dictionary = game.hazards.pendulums[0]
	var start: Vector3 = pendulum.blade.position
	step(40)
	check(pendulum.blade.position.distance_to(start) > .3, "a pendulum swings while the fight is on")
	var foe = spawn("brute", pendulum.node.position)
	# Keep the damage target under the blade. Its pathfinding/throwing AI
	# can otherwise leave the swing before contact, depending on nav sync.
	foe.speed = 0.0
	foe.timer = 1.0e9
	var hp: float = foe.hp
	for i in 60 * 4: step()
	check(not is_instance_valid(foe) or not foe.alive or foe.hp < hp, "a pendulum cuts foes too")
	clear_combat(false)
	step(2)
	check(game.room.open, "the cleared belfry room opens")
	var rest: Vector3 = pendulum.blade.position
	step(40)
	check(pendulum.blade.position.distance_to(rest) < .01, "pendulums stop once the room is cleared")
	await arena("halls", 2, "combat", "flooded")
	check(tiles_of("water") > 10, "a flooded floor stands in water")
	await arena("cellar", 2, "combat", "overgrown")
	check(tiles_of("moss") > 10, "an overgrown floor grows moss")
	await arena("cellar", 1, "start")
	check(game.residue.tiles.is_empty(), "the cellar keeps bare stone")

func test_residue() -> void:
	await arena("cellar", 1)
	var field = game.residue
	var at = Vector3(-3, 0, 1)
	field.add("water", at, 1.6, true)
	check(is_equal_approx(field.slows(at), .8), "water drags at the feet")
	field.react(at, .7, {"chill": 1.0})
	check(field.kind_at(at) == "ice", "chill freezes water")
	field.react(at, .7, {"burn": 1.0})
	check(field.kind_at(at) == "water", "burning ice melts back to water")
	field.react(at, .7, {"burn": 1.0})
	var steam = field.cloud_at(at)
	check(steam >= 0 and field.clouds[steam].kind == "steam", "fire on water boils it into steam")
	field.react(at, .7, {"burn": 1.0})
	check(field.cloud_at(at) >= 0, "steam does not explode like spores")
	var wet = spawn("brute", Vector3(-3, 0, 1))
	var other = spawn("brute", Vector3(-3.8, 0, 1.2))
	var dry = spawn("brute", Vector3(4, 0, -3))
	var hp_wet: float = other.hp
	var hp_dry: float = dry.hp
	check(field.shock(wet.global_position, 10.0) >= 2, "lightning runs through the whole pool")
	check(other.hp < hp_wet and dry.hp == hp_dry, "only foes in the water are struck")
	clear_combat()
	field.add("ink", Vector3(3, 0, 2), 1.2, true)
	check(is_equal_approx(field.slows(Vector3(3, 0, 2)), .6), "ink drags harder")
	field.react(Vector3(3, 0, 2), .7, {"burn": 1.0})
	check(field.kind_at(Vector3(3, 0, 2)) == "", "ink burns away")
	var lit = spawn("cinderling", Vector3(-3, 0, 1))
	lit.apply_status({"burn": 1.0})
	field.tick = 0.0
	field.update_sim(.01)
	check(lit.burn_time == 0.0, "water puts a burning foe out")

func test_foes() -> void:
	await arena("cistern")
	game.residue.add("water", Vector3(0, 0, -2), 2.4, true)
	var lurker = spawn("lurker", Vector3(0, 0, -2))
	step(3)
	check(not lurker.targetable and lurker.submerged, "a lurker in water cannot be struck")
	var hp: float = lurker.hp
	lurker.shocked(5.0)
	check(lurker.hp < hp and not lurker.targetable, "lightning reaches a lurker under water")
	game.player.place(Vector3(0, 0, -.4))
	var surfaced = false
	for i in 180:
		step()
		if lurker.targetable: surfaced = true
	check(surfaced, "a lurker surfaces to lunge")
	await arena("cellar", 2)
	var bailer = spawn("bailer", Vector3(0, 0, -4))
	bailer.timer = 0.0
	var water_before = tiles_of("water")
	for i in 150: step()
	check(tiles_of("water") > water_before, "a bailer's pail leaves water where it lands")
	await arena("crypt")
	var mourner = spawn("mourner", Vector3(6, 0, -4))
	for i in game.room.lanterns.size(): game.room.set_lantern(i, false)
	step(2)
	check(not mourner.targetable and mourner.shrouded and mourner.visual.get_child(0).visible,
		"a mourner outside light stays faintly visible but cannot be struck")
	mourner.place(game.player.global_position + Vector3(1.4, 0, 0))
	step(2)
	check(mourner.targetable, "a mourner in the player's glow can be struck")
	game.kindle_heat = 8.0
	var touched = false
	for i in 120:
		mourner.place(game.player.global_position + Vector3(.3, 0, 0))
		step()
		if game.kindle_heat == 0.0: touched = true
	check(touched, "a mourner's touch takes the kindle")
	clear_combat()
	var tallow = spawn("tallow")
	var full: float = tallow.hp
	tallow.chill_time = 2.0
	tallow.take_hit(10, Vector3.ZERO)
	check(is_equal_approx(full - tallow.hp, 5.0 * (1.25 if tallow.exposed else 1.0)), "chilled wax turns half of a blow")
	tallow.chill_time = 0.0
	tallow.apply_status({"burn": 1.0})
	var wax = tiles_of("wax")
	for i in 90: step()
	check(tiles_of("wax") > wax and tallow.visual.scale.x < 1.0, "a burning golem melts and sheds wax")
	await arena("archive")
	var pages = spawn("pages")
	step(2)
	check(pages.flock.size() == 5 and game.enemies.filter(func(e): return e.kind == "pages").size() == 5, "a page brings its flock")
	pages.apply_status({"burn": 1.0})
	check(pages.flock.filter(func(p): return p.burn_time > 0).size() > 1, "fire jumps from page to page")
	clear_combat()
	var scrivener = spawn("scrivener", Vector3(0, 0, -5))
	scrivener.timer = 0.0
	for i in 120: step()
	check(tiles_of("ink") > 0, "a scrivener's glyph leaves ink")
	await arena("kiln")
	var clinker = spawn("clinker")
	var start: float = clinker.hp
	clinker.take_hit(10, Vector3.ZERO)
	var cold_loss = start - clinker.hp
	clinker.apply_status({"burn": 1.0})
	var hot_start: float = clinker.hp
	clinker.take_hit(10, Vector3.ZERO)
	check(hot_start - clinker.hp > cold_loss * 3.0, "a clinker's shell turns blows until it burns")
	clear_combat()
	var bellows = spawn("bellows", Vector3(0, 0, -1))
	bellows.aim = Vector3(0, 0, 1)
	var shot = game.spawn_shot(Vector3(0, .65, 1.5), Vector3(0, 0, -1), 5, 0.01, {}, Color.WHITE, true)
	bellows.windup_done()
	check(not is_instance_valid(shot) or not shot.alive, "a bellows' gust blows shots away")
	check(game.player.push.length() > 1.0, "a bellows' gust shoves the player")
	await arena("belfry")
	var cog = spawn("cog")
	var at: Vector3 = cog.global_position
	cog.timer = 10.0
	step(20)
	check(cog.global_position.distance_to(at) < .05, "a cog stands still between ticks")
	cog.timer = 0.0
	step(20)
	check(cog.global_position.distance_to(at) > .5, "a cog lunges on the tick")
	clear_combat()
	var chime = spawn("chime", Vector3(0, 0, -2))
	chime.ring()
	var ring: Dictionary = chime.rings[0]
	ring.open.clear()
	var hit_hp: float = run.hp
	game.player.invulnerability = 0.0
	var hurt = false
	for i in 120:
		step()
		if run.hp < hit_hp: hurt = true
	check(hurt, "a chime's ring hurts where it has no gap")

func test_bosses() -> void:
	for theme in catalog.families.floors:
		await arena(theme.id, 3, "boss")
		var boss = game.enemies.filter(func(e): return e.boss)[0] if game.enemies.any(func(e): return e.boss) else null
		check(boss != null and boss.kind == theme.boss.kind, "the %s boss is %s" % [theme.id, theme.boss.kind])
		if boss == null: continue
		check(boss.max_hp > float(boss.stats()[0]) * 1.2, "%s grows with depth" % boss.kind)
		for i in 60 * 6: step()
		check(boss.alive, "%s survives six seconds of its own fight" % boss.kind)
	await arena("cistern", 2, "boss")
	var sluice = game.enemies.filter(func(e): return e.boss)[0]
	sluice.state_time = 0.0
	step(2)
	check(sluice.state == "flood" and tiles_of("water") > 60, "the Sluice Mother floods the room")
	check(not sluice.targetable, "she cannot be struck under the flood")
	var islands = game.room.lanterns.all(func(l): return game.residue.kind_at(l.at) != "water")
	check(islands, "the lanterns keep dry islands")
	var hp: float = sluice.hp
	sluice.shocked(10)
	check(sluice.hp < hp, "lightning in the flood reaches her")
	var tile = sluice.flooded.keys().filter(func(t): return game.residue.tiles.get(t, {}).get("kind", "") == "water")[0]
	sluice.place(game.residue.center(tile))
	game.residue.react(sluice.global_position, 1.0, {"chill": 1.0})
	step(2)
	check(sluice.pinned > 0 and sluice.targetable, "frost in the flood pins her")
	sluice.pinned = 0.0
	sluice.state_time = 0.0
	step(2)
	check(sluice.state == "drained" and sluice.exposed and sluice.targetable, "drained, she is stranded and exposed")
	await arena("crypt", 2, "boss")
	var chandler = game.enemies.filter(func(e): return e.boss)[0]
	chandler.pour(Vector3(1, 0, 0))
	var wax = tiles_of("wax")
	check(wax > 4, "the Chandler pours lines of wax")
	chandler.set_alight()
	check(tiles_of("wax") == 0 and tiles_of("fire") >= wax, "her wick sets all the wax alight")
	chandler.hp = chandler.max_hp * .45
	step(2)
	check(game.enemies.filter(func(e): return e.kind == "effigy").size() == 2, "below half she casts two effigies")
	var effigy = game.enemies.filter(func(e): return e.kind == "effigy")[0]
	var cold_scale: float = effigy.damage_scale("shot")
	effigy.burn_time = 1.0
	check(cold_scale == 1.0 and effigy.damage_scale("shot") == 3.0, "wax effigies melt in fire")
	await arena("archive", 2, "boss")
	var archivist = game.enemies.filter(func(e): return e.boss)[0]
	check(is_equal_approx(archivist.damage_scale("shot"), .3), "the Archivist's frost turns most of a shot")
	archivist.apply_status({"burn": 1.0})
	check(archivist.damage_scale("shot") > 1.0, "burning melts her frost")
	archivist.hp = archivist.max_hp * .45
	step(2)
	check(archivist.frozen_floor and tiles_of("ice") > 60, "below half the floor freezes over")
	await arena("kiln", 2, "boss")
	var kiln = game.enemies.filter(func(e): return e.boss)[0]
	check(not kiln.door_open and kiln.damage_scale("shot") < .2, "the Kilnmother's shut door turns blows")
	kiln.door_time = 0.0
	step(2)
	check(kiln.door_open and kiln.damage_scale("shot") > 1.0, "her open door bares the heart")
	var open_for: float = kiln.door_time
	kiln.apply_status({"chill": 1.0})
	check(kiln.door_time > open_for, "chill on the open heart holds the door")
	await arena("belfry", 2, "boss")
	var keeper = game.enemies.filter(func(e): return e.boss)[0]
	keeper.minute = keeper.hour - .02
	step(2)
	check(keeper.strikes.size() == 1, "the Hour Keeper strikes when its hands meet")
	keeper.chill_time = 2.0
	var before: float = keeper.minute
	step(30)
	var chilled = keeper.minute - before
	keeper.chill_time = 0.0
	before = keeper.minute
	step(30)
	check(chilled < (keeper.minute - before) * .7, "chill slows its hands")

func test_twists() -> void:
	await arena("cellar", 3, "combat", "swarming", true)
	var swarm = game.enemies.filter(func(e): return not e.inert and e.kind == "mote")
	if not swarm.is_empty():
		# Floors 3 to 5 also make every foe tougher (scripts/items/synergies.gd).
		var reference = Enemy.KINDS.mote[0] * (1.0 + 2 * Enemy.FLOOR_HEALTH) * load("res://scripts/items/synergies.gd").TOUGHNESS[3]
		check(is_equal_approx(swarm[0].max_hp, reference * .8), "a swarming floor's foes are frailer")
	await arena("cellar", 3, "combat", "restless")
	var restless = spawn("mote")
	check(restless.tempo() > 1.1 and restless.speed > Enemy.KINDS.mote[1] * 1.2, "a restless floor's foes are quicker")
	await arena("cellar", 3, "combat", "gilded")
	check(run.coin_bonus() >= .6, "a gilded floor pays more")
	await arena("cellar", 3, "combat", "windswept")
	check(game.wind.length() > 1.0, "a windswept floor has a draught")
	var shot = game.spawn_shot(Vector3(0, .65, 0), Vector3(0, 0, -1), 1, 1.0, {}, Color.WHITE, true)
	var start: Vector3 = shot.global_position
	step(10)
	var drift = shot.global_position - start
	check(Vector2(drift.x, drift.z).dot(Vector2(game.wind.x, game.wind.z).normalized()) > .2, "shots drift with the draught")

func test_forge() -> void:
	var seen_names := {}
	var valid_stats = catalog.base_stats()
	for seed_value in range(1, 81):
		var starters: Array = Forge.starters(seed_value)
		check(starters.size() == 4, "seed %d forges four starters" % seed_value)
		var patterns := {}
		var elements := {}
		for weapon in starters:
			patterns[weapon.pattern] = true
			elements[weapon.element] = true
			seen_names[weapon.name] = true
			check(Forge.lookup(weapon.id) == weapon, "a forged id rebuilds its weapon")
			check(weapon.effects.keys().all(func(key): return valid_stats.has(key)), "%s uses only known effects" % weapon.name)
			check(not weapon.name.is_empty() and weapon.description.ends_with("."), "%s is named and described" % weapon.id)
			var single = float(weapon.damage) * int(weapon.count) * int(weapon.get("burst", 1)) / float(weapon.cooldown)
			check(single > 12.0 and single < 140.0, "%s deals a sane volume of damage (%.0f)" % [weapon.name, single])
			check(Color.html_is_valid(weapon.color) and weapon.cooldown >= .1, "%s has a colour and a cadence" % weapon.name)
		var flying: Array = starters.filter(func(w): return w.get("archetype", "projectile") == "projectile").map(func(w): return w.pattern)
		check(elements.size() == 4 and flying.size() == patterns.keys().filter(func(p): return p in Forge.PATTERNS).size(), "seed %d's starters never share an element, nor a flying pattern" % seed_value)
	check(seen_names.size() > 200, "forged names vary (%d)" % seen_names.size())
	check(Forge.starters(5) != Forge.starters(6), "different seeds forge different weapons")
	var dark = Forge.lookup(Forge.id_for(77, 12, 1))
	var plain = Forge.lookup(Forge.id_for(77, 12, 0))
	check(dark.traits.size() == 3 and plain.traits.size() == 2, "dark-forged weapons carry a third trait")
	for bad in ["forged:9:1:1:0", "forged:1:x:1:0", "forged:1:1:1", "nothing"]:
		check(not Forge.known(bad), "the bad id '%s' is refused" % bad)
	check(Forge.known("candle") and Forge.known("paint_sprayer"), "catalog weapons still resolve for older saves")
	game.start_run(Forge.id_for(9090, 2), 9090, false)
	check(run.weapon_id == Forge.id_for(9090, 2) and run.weapon().name == Forge.starters(9090)[2].name, "a run starts with a forged weapon")
	run.save_run()
	run.weapon_id = "candle"
	check(run.load_run() and run.weapon_id == Forge.id_for(9090, 2), "a forged weapon survives save and load")
	game.start_run("forged:1:nope", 9091, false)
	check(Forge.is_forged(run.weapon_id) and Forge.known(run.weapon_id), "an unknown weapon falls back to the seed's own")
	var collection = root.get_node("Collection")
	var starters: Array = collection.starters(31337)
	check(starters.slice(0, 4).all(func(w): return w.get("forged", false)), "the menu offers the seed's forged weapons")
	check(starters.all(func(w): return w.get("forged", false) or w.has("requires")), "the menu never offers the classic catalog weapons")
	game.ui.reforge()
	var first = game.ui.starter_weapon().id
	game.ui.reforge()
	var second = game.ui.starter_weapon().id
	check(first != second, "new weapons are forged with a new menu seed")
	check(game.ui.starter_weapon(run.daily_seed()).id == game.ui.starter_weapon(run.daily_seed()).id, "today's seed always forges the same weapons")

## Version 2 forges spells that do not fly (rays, lightning, eruptions) and
## flying spells of several looks, every roll logical.
func test_archetypes() -> void:
	var found := {}
	var odd := 0
	var kinds := {}
	for seed_value in range(1, 300):
		var starters: Array = Forge.starters(seed_value)
		for weapon in starters:
			var kind: String = weapon.archetype
			kinds[kind] = kinds.get(kind, 0) + 1
			if not found.has(kind): found[kind] = weapon
			if kind == "projectile" and not found.has(weapon.form): found[weapon.form] = weapon
			if not weapon.element in Forge.suited_elements(weapon.pattern): odd += 1
			if kind != "projectile" and not weapon.traits.all(func(t): return t in Forge.ARCHETYPES[kind].traits): odd += 1
			if kind == "projectile" and not (weapon.form in Forge.ELEMENT_FORMS[weapon.element] or weapon.form == Forge.PATTERN_FORMS[weapon.pattern][0]): odd += 1
			if kind == "projectile" and not weapon.form in Forge.PATTERN_FORMS[weapon.pattern]: odd += 1
		if failures > 0: break
	check(found.has("ray") and found.has("lightning") and found.has("eruption"), "the forge writes rays, lightning and eruptions")
	# Every kind is as likely as any other, among starters and in shops alike.
	var rolled := {}
	for i in 2000:
		var kind: String = Forge.lookup(Forge.id_for(5000 + i, 40 + i % 50, i % 2)).archetype
		rolled[kind] = rolled.get(kind, 0) + 1
	for kind in Forge.KINDS:
		check(absf(float(rolled.get(kind, 0)) / 2000.0 - .25) < .04, "shops roll %s a quarter of the time (%d / 2000)" % [kind, rolled.get(kind, 0)])
		check(absf(float(kinds.get(kind, 0)) / (299.0 * 4.0) - .25) < .045, "starters offer %s a quarter of the time (%d / %d)" % [kind, kinds.get(kind, 0), 299 * 4])
	check(Forge.FORMS.all(func(f): return found.has(f)), "and flying spells of every look")
	check(odd == 0, "every element, trait and look suits its spell (%d odd)" % odd)
	check(found.lightning.element in ["storm", "radiance"], "lightning is storm or radiance")
	var old: Dictionary = Forge.lookup("forged:1:4242:1:0")
	check(not old.is_empty() and not old.has("archetype") and old.pattern in Forge.PATTERNS, "version-one spellbooks rebuild as they were")
	for i in 40:
		var shop: Dictionary = Forge.lookup(Forge.id_for(9000 + i, 50 + i, i % 2))
		if not shop.element in Forge.suited_elements(shop.pattern): odd += 1
	check(odd == 0, "shop and dark-forged spellbooks follow the same rules")
	await arena("cellar", 1)
	clear_combat(false)
	game.player.place(Vector3(0, 0, 4))
	var aim := Vector3(0, 0, -1)
	for kind in ["ray", "lightning", "eruption"]:
		clear_combat(false)
		var foe = spawn("brute", Vector3(0, 0, -1))
		foe.max_hp = 900.0
		foe.hp = 900.0
		run.weapon_id = found[kind].id
		game.player.aim_direction = aim.rotated(Vector3.UP, .12 if kind == "lightning" else 0.0)
		game.player.fire_cooldown = 0.0
		game.player.fire()
		var cast: Array = game.shots.filter(func(s): return s.mode == kind)
		check(cast.size() == 1, "a %s spellbook casts a %s" % [kind, kind])
		step(32)
		check(foe.hp < 900.0, "the %s strikes the foe ahead (%.0f)" % [kind, 900.0 - foe.hp])
		if not cast.is_empty() and is_instance_valid(cast[0]): check(not cast[0].fx.is_empty(), "the %s is drawn" % kind)
	clear_combat(false)
	run.weapon_id = found.needle.id
	game.player.fire_cooldown = 0.0
	game.player.fire()
	var needle: Array = game.shots.filter(func(s): return s.friendly and s.form == "needle")
	step(2)
	check(not needle.is_empty() and needle[0].core.basis.z.length() > needle[0].core.basis.x.length() * 4.0, "a needle is long and thin along its flight")
	clear_combat(false)

func book(kind: String) -> String:
	for seed_value in range(1, 400):
		for weapon in Forge.starters(seed_value):
			if weapon.archetype == kind: return weapon.id
	return ""

## Equips relics on a clean slate and returns the friendly spells cast by one cast.
func cast_with(kind: String, relics: Array, aim := Vector3(0, 0, -1)) -> Array:
	clear_combat(false)
	run.inventory = relics.duplicate()
	run.modifiers = []
	run.rebuild_stats()
	run.weapon_id = book(kind)
	game.player.place(Vector3(0, 0, 4))
	game.player.aim_direction = aim
	game.player.fire_cooldown = 0.0
	game.player.echoes.clear()
	var before: Array = game.shots.duplicate()
	game.player.fire()
	return game.shots.filter(func(s): return s.friendly and not s in before)

func dummy(at: Vector3, health := 900.0):
	var foe = spawn("brute", at)
	foe.max_hp = health
	foe.hp = health
	return foe

## New relics cast spells of their own, and every relic means something to
## every kind of spell.
func test_relic_powers() -> void:
	await arena("cellar", 1)
	var Synergy = load("res://scripts/items/synergies.gd")
	for id in ["echo_bell", "war_drum", "black_pearl", "phantom_veil", "storm_crown", "phoenix_feather", "prism_lens", "seismic_boots", "spyglass", "meteor_charm", "fractal_seed", "crimson_grail"]:
		check(catalog.item_by_id.has(id), "the relic %s exists" % id)
	for id in ["choir", "supercell", "event_horizon", "pyroclasm", "kaleidoscope", "aftershock", "deadeye", "meteor_shower", "legion", "infinite_regress", "blood_moon", "overture"]:
		check(Synergy.PAIRINGS.has(id) and catalog.item_by_id.has(Synergy.PAIRINGS[id][0]) and catalog.item_by_id.has(Synergy.PAIRINGS[id][1]), "the pairing %s joins two real relics" % id)
	for kind in ["projectile", "ray", "lightning", "eruption"]:
		# Phantom Veil and Legion: two more casts beside you.
		var alone: int = cast_with(kind, []).size()
		check(cast_with(kind, ["phantom_veil", "rear_view"]).size() >= alone * 3, "phantoms cast %s spells too" % kind)
		# Echo Bell and Choir: the cast rings out twice more.
		cast_with(kind, ["echo_bell", "forked_wick"])
		var echoes: int = game.player.echoes.size()
		var before: int = game.shots.size()
		for i in 50: game.player.update_sim(1.0 / 60.0, Vector2.ZERO, Vector3.ZERO, false)
		check(echoes == 2 and game.shots.size() > before, "a %s cast echoes" % kind)
		# Meteor Charm: a falling star where you aim.
		run.inventory = ["meteor_charm"]
		run.rebuild_stats()
		run.stats.meteor = 1.0
		var cast: Array = []
		run.weapon_id = book(kind)
		game.player.fire_cooldown = 0.0
		var known: Array = game.shots.duplicate()
		game.player.fire()
		check(game.shots.any(func(s): return not s in known and int(s.stats.get("erupt", 0)) == 9), "a %s cast can call a falling star" % kind)
		# Storm Crown and Prism Lens: lightning from above, a ray at the next foe.
		var foe = null
		cast = cast_with(kind, ["storm_crown", "prism_lens"])
		run.stats.thunder = 1.0
		foe = dummy(Vector3(0, 0, -1))
		dummy(Vector3(3, 0, -1))
		known = game.shots.duplicate()
		var spell: Array = cast_with(kind, ["storm_crown", "prism_lens"])
		for s in spell: s.stats.thunder = 1.0
		foe = dummy(Vector3(0, 0, -1))
		dummy(Vector3(3, 0, -1))
		var sky := false
		for i in 40:
			step(1)
			if game.shots.any(func(s): return is_instance_valid(s) and float(s.stats.get("sky", 0)) > 0): sky = true
		check(sky, "a %s hit calls lightning from above" % kind)
	# The rest, with the kind they matter most for.
	var near = null
	var spell: Array = cast_with("projectile", ["black_pearl"])
	var target = dummy(Vector3(0, 0, -1))
	near = dummy(Vector3(2.4, 0, -1))
	step(25)
	check(near.knock_velocity.length() > .5 or near.global_position.x < 2.3, "a Black Pearl hit drags the foes around it in")
	# War Drum: the fourth cast is a Great Cast.
	var damages: Array = []
	for i in 4:
		var volley: Array = cast_with("projectile", ["war_drum"])
		if not volley.is_empty(): damages.append(volley[0].damage)
	check(damages.size() == 4 and damages[3] > damages[0] * 1.9, "every fourth cast strikes twice as hard")
	# Seismic Boots: the floor erupts where a dash lands.
	clear_combat(false)
	run.inventory = ["seismic_boots"]
	run.rebuild_stats()
	game.player.dash_cooldown = 0
	game.player.dash_time = 0
	var known: Array = game.shots.duplicate()
	game.player.dash()
	check(game.shots.any(func(s): return not s in known and s.mode == "eruption" and float(s.stats.get("anchor", 0)) > 0), "a dash wakes the floor where it lands")
	# Phoenix Feather: a fallen foe erupts.
	clear_combat(false)
	run.inventory = ["phoenix_feather", "crimson_grail"]
	run.rebuild_stats()
	known = game.shots.duplicate()
	var damage_before: float = run.stats.damage
	game.kill_pairings(Vector3(1, 0, -2))
	check(game.shots.any(func(s): return not s in known and s.mode == "eruption"), "a fallen foe erupts in flame")
	check(run.stats.damage > damage_before and game.bloodlust == 1, "the Crimson Grail feeds on the kill")
	game.enter_room(Vector3(0, 0, 2))
	check(game.bloodlust == 0 and is_equal_approx(run.stats.damage, damage_before), "and its hunger ends with the room")
	await arena("cellar", 1)
	# Lightning: pierce carries it to the foe behind; ricochet leaps aside.
	cast_with("lightning", ["splinter"])
	clear_combat(false)
	var first = dummy(Vector3(0, 0, -1))
	var behind = dummy(Vector3(0, 0, -4))
	spell = cast_with("lightning", ["splinter"])
	first = dummy(Vector3(0, 0, -1))
	behind = dummy(Vector3(0, 0, -4))
	# Lightning gathers for a breath before it strikes.
	step(12)
	check(first.hp < 900.0 and behind.hp < 900.0, "piercing lightning strikes the foe behind too")
	spell = cast_with("lightning", ["skipping_stone"])
	first = dummy(Vector3(0, 0, -1))
	var aside = dummy(Vector3(3.5, 0, 1))
	step(12)
	check(first.hp < 900.0 and aside.hp < 900.0, "ricochet lightning leaps to a foe aside")
	# Eruptions: pierce runs on as a fissure; returning rises at your feet.
	spell = cast_with("eruption", ["splinter"])
	step(2)
	check(game.shots.filter(func(s): return s.mode == "eruption").size() >= 3, "a piercing eruption runs on as a fissure")
	spell = cast_with("eruption", ["return_address"])
	dummy(Vector3(0, 0, -2))
	step(30)
	check(game.shots.any(func(s): return s.mode == "eruption" and float(s.stats.get("anchor", 0)) > 0 and s.global_position.distance_to(game.player.global_position) < 1.5), "a returning eruption rises at your feet")
	# Rays: a lingering beam keeps burning what crosses it.
	spell = cast_with("ray", [])
	var lingering: Array = cast_with("ray", [])
	clear_combat(false)
	run.inventory = []
	run.rebuild_stats()
	run.weapon_id = book("ray")
	game.player.fire_cooldown = 0.0
	known = game.shots.duplicate()
	var beam_stats := {"ray": 1.0, "linger": 1.0}
	var beam = game.spawn_shot(Vector3(0, .65, 4), Vector3(0, 0, -1), 10.0, 72.0, beam_stats, Color.WHITE, true)
	step(1)
	var crossing = dummy(Vector3(0, 0, -2))
	var hp_then: float = crossing.hp
	step(40)
	check(is_instance_valid(beam) and crossing.hp < hp_then, "a lingering ray's beam burns what crosses it")
	run.inventory = []
	run.rebuild_stats()
	clear_combat(false)

func test_firing() -> void:
	await arena("cellar", 1)
	clear_combat()
	var cases := {}
	for seed_value in range(1, 400):
		for weapon in Forge.starters(seed_value):
			if not cases.has(weapon.pattern): cases[weapon.pattern] = weapon
			for trait_id in weapon.traits:
				if not cases.has(trait_id): cases[trait_id] = weapon
		if cases.size() >= Forge.PATTERNS.size() + Forge.ARCHETYPES.size() + 14: break
	check(cases.has("burst") and cases.has("twin") and cases.has("spiral") and cases.has("lingering") and cases.has("forking"), "the forge reaches every pattern and trait")
	run.weapon_id = cases.burst.id
	game.player.aim_direction = Vector3(0, 0, -1)
	game.player.fire_cooldown = 0.0
	var before = game.shots.size()
	game.player.fire()
	var first = game.shots.size() - before
	step(20)
	check(game.shots.size() - before >= first * 2 or game.player.burst_left == 0, "a burst weapon fires the rest of its volley")
	clear_combat()
	run.weapon_id = cases.twin.id
	game.player.fire()
	var pair = game.shots.filter(func(s): return s.friendly)
	check(pair.size() >= 2 and pair[0].direction.is_equal_approx(pair[1].direction) and pair[0].global_position.distance_to(pair[1].global_position) > .3, "twin shots fly side by side")
	clear_combat()
	run.weapon_id = cases.spiral.id
	var turn: float = game.player.spin_angle
	game.player.fire()
	check(game.player.spin_angle != turn, "a spiral turns with every volley")
	clear_combat()
	var linger = game.spawn_shot(Vector3(0, .65, 0), Vector3(0, 0, -1), 5, 6, {"linger": 1}, Color.WHITE, true)
	step(int(linger.lifetime * 60 * .6))
	check(is_instance_valid(linger) and linger.alive and linger.speed < 1.0, "a lingering shot hangs as a mine")
	clear_combat()
	var fast = game.spawn_shot(Vector3(0, .65, 0), Vector3(0, 0, -1), 5, 6, {"accel": 1}, Color.WHITE, true)
	step(20)
	check(fast.speed > 6.5, "an accelerating shot gathers speed")
	clear_combat()
	var fork = game.spawn_shot(Vector3(0, .65, 0), Vector3(1, 0, 0), 5, 2, {"fork": 1}, Color.WHITE, true)
	fork.lifetime = .1
	step(10)
	check(game.shots.filter(func(s): return is_instance_valid(s) and s.alive and s.forked).size() == 3, "a forking shot splits three ways at the end of its flight")
	clear_combat()
	game.spawn_shot(Vector3(-2, .65, 0), Vector3(1, 0, 0), 5, 8, {"trail_kind": "water"}, Color.WHITE, true)
	step(20)
	check(tiles_of("water") > 0, "a trailing shot leaves its element on the floor")

func test_dark_store() -> void:
	for seed_value in [11, 12, 13, 14, 15]:
		for depth in [1, 3, 5]:
			var floor_data = Generator.generate(seed_value * 101, depth)
			check(floor_data.rooms.values().filter(func(r): return r.type == "dark").size() == 1, "seed %d floor %d has one dark store" % [seed_value, depth])
			check(Generator.validate(floor_data).is_empty(), "seed %d floor %d with a dark store validates" % [seed_value, depth])
	check(Generator.validate(Generator.fallback_floor(5, 2)).is_empty(), "the fallback floor needs no dark store")
	var Bargain = load("res://scripts/items/death_bargain.gd")
	game.start_run("candle", 7070, false)
	run.floor_plan = ["cellar", "halls", "crypt", "kiln", "hearth"]
	var dark_id = run.rooms.keys().filter(func(id): return run.rooms[id].type == "dark")[0]
	run.current_room = dark_id
	game.enter_room(Vector3(0, 0, 2))
	check(game.marker != null and game.marker.get_meta("kind") == "dark", "the dark room keeps its altar")
	check(game.room.burning_indices().is_empty(), "the dark room's lanterns are dead")
	check(is_instance_valid(game.death_figure) and game.death_figure.state == "hidden", "Death waits unseen behind its altar")
	game.use_pedestal({"kind": "dark"})
	var offers: Array = run.rooms[dark_id].offers
	check(game.ui.mode == "bargain" and game.paused, "bargaining opens Death's bargain")
	check(game.death_figure.state == "rising", "Death rises out of the dark when the bargain opens")
	game.death_figure._process(1.0)
	check(game.death_figure.eyes.all(func(eye): return eye.material_override.albedo_color.a == 0.0), "its eyes come last")
	game.death_figure._process(4.0)
	check(game.death_figure.present() and game.death_figure.eyes.all(func(eye): return eye.material_override.albedo_color.a > .5), "then its small white eyes")
	check(offers.size() == 3 and offers.all(func(o): return int(o.power) >= 2 and int(o.power) <= 5 and Bargain.known_curse(o.curse) and Bargain.TRIALS.has(o.trial)), "three offers, each with a curse and a trial")
	check(offers.all(func(o): return is_equal_approx(absf(float(o.curse.amount)), Bargain.STEP * int(o.power) * absf(float(Bargain.CURSES[o.curse.id][2])))), "each curse is as heavy as its offer is strong")
	check(offers[0].kind == "item" and catalog.item_by_id[offers[0].id].rarity == "dark", "a dark relic is always on offer")
	var copy = offers.duplicate(true)
	run.rooms[dark_id].erase("offers")
	game.ensure_dark_offers()
	check(JSON.stringify(run.rooms[dark_id].offers) == JSON.stringify(copy), "the bargains come from the room's seed")
	offers = run.rooms[dark_id].offers
	game.ui.offers = offers
	game.ui.pick_bargain(0, "curse")
	check(game.ui.content.get_node_or_null("Take_0") != null and game.ui.bargain_pick == 0, "an offer is chosen from Death's right hand")
	offers[0].curse = {"id": "withering", "amount": -.18}
	var max_before: float = run.stats.max_hp
	var coins: int = run.coins
	check(game.seal_bargain(0, "curse").ok, "the bargain is sealed")
	check(offers[0].id in run.inventory and run.curses.size() == 1 and run.blood_debt == 0, "what is taken is carried, and its curse falls")
	check(run.coins == coins and run.stats.max_hp >= max_before - catalog.base_stats().max_hp, "Death takes no coins and no health")
	var cursed: float = run.stats.damage
	run.curses = []
	run.rebuild_stats()
	check(is_equal_approx(run.stats.damage - .18, cursed), "Withering weakens spells for the rest of the run")
	run.curses = [{"id": "withering", "amount": -.18}]
	run.rebuild_stats()
	check(run.rooms[dark_id].claimed and game.ui.mode == "play" and not game.paused, "Death deals once per altar")
	check(game.death_figure.state == "fading", "Death fades once the bargain is struck")
	check(not game.seal_bargain(1, "curse").ok and run.curses.size() == 1, "a second bargain is refused")
	check(Bargain.curse_text({"id": "withering", "amount": -.3}) == "Your spells strike 30% weaker.", "a curse says how heavy it is")
	run.save_run()
	run.curses = []
	run.load_run()
	check(run.curses.size() == 1 and is_equal_approx(run.stats.damage, cursed), "curses survive save and load")
	var curse := {"id": "leaden_feet", "amount": -.12}
	var before: int = run.curses.size()
	# Relics that strike on their own would fight the trials for the test.
	run.inventory = []
	run.rebuild_stats()
	# Waves against the clock: three waves, each cleared before the next.
	game.trials.begin("waves", curse)
	check(run.trial.state == "running" and not game.room.open, "a trial fought now seals Death's room")
	step(100)
	check(game.trials.wave == 1 and game.trials.foes.size() >= 3, "Death raises the first wave")
	for w in 3:
		for foe in game.trials.foes.duplicate(): slay(foe)
		step(2)
	check(run.trial.is_empty() and game.room.open and run.curses.size() == before, "clearing every wave in time keeps the curse away")
	# Reaper's quarry, out of time.
	game.trials.begin("quarry", curse)
	step(110)
	var champion = game.trials.foes[0] if not game.trials.foes.is_empty() else null
	check(game.trials.foes.size() == 1 and champion.elite != "", "Reaper's quarry summons one elite champion")
	game.trials.clock = .05
	step(5)
	check(run.trial.is_empty() and run.curses.size() == before + 1 and game.room.open, "out of time, the curse falls anyway and the doors open")
	check(not is_instance_valid(champion) or not champion.alive, "the champion goes back into the dark")
	before = run.curses.size()
	# Soul harvest: walk through every wisp.
	game.trials.begin("harvest", curse)
	step(110)
	check(game.trials.wisps.size() == 7, "Soul harvest scatters seven wisps")
	for wisp in game.trials.wisps.duplicate():
		if not is_instance_valid(wisp): continue
		game.player.place(Vector3(wisp.position.x, game.player.position.y, wisp.position.z))
		step(1)
	check(run.trial.is_empty() and run.curses.size() == before, "catching every wisp wins the harvest")
	# Last breath: a fall fails the trial instead of the run.
	clear_combat(false)
	run.hp = run.stats.max_hp
	var full: float = run.hp
	game.trials.begin("last_breath", curse)
	check(is_equal_approx(run.hp, 1.0), "Last breath leaves half a heart")
	game.player.invulnerability = 5.0
	step(110)
	run.wards = 0
	game.player.shield = 0
	game.player.invulnerability = 0
	game.player.hurt(1.0, game.player.position + Vector3(1, 0, 0))
	check(run.active and run.trial.is_empty() and is_equal_approx(run.hp, full) and run.curses.size() == before + 1, "falling in Last breath fails it, health returns and the run goes on")
	clear_combat(false)
	before = run.curses.size()
	# Leaving a trial halfway is failing it; No dashing goes on waiting.
	run.trial = {"kind": "waves", "curse": curse, "room": dark_id, "state": "running"}
	run.save_run()
	run.load_run()
	check(run.trial.is_empty() and run.curses.size() == before + 1, "leaving a trial halfway lets its curse fall")
	run.curses.pop_back()
	run.rebuild_stats()
	before = run.curses.size()
	# No dashing: the next fight, won without a dash.
	game.trials.begin("no_dash", curse)
	check(run.trial.state == "waiting" and game.ui.toast_text == "No dashing", "No dashing waits for the next fight")
	var fight_id = run.rooms.keys().filter(func(id): return run.rooms[id].type == "combat" and not run.rooms[id].cleared)[0]
	run.current_room = fight_id
	game.enter_room(Vector3(0, 0, 2))
	step(2)
	check(run.trial.state == "running", "the trial begins when a fight shuts its doors")
	run.save_run()
	run.load_run()
	check(run.trial.state == "waiting", "a reload puts No dashing back to waiting")
	step(2)
	game.player.dash_cooldown = 0
	game.player.dash_time = 0
	game.player.dash()
	check(run.trial.is_empty() and run.curses.size() == before + 1, "a dash fails it")
	game.trials.begin("no_dash", curse)
	step(2)
	game.clear_room()
	check(run.trial.is_empty() and run.curses.size() == before + 1, "winning the fight without a dash keeps the curse away")
	# Heavy Chains lengthen the dash's return.
	run.inventory = []
	run.curses = [{"id": "heavy_chains", "amount": -.45}]
	run.rebuild_stats()
	game.player.dash_cooldown = 0
	game.player.dash_time = 0
	game.player.dash()
	check(is_equal_approx(game.player.dash_cooldown, 1.35 * 1.45), "Heavy Chains make the dash return 45% slower")
	run.curses = []
	run.rebuild_stats()
	# Every trial can come up, co-op included (the party watches).
	var party_gen = RandomNumberGenerator.new()
	var party_trials := {}
	for i in 30:
		party_gen.seed = i
		var offer := {"price": 3}
		Bargain.terms(offer, party_gen)
		party_trials[offer.trial] = true
	check(party_trials.size() == Bargain.TRIALS.size(), "every trial can be set, alone or in co-op")
	for i in 400:
		var gen = RandomNumberGenerator.new()
		gen.seed = i
		check(catalog.roll_items(gen, 3, [], true, 2.0).all(func(item): return item.rarity != "dark"), "dark relics never appear outside the dark store")
		if failures > 0: break

func test_coins() -> void:
	var table: Dictionary = catalog.record("drop_tables", "enemy_common")
	var coins = table.rolls.filter(func(roll): return roll.has("coins"))[0].coins
	check(is_equal_approx(coins, .4), "foes drop about 0.4 coins each")
	var gen = RandomNumberGenerator.new()
	gen.seed = 5
	var total = 0
	for i in 2000:
		for drop in Drops.roll("enemy_common", gen):
			if drop.def == "copper_coin": total += 1
			elif drop.def == "silver_coin": total += 5
	check(total > 650 and total < 950, "two thousand foes pay about 800 coins (%d)" % total)
