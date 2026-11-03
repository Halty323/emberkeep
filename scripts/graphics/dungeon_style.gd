class_name DungeonStyle
extends RefCounted
## Carved storybook surfaces: large painted forms and matching relief,
## roughness and cavities. Shared by architecture, furniture and the title.
static var maps: Dictionary = {}
static var materials: Dictionary = {}
static var floor_sheet: PlaneMesh
static var active_theme := ""

static func theme_for(look: Dictionary) -> String:
	var theme: String=look.get("materials",{}).get("theme","")
	return theme if theme in DungeonPBR.THEMES else ""

static func prepare_theme(theme: String) -> void:
	if theme not in DungeonPBR.THEMES or theme==active_theme: return
	for key in materials.keys():
		if materials[key].has_meta("surface_theme"): materials.erase(key)
	active_theme=theme
	DungeonPBR.activate_theme(theme)

static func ceiling_material(look: Dictionary) -> ShaderMaterial:
	if look.get("materials",{}).get("ceiling","")=="wood": return wood_material(Color(look.get("cap","76614b")))
	return wall_material(Color(look.get("wall","454847")),false,theme_for(look))

static func structural_material(look: Dictionary, tint: Color, cap := false) -> ShaderMaterial:
	if look.get("materials",{}).get("structure","")=="wood": return wood_material(tint)
	return wall_material(tint,cap,theme_for(look))

static func quality_key() -> String:
	return str(DungeonPBR.resolution()) + ":" + str(Look.quality()) + ":" + str(RenderPolicy.current().lightweight_surfaces)

## Two bounded fragment-only height refinements at nearby surfaces. The
## conservative driver path and Effects Low never sample relief offsets.
static func relief_budget() -> float:
	if RenderPolicy.current().lightweight_surfaces or Look.quality() == 0: return 0.0
	return .6 if Look.quality() == 1 else 1.0

static func set_relief(material: ShaderMaterial, metres: float) -> void:
	material.set_meta("carved_relief",metres)
	material.set_shader_parameter("relief_depth",metres*relief_budget())

## Preferences also apply to surfaces already held by the room, title and
## view model. Update shared uniforms; never rebuild geometry or the run.
static func apply_quality() -> void:
	var budget := relief_budget()
	for material in materials.values():
		if material.has_meta("carved_relief"):
			material.set_shader_parameter("relief_depth",float(material.get_meta("carved_relief"))*budget)

static func floor_mesh() -> PlaneMesh:
	if not floor_sheet:
		floor_sheet = PlaneMesh.new()
		floor_sheet.size = RoomGeometry.CELL
	return floor_sheet

static func surface_maps(kind: int) -> Dictionary:
	var key := str(clampi(kind,0,2)) + "|" + str(DungeonPBR.resolution())
	if maps.has(key): return maps[key]
	maps[key] = DungeonPBR.maps("flagstone" if kind == 0 else "rock")
	return maps[key]

static func floor_material(look: Dictionary) -> ShaderMaterial:
	var theme:=theme_for(look)
	prepare_theme(theme)
	var key = "floor" + JSON.stringify(look) + quality_key()
	if materials.has(key): return materials[key]
	var surface: Dictionary = look.get("surface", {})
	var kind = maxi(0, Look.PATTERNS.find(surface.get("pattern", "slabs")))
	var textures = DungeonPBR.theme_maps(theme,"floor") if not theme.is_empty() else surface_maps(kind)
	var mat = ShaderMaterial.new()
	if not theme.is_empty(): mat.set_meta("surface_theme",theme)
	mat.shader = preload("res://shaders/dungeon_floor.gdshader")
	var colors: Array = look.get("floor", Look.DEFAULT_PALETTE)
	for i in 5: mat.set_shader_parameter("palette_" + "abcde"[i], Color(colors[i]))
	mat.set_shader_parameter("paint", textures.paint)
	mat.set_shader_parameter("relief_map", textures.normal)
	mat.set_shader_parameter("orm", textures.orm)
	mat.set_shader_parameter("uv_aspect", textures.uv_aspect)
	mat.set_shader_parameter("detail", Look.detail())
	mat.set_shader_parameter("tile_scale", .24 * 2.4 / maxf(.8, float(surface.get("size", 2.4))))
	mat.set_shader_parameter("earth", 1.0 if kind == 2 else 0.0)
	mat.set_shader_parameter("relief_strength", .95 if kind == 0 else .85)
	set_relief(mat,.06)
	for parameter in ["wetness", "moss", "frost", "embers", "brass"]:
		mat.set_shader_parameter(parameter, float(surface.get(parameter, 0)))
	mat.set_shader_parameter("moss_color", Color(surface.get("moss_color", "40532b")))
	mat.set_shader_parameter("ember_color", Color(surface.get("ember_color", "ff722c")))
	materials[key] = mat
	return mat

