class_name VerticalPlans
extends RefCounted
## Resolve the large architectural reservation before optional fixtures and
## furniture. A floor's primary chamber is chosen early on the boss route;
## lanterns move out of its way instead of silently cancelling the chamber.

static func prepare(floor_data: Dictionary, floor_number: int) -> Dictionary:
	var plans := {}
	var candidates: Array = floor_data.rooms.values().filter(func(room): return room.type=="combat")
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
		var plan := LoftRoom.plan(room,geometry,zones)
		if plan.is_empty() or not legal(plan,geometry,room,floor_data): continue
		plans[room.id] = plan
		room["vertical_primary"] = true
		make_mandatory(floor_data,room.id)
		break
	# Every other room that rolls a second level gets a real upstairs too: a
	# gallery over usable floor, reached by a staircase, never a ramp to a
	# raised ledge or down into a pit. A room too small for one stays flat.
	for room in candidates:
		if plans.has(room.id) or not FirstPersonTerrain.wants_vertical(room): continue
		var geometry := RoomGeometry.new(FloorGenerator.room_cells(room).map(func(cell): return cell-FloorGenerator.vec(room.anchor)))
		var plan := LoftRoom.plan(room,geometry,essential_zones(FloorGenerator.reserved_zones(floor_data,room)))
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
	# The floor's primary chamber first, exactly as before; then the rest.
	var changed := primary_upgrade(rooms,portals,data)
	# Old ramp annexes and sunken cellars in rooms nobody has entered become
	# real two-storey chambers (or flat, where a gallery cannot fit).
	for room in rooms.values():
		var old=room.get("fps_terrain",{})
		if not old is Dictionary or old.is_empty() or int(old.get("version",0))==LoftRoom.FLOOR_VERSION or not untouched(room): continue
		var geometry:=RoomGeometry.new(FloorGenerator.room_cells(room).map(func(cell): return cell-FloorGenerator.vec(room.anchor)))
		var plan:=LoftRoom.plan(room,geometry,essential_zones(FloorGenerator.reserved_zones(data,room)))
		if not plan.is_empty() and legal(plan,geometry,room,data): adopt(room,plan,geometry,data)
		else: room.erase("fps_terrain")
		changed=true
	return changed

static func untouched(room: Dictionary) -> bool:
	return not room.get("visited",false) and not room.get("cleared",false) and room.get("items",[]).is_empty() and not room.get("chests",[]).any(func(chest): return chest.get("opened",false))

static func primary_upgrade(rooms: Dictionary, portals: Dictionary, data: Dictionary) -> bool:
	for room in rooms.values():
		var blueprint=room.get("fps_terrain",{})
		if not blueprint is Dictionary or int(blueprint.get("version",0))<3: continue
		var geometry:=RoomGeometry.new(FloorGenerator.room_cells(room).map(func(cell): return cell-FloorGenerator.vec(room.anchor)))
		if legal(blueprint,geometry,room,data): return false
	var candidates: Array=rooms.values().filter(func(room): return room.type=="combat" and untouched(room))
	var route:=boss_route(data)
	# Prefer a chamber the boss route can be made to pass through: tried on a
	# copy of the floor, closing only the loops that would skip it.
	var unavoidable := {}
	for room in candidates:
		var trial: Dictionary = {"rooms": data.rooms.duplicate(true), "portals": data.portals.duplicate(true)}
		make_mandatory(trial, room.id)
		unavoidable[room.id] = route_portals(trial, room.id).is_empty()
	candidates.sort_custom(func(a,b):
		if unavoidable[a.id]!=unavoidable[b.id]: return unavoidable[a.id]
		if (a.id in route)!=(b.id in route): return a.id in route
		return int(a.depth)<int(b.depth) if int(a.depth)!=int(b.depth) else str(a.id)<str(b.id))
	for room in candidates:
		var geometry:=RoomGeometry.new(FloorGenerator.room_cells(room).map(func(cell): return cell-FloorGenerator.vec(room.anchor)))
		var plan:=LoftRoom.plan(room,geometry,essential_zones(FloorGenerator.reserved_zones(data,room)))
		if plan.is_empty() or not legal(plan,geometry,room,data): continue
		room["vertical_primary"]=true
		adopt(room,plan,geometry,data)
		return true
	return false

## Give an untouched room a gallery: lanterns, furniture, partitions and
## chests move out of the staircase and supports' way.
static func adopt(room: Dictionary, plan: Dictionary, geometry: RoomGeometry, data: Dictionary) -> void:
	room["fps_terrain"]=plan
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

## Remove only cycle edges that bypass this chamber. The complete floor
## remains connected, including optional branches and concealed secrets.
static func make_mandatory(data: Dictionary, primary: String) -> void:
	var normal:=route_portals(data,"")
	for attempt in data.portals.size():
		var bypass:=route_portals(data,primary)
		if bypass.is_empty(): return
		var removable:=bypass.filter(func(id): return id not in normal)
		if removable.is_empty(): return
		var id: String=removable.back()
		var portal: Dictionary=data.portals[id]
		for side in [portal.a,portal.b]: data.rooms[side.room].portals.erase(id)
		data.portals.erase(id)

static func route_portals(data: Dictionary, excluded: String) -> Array:
	var parents: Dictionary={FloorGenerator.START_ID:{"room":"","portal":""}}
	var queue: Array=[FloorGenerator.START_ID]
	while not queue.is_empty():
		var id: String=queue.pop_front()
		if data.rooms[id].type=="boss":
			var result: Array=[]
			while not parents[id].room.is_empty():
				result.push_front(parents[id].portal)
				id=parents[id].room
			return result
		for key in data.rooms[id].portals:
			var portal: Dictionary=data.portals[key]
			if portal.state=="concealed": continue
			var other: String=portal.b.room if portal.a.room==id else portal.a.room
			if other==excluded or parents.has(other): continue
			parents[other]={"room":id,"portal":key};queue.append(other)
	return []
