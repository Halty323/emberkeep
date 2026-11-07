class_name DetailBatch
extends RefCounted
## Collects small repeated boxes (book spines, bottles, planks) and builds a
## single MultiMesh per room cell with per-instance colours on one shared
## material, instead of a node and draw call per detail.
static var shared_material: StandardMaterial3D
var chunks: Dictionary = {}
# The prop the details being added belong to ("" for none), and once built,
# where each prop's details ended up: {prop id: [[MultiMesh, index], ...]},
# so a broken prop's bands and lids go with it.
var owner := ""
var owned: Dictionary = {}

func add(cell: Vector2i, transform: Transform3D, color: Color) -> void:
	if not chunks.has(cell):
		chunks[cell] = {"transforms": [], "colors": [], "owners": []}
	chunks[cell].transforms.append(transform)
	chunks[cell].colors.append(color)
	chunks[cell].owners.append(owner)

func count() -> int:
	var total = 0
	for chunk in chunks.values(): total += chunk.transforms.size()
	return total

static func material() -> StandardMaterial3D:
	if shared_material == null:
		shared_material = StandardMaterial3D.new()
		shared_material.vertex_color_use_as_albedo = true
		shared_material.roughness = .86
	return shared_material

func build(parent: Node3D) -> Array:
	var meshes: Array = []
	for cell in chunks:
		var chunk: Dictionary = chunks[cell]
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = Geo.shared_box(Vector3.ONE)
		mm.instance_count = chunk.transforms.size()
		for i in chunk.transforms.size():
			mm.set_instance_transform(i, chunk.transforms[i])
			mm.set_instance_color(i, chunk.colors[i])
			var prop: String = chunk.owners[i]
			if prop != "":
				if not owned.has(prop): owned[prop] = []
				owned[prop].append([mm, i])
		var instance = MultiMeshInstance3D.new()
		instance.multimesh = mm
		instance.material_override = material()
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(instance)
		meshes.append(instance)
	return meshes

## Hides every detail a prop owned (its instances shrink to nothing).
func hide_owned(prop: String) -> void:
	for slot in owned.get(prop, []):
		var mm: MultiMesh = slot[0]
		mm.set_instance_transform(int(slot[1]), Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	owned.erase(prop)
