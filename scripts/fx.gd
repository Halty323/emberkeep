class_name Effects
extends Node3D
## Facade over the current room's EffectPool. Callers describe what happened;
## recipes decide how it looks within the room's budgets. With no room (or a
## freed one) every call is a harmless no-op.
static var active: EffectPool

static func pool() -> EffectPool:
	return active if is_instance_valid(active) else null

## Generic burst kept for existing callers: important feedback.
static func burst(_parent: Node3D, at: Vector3, color: Color, count := 6, strength := 1.0) -> void:
	var p := pool()
	if p == null: return
	p.spray(at, color, count, 3.2 * strength, .11 * strength, .34, EffectPool.Priority.FEEDBACK)

static func ring_burst(_parent: Node3D, at: Vector3, color: Color, radius: float) -> void:
	var p := pool()
	if p: p.ring(at, color, radius)

static func beam(_parent: Node3D, a: Vector3, b: Vector3, color: Color) -> void:
	var p := pool()
	if p: p.beam(a, b, color)

## Restrained muzzle flecks, rate-limited so rapid or multi-pellet weapons
## cannot flood the batch.
static func muzzle(at: Vector3, direction: Vector3, color: Color) -> void:
	var p := pool()
	if p == null or p.muzzle_tokens < 1.0: return
	p.muzzle_tokens -= 1.0
	for i in 2:
		var spread := direction.rotated(Vector3.UP, p.rng.randf_range(-.5, .5))
		p.emit(at + direction * .25, spread * p.rng.randf_range(2.0, 3.5) + Vector3.UP * .4, color.lightened(.3), .05, .12, EffectPool.Priority.ATMOSPHERE, 0.0)

## Chips where a shot stops against a wall or furniture.
static func impact(at: Vector3, color: Color) -> void:
	var p := pool()
	if p == null or p.impact_tokens < 1.0: return
	p.impact_tokens -= 1.0
	p.spray(at, color.darkened(.1), 2, 2.4, .06, .22, EffectPool.Priority.ATMOSPHERE)

static func hit_spark(at: Vector3, color: Color, critical := false) -> void:
	var p := pool()
	if p == null: return
	p.spray(at, Color("ffe0a8") if critical else color.lightened(.25), 4 if critical else 2, 3.6, .07, .18, EffectPool.Priority.FEEDBACK, .3, 1.0)

static func death_puff(at: Vector3, color: Color, big := false) -> void:
	var p := pool()
	if p == null: return
	p.spray(at, color, 9 if big else 6, 3.0 * (1.5 if big else 1.0), .12, .4, EffectPool.Priority.FEEDBACK)
	p.spray(at, Color("6f6a62"), 4 if big else 3, 1.2, .16, .6, EffectPool.Priority.ATMOSPHERE, .9, -.6)
	p.mark(Vector3(at.x, 0, at.z), Color(color.darkened(.5), .45), .55 if big else .35, 5.0)

static func dash_dust(at: Vector3, direction: Vector3) -> void:
	var p := pool()
	if p == null: return
	for i in 5:
		var side := direction.cross(Vector3.UP) * p.rng.randf_range(-1.0, 1.0)
		p.emit(at + Vector3(0, .08, 0), (-direction * 1.6 + side) * p.rng.randf_range(.6, 1.2) + Vector3.UP * .5, Color("8d8473"), .1, .36, EffectPool.Priority.ATMOSPHERE, .4)

static func footstep(at: Vector3) -> void:
	var p := pool()
	if p == null: return
	p.emit(at + Vector3(p.rng.randf_range(-.1, .1), .05, p.rng.randf_range(-.1, .1)), Vector3(0, .5, 0), Color("7d766a"), .06, .3, EffectPool.Priority.ATMOSPHERE, .2)

static func pickup_glint(at: Vector3, color: Color) -> void:
	var p := pool()
	if p == null: return
	p.spray(at, color.lightened(.2), 4, 1.6, .06, .3, EffectPool.Priority.FEEDBACK, 1.2, -.5)

static func prop_dust(at: Vector3, color: Color) -> void:
	var p := pool()
	if p == null: return
	p.spray(at, color, 7, 2.6, .12, .45, EffectPool.Priority.FEEDBACK)
	p.spray(at, Color("8c8476"), 5, .9, .18, .8, EffectPool.Priority.ATMOSPHERE, .6, -.4)

static func chest_open(at: Vector3) -> void:
	var p := pool()
	if p == null: return
	p.spray(at + Vector3.UP * .6, Color("f2d28a"), 10, 2.0, .07, .55, EffectPool.Priority.FEEDBACK, 1.4, 1.5)
	p.ring(at, Color("e8c77a"), 1.2)

## A brief first-discovery glint (paintings), never permanent glitter.
static func discovery_glint(at: Vector3) -> void:
	var p := pool()
	if p == null: return
	p.spray(at, Color("fff1c9"), 6, 1.1, .05, .6, EffectPool.Priority.FEEDBACK, 0.0, 0.0)

## Temporary floor mark (scorch, paint), clipped to the footprint.
static func floor_mark(at: Vector3, color: Color, radius: float, life := 6.0) -> void:
	var p := pool()
	if p: p.mark(at, color, radius, life)
