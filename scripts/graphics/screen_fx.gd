class_name ScreenFx
extends Node
## The frame after it is drawn: shockwaves from blasts and slams, heat haze
## over fire, colour fringes when hurt, the floor's grade, bloom, vignette
## and grain (post.gdshader). Effects detail Low keeps the plain vignette and
## no bloom; Balanced shimmers and bends less. Purely visual.
const MAX_WAVES := 4
const MAX_HEAT := 6
const WAVE_LIFE := .55
static var current: ScreenFx
var game: Node3D
var overlay: ColorRect
var material: ShaderMaterial
var post_shader: Shader = preload("res://shaders/post.gdshader")
var plain_shader: Shader = preload("res://shaders/vignette.gdshader")
var ambient_occlusion: ScreenAmbientOcclusion
# {"at": world point, "age", "reach" (screen heights), "power"}.
var waves: Array = []
# Spells' marks on the frame (SpellFx): twists round a point, a flash of
# colour, a fringe of split colour, frost at the edges and brief shimmers.
const MAX_SWIRLS := 2
var swirls: Array = []
var flash_color := Color.BLACK
var flash_left := 0.0
var flash_life := .2
var fringe := 0.0
var chill := 0.0
var shimmers: Array = []
var grade := {"gain": Color.WHITE, "lift": Color.BLACK, "saturation": 1.0}

func setup(owner_game: Node3D, rect: ColorRect, shader_material: ShaderMaterial) -> void:
	game = owner_game
	overlay = rect
	material = shader_material
	current = self
	Settings.changed.connect(func(key):
		if key in ["effects_detail", "ssao"]: apply_quality())
	apply_quality()

func _exit_tree() -> void:
	if current == self: current = null

## Low draws the vignette alone and skips bloom; above it, the full pass.
func apply_quality() -> void:
	var level = Look.quality()
	var policy = RenderPolicy.current()
	material.shader = post_shader if level > 0 and policy.post_processing else plain_shader
	var env: Environment = game.room_environment.environment
	if game.first_person:
		DungeonStyle.apply_quality()
		DungeonAtmosphere.configure(env)
	env.glow_enabled = level > 0 and policy.glow
	if material.shader == plain_shader: waves.clear()
	env.glow_intensity = .7 if level == 1 else .85
	env.glow_bloom = .06
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for i in 7: env.set_glow_level(i, 1.0 if i in ([1, 3, 5] if level == 2 else [2, 4]) else 0.0)
	apply_occlusion()
	apply_grade()

func apply_occlusion() -> void:
	var enabled: bool = game.first_person and Settings.ssao_supported() and Settings.values.ssao != "off"
	if enabled and not is_instance_valid(ambient_occlusion):
		ambient_occlusion = ScreenAmbientOcclusion.create(game.camera)
	if is_instance_valid(ambient_occlusion): ambient_occlusion.configure(Settings.values.ssao,enabled)

## A floor's colour grade; the title keeps none.
func set_grade(theme: Dictionary) -> void:
	var source: Dictionary = theme.get("grade", {})
	grade = {"gain": Color(source.get("gain", "ffffff")), "lift": Color(source.get("lift", "000000")), "saturation": float(source.get("saturation", 1.0))}
	apply_grade()

func apply_grade() -> void:
	if material.shader != post_shader: return
	material.set_shader_parameter("gain", Vector3(grade.gain.r, grade.gain.g, grade.gain.b))
	material.set_shader_parameter("lift", Vector3(grade.lift.r, grade.lift.g, grade.lift.b))
	material.set_shader_parameter("saturation", grade.saturation)

## How strongly the frame warps (Settings "screen_effects"): Full, Reduced
## (under half) or Off.
static func strength() -> float:
	match str(Settings.values.get("screen_effects", "full")):
		"off": return 0.0
		"reduced": return .45
	return 1.0

## A ring that bends the frame outward as it spreads from a world point.
static func wave(at: Vector3, radius: float, power := 1.0) -> void:
	if current == null or not is_instance_valid(current) or Look.quality() == 0 or not RenderPolicy.current().post_processing or strength() <= 0.0: return
	if current.waves.size() >= MAX_WAVES: current.waves.pop_front()
	current.waves.append({"at": at, "age": 0.0, "reach": clampf(radius * .045, .06, .3), "power": power * strength() * (1.0 if Look.quality() == 2 else .7)})

static func ready() -> bool:
	return current != null and is_instance_valid(current) and Look.quality() > 0 and RenderPolicy.current().post_processing and current.material.shader == current.post_shader and strength() > 0.0

