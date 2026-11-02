class_name EmberkeepTitleScene
extends Node3D
## An authored title vignette. Nothing here belongs to the run simulation.
## Warm hearth, prepared equipment and a doorway into the tower tell the story
## before the player selects a run; no extra viewport or screen copy is used.
var armament_view: Node3D
var hearth_light: OmniLight3D
var sparks: MultiMeshInstance3D
var clock := 0.0
var bevel_meshes: Dictionary = {}

static func create(parent: Node3D, game) -> EmberkeepTitleScene:
	var scene = EmberkeepTitleScene.new()
	parent.add_child(scene)
	scene.build(game)
	return scene

func stone(at: Vector3, size: Vector3, tint := Color("716451")) -> MeshInstance3D:
	var mesh = Geo.add_mesh(self, beveled_box(size, .045), at, tint)
	mesh.material_override = DungeonStyle.wall_material(tint, false, "hearth")
	return mesh

func timber(at: Vector3, size: Vector3, tint := Color("64482f")) -> MeshInstance3D:
	var mesh = Geo.add_mesh(self, beveled_box(size, .025), at, tint)
	mesh.material_override = DungeonStyle.wood_material(tint)
	return mesh

func build(game) -> void:
	name = "TitleHearth"
	var floor = Geo.box(self, Vector3(0,-.13,0), Vector3(15,.25,13), Color("6b6251"))
	floor.material_override = DungeonStyle.floor_material({"materials":{"theme":"hearth"}, "floor": ["69614e","5c5949","6c6556","615842","74674f"], "surface": {"pattern":"slabs","size":2.5,"roughness":.86}})
	stone(Vector3(.4,2.9,-4), Vector3(14,5.8,.65),Color("5d594d"))
	stone(Vector3(6.6,2.9,-2), Vector3(.65,5.8,4.2),Color("4e524e"))
	# An actual chimney gives firelight a heavy central mass to shape. Its
	# darker stone and recessed corners break the old uninterrupted wall grid.
	stone(Vector3(2.55,3.88,-3.48),Vector3(3.38,3.8,.76),Color("454640"))
	stone(Vector3(.8,2.92,-3.43),Vector3(.22,5.7,.8),Color("57564a"))
	stone(Vector3(4.3,2.92,-3.43),Vector3(.22,5.7,.8),Color("57564a"))
	stone(Vector3(2.55,5.18,-3.39),Vector3(3.78,.2,.91),Color("716755"))
	# Heavy timber rhythm and a coffered ceiling frame the fire rather than
	# exposing an overhead arena. A distant blue doorway gives the eye depth.
	for x in [-5.8,-1.6,3.0,6.1]:
		timber(Vector3(x,2.7,-3.55),Vector3(.23,5.4,.26))
		timber(Vector3(x,5.35,.2),Vector3(.24,.3,8.2))
	for z in [-3.3,0,3.2]: timber(Vector3(.3,5.35,z),Vector3(12.4,.3,.23))
	# Hearth recess, dressed jambs, segmented arch and wide carved mantel.
	Geo.box(self,Vector3(2.55,1.04,-3.63),Vector3(2.8,2.08,.16),Color("171310"))
	stone(Vector3(1.18,1.0,-3.29),Vector3(.42,2.0,.75),Color("8c7960"))
	stone(Vector3(3.92,1.0,-3.29),Vector3(.42,2.0,.75),Color("8c7960"))
	for i in 11:
		var a = PI * (i+.5)/11
		var block = stone(Vector3(2.55+cos(a)*1.31,1.38+sin(a)*.83,-3.29),Vector3(.4,.28,.76),Color("938269"))
		block.rotation.z = atan2(cos(a)*.83,-sin(a)*1.31)
	stone(Vector3(2.55,2.42,-3.2),Vector3(3.42,.23,1.0),Color("9c8869"))
	stone(Vector3(2.55,.12,-2.98),Vector3(3.4,.24,1.8),Color("71634f"))
	for side in [-1,1]:
		stone(Vector3(2.55+side*1.42,.27,-3.15),Vector3(.56,.15,.95),Color("a18b66"))
	for i in 6:
		var log = Geo.cylinder(self,Vector3(1.86+i*.25,.35,-3.13),.12,.95,Color("302119"))
		log.rotation.x = PI/2
	for i in 5:
		var ember = Geo.sphere(self,Vector3(1.86+i*.32,.44,-3.12),.16,Color("df5b19"),.8)
		ember.scale = Vector3(1,.42,1)
	var flame = MeshInstance3D.new()
	flame.name = "HearthFireCard"
	var fire_mesh = QuadMesh.new()
	fire_mesh.size = Vector2(1.9,1.25)
	flame.mesh = fire_mesh
	flame.position = Vector3(2.55,.95,-3.1)
	var fire_material = ShaderMaterial.new()
	fire_material.shader = load("res://shaders/hearth_flame.gdshader")
	flame.material_override = fire_material
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.layers = 2
	add_child(flame)
	# Hand-forged fireguard and tools.
	for i in 9: Geo.box(self,Vector3(1.56+i*.245,.45,-2.62),Vector3(.03,.6,.03),Color("272b29"))
	Geo.box(self,Vector3(2.54,.74,-2.62),Vector3(2.1,.035,.04),Color("615942"))
	for i in 3:
		var poker = Geo.box(self,Vector3(4.38+i*.13,.67,-3.1),Vector3(.025,1.25,.025),Color("67695e"))
		poker.rotation.z = -.12-i*.07
	# Three motivated sources: contained fire, cold stair opening, table lamp.
	# A dark indirect baseline lets high-resolution normals catch grazing
	# highlights instead of washing every surface with a flat directional key.
	hearth_light = Geo.light(self,Vector3(2.55,1.03,-2.25),Color("ffe0af"),2.65,7.6,Settings.values.shadows)
	hearth_light.omni_attenuation = 1.35
	hearth_light.light_specular = .8
	hearth_light.shadow_bias = .035
	hearth_light.shadow_normal_bias = .25
	hearth_light.shadow_opacity = .78
	hearth_light.shadow_blur = 1.5
	hearth_light.light_size = .32
	var moon = Geo.light(self,Vector3(-2.95,2.8,-2.1),Color("8ec8ec"),.82,6.8)
	moon.omni_attenuation = 1.45
	moon.light_specular = .65
	var table_light = Geo.light(self,Vector3(2.25,1.37,.61),Color("ffe3af"),.85,3.7)
	table_light.omni_attenuation = 1.4
	# A blue portal between the timber bays, with the stair disappearing up.
	Geo.box(self,Vector3(-2.9,1.45,-3.6),Vector3(1.65,2.9,.18),Color("121e25"))
	for side in [-1,1]: stone(Vector3(-2.9+side*.95,1.55,-3.42),Vector3(.27,3.1,.42),Color("636b67"))
	stone(Vector3(-2.9,3.08,-3.42),Vector3(2.18,.2,.42),Color("899080"))
	for step in 5: stone(Vector3(-2.9,.09+step*.15,-3.58-step*.16),Vector3(1.6,.18+step*.3,.34),Color("59615c"))
	# Banner and old keep seal above the fire.
	Geo.box(self,Vector3(2.55,3.51,-3.06),Vector3(1.28,1.72,.04),Color("603c32"))
	for side in [-1,1]: Geo.box(self,Vector3(2.55+side*.53,3.5,-3.025),Vector3(.055,1.65,.025),Color("c2a16a"))
	var crest = Geo.box(self,Vector3(2.55,3.6,-2.99),Vector3(.35,.35,.08),Color("bf9b5c"))
	crest.rotation.z = PI/4
	# Rug, low preparation table, folded map, wax seal and the player's light.
	Geo.box(self,Vector3(1.25,.014,.6),Vector3(3.8,.025,3.7),Color("593a31"))
	for x in [-.5,3.0]: Geo.box(self,Vector3(x,.032,.6),Vector3(.055,.012,3.5),Color("a98755"))
	for z in [-1.1,2.3]: Geo.box(self,Vector3(1.25,.032,z),Vector3(3.4,.012,.055),Color("a98755"))
	timber(Vector3(1.35,.78,.82),Vector3(2.6,.16,1.45),Color("85603c"))
	for x in [-1,1]:
		for z in [-1,1]: timber(Vector3(1.35+x*1.02,.35,.82+z*.5),Vector3(.15,.7,.15))
	var map = Geo.box(self,Vector3(1.02,.874,.85),Vector3(1.03,.015,.74),Color("b8a47e"))
	map.rotation.y = -.21
	for i in 5:
		var road = Geo.box(self,Vector3(.68+i*.16,.886,.85),Vector3(.025,.005,.38),Color("7d765a"))
		road.rotation.y = -.21+float(i%2)*.5
	Geo.cylinder(self,Vector3(1.34,.896,1.02),.065,.02,Color("9b4937"))
	lantern(Vector3(2.25,.87,.61))
	armament_view = Node3D.new()
	armament_view.name = "PreparedArmament"
	armament_view.position = Vector3(2.0,1.55,.85)
	armament_view.rotation = Vector3(0,PI/2-.2,0)
	armament_view.scale = Vector3.ONE * 1.8
	add_child(armament_view)
	FirstPersonWeaponView.populate(armament_view)
	preview_weapon(game.ui.starter_weapon())
	for i in 3:
		var book = Geo.box(self,Vector3(4.67,.12+i*.13,-2.18),Vector3(.65,.12,.48),[Color("554431"),Color("394b43"),Color("6a4135")][i])
		book.rotation.y = .2-i*.16
	# Sword and shield waiting by the wall, as readable faceted silhouettes.
	var sword = Node3D.new()
	add_child(sword)
	sword.position = Vector3(5.0,.12,-1.64)
	sword.rotation.z = -.19
	Geo.box(sword,Vector3(0,.76,0),Vector3(.1,1.25,.055),Color("a6aaa0"))
	Geo.box(sword,Vector3(0,1.44,0),Vector3(.46,.07,.12),Color("a58b55"))
	Geo.cylinder(sword,Vector3(0,1.65,0),.05,.35,Color("5b3e28"))
	var shield = Geo.cylinder(self,Vector3(4.43,.62,-1.8),.53,.12,Color("62523d"))
	shield.rotation_degrees = Vector3(78,12,0)
	Geo.cylinder(shield,Vector3(0,.07,0),.15,.13,Color("a58b55"))
	# A small permanent spark batch, no new particles or physics nodes.
	sparks = MultiMeshInstance3D.new()
	var batch = MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = Geo.shared_box(Vector3(.018,.035,.018))
	batch.instance_count = 16
	sparks.multimesh = batch
	sparks.material_override = Geo.material(Color("ffc17b"),.6)
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sparks)
	var aged: Dictionary = {}
	for mesh in find_children("*","MeshInstance3D",true,false):
		var source = mesh.material_override
		if not source is StandardMaterial3D or source.emission_enabled or source.albedo_texture: continue
		var key = source.get_instance_id()
		if not aged.has(key):
			var finish: StandardMaterial3D = source.duplicate()
			finish.albedo_texture = DungeonTextures.aging()
			aged[key] = finish
		mesh.material_override = aged[key]
	game.room_environment.environment.ambient_light_energy = .13
	game.room_environment.environment.ambient_light_color = Color("91afce")
	game.room_environment.environment.background_color = Color("070b11")
	game.room_environment.environment.fog_density = .009
	game.room_environment.environment.fog_light_color = Color("111c25")
	game.key_light.light_energy = .045
	game.key_light.light_color = Color("92b2cb")
	DungeonAtmosphere.configure(game.room_environment.environment)

