class_name ThemedInteriors
extends RefCounted
## Authored story vignettes assembled in safe visual layers: shallow wall
## reliefs, existing furniture tops and ankle-low scatter. No new collision
## or gameplay state; candle positions feed the bounded room light pool. Primitive surfaces merge into four material
## batches, so many small details do not become hundreds of draw calls.
const THEMES := ["cellar", "cistern", "halls", "crypt", "archive", "kiln", "belfry", "hearth"]
const TOP_RECIPES := ["table", "workbench", "crate", "barrel", "cupboard", "pillar", "bench"]
const MAX_VERTICES := [12000, 20000, 30000]
const STONE := Color("777365")
const IRON := Color("343d42")
const BRASS := Color("b49a62")
const WOOD := Color("71513a")
const LINEN := Color("c8b995")
static var primitive_arrays: Dictionary = {}
static var finishes: Dictionary = {}
var groups: Dictionary = {}
var flame_sources: Array[Vector3] = []
var vertex_count := 0
var piece_count := 0
var limit := 24000
var probe_only := false
var skipped_scenes := 0
var report: Dictionary = {}

## One material batch. Each primitive is appended as whole packed arrays
## (its vertices once, then its indices), not one engine call per corner.
class Batch:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh

static func decorate(room) -> Dictionary:
	var builder = ThemedInteriors.new()
	var theme: String = Run.theme_id()
	var detail: int = Settings.detail_level()
	builder.limit = MAX_VERTICES[clampi(detail, 0, 2)]
	builder.report = plan(room, theme, detail)
	var wall_plan: Array = builder.report.walls
	var top_plan: Array = builder.report.tops
	var floor_plan: Array = builder.report.scatter
	builder.report.walls = []
	builder.report.tops = []
	builder.report.scatter = []
	# A staged room pauses between scenes when its frame slice is spent.
	var paced: bool = room.has_method("pace")
	for anchor in wall_plan:
		var inward = Vector3(-anchor.dir.x, 0, -anchor.dir.y)
		var frame = Transform3D(Basis(Vector3.UP, atan2(inward.x, inward.z)), Vector3(anchor.at.x, 2.03, anchor.at.y))
		if builder.try_scene(func(): builder.wall_scene(theme, frame, anchor.variant)):
			builder.report.walls.append(anchor)
		if paced: await room.pace()
	for anchor in top_plan:
		var frame = Transform3D(Basis(Vector3.UP, anchor.turn), anchor.at)
		if builder.try_scene(func(): builder.table_scene(theme, frame, anchor.scale, anchor.variant)):
			builder.report.tops.append(anchor)
		if paced: await room.pace()
	for anchor in floor_plan:
		var frame = Transform3D(Basis(Vector3.UP, anchor.turn), anchor.at)
		if builder.try_scene(func(): builder.floor_scene(theme, frame, anchor.variant)):
			builder.report.scatter.append(anchor)
		if paced: await room.pace()
	builder.finish(room)
	if room.illumination:
		for source in builder.flame_sources: room.illumination.register_flame(source)
	builder.report["vertices"] = builder.vertex_count
	builder.report["pieces"] = builder.piece_count
	builder.report["batches"] = builder.groups.size()
	builder.report["skipped_scenes"] = builder.skipped_scenes
	return builder.report

