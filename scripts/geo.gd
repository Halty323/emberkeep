class_name Geo
extends RefCounted
static var materials: Dictionary = {}
# Identical primitives share one mesh resource; nothing mutates a mesh after
# creation (cutaways scale nodes), so sharing is safe and saves uploads.
static var meshes: Dictionary = {}

static func material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var key = str(color) + str(emission)
	if materials.has(key):
		return materials[key]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = .86
	if emission > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	materials[key] = mat
	return mat

static func shared_box(size: Vector3) -> BoxMesh:
	var key = "box" + str(size)
	if not meshes.has(key):
		var mesh = BoxMesh.new()
		mesh.size = size
		meshes[key] = mesh
	return meshes[key]

static func box(parent: Node3D, position: Vector3, size: Vector3, color: Color, emission := 0.0) -> MeshInstance3D:
	return add_mesh(parent, shared_box(size), position, color, emission)

static func sphere(parent: Node3D, position: Vector3, radius: float, color: Color, emission := 0.0) -> MeshInstance3D:
	var key = "sphere%.4f" % radius
	if not meshes.has(key):
		var mesh = SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2
		mesh.radial_segments = 12
		mesh.rings = 6
		meshes[key] = mesh
	return add_mesh(parent, meshes[key], position, color, emission)

static func cylinder(parent: Node3D, position: Vector3, radius: float, height: float, color: Color, emission := 0.0, top := -1.0) -> MeshInstance3D:
	var key = "cylinder%.4f/%.4f/%.4f" % [radius, height, top]
	if not meshes.has(key):
		var mesh = CylinderMesh.new()
		mesh.top_radius = radius if top < 0 else top
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 12
		meshes[key] = mesh
	return add_mesh(parent, meshes[key], position, color, emission)

static func ring(parent: Node3D, position: Vector3, radius: float, color: Color, thickness := .035) -> MeshInstance3D:
	var mesh = TorusMesh.new()
	mesh.inner_radius = radius - thickness
	mesh.outer_radius = radius + thickness
	mesh.rings = 24
	mesh.ring_segments = 6
	return add_mesh(parent, mesh, position, color, .5)

static func add_mesh(parent: Node3D, mesh: Mesh, position: Vector3, color: Color, emission := 0.0) -> MeshInstance3D:
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material(color, emission)
	# Sparks, rings and luminous glass do not need costly shadow caster passes.
	if emission > 0:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	instance.position = position
	return instance

static func halo(parent: Node3D, position: Vector3, size: float, color: Color) -> MeshInstance3D:
	var mesh = PlaneMesh.new()
	mesh.size = Vector2.ONE * size
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/halo.gdshader")
	mat.set_shader_parameter("tint", color)
	instance.material_override = mat
	# Keep unlit effects out of the GLES3 per-light/shadow rendering passes.
	instance.layers = 2
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	instance.position = position
	return instance

static func light(parent: Node3D, position: Vector3, color: Color, energy: float, reach: float, shadows := false) -> OmniLight3D:
	var light = OmniLight3D.new()
	light.light_color = color
	light.light_cull_mask = 1
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.2
	light.shadow_enabled = shadows
	parent.add_child(light)
	light.position = position
	return light

static func collider(parent: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	parent.add_child(body)
	body.position = position
	return body