func lantern(at: Vector3) -> void:
	# Open brass cage and a real candle silhouette, rather than a solid yellow
	# cube pretending to be glass. The warm source above supplies the light.
	var metal = DungeonStyle.metal_material(Color("b39463"))
	var base = Geo.cylinder(self,at+Vector3(0,.045,0),.23,.09,Color("514735"))
	base.material_override = metal
	for x in [-.145,.145]:
		for z in [-.13,.13]:
			var rail = Geo.box(self,at+Vector3(x,.3,z),Vector3(.024,.5,.024),Color("8b764e"))
			rail.material_override = metal
	Geo.cylinder(self,at+Vector3(0,.21,0),.062,.26,Color("e5d3a9"))
	var flame = MeshInstance3D.new()
	flame.mesh = DungeonStyle.candle_flame_mesh()
	flame.material_override = DungeonStyle.candle_flame()
	flame.position = at+Vector3(0,.42,0)
	flame.layers = 2
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)
	var lid = Geo.cylinder(self,at+Vector3(0,.59,0),.245,.13,Color("8c744c"),0,.09)
	lid.material_override = metal
	var handle = Geo.ring(self,at+Vector3(0,.77,0),.15,Color("8c744c"),.02)
	handle.material_override = metal
	handle.rotation.x = PI/2

