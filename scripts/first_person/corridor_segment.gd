class_name WalkableCorridor
extends Node3D
## Opaque floor/wall/ceiling union with matching static collision. Floor
## tiles never overlap. Two shared material batches keep a connector cheap.
const HEIGHT := 3.4
const WALL := .24
var path: Array[Vector2]=[]
var regions: Array[Rect2]=[]
var tools: Dictionary={}
var tile_count := 0
var wall_count := 0
var lamps: Array[OmniLight3D]=[]

func build(points: Array[Vector2], preview := false, look: Dictionary = {}) -> void:
	path=points.duplicate()
	regions=CorridorPlan.strips(path)
	var xs: Array[float]=[]
	var zs: Array[float]=[]
	for rect in regions:
		for x in [rect.position.x,rect.end.x]:
			if x not in xs: xs.append(x)
		for z in [rect.position.y,rect.end.y]:
			if z not in zs: zs.append(z)
	xs.sort();zs.sort()
	var occupied := {}
	for x in xs.size()-1:
		for z in zs.size()-1:
			var center := Vector2((xs[x]+xs[x+1])*.5,(zs[z]+zs[z+1])*.5)
			if regions.any(func(rect): return rect.has_point(center)): occupied[Vector2i(x,z)]=true
	var edges := {}
	var fog_tiles: Array[Rect2]=[]
	for tile in occupied:
		var rect := Rect2(xs[tile.x],zs[tile.y],xs[tile.x+1]-xs[tile.x],zs[tile.y+1]-zs[tile.y])
		var at := rect.get_center()
		append_box("floor",Vector3(at.x,-.08,at.y),Vector3(rect.size.x,.16,rect.size.y))
		append_box("stone",Vector3(at.x,HEIGHT+.08,at.y),Vector3(rect.size.x,.16,rect.size.y))
		fog_tiles.append(rect)
		tile_count+=1
		for normal in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if occupied.has(tile+normal): continue
			var mid := at+Vector2(normal)*rect.size*.5
			if aperture(mid,Vector2(normal),false) or (not preview and aperture(mid,Vector2(normal),true)): continue
			var line: float = mid.x if normal.x!=0 else mid.y
			var low: float = rect.position.y if normal.x!=0 else rect.position.x
			var high: float = rect.end.y if normal.x!=0 else rect.end.x
			var key := "%d:%d:%.4f" % [normal.x,normal.y,line]
			if not edges.has(key): edges[key]={"normal":Vector2(normal),"line":line,"spans":[]}
			edges[key].spans.append(Vector2(low,high))
	for edge in edges.values():
		edge.spans.sort_custom(func(a,b): return a.x<b.x)
		var merged: Array[Vector2]=[]
		for span in edge.spans:
			if not merged.is_empty() and absf(merged.back().y-span.x)<.001: merged[merged.size()-1].y=span.y
			else: merged.append(span)
		for span in merged:
			var center := Vector2(edge.line,(span.x+span.y)*.5) if edge.normal.x!=0 else Vector2((span.x+span.y)*.5,edge.line)
			center+=edge.normal*WALL*.5
			var size := Vector3(WALL,HEIGHT,span.y-span.x+WALL) if edge.normal.x!=0 else Vector3(span.y-span.x+WALL,HEIGHT,WALL)
			append_box("stone",Vector3(center.x,HEIGHT*.5,center.y),size)
			wall_count+=1
	for kind in tools:
		var mesh: ArrayMesh=tools[kind].commit()
		var view := MeshInstance3D.new()
		view.name="Corridor"+str(kind).capitalize()
		view.mesh=mesh
		view.material_override=DungeonStyle.corridor_material("flagstone" if kind=="floor" else "masonry",look)
		view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# An idle preview receives the room's existing fixture light. The full
		# connector has its own stable lights across the hidden room handoff.
		view.layers=1 if preview else Geo.CORRIDOR_LAYER
		add_child(view)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape=mesh.create_trimesh_shape()
		body.add_child(shape)
		add_child(body)
	if not preview: fixtures()
	# The rooms' fog runs on through the passages between them.
	if not preview and FloorMist.wanted() and not path.is_empty():
		FloorMist.cover(self,fog_tiles,func(_at: Vector2) -> float: return 0.0,{},Geo.CORRIDOR_LAYER,int(path[0].x*31.0+path[0].y*17.0))
	tools.clear()

func append_box(kind: String, at: Vector3, dimensions: Vector3) -> void:
	if not tools.has(kind):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[kind]=tool
	tools[kind].append_from(Geo.shared_box(Vector3.ONE),0,Transform3D(Basis.IDENTITY.scaled(dimensions),at))

func aperture(at: Vector2, normal: Vector2, at_end: bool) -> bool:
	var endpoint: Vector2=path.back() if at_end else path.front()
	var outward: Vector2=(path.back()-path[path.size()-2]).normalized() if at_end else (path.front()-path[1]).normalized()
	return normal.dot(outward)>.99 and absf((at-endpoint).dot(outward))<.01 and at.distance_to(endpoint)<CorridorPlan.WIDTH*.6

func contains_point(at: Vector2, margin := .0) -> bool:
	for offset in [Vector2.ZERO,Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(.707,.707),Vector2(-.707,.707),Vector2(.707,-.707),Vector2(-.707,-.707)]:
		var p: Vector2 = at+offset*margin
		if not regions.any(func(rect): return rect.has_point(p)): return false
	return true

func fixtures() -> void:
	var length := CorridorPlan.distance(path,0,path.size()-1)
	for fraction in [.25,.75]:
		var sample := CorridorPlan.sample(path,length*fraction)
		var tangent := Vector2(-sample.direction.y,sample.direction.x)
		var at: Vector2=sample.at+tangent*.98
		Geo.box(self,Vector3(at.x,1.66,at.y),Vector3(.21,.08,.21),Color("645947"))
		Geo.cylinder(self,Vector3(at.x,1.85,at.y),.065,.32,Color("bca582"))
		var flame := MeshInstance3D.new()
		flame.mesh=DungeonStyle.candle_flame_mesh()
		flame.material_override=DungeonStyle.candle_flame()
		flame.position=Vector3(at.x,2.10,at.y)
		flame.scale=Vector3.ONE*1.5
		flame.layers=Geo.FLAME_LAYER
		flame.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flame)
		var light := Geo.light(self,Vector3(at.x,2.08,at.y),Color("ffcf93"),.85,8.5)
		light.omni_attenuation=1.4
		light.light_cull_mask=Geo.CORRIDOR_LAYER|Geo.VIEW_LAYER
		lamps.append(light)
