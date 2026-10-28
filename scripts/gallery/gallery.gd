class_name Gallery
extends RefCounted
## The permanent painting collection: discovery, collection progress, unlock
## reconciliation and bounded texture residency. Discoveries live in the
## profile, so they survive death and new runs.
const COLLECTION := "world_classics_12_v1"
## Wall and viewer textures kept decoded at once; older ones are released.
const RESIDENT_TEXTURES := 4
static var _textures: Dictionary = {}
static var _order: Array[String] = []

static func painting(id: String) -> Dictionary:
	return Content.get_def("paintings", id)

static func discovered() -> Array:
	return Run.profile.get("paintings", [])

static func is_discovered(id: String) -> bool:
	return id in discovered()

## [found, required] for a collection; the requirement is frozen in its record.
static func progress(collection_id := COLLECTION) -> Vector2i:
	var required: Array = Content.get_def("collections", collection_id).get("paintings", [])
	return Vector2i(required.filter(func(id): return id in discovered()).size(), required.size())

## Record an inspection. Returns {new, unlocked}; duplicates change nothing.
static func discover(id: String) -> Dictionary:
	if not Content.has_def("paintings", id):
		return {"new": false, "unlocked": []}
	if id in discovered():
		return {"new": false, "unlocked": reconcile()}
	Run.profile.paintings.append(id)
	# Progress and any unlock are saved together.
	var unlocked := reconcile(false)
	Run.save_profile()
	return {"new": true, "unlocked": unlocked}

## Grant every unlock whose collection is complete, exactly once. Runs on
## profile load as well as on discovery, so a crash between the final
## discovery and its notification cannot lose the weapon. Unlocks are never
## revoked, even if later content adds paintings.
static func reconcile(save := true) -> Array:
	var granted: Array = []
	for collection in Content.families.get("collections", []):
		var weapon: String = collection.get("unlocks", {}).get("weapon", "")
		if weapon == "" or weapon in Run.profile.unlocks:
			continue
		if collection.paintings.all(func(id): return id in discovered()):
			Run.profile.unlocks.append(weapon)
			granted.append(weapon)
	if save and not granted.is_empty():
		Run.save_profile()
	return granted

static func has_image(id: String) -> bool:
	var path: String = painting(id).get("image", "")
	return path != "" and ResourceLoader.exists(path)

## The painting's texture, or null while its image is pending import.
static func texture(id: String) -> Texture2D:
	if _textures.has(id):
		_order.erase(id)
		_order.append(id)
		return _textures[id]
	if not has_image(id):
		return null
	var tex: Texture2D = load(painting(id).image)
	_textures[id] = tex
	_order.append(id)
	while _order.size() > RESIDENT_TEXTURES:
		_textures.erase(_order.pop_front())
	return tex

static func resident() -> int:
	return _textures.size()

static func credit(id: String) -> String:
	var record := painting(id)
	var provenance: Dictionary = record.get("provenance", {})
	if provenance.is_empty():
		return "Reproduction pending import"
	var source: String = "Wikimedia Commons" if record.source.kind == "commons" else record.institution
	var rights: String = provenance.get("rights", {}).get("license", "")
	return "Reproduction: %s%s" % [source, (" · " + rights) if rights != "" else ""]
