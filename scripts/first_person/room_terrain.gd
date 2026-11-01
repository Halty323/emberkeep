class_name FirstPersonTerrain
extends RefCounted
## Persisted split-level rooms. A single-valued XZ height field gives every
## actor the same floor: a full-height upper annex or a carved cellar, joined
## by a broad physical slope. Old 1.2m gallery blueprints remain unchanged.
var ledge := Rect2()
var ramp := Rect2()
const RISE := 1.2 # Version-one gallery compatibility.
const UPPER_RISE := 2.8
const CELLAR_RISE := -2.6
const ANNEX_WIDTH := 4.6
const ANNEX_DEPTH := 4.2
const APPROACH_DEPTH := 4.8
var rise := RISE
var kind := "gallery"
var built := false

func setup(room, build_geometry := true) -> void:
	if room.data.has("fps_terrain"):
		var saved = room.data.fps_terrain
		if saved is Dictionary and saved.is_empty(): return
		if valid_blueprint(saved, room.geometry, room.sockets):
			ledge = decode_rect(saved.ledge)
			ramp = decode_rect(saved.ramp)
			rise = float(saved.get("rise", RISE))
			kind = str(saved.get("kind", "gallery"))
			if build_geometry: build(room)
		else:
			room.data["fps_terrain"] = {}
		return
	# Modern generation resolves the vertical reservation before furnishing.
	# A missing new record can safely be planned without consuming Run.rng.
	if int(room.data.get("generation", 2)) >= 3:
		var zones: Array = []
		for light in room.data.get("lights", []): zones.append({"circle": Vector2(float(light[0]),float(light[1])), "radius":1.1})
		for socket in room.sockets.values(): zones.append({"circle":RoomGeometry.socket_point(socket.cell,socket.dir),"radius":2.0})
		room.data["fps_terrain"] = plan_generation(room.data, room.geometry, zones)
		setup(room, build_geometry)
		return
	if room.data.get("fps_flat", false) or room.data.get("type", "") != "combat" or room.geometry.cells.size() < 2: return
	var best: Dictionary = {}
	var fewest := 4
	for cell in room.geometry.cells:
		var center = RoomGeometry.cell_center(cell)
		for side in [-1, 1]:
			var candidate = Rect2(center + Vector2(side * 4.4 - 1.7, -4.6), Vector2(3.4, 2.6))
			var approach = Rect2(candidate.position + Vector2(0, 2.6), Vector2(3.4, 3.6))
			var area = candidate.merge(approach).grow(.5)
			var clear := true
			for point in [area.position, area.end, Vector2(area.position.x, area.end.y), Vector2(area.end.x, area.position.y)]:
				if not room.geometry.contains(point, .6): clear = false
			var displaced: Array = []
			for prop in room.data.get("props", []):
				var point = Vector2(float(prop.position[0]), float(prop.position[1]))
				var size = Vector2(float(prop.size[0]), float(prop.size[1])) if prop.has("size") else Vector2.ONE * 1.6
				if area.intersects(Rect2(point - size / 2, size)):
					displaced.append(prop.id)
			for point in room.data.get("lights", []):
				if area.grow(.3).has_point(Vector2(float(point[0]), float(point[1]))): clear = false
			if room.data.has("pedestal") and area.grow(1.0).has_point(Vector2(float(room.data.pedestal[0]), float(room.data.pedestal[1]))): clear = false
			for record in room.data.get("chests", []) + room.data.get("items", []):
				if area.grow(1.0).has_point(Vector2(float(record.position[0]), float(record.position[1]))): clear = false
			for socket in room.sockets.values():
				if area.grow(1.8).has_point(RoomGeometry.socket_point(socket.cell, socket.dir)): clear = false
			if clear and displaced.size() < fewest:
				fewest = displaced.size()
				best = {"ledge": candidate, "ramp": approach, "displaced": displaced}
	if best.is_empty():
		room.data["fps_terrain"] = {}
		return
	ledge = best.ledge
	ramp = best.ramp
	# Reserve this template's walkable gallery before scenery is built. Removing
	# at most three optional props only opens routes; chests, mounts, lights,
	# exits and the pedestal are never displaced. Persist the resolved layout.
	if room.data.has("props"):
		room.data.props.assign(room.data.props.filter(func(prop): return prop.id not in best.displaced))
	room.data["fps_terrain"] = {"version": 1, "ledge": [ledge.position.x, ledge.position.y, ledge.size.x, ledge.size.y], "ramp": [ramp.position.x, ramp.position.y, ramp.size.x, ramp.size.y]}
	if build_geometry: build(room)


