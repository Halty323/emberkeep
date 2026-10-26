class_name DungeonUISurface
extends Control
## A small, native-canvas stone slab. It shares the dungeon's light positions
## without allocating another viewport, light, or shadow map.
var stone_material: ShaderMaterial
var face: ColorRect
var slab_color = Color("42433a")
var trim_color = Color("a18c62")
var compact_surface = false
var _shadow: StyleBoxFlat
var _lighting_initialized = false
var _last_colors := PackedColorArray()
var _last_key_direction = Vector3.ZERO
var _last_key_color = Color.BLACK
var _last_ambient = -1.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stone_material = ShaderMaterial.new()
	stone_material.shader = preload("res://shaders/ui_stone.gdshader")
	face = ColorRect.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.material = stone_material
	face.color = Color.WHITE
	add_child(face)
	_shadow = StyleBoxFlat.new()
	_shadow.bg_color = Color(0, 0, 0, 0)
	_shadow.shadow_color = Color(.015, .02, .018, .48)
	_shadow.shadow_size = 9
	_shadow.shadow_offset = Vector2(0, 5)
	_shadow.set_corner_radius_all(8)
	resized.connect(_update_geometry)

func configure(rect: Rect2, base_color: Color, accent_color: Color, compact := false) -> void:
	position = rect.position
	size = rect.size
	slab_color = base_color
	trim_color = accent_color
	compact_surface = compact
	stone_material.set_shader_parameter("base_color", slab_color)
	stone_material.set_shader_parameter("accent_color", trim_color)
	stone_material.set_shader_parameter("compact_surface", compact_surface)
	_update_geometry()
	queue_redraw()

func _update_geometry() -> void:
	face.size = size
	stone_material.set_shader_parameter("panel_size", size)
	stone_material.set_shader_parameter("panel_origin", position)
	queue_redraw()

func set_lighting(lamps: PackedVector4Array, colors: PackedColorArray, key_direction: Vector3, key_color: Color, ambient: float) -> void:
	# The UI shares already-padded packed arrays. Reuse their storage instead
	# of allocating and rebuilding eight values for every panel, every frame.
	var padded_lamps = lamps
	var padded_colors = colors
	if lamps.size() != 4:
		padded_lamps = lamps.slice(0, 4)
		while padded_lamps.size() < 4: padded_lamps.append(Vector4(0, 0, 1, 0))
	if colors.size() != 4:
		padded_colors = colors.slice(0, 4)
		while padded_colors.size() < 4: padded_colors.append(Color.BLACK)
	stone_material.set_shader_parameter("lamp_data", padded_lamps)
	# Lantern energy flickers, but colors, directional light, and ambient light
	# usually stay fixed. Avoid redundant RenderingServer uniform updates.
	if not _lighting_initialized or padded_colors != _last_colors:
		_last_colors = padded_colors
		stone_material.set_shader_parameter("lamp_colors", padded_colors)
	var direction = key_direction.normalized() if not key_direction.is_zero_approx() else Vector3(0, 0, 1)
	if not _lighting_initialized or direction != _last_key_direction:
		_last_key_direction = direction
		stone_material.set_shader_parameter("key_direction", direction)
	if not _lighting_initialized or key_color != _last_key_color:
		_last_key_color = key_color
		stone_material.set_shader_parameter("key_color", key_color)
	var ambient_value = .55 + maxf(0.0, ambient) * .65
	if not _lighting_initialized or not is_equal_approx(ambient_value, _last_ambient):
		_last_ambient = ambient_value
		stone_material.set_shader_parameter("ambient_energy", ambient_value)
	_lighting_initialized = true

func _draw() -> void:
	draw_style_box(_shadow, Rect2(Vector2.ZERO, size))
