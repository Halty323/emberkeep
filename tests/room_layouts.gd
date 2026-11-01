extends SceneTree
## New-generation architecture is measured independently of legacy fixtures.
var checks = 0
var failures = 0
var Generator
var Geometry
var Partitions
var Terrain
var Furnish
var Navigation
func _initialize() -> void:
	OS.set_environment("EMBERKEEP_LEGACY_TEST","0")
	call_deferred("exercise")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+label)
func exercise() -> void:
	var run = root.get_node("Run")
	var catalog = root.get_node("Content")
	Generator = load("res://scripts/dungeon/floor_generator.gd")
	Geometry = load("res://scripts/dungeon/room_geometry.gd")
	Partitions = load("res://scripts/dungeon/room_partitions.gd")
	Terrain = load("res://scripts/first_person/room_terrain.gd")
	Furnish = load("res://scripts/dungeon/furnisher.gd")
	Navigation = load("res://scripts/dungeon/room_navigation.gd")
	var original_rng: int = run.rng.state
	var walls = 0
	var furnished = 0
	var layouts: Dictionary = {}
	var annexes = 0
	var floors = 0
	var optional_counts := {"treasure":0,"shop":0,"dark":0}
	var missing_optional := {"treasure":0,"shop":0,"dark":0}
	var minimum_combat := 999
	var maximum_combat := 0
	var combat_rooms := 0
	var prop_total := 0
	var room_total := 0
	for seed_value in range(1,13):
		for depth in [1,3,5]:
			var data = Generator.generate(seed_value,depth)
			floors += 1
			check(data.generator==3 and not data.get("fallback",false),"new floor uses bounded generation3 without fallback")
			check(data.rooms.size()>=9 and data.rooms.size()<=11,"new tower has9–11 rooms including its secret")
			check(Generator.validate(data).is_empty(),"all mandatory roles, portals and boss dead end remain valid")
			var combats: int = data.rooms.values().filter(func(room): return room.type=="combat").size()
			check(combats>=3,"smaller towers retain at least three combat encounters")
			combat_rooms += combats
			minimum_combat = mini(minimum_combat,combats)
			maximum_combat = maxi(maximum_combat,combats)
			for role in optional_counts:
				var count: int = data.rooms.values().filter(func(room): return room.type==role).size()
				check(count<=1,"optional special rooms never repeat on a floor")
				if count: optional_counts[role]+=1
				else: missing_optional[role]+=1
			if depth==1: check(not data.rooms.values().any(func(room): return room.type=="dark"),"first floor has no dark bargain store")
			check(data.rooms.values().filter(func(room): return room.type=="rest" and not room.mounts.is_empty()).size()==1,"rest room still guarantees a painting")
			if seed_value<=2: check(JSON.stringify(data)==JSON.stringify(Generator.generate(seed_value,depth)),"seeded partitions and furnishing are repeatable")
			for room in data.rooms.values():
				room_total += 1
				prop_total += room.props.size()
				var geometry = Geometry.new(Generator.room_cells(room).map(func(cell): return cell-Generator.vec(room.anchor)))
				var sockets: Dictionary = {}
				for edge in geometry.exposed_edges():
					sockets[str(edge.cell)+":"+str(edge.dir)] = {"cell":edge.cell,"dir":edge.dir,"state":"wall"}
				for portal_id in room.portals:
					var portal: Dictionary = data.portals[portal_id]
					var side: Dictionary = portal.a if portal.a.room==room.id else portal.b
					var local = Generator.vec(side.cell)-Generator.vec(room.anchor)
					var direction = Generator.vec(side.dir)
					sockets[str(local)+":"+str(direction)] = {"cell":local,"dir":direction,"state":portal.state}
				if room.get("fps_terrain",{}).get("version",0)==2:
					check(Terrain.valid_blueprint(room.fps_terrain,geometry,sockets),"planned vertical blueprint remains valid with runtime door and closed-wall sockets")
				var blockers: Dictionary = {}
				var rects: Array[Rect2] = []
				var zones = Generator.reserved_zones(data,room)
				zones.append_array(Terrain.reserved_zones(room,geometry))
				for wall in room.get("partitions",[]):
					walls += 1
					check(Partitions.valid_record(wall,geometry),"wall record is finite, inside the room and bounded")
					var area = Partitions.rect(wall)
					check(not Furnish.hits_zone(area,zones,true,.1),"partitions preserve doorway, light, pedestal and stair reservations")
					for chest in room.chests: check(not area.grow(1).has_point(Generator.vec2(chest.position)),"partition leaves chest approach clear")
					for mount in room.mounts: check(not area.grow(.8).has_point(Generator.vec2(mount.view)),"partition preserves painting viewing spot")
					blockers[wall.id]=area;rects.append(area)
				for prop in room.props:
					check(Furnish.rect_inside(geometry,Furnish.record_rect(prop),.04),"dense furniture stays inside the room")
					var definition: Dictionary = catalog.record("furniture",prop.kind)
					if definition.solid:
						for wall in room.get("partitions",[]): check(not Furnish.record_rect(prop).intersects(Partitions.rect(wall)),"furniture never intersects real interior walls")
						blockers[prop.id]=Furnish.record_rect(prop)
						rects.append(Furnish.record_rect(prop))
				for chest in room.chests: blockers[chest.id]=Rect2(Generator.vec2(chest.position)-Vector2(.5,.33),Vector2(1,.66))
				var nav = Navigation.new(geometry,.5,blockers)
				var boss_nav = Navigation.new(geometry,1.0,blockers) if room.type=="boss" else null
				var hub = Generator.vec2(room.pedestal)
				for portal_id in room.portals:
					var portal: Dictionary = data.portals[portal_id]
					var side: Dictionary = portal.a if portal.a.room==room.id else portal.b
					var goal = Geometry.entry_point(Generator.vec(side.cell)-Generator.vec(room.anchor),Generator.vec(side.dir))
					check(nav.reachable(hub,goal),"every required doorway remains reachable around walls and dense furniture")
					if boss_nav: check(boss_nav.reachable(hub,goal),"boss navigation remains connected with dense furnishings")
				for chest in room.chests: check(nav.reachable(hub,Generator.vec2(chest.position)+Vector2(0,1)),"every chest remains reachable")
				for mount in room.mounts: check(nav.reachable(hub,Generator.vec2(mount.view)),"every painting remains reachable")
				if room.get("fps_terrain",{}).get("version",0)==2: annexes+=1
				if room.type in ["start","combat","rest","shop"]:
					if room.props.size()>=5: furnished+=1
					check(not room.props.is_empty(),"ordinary rooms contain actual furnishings")
				layouts[room.get("theme","")]=true
	var fallback: Dictionary = Generator.fallback_expedition(4141,3)
	check(Generator.validate(fallback).is_empty(),"exhausted retries still produce a legal current-generation tower")
	check(fallback.generator==3 and fallback.rooms.size()>=9 and fallback.rooms.size()<=11,"fallback retains compact current-generation room count")
	check(fallback.rooms.values().any(func(room): return room.cells.size()>1),"compact fallback preserves a larger combat chamber")
	var previous = Generator.generate_v2(4141,3)
	check(previous.generator==2 and previous.rooms.size()>=17,"saved v2 towers retain their original size")
	check(previous.rooms.values().all(func(room): return not room.has("partitions")),"v2 continuation does not acquire new internal walls")
	check(walls>20,"many rooms contain real architectural partitions")
	check(furnished>100,"rooms are furnished across every tested tower")
	check(layouts.size()>=10,"new and existing furniture compositions vary across seeds")
	check(annexes>5,"optional vertical chambers remain available alongside internal walls")
	for role in optional_counts:
		check(optional_counts[role]>0 and missing_optional[role]>0,"special room opportunity varies across seeds: "+role)
	check(float(combat_rooms)/floors>=3.5,"encounters occupy a meaningful share of the compact tower")
	check(float(prop_total)/room_total>=7,"denser rooms contain furnishings beyond isolated pedestal props")
	check(run.rng.state==original_rng,"topology, partitions and furniture never spend combat RNG")
	var geometry = Geometry.new([Vector2i.ZERO])
	for malformed in [{},{"id":"bad","position":[NAN,0],"size":[1,1],"height":3},{"id":"bad","position":[0,0],"size":[20,1],"height":3}]:
		check(not Partitions.valid_record(malformed,geometry),"corrupt saved wall records are rejected")
	print("ROOM LAYOUTS: %d checks, %d failures; %d floors / %d walls / %d annexes / %d furniture compositions; combat %d-%d average %.2f; props average %.2f; special floors %s" % [checks,failures,floors,walls,annexes,layouts.size(),minimum_combat,maximum_combat,float(combat_rooms)/floors,float(prop_total)/room_total,optional_counts])
	quit(0 if failures==0 else 1)
