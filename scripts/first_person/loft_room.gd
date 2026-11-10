class_name LoftRoom
extends RefCounted
## Two overlapping, independently walkable storeys joined by a staircase.
## A "floor" (version 4) is a whole second storey: the upper floor covers the
## room's entire footprint except the stairwell, held up by a grid of columns,
## with its own lanterns and tables. The older "loft" (version 3) is a 10 × 5
## gallery along one wall; saved rooms that have one keep it.
const RISE := 3.2
const CEILING := 7.4
const SLAB := .24
const STAIR_WIDTH := 3.0
const FLOOR_VERSION := 4
var deck := Rect2()
var stairs := Rect2()
var timber: Array[Transform3D]=[]
var full := false
var hole := Rect2()
var geometry: RoomGeometry
# The way the staircase climbs (foot to top); the gallery's always climbs north.
var facing := Vector2(0,-1)

func _init(plan: Dictionary, room_geometry: RoomGeometry = null) -> void:
	deck=rect(plan.ledge)
	stairs=rect(plan.ramp)
	full=str(plan.get("kind",""))=="floor" and room_geometry != null
	geometry=room_geometry
	facing=facing_of(plan)
	if full:
		hole=stair_hole(stairs,facing)
		deck=footprint(room_geometry)

static func facing_of(plan: Dictionary) -> Vector2:
	var value = plan.get("facing",[0,-1])
	if value is Array and value.size()==2:
		var direction := Vector2(float(value[0]),float(value[1]))
		if direction in [Vector2(0,-1),Vector2(0,1),Vector2(1,0),Vector2(-1,0)]: return direction
	return Vector2(0,-1)

## How far up a flight a point is, 0 at its foot and 1 at its top.
static func climb(flight: Rect2, direction: Vector2, p: Vector2) -> float:
	var along: float
	if direction==Vector2(0,-1): along=(flight.end.y-p.y)/flight.size.y
	elif direction==Vector2(0,1): along=(p.y-flight.position.y)/flight.size.y
	elif direction==Vector2(1,0): along=(p.x-flight.position.x)/flight.size.x
	else: along=(flight.end.x-p.x)/flight.size.x
	return clampf(along,0.0,1.0)

func stair_height(p: Vector2) -> float:
	return RISE*climb(stairs,facing,p)

## A flight extended by `before` past its foot and `after` past its top, and
## `side` across it.
static func extended(flight: Rect2, direction: Vector2, before: float, after: float, side: float) -> Rect2:
	var area := flight
	if direction.x==0:
		area=area.grow_individual(side,0,side,0)
		area=area.grow_individual(0,after if direction.y<0 else before,0,before if direction.y<0 else after)
	else:
		area=area.grow_individual(0,side,0,side)
		area=area.grow_individual(after if direction.x<0 else before,0,before if direction.x<0 else after,0)
	return area

## The opening in the upper floor above a staircase: the whole flight, so
## nobody climbing ever meets the slab overhead.
static func stair_hole(flight: Rect2, direction := Vector2(0,-1)) -> Rect2:
	return extended(flight,direction,.25,0.0,.2)

static func footprint(room_geometry: RoomGeometry) -> Rect2:
	var bounds := Rect2()
	for cell in room_geometry.cells:
		var area := Rect2(RoomGeometry.cell_center(cell)-RoomGeometry.HALF,RoomGeometry.CELL)
		bounds = area if not bounds.has_area() else bounds.merge(area)
	return bounds

## Whether a point is on the upper floor (with room to spare).
func on_deck(p: Vector2, margin := 0.0) -> bool:
	if full: return geometry.contains(p,margin) and not hole.grow(margin).has_point(p)
	return deck.grow(-margin).has_point(p)

