class_name Reliquary
extends RefCounted
## Where a relic waits: a carved octagonal plinth with a brass cradle, and
## above it a faceted crystal floating inside a slowly turning gilt cage with
## three motes circling it. A rune ring is cut into the floor around it.
## Only the floating part moves; the plinth, cradle and light stay still so
## the room's shadow maps can stay cached.
const BRASS := Color("b39159")
const STONE := Color("6c675c")

## Builds the reliquary under `parent` and returns the floating part, which
## the game turns and bobs. `scale` shrinks it for dropped equipment.
static func build(parent: Node3D, glow: Color, first_person: bool, scale := 1.0) -> Node3D:
	var stand := Node3D.new()
	stand.name = "Reliquary"
	stand.scale = Vector3.ONE * scale
	parent.add_child(stand)
	var stone: Material = DungeonStyle.wall_material(STONE) if first_person else Geo.material(STONE)
	var cap_stone: Material = DungeonStyle.wall_material(STONE.lightened(.12), true) if first_person else Geo.material(STONE.lightened(.12))
	# Plinth: a wide foot, an eight-sided shaft and an overhanging cap.
	octagon(stand, Vector3(0, .07, 0), .48, .14, stone)
	octagon(stand, Vector3(0, .5, 0), .3, .72, stone)
	octagon(stand, Vector3(0, .9, 0), .42, .09, cap_stone)
	for i in 8:
		var angle := i * TAU / 8 + TAU / 16
		var rib := Geo.box(stand, Vector3(cos(angle) * .3, .5, sin(angle) * .3), Vector3(.05, .62, .05), STONE.darkened(.15))
		rib.rotation.y = -angle
		rib.material_override = stone
	# A brass cradle: three curved arms meeting under the relic.
	var metal: Material = DungeonStyle.metal_material(BRASS) if first_person else Geo.material(BRASS)
	for i in 3:
		var angle := i * TAU / 3
		var arm := Geo.box(stand, Vector3(cos(angle) * .17, 1.02, sin(angle) * .17), Vector3(.035, .2, .035), BRASS)
		arm.rotation = Vector3(sin(angle) * .45, 0, -cos(angle) * .45)
		arm.material_override = metal
	var ring := Geo.ring(stand, Vector3(0, 1.1, 0), .2, BRASS, .018)
	ring.material_override = metal
	# The rune ring cut into the floor, glowing faintly in the relic's light.
	var floor_ring := Geo.ring(stand, Vector3(0, .02, 0), .95, glow, .02)
	floor_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var inner_ring := Geo.ring(stand, Vector3(0, .02, 0), .78, glow.darkened(.2), .012)
	inner_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 12:
		var angle := i * TAU / 12
		var tick := Geo.glow_box(stand, Vector3(cos(angle) * .865, .022, sin(angle) * .865), Vector3(.05, .004, .015), glow * .6)
		tick.rotation.y = -angle
	Geo.light(stand, Vector3(0, 1.55, 0), glow.lerp(Color("f0c68c"), .5), .55, 3.5)
	# The floating relic: a faceted crystal in a gilt cage, with motes.
	var relic := Node3D.new()
	relic.name = "Relic"
	stand.add_child(relic)
	relic.position = Vector3(0, 1.42, 0)
	relic.set_meta("rest_y", relic.position.y)
	var crystal := MeshInstance3D.new()
	var gem := SphereMesh.new()
	gem.radius = .14
	gem.height = .36
	gem.radial_segments = 6
	gem.rings = 3
	crystal.mesh = gem
	crystal.material_override = Geo.material(glow, .65)
	crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	relic.add_child(crystal)
	for tilt in [Vector3(PI / 2, 0, 0), Vector3(PI / 2, PI / 2, 0), Vector3(0, 0, 0)]:
		var band := Geo.ring(relic, Vector3.ZERO, .23, BRASS.lightened(.15), .012)
		band.rotation = tilt
		band.material_override = Geo.material(BRASS.lightened(.15), .25)
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 3:
		var angle := i * TAU / 3
		var mote := Geo.sphere(relic, Vector3(cos(angle) * .33, sin(angle * 2.0) * .05, sin(angle) * .33), .025, glow.lightened(.4), 2.0)
		mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return relic

## An eight-sided block, flat side out.
static func octagon(parent: Node3D, at: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	node.position = at
	node.rotation.y = TAU / 16
	return node

## The floating part turns, and rises and falls a little.
static func animate(relic: Node3D, time: float, delta: float) -> void:
	relic.rotation.y += delta * .6
	relic.position.y = float(relic.get_meta("rest_y", relic.position.y)) + sin(time * 1.6) * .04
