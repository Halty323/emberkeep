extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("exercise")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: "+label)
func exercise() -> void:
	var type = load("res://scripts/graphics/room_illumination.gd")
	var lighting = load("res://scripts/dungeon/floor_light.gd")
	var settings = root.get_node("Settings")
	var run = root.get_node("Run")
	settings.set_value("sound",false); settings.set_value("music",false)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game); current_scene = game
	game.set_process(false); game.set_physics_process(false)
	var colors := {}
	for theme in type.PALETTES:
		game.start_run("candle",72913504,false)
		run.floor_plan[0] = theme
		run.generate_floor()
		game.enter_room(Vector3.ZERO)
		game.room.resume_build(true)
		var room = game.room
		var illumination = room.illumination
		check(illumination.theme == theme, "fixture theme follows the actual floor, not the furniture layout")
		check(not illumination.fixtures.is_empty() and illumination.fixtures.size() <= type.MAX_FIXTURES, "each theme receives a bounded fixture composition")
		check(illumination.lamps.size() <= type.MAX_LIGHTS, "colored lights stay inside their own fixed budget")
		check(illumination.volumes.size() == illumination.lamps.size(), "each local fog volume belongs to a real light")
		check(illumination.find_children("*","CollisionObject3D",true,false).is_empty(), "hanging decoration adds no collision or navigation obstacles")
		check(illumination.lamps.all(func(lamp): return not lamp.shadow_enabled), "extra colored lights allocate no additional shadow maps")
		check(room.shadow_lamps.size() <= 1, "the hero fixture reuses the single existing local shadow map")
		for fixture in illumination.fixtures:
			check(fixture.source.y > fixture.floor + 2.0 and fixture.source.y < fixture.ceiling, "flames have headroom below a real ceiling support")
			colors[fixture.color.to_html()] = true
		for level in ["low","balanced","high"]:
			settings.set_value("effects_detail",level)
			illumination.apply_quality()
			var shown: Array = illumination.volumes.filter(func(volume): return volume.visible)
			check(shown.is_empty() == (level == "low"), "only Low omits the volumetric pass")
			for volume in shown:
				check(int(volume.material_override.get_shader_parameter("steps")) <= 10, "local integration has a finite mobile sampling budget")
		var before := JSON.stringify(illumination.fixtures)
		var random_before: int = run.rng.state
		var second = type.new()
		room.add_child(second); second.setup(room)
		check(JSON.stringify(second.fixtures) == before, "fixture layout is deterministic")
		check(run.rng.state == random_before, "cosmetic layout does not consume gameplay randomness")
		second.free()
		await process_frame
	game.start_run("candle",31609250,false)
	for record in run.rooms.values():
		if record.get("fps_terrain",{}).get("kind","") != "floor": continue
		run.current_room = record.id
		game.enter_room(Vector3.ZERO)
		game.room.resume_build(true)
		var illumination = game.room.illumination
		check(illumination.fixtures.any(func(f): return f.floor > 3.0), "two-storey rooms include upstairs fixtures")
		check(illumination.fixtures.any(func(f): return f.floor < 1.0), "two-storey rooms retain lower-storey fixtures")
		for fixture in illumination.fixtures:
			if fixture.floor < 1.0 and game.room.terrain.loft.on_deck(Vector2(fixture.source.x,fixture.source.z)):
				check(fixture.ceiling < 3.2, "lower chains attach to the slab instead of crossing the upper room")
	check(colors.size() >= 12, "floors have independently colored key/fill palettes")
	for level in [1,2,3]:
		var light: Dictionary = lighting.first_person(lighting.profile(level))
		check(light.ambient < .08 and light.key < .03, "fixtures dominate over flat ambient/directional illumination")
	game.end_run(false); game.reaper.flush(); game.queue_free()
	await process_frame
	print("ROOM ILLUMINATION: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
