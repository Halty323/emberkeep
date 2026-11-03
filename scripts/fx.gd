class_name Effects
extends Node3D
## Facade over the current room's EffectsPool. Callers keep their simple
## calls; budgets, recycling and culling happen in the pool. With no room
## loaded (nothing to see) every call is a no-op.

static func play(recipe: String, at: Vector3, tint := Color(0, 0, 0, 0), amount := -1, strength := 1.0, direction := Vector3.ZERO) -> int:
	# The co-op host's shared world is seen by every guest.
	NetHooks.fx("play", [recipe, at, tint, amount, strength, direction])
	var pool = EffectsPool.current
	if pool == null or not is_instance_valid(pool):
		return 0
	return pool.emit(recipe, at, tint, amount, strength, direction)

static func burst(_parent: Node3D, at: Vector3, color: Color, count := 6, strength := 1.0) -> void:
	play("burst", at, color, count, strength)

## A ring on the floor, and the frame bending outward with it.
static func ring_burst(_parent: Node3D, at: Vector3, color: Color, radius: float) -> void:
	NetHooks.fx("ring", [at, color, radius])
	var pool = EffectsPool.current
	if pool != null and is_instance_valid(pool):
		pool.ring(at, color, radius)
	ScreenFx.wave(at, radius, .8)

static func beam(_parent: Node3D, a: Vector3, b: Vector3, color: Color) -> void:
	NetHooks.fx("beam", [a, b, color])
	var pool = EffectsPool.current
	if pool != null and is_instance_valid(pool):
		pool.beam(a, b, color)