static func wall_material(color: Color, cap := false, family := "masonry") -> ShaderMaterial:
	if family not in DungeonPBR.THEMES and family not in DungeonPBR.FAMILIES: family="masonry"
	prepare_theme(family)
	var key = "wall" + color.to_html() + str(cap) + family + quality_key()
	if materials.has(key): return materials[key]
	var textures = DungeonPBR.theme_maps(family) if family in DungeonPBR.THEMES else DungeonPBR.maps(family)
	var mat = ShaderMaterial.new()
	if family in DungeonPBR.THEMES: mat.set_meta("surface_theme",family)
	mat.shader = preload("res://shaders/dungeon_wall.gdshader")
	mat.set_shader_parameter("tint", color.lightened(.45))
	mat.set_shader_parameter("paint", textures.paint)
	mat.set_shader_parameter("relief_map", textures.normal)
	mat.set_shader_parameter("orm", textures.orm)
	mat.set_shader_parameter("uv_aspect", textures.uv_aspect)
	mat.set_shader_parameter("tile_scale", .28 if cap else .25)
	mat.set_shader_parameter("relief_strength", .5 if cap else 1.0)
	set_relief(mat,.025 if cap else .075)
	mat.set_shader_parameter("dampness", .55 if family == "cistern" else (.16 if family == "halls" else 0.0))
	materials[key] = mat
	return mat

static func wood_material(color: Color, local_space := false) -> ShaderMaterial:
	var key = "wood" + color.to_html() + str(local_space) + quality_key()
	if materials.has(key): return materials[key]
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/dungeon_wood.gdshader")
	mat.set_shader_parameter("local_space", local_space)
	mat.set_shader_parameter("tint", color.lightened(.3))
	var textures = DungeonPBR.maps("wood")
	mat.set_shader_parameter("paint", textures.paint)
	mat.set_shader_parameter("relief_map", textures.normal)
	mat.set_shader_parameter("orm", textures.orm)
	mat.set_shader_parameter("uv_aspect", textures.uv_aspect)
	set_relief(mat,.025)
	materials[key] = mat
	return mat

static func metal_material(color: Color, local_space := false, vertex_color := false) -> ShaderMaterial:
	var key = "metal" + color.to_html() + str(local_space) + str(vertex_color) + quality_key()
	if materials.has(key): return materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/dungeon_metal.gdshader")
	var textures := DungeonPBR.maps("metal")
	mat.set_shader_parameter("paint",textures.paint)
	mat.set_shader_parameter("relief_map",textures.normal)
	mat.set_shader_parameter("orm",textures.orm)
	mat.set_shader_parameter("tint",color)
	mat.set_shader_parameter("local_space",local_space)
	mat.set_shader_parameter("vertex_color",vertex_color)
	materials[key] = mat
	return mat

## Corridor vertices keep their authored UV frame when the streaming origin
## moves. Reusing the dominant-axis shader avoids any texture jump at a bend.
static func corridor_material(family: String, look: Dictionary = {}) -> ShaderMaterial:
	var theme:=theme_for(look)
	prepare_theme(theme)
	var key := "corridor:"+family+":"+theme+":"+str(DungeonPBR.resolution())
	if materials.has(key): return materials[key]
	var textures := DungeonPBR.theme_maps(theme,"floor" if family=="flagstone" else "wall") if not theme.is_empty() else DungeonPBR.maps(family)
	var mat := ShaderMaterial.new()
	if not theme.is_empty(): mat.set_meta("surface_theme",theme)
	mat.shader=preload("res://shaders/dungeon_wood.gdshader")
	mat.set_shader_parameter("local_space",true)
	mat.set_shader_parameter("tint",Color("ced6dc"))
	mat.set_shader_parameter("paint",textures.paint)
	mat.set_shader_parameter("relief_map",textures.normal)
	mat.set_shader_parameter("orm",textures.orm)
	mat.set_shader_parameter("uv_aspect",textures.uv_aspect)
	mat.set_shader_parameter("tile_scale",Vector2(.25,.25))
	set_relief(mat,.035)
	materials[key]=mat
	return mat

