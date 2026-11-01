extends SceneTree
## Authoring-only. Original procedural material sheets; no external artwork.
func _initialize() -> void:
	OS.set_environment("EMBERKEEP_BAKE_MATERIALS", "1")
	call_deferred("bake")
func bake() -> void:
	var output = "res://assets/materials"
	DirAccess.make_dir_recursive_absolute(output)
	var textures = load("res://scripts/graphics/dungeon_textures.gd")
	for kind in 3:
		var maps = textures.legacy_floor(kind)
		maps.paint.get_image().save_png(output.path_join("floor_%d_paint.png" % kind))
		maps.normal.get_image().save_png(output.path_join("floor_%d_normal.png" % kind))
	for family in ["cellar","cistern","halls","crypt","archive","kiln","belfry","hearth","masonry","dressed"]:
		var maps = textures.wall(family)
		maps.paint.get_image().save_png(output.path_join("wall_%s_paint.png" % family))
		maps.normal.get_image().save_png(output.path_join("wall_%s_normal.png" % family))
	textures.aging().get_image().save_png(output.path_join("aging.png"))
	print("BAKED LEGACY DUNGEON MATERIALS: 27 original material sheets")
	quit()
