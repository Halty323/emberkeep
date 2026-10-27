class_name DungeonRoom
extends Node3D
const MAX_LANTERN_SHADOWS = 1
const WALL_BACK_HEIGHT = 2.8
const WALL_FRONT_HEIGHT = 1.8
const WALL_CUTAWAY_HEIGHT = .45
var game: Node3D
var decor_rng = RandomNumberGenerator.new()
var lamps: Array[OmniLight3D] = []
var shadow_lamps: Array[SpotLight3D] = []
var _quality_enabled = null
var gates: Array[Node3D] = []
var open = true
var time = 0.0
var ember_mesh: MultiMeshInstance3D
var ember_origins: Array[Vector3] = []
var obstacles: Array[Dictionary] = []
var front_walls: Array[Dictionary] = []

func build(owner_game: Node3D, room: Dictionary, preview := false) -> void:
	game = owner_game
	decor_rng.seed = int(room.get("seed", 53))
	var palette = [Color("49433d"), Color("45413b"), Color("4d463e"), Color("413e39"), Color("50473e")]
	for color_index in palette.size():
		var points: Array[Vector3] = []
		for x in range(-9, 9):
			for z in range(-7, 7):
				if posmod(x * 37 + z * 19 + x * z, 5) == color_index:
					points.append(Vector3(x + .5, -.16, z + .5))
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var tile = BoxMesh.new()
		tile.size = Vector3(.975, .25, .975)
		mm.mesh = tile
		mm.instance_count = points.size()
		for i in points.size():
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i]))
		var mesh = MultiMeshInstance3D.new()
		mesh.multimesh = mm
		mesh.material_override = Geo.material(palette[color_index])
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
	Geo.box(self, Vector3(0, -.55, 0), Vector3(18.6, .7, 14.6), Color("242d31"))
	Geo.box(self, Vector3(0, -.96, 0), Vector3(17.9, .25, 13.9), Color("19232b"))
	# Tall perimeter walls; the near sides cut away when an actor is behind them.
	for side in 4:
		var horizontal = side < 2
		var sign_value = -1.0 if side % 2 == 0 else 1.0
		var height = WALL_BACK_HEIGHT if sign_value < 0 else WALL_FRONT_HEIGHT
		var length = 9.0 if horizontal else 7.0
		for part in [-1, 1]:
			var center = float(part) * (length + 1.2) / 2.0
			var pos = Vector3(center, height / 2.0, sign_value * 7.2) if horizontal else Vector3(sign_value * 9.2, height / 2.0, center)
			var dims = Vector3(length - 1.2, height, .45) if horizontal else Vector3(.45, height, length - 1.2)
			var front_side = (Vector2i(0, 1) if horizontal else Vector2i(1, 0)) if sign_value > 0 else Vector2i.ZERO
			make_wall(pos, dims, front_side)
	var connected = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for i in connected.size():
		var direction: Vector2i = connected[i]
		var has_door: bool = preview or Run.rooms.has(Run.room_key(Run.coord(Run.current_room) + direction))
		var at = Vector3(direction.x * 9.15, 0, direction.y * 7.15)
		if has_door:
			var gate = Node3D.new()
			add_child(gate)
			gate.position = at
			var rotated = direction.x != 0
			var post_height = WALL_BACK_HEIGHT - .25 if direction.x + direction.y < 0 else 1.5
			Geo.box(gate, Vector3(0, -.015, 0), Vector3(.8, .08, 2.25) if rotated else Vector3(2.25, .08, .8), Color("b69c6a"))
			for s in [-1, 1]:
				Geo.box(gate, Vector3(0, post_height / 2, s * 1.1) if rotated else Vector3(s * 1.1, post_height / 2, 0), Vector3(.25, post_height, .25), Color("797263"))
			if post_height > 1.5:
				Geo.box(gate, Vector3(0, post_height, 0), Vector3(.3, .18, 2.5) if rotated else Vector3(2.5, .18, .3), Color("797263"))
			var barrier = Geo.box(gate, Vector3(0, .75, 0), Vector3(.16, 1.45, 2.0) if rotated else Vector3(2.0, 1.45, .16), Color("b85e4c"), .7)
			barrier.name = "Barrier"
			Geo.halo(gate, Vector3(0, .035, 0), 3.5, Color(.92, .62, .25, .28))
			gates.append(gate)
		else:
			var height = WALL_BACK_HEIGHT if direction.x + direction.y < 0 else WALL_FRONT_HEIGHT
			make_wall(at + Vector3(0, height / 2, 0), Vector3(.45, height, 2.5) if direction.x != 0 else Vector3(2.5, height, .45), direction if direction.x + direction.y > 0 else Vector2i.ZERO)
	for x in [-7.65, 7.65]:
		for z in [-5.65, 5.65]:
			make_lantern(Vector3(x, 0, z))
	var room_type: String = room.get("type", "combat")
	if room_type in ["start", "treasure", "rest", "shop"] or preview:
		Geo.box(self, Vector3(0, -.003, 0), Vector3(6.2, .03, 4.6), Color("514450") if room_type == "shop" else Color("5d4c3e"))
		Geo.ring(self, Vector3(0, .035, 0), 1.65, Color("9e875c"), .025)
		Geo.ring(self, Vector3(0, .035, 0), 1.45, Color("7c7359"), .018)
	if room_type in ["combat", "boss"] and not preview:
		var points = [Vector3(-3.5, 0, -2.7), Vector3(3.5, 0, 2.7)]
		if int(room.seed) % 2 == 0:
			points = [Vector3(-3.8, 0, 2.7), Vector3(3.8, 0, -2.7)]
		for p in points:
			var dims = Vector3(1.2, 1.2, 1.2)
			Geo.box(self, p + Vector3(0, .6, 0), dims, Color("4f5855"))
			Geo.box(self, p + Vector3(0, 1.22, 0), Vector3(1.35, .14, 1.35), Color("747b68"))
			Geo.collider(self, p + Vector3(0, 1.0, 0), Vector3(1.3, 2.0, 1.3))
			obstacles.append({"position": p, "radius": 1.05})
			make_candle(p + Vector3(0, 1.32, 0), .6)
	for i in 10:
		var side = -1 if i % 2 == 0 else 1
		var p = Vector3(decor_rng.randf_range(-6.5, 6.5), 0, side * 6.2)
		if absf(p.x) < 1.7:
			p.x += 3.0
		make_candle(p, decor_rng.randf_range(.45, .85))
	make_embers()
	set_open(true)
	apply_lighting_quality()

