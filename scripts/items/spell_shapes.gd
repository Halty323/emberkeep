class_name SpellShapes
extends RefCounted
## The shapes a spell takes beyond a flying orb: the beam a ray leaves along
## its path, a lightning bolt's jagged line, the rune that glows where
## something will rise from the floor, and what rises (each element its own
## way: flame tongues, ice spikes, a sky bolt, venom bubbles, a pillar of
## light, crystal shards, a wax geyser, a waterspout). Pieces belong to the
## spell that made them (EmberShot.fx) and play out on its clock after the
## spell itself has struck, so the light outlives the blow by a moment.
##
## A piece: {"node", "life", "age", "grow", "scale" (target), "drift"
## (velocity), "fall" (gravity), "flicker", "fade" (beams and runes keep
## their brightness in the basis's Y)}.
static var beam_mesh: QuadMesh
static var rune_mesh: PlaneMesh
static var materials: Dictionary = {}
static var meshes: Dictionary = {}
# Eruptions, in the order of Forge.ELEMENTS.
const RISINGS := ["flame", "ice", "skyfall", "bubbles", "pillar", "crystal", "geyser", "spout"]

static func material(shader: String, color: Color) -> ShaderMaterial:
	var key := shader + color.to_html()
	if not materials.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/%s.gdshader" % shader)
		mat.set_shader_parameter("tint", color)
		materials[key] = mat
	return materials[key]

static func piece(shot: Node3D, mesh: Mesh, mat: Material, at: Transform3D, life: float, extra: Dictionary = {}) -> Dictionary:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.layers = 2
	node.top_level = true
	node.extra_cull_margin = 2.0
	shot.add_child(node)
	node.global_transform = at
	var entry := {"node": node, "life": life, "age": 0.0, "base": at}
	entry.merge(extra, true)
	shot.fx.append(entry)
	return entry

## A stretch of beam from a to b; width in metres.
static func span(shot: Node3D, a: Vector3, b: Vector3, width: float, color: Color, life: float, brightness := 1.0, flicker := false) -> Dictionary:
	if not beam_mesh:
		beam_mesh = QuadMesh.new()
		beam_mesh.size = Vector2.ONE
	var reach := b - a
	if reach.length() < .02: reach = Vector3(0, 0, .02)
	var up := Vector3.UP if absf(reach.normalized().y) < .95 else Vector3.RIGHT
	var basis := Basis(reach, up * brightness, reach.normalized().cross(up).normalized() * width)
	return piece(shot, beam_mesh, material("shot_beam", color), Transform3D(basis, (a + b) / 2.0), life, {"beam": brightness, "width": width, "flicker": flicker})

## A ray's light along the path it really took (bends and ricochets too).
static func ray(shot: Node3D, path: Array, color: Color, size: float) -> void:
	var width := .13 + .1 * size
	for i in path.size() - 1:
		span(shot, path[i], path[i + 1], width, color, .26, 2.6)
		span(shot, path[i], path[i + 1], width * 3.6, color, .32, .7)

## A lightning bolt: a jagged line with a branch or two, flickering out.
static func bolt(shot: Node3D, a: Vector3, b: Vector3, color: Color, gen: RandomNumberGenerator, branches := 2) -> void:
	var points := jagged(a, b, gen, .32)
	for i in points.size() - 1:
		span(shot, points[i], points[i + 1], .09, color, .28, 3.0, true)
		span(shot, points[i], points[i + 1], .36, color, .32, .8, true)
	for j in branches:
		if points.size() < 4: break
		var from: Vector3 = points[gen.randi_range(1, points.size() - 2)]
		var away := (b - a).normalized().rotated(Vector3.UP, gen.randf_range(-1.1, 1.1)) * gen.randf_range(.6, 1.4) + Vector3(0, gen.randf_range(-.5, .3), 0)
		var twig := jagged(from, from + away, gen, .15)
		for i in twig.size() - 1:
			span(shot, twig[i], twig[i + 1], .06, color, .2, 2.0, true)

static func jagged(a: Vector3, b: Vector3, gen: RandomNumberGenerator, roughness: float) -> Array:
	var reach := b - a
	var steps := clampi(int(reach.length() / .6), 3, 16)
	var side := reach.cross(Vector3.UP).normalized()
	if side.length_squared() < .01: side = Vector3.RIGHT
	var lift := side.cross(reach).normalized()
	var points: Array = [a]
	for i in range(1, steps):
		var t := float(i) / steps
		var sway := sin(t * PI) * roughness
		points.append(a + reach * t + side * gen.randf_range(-sway, sway) + lift * gen.randf_range(-sway, sway))
	points.append(b)
	return points

