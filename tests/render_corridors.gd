extends SceneTree
## Native review under the actual PowerVR policy override: depth-only AO,
## physical generated levels, supported architecture and a visible handoff.
var game
var run
var output := ""
var reports: Array=[]
var Plans
var Geometry

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("capture")

func capture() -> void:
	Plans=load("res://scripts/dungeon/corridor_plan.gd")
	Geometry=load("res://scripts/dungeon/room_geometry.gd")
	output=OS.get_environment("EMBERKEEP_CORRIDOR_CAPTURE")
	if output.is_empty() or DisplayServer.get_name()=="headless":
		push_error("Set EMBERKEEP_CORRIDOR_CAPTURE and use an OpenGL display")
		quit(1);return
	DirAccess.make_dir_recursive_absolute(output)
	var settings=root.get_node("Settings")
	settings.set_value("sound",false)
	settings.set_value("music",false)
	settings.set_value("effects_detail","high")
	settings.set_value("small_details","high")
	settings.set_value("ssao","low")
	RenderPolicy.device_override=RenderPolicy.for_device("Android","Imagination","PowerVR","gl_compatibility")
	settings.apply_render_policy()
	run=root.get_node("Run")
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.set_physics_process(false)
	for floor_number in [1,2]:
		game.start_run("candle",31609250,false)
		run.floor_number=floor_number
		run.generate_floor()
		var id: String=run.rooms.values().filter(func(room): return room.get("vertical_primary",false))[0].id
		run.current_room=id
		game.enter_room(Vector3(0,0,2))
		game.paused=true
		for actor in game.enemies: actor.queue_free()
		game.enemies.clear()
		game.clear_room()
		game.ui.floor_title_start=-100
		game.ui.toast_time=0
		await process_frame
		await physics_frame
		var terrain=game.room.terrain
		var target:=Vector3(terrain.ledge.get_center().x,terrain.rise+.8,terrain.ledge.get_center().y)
		var preferred:=Vector2(terrain.ramp.get_center().x,terrain.ramp.end.y+3.2)
		var point=clear_viewpoint(preferred,target)
		if point==null:
			push_error("No valid camera for generated primary level");quit(1);return
		set_view(point,target)
		await save_view("upper-room" if floor_number==1 else "upper-room-floor-2")
		if floor_number==1:
			settings.set_value("ssao","off")
			await save_view("upper-ssao-off")
			settings.set_value("ssao","low")
			await save_view("upper-ssao-on")
			var landing: Vector2=terrain.ledge.get_center()+Vector2(0,terrain.ledge.size.y*.35)
			set_view(Vector3(landing.x,terrain.rise+.03,landing.y),Vector3(terrain.ramp.get_center().x,1.5,terrain.ramp.end.y+5))
			await save_view("upper-landing")
	game.start_run("candle",31609250,false)
	game.paused=true
	game.ui.floor_title_start=-100
	game.ui.toast_time=0
	var id: String=run.rooms[run.current_room].portals[0]
	var side: Dictionary=run.portal_side(id,run.current_room)
	var door: Vector2=Geometry.socket_point(side.cell,side.dir)
	var portal: Dictionary=run.portals[id]
	var path: Array[Vector2]=Plans.from_room(Plans.ensure(portal,run.rooms),portal,run.current_room)
	set_view(Vector3(door.x-side.dir.x*1.8,.03,door.y-side.dir.y*1.8),Vector3(path[1].x,1.5,path[1].y))
	await save_view("doorway-preview")
	game.corridors.arm(id)
	var segment=game.corridors.active
	set_view(Vector3(door.x-side.dir.x*1.8,.03,door.y-side.dir.y*1.8),Vector3(segment.path[1].x,1.5,segment.path[1].y))
	await save_view("corridor-entry")
	var sample: Dictionary=Plans.sample(segment.path,game.corridors.handoff+.5)
	var direction: Vector2=sample.direction
	set_view(Vector3(sample.at.x,.03,sample.at.y),Vector3(sample.at.x+direction.x*4,1.5,sample.at.y+direction.y*4))
	# Compare only static world geometry across the atomic loading step.
	# Held-weapon sway and HUD animation are independently tested in play.
	game.set_process(false)
	game.fps.weapon.hide()
	game.ui.hide()
	await save_view("handoff-before")
	var original_id: int=game.player.get_instance_id()
	game.corridors.advance()
	if original_id!=game.player.get_instance_id(): push_error("Player was recreated during handoff");quit(1);return
	game.fps.weapon.hide()
	await save_view("handoff-after")
	var before:=Image.load_from_file(output.path_join("handoff-before.png"))
	var after:=Image.load_from_file(output.path_join("handoff-after.png"))
	var difference:=0.0
	for y in before.get_height():
		for x in before.get_width():
			var a:=before.get_pixel(x,y)
			var b:=after.get_pixel(x,y)
			difference+=(absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b))/3.0
	difference/=before.get_width()*before.get_height()
	print("CORRIDOR HANDOFF: normalized RGB difference=",difference)
	if difference>.0005: push_error("Visible room geometry changed during corridor handoff");quit(1);return
	var file:=FileAccess.open(output.path_join("measurements.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(reports,"  "))
	game.queue_free()
	await process_frame
	print("CORRIDOR/LEVEL GL REVIEW: ",reports.size()," views; PowerVR AO samples=6")
	quit()

func set_view(at: Vector3, target: Vector3) -> void:
	game.player.place(at)
	game.player.velocity=Vector3.ZERO
	game.player.push=Vector3.ZERO
	game.player.invulnerability=100
	var aim: Vector3=(target-(at+Vector3.UP*1.5)).normalized()
	game.fps.yaw=atan2(-aim.x,-aim.z)
	game.fps.pitch=asin(aim.y)
	game.update_camera(0,true)

func save_view(label: String) -> void:
	for frame in 7: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	var report: Dictionary={"view":label,"seed":run.seed_value,"floor":run.floor_number,"room":run.current_room,
		"ssao":root.get_node("Settings").effective_ssao(),"ssao_samples":game.screen_fx.ambient_occlusion.surface.get_shader_parameter("sample_count"),
		"vertical_kind":game.room.terrain.kind,"vertical_rise":game.room.terrain.rise if game.room.terrain.ledge.has_area() else 0,
		"player_id":game.player.get_instance_id(),"eye":[game.camera.global_position.x,game.camera.global_position.y,game.camera.global_position.z],
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"video_mb":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0,
		"texture_mb":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)/1048576.0}
	reports.append(report)
	print("CORRIDOR GL: ",JSON.stringify(report))

func clear_viewpoint(preferred: Vector2, target: Vector3) -> Variant:
	for radius in [0.0,1.0,2.0,3.0,4.5,6.0]:
		for direction in 16:
			var point: Vector2=preferred+Vector2.RIGHT.rotated(TAU*direction/16.0)*radius
			if not game.room.geometry.contains(point,.65) or game.room.blocked_at(point): continue
			if game.room.terrain.ledge.grow(.5).has_point(point) or game.room.terrain.ramp.grow(.5).has_point(point): continue
			var at:=Vector3(point.x,.03,point.y)
			var shape:=CapsuleShape3D.new()
			shape.radius=.36;shape.height=1.7
			var query:=PhysicsShapeQueryParameters3D.new()
			query.shape=shape
			query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*.85)
			query.collision_mask=1|PropVisuals.FURNITURE_LAYER
			query.exclude=[game.player.get_rid()]
			if not game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
			var eye:=at+Vector3.UP*1.5
			var ray:=PhysicsRayQueryParameters3D.create(eye,eye+(target-eye).normalized()*minf(2.2,eye.distance_to(target)),1|PropVisuals.FURNITURE_LAYER,[game.player.get_rid()])
			if game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return at
	return null
