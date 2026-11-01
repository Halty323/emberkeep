extends SceneTree
## Opt-in native captures of the integrated main-scene stair transition.
## Uses the same one-camera, simulation-clock path as normal play.
var game
var run
var output := ""
var samples: Array = []

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("capture")

func settle() -> void:
	await process_frame
	await physics_frame
	await process_frame

func capture() -> void:
	output=OS.get_environment("EMBERKEEP_STAIR_CAPTURE")
	if output.is_empty() or DisplayServer.get_name()=="headless":
		push_error("Set EMBERKEEP_STAIR_CAPTURE and run with an OpenGL display")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var settings=root.get_node("Settings")
	settings.set_value("sound",false)
	settings.set_value("music",false)
	RenderPolicy.device_override=RenderPolicy.for_device("Android","Imagination","PowerVR","gl_compatibility")
	settings.apply_render_policy()
	run=root.get_node("Run")
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.set_physics_process(false)
	game.set_process(false)
	game.start_run("candle",18523427,false)
	for id in run.rooms:
		if run.rooms[id].type=="boss": run.current_room=id; break
	run.rooms[run.current_room].cleared=true
	run.rooms[run.current_room].claimed=true
	game.enter_room(Vector3(0,0,2))
	game.paused=false
	game.ui.toast_time=0
	game.ui.floor_title_start=-100
	await settle()
	game.player.place(game.stairs.approach_point())
	game.player.velocity=Vector3.ZERO
	var facing: Vector3 = (game.stairs.position+Vector3.UP*.8-game.player.position-Vector3.UP*1.5).normalized()
	game.fps.yaw=atan2(-facing.x,-facing.z)
	game.fps.pitch=asin(facing.y)
	game.update_camera(0,true)
	game.begin_climb()
	await shot("departure-eye")
	var stages: Array = [
		{"phase":"climb","time":.36,"name":"departure-pullback"},
		{"phase":"climb","time":1.55,"name":"walking-up"},
		{"phase":"climb","time":3.2,"name":"upper-spiral"},
		{"phase":"arrive","time":.8,"name":"emerging"},
		{"phase":"arrive","time":1.05,"name":"return-to-eye"}
	]
	for tick in 500:
		if game.transition.is_empty(): break
		var previous_floor: int = run.floor_number
		game.advance_transition(1.0/60.0)
		# Static collision is already synchronized. Only a floor swap needs
		# another physics frame before querying the new scene's camera boom.
		if run.floor_number != previous_floor: await settle()
		game.update_camera(1.0/60.0)
		if not stages.is_empty() and game.transition.get("phase","")==stages[0].phase and game.transition.get("time",0.0)>=stages[0].time:
			await shot(stages.pop_front().name)
	await shot("arrival-eye")
	var file=FileAccess.open(output.path_join("stair-measurements.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(samples,"  "))
	print("STAIR GL: ",samples.size()," integrated transition captures; floor=",run.floor_number," active=",game.stair_cinematic.active)
	game.queue_free()
	await process_frame
	quit(0 if stages.is_empty() else 1)

func shot(label: String) -> void:
	game.ui.toast_time=0
	game.ui.floor_title_start=-100
	game.update_camera(0)
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	print("STAIR FRAME: ",label," floor=",run.floor_number," time=",game.transition.get("time",0.0))
	samples.append({"name":label,"floor":run.floor_number,"phase":game.transition.get("phase","done"),
		"time":game.transition.get("time",0.0),"actor_visible":game.player.visual.visible,
		"weapon_visible":game.fps.weapon.visible,"eye":[game.camera.position.x,game.camera.position.y,game.camera.position.z],
		"player":[game.player.position.x,game.player.position.y,game.player.position.z]})
