class_name FirstPersonWeaponView
extends RefCounted
## A small faceted ember caster. Static parts merge into two draw surfaces;
## the third child is the weapon's changing pigment/muzzle accent.
static func populate(parent: Node3D) -> void:
	var wood = SurfaceTool.new()
	var metal = SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	metal.begin(Mesh.PRIMITIVE_TRIANGLES)
	box(wood, Vector3(.23,-.25,-.42), Vector3(.135,.17,.29))
	box(wood, Vector3(.23,-.32,-.32), Vector3(.09,.18,.12), -.22)
	box(metal, Vector3(.23,-.18,-.49), Vector3(.15,.13,.28))
	box(metal, Vector3(.23,-.115,-.49), Vector3(.03,.025,.27))
	var barrel = CylinderMesh.new()
	barrel.radial_segments = 8
	barrel.top_radius = .055
	barrel.bottom_radius = .055
	barrel.height = .29
	metal.append_from(barrel, 0, Transform3D(Basis(Vector3.RIGHT, PI/2),Vector3(.23,-.17,-.64)))
	for z in [-.53,-.70]:
		box(metal, Vector3(.23,-.17,z), Vector3(.14,.14,.045))
	for side in [-1,1]:
		box(metal, Vector3(.23 + side*.074,-.18,-.45), Vector3(.02,.07,.09))
	var stock = MeshInstance3D.new()
	stock.mesh = wood.commit()
	stock.material_override = DungeonStyle.wood_material(Color("745034"), true)
	parent.add_child(stock)
	var receiver = MeshInstance3D.new()
	receiver.mesh = metal.commit()
	var finish = StandardMaterial3D.new()
	finish.albedo_color = Color("8e7d59")
	finish.metallic = .65
	finish.roughness = .37
	receiver.material_override = finish
	parent.add_child(receiver)
	Geo.box(parent, Vector3(.23,-.105,-.72), Vector3(.045,.04,.05),Color("ffd395"),.3)
	for mesh in parent.get_children(): mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func box(tool: SurfaceTool, at: Vector3, size: Vector3, tilt := 0.0) -> void:
	tool.append_from(Geo.shared_box(Vector3.ONE),0,Transform3D(Basis(Vector3.RIGHT,tilt).scaled(size),at))
