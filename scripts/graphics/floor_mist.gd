class_name FloorMist
extends RefCounted
## Fog lingering over the floor on the first two floors of a climb, the damp
## low rooms at the bottom of the tower. It is made of puffs: soft cloud
## sprites a little above the floor under each one (sunken cellars, ramps and
## galleries included), drifting and turning slowly, always facing the eye so
## they look round and full from any height. Each room and passage draws all
## of its puffs at once (one MultiMesh). A Perlin field slides beneath them,
## rolling banks of thicker fog through and churning each puff's edges.
## Lanterns, candles, spells and the
## player's own light make them glow; between those they sink into the dark
## (shaders/floor_mist.gdshader). Effects detail sets how close they crowd.
const FLOORS := 2
const SPACING := {"low": 3.8, "balanced": 3.1, "high": 2.7}
const SIZE := Vector2(1.5, 2.7)
static var shared_material: ShaderMaterial
static var puffs: ImageTexture
static var quad: QuadMesh

## Whether the floor being played lingers in fog.
static func wanted() -> bool:
	return Run.active and Run.floor_number <= FLOORS

static func spacing() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	var settings = tree.root.get_node_or_null("Settings") if tree else null
	return SPACING.get(str(settings.values.get("effects_detail", "balanced")) if settings else "balanced", 3.1)

## Fills floor areas (room cells or passage tiles) with puffs; `floor`
## gives the height of the floor at a point.
static func cover(parent: Node3D, areas: Array, floor: Callable, light: Dictionary = {}, layers := 1, seed_value := 0) -> MultiMeshInstance3D:
	var gen := RandomNumberGenerator.new()
	gen.seed = seed_value
	var step := spacing()
	var transforms: Array[Transform3D] = []
	var bounds := AABB()
	for area in areas:
		# Kept off the walls, so a puff turning to face you never cuts into one.
		var inner: Rect2 = area.grow(-.5)
		if inner.size.x <= .1 or inner.size.y <= .1: continue
		var across := maxi(1, int(inner.size.x / step))
		var along := maxi(1, int(inner.size.y / step))
		for i in across:
			for j in along:
				var at := inner.position + Vector2((i + gen.randf_range(.15, .85)) * inner.size.x / across, (j + gen.randf_range(.15, .85)) * inner.size.y / along)
				var y: float = floor.call(at)
				var size := gen.randf_range(SIZE.x, SIZE.y)
				var origin := Vector3(at.x, y, at.y)
				transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), origin))
				bounds = AABB(origin, Vector3.ZERO) if transforms.size() == 1 else bounds.expand(origin)
	if transforms.is_empty(): return null
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = puff_quad()
	multimesh.instance_count = transforms.size()
	for i in transforms.size(): multimesh.set_instance_transform(i, transforms[i])
	var view := MultiMeshInstance3D.new()
	view.multimesh = multimesh
	view.material_override = material(light)
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.layers = layers
	# Puffs are drawn around their origins, wider than the quad and drifting.
	view.custom_aabb = AABB(bounds.position - Vector3(2.2, .6, 2.2), bounds.size + Vector3(4.4, 3.2, 4.4))
	view.set_meta("surface_role", "mist")
	parent.add_child(view)
	return view

static func puff_quad() -> QuadMesh:
	if not quad:
		quad = QuadMesh.new()
		quad.size = Vector2.ONE
	return quad

## One material for every room and passage; the floor's light tints it.
static func material(light: Dictionary) -> ShaderMaterial:
	if not shared_material:
		shared_material = ShaderMaterial.new()
		shared_material.shader = preload("res://shaders/floor_mist.gdshader")
		shared_material.set_shader_parameter("puff_map", puff_map())
		shared_material.set_shader_parameter("flow_map", flow_map())
	if not light.is_empty():
		# Cool and pale, leaning a little to the floor's own ambient colour;
		# the cellar's fog is thicker than the floor above it.
		shared_material.set_shader_parameter("tint", Color("b9c4ce").lerp(light.get("ambient_color", Color("9aaec2")), .3))
		shared_material.set_shader_parameter("strength", .17 if Run.floor_number <= 1 else .12)
	return shared_material

static var flow: ImageTexture

## A seamless Perlin field the fog's banks and churn slide across.
static func flow_map() -> ImageTexture:
	if flow: return flow
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = .028
	noise.fractal_octaves = 3
	noise.seed = 4471
	var image: Image = noise.get_seamless_image(128, 128)
	image.convert(Image.FORMAT_L8)
	image.generate_mipmaps()
	flow = ImageTexture.create_from_image(image)
	return flow

## Four soft, lumpy cloud shapes in a 2x2 sheet, made once.
static func puff_map() -> ImageTexture:
	if puffs: return puffs
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = .045
	noise.fractal_octaves = 4
	noise.seed = 2211
	const CELL := 128
	var image := Image.create(CELL * 2, CELL * 2, false, Image.FORMAT_L8)
	for variant in 4:
		var corner := Vector2i(variant % 2, variant / 2) * CELL
		for y in CELL:
			for x in CELL:
				var p := (Vector2(x, y) + Vector2(.5, .5) - Vector2.ONE * CELL * .5) / (CELL * .5)
				var lumps := noise.get_noise_2d(x + variant * 311.0, y + variant * 173.0) * .5 + .5
				var r := p.length()
				var body := 1.0 - smoothstep(.3, 1.0, r + (lumps - .5) * .6)
				var value := clampf(body * (.55 + lumps * .6), 0.0, 1.0) * (1.0 - smoothstep(.86, 1.0, r))
				image.set_pixel(corner.x + x, corner.y + y, Color(value, value, value))
	image.generate_mipmaps()
	puffs = ImageTexture.create_from_image(image)
	return puffs
