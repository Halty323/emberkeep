class_name LoftRoom
extends RefCounted
## Two overlapping, independently walkable storeys joined by a staircase.
## Unlike a height-field annex, the deck does not fill the room below it.
const RISE := 3.2
const CEILING := 7.4
const SLAB := .24
const STAIR_WIDTH := 3.0
var deck := Rect2()
var stairs := Rect2()
var timber: Array[Transform3D]=[]

func _init(plan: Dictionary) -> void:
	deck=rect(plan.ledge)
	stairs=rect(plan.ramp)

static func rect(value: Array) -> Rect2:
	return Rect2(float(value[0]),float(value[1]),float(value[2]),float(value[3]))

static func encoded(area: Rect2) -> Array:
	return [area.position.x,area.position.y,area.size.x,area.size.y]

static func plan(data: Dictionary, geometry: RoomGeometry, zones: Array) -> Dictionary:
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
	if value.get("version",0)!=3 or value.get("kind","")!="loft": return false
	for field in ["rise","ceiling"]:
		var number=value.get(field)
		if not (number is int or number is float) or not is_finite(float(number)): return false
	if not is_equal_approx(float(value.get("rise",0)),RISE) or not is_equal_approx(float(value.get("ceiling",0)),CEILING): return false
	for field in ["ledge","ramp"]:
		var a=value.get(field)
		if not a is Array or a.size()!=4 or not a.all(func(n): return (n is int or n is float) and is_finite(float(n))): return false
	var d:=rect(value.ledge)
	var s:=rect(value.ramp)
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
		var h:=RISE*(1.0-(p.y-stairs.position.y)/stairs.size.y)
		return h if at.y>=h-.45 else 0.0
	# Feet approaching on the staircase can step onto the deck. Feet below
	# its slab remain on the lower floor; no actor is lifted through a ceiling.
	if deck.has_point(p) and at.y>=RISE-.45: return RISE
	return 0.0

func upper(at: Vector3) -> bool:
	var p:=Vector2(at.x,at.z)
	if stairs.has_point(p):
		var h:=RISE*(1.0-(p.y-stairs.position.y)/stairs.size.y)
		return at.y>=h-.45
	return at.y>RISE-.45 and deck.grow(.2).has_point(p)

func walkable(p: Vector2, clearance: float, level: float) -> bool:
	if level<1:
		for offset in [Vector2.ZERO,Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			var q: Vector2=p+offset*clearance
			if stairs.has_point(q) and RISE*(1.0-(q.y-stairs.position.y)/stairs.size.y)<2.15: return false
		return true
	for direction in [Vector2.ZERO,Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2(.707,.707),Vector2(-.707,.707),Vector2(.707,-.707),Vector2(-.707,-.707)]:
		var point: Vector2=p+direction*clearance
		if not deck.has_point(point) and not stairs.has_point(point): return false
	return true

func foot(clearance := .5) -> Vector3:
	return Vector3(stairs.get_center().x,0,stairs.end.y+clearance+.2)

func head() -> Vector3:
	return Vector3(stairs.get_center().x,RISE,stairs.position.y-.7)

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
	var root:=Node3D.new()
	root.name="TwoStoreyChamber"
	room.add_child(root)
	var stone:=DungeonStyle.wall_material(Color("7c8074"),true)
	var wood:=DungeonStyle.wood_material(Color("796448"))
	var center:=deck.get_center()
	var slab=Geo.box(root,Vector3(center.x,RISE-SLAB*.5,center.y),Vector3(deck.size.x,SLAB,deck.size.y),Color("77796a"))
	slab.material_override=stone
	Geo.collider(root,slab.position,Vector3(deck.size.x,SLAB,deck.size.y))
	var paving:=MeshInstance3D.new()
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
