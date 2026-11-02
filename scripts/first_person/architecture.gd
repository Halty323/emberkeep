class_name FirstPersonArchitecture
extends RefCounted
## Dressed stone and timber share the dungeon's carved materials.
## Three mesh batches per room give supported eye-level silhouettes:
## no extra lights, shadow passes, alpha surfaces or gameplay colliders.
static func build(room) -> void:
	var parts := layout(room)
	var cap = Color(room.look.get("cap", "766e5b")).lerp(Color("a18d69"), .22)
	batch(room, "VaultRibs", parts.stone, DungeonStyle.wall_material(cap.darkened(.12)))
	batch(room, "DressedStone", parts.dressed, DungeonStyle.wall_material(cap.lightened(.07), true))
	batch(room, "CeilingCoffers", parts.timber, DungeonStyle.wood_material(Color("66523a")))

## Keep the authored transforms available before GPU upload. This is also
## usable by collision/architecture tools on a headless render server.
static func layout(room) -> Dictionary:
	var high:=LoftRoom.CEILING if room.data.get("fps_terrain",{}).get("version",0)==3 else 5.45
	var lift:=high-5.45
	var stone: Array[Transform3D] = []
	var dressed: Array[Transform3D] = []
	var timber: Array[Transform3D] = []
	for cell in room.geometry.cells:
		var center = RoomGeometry.cell_center(cell)
		var cuts: Array[Rect2]=[]
		for field in ["stairs","stairwell"]:
			if room.data.has(field):
				var point:=FloorGenerator.vec2(room.data[field])
				cuts.append(Rect2(point-Vector2.ONE*(Staircase.OUTER+.65),Vector2.ONE*(Staircase.OUTER+.65)*2))
		# Thick segmented ribs frame pools of lantern light. The arch starts
		# above every walkable head clearance and never narrows a doorway.
		# A cell boundary inside a larger room has no supporting wall. Never
		# hang half an arch in that opening. Only complete supported ribs remain.
		if arch_supported(room.geometry,cell):
			for depth in [-4.6, 0.0, 4.6]:
				var band:=Rect2(center+Vector2(-9,depth-.3),Vector2(18,.6))
				if cuts.any(func(cut): return cut.intersects(band)): continue
				arch(stone, Vector3(center.x, 3.3+lift, center.y + depth), 8.85, 1.97, 12, .29, .38)
				for side in [-1,1]:
					box(dressed,Vector3(center.x+side*8.88,3.29+lift,center.y+depth),Vector3(.65,.42,.58))
				box(dressed, Vector3(center.x, 5.32+lift, center.y + depth), Vector3(.5, .3, .49))
		# Ceiling coffers are real low-poly forms, rather than another screen
		# effect. The gaps and grain catch the existing warm local lights.
		for depth in [-5.8, -2.9, 0.0, 2.9, 5.8]:
			ceiling_beam(timber,Rect2(center+Vector2(-9,depth-.085),Vector2(18,.17)),cuts,lift)
		for across in [-5.4, 0.0, 5.4]:
			ceiling_beam(timber,Rect2(center+Vector2(across-.08,-7),Vector2(.16,14)),cuts,lift)

	for segment in room.geometry.wall_segments():
		if segment.to - segment.from < .4: continue
		var along = (segment.from + segment.to) * .5
		var length: float = segment.to - segment.from
		var at = Vector3(along, .23, segment.line) if segment.dir.x == 0 else Vector3(segment.line, .23, along)
		at -= Vector3(segment.dir.x, 0, segment.dir.y) * .025
		var yaw = 0.0 if segment.dir.x == 0 else PI / 2.0
		# Continuous skirting and an upper cornice ground the wall's large
		# flat faces. Their depth stays within the wall contact margin.
		box(dressed, at, Vector3(length, .28, .16), yaw)
		box(dressed, at + Vector3.UP * (4.58+lift), Vector3(length, .16, .13), yaw)
		var count = maxi(1, floori(length / 4.3))
		for column in count:
			var offset = (float(column) + .5) / count * length - length * .5
			var p = at + Vector3(offset, -.23, 0).rotated(Vector3.UP, yaw)
			# Wall mechanisms and memorials occupy authored niches. Leave the
			# supporting mouldings, but do not put a pilaster through their face.
			if niche_reserved(room, Vector2(p.x,p.z), segment.dir): continue
			box(stone, p + Vector3.UP * (2.51+lift*.5), Vector3(.28, 4.7+lift, .13), yaw)
			box(dressed, p + Vector3.UP * .38, Vector3(.49, .16, .19), yaw)
			box(dressed, p + Vector3.UP * 3.18, Vector3(.47, .2, .2), yaw)

	for socket in room.sockets.values():
		if socket.state not in ["open", "locked", "revealed"]: continue
		var point = RoomGeometry.socket_point(socket.cell, socket.dir)
		var inward = Vector3(-socket.dir.x, 0, -socket.dir.y)
		var base = Vector3(point.x, 0, point.y) + inward * .05
		var yaw = 0.0 if socket.dir.x == 0 else PI / 2.0
		for side in [-1.0, 1.0]:
			var p = base + Vector3(side * 1.23, 0, 0).rotated(Vector3.UP, yaw)
			box(stone, p + Vector3.UP * 1.45, Vector3(.33, 2.9, .21), yaw)
			box(dressed, p + Vector3.UP * .19, Vector3(.46, .34, .28), yaw)
			box(dressed, p + Vector3.UP * 2.84, Vector3(.45, .19, .27), yaw)
		# The ornamental arch sits above the physical lintel's opening, so
		# jumping cannot push the camera through a cosmetic low ceiling.
		arch(dressed, base + Vector3.UP * 3.01, 1.22, .69, 8, .22, .24, yaw)
		box(dressed, base + Vector3.UP * 3.73, Vector3(.3, .34, .3), yaw)

	return {"stone":stone,"dressed":dressed,"timber":timber}

