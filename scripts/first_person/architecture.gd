class_name FirstPersonArchitecture
extends RefCounted
## Dressed stone and timber use the same small painted maps as the dungeon.
## Three mesh batches per room give eye-level silhouettes a PS2-era economy:
## no extra lights, shadow passes, alpha surfaces or gameplay colliders.
static func build(room) -> void:
	var stone: Array[Transform3D] = []
	var dressed: Array[Transform3D] = []
	var timber: Array[Transform3D] = []
	for cell in room.geometry.cells:
		var center = RoomGeometry.cell_center(cell)
		# Thick segmented ribs frame pools of lantern light. The arch starts
		# above every walkable head clearance and never narrows a doorway.
		for depth in [-4.6, 0.0, 4.6]:
			arch(stone, Vector3(center.x, 3.3, center.y + depth), 8.64, 1.97, 12, .25, .34)
			box(dressed, Vector3(center.x, 5.27, center.y + depth), Vector3(.5, .25, .49))
		# Ceiling coffers are real low-poly forms, rather than another screen
		# effect. The gaps and grain catch the existing warm local lights.
		for depth in [-5.8, -2.9, 0.0, 2.9, 5.8]:
			box(timber, Vector3(center.x, 5.36, center.y + depth), Vector3(17.5, .13, .17))
		for across in [-5.4, 0.0, 5.4]:
			box(timber, Vector3(center.x + across, 5.33, center.y), Vector3(.16, .18, 13.75))

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
		box(dressed, at + Vector3.UP * 4.58, Vector3(length, .16, .13), yaw)
		var count = maxi(1, floori(length / 4.3))
		for column in count:
			var offset = (float(column) + .5) / count * length - length * .5
			var p = at + Vector3(offset, -.23, 0).rotated(Vector3.UP, yaw)
			box(stone, p + Vector3.UP * 2.51, Vector3(.28, 4.7, .13), yaw)
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

	var cap = Color(room.look.get("cap", "766e5b")).lerp(Color("a18d69"), .22)
	batch(room, "VaultRibs", stone, DungeonStyle.wall_material(cap.darkened(.12)))
	batch(room, "DressedStone", dressed, DungeonStyle.wall_material(cap.lightened(.07), true))
	batch(room, "CeilingCoffers", timber, DungeonStyle.wood_material(Color("66523a")))

static func box(transforms: Array[Transform3D], at: Vector3, size: Vector3, yaw := 0.0) -> void:
	transforms.append(Transform3D((Basis(Vector3.UP, yaw) * Basis.from_scale(size)), at))

static func arch(transforms: Array[Transform3D], at: Vector3, radius: float, rise: float, segments: int, thickness: float, depth: float, yaw := 0.0) -> void:
	var turn = Basis(Vector3.UP, yaw)
	for segment in segments:
		var a = PI * segment / segments
		var b = PI * (segment + 1) / segments
		var start = Vector3(cos(a) * radius, sin(a) * rise, 0)
		var end = Vector3(cos(b) * radius, sin(b) * rise, 0)
		var direction = end - start
		var basis = turn * Basis(Vector3.BACK, atan2(direction.y, direction.x)) * Basis.from_scale(Vector3(direction.length() - .025, thickness, depth))
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
