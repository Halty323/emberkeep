class_name DungeonAtmosphere
extends RefCounted
## A small, static artistic radiance cube gives bevels, polished stone and
## forged iron a coherent cool vault / warm bounce to reflect. It is indirect
## lighting, not a second rendered room. Standing water uses WaterMirror.
## PowerVR retains direct-light highlights without allocating a radiance cube.

static func configure(environment: Environment, light: Dictionary = {}) -> void:
	if not RenderPolicy.current().reflections:
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		environment.sky = null
		return
	if not environment.sky:
		var sky := Sky.new()
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		sky.process_mode = Sky.PROCESS_MODE_QUALITY
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/dungeon_radiance.gdshader")
		sky.sky_material = material
		environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var material: ShaderMaterial = environment.sky.sky_material
	if light.is_empty() and environment.sky.has_meta("carved_palette"): return
	var palette := {"vault":light.get("ambient_color",environment.ambient_light_color).lerp(Color("8caed0"),.55),
		"hearth":light.get("lamp_color",Color("ffdbab"))}
	# Avoid filtering the static radiance again when another room on the same
	# floor applies the same palette, or a settings page refreshes its values.
	if environment.sky.get_meta("carved_palette",{}) == palette: return
	for key in palette: material.set_shader_parameter(key,palette[key])
	environment.sky.set_meta("carved_palette",palette)
