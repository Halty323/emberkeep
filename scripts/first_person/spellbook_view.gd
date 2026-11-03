class_name SpellbookView
extends RefCounted
## The little light's spellbook, open in its right hand at the bottom of the
## view: wooden boards, brass corners, cream pages written in the weapon's
## colour, and the forearm in its robe sleeve below. The book's own parts are
## merged once per material; every relic then adds its own mark to the book
## or the arm (SpellbookLooks).
## Children 0, 1 and 2 are the boards, the brass and the glowing accent, in
## that order, so lighting quality changes and weapon tints find them.
const PAGE := Color("c8b892")
const SKIN := Color("c69c82")
const SLEEVE := Color("3d3449")
const CUFF := Color("8f7a50")
const BRASS := Color("b39159")
const BOARD := Color("5b2f2a")
# The open book: X across the spread, Y out of the pages, Z down the page.
# Tilted so the pages face the eye and turned a little toward the centre.
static var frame := Transform3D(Basis.from_euler(Vector3(deg_to_rad(54), deg_to_rad(-14), deg_to_rad(-10))), Vector3(.2, -.16, -.52))
# The hand meets the book under the spine; the forearm runs back and down.
static var wrist := Vector3.ZERO
static var forearm := Vector3.ZERO
static var parts: Dictionary = {}
static var page_shader: Shader

static func populate(parent: Node3D) -> void:
	if parts.is_empty(): build_parts()
	var cover := add(parent, parts.cover, DungeonStyle.wood_material(BOARD, true), "Boards")
	var brass := add(parent, parts.brass, DungeonStyle.metal_material(Color.WHITE, true, true), "Brass")
	var accent := add(parent, parts.accent, Geo.material(Color("ffd395"), .3), "Accent")
	add(parent, parts.pages, page_material(), "Pages")
	var runes := add(parent, parts.runes, rune_material(Color("ffd395")), "Runes")
	add(parent, parts.skin, Geo.material(SKIN), "Hand")
	add(parent, parts.sleeve, Geo.material(SLEEVE), "Sleeve")
	add(parent, parts.cuff, Geo.material(CUFF), "Cuff")
	# Relic marks are rebuilt under this node whenever the inventory changes.
	var marks := Node3D.new()
	marks.name = "Marks"
	parent.add_child(marks)
	for node in [cover, brass, accent, runes]: node.set_meta("spellbook", true)

static func add(parent: Node3D, mesh: Mesh, material: Material, label: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

## The weapon's colour: the spine gem and the writing on the pages.
static func tint(parent: Node3D, color: Color) -> void:
	parent.get_child(2).material_override = Geo.material(color, .35)
	var runes: MeshInstance3D = parent.get_node_or_null("Runes")
	if runes: runes.material_override.set_shader_parameter("ink", color)

## The writing flares when a spell is cast; it settles over a moment.
static func glow(parent: Node3D, amount: float) -> void:
	var runes: MeshInstance3D = parent.get_node_or_null("Runes")
	if runes: runes.material_override.set_shader_parameter("flare", amount)

static func page_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PAGE
	mat.albedo_texture = DungeonTextures.aging()
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE * 3.0
	mat.roughness = .95
	return mat

static func rune_material(color: Color) -> ShaderMaterial:
	if page_shader == null: page_shader = preload("res://shaders/spell_page.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = page_shader
	mat.set_shader_parameter("ink", color)
	return mat

## A point in the book's frame, in the view rig's space.
static func on_book(point: Vector3) -> Vector3:
	return frame * point

static func build_parts() -> void:
	var tools := {}
	for key in ["cover", "brass", "accent", "pages", "runes", "skin", "sleeve", "cuff"]:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = tool
	# Each half of the spread lifts a little from the spine.
	for side: int in [-1, 1]:
		var half := frame * Transform3D(Basis(Vector3.BACK, side * deg_to_rad(-8)), Vector3(side * .004, 0, 0))
		box(tools.cover, half, Vector3(side * .086, -.004, 0), Vector3(.172, .011, .232))
		box(tools.pages, half, Vector3(side * .081, .014, 0), Vector3(.156, .026, .214))
		# The written page: a sheet just above the paper.
		quad(tools.runes, half, Vector3(side * .081, .0275, 0), Vector2(.142, .196), side > 0)
		# Brass caps on the outer corners, and a clasp tab on the fore-edge.
		for end: int in [-1, 1]:
			box(tools.brass, half, Vector3(side * .163, -.002, end * .107), Vector3(.024, .016, .024), BRASS)
		box(tools.brass, half, Vector3(side * .176, -.004, 0), Vector3(.016, .013, .046), BRASS.darkened(.2))
	# The spine, its bands and the gem set into its head.
	cylinder(tools.cover, frame * Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, -.012, 0)), .019, .232)
	for z: float in [-.08, .08]:
		ring(tools.brass, frame * Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, -.012, z)), .018, .024, BRASS)
	sphere(tools.accent, frame * Transform3D(Basis(), Vector3(0, -.006, -.121)), .016)
	# The hand: palm under the spine, fingers round the right board, thumb
	# on the left page.
	box(tools.skin, frame, Vector3(.02, -.04, .045), Vector3(.1, .032, .11))
	for i in 4:
		var z := -.042 + i * .028
		box(tools.skin, frame * Transform3D(Basis(Vector3.BACK, deg_to_rad(-8)), Vector3(0, 0, 0)), Vector3(.105, -.024, z), Vector3(.13, .022, .021))
		box(tools.skin, frame * Transform3D(Basis(Vector3.BACK, deg_to_rad(-8)), Vector3(0, 0, 0)), Vector3(.176, -.004, z), Vector3(.022, .034, .02))
	box(tools.skin, frame * Transform3D(Basis(Vector3.UP, deg_to_rad(28)), Vector3(-.035, .012, .075)), Vector3.ZERO, Vector3(.026, .022, .07))
	# The forearm leaves the frame toward the lower right.
	wrist = frame * Vector3(.03, -.05, .1)
	forearm = Vector3(.56, -.78, .26).normalized()
	limb(tools.skin, wrist, wrist + forearm * .12, .034, .038)
	limb(tools.sleeve, wrist + forearm * .07, wrist + forearm * .5, .058, .074)
	limb(tools.cuff, wrist + forearm * .062, wrist + forearm * .09, .064, .066)
	for key in tools:
		var tool: SurfaceTool = tools[key]
		tool.generate_tangents()
		parts[key] = tool.commit()

