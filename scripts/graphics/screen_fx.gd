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
# {"at": world point, "age", "reach" (screen heights), "power"}.
var waves: Array = []
var grade := {"gain": Color.WHITE, "lift": Color.BLACK, "saturation": 1.0}

func setup(owner_game: Node3D, rect: ColorRect, shader_material: ShaderMaterial) -> void:
	game = owner_game
	overlay = rect
	material = shader_material
	current = self
	Settings.changed.connect(func(key):
		if key == "effects_detail": apply_quality())
	apply_quality()

func _exit_tree() -> void:
	if current == self: current = null

## Low draws the vignette alone and skips bloom; above it, the full pass.
func apply_quality() -> void:
	var level = Look.quality()
	material.shader = post_shader if level > 0 else plain_shader
	var env: Environment = game.room_environment.environment
	env.glow_enabled = level > 0
	env.glow_intensity = .7 if level == 1 else .85
	env.glow_bloom = .06
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for i in 7: env.set_glow_level(i, 1.0 if i in ([1, 3, 5] if level == 2 else [2, 4]) else 0.0)
	apply_grade()

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

## A ring that bends the frame outward as it spreads from a world point.
static func wave(at: Vector3, radius: float, power := 1.0) -> void:
	if current == null or not is_instance_valid(current) or Look.quality() == 0: return
	if current.waves.size() >= MAX_WAVES: current.waves.pop_front()
	current.waves.append({"at": at, "age": 0.0, "reach": clampf(radius * .045, .06, .3), "power": power * (1.0 if Look.quality() == 2 else .7)})

func _process(delta: float) -> void:
	if material.shader != post_shader: return
	var camera: Camera3D = game.camera
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	material.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))
	var packed: Array = []
	for w in waves: w.age += delta
	waves = waves.filter(func(w): return w.age < WAVE_LIFE)
	for i in MAX_WAVES:
		if i < waves.size() and is_instance_valid(camera):
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
		for source in game.heat_sources(MAX_HEAT):
			var at = camera.unproject_position(source.at) / size
			hot.append(Vector4(at.x, at.y, source.reach * .045, source.power * shimmer))
	while hot.size() < MAX_HEAT: hot.append(Vector4.ZERO)
	material.set_shader_parameter("heat", PackedVector4Array(hot))
	material.set_shader_parameter("grain", .02 if Look.quality() == 2 else .012)
