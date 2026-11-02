extends SceneTree
## Physical doorway presentation preserves portal triggers, collision and
## snuff-safe light budgets; fire keeps its authoritative damage mask.
var checks := 0
var failures := 0
func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("exercise")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+label)
func exercise() -> void:
	var settings = root.get_node("Settings")
	var run = root.get_node("Run")
	settings.set_value("sound",false)
	settings.set_value("music",false)
	var policy = load("res://scripts/graphics/render_policy.gd")
	policy.device_override=policy.for_device("Android","Imagination","PowerVR","gl_compatibility")
	settings.apply_render_policy()
	var generator = load("res://scripts/dungeon/floor_generator.gd")
	var geometry_api = load("res://scripts/dungeon/room_geometry.gd")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.start_run("candle",811115,false)
	var floor_data := {"rooms":{},"portals":{},"owners":{},"generator":2}
	var template: Dictionary = root.get_node("Content").record("rooms","hearth_1x1")
	var id: String = generator.place_room(floor_data,template,0,Vector2i.ZERO,811115,1)
	for direction in geometry_api.DIRECTIONS:
		generator.place_room(floor_data,template,0,direction,811115,1)
		generator.add_portal(floor_data,Vector2i.ZERO,direction)
	var record: Dictionary = floor_data.rooms[id]
	record.type="combat";record.cleared=true;record.claimed=true
	record.props=[];record.chests=[];record.mounts=[];record.pickups=[];record.partitions=[];record.fps_terrain={}
	run.rooms=floor_data.rooms;run.portals=floor_data.portals;run.current_room=id
	game.enter_room(Vector3(0,0,2))
	game.paused=true
	await process_frame
	var room = game.room
	check(room.gates.size()==4,"all four doorway orientations build")
	var rng_state: int = run.rng.state
	for gate in room.gates:
		check(gate.get_meta("physical_doorway",false),"doorway has physical connector presentation")
		check(gate.get_node("Barrier").has_node("LeftLeaf") and gate.get_node("Barrier").has_node("RightLeaf") and gate.get_node("Outline").get_child_count()==2,"each door keeps both hinged leaves alongside its new physical barrier")
		check(not gate.get_node("Barrier").visible and gate.get_node("Outline").visible,"open room shows the open leaf pose")
		var lights: Array = gate.find_children("*","Light3D",true,false)
		check(lights.is_empty(),"doorway does not allocate local or cube-shadow lights")
		var meshes: Array = gate.find_children("*","MeshInstance3D",true,false)
		check(meshes.size() <= 16,"door and walkable preview geometry stay in bounded finish batches")
		check(gate.get_node("Connector").find_children("*","StaticBody3D",true,false).size()==2,"preview has real floor and wall collision")
		check(meshes.all(func(mesh): return mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),"connector details add no shadow passes")
		check(not meshes.any(func(mesh): return mesh.material_override is StandardMaterial3D and mesh.material_override.blend_mode == BaseMaterial3D.BLEND_MODE_ADD),"open doorway has no emissive rectangle")
	room.set_open(false)
	check(room.gates.all(func(gate):return gate.get_node("Barrier").visible and not gate.get_node("Outline").visible),"combat sealing shows real closed leaves")
	room.set_open(true)
	check(room.gates.all(func(gate):return not gate.get_node("Barrier").visible and gate.get_node("Outline").visible),"clearing restores the connector opening")
	for direction in geometry_api.DIRECTIONS:
		var at: Vector2 = geometry_api.socket_point(Vector2i.ZERO,direction)-Vector2(direction)*.55
		check(geometry_api.in_trigger(at,Vector2i.ZERO,direction),"the existing approach trigger stays inside the room")
	check(run.rng.state==rng_state,"doorway presentation consumes no gameplay randomness")
	# Exercise the actual capsule through each unblocked approach rather
	# than only asserting that a door mesh has the expected shape.
	for direction in geometry_api.DIRECTIONS:
		var socket: Vector2 = geometry_api.socket_point(Vector2i.ZERO,direction)
		var from: Vector2 = socket-Vector2(direction)*2.1
		game.player.place(Vector3(from.x,.03,from.y))
		game.player.velocity=Vector3.ZERO
		game.player.push=Vector3.ZERO
		game.fps.pitch=0
		game.fps.yaw=atan2(-float(direction.x),-float(direction.y))
		for frame in 34:
			await physics_frame
			game.player.update_sim(1.0/60.0,Vector2(0,-1),game.fps.forward(),false)
		var flat := Vector2(game.player.position.x,game.player.position.z)
		check(geometry_api.in_trigger(flat,Vector2i.ZERO,direction),"real capsule can reach the doorway transition in each orientation")
		check(absf(game.player.position.y)<.12,"doorway approach has continuous floor collision")
	check(room.lamps.size()<=room.MAX_ACTIVE_FILLS and room.shadow_lamps.size()<=1,"doorway depth keeps existing light budgets")
	var field = game.residue
	check(field.views.fire.material.get_shader_parameter("first_person")==true,"ember bed uses the first-person visual branch")
	field.scorch(Vector3.ZERO,1.8)
	field.rebuild("fire")
	check(field.kind_at(Vector3.ZERO)=="fire" and field.views.fire.count>0,"fire damage still uses its exact tile mask")
	check(field.views.fire.view.get_child_count()==0,"molten crust adds no per-tile geometry or particles")
	if DisplayServer.get_name()!="headless" and not OS.get_environment("EMBERKEEP_DOOR_CAPTURE").is_empty():
		var out := OS.get_environment("EMBERKEEP_DOOR_CAPTURE")
		DirAccess.make_dir_recursive_absolute(out)
		game.ui.hide()
		game.player.place(Vector3(0,.03,2.3))
		game.fps.yaw=0;game.fps.pitch=0
		game.update_camera(.016)
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("physical-doorway.png"))
		room.set_open(false)
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("closed-doorway.png"))
		room.set_open(true)
		game.fps.pitch=-.45
		game.update_camera(.016)
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("ember-crust.png"))
	var portal_id: String = record.portals[0]
	var other_room: String = run.other_room(portal_id,run.current_room)
	game.begin_transition(portal_id)
	check(run.current_room!=other_room and game.corridors.portal_id==portal_id,"door approach prepares its paired corridor instead of teleporting")
	check(game.transition.is_empty() and is_zero_approx(game.light_veil.color.a),"corridor approach never starts the retired doorway fade")
	game.queue_free()
	for frame in 3: await process_frame
	print("DOORS AND EMBER SURFACES: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
