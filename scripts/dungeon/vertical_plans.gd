class_name VerticalPlans
extends RefCounted
## Resolve the large architectural reservation before optional fixtures and
## furniture. A floor's primary chamber is chosen early on the boss route;
## lanterns move out of its way instead of silently cancelling the chamber.

static func prepare(floor_data: Dictionary, floor_number: int) -> Dictionary:
	var plans := {}
	var candidates: Array = floor_data.rooms.values().filter(func(room): return room.type=="combat" and room.cells.size()>1)
	var route := boss_route(floor_data)
	candidates.sort_custom(func(a,b):
		var ar: bool = a.id in route
		var br: bool = b.id in route
		if ar!=br: return ar
		if int(a.depth)!=int(b.depth): return int(a.depth)<int(b.depth)
		return str(a.id)<str(b.id))
	for room in candidates:
		if room.id not in route: continue
		var geometry := RoomGeometry.new(FloorGenerator.room_cells(room).map(func(cell): return cell-FloorGenerator.vec(room.anchor)))
		var zones := essential_zones(FloorGenerator.reserved_zones(floor_data,room))
		var plan := FirstPersonTerrain.plan_generation(room,geometry,zones,true)
		if plan.is_empty() or not legal(plan,geometry,room,floor_data): continue
		plan.kind = "upper" if floor_number%2==1 else "cellar"
		plan.rise = FirstPersonTerrain.UPPER_RISE if plan.kind=="upper" else FirstPersonTerrain.CELLAR_RISE
		plans[room.id] = plan
		room["vertical_primary"] = true
		break
	for room in candidates:
		if plans.has(room.id): continue
		var geometry := RoomGeometry.new(FloorGenerator.room_cells(room).map(func(cell): return cell-FloorGenerator.vec(room.anchor)))
		var plan := FirstPersonTerrain.plan_generation(room,geometry,essential_zones(FloorGenerator.reserved_zones(floor_data,room)))
		if not plan.is_empty() and legal(plan,geometry,room,floor_data): plans[room.id] = plan
	for id in plans:
		var room: Dictionary = floor_data.rooms[id]
		room["fps_terrain"] = plans[id]
		relocate_lanterns(room,RoomGeometry.new(FloorGenerator.room_cells(room).map(func(cell): return cell-FloorGenerator.vec(room.anchor))),essential_zones(FloorGenerator.reserved_zones(floor_data,room)))
	return plans

static func essential_zones(zones: Array) -> Array:
	var result: Array = []
	for original in zones:
		if original.get("kind","")=="lantern": continue
		var zone: Dictionary = original.duplicate()
		# A combat reward needs a clear central spot, not a 5.2m exclusion
		# disk that rules out both side annexes by a few centimetres.
		if zone.get("kind","")=="pedestal": zone.radius=2.1
		result.append(zone)
	return result

static func legal(plan: Dictionary, geometry: RoomGeometry, room: Dictionary, floor_data: Dictionary) -> bool:
	var sockets := {}
	for id in room.portals:
		var portal: Dictionary = floor_data.portals[id]
		var side: Dictionary = portal.a if portal.a.room==room.id else portal.b
		sockets[id] = {"cell":FloorGenerator.vec(side.cell)-FloorGenerator.vec(room.anchor),"dir":FloorGenerator.vec(side.dir),"state":portal.state}
	return FirstPersonTerrain.valid_blueprint(plan,geometry,sockets)

static func relocate_lanterns(room: Dictionary, geometry: RoomGeometry, zones: Array) -> void:
	var blueprint: Dictionary = room.fps_terrain
	var area := FirstPersonTerrain.decode_rect(blueprint.ledge).merge(FirstPersonTerrain.decode_rect(blueprint.ramp)).grow(1.15)
	var lights: Array = room.get("lights",[]).duplicate(true)
	for index in lights.size():
		var at := FloorGenerator.vec2(lights[index])
		if not area.has_point(at): continue
		var best := at
		var found := false
		for radius in [.5,1.0,1.5,2.0,2.5,3.0,4.0,5.0]:
			for direction in 24:
				var candidate: Vector2 = at+Vector2.RIGHT.rotated(TAU*direction/24.0)*radius
				if area.has_point(candidate) or not geometry.contains(candidate,.7) or FloorGenerator.in_zones(candidate,zones,.3): continue
				var crowded := false
				for other in lights.size():
					if other!=index and FloorGenerator.vec2(lights[other]).distance_to(candidate)<1.0: crowded=true
				if crowded: continue
				best=candidate
				found=true
				break
			if found: break
		if found: lights[index]=FloorGenerator.point_array(best)
	room.lights=lights