static func box(transforms: Array[Transform3D], at: Vector3, size: Vector3, yaw := 0.0) -> void:
	transforms.append(Transform3D((Basis(Vector3.UP, yaw) * Basis.from_scale(size)), at))

static func arch_supported(geometry: RoomGeometry, cell: Vector2i) -> bool:
	return not geometry.cell_set.has(cell+Vector2i.LEFT) and not geometry.cell_set.has(cell+Vector2i.RIGHT)

static func ceiling_beam(transforms: Array[Transform3D], area: Rect2, cuts: Array[Rect2], lift := 0.0) -> void:
	var pieces: Array[Rect2]=[area]
	for cut in cuts: pieces=FirstPersonTerrain.subtract_rects(pieces,cut)
	for piece in pieces:
		var at:=piece.get_center()
		box(transforms,Vector3(at.x,5.39+lift,at.y),Vector3(piece.size.x,.18,piece.size.y))

static func arch(transforms: Array[Transform3D], at: Vector3, radius: float, rise: float, segments: int, thickness: float, depth: float, yaw := 0.0) -> void:
	var turn = Basis(Vector3.UP, yaw)
	for segment in segments:
		var a = PI * segment / segments
		var b = PI * (segment + 1) / segments
		var start = Vector3(cos(a) * radius, sin(a) * rise, 0)
		var end = Vector3(cos(b) * radius, sin(b) * rise, 0)
		var direction = end - start
		var basis = turn * Basis(Vector3.BACK, atan2(direction.y, direction.x)) * Basis.from_scale(Vector3(direction.length() + .045, thickness, depth))
		transforms.append(Transform3D(basis, at + turn * (start + end) / 2.0))

static func batch(room, label: String, transforms: Array[Transform3D], material: Material) -> void:
	if transforms.is_empty(): return
	var view = MultiMeshInstance3D.new()
	view.name = label
	var mesh = MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.mesh = Geo.shared_box(Vector3.ONE)
	mesh.instance_count = transforms.size()
	for i in transforms.size(): mesh.set_instance_transform(i, transforms[i])
	view.multimesh = mesh
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room.add_child(view)

static func niche_reserved(room, at: Vector2, direction: Vector2i) -> bool:
	for anchor in room.interiors_report.get("walls", []):
		if Vector2i(anchor.dir) == direction and anchor.at.distance_to(at) < 1.55: return true
	return false
