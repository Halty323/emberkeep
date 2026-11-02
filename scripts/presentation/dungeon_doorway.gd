class_name DungeonDoorway
extends RefCounted
## Hinged doors frame a real walkable connector. A short, opaque preview of
## the same corridor remains behind each idle doorway; the full connector
## takes over before the player crosses the threshold.
const WIDTH := 2.5
const HEIGHT := 3.05
static var finishes: Dictionary = {}
static var pending: Dictionary = {}

static func stone(tint: Color, bounced := false, family := "masonry") -> StandardMaterial3D:
	if family in DungeonPBR.THEMES:
		DungeonStyle.prepare_theme(family)
		for old in finishes.keys():
			if finishes[old].has_meta("surface_theme") and finishes[old].get_meta("surface_theme")!=family: finishes.erase(old)
	var key: String = family + tint.to_html() + str(bounced) + str(DungeonPBR.resolution())
	if finishes.has(key): return finishes[key]
	var maps: Dictionary = DungeonPBR.theme_maps(family) if family in DungeonPBR.THEMES else DungeonPBR.maps(family)
	var material := StandardMaterial3D.new()
	if family in DungeonPBR.THEMES: material.set_meta("surface_theme",family)
	material.albedo_color = tint.lightened(.5)
	material.albedo_texture = maps.paint
	material.normal_enabled = true
	material.normal_texture = maps.normal
	material.normal_scale = .55
	material.roughness_texture = maps.orm
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	material.roughness = .92
	material.ao_enabled = true
	material.ao_texture = maps.orm
	material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3(.4,.8,.4)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# A very low bounced-light floor keeps the connector legible when the
	# nearest real fixture has gone out. This is textured, not a glowing panel.
	if bounced:
		material.emission_enabled = true
		material.emission = Color("e7bc83")
		material.emission_energy_multiplier = .13 if family == "wood" else .045
		material.emission_texture = maps.paint
	finishes[key] = material
	return material

static func box(parent: Node3D, at: Vector3, dimensions: Vector3, material: Material) -> void:
	var key: String = str(parent.get_instance_id())+":"+str(material.get_instance_id())
	if not pending.has(key):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		pending[key] = {"parent":parent,"material":material,"tool":tool}
	var tool: SurfaceTool = pending[key].tool
	tool.append_from(Geo.shared_box(Vector3.ONE),0,Transform3D(Basis.IDENTITY.scaled(dimensions),at))

static func flush() -> void:
	for record in pending.values():
		var mesh := MeshInstance3D.new()
		mesh.mesh = record.tool.commit()
		mesh.material_override = record.material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		record.parent.add_child(mesh)
	pending.clear()

static func build(room, socket: Dictionary) -> Node3D:
	pending.clear()
	var direction: Vector2i = socket.dir
	var point: Vector2 = RoomGeometry.socket_point(socket.cell,direction) + Vector2(direction)*.15
	var gate := Node3D.new()
	gate.name = "StoneDoorway"
	room.add_child(gate)
	gate.position = Vector3(point.x,0,point.y)
	gate.rotation.y = atan2(float(direction.x),float(direction.y))
	gate.set_meta("portal",socket.portal)
	gate.set_meta("physical_doorway",true)
	var stone_finish := stone(Color(room.look.get("wall","666456")),false,DungeonStyle.theme_for(room.look))
	var wood := stone(Color("665240"),true,"wood")
	var frame_finish:=wood if room.look.get("materials",{}).get("structure","")=="wood" else stone_finish
	var iron := Geo.material(Color("394047"))
	var brass := Geo.material(Color("98805b"))
	# Thick jambs, a broad lintel and a recessed arch make the opening read as
	# a passage through the wall, instead of an emissive rectangular boundary.
	for side in [-1,1]:
		box(gate,Vector3(side*1.18,1.54,.06),Vector3(.34,3.08,.66),frame_finish)
		box(gate,Vector3(side*1.18,.16,.02),Vector3(.49,.3,.79),frame_finish)
		box(gate,Vector3(side*1.18,2.72,.02),Vector3(.48,.18,.78),frame_finish)
	box(gate,Vector3(0,3.05,.06),Vector3(2.72,.38,.69),frame_finish)
	var roof: float=room.ceiling_height()
	var upper_at:=Vector3(0,(3.15+roof)*.5,.06)
	var upper_size:=Vector3(2.5,roof-3.15,.46)
	box(gate,upper_at,upper_size,stone_finish)
	Geo.collider(gate,upper_at,upper_size)
	var barrier := Node3D.new()
	barrier.name = "Barrier"
	gate.add_child(barrier)
	var outline := Node3D.new()
	outline.name = "Outline"
	gate.add_child(outline)
	# Existing callers use Barrier/Outline visibility for entry resealing.
	# Their children are real closed/open door poses, not light strips.
	for side in [-1,1]:
		door_leaf(barrier,side,false,wood,iron,brass)
		door_leaf(outline,side,true,wood,iron,brass)
	Geo.collider(barrier,Vector3(0,1.45,0),Vector3(2.05,2.9,.18))
	flush()
	var path: Array[Vector2]=[]
	if Run.portals.has(socket.portal):
		var portal: Dictionary=Run.portals[socket.portal]
		path=CorridorPlan.from_room(CorridorPlan.ensure(portal,Run.rooms),portal,room.data.id)
	else:
		var start:=RoomGeometry.socket_point(socket.cell,direction)
		var n:=Vector2(direction)
		path=[start,start+n*CorridorPlan.LEAD,start+n*CorridorPlan.LEAD+Vector2(-n.y,n.x)*CorridorPlan.OFFSET]
	var preview:=WalkableCorridor.new()
	preview.name="Connector"
	gate.add_child(preview)
	preview.transform=gate.transform.affine_inverse()
	var first: Array[Vector2]=[path[0],path[1],path[2]]
	preview.build(first,true,room.look)
	return gate

static func door_leaf(parent: Node3D, side: int, opened: bool, wood: Material, iron: Material, brass: Material) -> void:
	var hinge := Node3D.new()
	hinge.name = "LeftLeaf" if side<0 else "RightLeaf"
	parent.add_child(hinge)
	hinge.position = Vector3(side*1.0,0,.12)
	hinge.rotation.y = -side*1.43 if opened else 0.0
	for plank in 4:
		box(hinge,Vector3(-side*(.13+plank*.245),1.38,0),Vector3(.235,2.65,.13),wood)
	for y in [.35,1.38,2.4]:
		box(hinge,Vector3(-side*.5,y,-.083),Vector3(.99,.105,.045),iron)
		for rivet in [.16,.82]:
			box(hinge,Vector3(-side*rivet,y,-.115),Vector3(.045,.045,.025),brass)
	box(hinge,Vector3(-side*.83,1.3,-.14),Vector3(.07,.26,.09),brass)
