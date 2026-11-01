extends SceneTree
## Opt-in physical split-level views, using the safe Android render policy.
func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("capture")
func capture() -> void:
	var output := OS.get_environment("EMBERKEEP_VERTICAL_CAPTURE")
	if output.is_empty() or DisplayServer.get_name()=="headless":
		push_error("Set EMBERKEEP_VERTICAL_CAPTURE and run with an OpenGL display")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var settings = root.get_node("Settings")
	settings.set_value("sound",false)
	settings.set_value("music",false)
	var policy = load("res://scripts/graphics/render_policy.gd")
	policy.device_override=policy.for_device("Android","Imagination","PowerVR","gl_compatibility")
	settings.apply_render_policy()
	var run = root.get_node("Run")
	var generator = load("res://scripts/dungeon/floor_generator.gd")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.set_physics_process(false)
	for kind in ["upper","cellar"]:
		game.start_run("candle",472,false)
		run.floor_plan=["halls","halls","halls","halls","halls"]
		run.floor_twists=["","","","",""]
		run.floor_number=3
		var floor_data := {"rooms":{},"portals":{},"owners":{},"generator":3}
		generator.place_room(floor_data,root.get_node("Content").record("rooms","hall_2x1"),0,Vector2i.ZERO,472,3)
		run.rooms=floor_data.rooms
		run.portals={}
		run.current_room="0,0"
		var data: Dictionary=run.rooms[run.current_room]
		data.type="combat"
		data.cleared=true
		data.claimed=true
		data.props=[]
		data.items=[]
		data.partitions=[]
		data.generation=3
		var rise: float=2.8 if kind=="upper" else -2.6
		data.fps_terrain={"version":2,"kind":kind,"rise":rise,"ledge":[1.7,-5.2,4.6,4.2],"ramp":[1.7,-1.0,4.6,4.8]}
		data.chests=[{"id":"vertical-proof","position":[4,-3.1],"height":rise,"locked":false,"opened":false,"table":"normal_chest","size":[1,.66]}]
		game.enter_room(Vector3(7,0,5.6))
		game.paused=true
		game.ui.toast_time=0
		game.ui.floor_title_start=-100
		for actor in game.enemies: actor.queue_free()
		game.enemies.clear()
		await process_frame
		await physics_frame
		var at := Vector3(7,.03,5.6)
		game.player.place(at)
		game.player.velocity=Vector3.ZERO
		var target := Vector3(4,1.9 if kind=="upper" else -1.1,-1.8)
		var direction: Vector3=(target-(at+Vector3.UP*1.5)).normalized()
		game.fps.yaw=atan2(-direction.x,-direction.z)
		game.fps.pitch=asin(direction.y)
		game.update_camera(.016)
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(kind+".png"))
		print("VERTICAL GL: ",kind," rise=",game.room.terrain.rise," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	game.queue_free()
	await process_frame
	quit()