static func plan(room, theme: String, detail: int) -> Dictionary:
	var result = {"theme": theme, "walls": [], "tops": [], "scatter": []}
	if theme not in THEMES: return result
	var gen = RandomNumberGenerator.new()
	gen.seed = Content.stable_hash("interior:%s:%d:%s" % [theme, int(room.data.get("seed", 0)), str(room.data.get("id", ""))])
	var candidates: Array = room.geometry.wall_segments().filter(func(edge): return float(edge.to - edge.from) >= 2.7)
	# Deterministic shuffle on a private cosmetic stream.
	for i in range(candidates.size() - 1, 0, -1):
		var j = gen.randi_range(0, i)
		var temp = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = temp
	var wall_limit = mini(4, room.geometry.cells.size() + 1 + (1 if detail == 2 else 0))
	if detail == 0: wall_limit = mini(2, wall_limit)
	for edge in candidates:
		if result.walls.size() >= wall_limit: break
		var along = (edge.from + edge.to) / 2.0
		var face = Vector2(along, edge.line) if edge.dir.x == 0 else Vector2(edge.line, along)
		var at = face - Vector2(edge.dir) * .025
		if not wall_clear(room, face, edge.dir): continue
		if result.walls.any(func(other): return other.at.distance_to(at) < 3.0): continue
		result.walls.append({"at": at, "dir": edge.dir, "variant": gen.randi_range(0, 2)})
	var top_limit = mini(4, room.geometry.cells.size() + (1 if detail > 0 else 0))
	var tops_per_level := {}
	for id in room.props:
		var prop: Dictionary = room.props[id]
		var definition: Dictionary = prop.definition
		if definition.recipe not in TOP_RECIPES or not definition.get("solid", false) or definition.has("breakable"): continue
		var record: Dictionary = prop.record
		var level := float(record.get("height", 0))
		if int(tops_per_level.get(level, 0)) >= top_limit: continue
		tops_per_level[level] = int(tops_per_level.get(level, 0)) + 1
		var size = Vector2(float(definition.size[0]), float(definition.size[1]))
		var scale = clampf(minf(size.x, size.y) / 1.1, .4, 1.0)
		var at = Vector3(float(record.position[0]), float(record.get("height", 0)) + float(definition.height) + .025, float(record.position[1]))
		result.tops.append({"id": id, "at": at, "turn": -float(record.get("rotation", 0)) * PI / 2, "scale": scale, "variant": gen.randi_range(0, 2)})
	var scatter_limit = mini(12, room.geometry.cells.size() * (2 if detail == 0 else 4))
	for cell in room.geometry.cells:
		for attempt in 24:
			if result.scatter.size() >= scatter_limit: break
			var point = RoomGeometry.cell_center(cell) + Vector2(gen.randf_range(-6.8, 6.8), gen.randf_range(-4.9, 4.9))
			if not scatter_clear(room, point): continue
			if result.scatter.any(func(other): return Vector2(other.at.x, other.at.z).distance_to(point) < 1.4): continue
			result.scatter.append({"at": Vector3(point.x, .018, point.y), "turn": gen.randf() * TAU, "variant": gen.randi_range(0, 2)})
	return result

static func wall_clear(room, face: Vector2, direction: Vector2i) -> bool:
	# Existing painting mounts and tall furniture keep their viewing space.
	for mount in room.data.get("mounts", []):
		if Vector2(float(mount.position[0]), float(mount.position[1])).distance_to(face) < float(mount.width) / 2.0 + 1.9: return false
	var probe = face - Vector2(direction) * .55
	for prop in room.props.values():
		var definition: Dictionary = prop.definition
		if float(definition.height) < 1.2: continue
		var point = Vector2(float(prop.record.position[0]), float(prop.record.position[1]))
		var half = maxf(float(definition.size[0]), float(definition.size[1])) / 2.0
		if probe.distance_to(point) < half + 1.4: return false
	for light in room.data.get("lights", []):
		if Vector2(float(light[0]), float(light[1])).distance_to(probe) < 1.0: return false
	# A gallery can place the viewer at wall-relief height. Reserve its edge.
	if room.terrain and room.terrain.ledge.has_area() and room.terrain.ledge.merge(room.terrain.ramp).grow(.8).has_point(probe): return false
	return true

static func scatter_clear(room, at: Vector2) -> bool:
	if not room.geometry.contains(at, .7) or room.blocked_at(at): return false
	if at.distance_to(Vector2(room.pedestal.x, room.pedestal.z)) < 2.7: return false
	if room.terrain and room.terrain.ledge.has_area() and room.terrain.ledge.merge(room.terrain.ramp).grow(.9).has_point(at): return false
	for socket in room.sockets.values():
		if RoomGeometry.socket_point(socket.cell, socket.dir).distance_to(at) < 2.7: return false
	for record in room.data.get("chests", []) + room.data.get("items", []):
		if Vector2(float(record.position[0]), float(record.position[1])).distance_to(at) < 1.7: return false
	for mount in room.data.get("mounts", []):
		if Vector2(float(mount.view[0]), float(mount.view[1])).distance_to(at) < 1.8: return false
	return true

