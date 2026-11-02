class_name ScreenAmbientOcclusion
extends MeshInstance3D
## A bounded depth-based contact-occlusion pass for Compatibility. Scene depth
## is sampled in view space; HUD/canvas layers draw afterwards and stay sharp.
## No scene-color copy, extra camera, reflection target or history buffer.
var surface: ShaderMaterial

static func create(camera: Camera3D) -> ScreenAmbientOcclusion:
	var pass_node = ScreenAmbientOcclusion.new()
	pass_node.name = "ScreenAmbientOcclusion"
	var quad = QuadMesh.new()
	quad.size = Vector2(2,2)
	pass_node.mesh = quad
	pass_node.surface = ShaderMaterial.new()
	pass_node.surface.shader = preload("res://shaders/ambient_occlusion.gdshader")
	pass_node.surface.render_priority = -128
	pass_node.material_override = pass_node.surface
	pass_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pass_node.extra_cull_margin = 16384
	pass_node.ignore_occlusion_culling = true
	# The unlit effects layer is excluded from the water mirror.
	pass_node.layers = 2
	pass_node.position.z = -.5
	camera.add_child(pass_node)
	return pass_node

func configure(quality: String, enabled: bool) -> void:
	visible = enabled and quality != "off"
	var samples: Vector2i = RenderPolicy.current().get("ssao_samples",Vector2i(8,12))
	surface.set_shader_parameter("sample_count",samples.y if quality == "high" else samples.x)
	surface.set_shader_parameter("radius",1.15 if quality == "high" else .85)
	surface.set_shader_parameter("intensity",.7 if quality == "high" else .45)