static func wants_vertical(data: Dictionary) -> bool:
	return int(data.get("generation",2)) >= 3 and data.get("type","") == "combat" and data.get("cells",[]).size() >= 2 and Content.stable_hash("vertical:%s:%s" % [str(data.get("seed",0)),str(data.get("id",""))]) % 100 < 48

## Called before furniture/partitions. The saved blueprint reserves one safe
## side annex; topology, rewards and gameplay RNG remain independent.
static func plan_generation(data: Dictionary, geometry: RoomGeometry, zones: Array) -> Dictionary:
	if not wants_vertical(data): return {}
	var gen := RandomNumberGenerator.new()
	gen.seed = Content.stable_hash("vertical-layout:%s:%s" % [str(data.get("seed",0)),str(data.get("id",""))])
	var candidates: Array[Rect2] = []
	for cell in geometry.cells:
		var center := RoomGeometry.cell_center(cell)
		for side in [-1,1]:
			candidates.append(Rect2(center+Vector2(side*4.0-ANNEX_WIDTH*.5,-5.2),Vector2(ANNEX_WIDTH,ANNEX_DEPTH)))
	for i in range(candidates.size()-1,0,-1):
		var j := gen.randi_range(0,i)
		var temporary: Rect2 = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = temporary
	for deck in candidates:
		var slope := Rect2(deck.position+Vector2(0,deck.size.y),Vector2(deck.size.x,APPROACH_DEPTH))
		var area := deck.merge(slope)
		if not area_inside(geometry,area,.65): continue
		var blocked := false
		for zone in zones:
			if zone.has("rect") and zone.rect.grow(.12).intersects(area): blocked = true
			if zone.has("circle") and nearest_on(area,zone.circle).distance_to(zone.circle) < float(zone.radius)+.12: blocked = true
		if blocked: continue
		var level := "upper" if gen.randf() < .5 else "cellar"
		return {"version":2,"kind":level,"rise":UPPER_RISE if level=="upper" else CELLAR_RISE,
			"ledge":rect_array(deck),"ramp":rect_array(slope)}
	return {}

static func rect_array(rect: Rect2) -> Array:
	return [snappedf(rect.position.x,.001),snappedf(rect.position.y,.001),snappedf(rect.size.x,.001),snappedf(rect.size.y,.001)]

static func nearest_on(rect: Rect2, point: Vector2) -> Vector2:
	return Vector2(clampf(point.x,rect.position.x,rect.end.x),clampf(point.y,rect.position.y,rect.end.y))

static func area_inside(geometry: RoomGeometry, rect: Rect2, margin: float) -> bool:
	var count := Vector2i(ceili(rect.size.x/.5),ceili(rect.size.y/.5))
	for x in count.x+1:
		for y in count.y+1:
			if not geometry.contains(rect.position+rect.size*Vector2(float(x)/count.x,float(y)/count.y),margin): return false
	return true

static func reserved_zones(data: Dictionary, _geometry: RoomGeometry = null) -> Array:
	var blueprint = data.get("fps_terrain", {})
	if not blueprint is Dictionary or blueprint.get("version",0) != 2: return []
	if not valid_rect(blueprint.get("ledge")) or not valid_rect(blueprint.get("ramp")): return []
	return [{"kind":"vertical","rect":decode_rect(blueprint.ledge).merge(decode_rect(blueprint.ramp)).grow(.65)}]

func challenge() -> bool:
	return kind in ["upper","cellar"] and ledge.has_area()

func reward_point() -> Vector3:
	var center := ledge.get_center()
	return Vector3(center.x,rise,center.y)

## Rectangular subtraction produces only the surrounding main floor. The
## cellar floor and slope are separate physical surfaces below this opening.
static func subtract_rects(sections: Array[Rect2], cut: Rect2) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for section in sections:
		var overlap := section.intersection(cut)
		if not overlap.has_area():
			result.append(section)
			continue
		for piece in [Rect2(section.position,Vector2(section.size.x,overlap.position.y-section.position.y)),
			Rect2(Vector2(section.position.x,overlap.end.y),Vector2(section.size.x,section.end.y-overlap.end.y)),
			Rect2(Vector2(section.position.x,overlap.position.y),Vector2(overlap.position.x-section.position.x,overlap.size.y)),
			Rect2(Vector2(overlap.end.x,overlap.position.y),Vector2(section.end.x-overlap.end.x,overlap.size.y))]:
			if piece.size.x > .001 and piece.size.y > .001: result.append(piece)
	return result

func floor_sections(cell_rect: Rect2) -> Array[Rect2]:
	var sections: Array[Rect2] = [cell_rect]
	return subtract_rects(sections,ledge.merge(ramp)) if kind == "cellar" and ledge.has_area() else sections

static func decode_rect(value: Array) -> Rect2:
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))