## Measure a complete authored vignette first, then either append all of it
## or omit all of it. A low detail budget cannot leave half a wheel/chain.
func try_scene(draw: Callable) -> bool:
	var before_vertices = vertex_count
	var before_pieces = piece_count
	probe_only = true
	draw.call()
	var cost = vertex_count - before_vertices
	vertex_count = before_vertices
	piece_count = before_pieces
	probe_only = false
	if before_vertices + cost > limit:
		skipped_scenes += 1
		return false
	draw.call()
	return true

func wall_scene(theme: String, frame: Transform3D, variant: int) -> void:
	match theme:
		"cellar":
			# Prisoner's chains, tally marks and a crooked keeper's shelf.
			box(frame, Vector3(0,.87,0), Vector3(1.9,.13,.08), WOOD)
			for side in [-1,1]:
				for link in 5:
					ring(frame, Vector3(side*.63,.55-link*.27,.035), Vector3(.11,.15,.025), IRON, "metal", PI/2 if link%2==0 else 1.15)
				ring(frame, Vector3(side*.63,-.66,.035), Vector3(.22,.25,.035), BRASS, "metal")
			for mark in 5:
				box(frame, Vector3(-.25+mark*.1,.1,.025),Vector3(.026,.33,.025), LINEN.darkened(.35), "matte", -.12 if mark<4 else 1.05)
			box(frame, Vector3(.22,-.95,0),Vector3(.85,.13,.13), WOOD)
		"cistern":
			# Sluice valve, pipe joints, riveted drain and tide-level gauge.
			box(frame, Vector3(-.74,.04,.01), Vector3(.15,2.2,.12), Color("678387"), "metal")
			box(frame, Vector3(.15,.83,.01), Vector3(1.9,.13,.12), Color("678387"), "metal")
			for y in [-.7,.0,.7]: box(frame,Vector3(-.74,y,.025),Vector3(.27,.13,.14),BRASS,"metal")
			wheel(frame, Vector3(.25,.15,.045), .55, Color("a26a44"), 8)
			box(frame,Vector3(.78,-.66,.01),Vector3(.34,.98,.035),IRON)
			for i in 6: box(frame,Vector3(.78,-1.04+i*.15,.035),Vector3(.25 if i%2==0 else .14,.025,.025),LINEN)
		"halls":
			# Old garden masonry split by a curling root and little seed pods.
			box(frame,Vector3(.15,-.22,0),Vector3(1.6,1.4,.045),STONE.darkened(.12))
			for side in [-1,1]:
				var points = [Vector3(side*.8,-1,.025),Vector3(side*.6,-.35,.05),Vector3(side*.95,.2,.055),Vector3(side*.5,.82,.03),Vector3(side*.2,1.25,.025)]
				for i in points.size()-1: bar(frame,points[i],points[i+1],.09,Color("536045"))
				for i in 3: sphere(frame,Vector3(side*(.25+i*.22),.85+i*.14,.025),Vector3(.15,.065,.035),Color("7d9a59"))
			for i in 3: sphere(frame,Vector3(-.25+i*.26,-.18,.06),Vector3(.11,.17,.035),Color("a1a46c"))
		"crypt":
			# A memorial niche, ribbon, unlit candles and a carved remembrance.
			box(frame,Vector3(0,-.02,0),Vector3(1.5,1.92,.045),Color("5d555d"))
			for side in [-1,1]: box(frame,Vector3(side*.77,.0,.02),Vector3(.16,2.1,.075),STONE)
			box(frame,Vector3(0,1.04,.02),Vector3(1.72,.16,.09),STONE)
			box(frame,Vector3(0,-1.04,.02),Vector3(1.85,.19,.13),STONE)
			box(frame,Vector3(0,.15,.035),Vector3(.13,1.05,.045),BRASS,"metal")
			box(frame,Vector3(0,.35,.035),Vector3(.65,.12,.045),BRASS,"metal")
			for i in 4:
				box(frame,Vector3(-.6+i*.39,-.76,.045),Vector3(.1,.35+(i%2)*.15,.055),LINEN)
				sphere(frame,Vector3(-.6+i*.39,-.53+(i%2)*.07,.05),Vector3(.06,.09,.025),Color("ffca76"),"ember")
			box(frame,Vector3(.44,.0,.06),Vector3(.19,1.45,.02),Color("763e4d"),"cloth")
		"archive":
			# An astrolabe with star ticks over a scroll pigeonhole.
			wheel(frame,Vector3(0,.45,.035),.73,BRASS,12)
			ring(frame,Vector3(0,.45,.04),Vector3(.52,.52,.04),Color("8f9eac"),"metal")
			bar(frame,Vector3(-.48,.05,.075),Vector3(.5,.95,.075),.045,LINEN)
			box(frame,Vector3(0,-.73,.005),Vector3(1.85,.63,.13),WOOD)
			for i in 6:
				box(frame,Vector3(-.75+i*.3,-.73,.035),Vector3(.04,.62,.15),WOOD.darkened(.3))
				cylinder(frame,Vector3(-.62+i*.3,-.65,.085),Vector3(.085,.07,.085),LINEN,"matte",PI/2)
		"kiln":
			# Riveted furnace mouth and a soot-dark rack of smith's tools.
			box(frame,Vector3(-.27,.0,0),Vector3(1.35,1.7,.05),IRON)
			box(frame,Vector3(-.27,-.1,.03),Vector3(.93,.93,.025),Color("ca632c"),"ember")
			for i in 6: box(frame,Vector3(-.73+i*.18,-.1,.06),Vector3(.065,1.07,.045),IRON,"metal")
			for side in [-1,1]:
				for y in [-.7,.7]: sphere(frame,Vector3(-.27+side*.56,y,.065),Vector3(.06,.06,.025),BRASS,"metal")
			box(frame,Vector3(.86,.76,0),Vector3(.6,.12,.12),WOOD)
			for i in 2:
				bar(frame,Vector3(.65+i*.36,.65,.04),Vector3(.7+i*.33,-.65,.04),.065,IRON,"metal")
				box(frame,Vector3(.7+i*.33,-.66,.04),Vector3(.31,.19,.07),IRON,"metal")
		"belfry":
			# Meshing exposed clock wheels and their hanging drive chains.
			gear(frame,Vector3(-.35,.36,.035),.65,BRASS,12)
			gear(frame,Vector3(.62,-.19,.035),.41,Color("77848a"),10)
			for side in [-1,1]:
				for i in 7: ring(frame,Vector3(side*.92,.65-i*.25,.03),Vector3(.075,.12,.025),IRON,"metal")
			bar(frame,Vector3(-.35,.36,.07),Vector3(-.15,.74,.07),.045,LINEN)
		"hearth":
			# A little household hearth, copper pans, a drying towel and keepsake.
			for side in [-1,1]: box(frame,Vector3(side*.68,-.15,0),Vector3(.25,1.55,.12),STONE)
			box(frame,Vector3(0,.66,.01),Vector3(1.7,.24,.14),STONE)
			box(frame,Vector3(0,-.25,.01),Vector3(1.08,.95,.03),IRON)
			for i in 3: sphere(frame,Vector3(-.3+i*.3,-.4,.045),Vector3(.18,.37-(i%2)*.08,.035),Color("ebaa52"),"ember")
			box(frame,Vector3(.99,.39,.02),Vector3(.18,.97,.025),Color("af8664"),"cloth")
			cylinder(frame,Vector3(-1.06,.16,.025),Vector3(.29,.045,.29),Color("a87d50"),"metal",PI/2)
			box(frame,Vector3(-1.06,.6,.025),Vector3(.07,.43,.045),IRON,"metal")
	if variant == 1:
		# Asymmetry keeps repeated wall compositions from feeling stamped.
		box(frame,Vector3(1.02,-.94,.01),Vector3(.27,.17,.07),STONE.darkened(.22))

