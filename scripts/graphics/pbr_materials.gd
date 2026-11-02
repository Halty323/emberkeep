class_name DungeonPBR
extends RefCounted
## Original carved artwork, loaded once per material and device budget.
## ORMH keeps cavities, roughness, metal and relief in one linear texture.
## The photographic set is retained in source, outside this experiment's pack.
const ROOT := "res://assets/materials/stylized/"
const FAMILIES := ["masonry", "flagstone", "rock", "wood", "metal"]
const THEMES := ["cellar", "cistern", "halls", "crypt", "archive", "kiln", "belfry", "hearth"]
static var loaded: Dictionary = {}
static var theme_loaded: Dictionary = {}
static var active_theme := ""

## Room/corridor previews share one floor theme. Previous theme textures
## leave the cache at a floor change; live meshes retain their own references
## until the old room is freed. No atlas containing all eight floors is loaded.
static func activate_theme(theme: String) -> void:
	if theme not in THEMES or theme==active_theme: return
	theme_loaded.clear()
	active_theme=theme

static func theme_maps(theme: String, surface := "wall") -> Dictionary:
	if theme not in THEMES: return maps("flagstone" if surface=="floor" else "masonry")
	activate_theme(theme)
	if surface not in ["wall","floor"]: surface="wall"
	var mobile:=resolution()==1024
	var key:=surface+("_mobile" if mobile else "_desktop")
	if theme_loaded.has(key): return theme_loaded[key]
	var path:=ROOT+"themes/"+theme+"/"+surface+"/"
	var suffix:="_mobile" if mobile else ""
	theme_loaded[key]={"paint":load(path+"color"+suffix+".jpg"),"normal":load(path+"normal"+suffix+".jpg"),
		"orm":load(path+"ormh.png"),"uv_aspect":Vector2(1,2)}
	return theme_loaded[key]

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
	for theme in THEMES:
		for surface in ["wall","floor"]:
			for filename in ["color.jpg","normal.jpg","color_mobile.jpg","normal_mobile.jpg","ormh.png"]:
				var path: String=ROOT+"themes/"+theme+"/"+surface+"/"+filename
				if not ResourceLoader.exists(path):
					errors.append("Missing themed material: "+path)
					continue
				var texture=load(path)
				var width:=2048 if filename in ["color.jpg","normal.jpg"] else 1024
				if not texture is Texture2D or texture.get_width()!=width or texture.get_height()!=width/2:
					errors.append("Invalid themed material size: "+path)
	return errors
