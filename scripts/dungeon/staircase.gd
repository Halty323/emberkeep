class_name Staircase
extends Node3D
## The way up the tower. When a floor's boss falls, a spiral stair builds
## itself in the boss room, step by step, rising into a shaft of light from
## the floor above, and climbing it is the floor's exit. The next floor opens
## with the stairwell it came up through. The generator reserves both spots
## ("stairs" in boss rooms, "stairwell" in the start rooms of floors 2-3);
## rooms saved before that find a clear spot when they are built.
const STEPS := 20
const RISE := .27
const TURN := .4538 # 26 degrees between steps: about one and a half turns.
const INNER := .3
const OUTER := 1.55
const MID := (INNER + OUTER) / 2.0
# Kept free of furniture around a stair, so it never closes a path.
const CLEARANCE := OUTER + .9
const COLUMN_TIME := .45
const STEP_GAP := .09
const STEP_TIME := .32
const LIGHT_FROM := 2.3
const BUILD_TIME := 2.7
const STONE := Color("6b675b")
const STEP_COLOR := Color("8a8270")
const WOOD := Color("6e5a42")

var facing := Vector2(0, 1)
var start_angle := 0.0
var steps: Array[Node3D] = []
var column: Node3D
var shaft_material: ShaderMaterial
var top_light: OmniLight3D
var time := 0.0
var built := false
var landed := 0

## A clear spot for a stair or stairwell: inside the room and away from its
## walls, doorways, pedestal, lanterns and anything solid (`blockers`, as
## rects). Tried in a fixed order, so the same room always gets the same one.
static func find_spot(geometry: RoomGeometry, zones: Array, pedestal: Vector2, blockers: Array) -> Vector2:
	var others = zones.filter(func(zone): return zone.kind != "pedestal")
	for distance in [4.2, 5.0, 3.6, 5.8, 6.6]:
		for turn in [0, 1, -1, 2, -2, 3, -3, 4]:
			var point = pedestal + Vector2(0, -1).rotated(turn * PI / 4.0) * distance
			if not geometry.contains(point, OUTER + 1.0): continue
			if FloorGenerator.in_zones(point, others, OUTER + .4): continue
			if point.distance_to(pedestal) < OUTER + 1.6: continue
			if blockers.any(func(rect): return rect.grow(CLEARANCE).has_point(point)): continue
			return point
	# Every generated room has a spot (the dungeon suite checks); an odd
	# legacy room still gets its way up, just behind the pedestal.
	return pedestal + Vector2(0, -3.2)

## Builds the stair at its spot with its foot toward `toward`. A complete
## stair (reloaded, or re-entered) is already standing and lit.
func setup(toward: Vector2, complete: bool) -> void:
	facing = (toward - Vector2(position.x, position.z)).normalized() if not toward.is_equal_approx(Vector2(position.x, position.z)) else Vector2(0, 1)
	start_angle = facing.angle() + TURN
	column = Node3D.new()
	add_child(column)
	Geo.cylinder(column, Vector3(0, 3.0, 0), INNER, 6.0, STONE)
	Geo.halo(self, Vector3(0, .03, 0), 5.0, Color(1, .78, .45, .22))
	for i in STEPS:
		var step = Node3D.new()
		add_child(step)
		Geo.box(step, Vector3(MID, 0, 0), Vector3(OUTER - INNER + .06, .12, .62), STEP_COLOR)
		if i % 2 == 1:
			var post = Geo.cylinder(step, Vector3(OUTER - .07, .48, 0), .035, .96, WOOD)
			post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		steps.append(step)
	var shaft = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = OUTER * 1.25
	mesh.bottom_radius = OUTER * .9
	mesh.height = 7.0
	mesh.cap_top = false
	mesh.cap_bottom = false
	shaft.mesh = mesh
	shaft_material = ShaderMaterial.new()
	shaft_material.shader = preload("res://shaders/light_shaft.gdshader")
	shaft.material_override = shaft_material
	shaft.layers = 2
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.position = Vector3(0, 6.2, 0)
	add_child(shaft)
	top_light = Geo.light(self, Vector3(0, 6.0, 0), Color("ffd9a0"), 1.1, 7.5)
	if complete:
		time = BUILD_TIME
		landed = STEPS
		built = true
	pose()

## Advances the build on the simulation clock; true on the tick it finishes.
func advance(delta: float) -> bool:
	if built: return false
	time += delta
	for i in range(landed, STEPS):
		if step_progress(i) < 1.0: break
		landed = i + 1
		Effects.play("prop_dust", to_global(step_point(i)))
		if i % 5 == 4: Audio.play_sound("door", 1.4 + i * .02)
	# Fixed ticks never land exactly on the build time in floating point.
	if time >= BUILD_TIME - .0001:
		built = true
		Audio.play_sound("item", .8)
	pose()
	return built