func table_scene(theme: String, source: Transform3D, scale: float, variant: int) -> void:
	var frame = source * Transform3D(Basis.from_scale(Vector3.ONE * scale),Vector3.ZERO)
	match theme:
		"cellar":
			for i in 3: jar(frame,Vector3(-.3+i*.28,0,.08*(i%2)),.13,.32+(i%2)*.12,Color("68827d"))
			box(frame,Vector3(.2,.035,-.27),Vector3(.42,.065,.21),LINEN,"cloth",.08)
		"cistern":
			bucket(frame,Vector3(-.23,0,0),.23,Color("6b797b"))
			wheel(frame,Vector3(.3,.22,.14),.25,Color("a26a44"),6)
			bar(frame,Vector3(.18,.035,-.3),Vector3(.42,.035,.24),.055,BRASS,"metal")
		"halls":
			for i in 4:
				var point = Vector3(-.35+(i%2)*.45,.0,-.18+(i/2)*.32)
				cylinder(frame,point+Vector3.UP*.16,Vector3(.045,.3,.045),Color("b6aa79"))
				sphere(frame,point+Vector3.UP*.31,Vector3(.18,.09,.18),[Color("b5b66a"),Color("779c7d"),Color("a799bc")][i%3])
		"crypt":
			box(frame,Vector3(0,.025,0),Vector3(.72,.045,.52),Color("72505e"),"cloth")
			for i in 3: candle(frame,Vector3(-.25+i*.25,.05,-.1),.22+i*.09)
			sphere(frame,Vector3(.18,.15,.18),Vector3(.18,.14,.17),LINEN)
			for x in [-1,1]: box(frame,Vector3(.18+x*.07,.17,.32),Vector3(.04,.045,.015),IRON)
		"archive":
			box(frame,Vector3(0,.035,0),Vector3(.78,.06,.54),Color("3e6174"),"cloth")
			for i in 3: box(frame,Vector3(-.28,.08+i*.055,.15),Vector3(.31,.05,.22),[Color("8d6a4c"),Color("b9af86"),Color("627c7e")][i])
			for i in 3:
				var turn = Basis(Vector3.UP,float(i)*PI/3)*Basis(Vector3.RIGHT,PI/2+.4*i)
				shape("ring",frame*Transform3D(turn.scaled(Vector3.ONE*.28),Vector3(.19,.35,-.04)),BRASS,"metal")
			cylinder(frame,Vector3(.19,.06,-.04),Vector3(.12,.12,.12),WOOD)
		"kiln":
			box(frame,Vector3(-.13,.12,0),Vector3(.33,.24,.23),IRON,"metal")
			box(frame,Vector3(-.13,.26,0),Vector3(.7,.12,.3),Color("767c7e"),"metal")
			bar(frame,Vector3(.3,.04,-.22),Vector3(.44,.04,.27),.07,WOOD)
			box(frame,Vector3(.31,.065,-.25),Vector3(.24,.13,.16),IRON,"metal")
		"belfry":
			box(frame,Vector3(0,.02,0),Vector3(.8,.035,.55),Color("597b81"),"cloth")
			gear(frame*Transform3D(Basis(Vector3.RIGHT,-PI/2),Vector3.ZERO),Vector3(-.18,-.04,.08),.22,BRASS,10)
			gear(frame*Transform3D(Basis(Vector3.RIGHT,-PI/2),Vector3.ZERO),Vector3(.25,.13,.07),.15,Color("889493"),8)
			jar(frame,Vector3(.27,.0,-.22),.09,.2,Color("725642"))
		"hearth":
			box(frame,Vector3(0,.025,0),Vector3(.85,.05,.6),WOOD)
			jar(frame,Vector3(-.2,.05,-.04),.18,.31,Color("8d6c52"))
			for i in 2:
				cylinder(frame,Vector3(.15+i*.18,.11,.15-i*.24),Vector3(.09,.12,.09),Color("c9b687"))
				ring(frame,Vector3(.23+i*.18,.12,.15-i*.24),Vector3(.06,.06,.06),Color("c9b687"))
			sphere(frame,Vector3(.18,.11,-.19),Vector3(.2,.08,.11),Color("ae8957"))
	if variant == 2: box(frame,Vector3(-.38,.025,.29),Vector3(.18,.04,.08),LINEN)

