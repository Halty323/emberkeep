extends SceneTree
func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")
	call_deferred("capture")
func capture() -> void:
	var settings = root.get_node("Settings")
	var run = root.get_node("Run")
	var content = root.get_node("Content")
	settings.set_value("sound",false)
	settings.set_value("music",false)
	settings.set_value("small_details","high")
	RenderPolicy.device_override = RenderPolicy.for_device("Android","Imagination","PowerVR","gl_compatibility")
	settings.apply_render_policy()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	var out = OS.get_environment("EMBERKEEP_INTERIOR_CAPTURE")
	if out.is_empty():
		push_error("Set EMBERKEEP_INTERIOR_CAPTURE to a capture directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	for theme in content.families.floors:
		game.start_run("candle",18523427,false)
		run.floor_plan = [theme.id,theme.id,theme.id,theme.id,theme.id]
		run.floor_twists = ["","","","",""]
		run.floor_number = 3
		run.generate_floor()
		for id in run.rooms:
			if run.rooms[id].type != "combat" or run.rooms[id].cells.size()<2: continue
			run.current_room=id
			break
		game.enter_room(Vector3(0,0,2))
		game.paused=true
		# This fixture teleports the camera after the encounter is generated.
		# Clear actors before composing the interior: seed 18523427 otherwise
		# places the eye inside a frozen brute in the kiln/hearth screenshots.
		for enemy in game.enemies: enemy.queue_free()
		game.enemies.clear()
		game.room.set_open(true)
		await process_frame
		await physics_frame
		game.ui.toast_time=0
		game.ui.floor_title_start=-100
		var report: Dictionary = game.room.interiors_report
		if report.walls.is_empty(): push_error("No wall vignette for " + theme.id);quit(1);return
		var anchor: Dictionary = report.walls[0]
		var inward = Vector3(-anchor.dir.x,0,-anchor.dir.y)
		var tangent = Vector3(inward.z,0,-inward.x)
		var spot := Vector3.ZERO
		var safe := false
		# Capture from walkable ground instead of placing the eye in a table.
		for distance in [4.1, 5.4, 3.2, 6.1]:
			var found := false
			for sideways in [1.3, -1.3, 0.0, 2.4, -2.4]:
				var candidate: Vector3 = Vector3(anchor.at.x,.03,anchor.at.y) + inward * distance + tangent * sideways
				var point := Vector2(candidate.x,candidate.z)
				if not game.room.geometry.contains(point,.5) or game.room.blocked_at(point) or not capsule_clear(game, candidate): continue
				if game.room.terrain and game.room.terrain.ledge.has_area() and game.room.terrain.ledge.merge(game.room.terrain.ramp).grow(.5).has_point(point): continue
				spot = candidate
				found = true
				safe = true
				break
			if found: break
		if not safe:
			push_error("No collision-clear interior viewpoint for " + theme.id)
			quit(1)
			return
		game.player.place(spot)
		game.player.velocity = Vector3.ZERO
		game.player.invulnerability=100
		var target=Vector3(anchor.at.x,1.95,anchor.at.y)
		var direction=(target-(spot+Vector3.UP*1.5)).normalized()
		game.fps.yaw=atan2(-direction.x,-direction.z)
		game.fps.pitch=asin(direction.y)
		game.update_camera(.016)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(theme.id+"-interior.png"))
		print("INTERIOR CAPTURE: ",theme.id," eye=",game.camera.global_position," wall=",anchor," pieces=",report.pieces," batches=",report.batches," vertices=",report.vertices," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	game.queue_free()
	await process_frame
	quit()

# Match the actual standing capsule, with a small extra visual clearance.
func capsule_clear(game, at: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = .36
	shape.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,at + Vector3.UP * .85)
	query.collision_mask = 1 | PropVisuals.FURNITURE_LAYER
	query.exclude = [game.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
