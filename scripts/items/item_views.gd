class_name ItemViews
extends RefCounted
## Procedural placeholder views for chests and dropped active items.

static func chest(parent: Node3D, record: Dictionary) -> Node3D:
	var node = Node3D.new()
	parent.add_child(node)
	node.position = Vector3(float(record.position[0]), 0, float(record.position[1]))
	Geo.box(node, Vector3(0, .3, 0), Vector3(1.0, .55, .66), Color("6a4b33"))
	for x in [-.42, .42]:
		Geo.box(node, Vector3(x, .3, 0), Vector3(.08, .58, .7), Color("a2814f"))
	var lid = Node3D.new()
	lid.name = "Lid"
	node.add_child(lid)
	lid.position = Vector3(0, .58, -.33)
	Geo.box(lid, Vector3(0, .1, .33), Vector3(1.04, .2, .7), Color("7a5639"))
	if record.locked:
		var plate = Geo.box(node, Vector3(0, .42, .35), Vector3(.18, .2, .04), Color("d7b46d"), .35)
		plate.name = "Lock"
	Geo.collider(node, Vector3(0, .5, 0), Vector3(1.0, 1.0, .66))
	Geo.halo(node, Vector3(0, .03, 0), 2.4, Color(1, .7, .3, .14))
	if record.opened:
		set_open(node)
	return node

static func set_open(node: Node3D) -> void:
	node.get_node("Lid").rotation_degrees.x = -110
	var lock = node.get_node_or_null("Lock")
	if lock: lock.visible = false

static func item(parent: Node3D, record: Dictionary) -> Node3D:
	var definition = Content.record("actives", record.def)
	var node = Node3D.new()
	parent.add_child(node)
	node.position = Vector3(float(record.position[0]), 0, float(record.position[1]))
	Geo.cylinder(node, Vector3(0, .12, 0), .38, .24, Color("5d5a4c"))
	var orb = Geo.sphere(node, Vector3(0, .62, 0), .24, Color(definition.color), .9)
	orb.name = "Orb"
	Geo.ring(node, Vector3(0, .26, 0), .42, Color(definition.color), .025)
	Geo.halo(node, Vector3(0, .03, 0), 2.6, Color(Color(definition.color), .22))
	return node
