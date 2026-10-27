class_name Geo
extends RefCounted
static var materials: Dictionary = {}
## Floor footprint of the room being shown, as cell rectangles (x0, z0, x1, z1).
## Glows clip to this mask so they never spill into the void of an L-shaped room.
static var footprint := PackedVector4Array([Vector4(-9, -7, 9, 7), Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])

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

static func box(parent: Node3D, position: Vector3, size: Vector3, color: Color, emission := 0.0) -> MeshInstance3D:
	var mesh = BoxMesh.new()
	mesh.size = size
	return add_mesh(parent, mesh, position, color, emission)

static func sphere(parent: Node3D, position: Vector3, radius: float, color: Color, emission := 0.0) -> MeshInstance3D:
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 12
	mesh.rings = 6
	return add_mesh(parent, mesh, position, color, emission)

static func cylinder(parent: Node3D, position: Vector3, radius: float, height: float, color: Color, emission := 0.0) -> MeshInstance3D:
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	return add_mesh(parent, mesh, position, color, emission)

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
	mat.set_shader_parameter("room_cells", footprint)
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