static func valid_rect(value: Variant) -> bool:
	return value is Array and value.size() == 4 and value.all(func(number): return (number is int or number is float) and is_finite(float(number))) and float(value[2]) >= 1.2 and float(value[3]) >= 1.2 and float(value[2]) <= 8.0 and float(value[3]) <= 8.0

static func valid_blueprint(value: Variant, geometry: RoomGeometry, sockets: Dictionary = {}) -> bool:
	if not value is Dictionary or value.get("version",-1) not in [1,2]: return false
	if not valid_rect(value.get("ledge")) or not valid_rect(value.get("ramp")): return false
	var deck := decode_rect(value.ledge)
	var slope := decode_rect(value.ramp)
	var level := RISE
	var modern: bool = value.version == 2
	if modern:
		if value.get("kind","") not in ["upper","cellar"]: return false
		var saved_rise = value.get("rise")
		if not (saved_rise is int or saved_rise is float) or not is_finite(float(saved_rise)): return false
		level = float(saved_rise)
		if absf(level-(UPPER_RISE if value.kind=="upper" else CELLAR_RISE)) > .001: return false
		if deck.size.x < 3.3 or deck.size.y < 3.3 or slope.size.y < 4.2: return false
	if absf(deck.position.x-slope.position.x) > .015 or absf(deck.size.x-slope.size.x) > .015 or absf(deck.end.y-slope.position.y) > .015: return false
	if absf(level)/slope.size.y > .8: return false
	var occupied := deck.merge(slope).grow(1.8 if modern else 2.3)
	for socket in sockets.values():
		# The runtime registry also includes solid-wall sockets. Only an
		# actual doorway needs the approach clearance reserved here.
		if socket.get("state","") == "wall": continue
		if occupied.has_point(RoomGeometry.socket_point(socket.cell,socket.dir)): return false
	return area_inside(geometry,deck,.3) and area_inside(geometry,slope,.3)

func height(point: Vector2) -> float:
	if ledge.has_area() and ledge.has_point(point): return rise
	if ramp.has_area() and ramp.has_point(point): return rise * (1.0 - (point.y - ramp.position.y) / ramp.size.y)
	return 0.0

## A capsule touching an incline needs its feet slightly above the height
## directly below its centre. Snapping AI feet to the centreline alone embeds
## the leading hemisphere in a steep ramp and stalls horizontal movement.
func standing_height(point: Vector2, radius: float) -> float:
	var surface := height(point)
	if ramp.has_area() and ramp.has_point(point):
		var slope := rise / ramp.size.y
		surface += maxf(0,radius) * (sqrt(1.0+slope*slope)-1.0)
	return surface

func traversable(point: Vector2, clearance: float) -> bool:
	var here = height(point)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		if absf(height(point + direction * clearance) - here) > .65: return false
	return true

func build(room) -> void:
	if built or not ledge.has_area(): return
	built = true
	var at := ledge.get_center()
	var bottom := minf(-.08,rise-.18)
	var thickness := rise+.08 if rise > 0 else .22
	var deck = Geo.box(room,Vector3(at.x,rise-thickness*.5,at.y),Vector3(ledge.size.x,thickness,ledge.size.y),Color("514c42"))
	deck.material_override = DungeonStyle.wall_material(Color(room.look.get("wall","514c42")))
	Geo.collider(room,deck.position,Vector3(ledge.size.x,thickness,ledge.size.y))
	var paving := MeshInstance3D.new()
	var paving_mesh := PlaneMesh.new()
	paving_mesh.size = ledge.size
	paving.mesh = paving_mesh
	paving.position = Vector3(at.x,rise+.003,at.y)
	paving.material_override = DungeonStyle.floor_material(room.look)
	room.add_child(paving)
	var points: Array[Vector3] = [Vector3(ramp.position.x,rise,ramp.position.y),Vector3(ramp.end.x,rise,ramp.position.y),Vector3(ramp.end.x,0,ramp.end.y),Vector3(ramp.position.x,0,ramp.end.y)]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [0,1,2,0,2,3]:
		tool.set_uv(Vector2(points[i].x,points[i].z))
		tool.add_vertex(points[i])
	tool.generate_normals()
	var view := MeshInstance3D.new()
	view.mesh = tool.commit()
	view.material_override = DungeonStyle.floor_material(room.look)
	room.add_child(view)
	var collider := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var wedge := ConvexPolygonShape3D.new()
	wedge.points = PackedVector3Array(points+[Vector3(ramp.position.x,bottom,ramp.position.y),Vector3(ramp.end.x,bottom,ramp.position.y),Vector3(ramp.end.x,bottom,ramp.end.y),Vector3(ramp.position.x,bottom,ramp.end.y)])
	shape.shape = wedge
	collider.add_child(shape)
	room.add_child(collider)
	var underside: Array = points.map(func(point): return Vector3(point.x,bottom,point.z))
	var facing := SurfaceTool.new()
	facing.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [[points[0],points[3],underside[3],underside[0]],[points[1],underside[1],underside[2],points[2]],
		[points[0],underside[0],underside[1],points[1]],[points[3],points[2],underside[2],underside[3]]]:
		for index in [0,1,2,0,2,3]: facing.add_vertex(face[index])
	facing.generate_normals()
	var sides := MeshInstance3D.new()
	sides.mesh = facing.commit()
	sides.material_override = DungeonStyle.wall_material(Color(room.look.get("wall","514c42")))
	room.add_child(sides)
	if kind == "cellar": build_cellar_banks(room)
	else: build_upper_rails(room)
	if challenge(): build_annex_details(room)