## Support columns under a whole upper floor: a grid in every cell, kept
## clear of the stairwell, its foot and the room's middle.
static func columns(room_geometry: RoomGeometry, flight: Rect2, direction := Vector2(0,-1)) -> Array[Vector2]:
	var result: Array[Vector2]=[]
	var keep_clear := reserved_area(flight,direction).grow(.8)
	for cell in room_geometry.cells:
		var center := RoomGeometry.cell_center(cell)
		for x in [-4.6,4.6]:
			for z in [-3.4,3.4]:
				var p: Vector2=center+Vector2(x,z)
				if keep_clear.has_point(p) or not room_geometry.contains(p,1.0): continue
				result.append(p)
	return result

## Spots upstairs for foes, the earned chest and lanterns, in a fixed order.
func upper_spots(margin := 1.2) -> Array[Vector2]:
	var result: Array[Vector2]=[]
	for cell in (geometry.cells if full else []):
		var center := RoomGeometry.cell_center(cell)
		for offset in [Vector2(0,-2.5),Vector2(-3.5,1.5),Vector2(3.5,1.5),Vector2(-6.5,-4.5),Vector2(6.5,-4.5),Vector2(0,4.5)]:
			var p: Vector2=center+offset
			if on_deck(p,margin) and not hole.grow(1.4).has_point(p): result.append(p)
	if result.is_empty(): result.append(Vector2(deck.get_center().x,deck.position.y+.8))
	return result

func upper_spot(index: int) -> Vector3:
	var spots := upper_spots()
	var p: Vector2=spots[posmod(index,spots.size())]
	return Vector3(p.x,RISE,p.y)

## Lanterns on the upper floor, set against its walls: two a cell, six at most.
func upper_lanterns() -> Array[Vector3]:
	var result: Array[Vector3]=[]
	if not full:
		for x in [deck.position.x+.8,deck.end.x-.8]: result.append(Vector3(x,RISE,deck.position.y+.8))
		return result
	for cell in geometry.cells:
		var center := RoomGeometry.cell_center(cell)
		var placed := 0
		for offset in [Vector2(-7.6,0),Vector2(7.6,0),Vector2(0,-5.8),Vector2(0,5.8)]:
			var p: Vector2=center+offset
			if placed>=2 or result.size()>=6: break
			if not on_deck(p,.7) or hole.grow(1.6).has_point(p): continue
			result.append(Vector3(p.x,RISE,p.y))
			placed+=1
	return result

static func rect(value: Array) -> Rect2:
	return Rect2(float(value[0]),float(value[1]),float(value[2]),float(value[3]))

static func encoded(area: Rect2) -> Array:
	return [area.position.x,area.position.y,area.size.x,area.size.y]

## A whole second storey: a staircase set into one cell, rising toward a
## landing by its wall, clear of doorways and the room's reserved spots.
static func plan(data: Dictionary, geometry: RoomGeometry, zones: Array) -> Dictionary:
	for cell in geometry.cells:
		var center:=RoomGeometry.cell_center(cell)
		var options: Array=[]
		# Climbing north or south through the middle of a cell, or east or
		# west along its north or south wall.
		for dx in [-5.0,5.0,-2.4,2.4]:
			options.append([Rect2(Vector2(center.x+dx-STAIR_WIDTH*.5,center.y-4.4),Vector2(STAIR_WIDTH,6.2)),Vector2(0,-1)])
			options.append([Rect2(Vector2(center.x+dx-STAIR_WIDTH*.5,center.y-1.8),Vector2(STAIR_WIDTH,6.2)),Vector2(0,1)])
		for z in [-5.6,2.6]:
			options.append([Rect2(Vector2(center.x+.2,center.y+z),Vector2(6.2,STAIR_WIDTH)),Vector2(1,0)])
			options.append([Rect2(Vector2(center.x-6.4,center.y+z),Vector2(6.2,STAIR_WIDTH)),Vector2(-1,0)])
			options.append([Rect2(Vector2(center.x-6.4,center.y+z),Vector2(6.2,STAIR_WIDTH)),Vector2(1,0)])
			options.append([Rect2(Vector2(center.x+.2,center.y+z),Vector2(6.2,STAIR_WIDTH)),Vector2(-1,0)])
		for option in options:
			var flight: Rect2=option[0]
			var direction: Vector2=option[1]
			var reserve:=reserved_area(flight,direction)
			var blueprint: Dictionary={"version":FLOOR_VERSION,"kind":"floor","rise":RISE,"ceiling":CEILING,"ledge":encoded(reserve),"ramp":encoded(flight),"facing":[direction.x,direction.y]}
			if not valid(blueprint,geometry): continue
			var blocked:=false
			var occupied: Array[Rect2]=[reserve]
			for p in columns(geometry,flight,direction): occupied.append(Rect2(p-Vector2.ONE*.4,Vector2.ONE*.8))
			for zone in zones:
				for area in occupied:
					if zone.has("rect") and area.intersects(zone.rect.grow(-.55) if zone.get("kind","")=="door" else zone.rect): blocked=true
					if zone.has("circle"):
						var near:=Vector2(clampf(zone.circle.x,area.position.x,area.end.x),clampf(zone.circle.y,area.position.y,area.end.y))
						if near.distance_to(zone.circle)<(1.25 if zone.get("kind","")=="door" else float(zone.radius)): blocked=true
			if not blocked: return blueprint
	return {}

