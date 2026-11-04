class_name DeathFigure
extends Node3D
## Death behind a dark altar. It comes out of the dark in three breaths: mist
## and a black shape with its scythe, then robe, bone and steel, and last its
## eyes, two small white lights. It turns to watch the player, and once the
## bargain is struck it goes the way it came.
## Every part keeps one alpha-blended material from the start, so nothing
## changes shader variant (and nothing compiles) while it appears.
const NEAR := 6.5
const WAIT := 3.5
# Seconds into the rising: mist, then the shape, then its colours, then eyes.
const SHAPE := [.5, 2.0]
const DETAIL := [2.0, 3.6]
const EYES := [3.4, 4.3]
const RISE := 4.3
const FADE := 2.0
const ROBE := Color("17131c")
const BONE := Color("d8d0c0")
const STEEL := Color("9a9ca6")
const MIST := Color(.42, .36, .52)

var game: Node
var state := "hidden"
var clock := 0.0
var lingering := 0.0
# [MeshInstance3D, StandardMaterial3D, final colour]
var parts: Array = []
var eyes: Array = []
var glows: Array = []
var mist: Array = []
var back: MeshInstance3D
var light: OmniLight3D
var body: Node3D
static var soft_texture: GradientTexture2D

func setup(owner_game: Node) -> void:
	game = owner_game
	body = Node3D.new()
	add_child(body)
	build_robe()
	build_arms()
	build_scythe()
	build_mist()
	light = OmniLight3D.new()
	light.light_color = Color("b9a2e6")
	light.light_energy = 0.0
	light.omni_range = 3.2
	light.position = Vector3(0, 2.7, .7)
	add_child(light)
	apply(0.0, 0.0, 0.0, 0.0)

## Begins rising, if it is not already here.
func appear() -> void:
	if state != "hidden": return
	state = "rising"
	clock = 0.0
	if game and game.has_method("death_rises"): game.death_rises(self)

## Fades back into the dark once the bargain is made.
func vanish() -> void:
	if state in ["hidden", "gone", "fading"]: return
	state = "fading"
	clock = 0.0

func present() -> bool:
	return state == "present"

func _process(delta: float) -> void:
	if not game or not is_instance_valid(game.player): return
	var player_at: Vector3 = game.player.global_position
	if state == "hidden":
		lingering += delta
		if lingering > WAIT or global_position.distance_to(player_at) < NEAR: appear()
		return
	if state == "gone": return
	clock += delta
	# It turns slowly to keep the player in sight, and hovers a little.
	var towards := player_at - global_position
	if towards.length_squared() > .01:
		rotation.y = lerp_angle(rotation.y, atan2(towards.x, towards.z), minf(1.0, delta * 1.6))
	body.position.y = .06 + sin(clock * 1.3) * .035
	for i in mist.size():
		var angle := clock * (.12 + i * .02) + TAU * i / mist.size()
		mist[i].position = Vector3(cos(angle) * (.55 + .1 * (i % 3)), .25 + .05 * sin(clock + i), sin(angle) * (.45 + .1 * (i % 2)))
	if state == "rising":
		var shape := ramp(clock, SHAPE)
		apply(minf(1.0, clock / 1.2), shape, ramp(clock, DETAIL), ramp(clock, EYES))
		if clock >= RISE: state = "present"
	elif state == "present":
		apply(1.0, 1.0, 1.0, .85 + .15 * sin(clock * 2.1))
	elif state == "fading":
		# The eyes go first, then the colour, then the shape and the mist.
		var t := clock / FADE
		apply(1.0 - ramp(t, [.55, 1.0]), 1.0 - ramp(t, [.35, .9]), 1.0 - ramp(t, [.1, .5]), 1.0 - ramp(t, [0.0, .2]))
		if clock >= FADE:
			state = "gone"
			visible = false

static func ramp(t: float, span: Array) -> float:
	return smoothstep(float(span[0]), float(span[1]), t)

## mist: the haze; shape: how solid the black figure is; detail: how much of
## its colour shows; eyes: how bright its eyes are.
func apply(haze: float, shape: float, detail: float, eye: float) -> void:
	visible = haze > 0.0 or shape > 0.0
	for part in parts:
		var colour: Color = Color.BLACK.lerp(part[2], detail)
		colour.a = shape
		part[1].albedo_color = colour
		if part[1].emission_enabled: part[1].emission_energy_multiplier = detail * .35
	for eye_mesh in eyes:
		eye_mesh.material_override.albedo_color = Color(1, 1, 1, eye * shape)
		eye_mesh.material_override.emission_energy_multiplier = 2.6 * eye
	for glow in glows:
		glow.material_override.albedo_color = Color(.92, .95, 1.0, .32 * eye * shape)
	if not mist.is_empty(): mist[0].material_override.albedo_color = Color(MIST, .55 * haze)
	back.material_override.albedo_color = Color(.36, .26, .52, .55 * haze * (1.0 - .45 * detail))
	light.light_energy = .55 * maxf(haze * .4, detail)

## One part of the figure, with its own fading material.
func part(mesh: Mesh, at: Vector3, colour: Color, parent: Node3D = null, glint := false) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mat.roughness = .55 if glint else .95
	mat.metallic = .6 if glint else 0.0
	mat.albedo_color = Color(0, 0, 0, 0)
	if glint:
		mat.emission_enabled = true
		mat.emission = Color("c9c4e8")
		mat.emission_energy_multiplier = 0.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else body).add_child(instance)
	instance.position = at
	parts.append([instance, mat, colour])
	return instance