## The rune glowing where something is about to rise.
static func rune(shot: Node3D, at: Vector3, radius: float, color: Color, life: float) -> Dictionary:
	if not rune_mesh:
		rune_mesh = PlaneMesh.new()
		rune_mesh.size = Vector2.ONE
	var basis := Basis(Vector3.RIGHT * radius * 2.0, Vector3.UP * .01, Vector3.BACK * radius * 2.0)
	return piece(shot, rune_mesh, material("spell_rune", color), Transform3D(basis, at + Vector3.UP * .05), life, {"rune": true})

static func shape(kind: String, a: float, b: float) -> Mesh:
	var key := "%s:%.2f:%.2f" % [kind, a, b]
	if meshes.has(key): return meshes[key]
	var mesh: Mesh
	match kind:
		"cone":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = a
			cone.height = b
			cone.radial_segments = 7
			cone.rings = 1
			mesh = cone
		"column":
			var column := CylinderMesh.new()
			column.top_radius = a
			column.bottom_radius = a * .8
			column.height = b
			column.radial_segments = 12
			column.rings = 1
			mesh = column
		"prism":
			var prism := CylinderMesh.new()
			prism.top_radius = 0.0
			prism.bottom_radius = a
			prism.height = b
			prism.radial_segments = 4
			prism.rings = 1
			mesh = prism
		_:
			var ball := SphereMesh.new()
			ball.radius = a
			ball.height = a * 2.0
			ball.radial_segments = 10
			ball.rings = 6
			mesh = ball
	meshes[key] = mesh
	return mesh

## Something rises from the floor at `at`, as its element would.
static func erupt(shot: Node3D, at: Vector3, radius: float, element: int, color: Color, gen: RandomNumberGenerator) -> void:
	var glow: Material = EmberShot.material("core", color.lightened(.15))
	var pale: Material = EmberShot.material("core", color.lightened(.45))
	var kind: String = RISINGS[clampi(element, 0, RISINGS.size() - 1)]
	rune(shot, at, radius, color, .5)["burst"] = true
	match kind:
		"flame":
			# Tongues of flame licking up and out, the tallest in the middle.
			for i in 7:
				var spot := ring_point(at, radius * (.0 if i == 0 else .55), i, 6, gen)
				var tall := gen.randf_range(1.0, 1.6) * (1.3 if i == 0 else 1.0)
				var tilt := Basis(Vector3.FORWARD.rotated(Vector3.UP, gen.randf() * TAU), gen.randf_range(.0, .25))
				lift(shot, shape("cone", .17, 1.0), EmberShot.material("core", color), Transform3D(tilt.scaled(Vector3(1, tall, 1)), spot + Vector3.UP * tall * .5), .55, .1, Vector3.UP * .8)
		"ice", "crystal":
			# Spikes thrust up at angles and hold a moment before they melt.
			var count := 8 if kind == "ice" else 10
			var mesh: Mesh = shape("cone", .16, 1.0) if kind == "ice" else shape("prism", .12, 1.0)
			for i in count:
				var spot := ring_point(at, radius * gen.randf_range(.1, .8), i, count, gen)
				var out := (spot - at)
				out.y = 0
				var axis := Vector3.UP.cross(out.normalized()) if out.length() > .05 else Vector3.RIGHT
				var tall := gen.randf_range(.8, 1.5) * (1.25 if kind == "crystal" else 1.0)
				var basis := Basis(axis.normalized(), gen.randf_range(.15, .55)).scaled(Vector3(1, tall, 1))
				lift(shot, mesh, pale if kind == "ice" else glow, Transform3D(basis, spot + basis.y * .45), .75, .07)
		"skyfall":
			# Lightning from the dark overhead onto the spot.
			var top := at + Vector3(gen.randf_range(-.4, .4), 3.4, gen.randf_range(-.4, .4))
			bolt(shot, top, at + Vector3.UP * .05, color, gen, 3)
			lift(shot, shape("ball", .5, 0.0), pale, Transform3D(Basis.IDENTITY.scaled(Vector3(radius * 1.4, .25, radius * 1.4)), at + Vector3.UP * .1), .3, .04)
		"bubbles":
			# Venom boils up in bubbles that swell and burst.
			for i in 8:
				var spot := ring_point(at, radius * gen.randf_range(.0, .75), i, 8, gen)
				var size := gen.randf_range(.22, .42)
				lift(shot, shape("ball", 1.0, 0.0), glow, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), spot + Vector3.UP * size), gen.randf_range(.4, .65), .25, Vector3.UP * gen.randf_range(.4, 1.2))
		"pillar":
			# A shaft of light from floor to ceiling, narrowing as it fades.
			lift(shot, shape("column", 1.0, 1.0), glow, Transform3D(Basis.IDENTITY.scaled(Vector3(radius * .55, 4.0, radius * .55)), at + Vector3.UP * 2.0), .55, .06)
			lift(shot, shape("column", 1.0, 1.0), pale, Transform3D(Basis.IDENTITY.scaled(Vector3(radius * .2, 4.0, radius * .2)), at + Vector3.UP * 2.0), .45, .04)
		"geyser", "spout":
			# A column bursting up, throwing drops (or wax) that fall back.
			var wide := radius * (.42 if kind == "spout" else .34)
			lift(shot, shape("column", 1.0, 1.0), glow, Transform3D(Basis.IDENTITY.scaled(Vector3(wide, 2.2, wide)), at + Vector3.UP * 1.1), .5, .08)
			for i in 9:
				var out := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 9.0 + gen.randf()) * gen.randf_range(1.2, 2.6)
				var drop := gen.randf_range(.09, .17)
				lift(shot, shape("ball", 1.0, 0.0), pale, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * drop), at + Vector3.UP * 1.9), .75, .02, out + Vector3.UP * gen.randf_range(2.0, 3.6), 9.0)

