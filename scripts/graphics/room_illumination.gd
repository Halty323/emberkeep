class_name RoomIllumination
extends Node3D
## Theme-authored ceiling fixtures and localized participating media. Purely
## visual: separate seed stream, no collision, loot or gameplay light zones.
const MAX_FIXTURES := 4
const MAX_LIGHTS := 4
var flame_sources: Array[Dictionary] = []
var flame_lights: Array[OmniLight3D] = []
const PALETTES := {
	"cellar": ["edc28e", "8aafcf", "chain"],
	"cistern": ["a4d8d7", "deb98e", "cage"],
	"halls": ["bdcfa1", "d9bb8e", "chandelier"],
	"crypt": ["c9b5e5", "e4bf8d", "votive"],
	"archive": ["b8d0e2", "e6ce9c", "chandelier"],
	"kiln": ["e4ad88", "99bed0", "brazier"],
	"belfry": ["a2cdd1", "d9be8d", "cage"],
	"hearth": ["e8c5a4", "a8bcd8", "chandelier"]}
var fixtures: Array[Dictionary] = []
var lamps: Array[SpotLight3D] = []
var volumes: Array[MeshInstance3D] = []
var links: Array[Transform3D] = []
var room
var theme := "cellar"
var clock := 0.0
var last_quality := ""
static var link_mesh: TorusMesh
static var volume_mesh: BoxMesh
static var flame_materials: Dictionary = {}

static func palette(id: String) -> Array:
	return PALETTES.get(id, PALETTES.cellar)

func setup(owner_room) -> void:
	room = owner_room
	name = "RoomIllumination"
	# data.theme names a furniture layout, not the floor's visual theme.
	theme = Run.theme_id()
	var colors := palette(theme)
	var gen := RandomNumberGenerator.new()
	gen.seed = Content.stable_hash("ceiling-light:%s:%s" % [room.data.get("seed",0), theme])
	var levels: Array[float] = [0.0]
	if room.terrain and room.terrain.loft: levels.append(LoftRoom.RISE)
	# Alternate storeys before filling more cells, so upstairs never loses all
	# its accents to a lower-floor fixture budget.
	var candidates: Array = []
	for side in [-1.0,1.0]:
		for pass_index in levels.size():
			for index in room.geometry.cells.size():
				candidates.append({"cell":room.geometry.cells[index], "level":levels[(index+pass_index)%levels.size()], "side":side})
	for candidate in candidates:
		if fixtures.size() >= MAX_FIXTURES: break
		var level: float = candidate.level
		var at: Vector2 = RoomGeometry.cell_center(candidate.cell)+Vector2(candidate.side*3.0,gen.randf_range(-2.6,2.6))
		# Structural exclusions come from the saved plan. Furniture is built
		# later and may sit below a fixture; rebuilding must choose the same
		# hanging positions regardless of build order or broken containers.
		if room.data.get("partitions",[]).any(func(record): return RoomPartitions.rect(record).grow(.75).has_point(at)): continue
		if room.terrain and room.terrain.loft:
			var loft = room.terrain.loft
			if LoftRoom.reserved_area(loft.stairs,loft.facing).grow(.5).has_point(at): continue
			if level > 0.0 and not loft.on_deck(at,1.1): continue
		var ceiling: float = room.ceiling_height()
		if is_zero_approx(level) and room.terrain and room.terrain.loft and room.terrain.loft.on_deck(at): ceiling = LoftRoom.RISE-LoftRoom.SLAB
		var source_y := minf(level+3.15,ceiling-.52)
		if source_y-level < 2.2: continue
		var color := Color(colors[fixtures.size()%2])
		build_fixture(Vector3(at.x,source_y,at.y),ceiling,level,color,str(colors[2]),gen)
	build_chains()
	apply_quality()

