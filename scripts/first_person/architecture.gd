class_name FirstPersonArchitecture
extends RefCounted
## Instanced arch ribs give eye-level rooms a vaulted silhouette while
## sharing one mesh/material and keeping the mobile draw budget bounded.
static func build(room) -> void:
	var transforms: Array[Transform3D] = []
	for cell in room.geometry.cells:
		var center = RoomGeometry.cell_center(cell)
		for depth in [-4.6, 0, 4.6]:
			for segment in 10:
				var a = PI * segment / 10.0
				var b = PI * (segment + 1) / 10.0
				var start = Vector3(center.x + cos(a) * 8.65, 3.25 + sin(a) * 2.05, center.y + depth)
				var end = Vector3(center.x + cos(b) * 8.65, 3.25 + sin(b) * 2.05, center.y + depth)
				var delta = end - start
				var basis = Basis(Vector3.BACK, atan2(delta.y, delta.x)).scaled(Vector3(delta.length() + .04, .16, .23))
				transforms.append(Transform3D(basis, (start + end) / 2))
	var ribs = MultiMeshInstance3D.new()
	ribs.name = "VaultRibs"
	var batch = MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = Geo.shared_box(Vector3.ONE)
	batch.instance_count = transforms.size()
	for i in transforms.size(): batch.set_instance_transform(i, transforms[i])
	ribs.multimesh = batch
	ribs.material_override = Geo.material(Color("71604b"))
	ribs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room.add_child(ribs)