func floor_scene(theme: String, frame: Transform3D, variant: int) -> void:
	match theme:
		"cellar":
			for i in 4: shape("ring",frame*Transform3D(Basis.from_scale(Vector3(.1,.025,.065)),Vector3(-.3+i*.17,.025,0)),IRON,"metal")
		"cistern":
			for i in 3: box(frame,Vector3(-.25+i*.24,.022,(i%2)*.18),Vector3(.35,.045,.13),STONE.darkened(.25),"matte",.08*i)
		"halls":
			for i in 4: sphere(frame,Vector3(-.3+i*.18,.025,.12*(i%2)),Vector3(.13,.035,.09),Color("76915b"))
		"crypt":
			for i in 3: cylinder(frame,Vector3(-.2+i*.22,.025,.1*(i%2)),Vector3(.09,.045,.09),LINEN.darkened(.12))
		"archive":
			for i in 3: box(frame,Vector3(-.19+i*.16,.008+i*.004,.1*(i%2)),Vector3(.3,.009,.23),LINEN,"cloth",.13*i)
		"kiln":
			for i in 4: box(frame,Vector3(-.3+i*.2,.02,.12*(i%2)),Vector3(.13,.04,.08),IRON,"metal",.26*i)
		"belfry":
			for i in 3: box(frame,Vector3(-.22+i*.23,.026,.13*(i%2)),Vector3(.1,.05,.1),Color("8a7a58"),"metal",.4*i)
		"hearth":
			for i in 3: bar(frame,Vector3(-.3,.02,-.13+i*.13),Vector3(.2,.02,-.07+i*.13),.025,WOOD)

