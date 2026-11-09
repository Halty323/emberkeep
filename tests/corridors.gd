extends SceneTree
## Real capsule traversal, reversible streaming and renderer-independent
## camera continuity. Uses the player's reported seed as a generation fixture.
var checks := 0
var failures := 0
var game
var run
var Plans
var Geometry
var Generator
class ArchitectureFixture extends Node3D:
	var geometry
	var look := {}
	var data := {}
	var sockets := {}
	var interiors_report := {}

func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("exercise")

func check(value: bool, label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL: "+label)

func settle() -> void:
	for i in 3: await process_frame

func exercise() -> void:
	Plans=load("res://scripts/dungeon/corridor_plan.gd")
	Geometry=load("res://scripts/dungeon/room_geometry.gd")
	Generator=load("res://scripts/dungeon/floor_generator.gd")
	run=root.get_node("Run")
	var settings=root.get_node("Settings")
	settings.set_value("sound",false)
	settings.set_value("music",false)
	await generation()
	await architecture_and_migration()
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.set_physics_process(false)
	game.start_run("candle",31609250,false)
	game.paused=true
	await fixture()
	await rebase_continuity()
	for direction in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]: await traverse(direction)
	game.queue_free()
	await settle()
	print("WALKABLE CORRIDORS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func generation() -> void:
	var rng_state: int=run.rng.state
	var primary_count:=0
	for seed_value in [31609250,18523427,64872557,472,1,2,3,4]:
		for floor_number in [1,2,3,5]:
			var data: Dictionary=Generator.generate(seed_value,floor_number)
			var vertical: Array=data.rooms.values().filter(func(room): return room.get("vertical_primary",false))
			check(vertical.size()==1,"each floor guarantees a primary two-level combat room")
			if not vertical.is_empty():
				primary_count+=1
				check(vertical[0].fps_terrain.kind in ["loft","floor"] and int(vertical[0].fps_terrain.version)>=3,"the primary is an actual two-storey room rather than a height-field annex")
				check(load("res://scripts/dungeon/vertical_plans.gd").route_portals(data,vertical[0].id).is_empty(),"all routes to the boss pass through the two-storey room")
				var verticals=load("res://scripts/dungeon/vertical_plans.gd")
				check(vertical[0].id in verticals.boss_route(data),"the guaranteed two-level chamber appears on the normal boss route")
			for portal in data.portals.values():
				var plan: Dictionary=Plans.ensure(portal,data.rooms)
				check(plan==Plans.ensure(portal,data.rooms),"a portal reuses its persisted connector")
				var forward: Array=Plans.from_room(plan,portal,portal.a.room)
				var backward: Array=Plans.from_room(plan,portal,portal.b.room)
				var shift: Vector2=Generator.vec2(plan.offset_b)
				check(forward.size()==6 and backward.size()==6,"both ends have real occluding elbows")
				for i in forward.size():
					check(forward[i].distance_to(backward[5-i]+shift)<.005,"backtracking follows the same physical connector")
				for i in forward.size()-1:
					var delta: Vector2=forward[i+1]-forward[i]
					check(absf(delta.x)<.001 or absf(delta.y)<.001,"corridor runs are orthogonal, without diagonal gaps")
			for room in data.rooms.values():
				for portal_id in room.portals:
					var portal: Dictionary=data.portals[portal_id]
					var route: Array[Vector2]=Plans.from_room(portal.corridor,portal,room.id)
					var regions: Array[Rect2]=Plans.strips(route)
					var separate:=true
					for other_id in room.portals:
						if other_id==portal_id: continue
						var other: Dictionary=data.portals[other_id]
						var other_route: Array[Vector2]=Plans.from_room(other.corridor,other,room.id)
						for preview in Plans.strips(other_route.slice(0,3)):
							if regions.any(func(region): return region.intersects(preview.grow(.24))): separate=false
					check(separate,"another exit's corridor preview cannot obstruct the active route")
	check(primary_count==32,"reported and regression seeds all contain actual primary levels")
	check(run.rng.state==rng_state,"corridor and architectural plans never consume gameplay RNG")

func architecture_and_migration() -> void:
	var architecture=load("res://scripts/first_person/architecture.gd")
	for cells in [[Vector2i.ZERO,Vector2i.RIGHT],[Vector2i.ZERO],[Vector2i.ZERO,Vector2i.DOWN]]:
		var holder:=ArchitectureFixture.new()
		holder.geometry=Geometry.new(cells)
		root.add_child(holder)
		var parts: Dictionary=architecture.layout(holder)
		if cells==[Vector2i.ZERO,Vector2i.RIGHT]:
			var grounded:=true
			for part in parts.stone:
				if part.basis.y.length()<4: grounded=false
			check(grounded,"a wide hall has wall pilasters but no unsupported ribs across its internal cell seam")
		else:
			var corbels:=0
			for transform in parts.dressed:
				if is_equal_approx(transform.origin.y,3.29) and is_equal_approx(transform.basis.x.length(),.65): corbels+=1
			check(corbels==cells.size()*6,"each supported vault rib has two attached stone corbels")
		holder.queue_free()
		await process_frame
	var shaft:=ArchitectureFixture.new()
	shaft.geometry=Geometry.new([Vector2i.ZERO])
	shaft.data={"stairs":[0,0]}
	root.add_child(shaft)
	var beams: Array=architecture.layout(shaft).timber
	var stair=load("res://scripts/dungeon/staircase.gd")
	var radius: float=stair.OUTER+.65
	var cut:=Rect2(-radius,-radius,radius*2,radius*2).grow(-.01)
	for transform in beams:
		var size:=Vector2(transform.basis.x.length(),transform.basis.z.length())
		var rect:=Rect2(Vector2(transform.origin.x,transform.origin.z)-size*.5,size)
		check(not rect.intersects(cut),"ceiling timbers do not hang across the open stair shaft")
	shaft.queue_free()
	await process_frame
	var vertical=load("res://scripts/dungeon/vertical_plans.gd")
	var data: Dictionary=Generator.generate(31609250,1)
	for room in data.rooms.values():
		room.fps_terrain={}
		room.erase("vertical_primary")
	data.rooms["0,0"].chests=[{"id":"already-open","position":[1,1],"opened":true}]
	var visited_before: Dictionary=data.rooms["0,0"].duplicate(true)
	var portals_before: Dictionary=data.portals.duplicate(true)
	var rng_state: int=run.rng.state
	check(vertical.upgrade_unvisited(data.rooms,data.portals,1),"an older saved floor gains a level in one untouched chamber")
	check(data.rooms["0,0"]==visited_before and data.portals==portals_before,"checkpoint repair preserves visited rooms, opened chests and the floor graph")
	check(not vertical.upgrade_unvisited(data.rooms,data.portals,1),"checkpoint repair is idempotent")
	check(run.rng.state==rng_state,"checkpoint repair cannot reroll combat or loot")
	var portal: Dictionary=data.portals.values()[0]
	var plan: Dictionary=Plans.ensure(portal,data.rooms)
	check(Plans.valid(JSON.parse_string(JSON.stringify(plan))),"corridor blueprints survive JSON checkpoint serialization")
	var corrupt: Dictionary=plan.duplicate(true)
	corrupt.path[2][0]=NAN
	portal.corridor=corrupt
	check(Plans.valid(Plans.ensure(portal,data.rooms)),"malformed saved corridor coordinates are regenerated safely")

func fixture() -> void:
	var floor_data: Dictionary={"rooms":{},"portals":{},"owners":{},"generator":3}
	var catalog=root.get_node("Content")
	Generator.place_room(floor_data,catalog.record("rooms","hearth_1x1"),0,Vector2i.ZERO,31609250,1)
	for direction in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		Generator.place_room(floor_data,catalog.record("rooms","hearth_1x1"),0,direction,31609250,1)
		Generator.add_portal(floor_data,Vector2i.ZERO,direction)
	for record in floor_data.rooms.values():
		record.type="combat"
		record.cleared=true
		record.claimed=true
		record.props=[]
		record.partitions=[]
		record.chests=[]
		record.items=[]
		record.fps_terrain={}
	run.rooms=floor_data.rooms
	run.portals=floor_data.portals
	run.current_room="0,0"
	game.enter_room(Vector3(0,.03,0))
	await settle()

func portal_for(direction: Vector2i) -> String:
	for id in run.rooms["0,0"].portals:
		if run.portal_side(id,"0,0").dir==direction: return id
	return ""

func rebase_continuity() -> void:
	var id:=portal_for(Vector2i.RIGHT)
	var target_id: String=run.other_room(id,"0,0")
	run.rooms[target_id].cleared=false
	run.rooms[target_id].claimed=false
	game.corridors.arm(id)
	await settle()
	var staged_id: int=game.corridors.staged_room.get_instance_id()
	check(not game.corridors.staged_room.visible and not run.rooms[target_id].visited,"one hidden neighbor is prepared without visiting it or starting combat")
	var pool=load("res://scripts/effects/effects_pool.gd")
	check(pool.current==game.room.effects,"preparing an unseen neighbor never steals the active room's particles")
	var active=game.corridors.active
	var sample: Dictionary=Plans.sample(active.path,game.corridors.handoff+.5)
	game.player.place(Vector3(sample.at.x,.03,sample.at.y))
	game.player.velocity=Vector3(2,-.2,1)
	game.player.fire_cooldown=.37
	game.player.dash_cooldown=.82
	game.player.invulnerability=.24
	game.fps.yaw=.8
	game.fps.pitch=.1
	game.update_camera(0,true)
	var player_id: int=game.player.get_instance_id()
	var active_id: int=active.get_instance_id()
	var probe: Vector3=active.to_global(Vector3(active.path[2].x,2,active.path[2].y))-game.camera.global_position
	var eye: Vector3=game.camera.global_position
	var axial: Vector2=(active.path[3]-active.path[2]).normalized()
	var tangent:=Vector2(-axial.y,axial.x)
	var middle: Vector2=(active.path[2]+active.path[3])*.5
	for along in [-1.0,0.0,1.0]:
		for side in [-.94,0.0,.94]:
			var viewpoint: Vector2=middle+axial*along+tangent*side
			for endpoint in [active.path.front(),active.path.back()]:
				for edge in [-1.28,0.0,1.28]:
					var target: Vector2=endpoint+tangent*edge
					var query:=PhysicsRayQueryParameters3D.create(Vector3(viewpoint.x,1.5,viewpoint.y),Vector3(target.x,1.5,target.y),1)
					check(not game.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"solid elbows hide the entire room aperture, even when hugging a wall or dashing through the handoff")
	var projectile=game.spawn_shot(game.player.position+Vector3.UP,Vector3.FORWARD,5,15,{},Color.WHITE,true)
	var projectile_id: int=projectile.get_instance_id()
	var trail_before: Vector3=projectile.streak.global_position-game.camera.global_position
	var launch_before: Vector3=projectile.start_position-game.player.position
	game.paused=false
	check(game.actions.place_bomb().ok,"a live bomb can be placed inside the walkable corridor")
	game.paused=true
	var bomb: Dictionary=run.pending_bombs.back()
	var bomb_view=game.bomb_views[bomb.id]
	var bomb_id: int=bomb_view.get_instance_id()
	var bomb_relative: Vector3=bomb_view.position-game.player.position
	var fuse: float=bomb.fuse
	game.corridors.advance()
	check(run.current_room!="0,0","walking past the middle loads the next room")
	check(game.room.get_instance_id()==staged_id,"the handoff adopts the prepared room instead of rebuilding its geometry")
	check(game.player.get_instance_id()==player_id and game.corridors.active.get_instance_id()==active_id,"the player and physical corridor survive the handoff")
	check(is_equal_approx(game.player.fire_cooldown,.37) and is_equal_approx(game.player.dash_cooldown,.82) and is_equal_approx(game.player.invulnerability,.24),"door traversal never resets combat cooldowns or grants invulnerability")
	check(game.player.velocity.distance_to(Vector3(2,-.2,1))<.001,"velocity remains continuous")
	check(game.shots.any(func(shot): return shot.get_instance_id()==projectile_id),"a projectile inside the corridor survives room adoption")
	check((projectile.streak.global_position-game.camera.global_position).distance_to(trail_before)<.001 and (projectile.start_position-game.player.position).distance_to(launch_before)<.001,"projectile trail and launch origin follow the coordinate rebase")
	check(bomb.room==run.current_room and is_equal_approx(bomb.fuse,fuse),"a lit corridor bomb changes coordinate frames without resetting its fuse")
	check(game.bomb_views[bomb.id].get_instance_id()==bomb_id and (bomb_view.position-game.player.position).distance_to(bomb_relative)<.001,"the same live bomb stays visually fixed in the corridor")
	check(pool.current==game.room.effects,"adopting the prepared room activates its particle pool")
	var settings=root.get_node("Settings")
	settings.set_value("effects_detail","low")
	check(game.room.effects.budgets.transient==settings.effect_budget("transient"),"an adopted room still receives live quality changes")
	settings.set_value("effects_detail","high")
	var after: Vector3=active.to_global(Vector3(active.path[2].x,2,active.path[2].y))-game.camera.global_position
	check(probe.distance_to(after)<.001,"camera-relative geometry does not move during origin rebasing")
	check(game.transition.is_empty() and is_zero_approx(game.light_veil.color.a),"a corridor never starts the old fade/teleport presentation")
	check(not game.deferred_encounter.is_empty() and game.enemies.is_empty(),"unvisited encounters wait until the capsule enters the room")
	game.paused=false
	game._physics_process(1.0/60.0)
	game.paused=true
	check(not run.rooms[target_id].cleared and game.enemies.is_empty(),"an empty staged encounter cannot clear itself while walking the corridor")
	var back: Dictionary=Plans.sample(active.path,game.corridors.handoff-.5)
	var back_point: Vector3=active.to_global(Vector3(back.at.x,.03,back.at.y))
	game.player.place(back_point)
	game.corridors.advance()
	check(run.current_room=="0,0" and game.player.get_instance_id()==player_id,"turning back before arrival streams the original room")
	game.player.place(Vector3(7,.03,0))
	game.corridors.advance()
	await settle()
	check(game.corridors.active==null,"returning inside releases the full connector")

func traverse(direction: Vector2i) -> void:
	run.current_room="0,0"
	game.enter_room(Vector3(0,.03,0))
	var id:=portal_for(direction)
	var endpoint: Vector2=Geometry.socket_point(Vector2i.ZERO,direction)
	game.player.place(Vector3(endpoint.x-direction.x*1.8,.03,endpoint.y-direction.y*1.8))
	game.player.velocity=Vector3.ZERO
	game.player.push=Vector3.ZERO
	game.player.invulnerability=100
	game.corridors.arm(id)
	var route: Array=game.corridors.active.path.duplicate()
	var offset: Vector2=game.corridors.destination_offset
	var final_point: Vector2=route.back()+Vector2(direction)*1.7
	route.append(final_point)
	var completed:=true
	for point in route:
		var reached:=false
		for frame in 500:
			await physics_frame
			var target: Vector2=point-(offset if run.current_room!="0,0" else Vector2.ZERO)
			var delta:=target-Vector2(game.player.position.x,game.player.position.z)
			if delta.length()<.18: reached=true;break
			game.fps.yaw=atan2(-delta.x,-delta.y)
			game.fps.pitch=0
			game.player.update_sim(1.0/60.0,Vector2(0,-1),game.fps.forward(),false)
			game.corridors.advance()
		if not reached:
			print("CORRIDOR STUCK: direction=",direction," waypoint=",point," player=",game.player.position," room=",run.current_room)
			completed=false
			break
	check(completed and run.current_room!="0,0","capsule physically walks the full corridor in each orientation")
	check(absf(game.player.position.y)<.12,"connector floors have continuous collision")
	check(game.corridors.active==null and game.room.entry_portal.is_empty(),"arrival restores encounter sealing and releases corridor geometry")
	if direction==Vector2i.RIGHT:
		check(game.enemies.size()>0 and not game.room.open and game.deferred_encounter.is_empty(),"entering the chamber starts its encounter and closes the entrance")
	await settle()