## What a staircase needs kept clear on the ground: the flight, a landing
## above it and room to step onto it at its foot.
static func reserved_area(flight: Rect2, direction := Vector2(0,-1)) -> Rect2:
	return extended(flight,direction,1.8,1.4,.3)

## The older gallery along one wall (version 3), kept for saved rooms.
static func plan_gallery(data: Dictionary, geometry: RoomGeometry, zones: Array) -> Dictionary:
	for cell in geometry.cells:
		var center:=RoomGeometry.cell_center(cell)
		for side in [-1,1]:
			var deck_area:=Rect2(center+Vector2(side*1.6-5,-5.8),Vector2(10,5))
			var x: float=deck_area.position.x+.8 if side<0 else deck_area.end.x-.8-STAIR_WIDTH
			var stair_area:=Rect2(Vector2(x,deck_area.end.y),Vector2(STAIR_WIDTH,6.2))
			var blueprint: Dictionary={"version":3,"kind":"loft","rise":RISE,"ceiling":CEILING,"ledge":encoded(deck_area),"ramp":encoded(stair_area)}
			if not valid(blueprint,geometry): continue
			var columns:=supports(deck_area)
			var blocked:=false
			for zone in zones:
				var low:=stair_area
				low.position.y+=stair_area.size.y*(1.0-2.15/RISE)
				low.size.y=stair_area.end.y-low.position.y
				var occupied: Array[Rect2]=[low.grow(.15)]
				for p in columns: occupied.append(Rect2(p-Vector2.ONE*.4,Vector2.ONE*.8))
				for area in occupied:
					if zone.has("rect") and area.intersects(zone.rect.grow(-.55) if zone.get("kind","")=="door" else zone.rect): blocked=true
					if zone.has("circle"):
						var near:=Vector2(clampf(zone.circle.x,area.position.x,area.end.x),clampf(zone.circle.y,area.position.y,area.end.y))
						if near.distance_to(zone.circle)<(1.25 if zone.get("kind","")=="door" else float(zone.radius)): blocked=true
			if not blocked: return blueprint
	return {}

