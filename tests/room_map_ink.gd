extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("exercise")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)
func exercise() -> void:
	var ink = load("res://scripts/presentation/room_map_ink.gd")
	var shapes := [[Vector2i.ZERO], [Vector2i.ZERO, Vector2i.RIGHT], [Vector2i.ZERO, Vector2i.DOWN],
		[Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN],
		[Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE],
		[Vector2i.ZERO, Vector2i.DOWN, Vector2i(0,2), Vector2i(1,2), Vector2i(2,2), Vector2i(2,1), Vector2i(2,0)]]
	for shape in shapes:
		for turn in 4:
			var cells: Array = shape.map(func(c):
				for i in turn: c = Vector2i(-c.y, c.x)
				return c + Vector2i(4, -3))
			for size in [22.0, 48.0]:
				var polygon: PackedVector2Array = ink.outline(cells, size)
				var inner: PackedVector2Array = Geometry2D.offset_polygon(polygon, -size * .065)[0]
				var path: PackedVector2Array = ink.path(inner)
				check(path.size() > 3, "one complete trail exists for each room shape")
				check(path == ink.path(inner), "room ink is deterministic")
				for i in range(1, path.size()):
					check(ink.segment_inside(path[i-1], path[i], polygon), "continuous trail never crosses an empty notch")
				for cell in cells:
					var center: Vector2 = Vector2(cell) * size
					var distance := INF
					for i in range(1, path.size()): distance = minf(distance, center.distance_to(Geometry2D.get_closest_point_to_segment(center, path[i-1], path[i])))
					check(distance < 4.5, "the same scribble fills every cell of the room")
	print("ROOM MAP INK: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