static func ring_point(at: Vector3, distance: float, i: int, count: int, gen: RandomNumberGenerator) -> Vector3:
	return at + Vector3.FORWARD.rotated(Vector3.UP, TAU * i / maxf(1, count) + gen.randf_range(-.3, .3)) * distance

## A piece that springs up from nothing, holds and shrinks away.
## Rooted pieces (spikes, tongues, columns) grow up from their foot.
static func lift(shot: Node3D, mesh: Mesh, mat: Material, at: Transform3D, life: float, grow: float, drift := Vector3.ZERO, fall := 0.0) -> void:
	var rooted := not mesh is SphereMesh
	piece(shot, mesh, mat, at, life, {"grow": grow, "drift": drift, "fall": fall, "root": at.basis.y * .5 if rooted else Vector3.ZERO})

## Plays every piece on; true while any is still showing.
static func animate(shot: Node3D, delta: float) -> bool:
	var showing := false
	for entry in shot.fx:
		var node: MeshInstance3D = entry.node
		if not is_instance_valid(node) or not node.visible: continue
		entry.age += delta
		var t: float = entry.age / entry.life
		if t >= 1.0:
			node.visible = false
			continue
		showing = true
		if entry.has("beam"):
			var flicker := (.55 + .45 * randf()) if entry.get("flicker", false) else 1.0
			var fade := (1.0 - t) * (1.0 - t) * flicker
			var basis: Basis = entry.base.basis
			node.global_transform = Transform3D(Basis(basis.x, basis.y.normalized() * maxf(.001, float(entry.beam) * fade), basis.z * lerpf(1.0, .4, t)), entry.base.origin)
		elif entry.has("rune"):
			var basis: Basis = entry.base.basis
			var charge := 1.0 - t if entry.get("burst", false) else t
			node.global_transform = Transform3D(Basis(basis.x, Vector3.UP * maxf(.001, charge), basis.z), entry.base.origin)
		else:
			var grow: float = maxf(.001, entry.grow)
			var rise := clampf(entry.age / grow, 0.0, 1.0)
			var shrink := clampf((t - .6) / .4, 0.0, 1.0)
			var size := ease(rise, .4) * (1.0 - shrink)
			var drift: Vector3 = entry.get("drift", Vector3.ZERO)
			if entry.get("fall", 0.0) > 0: entry.drift = drift + Vector3.DOWN * float(entry.fall) * delta
			var origin: Vector3 = entry.base.origin + drift * delta
			entry.base = Transform3D(entry.base.basis, origin)
			var root: Vector3 = entry.get("root", Vector3.ZERO)
			node.global_transform = Transform3D(entry.base.basis.scaled(Vector3.ONE * maxf(.001, size)), origin - root * (1.0 - size))
	return showing