static func valid(value: Dictionary, geometry: RoomGeometry, sockets: Dictionary = {}) -> bool:
	var whole: bool = int(value.get("version",0))==FLOOR_VERSION and value.get("kind","")=="floor"
	if not whole and (value.get("version",0)!=3 or value.get("kind","")!="loft"): return false
	for field in ["rise","ceiling"]:
		var number=value.get(field)
		if not (number is int or number is float) or not is_finite(float(number)): return false
	if not is_equal_approx(float(value.get("rise",0)),RISE) or not is_equal_approx(float(value.get("ceiling",0)),CEILING): return false
	for field in ["ledge","ramp"]:
		var a=value.get(field)
		if not a is Array or a.size()!=4 or not a.all(func(n): return (n is int or n is float) and is_finite(float(n))): return false
	var d:=rect(value.ledge)
	var s:=rect(value.ramp)
	if whole:
		var climbing := facing_of(value)
		var expected := Vector2(STAIR_WIDTH,6.2) if climbing.x==0 else Vector2(6.2,STAIR_WIDTH)
		if not s.size.is_equal_approx(expected) or not d.encloses(s): return false
		for x in [d.position.x,d.end.x]:
			for z in [d.position.y,d.end.y]:
				if not geometry.contains(Vector2(x,z),.4): return false
		for socket in sockets.values():
			if socket.get("state","")=="wall": continue
			if d.grow(1.3).has_point(RoomGeometry.socket_point(socket.cell,socket.dir)): return false
		return true
	if d.size!=Vector2(10,5) or s.size!=Vector2(STAIR_WIDTH,6.2): return false
	if absf(d.end.y-s.position.y)>.01 or s.position.x<d.position.x+.4 or s.end.x>d.end.x-.4: return false
	for area in [d,s]:
		for x in [area.position.x,area.end.x]:
			for z in [area.position.y,area.end.y]:
				if not geometry.contains(Vector2(x,z),.6): return false
	for socket in sockets.values():
		if socket.get("state","")=="wall": continue
		var door:=RoomGeometry.socket_point(socket.cell,socket.dir)
		if s.grow(1.45).has_point(door): return false
		for p in supports(d):
			if p.distance_to(door)<1.55: return false
	return true

static func supports(area: Rect2) -> Array[Vector2]:
	var result: Array[Vector2]=[]
	for x in [area.position.x+.2,area.end.x-.2]:
		# Set the front columns back from the gallery edge so side-door
		# approach lanes remain clear on small three-exit chambers too.
		for z in [area.position.y+.2,area.end.y-1.0]: result.append(Vector2(x,z))
	return result

func height_at(at: Vector3) -> float:
	var p:=Vector2(at.x,at.z)
	if stairs.has_point(p):
		var h:=stair_height(p)
		return h if at.y>=h-.45 else 0.0
	# Feet approaching on the staircase can step onto the deck. Feet below
	# its slab remain on the lower floor; no actor is lifted through a ceiling.
	if on_deck(p) and at.y>=RISE-.45: return RISE
	return 0.0

func upper(at: Vector3) -> bool:
	var p:=Vector2(at.x,at.z)
	if stairs.has_point(p):
		var h:=stair_height(p)
		return at.y>=h-.45
	if full: return at.y>RISE-.45 and geometry.contains(p) and not hole.has_point(p)
	return at.y>RISE-.45 and deck.grow(.2).has_point(p)

func walkable(p: Vector2, clearance: float, level: float) -> bool:
	if level<1:
		for offset in [Vector2.ZERO,Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			var q: Vector2=p+offset*clearance
			if stairs.has_point(q) and stair_height(q)<2.15: return false
		return true
	# Routes on the upper storey must stay at upper-floor height. The
	# cross-storey route handles the flight explicitly via its head/foot.
	if full:
		for offset in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(.707,.707), Vector2(-.707,.707), Vector2(.707,-.707), Vector2(-.707,-.707)]:
			if not on_deck(p + offset * clearance): return false
		return true
	# Beside a railed stairwell the floor ends at the rail: only from beyond
	# the open top end may a path step into the flight.
	var beyond_top: bool = (p-(stairs.get_center()+facing*half_flight())).dot(facing) >= -.05
	for direction in [Vector2.ZERO,Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2(.707,.707),Vector2(-.707,.707),Vector2(.707,-.707),Vector2(-.707,-.707)]:
		var point: Vector2=p+direction*clearance
		if full and not stairs.has_point(p) and not beyond_top and hole.has_point(point): return false
		# On a whole upper floor only the top of the flight joins it; its
		# railed sides are no way on or off.
		if not on_deck(point) and not (stairs.has_point(point) and (not full or stair_height(point)>RISE-.9)): return false
	return true

func half_flight() -> float:
	return (stairs.size.y if facing.x==0 else stairs.size.x)*.5