static func dress_props(room) -> void:
	for entry in room.props.values():
		var brazier: bool = entry.definition.recipe == "brazier"
		for mesh in entry.node.find_children("*", "MeshInstance3D", true, false):
			var source = mesh.material_override
			if brazier:
				if source is ShaderMaterial and source.shader.resource_path == "res://shaders/halo.gdshader":
					mesh.visible = false
					continue
				if mesh.name == "Flame":
					dress_brazier_fire(mesh)
					continue
				if mesh.name == "Coals":
					mesh.material_override = brazier_coals()
					continue
				if source is StandardMaterial3D:
					mesh.material_override = metal_material(source.albedo_color)
					continue
			if not source is StandardMaterial3D or source.emission_enabled: continue
			var color: Color = source.albedo_color
			if color.is_equal_approx(PropVisuals.WOOD) or color.is_equal_approx(PropVisuals.DARK_WOOD) or color.is_equal_approx(PropVisuals.LIGHT_WOOD):
				mesh.material_override = wood_material(color)
			elif color.is_equal_approx(PropVisuals.BRASS):
				mesh.material_override = metal_material(color)

static func lantern_glass() -> ShaderMaterial:
	if materials.has("glass"): return materials.glass
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/lantern_glass.gdshader")
	materials.glass = mat
	return mat

static var candle_mesh: QuadMesh
static var brazier_mesh: QuadMesh

static func brazier_coals() -> ShaderMaterial:
	if not materials.has("coals"):
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/hearth_coals.gdshader")
		materials.coals = mat
	return materials.coals

static func dress_brazier_fire(flame: MeshInstance3D) -> void:
	if not brazier_mesh:
		brazier_mesh = QuadMesh.new()
		brazier_mesh.size = Vector2(.58, .80)
	flame.mesh = brazier_mesh
	flame.material_override = candle_flame()
	flame.scale = Vector3.ONE
	flame.position = Vector3(0, 1.34, 0)
	flame.layers = Geo.FLAME_LAYER
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Three small, spatially separated tongues give fire volume from above
	# and from every side. Geometry/materials are shared, with no new lights.
	if flame.get_child_count() > 0: return
	for side in [-1.0, 1.0]:
		var tongue := MeshInstance3D.new()
		tongue.mesh = brazier_mesh
		tongue.material_override = candle_flame()
		tongue.position = Vector3(side * .13, -.11, side * .08)
		tongue.scale = Vector3(.72, .72 if side < 0 else .64, .72)
		tongue.layers = Geo.FLAME_LAYER
		tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.add_child(tongue)

static func candle_flame() -> ShaderMaterial:
	if materials.has("candle_flame"): return materials.candle_flame
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/hearth_flame.gdshader")
	mat.set_shader_parameter("billboard",true)
	materials.candle_flame = mat
	return mat

static func candle_flame_mesh() -> QuadMesh:
	if not candle_mesh:
		candle_mesh = QuadMesh.new()
		candle_mesh.size = Vector2(.16,.25)
	return candle_mesh

static func verify_material_assets() -> Array[String]:
	var errors: Array[String] = DungeonPBR.verify_assets()
	var paths: Array[String] = ["res://assets/materials/aging.png"]
	for kind in 3:
		for channel in ["paint","normal"]: paths.append("res://assets/materials/floor_%d_%s.png" % [kind,channel])
	for family in ["cellar","cistern","halls","crypt","archive","kiln","belfry","hearth","masonry","dressed"]:
		for channel in ["paint","normal"]: paths.append("res://assets/materials/wall_%s_%s.png" % [family,channel])
	for path in paths:
		if not ResourceLoader.exists(path):
			errors.append("Missing material sheet: " + path)
			continue
		var texture = load(path)
		if not texture is Texture2D or texture.get_width() <= 0: errors.append("Unreadable material sheet: " + path)
	return errors
