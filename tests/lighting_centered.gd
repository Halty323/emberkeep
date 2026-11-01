extends SceneTree
## Eye-level lighting must stay readable, local and bounded without fake
## luminous floor cards or allocating cube-shadow maps.
var checks := 0
var failures := 0
var game

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("exercise")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func settle() -> void:
	for i in 3: await process_frame

func exercise() -> void:
	var run = root.get_node("Run")
	var settings = root.get_node("Settings")
	var lighting = load("res://scripts/dungeon/floor_light.gd")
	var rng_state = run.rng.state
	var previous_lamp := 0.0
	for level in [1,2,3]:
		var source: Dictionary = lighting.profile(level)
		var original = source.duplicate(true)
		var profile: Dictionary = lighting.first_person(source)
		check(source == original, "FPS profile does not mutate a shared legacy floor")
		check(profile.key < source.key, "actual fixtures lead instead of a flat global key")
		check(profile.lamp > source.lamp and profile.lamp > previous_lamp, "local lantern light grows as the tower climbs")
		check(profile.ambient >= .08 and profile.ambient <= .16, "cool visibility floor retains deep, readable shadows")
		check(profile.foe_body == source.foe_body and profile.foe_glow == source.foe_glow, "enemy readability contract is preserved")
		check(profile.lit == source.lit, "lighting presentation does not alter burning lantern membership")
		check(profile.doorway > 0.0 and profile.doorway < source.doorway, "doorway inlay remains visible without a neon frame")
		previous_lamp = profile.lamp
	check(run.rng.state == rng_state, "lighting profiles consume no gameplay randomness")
	settings.set_value("sound", false)
	settings.set_value("music", false)
	settings.set_value("shadows", true)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.start_run("candle", 18523427, false)
	game.paused = true
	await settle()
	var room = game.room
	check(room.first_person_room, "fixture uses the default eye-level room")
	check(room.lamps.size() <= room.MAX_ACTIVE_FILLS and room.shadow_lamps.size() <= room.MAX_LANTERN_SHADOWS, "fixed fill and shadow budgets remain bounded")
	for lamp in room.lamps:
		check(not lamp.shadow_enabled, "fill light does not allocate a six-face cube shadow")
		check(room.lantern_points.any(func(p): return (p+Vector3(0,1.65,0)).distance_to(lamp.position)<.01), "fixture light sits at the actual flame height")
	for lantern in room.lanterns:
		check(lantern.glass.mesh is QuadMesh, "opaque emissive cube is replaced by an open flame")
		check(lantern.glass.visible == lantern.burning, "flame matches the actual burning state")
		check(not lantern.pool.visible and not lantern.glow.visible, "real lighting replaces floor and tilted air cards")
	var lamp_ids = room.lamps.map(func(lamp): return lamp.get_instance_id())
	for i in 180: room._process(1.0/60.0)
	check(room.lamps.map(func(lamp): return lamp.get_instance_id()) == lamp_ids, "flame flicker reuses the existing lights")
	for enabled in [false,true,false,true]:
		settings.set_value("shadows", enabled)
		room.apply_lighting_quality()
		check(room.shadow_lamps.all(func(lamp): return lamp.shadow_enabled == enabled and lamp.visible == enabled), "shadow setting changes only the existing shadow light")
		check(room.lamps.map(func(lamp): return lamp.get_instance_id()) == lamp_ids, "shadow toggles retain real warm fills")
	for index in room.lanterns.size(): room.set_lantern(index,false)
	await settle()
	check(room.lamps.is_empty() and room.lantern_points.is_empty(), "snuffing every lantern extinguishes every fill")
	check(room.shadow_lamps.all(func(lamp): return not lamp.visible), "no shadow light remains without a burning fixture")
	check(room.lanterns.all(func(lantern): return not lantern.glass.visible), "snuffing removes flame emission")
	room.set_lantern(0,true)
	await settle()
	check(room.lamps.size()==1 and room.lanterns[0].glass.visible, "relighting restores one local fixture and flame")
	check(room.shadow_lamps.size()==1 and room.shadow_lamps[0].visible, "relighting reuses the single shadow map")
	check(not room.lit_at(Vector3(1000,0,1000)) and room.lit_at(room.lanterns[0].at), "light gameplay membership is unchanged")
	game.queue_free()
	await settle()
	print("LIGHTING CENTERED: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