func preview_weapon(weapon: Dictionary) -> void:
	if not is_instance_valid(armament_view): return
	armament_view.get_child(2).material_override = Geo.material(Color(weapon.color),.6)
	armament_view.get_child(1).scale = Vector3(1.18 if int(weapon.count) > 1 else 1.0,1.0,1.15 if weapon.get("pattern","") == "lance" else 1.0)

func _process(delta: float) -> void:
	clock += delta
	if hearth_light:
		hearth_light.light_energy = 2.65 + sin(clock*2.1)*.055+sin(clock*5.3)*.025
		if hearth_light.shadow_enabled != Settings.values.shadows: hearth_light.shadow_enabled = Settings.values.shadows
	for i in 16:
		var y = fposmod(i*.137+clock*.28,2.3)
		var at = Vector3(2.55+sin(i*3.7+clock)*.43,.45+y,-3.05+cos(i*1.9)*.2)
		sparks.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,at))

func pose(camera: Camera3D) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = 43
	camera.near = .1
	camera.far = 40
	camera.h_offset = 0
	camera.position = Vector3(6.45+sin(clock*.07)*.045,2.8,9.5)
	camera.look_at(Vector3(1.3,1.45,-1.25))

## Small bevels catch real highlights on masonry and wood edges. Shared
## meshes keep the number of draw surfaces unchanged; no subdivision pass.
func beveled_box(size: Vector3, wanted: float) -> ArrayMesh:
	var bevel = minf(wanted, minf(size.x,minf(size.y,size.z)) * .12)
	var key = str(size)+":"+str(bevel)
	if bevel_meshes.has(key): return bevel_meshes[key]
	var half = size * .5
	var core = half - Vector3.ONE * bevel
	var tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 3:
		var a = (axis+1)%3
		var b = (axis+2)%3
		for sign_value in [-1,1]:
			var normal = Vector3.ZERO
			normal[axis] = sign_value
			var points: Array[Vector3] = []
			for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
				var p = Vector3.ZERO
				p[axis] = sign_value * half[axis]
				p[a] = corner.x * core[a]
				p[b] = corner.y * core[b]
				points.append(p)
			bevel_face(tool,points,normal)
	for axis in 3:
		var a = (axis+1)%3
		var b = (axis+2)%3
		for sa in [-1,1]:
			for sb in [-1,1]:
				var points: Array[Vector3] = []
				for corner in [Vector2(-1,0),Vector2(1,0),Vector2(1,1),Vector2(-1,1)]:
					var p = core
					p[axis] = corner.x * core[axis]
					p[a] = sa * (half[a] if corner.y == 0 else core[a])
					p[b] = sb * (core[b] if corner.y == 0 else half[b])
					points.append(p)
				var normal = Vector3.ZERO
				normal[a] = sa
				normal[b] = sb
				bevel_face(tool,points,normal.normalized())
	for sx in [-1,1]:
		for sy in [-1,1]:
			for sz in [-1,1]:
				var corner = Vector3(sx,sy,sz)
				var points: Array[Vector3] = []
				for axis in 3:
					var p = core * corner
					p[axis] = half[axis] * corner[axis]
					points.append(p)
				bevel_face(tool,points,corner.normalized())
	var mesh = tool.commit()
	bevel_meshes[key] = mesh
	return mesh

func bevel_face(tool: SurfaceTool, points: Array[Vector3], normal: Vector3) -> void:
	if (points[1]-points[0]).cross(points[2]-points[0]).dot(normal) > 0: points.reverse()
	var indices = [0,1,2,0,2,3] if points.size()==4 else [0,1,2]
	for i in indices:
		tool.set_normal(normal)
		tool.set_uv(Vector2(points[i].x+points[i].z,points[i].y))
		tool.add_vertex(points[i])
