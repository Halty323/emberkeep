class_name PaintingView
extends RefCounted
## A wall-mounted painting: a lit canvas quad inside a procedural frame with a
## brass plaque. The canvas keeps the work's full proportions within its
## mount. Without an imported reproduction it shows a covered canvas, never a
## generated stand-in for the artwork.
const CENTER_HEIGHT := 1.45
const FRAME := .12

static func build(room: Node3D, mount: Dictionary, painting: Dictionary, texture: Texture2D) -> Dictionary:
	var direction = Vector2i(int(mount.dir[0]), int(mount.dir[1]))
	var node = Node3D.new()
	node.name = "Painting_" + painting.id
	room.add_child(node)
	var face = Vector2(float(mount.position[0]), float(mount.position[1])) - Vector2(direction) * .06
	node.position = Vector3(face.x, CENTER_HEIGHT, face.y)
	node.rotation.y = -float(Furnisher.facing(-direction)) * PI / 2.0
	var size = PaintingLibrary.fit(float(painting.aspect), Vector2(float(mount.width), float(mount.height)) - Vector2.ONE * FRAME * 2)
	var gilt = Color("8a6a3c")
	for side in [-1, 1]:
		Geo.box(node, Vector3(0, side * (size.y / 2 + FRAME / 2), .02), Vector3(size.x + FRAME * 2, FRAME, .08), gilt)
		Geo.box(node, Vector3(side * (size.x / 2 + FRAME / 2), 0, .02), Vector3(FRAME, size.y, .08), gilt)
	Geo.box(node, Vector3(0, 0, -.01), Vector3(size.x + .02, size.y + .02, .02), Color("2e2a24"))
	var canvas = MeshInstance3D.new()
	canvas.name = "Canvas"
	var quad = QuadMesh.new()
	quad.size = size
	canvas.mesh = quad
	var surface = StandardMaterial3D.new()
	surface.roughness = .9
	if texture:
		surface.albedo_texture = texture
	else:
		surface.albedo_color = Color("5c5348")
	canvas.material_override = surface
	canvas.position = Vector3(0, 0, .015)
	canvas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(canvas)
	if not texture:
		# A loosely draped dust cloth, so an un-imported slot reads as covered.
		for i in 3:
			var fold = Geo.box(node, Vector3((i - 1) * size.x * .28, -size.y * .05, .03), Vector3(size.x * .08, size.y * .92, .015), Color("6b6155"))
			fold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plaque = Geo.box(node, Vector3(0, -size.y / 2 - FRAME - .14, .03), Vector3(minf(.6, size.x * .5), .12, .03), Color("b39258"), .2)
	plaque.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		if child is GeometryInstance3D: child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"node": node, "canvas": canvas, "size": size, "center": node.global_position if node.is_inside_tree() else node.position}