func make_wall(at: Vector3, dimensions: Vector3, front_side := Vector2i.ZERO) -> void:
	var body = Geo.box(self, at, dimensions, Color("394148"))
	var cap = Geo.box(self, at + Vector3(0, dimensions.y / 2 + .035, 0), Vector3(dimensions.x + .06, .09, dimensions.z + .06), Color("656358"))
	var collider = Geo.collider(self, at, dimensions + Vector3(0, 2, 0))
	if front_side != Vector2i.ZERO:
		# Keep a static full-height occluder while the visible wall cuts away.
		# This avoids transparent wall passes and moving shadow-map casters.
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var caster = Geo.box(self, at, dimensions, Color("394148"))
		caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		front_walls.append({"body": body, "cap": cap, "shadow_caster": caster,
			"collider": collider, "side": front_side, "height": dimensions.y})

func update_wall_visibility(focus: Vector3, delta: float, others: Array = []) -> void:
	for wall in front_walls:
		var near = focus.x > 6.0 if wall.side.x > 0 else focus.z > 4.0
		for actor in others:
			if (actor.x > 6.0 if wall.side.x > 0 else actor.z > 4.0):
				near = true
				break
		var target = WALL_CUTAWAY_HEIGHT if near else WALL_FRONT_HEIGHT
		var height = target if delta <= 0 else move_toward(wall.height, target, delta * 7.0)
		if is_equal_approx(height, wall.height): continue
		wall.height = height
		wall.body.scale.y = height / WALL_FRONT_HEIGHT
		wall.body.position.y = height / 2
		wall.cap.position.y = height + .035

