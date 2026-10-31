extends SceneTree
## Combat dynamics: lantern light and darkness, grazing sparks, the kindle,
## noise, what fights leave on the floor, each floor's foes and elites, and
## the three bosses. Run through tools/test.sh with disposable storage.
var checks = 0
var failures = 0
var run
var catalog
var game
var Foes
var Residue
var Light

func _initialize() -> void:
	call_deferred("test_combat")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func step(frames := 1) -> void:
	for frame in frames:
		game._physics_process(1.0 / 60.0)

## Removes every foe and shot. Unless told otherwise a keeper stays: an
## ember that never kindles, far in a corner, holding the room shut.
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

## A sealed single-cell room of the floor, emptied of its own foes.
func arena(floor_number: int, kind := "combat", seed_value := 51234, needs_dark := false) -> String:
	game.start_run("candle", seed_value, false)
	# Floors 1-3 here are the old tower: the cellar, the halls and the hearth.
	run.plan_climb("legacy_tower")
	run.floor_number = floor_number
	run.generate_floor()
	for id in run.rooms:
		var data = run.rooms[id]
		if data.type != kind or (data.cells.size() != 1 and kind != "boss"): continue
		if needs_dark:
			var count = data.get("lights", []).size()
			if Light.lit_lanterns(count, Light.profile(floor_number), int(data.seed)).size() >= count or count < 2: continue
		data.cleared = false
		run.current_room = id
		game.enter_room(Vector3(0, 0, 2))
		if kind != "boss": clear_combat()
		# Bare floor: furniture and pillars would stop the shots aimed here.
		for prop in game.room.props.keys(): game.room.break_prop(prop)
		await process_frame
		game.player.place(Vector3(0, 0, 4))
		game.player.invulnerability = 0.0
		run.hp = run.stats.max_hp
		game.reset_combat()
		return id
	return ""

func foe(kind: String, at: Vector3, source := "") :
	var enemy = game.spawn_enemy(at, kind, source)
	return enemy

func hostile_count() -> int:
	return game.shots.filter(func(s): return is_instance_valid(s) and s.alive and not s.friendly).size()

