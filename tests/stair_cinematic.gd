extends SceneTree
## Physical camera clearance, simulation-clock pause and presentation-state
## restoration while the real stair path crosses a complete generated room.
var game
var run
var checks := 0
var failures := 0
var view

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("exercise")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func settle() -> void:
	await process_frame
	await physics_frame
	await process_frame

func exercise() -> void:
	# Load project classes only after autoload registration in --script mode.
	var cine = load("res://scripts/presentation/stair_cinematic.gd")
	var stair_type = load("res://scripts/dungeon/staircase.gd")
	var motor = load("res://scripts/first_person/controller.gd")
	var geo = load("res://scripts/geo.gd")
	var props = load("res://scripts/dungeon/prop_visuals.gd")
	run = root.get_node("Run")
	root.get_node("Settings").set_value("sound",false)
	root.get_node("Settings").set_value("music",false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.set_process(false)
	game.start_run("candle",18523427,false)
	for id in run.rooms:
		if run.rooms[id].type == "boss":
			run.current_room = id
			break
	run.rooms[run.current_room].cleared = true
	run.rooms[run.current_room].claimed = true
	game.enter_room(Vector3(0,0,2))
	game.paused = false
	await settle()
	check(is_instance_valid(game.stairs) and game.stairs.built,"real generated boss room has its complete exit stair")
	game.player.place(game.stairs.approach_point())
	game.player.velocity = Vector3.ZERO
	game.fps.yaw = 0
	game.fps.pitch = -.12
	game.update_camera(0,true)
	var first_eye: Transform3D = game.camera.global_transform
	var start: Vector3 = game.player.position
	var path: Array = [start,start] + game.stairs.climb_path()
	var times: Array = [cine.PULLBACK,cine.APPROACH*.6,cine.APPROACH*.4]
	for i in stair_type.STEPS: times.append(cine.CLIMB/stair_type.STEPS)
	game.transition = {"kind":"stairs","phase":"climb","time":0.0,"path":path,"times":times}
	view = cine.new()
	view.begin(game)
	check(view.pose(game),"stair presentation owns one existing camera")
	check(game.camera.global_transform.is_equal_approx(first_eye),"departure starts exactly at the existing eye pose")
	check(not game.fps.weapon.visible and not game.player.gun.visible,"cinematic hides both held and world caster models")
	check(not game.player.visual.visible,"pullback does not reveal a face inside the first-person eye")
	game.transition.time = cine.PULLBACK*.5
	view.pose(game)
	check(game.camera.position.distance_to(first_eye.origin)>.15,"camera visibly slides backward during the initial hold")
	check(game.player.position.is_equal_approx(start),"initial pullback holds the character at the stair approach")
	check(game.player.visual.visible,"character becomes visible once camera clears the body")
	game.transition.time = cine.PULLBACK
	view.pose(game)
	var shoulder: Transform3D = game.camera.global_transform
	game.paused = true
	for i in 12: view.pose(game)
	check(game.camera.global_transform.is_equal_approx(shoulder),"paused render frames do not advance or drift the cinematic")
	check(view.collision_exclusions.size()>=2,"camera ignores the player and stair reservation cylinder")
	game.paused = false
	# A new physical wall behind the subject must shorten the camera boom.
	var wall_at: Vector3 = game.player.position+view.behind*1.65+Vector3.UP*1.3
	var wall = geo.collider(game.scene_root,wall_at,Vector3(8,4,.35))
	wall.look_at(wall_at+view.behind)
	await settle()
	view.pose(game)
	check(game.camera.position.distance_to(game.player.position)<shoulder.origin.distance_to(game.player.position),"camera retracts before a physical wall")
	var framed: Vector3 = (game.player.global_position+Vector3.UP*.88-game.camera.global_position).normalized()
	check((-game.camera.global_basis.z).dot(framed)>.99,"a retracted camera keeps the character centered")
	var camera_shape := SphereShape3D.new()
	camera_shape.radius = cine.CAMERA_RADIUS*.95
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = camera_shape
	query.transform = Transform3D(Basis.IDENTITY,game.camera.global_position)
	query.collision_mask = 1 | props.FURNITURE_LAYER
	query.exclude = view.collision_exclusions
	check(game.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"camera sphere remains outside wall and furniture collision")
	wall.queue_free()
	await settle()
	var total := 0.0
	for duration in times: total += float(duration)
	for tick in 70:
		game.transition.time = cine.PULLBACK+(total-cine.PULLBACK)*float(tick)/69.0
		game.player.walk_to(game.path_point(path,times,game.transition.time))
		view.pose(game)
	check(game.player.position.y>5.0,"scripted character reaches the physical upper stair steps")
	check(game.camera.position.y>first_eye.origin.y+2.0,"follow camera climbs with the character")
	check(game.camera.global_transform.is_finite(),"spiral follow retains a finite camera transform")
	check(absf(game.fps.yaw)<.001 and absf(game.fps.pitch+.12)<.001,"spiral steps do not spin or overwrite the original input aim")
	game.transition = {}
	check(not view.pose(game) and not view.active,"finishing transition releases camera ownership")
	check(not game.player.visual.visible and game.fps.weapon.visible,"normal first-person body and caster visibility are restored")
	check(is_equal_approx(game.camera.fov,float(root.get_node("Settings").values.fov)),"normal FOV returns exactly after release")
	# The next floor's scripted emergence keeps the camera above its floor,
	# hides the cover while climbing, then eases exactly into the exit-facing eye.
	run.next_floor()
	game.enter_room(Vector3(0,0,2))
	game.paused = false
	await settle()
	var well: Vector3 = game.well_spot
	var out := Vector2(game.room.pedestal.x-well.x,game.room.pedestal.z-well.z).normalized()
	var safe: Vector2 = game.room.geometry.safe_point(Vector2(well.x,well.z)+out*(stair_type.OUTER+.9),.5,game.room.blocked_at)
	var arrival := Vector3(safe.x,0,safe.y)
	var arrival_path: Array = stair_type.rise_path(well,arrival)
	var arrival_times: Array = []
	for i in arrival_path.size()-2: arrival_times.append(game.ARRIVE_RISE/(arrival_path.size()-2))
	arrival_times.append(game.ARRIVE_STEP_OFF)
	game.transition = {"kind":"stairs","phase":"arrive","time":0.0,"path":arrival_path,"times":arrival_times}
	game.player.position = arrival_path[0]
	view.begin(game,true)
	view.pose(game)
	check(game.camera.position.y>=1.0,"arrival never places camera under the room floor")
	check(is_instance_valid(view.well_cover) and not view.well_cover.visible,"stairwell cover opens while the character emerges")
	check(is_equal_approx(run.view_angles[0],game.fps.yaw),"arrival exit-facing aim is ready before the checkpoint is saved")
	var arrival_total := 0.0
	for duration in arrival_times: arrival_total += float(duration)
	game.transition.time = arrival_total
	game.player.walk_to(arrival)
	view.pose(game)
	check(game.camera.position.is_equal_approx(arrival+Vector3.UP*motor.EYE),"arrival finishes exactly at the first-person eye")
	var cover: MeshInstance3D = view.well_cover
	view.cancel(game)
	check(cover.visible and not view.active,"cancel restores the stairwell cover and camera ownership")
	check(not game.player.visual.visible and not game.player.gun.visible,"cancel leaves no visible third-person body or world gun")
	game.transition = {}
	# Exercise the actual main-scene hooks as one continuous climb, rather
	# than only asking a standalone helper for poses.
	game.start_run("candle",18523427,false)
	for id in run.rooms:
		if run.rooms[id].type == "boss": run.current_room=id; break
	run.rooms[run.current_room].cleared=true
	run.rooms[run.current_room].claimed=true
	game.enter_room(Vector3(0,0,2))
	game.paused=false
	await settle()
	game.player.place(game.stairs.approach_point())
	game.update_camera(0,true)
	var departure_floor: int = run.floor_number
	game.begin_climb()
	check(game.transition.get("kind","") == "stairs" and game.stair_cinematic.active,"main begins the full cinematic instead of an instant FPS floor switch")
	var showed_actor := false
	var reached_arrival := false
	for tick in 420:
		if game.transition.is_empty(): break
		game.advance_transition(1.0/60.0)
		game.update_camera(1.0/60.0)
		showed_actor = showed_actor or game.player.visual.visible
		reached_arrival = reached_arrival or game.transition.get("phase","") == "arrive"
		if tick%8==0: await settle()
	check(showed_actor,"main keeps the walking character visible during the climb")
	check(reached_arrival and run.floor_number == departure_floor+1,"the completed spiral switches floor once and starts the arrival scene")
	check(game.transition.is_empty() and not game.stair_cinematic.active,"arrival releases the main transition and cinematic together")
	check(not game.player.visual.visible and game.fps.weapon.visible,"the next floor restores the real first-person rig")
	check(game.camera.position.is_equal_approx(game.player.position+Vector3.UP*motor.EYE),"main arrival lands exactly at the saved standing eye")
	game.return_to_title()
	check(not view.active and not game.stair_cinematic.active and game.in_menu,"returning to the hearth leaves no cinematic state")
	game.queue_free()
	await process_frame
	print("STAIR CINEMATIC: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
