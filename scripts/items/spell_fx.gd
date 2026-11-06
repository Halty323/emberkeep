class_name SpellFx
extends RefCounted
## What each spellbook does to the frame and the floor. Two layers:
## - Warps on the whole frame (ScreenFx: shockwaves bending it, swirls
##   twisting it, frost creeping in from the edges, a flash of colour, the
##   colours splitting at the edges, air shimmering). They need the full
##   post pass, so they show on desktops and most phones but not on the
##   PowerVR safe path, where they quietly do nothing.
## - Shockwave rings racing over the floor (SpellShapes.shock), drawn by
##   every renderer.
## Each element has its own signature when cast and when it lands, each kind
## of spell its own when it strikes, and each eruption its own when it rises.
## Whole-frame marks answer only what happens close in front of the eye.
const NEAR := 14.0
const IMPACT_GAP := .12
static var last_impact: Dictionary = {}

static func near(game: Node, at: Vector3) -> bool:
	var camera: Camera3D = game.camera
	return is_instance_valid(camera) and not camera.is_position_behind(at) and camera.global_position.distance_to(at) < NEAR

static func element_of(stats: Dictionary) -> String:
	return str(stats.get("element", ""))

## Leaving the book.
static func cast(game: Node, stats: Dictionary, origin: Vector3, aim: Vector3) -> void:
	match SpellForms.archetype(stats):
		"ray":
			ScreenFx.split(.3)
			return
		"lightning":
			ScreenFx.flash(Color(.8, .78, 1.0), .035, .12)
			return
		"eruption": return
	match element_of(stats):
		"ember": ScreenFx.shimmer(origin + aim * 1.4, 1.0, .7, .25)
		"frost": ScreenFx.frost(.16)
		"storm": ScreenFx.split(.22)
		"radiance": ScreenFx.flash(Color("ffe5b5"), .045, .12)
		"glass": ScreenFx.split(.14)
		"wax": ScreenFx.shimmer(origin + aim * 1.2, .8, .4, .2)

## A flying spell landing (a foe or a wall): its element's mark, now and then.
static func impact(shot: Node3D, at: Vector3) -> void:
	var element := element_of(shot.stats)
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(last_impact.get(element, -1.0)) < IMPACT_GAP: return
	last_impact[element] = now
	var game: Node = shot.game
	var floor_at := ground(game, at)
	var color: Color = shot.tint
	match element:
		"ember":
			ScreenFx.shimmer(at, 1.2, .9, .5)
			SpellShapes.shock(shot, floor_at, .9, color, .3)
		"frost":
			SpellShapes.shock(shot, floor_at, 1.1, color.lightened(.3), .4)
			if near(game, at): ScreenFx.frost(.08)
		"storm":
			ScreenFx.split(.18)
			SpellShapes.shock(shot, floor_at, 1.0, color, .22, 1.6)
		"venom":
			ScreenFx.swirl(at, 1.6, 1.1, .5)
			SpellShapes.shock(shot, floor_at, .8, color, .45)
		"radiance":
			if near(game, at): ScreenFx.flash(color, .04, .1)
			SpellShapes.shock(shot, floor_at, 1.1, color, .3)
		"glass":
			ScreenFx.wave(at, 1.8, .55)
			ScreenFx.split(.12)
			SpellShapes.shock(shot, floor_at, .9, color.lightened(.3), .3, 1.6)
		"wax":
			ScreenFx.shimmer(at, .9, .5, .35)
			SpellShapes.shock(shot, floor_at, .7, color, .35)
		"tide":
			ScreenFx.wave(at, 2.4, .7)
			SpellShapes.shock(shot, floor_at, 1.2, color, .5)
			SpellShapes.shock(shot, floor_at, .7, color, .4)

## Lightning landing: a flash, the colours torn, the frame kicked, a ring.
static func strike(shot: Node3D, at: Vector3) -> void:
	var game: Node = shot.game
	var sky := float(shot.stats.get("sky", 0)) > 0
	if near(game, at):
		ScreenFx.flash(Color(.85, .82, 1.0), .2 if sky else .12, .18)
		ScreenFx.split(.6 if sky else .4)
	ScreenFx.wave(at, 2.6 if sky else 2.0, 1.0 if sky else .7)
	SpellShapes.shock(shot, ground(game, at), 2.4 if sky else 1.6, shot.tint, .35, 1.8)

## A ray's path: the air ripples along it for a moment.
static func beam(shot: Node3D, path: Array) -> void:
	if path.size() < 2: return
	var a: Vector3 = path[0]
	var b: Vector3 = path.back()
	for i in 3:
		ScreenFx.shimmer(a.lerp(b, (i + 1) / 4.0), .7, .55, .22)

## What rises from an eruption, each its own way.
static func rise(shot: Node3D, at: Vector3, rising: int, radius: float) -> void:
	var game: Node = shot.game
	var close := near(game, at + Vector3.UP)
	var color: Color = shot.tint
	var kind: String = SpellShapes.RISINGS[clampi(rising, 0, SpellShapes.RISINGS.size() - 1)]
	SpellShapes.shock(shot, at, radius * 1.6, color, .5, 1.5)
	match kind:
		"flame":
			ScreenFx.wave(at + Vector3.UP * .5, radius * 2.0, 1.0)
			ScreenFx.shimmer(at + Vector3.UP, radius * 1.4, 1.0, .9)
		"ice":
			ScreenFx.wave(at + Vector3.UP * .5, radius * 1.6, .6)
			if close: ScreenFx.frost(.35)
		"skyfall":
			ScreenFx.wave(at + Vector3.UP * .5, radius * 2.2, 1.0)
			if close:
				ScreenFx.flash(Color(.85, .82, 1.0), .18, .2)
				ScreenFx.split(.5)
		"bubbles":
			ScreenFx.swirl(at + Vector3.UP * .5, radius * 2.2, 1.7, .75)
		"pillar":
			ScreenFx.wave(at + Vector3.UP, radius * 1.8, .8)
			if close: ScreenFx.flash(color, .14, .3)
		"crystal":
			ScreenFx.wave(at + Vector3.UP * .5, radius * 1.8, .7)
			if close: ScreenFx.split(.5)
		"geyser":
			ScreenFx.wave(at + Vector3.UP * .5, radius * 1.8, .9)
			ScreenFx.shimmer(at + Vector3.UP * 1.2, radius, .7, .6)
		"spout":
			ScreenFx.wave(at + Vector3.UP * .5, radius * 2.2, 1.0)
			SpellShapes.shock(shot, at, radius * 1.0, color, .6, 1.0)
		"meteor":
			ScreenFx.wave(at + Vector3.UP * .5, radius * 2.8, 1.6)
			ScreenFx.shimmer(at + Vector3.UP, radius * 1.6, 1.0, 1.0)
			SpellShapes.shock(shot, at, radius * 2.4, color, .7, 2.0)
			if close:
				ScreenFx.flash(color, .22, .25)
				ScreenFx.split(.4)

## The floor beneath a point, for rings.
static func ground(game: Node, at: Vector3) -> Vector3:
	if not game.first_person or not is_instance_valid(game.room): return Vector3(at.x, 0, at.z)
	return Vector3(at.x, game.room.floor_height(at), at.z)