## The frame twists round a world point, turning by `turn` radians at its heart.
static func swirl(at: Vector3, radius: float, turn: float, life := .5) -> void:
	if not ready(): return
	if current.swirls.size() >= MAX_SWIRLS: current.swirls.pop_front()
	current.swirls.append({"at": at, "age": 0.0, "life": life, "reach": clampf(radius * .05, .05, .32), "turn": turn * strength()})

## A flash of colour over the whole frame, fading over `life` seconds.
static func flash(color: Color, amount: float, life := .2) -> void:
	# Being hurt is never drowned out by a spell's flash.
	if not ready() or float(current.game.get("hurt_flash")) > .2: return
	amount *= strength()
	if amount * life < current.flash_left * current.flash_color.a: return
	current.flash_color = Color(color, amount)
	current.flash_left = life
	current.flash_life = life

## Colours split at the frame's edges for a moment.
static func split(amount: float) -> void:
	if ready(): current.fringe = maxf(current.fringe, amount * strength())

## Frost creeping in from the edges.
static func frost(amount: float) -> void:
	if ready(): current.chill = clampf(maxf(current.chill, amount * strength()), 0.0, 1.0)

## Air shimmering over a point for a while (heat, a ray's path).
static func shimmer(at: Vector3, radius: float, power: float, life: float) -> void:
	if not ready() or current.shimmers.size() >= MAX_HEAT: return
	current.shimmers.append({"at": at, "reach": radius, "power": power * strength(), "age": 0.0, "life": life})

func _process(delta: float) -> void:
	if material.shader != post_shader: return
	advance_spell_marks(delta)
	var camera: Camera3D = game.camera
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	material.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))
	var packed: Array = []
	for w in waves: w.age += delta
	waves = waves.filter(func(w): return w.age < WAVE_LIFE)
	for i in MAX_WAVES:
		if i < waves.size() and is_instance_valid(camera) and not camera.is_position_behind(waves[i].at):
			var w: Dictionary = waves[i]
			var t = w.age / WAVE_LIFE
			var at = camera.unproject_position(w.at) / size
			packed.append(Vector4(at.x, at.y, w.reach * (.2 + .8 * t), w.power * (1.0 - t) * (1.0 - t)))
		else:
			packed.append(Vector4.ZERO)
	material.set_shader_parameter("waves", PackedVector4Array(packed))
	var hot: Array = []
	var shimmer = 1.0 if Look.quality() == 2 else .6
	if is_instance_valid(camera) and game.is_playing():
		var sources: Array = game.heat_sources(MAX_HEAT)
		for spot in shimmers:
			if sources.size() >= MAX_HEAT: break
			sources.append({"at": spot.at, "reach": spot.reach, "power": spot.power * (1.0 - spot.age / spot.life)})
		for source in sources:
			if camera.is_position_behind(source.at): continue
			var at = camera.unproject_position(source.at) / size
			hot.append(Vector4(at.x, at.y, source.reach * .045, source.power * shimmer))
	while hot.size() < MAX_HEAT: hot.append(Vector4.ZERO)
	material.set_shader_parameter("heat", PackedVector4Array(hot))
	material.set_shader_parameter("grain", (.003 if Look.quality() == 2 else .0015) if game.first_person else (.02 if Look.quality() == 2 else .012))

func advance_spell_marks(delta: float) -> void:
	var camera: Camera3D = game.camera
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	for s in swirls: s.age += delta
	swirls = swirls.filter(func(s): return s.age < s.life)
	var packed: Array = []
	for i in MAX_SWIRLS:
		if i < swirls.size() and is_instance_valid(camera) and not camera.is_position_behind(swirls[i].at):
			var s: Dictionary = swirls[i]
			var t: float = s.age / s.life
			var at := camera.unproject_position(s.at) / size
			# Winds up quickly, then lets go.
			packed.append(Vector4(at.x, at.y, s.reach, s.turn * sin(PI * minf(1.0, t * 1.4)) * (1.0 - t)))
		else:
			packed.append(Vector4.ZERO)
	material.set_shader_parameter("swirls", PackedVector4Array(packed))
	flash_left = maxf(0.0, flash_left - delta)
	var glow := flash_color.a * pow(flash_left / maxf(.01, flash_life), 2.0)
	material.set_shader_parameter("flash", Vector4(flash_color.r, flash_color.g, flash_color.b, glow))
	fringe = move_toward(fringe, 0.0, delta * 3.0)
	material.set_shader_parameter("aberration", fringe)
	chill = move_toward(chill, 0.0, delta * .8)
	material.set_shader_parameter("chill", chill)
	for spot in shimmers: spot.age += delta
	shimmers = shimmers.filter(func(spot): return spot.age < spot.life)