static func boss_route(floor_data: Dictionary) -> Array:
	var parents := {FloorGenerator.START_ID:""}
	var queue: Array = [FloorGenerator.START_ID]
	var boss := ""
	while not queue.is_empty():
		var id: String = queue.pop_front()
		if floor_data.rooms[id].type=="boss": boss=id;break
		for portal_id in floor_data.rooms[id].portals:
			var portal: Dictionary = floor_data.portals[portal_id]
			if portal.state=="concealed": continue
			var other: String = portal.b.room if portal.a.room==id else portal.a.room
			if parents.has(other): continue
			parents[other]=id
			queue.append(other)
	var result: Array = []
	while not boss.is_empty():
		result.append(boss)
		boss=parents.get(boss,"")
	return result

## A pre-update checkpoint may have no vertical room at all. Repair one
## untouched chamber only; visited rooms, opened chests and collected items
## are never moved or regenerated. New floors use prepare() unconditionally.
static func upgrade_unvisited(rooms: Dictionary, portals: Dictionary, floor_number: int) -> bool:
	var data := {"rooms":rooms,"portals":portals}
	for room in rooms.values():
		var blueprint=room.get("fps_terrain",{})
		if not blueprint is Dictionary or blueprint.get("version",0)!=2: continue
		var geometry:=RoomGeometry.new(FloorGenerator.room_cells(room).map(func(cell): return cell-FloorGenerator.vec(room.anchor)))
		if legal(blueprint,geometry,room,data): return false
	var candidates: Array=rooms.values().filter(func(room):
		return int(room.get("generation",2))>=3 and room.type=="combat" and room.cells.size()>1 and not room.get("visited",false) and not room.get("cleared",false) and room.get("items",[]).is_empty() and not room.get("chests",[]).any(func(chest): return chest.get("opened",false)))
	candidates.sort_custom(func(a,b): return int(a.depth)<int(b.depth) if int(a.depth)!=int(b.depth) else str(a.id)<str(b.id))
	for room in candidates:
		var geometry:=RoomGeometry.new(FloorGenerator.room_cells(room).map(func(cell): return cell-FloorGenerator.vec(room.anchor)))
		var plan:=FirstPersonTerrain.plan_generation(room,geometry,essential_zones(FloorGenerator.reserved_zones(data,room)),true)
		if plan.is_empty() or not legal(plan,geometry,room,data): continue
		plan.kind="upper" if floor_number%2==1 else "cellar"
		plan.rise=FirstPersonTerrain.UPPER_RISE if plan.kind=="upper" else FirstPersonTerrain.CELLAR_RISE
		room["fps_terrain"]=plan
		room["vertical_primary"]=true
		var area:=FirstPersonTerrain.decode_rect(plan.ledge).merge(FirstPersonTerrain.decode_rect(plan.ramp)).grow(.7)
		var zones:=essential_zones(FloorGenerator.reserved_zones(data,room))
		relocate_lanterns(room,geometry,zones)
		room.props=room.get("props",[]).filter(func(prop): return not area.intersects(Furnisher.record_rect(prop)))
		room.partitions=room.get("partitions",[]).filter(func(wall): return not area.intersects(RoomPartitions.rect(wall)))
		for chest in room.get("chests",[]):
			var at:=FloorGenerator.vec2(chest.position)
			if not area.grow(.8).has_point(at): continue
			var point:=geometry.safe_point(at,.8,func(p):
				return area.grow(.8).has_point(p) or FloorGenerator.in_zones(p,zones,.5) or room.props.any(func(prop): return Furnisher.record_rect(prop).grow(.8).has_point(p)))
			chest.position=FloorGenerator.point_array(point)
		return true
	return false