func make_lantern(p: Vector3) -> void:
	Geo.box(self, p + Vector3(0, .28, 0), Vector3(.85, .55, .85), Color("424d4c"))
	Geo.box(self, p + Vector3(0, .61, 0), Vector3(1.0, .12, 1.0), Color("716f5d"))
	Geo.cylinder(self, p + Vector3(0, 1.03, 0), .14, .8, Color("ac9061"))
	Geo.box(self, p + Vector3(0, 1.6, 0), Vector3(.5, .55, .5), Color("f7bb6d"), 1.05)
	Geo.box(self, p + Vector3(0, 1.94, 0), Vector3(.68, .12, .68), Color("826d51"))
	for x in [-.22, .22]:
		for z in [-.22, .22]:
			var bar = Geo.box(self, p + Vector3(x, 1.6, z), Vector3(.035, .65, .035), Color("6e6654"))
			bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Unshadowed fills preserve warm lantern pools in both quality modes.
	var light = Geo.light(self, p + Vector3(0, 2.2, 0), Color("ffbc71"), .6, 7.0)
	lamps.append(light)
	# Keep one warm key shadow; the other lanterns are inexpensive fills. Four
	# overlapping shadow lights still cost too much on mobile GLES3 renderers.
	if shadow_lamps.size() < MAX_LANTERN_SHADOWS:
		make_shadow_light(p)
	Geo.halo(self, p + Vector3(0, .03, 0), 7.5, Color(1, .57, .17, .2))
	var glow = Geo.halo(self, p + Vector3(0, 1.65, 0), 2.0, Color(1, .6, .2, .4))
	glow.rotation_degrees.x = 58

func make_shadow_light(p: Vector3) -> void:
	# A fixed inward-facing spotlight needs one map instead of six cube faces.
	var shadow_light = SpotLight3D.new()
	shadow_light.light_color = Color("ffbc71")
	shadow_light.light_cull_mask = 1
	shadow_light.light_energy = 1.5
	shadow_light.spot_range = 13.0
	shadow_light.spot_angle = 58.0
	shadow_light.spot_angle_attenuation = 1.5
	shadow_light.shadow_bias = .06
	shadow_light.shadow_normal_bias = .7
	shadow_light.shadow_opacity = 1.0
	shadow_light.visible = false
	add_child(shadow_light)
	shadow_light.position = p + Vector3(0, 2.2, 0)
	shadow_light.look_at(Vector3(p.x * .3, 0, p.z * .3))
	shadow_lamps.append(shadow_light)

func make_candle(p: Vector3, height: float) -> void:
	var wax = Geo.cylinder(self, p + Vector3(0, height / 2, 0), .12, height, Color("c9ad7e"))
	wax.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flame = Geo.sphere(self, p + Vector3(0, height + .1, 0), .11, Color("ffe0a1"), 2.0)
	flame.scale = Vector3(.7, 1.5, .7)
	Geo.halo(self, p + Vector3(0, .025, 0), 2.3, Color(1, .5, .13, .14))

func make_embers() -> void:
	ember_mesh = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh = SphereMesh.new()
	mesh.radius = .025
	mesh.height = .05
	mesh.radial_segments = 4
	mesh.rings = 3
	mm.mesh = mesh
	mm.instance_count = 40
	for i in 40:
		ember_origins.append(Vector3(decor_rng.randf_range(-9, 9), decor_rng.randf_range(.1, 4.0), decor_rng.randf_range(-7, 7)))
	ember_mesh.multimesh = mm
	ember_mesh.material_override = Geo.material(Color("efbc78"), 1.2)
	ember_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ember_mesh)

func set_open(value: bool) -> void:
	open = value
	for gate in gates:
		gate.get_node("Barrier").visible = not value

func apply_lighting_quality() -> void:
	var enabled: bool = Settings.values.shadows
	if _quality_enabled == enabled:
		return
	_quality_enabled = enabled
	for light in shadow_lamps:
		light.shadow_enabled = enabled
		light.visible = enabled

func _process(delta: float) -> void:
	time += delta
	apply_lighting_quality()
	for i in lamps.size():
		lamps[i].light_energy = .6 + sin(time * 3.1 + i * 2.4) * .025 + sin(time * 7.2 + i) * .012
	if ember_mesh:
		for i in ember_origins.size():
			var p: Vector3 = ember_origins[i]
			p.y = fposmod(p.y + time * .16, 4.0)
			p.x += sin(time * .35 + i) * .25
			ember_mesh.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