func candle(frame: Transform3D, at: Vector3, height: float) -> void:
	if not probe_only: flame_sources.append(frame*(at+Vector3.UP*(height+.045)))
	cylinder(frame,at+Vector3.UP*height/2,Vector3(.065,height,.065),LINEN)
	sphere(frame,at+Vector3.UP*(height+.045),Vector3(.035,.065,.035),Color("ffc679"),"ember")

func jar(frame: Transform3D, at: Vector3, radius: float, height: float, color: Color) -> void:
	cylinder(frame,at+Vector3.UP*height*.42,Vector3(radius,height*.75,radius),color)
	cylinder(frame,at+Vector3.UP*height*.87,Vector3(radius*.55,height*.25,radius*.55),color)

func bucket(frame: Transform3D, at: Vector3, radius: float, color: Color) -> void:
	cylinder(frame,at+Vector3.UP*radius,Vector3(radius,radius*1.8,radius),color,"metal")
	shape("ring",frame*Transform3D(Basis.from_scale(Vector3(radius,.035,radius)),at+Vector3.UP*radius*1.9),BRASS,"metal")

func wheel(frame: Transform3D, at: Vector3, radius: float, color: Color, spokes: int) -> void:
	ring(frame,at,Vector3(radius,radius,.05),color,"metal")
	cylinder(frame,at,Vector3(.11,.08,.11),color,"metal",PI/2)
	for i in spokes:
		var angle = TAU*i/spokes
		bar(frame,at,at+Vector3(cos(angle),sin(angle),0)*radius*.87,.055,color,"metal")

func gear(frame: Transform3D, at: Vector3, radius: float, color: Color, teeth: int) -> void:
	wheel(frame,at,radius*.83,color,6)
	for i in teeth:
		var a = TAU*i/teeth
		box(frame,at+Vector3(cos(a),sin(a),0)*radius,Vector3(radius*.26,radius*.19,.065),color,"metal",a)

func box(frame: Transform3D, at: Vector3, size: Vector3, color: Color, finish := "matte", turn := 0.0) -> void:
	shape("box",frame*Transform3D(Basis(Vector3.BACK,turn).scaled(size),at),color,finish)

