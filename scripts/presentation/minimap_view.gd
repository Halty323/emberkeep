class_name MinimapView
extends Control
## The first-person minimap, heading up: it follows the player and turns as
## they look, so the way they face is always up, with an arrow at its centre
## for them. The full map (M) stays north-up. Clipped to its frame at any
## angle.
const CELL_SIZE := 22.0
var ui

func setup(owner_ui) -> void:
	ui = owner_ui
	name = "MinimapView"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _draw() -> void:
	var game = ui.game
	if not Run.active or not is_instance_valid(game.player) or not Run.rooms.has(Run.current_room): return
	var center := size / 2.0
	var at: Vector3 = game.player.position
	var focus := Vector2(Run.room_anchor(Run.rooms[Run.current_room])) + Vector2(at.x / RoomGeometry.CELL.x, at.z / RoomGeometry.CELL.y)
	# The map turns by the view's yaw: what lies ahead is drawn above.
	draw_set_transform(center, float(game.fps.yaw), Vector2.ONE)
	var reach := size.length()
	ui.canvas = self
	ui.draw_floor_map(Rect2(-Vector2.ONE * reach, Vector2.ONE * reach * 2.0), focus, CELL_SIZE)
	ui.canvas = ui
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var arrow := PackedVector2Array([center + Vector2(0, -7), center + Vector2(5, 5), center + Vector2(0, 2.5), center + Vector2(-5, 5)])
	draw_colored_polygon(arrow, Color("1a1d1a"))
	draw_colored_polygon(PackedVector2Array(Array(arrow).map(func(p): return center + (p - center) * .75)), ui.GOLD)