func foot(clearance := .5) -> Vector3:
	var p: Vector2=stairs.get_center()-facing*(half_flight()+clearance+.2)
	return Vector3(p.x,0,p.y)

func head() -> Vector3:
	var p: Vector2=stairs.get_center()+facing*(half_flight()+.7)
	return Vector3(p.x,RISE,p.y)

## The flight's slope collision and treads, for any climbing direction.
func build_flight(root: Node3D, stone: Material) -> void:
	var c: Vector2=stairs.get_center()
	var across := Vector2(-facing.y,facing.x)*(STAIR_WIDTH*.5)
	var top_mid: Vector2=c+facing*half_flight()
	var foot_mid: Vector2=c-facing*half_flight()
	var top: Array[Vector3]=[]
	for p in [top_mid+across,top_mid-across]: top.append(Vector3(p.x,RISE,p.y))
	for p in [foot_mid+across,foot_mid-across]: top.append(Vector3(p.x,0,p.y))
	var pts:=PackedVector3Array(top+top.map(func(p): return p-Vector3.UP*SLAB))
	var shape:=CollisionShape3D.new();var wedge:=ConvexPolygonShape3D.new();wedge.points=pts;shape.shape=wedge
	var body:=StaticBody3D.new();body.add_child(shape);root.add_child(body)
	var treads: Array[Transform3D]=[]
	var length:=half_flight()*2.0/32.0
	for i in 32:
		var height:=RISE*(i+1)/32.0
		var at: Vector2=foot_mid+facing*(i+.5)*length
		var size := Vector3(STAIR_WIDTH,.22,length+.012) if facing.x==0 else Vector3(length+.012,.22,STAIR_WIDTH)
		treads.append(Transform3D(Basis.IDENTITY.scaled(size),Vector3(at.x,height-.11,at.y)))
	FirstPersonArchitecture.batch(root,"StairTreads",treads,stone)

func route(room, from: Vector3, to: Vector3, clearance: float) -> PackedVector3Array:
	var result:=PackedVector3Array()
	var a:=upper(from)
	var b:=upper(to)
	# Once an actor is on the connector, finish that leg. Replanning back to
	# the head every half-second otherwise makes descending foes oscillate.
	if stairs.has_point(Vector2(from.x,from.z)) and a:
		if stairs.has_point(Vector2(to.x,to.z)) and b:
			result.append(to)
			return result
		var destination:=head() if b else foot(clearance)
		result.append(destination)
		append_route(result,room.navigation(clearance,RISE if b else 0),destination,to,RISE if b else 0)
		return result
	if a==b:
		append_route(result,room.navigation(clearance,RISE if a else 0),from,to,RISE if a else 0)
		return result
	var entry:=head() if a else foot(clearance)
	var exit:=foot(clearance) if a else head()
	append_route(result,room.navigation(clearance,RISE if a else 0),from,entry,RISE if a else 0)
	result.append(entry)
	result.append(exit)
	append_route(result,room.navigation(clearance,RISE if b else 0),exit,to,RISE if b else 0)
	return result

func append_route(result: PackedVector3Array, nav: RoomNavigation, from: Vector3, to: Vector3, level: float) -> void:
	for p in nav.find_path(Vector2(from.x,from.z),Vector2(to.x,to.z)):
		var h:=height_at(Vector3(p.x,level,p.y))
		result.append(Vector3(p.x,h,p.y))