func cylinder(frame: Transform3D, at: Vector3, size: Vector3, color: Color, finish := "matte", tilt := 0.0) -> void:
	shape("cylinder",frame*Transform3D(Basis(Vector3.RIGHT,tilt)*Basis.from_scale(size),at),color,finish)

func sphere(frame: Transform3D, at: Vector3, size: Vector3, color: Color, finish := "matte") -> void:
	shape("sphere",frame*Transform3D(Basis.from_scale(size),at),color,finish)

func ring(frame: Transform3D, at: Vector3, size: Vector3, color: Color, finish := "metal", tilt := 0.0) -> void:
	shape("ring",frame*Transform3D(Basis(Vector3.UP,tilt)*Basis(Vector3.RIGHT,PI/2)*Basis.from_scale(Vector3(size.x,size.z,size.y)),at),color,finish)

func bar(frame: Transform3D, a: Vector3, b: Vector3, width: float, color: Color, finish := "matte") -> void:
	var along = (b-a).normalized()
	var side = along.cross(Vector3.FORWARD).normalized()
	if side.length_squared() < .01: side = along.cross(Vector3.RIGHT).normalized()
	var back = side.cross(along).normalized()
	shape("box",frame*Transform3D(Basis(side*width,along*a.distance_to(b),back*width),(a+b)/2),color,finish)

static func arrays(kind: String) -> Array:
	if primitive_arrays.has(kind): return primitive_arrays[kind]
	var mesh: PrimitiveMesh
	match kind:
		"box":
			mesh = BoxMesh.new()
			mesh.size = Vector3.ONE
		"cylinder":
			mesh = CylinderMesh.new()
			mesh.radial_segments = 8
			mesh.top_radius = 1
			mesh.bottom_radius = 1
			mesh.height = 1
		"sphere":
			mesh = SphereMesh.new()
			mesh.radius = 1
			mesh.height = 2
			mesh.radial_segments = 8
			mesh.rings = 3
		"ring":
			mesh = TorusMesh.new()
			mesh.inner_radius = .73
			mesh.outer_radius = 1.0
			mesh.rings = 12
			mesh.ring_segments = 3
	var result = mesh.get_mesh_arrays()
	primitive_arrays[kind] = result
	return result

func shape(kind: String, transform: Transform3D, color: Color, finish: String) -> void:
	var source = arrays(kind)
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	var count = indices.size() if not indices.is_empty() else vertices.size()
	if probe_only:
		vertex_count += count
		piece_count += 1
		return
	if vertex_count + count > limit: return
	if not groups.has(finish): groups[finish] = Batch.new()
	var batch: Batch = groups[finish]
	var base := batch.vertices.size()
	var normal_basis = transform.basis.inverse().transposed()
	batch.vertices.append_array(transform * vertices)
	for normal in normals: batch.normals.append((normal_basis * normal).normalized())
	var tint := PackedColorArray()
	tint.resize(vertices.size())
	tint.fill(color)
	batch.colors.append_array(tint)
	if indices.is_empty():
		for index in vertices.size(): batch.indices.append(base + index)
	else:
		for index in indices: batch.indices.append(base + index)
	vertex_count += count
	piece_count += 1

func finish(room) -> void:
	for key in groups:
		var node = MeshInstance3D.new()
		node.name = "Interior_" + report.theme + "_" + key
		node.mesh = groups[key].commit()
		if not finishes.has(key):
			var material = StandardMaterial3D.new()
			material.vertex_color_use_as_albedo = true
			material.albedo_color = Color(1.08,1.08,1.08)
			material.albedo_texture = DungeonTextures.aging()
			material.uv1_triplanar = true
			material.uv1_world_triplanar = true
			material.uv1_scale = Vector3.ONE * .6
			material.roughness = .85
			if key == "metal":
				material.metallic = .5
				material.roughness = .48
			elif key == "ember":
				material.emission_enabled = true
				material.emission = Color("ffd6a1")
				material.emission_energy_multiplier = .24
			finishes[key] = material
		node.material_override = finishes[key]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		room.add_child(node)
