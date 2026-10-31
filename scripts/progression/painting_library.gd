class_name PaintingLibrary
extends RefCounted
## Bundled reproductions only; nothing is ever requested over the network.
## Wall textures for paintings on screen live in a small bounded cache; the
## larger inspection image loads on demand and is released by the viewer.
const WALL_CACHE := 6
static var wall_cache: Dictionary = {}
static var order: Array = []

static func path(painting_id: String, kind := "wall") -> String:
	return Content.record("paintings", painting_id).get("asset", {}).get(kind, "")

static func has_image(painting_id: String, kind := "wall") -> bool:
	var file = path(painting_id, kind)
	return file != "" and Content.record("paintings", painting_id).asset.status == "imported" and ResourceLoader.exists(file)

static func wall_texture(painting_id: String) -> Texture2D:
	if wall_cache.has(painting_id):
		order.erase(painting_id)
		order.append(painting_id)
		return wall_cache[painting_id]
	if not has_image(painting_id):
		return null
	var texture: Texture2D = load(path(painting_id))
	wall_cache[painting_id] = texture
	order.append(painting_id)
	while order.size() > WALL_CACHE:
		wall_cache.erase(order.pop_front())
	return texture

static func inspection_texture(painting_id: String) -> Texture2D:
	if has_image(painting_id, "full"):
		return load(path(painting_id, "full"))
	return wall_texture(painting_id)

static func resident() -> int:
	return wall_cache.size()

## Size inside a mount, preserving the full composition's proportions.
static func fit(aspect: float, box: Vector2) -> Vector2:
	if aspect >= box.x / box.y:
		return Vector2(box.x, box.x / aspect)
	return Vector2(box.y * aspect, box.y)