func build_fixture(at: Vector3, ceiling: float, ground: float, color: Color, recipe: String, gen: RandomNumberGenerator) -> void:
	var model := Node3D.new()
	model.name = "Hanging_"+recipe
	model.position = at
	add_child(model)
	var iron := Color("4b4a45")
	var metal := DungeonStyle.metal_material(iron)
	var wax := Color("c4b79e")
	# The chain really reaches the underside of the ceiling/slab.
	chain(at+Vector3(0,.18,0),ceiling-.02)
	var ceiling_plate = Geo.cylinder(self,Vector3(at.x,ceiling-.025,at.z),.16,.05,iron)
	ceiling_plate.material_override = metal
	var bowl = Geo.cylinder(model,Vector3(0,-.25,0),.42,.13,iron,0,.25)
	bowl.material_override = metal
	var candle_count := 5 if recipe in ["chandelier","votive"] else 3
	if recipe == "chain": candle_count = 1
	for i in candle_count:
		var angle := TAU * float(i)/candle_count
		var offset := Vector3(cos(angle),0,sin(angle))*(.42 if candle_count>1 else 0.0)
		var arm = Geo.box(model,offset*.5+Vector3(0,-.18,0),Vector3(.5,.045,.045),iron)
		arm.rotation.y = -angle
		arm.material_override = metal
		var cup = Geo.cylinder(model,offset+Vector3(0,-.15,0),.11,.05,iron)
		cup.material_override = metal
		Geo.cylinder(model,offset+Vector3(0,-.045,0),.065,.20,wax)
		var flame := MeshInstance3D.new()
		flame.mesh = DungeonStyle.candle_flame_mesh()
		flame.material_override = fire_material(color)
		flame.position = offset+Vector3(0,.15,0)
		flame.layers = Geo.FLAME_LAYER
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.add_child(flame)
		ScreenFx.add_flame_bloom(flame,.65,color)
	if recipe in ["cage","brazier"]:
		for side in 4:
			var offset := Vector3(cos(side*PI*.5),0,sin(side*PI*.5))*.37
			var bar = Geo.box(model,offset+Vector3(0,.02,0),Vector3(.035,.56,.035),iron)
			bar.material_override = metal
		var lid = Geo.cylinder(model,Vector3(0,.30,0),.42,.09,iron,0,.18)
		lid.material_override = metal
	# Additional support chains on large chandeliers attach to the hub.
	if candle_count>3:
		for side in [-1.0,1.0]:
			var brace = Geo.box(model,Vector3(side*.2,.03,0),Vector3(.025,.43,.025),iron)
			brace.rotation.z = side*-.65
			brace.material_override = metal
	for mesh in model.find_children("*","GeometryInstance3D",true,false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flame_source := at+Vector3.UP*.15
	fixtures.append({"source":flame_source,"floor":ground,"color":color,"recipe":recipe,"ceiling":ceiling})
	if lamps.size() < MAX_LIGHTS:
		var lamp := SpotLight3D.new()
		lamp.position = flame_source
		lamp.rotation_degrees.x = -90
		lamp.spot_range = flame_source.y-ground+1.1
		lamp.spot_angle = 49.0
		lamp.spot_attenuation = 1.5
		lamp.spot_angle_attenuation = 1.1
		lamp.light_color = color
		lamp.light_energy = .78 if lamps.size()%2==0 else .62
		lamp.light_size = .18
		lamp.light_specular = .7
		lamp.light_cull_mask = Geo.LIT_LAYERS
		lamp.set_meta("base_energy",lamp.light_energy)
		lamp.shadow_enabled = false
		add_child(lamp)
		lamps.append(lamp)
		add_volume(flame_source,ground,color,gen.randf_range(1.8,2.25))

func chain(at: Vector3, ceiling: float) -> void:
	var count := maxi(1,ceili((ceiling-at.y)/.10))
	for i in count:
		var y := lerpf(at.y,ceiling,float(i)/count)
		var basis := Basis(Vector3.RIGHT,PI*.5)
		if i%2: basis = Basis(Vector3.UP,PI*.5)*basis
		links.append(Transform3D(basis.scaled(Vector3(.72,1.15,.72)),Vector3(at.x,y,at.z)))

func build_chains() -> void:
	if links.is_empty(): return
	if not link_mesh:
		link_mesh = TorusMesh.new()
		link_mesh.inner_radius = .035
		link_mesh.outer_radius = .055
		link_mesh.rings = 8
		link_mesh.ring_segments = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = link_mesh
	mm.instance_count = links.size()
	for i in links.size(): mm.set_instance_transform(i,links[i])
	var view := MultiMeshInstance3D.new()
	view.name = "CeilingChains"
	view.multimesh = mm
	view.material_override = DungeonStyle.metal_material(Color("4b4a45"))
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)
	links.clear()

static func fire_material(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not flame_materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/hearth_flame.gdshader")
		material.set_shader_parameter("billboard",true)
		material.set_shader_parameter("flame_tint",color)
		material.set_shader_parameter("colorize",.78)
		flame_materials[key] = material
	return flame_materials[key]

func add_volume(source: Vector3, floor_y: float, color: Color, radius: float) -> void:
	if not volume_mesh: volume_mesh = BoxMesh.new(); volume_mesh.size = Vector3.ONE
	var height := source.y-floor_y-.05
	var view := MeshInstance3D.new()
	view.name = "LocalLightVolume"
	view.mesh = volume_mesh
	view.position = Vector3(source.x,floor_y+height*.5,source.z)
	view.scale = Vector3(radius*2,height,radius*2)
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.layers = Geo.FLAME_LAYER
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/local_light_volume.gdshader")
	material.set_shader_parameter("tint",color)
	view.material_override = material
	add_child(view)
	volumes.append(view)

func apply_quality() -> void:
	var quality: String = Settings.values.effects_detail
	if quality == last_quality: return
	last_quality = quality
	for i in volumes.size():
		volumes[i].visible = quality != "low" and i < (3 if quality == "balanced" else MAX_LIGHTS)
		volumes[i].material_override.set_shader_parameter("steps",6 if quality == "balanced" else 10)

## Real surface illumination for ordinary candles and furniture fires. Nearby
## candle clusters share one stable source. Sources never follow the camera.
func register_flame(at: Vector3, large := false) -> void:
	for source in flame_sources:
		if source.at.distance_to(at) < .65:
			if large: source.energy = 1.1; source.reach = 4.5
			sync_flames()
			return
	flame_sources.append({"at":at,"energy":1.1 if large else .65,"reach":4.5 if large else 2.8})
	sync_flames()

func sync_flames() -> void:
	while flame_lights.size() < flame_sources.size():
		var lamp := Geo.light(self,Vector3.ZERO,Color("ffd09a"),0.0,2.8)
		lamp.omni_attenuation = 1.5
		lamp.light_size = .12
		flame_lights.append(lamp)
	for i in flame_lights.size():
		var source: Dictionary = flame_sources[i]
		var lamp := flame_lights[i]
		lamp.position = source.at
		lamp.light_energy = source.energy
		lamp.omni_range = source.reach

func _process(delta: float) -> void:
	clock += delta
	apply_quality()
	for i in lamps.size(): lamps[i].light_energy = float(lamps[i].get_meta("base_energy"))*(1.0+sin(clock*1.65+i*2.13)*.035)