func build_upper_rails(room) -> void:
	# Low raised curbs mark the drop while leaving the ramp mouth clear.
	for side in [ledge.position.x,ledge.end.x]:
		Geo.box(room,Vector3(side,rise+.7,ledge.get_center().y),Vector3(.1,.1,ledge.size.y),Color("9b845e"))

func build_cellar_banks(room) -> void:
	var stone := DungeonStyle.wall_material(Color(room.look.get("wall","514c42")))
	var full := ledge.merge(ramp)
	# Full-height bank faces stop cellar actors walking through the outside
	# foundation. At the ramp, the retaining walls follow its rising profile.
	for side in [full.position.x,full.end.x]:
		var bank = Geo.box(room,Vector3(side,rise*.5,ledge.get_center().y),Vector3(.16,-rise,ledge.size.y),Color("514c42"))
		bank.material_override = stone
		Geo.collider(room,bank.position,Vector3(.16,-rise,ledge.size.y))
		# Move the visible bank a few centimetres into the cutout. Its upper
		# edge otherwise coincides with the main slab's vertical side face.
		var visible_side: float = side + (.025 if side==full.position.x else -.025)
		var vertices: Array[Vector3] = [Vector3(visible_side,rise,ramp.position.y),Vector3(visible_side,0,ramp.end.y),Vector3(visible_side,0,ramp.position.y)]
		var wall := SurfaceTool.new()
		wall.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in ([0,1,2] if side==full.position.x else [2,1,0]): wall.add_vertex(vertices[index])
		wall.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.mesh = wall.commit()
		mesh.material_override = stone
		room.add_child(mesh)
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var prism := ConvexPolygonShape3D.new()
		prism.points = PackedVector3Array(vertices+vertices.map(func(point): return point+Vector3(.12 if side==full.end.x else -.12,0,0)))
		collision.shape = prism
		body.add_child(collision)
		room.add_child(body)
	var back = Geo.box(room,Vector3(ledge.get_center().x,rise*.5,ledge.position.y),Vector3(ledge.size.x,-rise,.16),Color("514c42"))
	back.material_override = stone
	Geo.collider(room,back.position,Vector3(ledge.size.x,-rise,.16))
	# A shallow masonry coping makes the open cellar edge readable and
	# covers coplanar joins with the original main floor. The ramp mouth
	# stays completely open and authoritative collision is unchanged.
	var cap_finish := DungeonStyle.wall_material(Color(room.look.get("cap","736c58")),true)
	for x in [full.position.x,full.end.x]:
		var cap = Geo.box(room,Vector3(x,.04,full.get_center().y),Vector3(.2,.08,full.size.y),Color("736c58"))
		cap.material_override=cap_finish
	var back_cap = Geo.box(room,Vector3(ledge.get_center().x,.04,ledge.position.y),Vector3(ledge.size.x+.2,.08,.2),Color("736c58"))
	back_cap.material_override=cap_finish

func build_annex_details(room) -> void:
	# Architectural shelves and braces make the destination read as a room,
	# without new navigation blockers, lamps or expensive viewport effects.
	var center := ledge.get_center()
	var stone := DungeonStyle.wall_material(Color(room.look.get("cap","736c58")),true)
	for side in [-1,1]:
		var column = Geo.box(room,Vector3(center.x+side*(ledge.size.x*.5-.2),rise+1.0,ledge.position.y+.18),Vector3(.22,2.0,.24),Color("736c58"))
		column.material_override = stone
	var shelf = Geo.box(room,Vector3(center.x,rise+.7,ledge.position.y+.22),Vector3(ledge.size.x-.7,.12,.35),Color("66523a"))
	shelf.material_override = DungeonStyle.wood_material(Color("66523a"))
	for i in 3:
		var book = Geo.box(room,Vector3(center.x-.55+i*.5,rise+.9,ledge.position.y+.22),Vector3(.26,.3,.2),[Color("53614d"),Color("6a4540"),Color("4d5368")][i])
		book.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