func build(room) -> void:
	if full:
		build_floor(room)
		return
	var root:=Node3D.new()
	root.name="TwoStoreyChamber"
	room.add_child(root)
	var stone:=DungeonStyle.structural_material(room.look,Color(room.look.get("cap","7c8074")),true)
	var wood:=DungeonStyle.wood_material(Color("796448"))
	var center:=deck.get_center()
	var slab=Geo.box(root,Vector3(center.x,RISE-SLAB*.5,center.y),Vector3(deck.size.x,SLAB,deck.size.y),Color("77796a"))
	slab.name="GallerySlab"
	slab.material_override=stone
	Geo.collider(root,slab.position,Vector3(deck.size.x,SLAB,deck.size.y))
	var paving:=MeshInstance3D.new()
	paving.name="GalleryFloor"
	var plane:=PlaneMesh.new();plane.size=deck.size
	paving.mesh=plane;paving.position=Vector3(center.x,RISE+.003,center.y)
	paving.material_override=DungeonStyle.floor_material(room.look)
	root.add_child(paving)
	for p in supports(deck):
		var column=Geo.box(root,Vector3(p.x,(RISE-SLAB)*.5,p.y),Vector3(.4,RISE-SLAB,.4),Color("7c8074"))
		column.material_override=stone
		Geo.collider(root,column.position,Vector3(.4,RISE-SLAB,.4))
		room.add_obstacle("loft-column:%s"%str(p),p,.23)
	# A thin stair slab leaves usable room beneath its high end. Smooth
	# collision avoids step-height snags and serves both the player and AI.
	var top: Array[Vector3]=[Vector3(stairs.position.x,RISE,stairs.position.y),Vector3(stairs.end.x,RISE,stairs.position.y),Vector3(stairs.position.x,0,stairs.end.y),Vector3(stairs.end.x,0,stairs.end.y)]
	var pts:=PackedVector3Array(top+top.map(func(p): return p-Vector3.UP*SLAB))
	var shape:=CollisionShape3D.new();var wedge:=ConvexPolygonShape3D.new();wedge.points=pts;shape.shape=wedge
	var body:=StaticBody3D.new();body.add_child(shape);root.add_child(body)
	var treads: Array[Transform3D]=[]
	for i in 32:
		var length:=stairs.size.y/32.0
		var height:=RISE*(32-i)/32.0
		treads.append(Transform3D(Basis.IDENTITY.scaled(Vector3(stairs.size.x,.22,length+.012)),Vector3(stairs.get_center().x,height-.11,stairs.position.y+(i+.5)*length)))
	FirstPersonArchitecture.batch(root,"StairTreads",treads,stone)
	# Grounded rail posts surround the deck, with a real opening at the stair.
	for side in [-1,1]:
		var x: float=deck.position.x if side<0 else deck.end.x
		rail(root,Vector2(x,deck.position.y),Vector2(x,deck.end.y),wood)
	rail(root,deck.position,Vector2(deck.end.x,deck.position.y),wood)
	for span in [Vector2(deck.position.x,stairs.position.x),Vector2(stairs.end.x,deck.end.x)]:
		rail(root,Vector2(span.x,deck.end.y),Vector2(span.y,deck.end.y),wood)
	# Readable furnishing above and below, both grounded on their own floor.
	for y in [0.0,RISE]:
		wood_box(Vector3(center.x,y+.76,deck.position.y+1.3),Vector3(2.3,.16,.9))
		Geo.collider(root,Vector3(center.x,y+.42,deck.position.y+1.3),Vector3(2.3,.84,.9))
		room.add_obstacle("loft-table:%s"%str(y),Vector2(center.x,deck.position.y+1.3),1.2,y)
		room.obstacles.back()["rect"]=Rect2(Vector2(center.x-1.15,deck.position.y+.85),Vector2(2.3,.9))
		for x in [-.92,.92]:
			for z in [-.3,.3]:
				wood_box(Vector3(center.x+x,y+.35,deck.position.y+1.3+z),Vector3(.13,.7,.13))
		for x in [-.7,0,.7]:
			Geo.cylinder(root,Vector3(center.x+x,y+.95,deck.position.y+1.3),.09,.22,Color("a38d6c"))
	root.set_meta("walkable_lower_area",deck.get_area())
	root.set_meta("walkable_upper_area",deck.get_area())
	FirstPersonArchitecture.batch(root,"LoftTimber",timber,wood)
	timber.clear()

