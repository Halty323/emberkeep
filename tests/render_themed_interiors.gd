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
		game.ui.toast_time=0
		game.ui.floor_title_start=-100
		var report: Dictionary = game.room.interiors_report
		if report.walls.is_empty(): push_error("No wall vignette for " + theme.id);quit(1);return
		var anchor: Dictionary = report.walls[0]
		var inward = Vector3(-anchor.dir.x,0,-anchor.dir.y)
		var tangent = Vector3(inward.z,0,-inward.x)
		var cell = game.room.geometry.cell_at(anchor.at)
		var center: Vector2 = game.room.geometry.cell_center(cell)
		var toward_middle = Vector3(center.x-anchor.at.x,0,center.y-anchor.at.y)
		var sign_along = signf(toward_middle.dot(tangent))
		var spot = Vector3(anchor.at.x, .03, anchor.at.y) + inward * 4.1 + tangent * sign_along * 1.3
		# Capture from walkable ground instead of placing the eye in a table.
		for distance in [4.1, 5.4, 3.2, 6.1]:
			var found := false
			for sideways in [1.3, -1.3, 0.0, 2.4, -2.4]:
				var candidate: Vector3 = Vector3(anchor.at.x,.03,anchor.at.y) + inward * distance + tangent * sideways
				var point := Vector2(candidate.x,candidate.z)
				if not game.room.geometry.contains(point,.5) or game.room.blocked_at(point): continue
				if game.room.terrain and game.room.terrain.ledge.has_area() and game.room.terrain.ledge.merge(game.room.terrain.ramp).grow(.5).has_point(point): continue
				spot = candidate
				found = true
				break
			if found: break
		game.player.place(spot)
		game.player.invulnerability=100
		var target=Vector3(anchor.at.x,1.95,anchor.at.y)
		var direction=(target-(spot+Vector3.UP*1.5)).normalized()
		game.fps.yaw=atan2(-direction.x,-direction.z)
		game.fps.pitch=asin(direction.y)
		game.update_camera(.016)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(theme.id+"-interior.png"))
		print("INTERIOR CAPTURE: ",theme.id," wall=",anchor," pieces=",report.pieces," batches=",report.batches," vertices=",report.vertices," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	game.queue_free()
	await process_frame
	quit()
