extends SceneTree
## Physical split-level regression: real collider traversal, enemy routes and
## saved blueprints, including the negative-height cellar cutout.
var checks := 0
var failures := 0
var game
var run
var terrain_type: Script
var geometry_type: Script
var generator_type: Script

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("exercise")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func step(motion: Vector2, count: int) -> void:
	for frame in count:
		await physics_frame
		game.player.update_sim(1.0/60.0,motion,game.fps.forward(),false)

func place(at: Vector3) -> void:
	game.player.place(at)
	game.player.velocity = Vector3.ZERO
	game.player.push = Vector3.ZERO
	game.player.dash_time = 0
	game.player.dash_cooldown = 0
	game.fps.yaw = 0
	game.fps.pitch = 0

func exercise() -> void:
	run = root.get_node("Run")
	terrain_type = load("res://scripts/first_person/room_terrain.gd")
	geometry_type = load("res://scripts/dungeon/room_geometry.gd")
	generator_type = load("res://scripts/dungeon/floor_generator.gd")
	root.get_node("Settings").set_value("sound",false)
	root.get_node("Settings").set_value("music",false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.start_run("candle",18523427,false)
	game.paused = true
	await check_planning()
	for kind in ["upper","cellar"]: await check_physics(kind)
	game.queue_free()
	await process_frame
	print("VERTICAL ROOMS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func check_planning() -> void:
	var geometry = geometry_type.new([Vector2i.ZERO,Vector2i.RIGHT])
	var before: int = run.rng.state
	var kinds := {}
	var generated := 0
	for seed_value in 160:
		var data := {"generation":3,"type":"combat","id":"0,0","seed":seed_value,"cells":[[0,0],[1,0]]}
		var zones := [{"kind":"pedestal","circle":Vector2(9,0),"radius":2.6}]
		var first: Dictionary = terrain_type.plan_generation(data,geometry,zones)
		check(first == terrain_type.plan_generation(data,geometry,zones),"planning repeats without gameplay randomness")
		if first.is_empty(): continue
		generated += 1
		kinds[first.kind] = true
		check(terrain_type.valid_blueprint(first,geometry),"planned full-height annex stays within the footprint")
		data.fps_terrain = first
		var reservations: Array = terrain_type.reserved_zones(data,geometry)
		check(reservations.size()==1 and reservations[0].rect.has_point(terrain_type.decode_rect(first.ledge).get_center()),"furnishing reserves the actual vertical destination")
	check(generated>35 and generated<120,"vertical rooms occur by chance rather than in every room")
	check(kinds.has("upper") and kinds.has("cellar"),"both upper and cellar rooms occur")
	check(run.rng.state==before,"planning never spends gameplay RNG")
	var legacy := {"version":1,"ledge":[2.7,-4.6,3.4,2.6],"ramp":[2.7,-2.0,3.4,3.6]}
	check(terrain_type.valid_blueprint(legacy,geometry),"older gallery checkpoints stay valid")
	var malformed := {"version":2,"kind":"cellar","rise":-99,"ledge":[2.1,-5.2,3.8,3.8],"ramp":[2.1,-1.4,3.8,4.8]}
	check(not terrain_type.valid_blueprint(malformed,geometry),"unbounded saved cellar depth is rejected")
	malformed.rise = terrain_type.CELLAR_RISE
	malformed.kind = "unknown"
	check(not terrain_type.valid_blueprint(malformed,geometry),"unknown saved vertical kind is rejected")
	var expanded := {"version":2,"kind":"upper","rise":2.8,"ledge":[1.7,-5.2,4.6,4.2],"ramp":[1.7,-1.0,4.6,4.8]}
	var rear := {"cell":Vector2i.ZERO,"dir":Vector2i.UP,"state":"wall"}
	check(terrain_type.valid_blueprint(expanded,geometry,{"rear":rear}),"closed-wall registry entries do not reject a valid larger annex")
	rear.state="open"
	check(not terrain_type.valid_blueprint(expanded,geometry,{"rear":rear}),"an actual doorway still reserves its approach beside an annex")
	var sections: Array[Rect2] = [Rect2(-9,-7,18,14)]
	var pieces: Array = terrain_type.subtract_rects(sections,Rect2(2.1,-5.2,3.8,8.6))
	var area := 0.0
	for piece in pieces: area += piece.get_area()
	check(absf(area-(18*14-3.8*8.6))<.01,"floor cutout removes exactly the cellar footprint")

func check_physics(kind: String) -> void:
	var floor_data := {"rooms":{},"portals":{},"owners":{},"generator":2}
	generator_type.place_room(floor_data,root.get_node("Content").record("rooms","hall_2x1"),0,Vector2i.ZERO,472,1)
	run.rooms = floor_data.rooms
	run.portals = {}
	run.current_room = "0,0"
	var record: Dictionary = run.rooms[run.current_room]
	record.type = "combat"
	record.cleared = true
	record.claimed = true
	record.props = []
	record.chests = []
	record.items = []
	record.partitions = []
	record.generation = 3
	var rise: float = terrain_type.UPPER_RISE if kind=="upper" else terrain_type.CELLAR_RISE
	record.fps_terrain = {"version":2,"kind":kind,"rise":rise,"ledge":[1.7,-5.2,4.6,4.2],"ramp":[1.7,-1.0,4.6,4.8]}
	game.enter_room(Vector3(0,0,2))
	game.paused = true
	for enemy in game.enemies: enemy.queue_free()
	game.enemies.clear()
	await step(Vector2.ZERO,2)
	var terrain = game.room.terrain
	check(terrain.challenge() and terrain.kind==kind,"loaded " + kind + " is a rewarded challenge room")
	var top: Vector2 = terrain.ledge.get_center()
	var foot := Vector3(terrain.ramp.get_center().x,.04,terrain.ramp.end.y+.7)
	place(foot)
	await step(Vector2.ZERO,5)
	await step(Vector2(0,-1),108)
	check(game.player.position.z<terrain.ramp.position.y+.1 and absf(game.player.position.y-rise)<.14,"walk physically into " + kind)
	await step(Vector2.ZERO,12)
	check(absf(game.player.position.y-rise)<.14,"standing remains stable at " + kind + " elevation")
	game.fps.jump_buffer = .14
	await step(Vector2.ZERO,14)
	check(game.player.position.y>rise+.55,"jump leaves the " + kind + " floor")
	await step(Vector2.ZERO,55)
	check(absf(game.player.position.y-rise)<.15,"jump lands on actual " + kind + " collision")
	await step(Vector2(0,1),124)
	check(game.player.position.z>terrain.ramp.end.y and absf(game.player.position.y)<.14,"walk back from " + kind + " to the main floor")
	check(game.room.navigation(.5).reachable(Vector2(foot.x,foot.z),top),"enemy navigation reaches " + kind + " by its ramp")
	check(not game.room.navigation(.5).line_clear(top,top+Vector2.LEFT*3.0),"enemy routing rejects a " + kind + " cliff shortcut")
	place(Vector3(top.x,rise+.04,top.y))
	await step(Vector2.ZERO,10)
	check(absf(game.camera.position.y-game.player.position.y-game.fps.EYE)<.1,"camera remains at actual " + kind + " eye height")
	var enemy = game.spawn_enemy(foot,"mote")
	enemy.place(foot)
	enemy.timer = 1000
	game.player.invulnerability = 100
	for frame in 360:
		await physics_frame
		enemy.update_sim(1.0/60.0)
	check(absf(enemy.position.y-rise)<.35 and Vector2(enemy.position.x,enemy.position.z).distance_to(top)<1.8,"real enemy pursues vertically into " + kind)
	place(foot)
	for frame in 420:
		await physics_frame
		enemy.update_sim(1.0/60.0)
	check(absf(enemy.position.y)<.25 and Vector2(enemy.position.x,enemy.position.z).distance_to(Vector2(foot.x,foot.z))<1.8,"real enemy returns from " + kind + " to main floor")
	enemy.queue_free()
	game.enemies.clear()
	await process_frame
	var reward: Vector3 = terrain.reward_point()
	check(absf(reward.y-rise)<.001 and terrain.ledge.has_point(Vector2(reward.x,reward.z)),"reward point belongs to " + kind + " landing")
	game.residue.add("water",reward,1.1)
	var other_level := Vector3(reward.x,0,reward.z)
	check(game.residue.kind_at(reward)=="water" and game.residue.kind_at(other_level)=="","floor residues cannot affect the other " + kind + " elevation")
	check(is_equal_approx(game.residue.slows(reward),.8) and is_equal_approx(game.residue.slows(other_level),1.0),"water drag follows the actual " + kind + " floor")
	check(game.residue.tiles_in(other_level,.5).is_empty(),"effects at another height cannot paint " + kind + " floor")
	game.residue.add_cloud(reward,1.2)
	check(game.residue.cloud_at(reward)>=0 and game.residue.cloud_at(other_level)<0,"cloud effects stay on their " + kind + " level")
	var before := JSON.stringify(record.fps_terrain)
	game.enter_room(Vector3(0,0,2))
	check(JSON.stringify(record.fps_terrain)==before,"re-entering preserves " + kind + " blueprint")
	check(game.room.terrain.kind==kind and absf(game.room.floor_height(reward)-rise)<.001,"reloaded " + kind + " retains physical height")