func test_combat() -> void:
	run = root.get_node("Run")
	catalog = root.get_node("Content")
	Foes = load("res://scripts/foes/foes.gd")
	Residue = load("res://scripts/combat/residue.gd")
	Light = load("res://scripts/dungeon/floor_light.gd")
	root.get_node("Settings").set_value("sound", false)
	root.get_node("Settings").set_value("music", false)
	test_rosters()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	await test_light()
	await test_player_dynamics()
	await test_residue()
	await test_cellar_foes()
	await test_halls_foes()
	await test_top_foes()
	await test_elites()
	await test_warden()
	await test_mosskeeper()
	await test_last_light()
	await test_encounters()
	game.return_to_title()
	game.queue_free()
	root.get_node("Audio").music_player.stop()
	await process_frame
	await process_frame
	print("EMBERKEEP COMBAT TEST RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

## Each floor brings its own foes; elites start in the halls.
func test_rosters() -> void:
	var kinds := {1: {}, 2: {}, 3: {}}
	var elites := {1: 0, 2: 0, 3: 0}
	var eligible := {1: 0, 2: 0, 3: 0}
	var pairs = true
	var capped = true
	var climb = ["cellar", "halls", "hearth"]
	for floor_number in [1, 2, 3]:
		var full: Array = Foes.roster_for(climb[floor_number - 1], floor_number, climb)
		var roster: Array = full.map(func(entry): return entry[0])
		for i in 300:
			var gen = RandomNumberGenerator.new()
			gen.seed = i * 7919 + floor_number
			var plan: Array = Foes.compose(full, Foes.elite_chance(floor_number), 6, gen)
			var taken := {}
			for j in plan.size():
				var entry: Dictionary = plan[j]
				kinds[floor_number][entry.kind] = true
				taken[entry.kind] = taken.get(entry.kind, 0) + 1
				if entry.kind == "rootling":
					pairs = pairs and entry.partner >= 0 and plan[entry.partner].partner == j
				else:
					eligible[floor_number] += 1
					if entry.elite != "": elites[floor_number] += 1
				capped = capped and entry.kind in roster
			for entry in full:
				capped = capped and taken.get(entry[0], 0) <= entry[2] * (2 if entry[0] == "rootling" else 1)
	for kind in ["snuffer", "drip", "shackled"]: check(kinds[1].has(kind), "the cellar brings the " + kind)
	for kind in ["sporecap", "rootling", "lichen"]: check(kinds[2].has(kind), "the halls bring the " + kind)
	for kind in ["lampwright", "prism", "cinderling"]: check(kinds[3].has(kind), "the top floor brings the " + kind)
	check(not kinds[1].has("lampwright") and not kinds[1].has("sporecap") and not kinds[2].has("prism"), "foes keep to their floors")
	check(pairs, "rootlings always grow in pairs")
	check(capped, "every foe comes from its floor's roster within its limit")
	var share2 = float(elites[2]) / eligible[2]
	var share3 = float(elites[3]) / eligible[3]
	check(elites[1] == 0 and share2 > .12 and share2 < .32 and share3 > .24 and share3 < .48,
		"elites from the halls up (%.2f, %.2f)" % [share2, share3])
	var a = RandomNumberGenerator.new()
	a.seed = 99
	var b = RandomNumberGenerator.new()
	b.seed = 99
	var top: Array = Foes.roster_for("hearth", 3, climb)
	check(Foes.compose(top, Foes.elite_chance(3), 7, a) == Foes.compose(top, Foes.elite_chance(3), 7, b), "an encounter is the same from the same seed")
	check(Foes.boss_kind(catalog.record("floors", "cellar")) == "warden" and Foes.boss_kind(catalog.record("floors", "halls")) == "mosskeeper"
		and Foes.boss_kind(catalog.record("floors", "hearth")) == "last_light", "each floor has its own boss")

## Lanterns can be relit and put out; light exposes foes, darkness hides them.
func test_light() -> void:
	var id = await arena(1, "combat", 51234, true)
	check(id != "", "a cellar room with a dead lantern")
	var room = game.room
	var dead = room.lantern_near(Vector2.ZERO, 999.0, false)
	var lit_before = room.lantern_points.size()
	var at: Vector3 = room.lanterns[dead].at
	var inward = (Vector3(0, 0, 0) - Vector3(at.x, 0, at.z)).normalized()
	game.spawn_shot(at + inward * 2.0 + Vector3(0, .65, 0), -inward, 5, 15, {}, Color.WHITE, true)
	step(12)
	check(room.lanterns[dead].burning and room.lantern_points.size() == lit_before + 1, "a shot through a dead lantern's glass relights it")
	check(room.lamps.size() == mini(room.MAX_ACTIVE_FILLS, room.lantern_points.size()), "the fill lights follow the burning lanterns")
	check(not game.latest_noise(1.5, 1.0).is_empty(), "relighting makes a sound")
	# Light exposes: a foe in a lantern's pool takes more.
	var burning: Vector3 = room.lantern_points[0]
	var in_light = foe("mote", burning + (Vector3.ZERO - burning).normalized() * 1.2)
	var dark_spot = Vector3.ZERO
	for x in range(-8, 9):
		for z in range(-6, 7):
			var p = Vector3(x, 0, z)
			if room.geometry.contains(Vector2(p.x, p.z), .6) and not room.lit_at(p): dark_spot = p
	var in_dark = foe("mote", dark_spot)
	for enemy in [in_light, in_dark]:
		enemy.speed = 0.0
		enemy.hp = 100.0
		enemy.max_hp = 100.0
	game.player.place(dark_spot + (Vector3(0, 0, 3.0) if dark_spot.z < 2 else Vector3(0, 0, -3.0)))
	game.player.place(Vector3(dark_spot.x, 0, clampf(dark_spot.z + 6.0, -6, 6)) if absf(dark_spot.z) < 1 else Vector3(-dark_spot.x, 0, -dark_spot.z))
	step(1)
	in_light.take_hit(10, Vector3.ZERO, false, false, "shot")
	in_dark.take_hit(10, Vector3.ZERO, false, false, "shot")
	check(room.lit_at(in_light.global_position) and is_equal_approx(100.0 - in_light.hp, 12.5) and is_equal_approx(100.0 - in_dark.hp, 10.0), "a foe in lantern light takes a quarter more")
	# Darkness hides: with a dead lantern in the room, only the eyes show.
	room.set_lantern(room.lantern_near(Vector2.ZERO, 999.0, true), false)
	step(1)
	var far = in_dark.global_position.distance_to(game.player.global_position) > game.player_light_radius()
	check(room.has_dark() and far and in_dark.shrouded and not in_dark.visual.get_child(0).visible and in_dark.eyes.visible, "a foe in the dark shows only its eyes")
	game.player.place(in_dark.global_position + Vector3(1.0, 0, 0))
	step(1)
	check(not in_dark.shrouded and in_dark.visual.get_child(0).visible, "the player's own light shows it")
	# A Snuffer puts a burning lantern out.
	clear_combat()
	var target = room.lantern_near(Vector2.ZERO, 999.0, true)
	var lantern_at: Vector3 = room.lanterns[target].at
	foe("snuffer", lantern_at + (Vector3.ZERO - lantern_at).normalized() * 1.6)
	var ticks = 0
	while room.lanterns[target].burning and ticks < 300:
		step(1)
		ticks += 1
	check(not room.lanterns[target].burning, "a Snuffer flies to a lantern and puts it out (%d ticks)" % ticks)
	# With every lantern out there is nothing for the shadow lamp to hang on.
	for i in room.burning_indices(): room.set_lantern(i, false)
	check(room.lamps.is_empty() and room.shadow_lamps.all(func(lamp): return not lamp.visible), "with no lantern burning the room has no lantern light")
	room.set_lantern(dead, true)
	clear_combat(false)
	step(2)
	check(game.room.open and run.rooms[id].get("lit", []) == room.burning_indices(), "a won room keeps its lanterns as left")

## Grazing sparks, the kindle and noise.
func test_player_dynamics() -> void:
	await arena(1)
	var player = game.player
	player.place(Vector3.ZERO)
	player.dash_cooldown = 0.0
	player.last_move = Vector3.RIGHT
	game.spawn_shot(Vector3(.5, .65, .4), Vector3.LEFT, 1, 0.1, {}, Color.WHITE, false)
	game.request_dash = true
	step(1)
	check(game.sparks == 1 and hostile_count() == 0, "a dash grazing a hostile ember catches it as a spark")
	player.aim_direction = Vector3.RIGHT
	player.fire_cooldown = 0.0
	player.fire()
	check(game.sparks == 0 and game.shots.any(func(s): return is_instance_valid(s) and s.friendly and float(s.stats.get("homing", 0)) >= 5.0), "the next shot releases sparks as homing embers")
	player.dash_cooldown = 0.0
	player.dash_time = 0.0
	for i in 5: game.spawn_shot(player.global_position + Vector3(.3, .65, 0).rotated(Vector3.UP, i), Vector3.LEFT, 1, 0.1, {}, Color.WHITE, false)
	game.request_dash = true
	step(1)
	check(game.sparks == game.MAX_SPARKS, "no more than three sparks are held")
	# Kindle: quick kills grow it, a hit gutters it, quiet cools it.
	game.reset_combat()
	for i in 3: game.stoke()
	check(game.kindle_level() == 1 and is_equal_approx(game.kindle_damage(), 1.15) and is_equal_approx(game.player_light_radius(), game.PLAYER_LIGHT + 1.0), "three quick kills kindle the flame")
	for i in 7: game.stoke()
	check(game.kindle_level() == 3 and is_equal_approx(game.kindle_damage(), 1.5), "ten kindle it fully")
	clear_combat()
	player.fire_cooldown = 0.0
	player.fire()
	check(game.shots.any(func(s): return is_instance_valid(s) and s.friendly and float(s.stats.get("burn", 0)) >= .6), "a full kindle sets every ember alight")
	player.invulnerability = 0.0
	player.shield = 0
	run.wards = 0
	player.hurt(1.0, Vector3.ZERO)
	check(game.kindle_level() == 0, "a hit gutters the kindle")
	run.hp = run.stats.max_hp
	game.reset_combat()
	for i in 6: game.stoke()
	step(roundi((game.KINDLE_FADE_AFTER + 2.5) * 60))
	check(game.kindle_level() == 1, "a streak cools once kills stop")
	# Noise: shots are heard, dashes louder.
	game.noises.clear()
	player.fire_cooldown = 0.0
	player.fire()
	var noise: Dictionary = game.latest_noise(1.0, 1.0)
	check(not noise.is_empty() and Vector2(noise.at.x, noise.at.z).distance_to(Vector2(player.position.x, player.position.z)) < .1, "a shot is heard where it was fired")
	player.dash_cooldown = 0.0
	player.dash_time = 0.0
	game.request_dash = true
	step(1)
	check(not game.latest_noise(2.0, 1.0).is_empty(), "a dash is louder")

## Wax, ice, fire, moss, glass and spores.
func test_residue() -> void:
	await arena(1)
	var residue = game.residue
	game.player.place(Vector3(6, 0, 5))
	check(residue.views.values().all(func(v): return not v.view.visible), "nothing on the floor draws nothing")
	residue.add("wax", Vector3(-4, 0, -2), 1.8)
	var wax = residue.tiles.size()
	step(1)
	var marked = residue.views.wax.image.get_pixelv(residue.key(Vector3(-4, 0, -2)) - residue.grid_origin).r
	check(residue.views.wax.view.visible and marked > .99 and not residue.views.ice.view.visible, "each kind is drawn as one even patch from its own mask")
	residue.react(Vector3(-4, 0, -2), .7, {"burn": 1.0})
	var fire_count = func(): return residue.tiles.values().filter(func(t): return t.kind == "fire").size()
	var first = fire_count.call()
	var standing = foe("mote", Vector3(-4, 0, -2))
	standing.speed = 0.0
	standing.hp = 500.0
	step(30)
	check(first > 0 and fire_count.call() > first, "burn ignites wax and the fire spreads along it (%d to %d)" % [first, fire_count.call()])
	check(standing.burn_time > 0, "a foe standing in fire burns")
	game.player.place(Vector3(-4, 0, -2))
	game.player.invulnerability = 0.0
	var hp = run.hp
	step(16)
	check(run.hp < hp, "fire hurts the player too")
	game.player.place(Vector3(6, 0, 5))
	run.hp = run.stats.max_hp
	step(roundi((Residue.FIRE_LIFE + 2.5) * 60))
	check(fire_count.call() == 0 and residue.tiles.size() < wax, "fire burns the wax away")
	clear_combat()
	# Chill makes ice; ice keeps you sliding; it melts back to wax.
	# A wide patch: outside the physics callback a step moves the player by
	# the last real frame's length, which varies from run to run.
	residue.add("wax", Vector3(2, 0, 0), 3.2)
	residue.react(Vector3(2, 0, 0), 3.6, {"chill": 1.0})
	check(residue.kind_at(Vector3(2, 0, 0)) == "ice", "chill turns wax to ice")
	game.player.place(Vector3(.2, 0, 0))
	game.player.velocity = Vector3(4, 0, 0)
	step(6)
	var slide = game.player.velocity.length()
	game.player.place(Vector3(-5, 0, 4))
	game.player.velocity = Vector3(4, 0, 0)
	step(6)
	check(slide > 2.5 and game.player.velocity.length() < .5, "ice keeps the player sliding (%.1f against %.1f)" % [slide, game.player.velocity.length()])
	residue.ignite(Vector3(2, 0, 0), .7)
	check(residue.kind_at(Vector3(2, 0, 0)) == "wax", "fire melts ice back to wax")
	residue.freeze(Vector3(2, 0, 0), 1.0)
	step(roundi((Residue.ICE_LIFE + .5) * 60))
	check(residue.kind_at(Vector3(2, 0, 0)) == "wax", "ice melts back to wax in time")
	# Moss drags at the feet.
	residue.add("moss", Vector3(-6, 0, 4), 1.0)
	check(is_equal_approx(residue.slows(Vector3(-6, 0, 4)), .75), "moss slows the player")
	# Spores hide what is inside; poison runs through; fire sets them off.
	game.player.place(Vector3(6, 0, 5))
	residue.add_cloud(Vector3(-4, 0, 3), 2.0)
	var hidden = foe("mote", Vector3(-4, 0, 3))
	var neighbour = foe("mote", Vector3(-3.2, 0, 3.4))
	for enemy in [hidden, neighbour]:
		enemy.speed = 0.0
		enemy.hp = 200.0
		enemy.max_hp = 200.0
	step(1)
	check(hidden.shrouded and residue.slows(Vector3(-4, 0, 3)) < 1.0, "a spore cloud hides what is inside and drags at the feet")
	hidden.apply_status({"poison": 1.0})
	step(20)
	check(residue.clouds[0].poisoned and neighbour.poison_time > 0, "poison spreads through a spore cloud")
	var before = neighbour.hp
	residue.ignite(Vector3(-4, 0, 3), .5)
	check(residue.clouds.is_empty() and before - neighbour.hp >= Residue.CLOUD_BLAST * .99, "fire sets the spores off")
	clear_combat()
	# Glass splits a shot crossing it into three, once.
	residue.add("glass", Vector3(0, 0, -3), 1.2)
	game.spawn_shot(Vector3(-5, .65, -3), Vector3.RIGHT, 3, 15, {}, Color.WHITE, true)
	step(25)
	var split = game.shots.filter(func(s): return is_instance_valid(s) and s.alive).size()
	check(split == 3, "glass splits a crossing shot into three (%d)" % split)

## The cellar: drips, the shackled and its post.
func test_cellar_foes() -> void:
	await arena(1)
	var drip = foe("drip", Vector3(-5, 0, -3))
	check(not drip.targetable and not drip.visual.visible, "a drip on the ceiling shows only its shadow and cannot be struck")
	game.player.place(Vector3(6, 0, 4))
	game.noises.clear()
	game.make_noise(Vector3(-5, 0, 3), 3.0)
	var start: Vector3 = drip.global_position
	step(20)
	check(drip.global_position.distance_to(Vector3(-5, 0, 3)) < start.distance_to(Vector3(-5, 0, 3)) - .3, "it drifts after the last loud noise")
	var ticks = 0
	while drip.state != "ground" and ticks < 600:
		step(1)
		ticks += 1
	check(drip.state == "ground" and drip.targetable and game.residue.tiles.size() > 0, "it drops with a splash of wax and can be struck")
	clear_combat()
	# The shackled keeps to its chain until its post is shot down.
	var prisoner = foe("shackled", Vector3(-4, 0, 0))
	step(2)
	var post = prisoner.post
	check(is_instance_valid(post) and post.inert and post.kind == "shackle_post", "the shackled is chained to a post")
	game.player.place(Vector3(7, 0, 4))
	step(180)
	check(prisoner.global_position.distance_to(post.global_position) <= prisoner.LEASH + .1, "its chain holds it near the post")
	var slow = prisoner.speed
	post.take_hit(100, Vector3.ZERO, false, false, "shot")
	check(prisoner.freed and prisoner.speed > slow, "shooting the post frees it, faster")
	for keeper in game.enemies.filter(func(e): return is_instance_valid(e) and e.kind == "ember"):
		keeper.alive = false
		keeper.queue_free()
	prisoner.take_hit(10000, Vector3.ZERO, false, false, "shot")
	step(2)
	check(game.room.open and game.enemies.is_empty(), "the room opens once the prisoner falls")
	# Scenery alone never holds a room shut.
	await arena(1)
	clear_combat(false)
	foe("dropped_lantern", Vector3(2, 0, 0))
	step(2)
	check(game.room.open, "an inert post or lantern never holds the room shut")

## The halls: spores, rootlings, lichen, thrown motes and fusing wisps.
func test_halls_foes() -> void:
	await arena(2)
	game.player.place(Vector3(3, 0, 2))
	var cap = foe("sporecap", Vector3(-5, 0, -2))
	cap.timer = 0.0
	var ticks = 0
	while game.residue.clouds.is_empty() and ticks < 240:
		step(1)
		ticks += 1
	check(not game.residue.clouds.is_empty() and Vector2(game.residue.clouds[0].at.x - 3, game.residue.clouds[0].at.z - 2).length() < 2.5, "a sporecap lobs spores where the player stands")
	clear_combat()
	game.residue.clouds.clear()
	var a = foe("rootling", Vector3(-4, 0, 0), "t:e1")
	var b = foe("rootling", Vector3(2, 0, 0), "t:e2")
	a.bind_partner(b)
	game.player.place(Vector3(-1, 0, 0))
	game.player.invulnerability = 0.0
	var hp = run.hp
	step(2)
	check(run.hp < hp, "the vine between a rootling pair hurts")
	run.hp = run.stats.max_hp
	game.player.place(Vector3(0, 0, 5))
	a.take_hit(1000, Vector3.ZERO, false, false, "shot")
	check(b.enraged, "killing one rootling enrages the other")
	step(30)
	b.take_hit(1000, Vector3.ZERO, false, false, "shot")
	check(game.pickups.any(func(p): return is_instance_valid(p) and p.definition.id == "silver_coin"), "killing both within two seconds drops a little extra")
	clear_combat()
	# A lichen's face turns shots; its back does not.
	var lichen = foe("lichen", Vector3(0, 0, 0))
	lichen.speed = 0.0
	lichen.timer = 99.0
	lichen.facing = Vector3.RIGHT
	game.player.place(Vector3(6, 0, 4))
	var whole = lichen.hp
	var front = game.spawn_shot(Vector3(2.5, .65, 0), Vector3.LEFT, 5, 15, {}, Color.WHITE, true)
	step(8)
	check(is_instance_valid(front) and not front.friendly and is_equal_approx(lichen.hp, whole), "a shot at a lichen's face turns back on the player")
	lichen.facing = Vector3.RIGHT
	game.spawn_shot(Vector3(-2.5, .65, 0), Vector3.RIGHT, 5, 15, {}, Color.WHITE, true)
	step(8)
	check(lichen.hp < whole, "its back is soft")
	clear_combat()
	# Brutes throw motes in the halls.
	var brute = foe("brute", Vector3(-4, 0, 0))
	var mote = foe("mote", Vector3(-3, 0, 0))
	brute.speed = 0.0
	brute.timer = 0.0
	game.player.place(Vector3(4, 0, 0))
	step(1)
	check(not mote.thrown.is_empty(), "a brute picks up a mote to throw")
	step(60)
	check(mote.thrown.is_empty() and mote.global_position.distance_to(game.player.global_position) < 2.5, "the mote lands beside the player")
	clear_combat()
	# Wisps that both survive fuse back into a splitter here, never in the cellar.
	var splitter = foe("splitter", Vector3(-3, 0, -3))
	splitter.take_hit(1000, Vector3.ZERO, false, false, "shot")
	var wisps = game.enemies.filter(func(e): return is_instance_valid(e) and e.kind == "wisp")
	check(wisps.size() == 2 and wisps.all(func(w): return w.can_merge), "a splitter's wisps may fuse in the halls")
	step(roundi(4.0 * 60) + 90)
	var fused = game.enemies.filter(func(e): return is_instance_valid(e) and e.alive and e.kind == "splitter")
	check(fused.size() == 1 and not fused[0].can_merge and game.enemies.filter(func(e): return is_instance_valid(e) and e.alive and e.kind == "wisp").is_empty(), "left alive, they fuse back into a splitter, once")
	run.floor_number = 1
	clear_combat()
	var cellar_splitter = foe("splitter", Vector3(-3, 0, -3))
	cellar_splitter.take_hit(1000, Vector3.ZERO, false, false, "shot")
	check(game.enemies.filter(func(e): return is_instance_valid(e) and e.kind == "wisp").all(func(w): return not w.can_merge), "cellar wisps never fuse")

## The top floor: lampwrights, prisms, cinderlings and rebounding chargers.
func test_top_foes() -> void:
	await arena(3)
	game.player.place(Vector3(6, 0, 5))
	var lamplighter = foe("lampwright", Vector3(-3, 0, 0))
	var helped = foe("mote", Vector3(-1.8, 0, 0))
	helped.speed = 0.0
	lamplighter.speed = 0.0
	step(2)
	check(helped.aura_haste > 0 and helped.tempo() > 1.0 and game.room.lit_at(helped.global_position), "a lampwright's light hurries and exposes foes in it")
	lamplighter.take_hit(1000, Vector3.ZERO, false, false, "shot")
	var dropped = game.enemies.filter(func(e): return is_instance_valid(e) and e.alive and e.kind == "dropped_lantern")
	check(dropped.size() == 1 and dropped[0].inert, "its lantern stays burning where it fell")
	helped.hp = 100.0
	dropped[0].take_hit(1, Vector3.ZERO, false, false, "shot")
	check(helped.hp < 100.0, "shot, the lantern bursts")
	clear_combat()
	# A prism drinks embers and throws them back; a dash shatters it.
	var prism = foe("prism", Vector3(0, 0, 0))
	prism.speed = 0.0
	game.player.place(Vector3(5, 0, 0))
	var whole = prism.hp
	for i in 3: game.spawn_shot(Vector3(2.5, .65, -.2 + i * .2), Vector3.LEFT, 5, 15, {}, Color.WHITE, true)
	step(8)
	check(is_equal_approx(prism.hp, whole) and prism.stored == 3, "a prism drinks the shots that reach it")
	step(60)
	check(hostile_count() >= 3, "and throws them back as a fan")
	prism.dashed_through()
	check(prism.cracked > 0 and prism.hp <= whole * .5 + .01 and game.residue.tiles.values().any(func(t): return t.kind == "glass"), "a dash through it shatters it, leaving glass")
	var cracked_hp = prism.hp
	game.spawn_shot(Vector3(2.5, .65, 0), Vector3.LEFT, 5, 15, {}, Color.WHITE, true)
	step(8)
	check(prism.hp < cracked_hp, "a cracked prism takes shots")
	clear_combat(false)
	# A cinderling's ember kindles a new one unless stepped on.
	game.player.place(Vector3(6, 0, 5))
	var flame = foe("cinderling", Vector3(-4, 0, -2))
	flame.take_hit(1000, Vector3.ZERO, false, false, "shot")
	var embers = game.enemies.filter(func(e): return is_instance_valid(e) and e.alive and e.kind == "ember")
	check(embers.size() == 1 and not embers[0].targetable and not embers[0].inert, "a cinderling leaves an ember that holds the room")
	step(roundi(3.1 * 60))
	var rekindled = game.enemies.filter(func(e): return is_instance_valid(e) and e.alive and e.kind == "cinderling")
	check(rekindled.size() == 1 and rekindled[0].hp < rekindled[0].max_hp, "three seconds later it kindles a new one")
	rekindled[0].take_hit(1000, Vector3.ZERO, false, false, "shot")
	var second = game.enemies.filter(func(e): return is_instance_valid(e) and e.alive and e.kind == "ember")
	game.player.place(second[0].global_position)
	step(2)
	check(game.enemies.filter(func(e): return is_instance_valid(e) and e.alive).is_empty(), "stepping on the ember puts it out")
	clear_combat()
	var charger = foe("charger", Vector3(-4, 0, 0))
	charger.timer = 0.0
	step(1)
	check(charger.charges_left == 2, "a top-floor charger rebounds twice")

## Elites: gilded, twinned, volatile and warded.
func test_elites() -> void:
	await arena(2)
	game.player.place(Vector3(6, 0, 4))
	var gilded = foe("mote", Vector3(-3, 0, 0), "elite:e1")
	gilded.make_elite("gilded")
	gilded.hp = 500.0
	gilded.max_hp = 500.0
	for i in 6: gilded.take_hit(1, Vector3.ZERO, false, false, "shot")
	check(game.pickups.filter(func(p): return is_instance_valid(p) and p.definition.id == "copper_coin").size() == 4, "a gilded foe sheds a coin a hit, four at most")
	gilded.hp = 100.0
	var away_before = gilded.global_position.distance_to(game.player.global_position)
	step(30)
	check(gilded.global_position.distance_to(game.player.global_position) > away_before, "hurt past half, it runs")
	clear_combat()
	var a = foe("mote", Vector3(-3, 0, -2))
	var b = foe("spitter", Vector3(-3, 0, 2))
	a.make_elite("twinned", b)
	check(a.hp == b.hp and is_equal_approx(a.max_hp, b.max_hp), "twins share one pool")
	var pool = a.hp
	a.take_hit(5, Vector3.ZERO, false, false, "shot")
	check(is_equal_approx(b.hp, pool - 5.0), "a hit on one is a hit on both")
	b.take_hit(10000, Vector3.ZERO, false, false, "shot")
	check(not a.alive and not b.alive, "and they fall together")
	clear_combat()
	var volatile = foe("mote", Vector3(-3, 0, 0))
	volatile.make_elite("volatile")
	volatile.take_hit(10000, Vector3.ZERO, false, false, "shot")
	check(hostile_count() >= 10, "a volatile foe bursts into a ring of embers")
	clear_combat()
	var warded = foe("mote", Vector3(-3, 0, 0))
	warded.make_elite("warded")
	warded.speed = 0.0
	var full = warded.hp
	warded.take_hit(5, Vector3.ZERO, false, false, "shot")
	check(is_equal_approx(warded.hp, full) and warded.ward_up, "a ward turns shots")
	warded.dashed_through()
	warded.take_hit(5, Vector3.ZERO, false, false, "shot")
	check(not warded.ward_up and warded.hp < full, "a dash through pops it")
	var bombed = foe("mote", Vector3(3, 0, -3))
	bombed.make_elite("warded")
	game.blast(bombed.global_position, 1.5, 3.0, true, null)
	check(not bombed.ward_up, "so does a blast")

## The Hearth Warden: sound, its lantern's light, the dark, the stun.
func test_warden() -> void:
	await arena(1, "boss")
	var warden = game.get_boss()
	check(warden != null and warden.kind == "warden" and Foes.boss_name(warden.kind) == "THE HEARTH WARDEN", "the cellar's boss is the Hearth Warden")
	warden.summon = 99.0
	warden.speed = 0.0
	var aim: Vector3 = warden.swing_direction()
	game.player.place(warden.global_position - aim * 5.0)
	var hp = warden.hp
	warden.take_hit(100, Vector3.ZERO, false, false, "shot")
	var glancing = hp - warden.hp
	game.player.place(warden.global_position + aim * 4.0)
	hp = warden.hp
	warden.take_hit(100, Vector3.ZERO, false, false, "shot")
	var full = hp - warden.hp
	check(glancing > 0 and absf(glancing / full - warden.GLANCING) < .01, "outside its lantern's light shots barely hurt it (%.1f of %.1f)" % [glancing, full])
	game.player.place(warden.global_position - aim * 6.0)
	game.noises.clear()
	game.make_noise(Vector3(4, 0, -3), 3.0)
	warden.swing_angle = atan2(aim.x, aim.z)
	warden.swing_dir = 0.0
	step(1)
	check(Vector2(warden.target.x - 4, warden.target.z + 3).length() < .1, "blind, it goes where the last loud noise was")
	warden.hp = warden.max_hp * .49
	step(1)
	check(warden.phase == 2 and game.room.lantern_points.is_empty(), "at half health it puts out every lantern")
	var lantern_at: Vector3 = warden.lantern.global_position
	game.spawn_shot(Vector3(lantern_at.x, .65, lantern_at.z), Vector3.RIGHT, warden.LANTERN_HP + 1, 0.1, {}, Color.WHITE, true)
	step(1)
	check(warden.lantern_broken and warden.stunned > 0 and is_equal_approx(warden.damage_scale("shot"), 2.0), "its own lantern can be shot apart, stunning it")
	warden.take_hit(100000, Vector3.ZERO, false, false, "shot")
	step(15)
	check(game.room.open and is_instance_valid(game.stairs), "the Warden falls and the stair rises")

## The Mosskeeper: moss, fire in its roots, the three bulbs.
func test_mosskeeper() -> void:
	await arena(2, "boss")
	var heart = game.get_boss()
	check(heart != null and heart.kind == "mosskeeper", "the halls' boss is the Mosskeeper")
	heart.sprout = 99.0
	heart.spore = 99.0
	heart.timer = 99.0
	game.player.place(heart.global_position + Vector3(0, 0, 6))
	var miss = game.spawn_shot(heart.global_position + Vector3(4, .65, 3), Vector3.RIGHT, 1, 0.1, {}, Color.WHITE, true)
	miss.finish()
	check(game.residue.kind_at(heart.global_position + Vector3(4, 0, 3)) == "moss", "a missed shot grows moss where it lands")
	game.residue.add("moss", heart.global_position, 2.6)
	heart.hp = 200.0
	step(65)
	check(heart.hp > 200.0, "moss joined to the heart heals it")
	var healed = heart.hp
	game.residue.ignite(heart.global_position + Vector3(2.4, 0, 0), .7)
	step(45)
	check(heart.hp < healed, "fire running through its moss burns the heart")
	heart.take_hit(100000, Vector3.ZERO, false, false, "shot")
	var bulbs: Array = heart.bulbs
	check(heart.alive and heart.phase == 2 and not heart.targetable and is_equal_approx(heart.hp, heart.max_hp * heart.PHASE_TWO) and bulbs.size() == 3, "a killing blow sends it below, into three bulbs")
	bulbs[0].take_hit(10000, Vector3.ZERO, false, false, "shot")
	check(bulbs[0].alive and bulbs[0].wilted > 0 and not bulbs[0].targetable, "a bulb struck down wilts")
	step(roundi(3.1 * 60))
	check(bulbs[0].wilted <= 0 and bulbs[0].targetable and bulbs[0].hp > 0, "alone, it grows back")
	for bulb in bulbs: bulb.take_hit(10000, Vector3.ZERO, false, false, "shot")
	step(15)
	check(not is_instance_valid(heart) or not heart.alive, "all three wilted together, the Mosskeeper falls")
	check(game.room.open, "and the room opens")

## The Last Light: your own weapon, drained lanterns, the end in the light.
func test_last_light() -> void:
	await arena(3, "boss")
	var thief = game.get_boss()
	check(thief != null and thief.kind == "last_light", "the top floor's boss is the Last Light")
	thief.speed = 0.0
	run.weapon_id = "scatter"
	game.player.place(thief.global_position + Vector3(0, 0, 7))
	for shot in game.shots.duplicate():
		if is_instance_valid(shot): shot.remove()
	game.shots.clear()
	thief.mirror_volley(Vector3.BACK)
	check(hostile_count() == int(catalog.weapon_by_id["scatter"].count), "it fires the player's own weapon back (%d)" % hostile_count())
	thief.fire_timer = 99.0
	var lit_before = game.room.lantern_points.size()
	thief.drain = 0.0
	step(roundi((thief.CHANNEL + .2) * 60))
	check(game.room.lantern_points.size() == lit_before - 1 and thief.radiance == 1 and is_equal_approx(thief.damage_scale("shot"), .88), "it drains a lantern and grows stronger")
	game.relight(game.room.lantern_near(Vector2.ZERO, 999.0, false))
	check(thief.radiance == 0, "relighting the lantern takes that strength back")
	thief.drain = 0.0
	step(1)
	thief.take_hit(thief.INTERRUPT + 5, Vector3.ZERO, false, false, "shot")
	step(2)
	check(thief.channel.is_empty() and game.room.lantern_points.size() == lit_before, "enough damage breaks its drain")
	thief.hp = thief.max_hp * .3
	step(1)
	check(thief.final and game.room.lantern_points.is_empty(), "near the end it swallows every lantern")
	game.player.place(thief.global_position + Vector3(0, 0, 9))
	var hp = thief.hp
	thief.take_hit(50, Vector3.ZERO, false, false, "shot")
	check(is_equal_approx(thief.hp, hp), "then nothing touches it out of the light")
	game.player.place(thief.global_position + Vector3(0, 0, 2))
	thief.take_hit(50, Vector3.ZERO, false, false, "shot")
	check(thief.hp < hp, "but in the player's own glow it can be struck")
	thief.take_hit(100000, Vector3.ZERO, false, false, "shot")
	step(1)
	check(game.room.lantern_points.size() == game.room.lanterns.size() and game.kindle_level() == 3, "when it falls every lantern burns and the light returns")

## A restarted fight is the same fight.
func test_encounters() -> void:
	game.start_run("candle", 61001, false)
	run.plan_climb("legacy_tower")
	run.floor_number = 3
	run.generate_floor()
	var id = ""
	for key in run.rooms:
		if run.rooms[key].type == "combat": id = key
	run.current_room = id
	game.enter_room(Vector3(0, 0, 2))
	var first = game.enemies.map(func(e): return "%s/%s" % [e.kind, e.elite])
	game.enter_room(Vector3(0, 0, 2))
	var second = game.enemies.map(func(e): return "%s/%s" % [e.kind, e.elite])
	check(first == second and first.size() >= 5, "re-entering an unwon room meets the same foes")
	var mote = foe("mote", Vector3.ZERO)
	check(is_equal_approx(mote.max_hp, 15.0 * (1.0 + 2 * mote.FLOOR_HEALTH)), "foes grow 30% stronger a floor")
