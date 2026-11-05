extends SceneTree
## Every kind of spellbook breaks crates and barrels: a flying spell, a ray,
## lightning and an eruption, each aimed at a breakable prop in a real
## first-person room.
var checks := 0
var failures := 0

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("go")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func go() -> void:
	var run = root.get_node("Run")
	var forge = load("res://scripts/items/forge.gd")
	var settings = root.get_node("Settings")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in 3: await process_frame
	game.start_run("candle", 7072, false)
	for i in 20: await process_frame
	game.set_physics_process(false)
	var kinds := {}
	for seed_value in range(1, 100):
		for weapon in forge.starters(seed_value):
			if not kinds.has(weapon.archetype): kinds[weapon.archetype] = weapon.id
	for kind in ["projectile", "ray", "lightning", "eruption"]:
		var props: Dictionary = game.room.props
		var id := ""
		for key in props:
			if props[key].definition.has("breakable"):
				id = key
				break
		check(id != "", "a breakable prop is left for the %s" % kind)
		if id == "": continue
		var at: Vector3 = props[id].node.global_position
		var spot := at + Vector3(0, 0, 3.5)
		run.weapon_id = kinds[kind]
		game.player.place(Vector3(spot.x, game.room.floor_height(spot), spot.z))
		game.fps.yaw = 0.0
		for cast in 3:
			if not props.has(id): break
			game.update_camera(.016)
			game.player.aim_direction = (at + Vector3.UP * .45 - game.fps.shot_origin()).normalized()
			game.player.fire_cooldown = 0
			game.player.fire()
			for i in 40:
				for spell in game.shots.duplicate():
					if is_instance_valid(spell) and spell.alive: spell.update_sim(1.0 / 60.0)
		check(not props.has(id), "a %s spellbook breaks a crate or barrel" % kind)
		# Let the broken prop's collider go before the next spell is aimed.
		for i in 3: await process_frame
	game.queue_free()
	await process_frame
	# Every spell sound renders: real signal, no clipping, short enough to
	# trigger often, and all of them quickly enough for a worker at start-up.
	var started := Time.get_ticks_msec()
	var recipes: Dictionary = load("res://scripts/spell_audio.gd").recipes()
	for id in recipes:
		var stream: AudioStreamWAV = recipes[id].call()
		var peak := 0
		for i in range(0, stream.data.size(), 2): peak = maxi(peak, absi(stream.data.decode_s16(i)))
		var seconds := stream.data.size() / 2.0 / 22050.0
		check(peak > 3000 and peak < 32767 and seconds > .1 and seconds < 1.5, "the %s sound renders (peak %d, %.2f s)" % [id, peak, seconds])
	var took := Time.get_ticks_msec() - started
	print("spell sounds rendered in %d ms" % took)
	check(took < 8000, "spell sounds render in time (%d ms)" % took)
	for id in ["cast_ember", "cast_frost", "cast_storm", "cast_venom", "cast_radiance", "cast_glass", "cast_wax", "cast_tide", "ray", "charge", "crack", "thunder", "rumble", "whistle"]:
		check(recipes.has(id), "there is a %s sound" % id)
	for rising in load("res://scripts/items/spell_shapes.gd").RISINGS:
		check(recipes.has("rise_" + rising), "an eruption of %s has its own sound" % rising)
	print("SPELL PROPS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