static func cone(bottom: float, top: float, height: float, sides := 14) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh

static func ball(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 8
	return mesh

static func block(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

## Robe, shoulders, hood, the void of its face and the eyes within it.
func build_robe() -> void:
	part(cone(.58, .2, 1.85), Vector3(0, .93, 0), ROBE)
	part(cone(.3, .27, .06), Vector3(0, 1.24, 0), Color("3b3345"))
	var shoulders := part(ball(.3), Vector3(0, 1.78, 0), ROBE)
	shoulders.scale = Vector3(1.45, .72, 1.0)
	var hood := part(ball(.25), Vector3(0, 2.1, -.08), Color("1d1824"))
	hood.scale = Vector3(1.0, 1.22, 1.12)
	var peak := part(cone(.17, .0, .3, 10), Vector3(0, 2.33, -.16), Color("1d1824"))
	peak.rotation.x = -.5
	# The hood's rim: a little lighter cloth framing the dark.
	var ring := TorusMesh.new()
	ring.inner_radius = .15
	ring.outer_radius = .2
	ring.rings = 16
	ring.ring_segments = 6
	var rim := part(ring, Vector3(0, 2.08, .2), Color("2c2535"))
	rim.rotation.x = PI / 2.0
	rim.scale = Vector3(1.0, 1.0, 1.18)
	var face := part(ball(.16), Vector3(0, 2.08, .17), Color.BLACK)
	face.scale = Vector3(1.0, 1.18, .55)
	# Ragged hem strips, swaying a hand's width above the floor.
	for i in 7:
		var angle := TAU * i / 7.0 + .2
		var strip := part(block(Vector3(.16, .34, .03)), Vector3(sin(angle) * .55, .14, cos(angle) * .55), ROBE)
		strip.rotation.y = angle
		strip.rotation.x = .18
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = ball(.0165)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color.WHITE
		eye.material_override = mat
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(eye)
		eye.position = Vector3(side * .056, 2.115, .262)
		eyes.append(eye)
		var glow := sprite(.13, Color(1, 1, 1, 0))
		body.add_child(glow)
		glow.position = eye.position + Vector3(0, 0, .02)
		glows.append(glow)

## The right hand offers, palm up; the left holds the scythe.
func build_arms() -> void:
	var offering := Node3D.new()
	body.add_child(offering)
	offering.position = Vector3(-.32, 1.72, .05)
	offering.rotation = Vector3(-1.0, 0, -.08)
	part(cone(.075, .12, .62), Vector3(0, -.3, 0), ROBE, offering)
	var palm := part(ball(.06), Vector3(0, -.64, .02), BONE, offering)
	palm.scale = Vector3(1.0, .6, 1.2)
	for i in 4:
		var finger := part(block(Vector3(.018, .11, .018)), Vector3(-.04 + i * .027, -.72, .04), BONE, offering)
		finger.rotation.x = -.5
	var holding := Node3D.new()
	body.add_child(holding)
	holding.position = Vector3(.36, 1.72, .05)
	holding.rotation = Vector3(-.35, 0, .55)
	part(cone(.075, .12, .5), Vector3(0, -.25, 0), ROBE, holding)
	var fist := part(ball(.062), Vector3(0, -.53, .02), BONE, holding)
	fist.scale = Vector3(1.0, 1.1, 1.0)

## A long pole with a curved blade at its head, over Death's shoulder.
func build_scythe() -> void:
	var scythe := Node3D.new()
	body.add_child(scythe)
	scythe.position = Vector3(.64, 1.32, .22)
	scythe.rotation.z = .07
	part(block(Vector3(.042, 2.7, .042)), Vector3.ZERO, Color("3a3029"), scythe)
	part(block(Vector3(.07, .07, .07)), Vector3(0, 1.32, 0), STEEL, scythe, true)
	var previous := Vector3(0, 1.3, 0)
	for i in 8:
		var s := float(i + 1) / 8.0
		var next := Vector3(-.95 * s, 1.3 - .42 * s * s, -.12 * s)
		var segment := part(block(Vector3(previous.distance_to(next) + .02, .1 * (1.0 - s * .75), .014)), (previous + next) / 2.0, STEEL, scythe, true)
		segment.rotation.z = atan2(next.y - previous.y, next.x - previous.x)
		previous = next

## Mist at its feet and a faint glow behind it, so the black shape shows
## against the dark before anything else does.
func build_mist() -> void:
	var haze := StandardMaterial3D.new()
	for i in 7:
		var puff := sprite(1.1 + .25 * (i % 3), Color(MIST, 0), haze)
		add_child(puff)
		mist.append(puff)
	back = sprite(2.9, Color(0, 0, 0, 0))
	add_child(back)
	back.position = Vector3(0, 1.45, -.55)

static func radial() -> GradientTexture2D:
	if soft_texture: return soft_texture
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(.45, Color(1, 1, 1, .35))
	soft_texture = GradientTexture2D.new()
	soft_texture.gradient = gradient
	soft_texture.fill = GradientTexture2D.FILL_RADIAL
	soft_texture.fill_from = Vector2(.5, .5)
	soft_texture.fill_to = Vector2(.5, 0)
	soft_texture.width = 64
	soft_texture.height = 64
	return soft_texture

## A soft round sprite that always faces the camera.
static func sprite(size: float, colour: Color, shared: StandardMaterial3D = null) -> MeshInstance3D:
	var mat := shared if shared else StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = radial()
	mat.albedo_color = colour
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
