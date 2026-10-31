class_name SettingRow
extends Button
## One settings row. It owns its lit stone slab as a child drawn behind the
## label, so the background and hit target always move and reflow together.
const PADDING := 22.0
var surface: DungeonUISurface
var setting_key := ""
var value_text := ""
var value_font: Font
var value_size := 20
var value_color := Color("f1cc8a")

func _init() -> void:
	surface = DungeonUISurface.new()
	surface.show_behind_parent = true
	add_child(surface)
	item_rect_changed.connect(_sync_surface)

func configure(rect: Rect2, label: String, value: String, background: Color, accent: Color) -> void:
	text = label
	value_text = value
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_theme_constant_override("h_separation", 0)
	surface.configure(Rect2(Vector2.ZERO, rect.size), background, accent, true)
	position = rect.position
	size = rect.size
	_sync_surface()

func _sync_surface() -> void:
	surface.position = Vector2.ZERO
	surface.size = size
	# Light the slab from the row's place in shared logical UI coordinates.
	surface.set_logical_origin(position)
	queue_redraw()

func label_width() -> float:
	var font: Font = get_theme_font("font")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size")).x

func value_width() -> float:
	return value_font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, value_size).x if value_font else 0.0

## True when the label and the right-aligned value cannot collide.
func content_fits() -> bool:
	return PADDING + label_width() + 24.0 + value_width() + PADDING <= size.x

func _draw() -> void:
	if not value_font or value_text.is_empty():
		return
	var at = Vector2(size.x - PADDING - value_width(), size.y / 2.0 + value_size * .36)
	var color = value_color if not disabled else Color("a9a58f")
	draw_string(value_font, at + Vector2(0, 2), value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, value_size, Color(.025, .035, .025, .85))
	draw_string(value_font, at, value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, value_size, color)
