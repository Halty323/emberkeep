extends SceneTree
## Opt-in native capture of the experimental spells: a ray, lightning, an
## eruption's rune and its rising for several elements, and flying spells of
## each look. Needs a display (or Xvfb) and EMBERKEEP_SPELLS_CAPTURE set to an
## output directory.
var game
var run
var Forge

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("go")

func frames(count: int) -> void:
	for i in count: await process_frame

func shot(out: String, label: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	if out != "": image.save_png(out.path_join("spell_%s.png" % label))
	print("SPELLS CAPTURE %s" % label)

## Only the spells move (foes hold still for the picture), at the game's own
## tick; the clock is slowed so a software renderer's long frames do not
## skip a quarter-second beam.
func step(count: int) -> void:
	for i in count:
		for spell in game.shots.duplicate():
			if is_instance_valid(spell) and spell.alive: spell.update_sim(1.0 / 60.0)
		for enemy in game.enemies:
			if is_instance_valid(enemy): enemy.show_flash(1.0 / 60.0)
		await process_frame

func clear() -> void:
	for spell in game.shots:
		if is_instance_valid(spell): spell.queue_free()
	game.shots.clear()

## The first forged spellbook that matches.
func find(test: Callable) -> Dictionary:
	for seed_value in range(1, 600):
		for weapon in Forge.starters(seed_value):
			if test.call(weapon): return weapon
		for slot in range(20, 30):
			var other: Dictionary = Forge.lookup(Forge.id_for(seed_value, slot))
			if test.call(other): return other
	return {}

func foes(spots := [-1.6, 0.0, 1.6]) -> void:
	for enemy in game.enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.alive = false
			enemy.queue_free()
	game.enemies.clear()
	for x in spots:
		var foe = game.spawn_enemy(game.player.position + Vector3(x, 0, -5.5), "brute")
		foe.max_hp = 5000.0
		foe.hp = 5000.0

func cast(weapon: Dictionary) -> void:
	run.weapon_id = weapon.id
	game.player.aim_direction = game.fps.shot_direction(game.fps.shot_origin())
	game.player.fire_cooldown = 0.0
	game.player.fire()

func go() -> void:
	var out := OS.get_environment("EMBERKEEP_SPELLS_CAPTURE")
	run = root.get_node("Run")
	Forge = load("res://scripts/items/forge.gd")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(2)
	game.start_run("candle", 7072, false)
	await frames(30)
	run.floor_number = 3
	var fight: Array = run.rooms.keys().filter(func(id): return run.rooms[id].type == "combat")
	run.current_room = fight[0]
	run.rooms[fight[0]].cleared = true
	game.enter_room(Vector3(0, 0, 4))
	await frames(30)
	game.set_physics_process(false)
	game.player.place(Vector3(0, game.room.floor_height(Vector3(0, 0, 5)), 5))
	game.fps.yaw = 0.0
	game.fps.pitch = -.08
	await frames(4)
	Engine.time_scale = .06
	foes()
	cast(find(func(w): return w.get("archetype", "") == "ray"))
	await step(2)
	shot(out, "ray")
	clear()
	foes()
	cast(find(func(w): return w.get("archetype", "") == "lightning"))
	# Lightning gathers for a breath before it strikes.
	await step(9)
	shot(out, "lightning")
	clear()
	for element in ["ember", "frost", "radiance", "tide"]:
		# Foes to either side, so what rises in the middle shows.
		foes([-2.8, 2.8])
		cast(find(func(w): return w.get("archetype", "") == "eruption" and w.element == element))
		await step(12)
		if element == "ember": shot(out, "rune")
		await step(14)
		shot(out, "erupt_" + element)
		clear()
	foes()
	for look in ["shard", "needle", "comet", "disc"]:
		cast(find(func(w): return w.get("form", "") == look))
		await step(6)
		shot(out, "form_" + look)
		clear()
	Engine.time_scale = 1.0
	game.queue_free()
	await frames(3)
	quit(0)
