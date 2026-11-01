class_name DungeonPBR
extends RefCounted
## Original carved artwork, loaded once per material and device budget.
## ORMH keeps cavities, roughness, metal and relief in one linear texture.
## The photographic set is retained in source, outside this experiment's pack.
const ROOT := "res://assets/materials/stylized/"
const FAMILIES := ["masonry", "flagstone", "rock", "wood", "metal"]
static var loaded: Dictionary = {}

static func resolution() -> int:
	return 1024 if OS.get_name() in ["Android", "iOS"] or RenderPolicy.current().lightweight_surfaces else 2048

static func maps(family: String) -> Dictionary:
	if family not in FAMILIES: family = "masonry"
	var mobile: bool = resolution() == 1024
	var key: String = family + ("_mobile" if mobile else "_desktop")
	if loaded.has(key): return loaded[key]
	var path: String = ROOT + family + "/"
	var suffix: String = "_mobile" if mobile else ""
	loaded[key] = {"paint": load(path + "color" + suffix + ".jpg"),
		"normal": load(path + "normal" + suffix + ".jpg"), "orm": load(path + "ormh.png"),
		"uv_aspect": Vector2(1,2) if family in ["masonry", "flagstone"] else Vector2.ONE}
	return loaded[key]

static func verify_assets() -> Array[String]:
	var errors: Array[String] = []
	for family in FAMILIES:
		for filename in ["color.jpg", "normal.jpg", "color_mobile.jpg", "normal_mobile.jpg", "ormh.png"]:
			var path: String = ROOT + family + "/" + filename
			if not ResourceLoader.exists(path):
				errors.append("Missing carved material: " + path)
				continue
			var texture = load(path)
			var expected: int = 2048 if filename in ["color.jpg", "normal.jpg"] else 1024
			if not texture is Texture2D or texture.get_width() != expected or texture.get_height() != expected / (2 if family in ["masonry", "flagstone"] else 1):
				errors.append("Invalid carved material size: " + path)
	return errors