## Solid once standing (while it builds, the game eases anyone out of its way).
func make_solid() -> void:
	add_child(solid_cylinder(OUTER, 6.0))

static func solid_cylinder(radius: float, height: float) -> StaticBody3D:
	var body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape = CollisionShape3D.new()
	var cylinder = CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape.shape = cylinder
	shape.position.y = height / 2.0
	body.add_child(shape)
	return body

func step_progress(i: int) -> float:
	return clampf((time - COLUMN_TIME - i * STEP_GAP) / STEP_TIME, 0.0, 1.0)

func step_angle(i: int) -> float:
	return start_angle + i * TURN

## Each step flies in from below and outside, turning into place.
func pose() -> void:
	column.scale.y = maxf(.001, ease(clampf(time / COLUMN_TIME, 0.0, 1.0), .4))
	for i in STEPS:
		var t = step_progress(i)
		var settle = 1.0 - pow(1.0 - t, 3.0)
		var angle = step_angle(i) - (1.0 - settle) * .9
		var reach = (1.0 - settle) * 2.2
		steps[i].visible = t > 0.0
		steps[i].position = Vector3(cos(angle) * reach, RISE * (i + 1) - (1.0 - settle) * 1.6, sin(angle) * reach)
		steps[i].rotation.y = -angle
		steps[i].scale = Vector3.ONE * lerpf(.35, 1.0, settle)
	# A warm light climbs with the newest step, so even the cellar sees the
	# stair assemble; once complete it settles high up as the light above.
	var glow = clampf((time - LIGHT_FROM) / (BUILD_TIME - LIGHT_FROM), 0.0, 1.0)
	var front = clampf((time - COLUMN_TIME) / (STEPS * STEP_GAP + STEP_TIME), 0.0, 1.0)
	var waking = clampf(time / COLUMN_TIME, 0.0, 1.0)
	shaft_material.set_shader_parameter("strength", lerpf(.3 * waking, 1.0, glow))
	top_light.position.y = lerpf(RISE * STEPS * front + 1.4, 6.0, glow)
	top_light.light_energy = lerpf(.8 * waking, 1.1, glow)
	top_light.visible = time > 0.0

## Top of step `i`, in the stair's own space.
func step_point(i: int) -> Vector3:
	var angle = step_angle(i)
	return Vector3(cos(angle) * MID, RISE * (i + 1) + .06, sin(angle) * MID)

## Where to stand to use the stair: in front of its foot, clear of the column.
func approach_point() -> Vector3:
	var angle = start_angle - TURN
	return to_global(Vector3(cos(angle), 0, sin(angle)) * (OUTER + .75))

## The way up, in world space: to the foot, then every step.
func climb_path() -> Array:
	var angle = start_angle - TURN
	var path: Array = [approach_point(), to_global(Vector3(cos(angle) * MID, 0, sin(angle) * MID))]
	for i in STEPS:
		path.append(to_global(step_point(i)))
	return path

## The stairwell a floor opens with: a dark opening with a stone rim, the top
## of the column and its last posts. Solid, so nobody walks over the hole.
static func make_well(parent: Node3D, at: Vector3) -> Node3D:
	var well = Node3D.new()
	parent.add_child(well)
	well.position = at
	var hole = MeshInstance3D.new()
	var disc = CylinderMesh.new()
	disc.top_radius = OUTER + .1
	disc.bottom_radius = OUTER + .1
	disc.height = .02
	hole.mesh = disc
	var dark = StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color("030405")
	hole.material_override = dark
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hole.position.y = .011
	well.add_child(hole)
	var rim = TorusMesh.new()
	rim.inner_radius = OUTER + .04
	rim.outer_radius = OUTER + .26
	rim.rings = 28
	rim.ring_segments = 6
	Geo.add_mesh(well, rim, Vector3(0, .05, 0), STONE)
	Geo.cylinder(well, Vector3(0, .3, 0), INNER, .6, STONE)
	for i in 3:
		var angle = i * TURN * 2.0
		var post = Geo.cylinder(well, Vector3(cos(angle) * (OUTER - .07), .48, sin(angle) * (OUTER - .07)), .035, .96, WOOD)
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	well.add_child(solid_cylinder(OUTER, 2.0))
	return well

## Coming up through a stairwell: the last quarter turn from below the floor
## (which hides what is still under it), out over the rim toward `to`.
static func rise_path(well: Vector3, to: Vector3) -> Array:
	var out = Vector2(to.x - well.x, to.z - well.z).normalized()
	var exit_angle = out.angle()
	var path: Array = []
	for k in range(5, -1, -1):
		var angle = exit_angle - k * TURN
		path.append(well + Vector3(cos(angle) * MID, -k * RISE, sin(angle) * MID))
	path.append(to)
	return path
