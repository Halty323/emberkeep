extends SceneTree
## Real stacked surfaces, normal progression and legacy-run continuation.
var game
var run
var Generator
var Vertical
var checks:=0
var failures:=0
var output:=""
var captures: Array=[]

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("exercise")

func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1;push_error("FAIL: "+label)

func settle() -> void:
	await process_frame
	await physics_frame
	await process_frame

func walk_to(target: Vector3, budget := 420) -> bool:
	for tick in budget:
		await physics_frame
		var difference: Vector3=target-game.player.position
		var flat:=Vector2(difference.x,difference.z)
		if flat.length()<.16 and absf(difference.y)<.18: return true
		game.fps.yaw=atan2(-difference.x,-difference.z)
		game.player.update_sim(1.0/60.0,Vector2(0,-1),game.fps.forward(),false)
	print("STOREY STUCK ",target," at ",game.player.position)
	return false

func enter_portal(id: String) -> bool:
	var source: String=run.current_room
	var side: Dictionary=run.portal_side(id,source)
	game.corridors.arm(id)
	await settle()
	var geometry=load("res://scripts/dungeon/room_geometry.gd")
	var entrance: Vector2=geometry.entry_point(side.cell,side.dir)
	var path: Array=[]
	for point in game.room.navigation(.6).find_path(Vector2(game.player.position.x,game.player.position.z),entrance): path.append(point)
	path.append(entrance)
	path.append_array(game.corridors.active.path)
	var offset: Vector2=game.corridors.destination_offset
	path.append(path.back()+Vector2(side.dir)*1.8)
	for point in path:
		var reached:=false
		for tick in 500:
			await physics_frame
			var target: Vector2=point-(offset if run.current_room!=source else Vector2.ZERO)
			var delta:=target-Vector2(game.player.position.x,game.player.position.z)
			if delta.length()<.18: reached=true;break
			game.fps.yaw=atan2(-delta.x,-delta.y)
			game.player.update_sim(1.0/60.0,Vector2(0,-1),game.fps.forward(),false)
			game.corridors.advance()
			game.track_exploration()
		if not reached: return false
	return run.current_room!=source

func clear_actors() -> void:
	for enemy in game.enemies:
		enemy.alive=false;enemy.queue_free()
	game.enemies.clear()

func view_at(at: Vector3, target: Vector3) -> void:
	game.player.place(at);game.player.velocity=Vector3.ZERO
	var aim: Vector3=(target-(at+Vector3.UP*1.5)).normalized()
	game.fps.yaw=atan2(-aim.x,-aim.z);game.fps.pitch=asin(aim.y)
	game.update_camera(0,true)