## The whole upper storey: slab pieces over every cell around the stairwell,
## a stone ceiling below and paving above, columns, the staircase, a rail
## round the stairwell and tables upstairs.
func build_floor(room) -> void:
	var root:=Node3D.new()
	root.name="TwoStoreyChamber"
	room.add_child(root)
	var stone:=DungeonStyle.structural_material(room.look,Color(room.look.get("cap","7c8074")),true)
	var wood:=DungeonStyle.wood_material(Color("796448"))
	var paving_material: Material=DungeonStyle.floor_material(room.look)
	var pieces: Array[Rect2]=[]
	for cell in geometry.cells: pieces.append(Rect2(RoomGeometry.cell_center(cell)-RoomGeometry.HALF,RoomGeometry.CELL))
	pieces=FirstPersonTerrain.subtract_rects(pieces,hole)
	for piece in pieces:
		if not piece.has_area(): continue
		var middle:=piece.get_center()
		var slab=Geo.box(root,Vector3(middle.x,RISE-SLAB*.5,middle.y),Vector3(piece.size.x,SLAB,piece.size.y),Color("77796a"))
		slab.name="FloorSlab"
		slab.material_override=stone
		Geo.collider(root,slab.position,Vector3(piece.size.x,SLAB,piece.size.y))
		var paving:=MeshInstance3D.new()
		paving.name="UpperFloor"
		var plane:=PlaneMesh.new();plane.size=piece.size
		paving.mesh=plane;paving.position=Vector3(middle.x,RISE+.003,middle.y)
		paving.material_override=paving_material
		root.add_child(paving)
	var beams: Array[Transform3D]=[]
	for p in columns(geometry,stairs,facing):
		var column=Geo.box(root,Vector3(p.x,(RISE-SLAB)*.5,p.y),Vector3(.45,RISE-SLAB,.45),Color("7c8074"))
		column.material_override=stone
		Geo.collider(root,column.position,Vector3(.45,RISE-SLAB,.45))
		room.add_obstacle("floor-column:%s"%str(p),p,.26)
		# A timber capital spreads each column into the slab above it.
		beams.append(Transform3D(Basis.IDENTITY.scaled(Vector3(.9,.18,.9)),Vector3(p.x,RISE-SLAB-.09,p.y)))
	FirstPersonArchitecture.batch(root,"FloorCapitals",beams,wood)
	build_flight(root,stone)
	# The stairwell's rail on every side but the landing at the top.
	var corners := [Vector2(hole.position.x,hole.position.y),Vector2(hole.end.x,hole.position.y),Vector2(hole.end.x,hole.end.y),Vector2(hole.position.x,hole.end.y)]
	for i in 4:
		var a: Vector2=corners[i]
		var b: Vector2=corners[(i+1)%4]
		var middle: Vector2=(a+b)*.5-hole.get_center()
		# The open side faces the way the flight climbs.
		if middle.normalized().dot(facing)>.9: continue
		rail(root,a,b,wood)
	# Upstairs furniture is resolved through the same saved prop pipeline as downstairs.
	var area := 0.0
	for piece in pieces: area += piece.get_area()
	root.set_meta("walkable_lower_area",area)
	root.set_meta("walkable_upper_area",area)
	FirstPersonArchitecture.batch(root,"LoftTimber",timber,wood)
	timber.clear()

func wood_box(at: Vector3,size: Vector3) -> void:
	timber.append(Transform3D(Basis.IDENTITY.scaled(size),at))

func rail(parent: Node3D, a: Vector2, b: Vector2, material: Material) -> void:
	var length:=a.distance_to(b)
	if length<.15: return
	var middle: Vector2=(a+b)*.5
	var along_x:=absf(a.x-b.x)>.01
	var bar:=Vector3(middle.x,RISE+1.0,middle.y)
	wood_box(bar,Vector3(length,.12,.12) if along_x else Vector3(.12,.12,length))
	Geo.collider(parent,bar-Vector3.UP*.5,Vector3(length,1.0,.14) if along_x else Vector3(.14,1.0,length))
	for i in maxi(2,ceili(length/1.7)+1):
		var p:=a.lerp(b,float(i)/maxi(1,ceili(length/1.7)))
		wood_box(Vector3(p.x,RISE+.5,p.y),Vector3(.12,1.0,.12))
