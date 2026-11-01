class_name FirstPersonWeaponView
extends RefCounted
## A compact iron ember-caster with a weathered stock and restrained brass.
## Two cached static surfaces plus the changing pigment accent: no extra
## lights, shadows or nodes when the selected weapon changes.
static var parts: Dictionary = {}
const IRON := Color("283239")
const EDGE := Color("535e62")
const BRASS := Color("8e7954")

static func populate(parent: Node3D) -> void:
	if parts.is_empty(): build_parts()
	var stock = MeshInstance3D.new()
	stock.mesh = parts.wood
	stock.material_override = DungeonStyle.wood_material(Color("453d35"), true)
	parent.add_child(stock)
	var receiver = MeshInstance3D.new()
	receiver.mesh = parts.metal
	receiver.material_override = parts.finish
	parent.add_child(receiver)
	Geo.box(parent, Vector3(.23,-.105,-.72), Vector3(.027,.026,.038),Color("ffd395"),.3)
	for mesh in parent.get_children(): mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func build_parts() -> void:
	var wood = SurfaceTool.new()
	var metal = SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	metal.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Rounded foregrip and sloping pistol grip remain within the old view rig.
	box(wood,Vector3(.23,-.255,-.44),Vector3(.118,.115,.245),-.025)
	box(wood,Vector3(.23,-.325,-.30),Vector3(.084,.175,.103),-.22)
	box(wood,Vector3(.23,-.255,-.275),Vector3(.103,.105,.10),-.08)
	# Slender beveled receiver, darker than the wood so light catches the
	# milled edges. Brass is confined to a sight rail, collar and small rivets.
	box(metal,Vector3(.23,-.18,-.45),Vector3(.129,.09,.265),0,IRON)
	box(metal,Vector3(.23,-.13,-.465),Vector3(.10,.025,.23),0,EDGE)
	box(metal,Vector3(.23,-.109,-.47),Vector3(.014,.016,.205),0,BRASS)
	box(metal,Vector3(.23,-.245,-.27),Vector3(.11,.026,.108),-.08,IRON)
	box(metal,Vector3(.23,-.394,-.282),Vector3(.089,.025,.106),-.22,IRON)
	cylinder(metal,Vector3(.23,-.168,-.64),.043,.255,IRON,Basis(Vector3.RIGHT,PI/2))
	for z in [-.55,-.735]:
		ring(metal,Vector3(.23,-.168,z),.043,.057,BRASS,Basis(Vector3.RIGHT,PI/2))
	for side in [-1,1]:
		box(metal,Vector3(.23+side*.047,-.168,-.635),Vector3(.012,.044,.155),0,IRON)
		for z in [-.38,-.48]:
			cylinder(metal,Vector3(.23+side*.068,-.18,z),.009,.008,BRASS,Basis(Vector3.FORWARD,PI/2))
	# A small open trigger guard replaces another solid block silhouette.
	ring(metal,Vector3(.23,-.30,-.385),.029,.036,IRON,Basis(Vector3.FORWARD,PI/2).scaled(Vector3(1,1,1.35)))
	var finish = StandardMaterial3D.new()
	finish.albedo_color = Color.WHITE
	finish.vertex_color_use_as_albedo = true
	finish.vertex_color_is_srgb = true
	finish.metallic = .78
	finish.roughness = .43
	parts = {"wood": wood.commit(), "metal": metal.commit(), "finish": finish}

static func cylinder(tool: SurfaceTool, at: Vector3, radius: float, length_value: float, color: Color, basis: Basis) -> void:
	var mesh = CylinderMesh.new()
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length_value
	append(tool,mesh,Transform3D(basis,at),color)

static func ring(tool: SurfaceTool, at: Vector3, inner: float, outer: float, color: Color, basis: Basis) -> void:
	var mesh = TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 16
	mesh.ring_segments = 6
	append(tool,mesh,Transform3D(basis,at),color)

static func append(tool: SurfaceTool, mesh: PrimitiveMesh, frame: Transform3D, color: Color) -> void:
	var arrays = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_frame = frame.basis.inverse().transposed()
	for i in indices:
		tool.set_color(color)
		tool.set_normal((normal_frame*normals[i]).normalized())
		tool.set_uv(uvs[i])
		tool.add_vertex(frame*vertices[i])

## A 26-face bevel gives the small body readable grazing highlights. Parts
## are merged once, so the finished caster still has exactly three surfaces.
static func box(tool: SurfaceTool, at: Vector3, size: Vector3, tilt := 0.0, color := Color.WHITE) -> void:
	var frame = Transform3D(Basis(Vector3.RIGHT,tilt),at)
	var bevel = minf(.009,minf(size.x,minf(size.y,size.z))*.13)
	var half = size*.5
	var core = half-Vector3.ONE*bevel
	for axis in 3:
		var a = (axis+1)%3
		var b = (axis+2)%3
		for sign_value in [-1,1]:
			var normal = Vector3.ZERO
			normal[axis] = sign_value
			var points: Array[Vector3] = []
			for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
				var p = Vector3.ZERO
				p[axis] = sign_value*half[axis]
				p[a] = corner.x*core[a]
				p[b] = corner.y*core[b]
				points.append(p)
			face(tool,points,normal,frame,color)
	for axis in 3:
		var a = (axis+1)%3
		var b = (axis+2)%3
		for sa in [-1,1]:
			for sb in [-1,1]:
				var points: Array[Vector3] = []
				for corner in [Vector2(-1,0),Vector2(1,0),Vector2(1,1),Vector2(-1,1)]:
					var p = core
					p[axis] = corner.x*core[axis]
					p[a] = sa*(half[a] if corner.y==0 else core[a])
					p[b] = sb*(core[b] if corner.y==0 else half[b])
					points.append(p)
				var normal = Vector3.ZERO
				normal[a] = sa
				normal[b] = sb
				face(tool,points,normal.normalized(),frame,color)
	for sx in [-1,1]:
		for sy in [-1,1]:
			for sz in [-1,1]:
				var corner = Vector3(sx,sy,sz)
				var points: Array[Vector3] = []
				for axis in 3:
					var p = core*corner
					p[axis] = half[axis]*corner[axis]
					points.append(p)
				face(tool,points,corner.normalized(),frame,color)

static func face(tool: SurfaceTool, points: Array[Vector3], normal: Vector3, frame: Transform3D, color: Color) -> void:
	if (points[1]-points[0]).cross(points[2]-points[0]).dot(normal)>0: points.reverse()
	var indices = [0,1,2,0,2,3] if points.size()==4 else [0,1,2]
	for i in indices:
		tool.set_color(color)
		tool.set_normal(frame.basis*normal)
		tool.set_uv(Vector2(points[i].x+points[i].z,points[i].y))
		tool.add_vertex(frame*points[i])