func save_view(label: String) -> void:
	if output.is_empty(): return
	game.ui.floor_title_start=-100
	game.ui.toast_time=0
	game.residue.update_sim(0)
	game.update_camera(0,true)
	root.disable_3d=false
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	captures.append({"view":label,"seed":run.seed_value,"room":run.current_room,"feet":[game.player.position.x,game.player.position.y,game.player.position.z],"ceiling":game.room.ceiling_height(),"upper_area":game.room.terrain.loft.deck.get_area(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"texture_mb":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)/1048576.0,"video_mb":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0})
	var report:=FileAccess.open(output.path_join("measurements.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify(captures,"  "))
	print("STOREY GL ",label," eye=",game.camera.position," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," video_mb=",Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0)
	root.disable_3d=true

func exercise() -> void:
	Generator=load("res://scripts/dungeon/floor_generator.gd")
	Vertical=load("res://scripts/dungeon/vertical_plans.gd")
	run=root.get_node("Run")
	root.get_node("Settings").set_value("sound",false)
	root.get_node("Settings").set_value("music",false)
	output=OS.get_environment("EMBERKEEP_STOREY_CAPTURE")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		RenderPolicy.device_override=RenderPolicy.for_device("Android","Imagination","PowerVR","gl_compatibility")
		root.get_node("Settings").apply_render_policy()
		# Physics still runs normally between captures. Draw only for each
		# measurement, so software GL does not slow a multi-room walking test.
		root.disable_3d=true
	for seed_value in [31609250,18523427,64872557,472,1,2,3,4]:
		for floor_number in [1,2,5]:
			var data: Dictionary=Generator.generate(seed_value,floor_number)
			var primary: Array=data.rooms.values().filter(func(room): return room.get("vertical_primary",false))
			check(primary.size()==1 and primary[0].fps_terrain.get("version",0)==3,"each new floor has an actual two-storey chamber")
			check(Vertical.route_portals(data,primary[0].id).is_empty(),"no normal route to the boss bypasses the two-storey chamber")
			check(Generator.validate(data).is_empty(),"mandatory storey routing preserves complete floor validity")
		var old: Dictionary=Generator.generate_v2(seed_value,1)
		var seen: Dictionary=old.rooms["0,0"].duplicate(true)
		var portals: Dictionary=old.portals.duplicate(true)
		check(Vertical.upgrade_unvisited(old.rooms,old.portals,1),"legacy layouts gain a real storey in an untouched chamber")
		check(old.rooms["0,0"]==seen and old.portals==portals,"save repair preserves visited rooms and the floor graph")
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game);current_scene=game
	game.set_physics_process(false);game.set_process(false)
	game.start_run("candle",31609250,false)
	run.generator_version=2
	run.generate_floor()
	check(run.generator_version==2 and run.rooms.values().any(func(r):return r.get("fps_terrain",{}).get("kind","")=="loft"),"continued legacy runs receive new architecture while keeping their saved loot rules")
	var legacy_primary: Dictionary=run.rooms.values().filter(func(r):return r.get("fps_terrain",{}).get("kind","")=="loft")[0]
	check(Vertical.route_portals({"rooms":run.rooms,"portals":run.portals},legacy_primary.id).is_empty(),"the next legacy floor also puts the real storey on every boss route")
	game.start_run("candle",31609250,false)
	var primary: Dictionary=run.rooms.values().filter(func(room): return room.get("vertical_primary",false))[0]
	game.paused=true
	var route: Array=Vertical.route_portals({"rooms":run.rooms,"portals":run.portals},"")
	for portal in route:
		if run.current_room==primary.id: break
		if not game.room.open: clear_actors();game.clear_room()
		check(await enter_portal(portal),"normal capsule movement traverses the actual route's corridors")
	check(run.current_room==primary.id and game.room.terrain.loft!=null,"normal fresh-run progression actually enters the two-storey room")
	check(game.enemies.any(func(enemy):return enemy.position.y>3),"the actual encounter includes upstairs enemies")
	clear_actors()
	game.clear_room()
	await settle()
	var loft=game.room.terrain.loft
	check(loft!=null and game.room.ceiling_height()>7,"the real main scene constructs the taller two-storey room")
	if loft==null: quit(1);return
	var center: Vector2=loft.deck.get_center()
	var upper_walk:=Vector3(center.x,loft.RISE,center.y+1.25)
	view_at(game.player.position,Vector3(center.x,2.8,center.y))
	await save_view("room-arrival")
	var ground:=Vector3(center.x,.03,center.y)
	game.player.place(ground);game.player.velocity=Vector3.ZERO
	for tick in 8:
		await physics_frame
		game.player.update_sim(1.0/60.0,Vector2.ZERO,Vector3.FORWARD,false)
	check(absf(game.player.position.y)<.12,"standing underneath the upper floor does not teleport feet onto it")
	var ray:=PhysicsRayQueryParameters3D.create(ground+Vector3.UP*.8,ground+Vector3.UP*5,1)
	var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and absf(hit.position.y-(loft.RISE-loft.SLAB))<.1,"a real upper slab is above a walkable lower room")
	view_at(game.player.position,Vector3(loft.deck.end.x,1.4,center.y))
	await save_view("beneath-upstairs")
	var target:=Vector3(loft.deck.end.x-.8,.03,center.y)
	check(await walk_to(target),"the capsule physically crosses the room underneath the upper deck")
	var foot: Vector3=loft.foot(.5)
	game.player.place(foot+Vector3.UP*.03);game.player.velocity=Vector3.ZERO
	check(await walk_to(loft.head()),"the capsule physically climbs the staircase onto the upstairs floor")
	check(await walk_to(upper_walk),"the player can walk around upstairs beside the reward chest")
	view_at(game.player.position,Vector3(loft.stairs.get_center().x,1.2,loft.stairs.end.y+1))
	await save_view("upper-floor")
	check(absf(game.room.floor_height(Vector3(center.x,0,center.y)))<.001 and absf(game.room.floor_height(Vector3(center.x,loft.RISE,center.y))-loft.RISE)<.001,"the same XZ coordinate has two independent floors")
	check(await walk_to(loft.head()),"the upstairs stair entrance remains clear")
	check(await walk_to(foot),"the capsule physically descends back to the ground floor")
	var enemy=game.spawn_enemy(foot,"mote")
	enemy.timer=1000
	game.player.place(upper_walk+Vector3.UP*.03);game.player.invulnerability=999
	for tick in 900:
		await physics_frame
		enemy.update_sim(1.0/60.0)
		if absf(enemy.position.y-loft.RISE)<.2 and enemy.position.distance_to(game.player.position)<1.7: break
	check(absf(enemy.position.y-loft.RISE)<.3,"enemy navigation reaches the upstairs floor by the stairs")
	game.player.place(foot+Vector3.UP*.03)
	for tick in 900:
		await physics_frame
		enemy.update_sim(1.0/60.0)
		if absf(enemy.position.y)<.2 and enemy.position.distance_to(foot)<1.7: break
	check(absf(enemy.position.y)<.3 and enemy.position.distance_to(foot)<1.8,"enemy navigation returns to the ground floor")
	if absf(enemy.position.y)>=.3 or enemy.position.distance_to(foot)>=1.8:
		print("STOREY ENEMY: ",enemy.position," foot=",foot," path=",enemy.storey_path," replanned=",loft.route(game.room,enemy.position,foot,.5))
	enemy.queue_free();game.enemies.clear();await settle()
	for kind in ["bailer","cog"]:
		var foe=game.spawn_enemy(foot,kind)
		game.player.place(upper_walk+Vector3.UP*.03)
		for tick in 1800:
			await physics_frame
			foe.update_sim(1.0/60.0)
			if absf(foe.position.y-loft.RISE)<.2 and loft.deck.has_point(Vector2(foe.position.x,foe.position.z)): break
		check(absf(foe.position.y-loft.RISE)<.3,kind+" uses the stairs instead of attacking through the floor")
		if absf(foe.position.y-loft.RISE)>=.3: print("STOREY SUBCLASS: ",kind," at=",foe.position," path=",foe.storey_path)
		if kind=="bailer":
			foe.timer=0;foe.has_sight=true
			foe.behave(.01,5,Vector3.FORWARD)
			check(not foe.lob.is_empty() and absf(foe.lob.at.y-loft.RISE)<.15,"upstairs water attacks target the actual upstairs floor")
		foe.queue_free();game.enemies.clear();await settle()
	var upstairs:=Vector3(center.x,loft.RISE,center.y)
	var downstairs:=Vector3(center.x,0,center.y)
	game.residue.add("water",downstairs,1.0)
	check(game.residue.kind_at(downstairs)=="water" and game.residue.kind_at(upstairs)=="","ground-floor water cannot slow a player upstairs")
	game.residue.add("moss",upstairs,1.0)
	check(game.residue.kind_at(upstairs)=="moss" and game.residue.kind_at(downstairs)=="water","both storeys retain independent residue at identical XZ coordinates")
	game.residue.add_cloud(upstairs,1.0)
	check(game.residue.cloud_at(upstairs)>=0 and game.residue.cloud_at(downstairs)<0,"an upstairs cloud stays on its own floor")
	var coin=game.spawn_pickup(upstairs,"copper_coin",1)
	check(absf(coin.position.y-loft.RISE)<.01,"pickups spawned upstairs stay upstairs")
	var saved: Dictionary=run.rooms[run.current_room].pickups.filter(func(p):return p.id==coin.drop_id)[0]
	check(absf(saved.get("height",0)-loft.RISE)<.01,"saved pickups retain their storey")
	check(primary.chests.any(func(chest):return absf(chest.get("height",0)-loft.RISE)<.01),"clearing the actual room awards its normal chest upstairs")
	game.queue_free();await process_frame
	print("TWO STOREY ROOMS: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