## A point along the forearm, `along` metres from the wrist.
static func on_arm(along: float) -> Vector3:
	return wrist + forearm * along

static func limb(tool: SurfaceTool, from: Vector3, to: Vector3, from_radius: float, to_radius: float, color := Color.WHITE) -> void:
	var axis := (to - from)
	var up := axis.normalized()
	var side := up.cross(Vector3.FORWARD).normalized()
	if side.length_squared() < .01: side = up.cross(Vector3.RIGHT).normalized()
	var basis := Basis(side, up, side.cross(up)).orthonormalized()
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 14
	mesh.rings = 1
	mesh.bottom_radius = from_radius
	mesh.top_radius = to_radius
	mesh.height = axis.length()
	append(tool, mesh, Transform3D(basis, (from + to) * .5), color)

static func cylinder(tool: SurfaceTool, at: Transform3D, radius: float, length_value: float, color := Color.WHITE) -> void:
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 14
	mesh.rings = 1
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length_value
	append(tool, mesh, at, color)

static func ring(tool: SurfaceTool, at: Transform3D, inner: float, outer: float, color := Color.WHITE) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 16
	mesh.ring_segments = 6
	append(tool, mesh, at, color)

static func sphere(tool: SurfaceTool, at: Transform3D, radius: float, color := Color.WHITE) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	append(tool, mesh, at, color)

static func box(tool: SurfaceTool, at: Transform3D, center: Vector3, size: Vector3, color := Color.WHITE) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	append(tool, mesh, at * Transform3D(Basis(), center), color)

static func quad(tool: SurfaceTool, at: Transform3D, center: Vector3, size: Vector2, right_page: bool) -> void:
	var corners := [Vector3(-.5, 0, -.5), Vector3(.5, 0, -.5), Vector3(.5, 0, .5), Vector3(-.5, 0, .5)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var normal := (at.basis * Vector3.UP).normalized()
	for i in [0, 1, 2, 0, 2, 3]:
		tool.set_normal(normal)
		# U is offset by half for the right page so one sheet holds both.
		tool.set_uv(Vector2(uvs[i].x * .5 + (.5 if right_page else 0.0), uvs[i].y))
		tool.set_color(Color.WHITE)
		tool.add_vertex(at * (center + Vector3(corners[i].x * size.x, 0, corners[i].z * size.y)))

static func append(tool: SurfaceTool, mesh: PrimitiveMesh, at: Transform3D, color: Color) -> void:
	var arrays := mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_basis := at.basis.inverse().transposed()
	for i in indices:
		tool.set_color(color)
		tool.set_normal((normal_basis * normals[i]).normalized())
		tool.set_uv(uvs[i])
		tool.add_vertex(at * vertices[i])
