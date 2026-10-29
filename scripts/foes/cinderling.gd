extends DungeonEnemy
## A quick little flame that weaves as it comes. When it falls it leaves an
## ember that kindles a new one three seconds later (twice at most), unless
## the player steps on it first.
const REKINDLES := 2
var generation = 0

func stats() -> Array:
	return [18, 2.6, .34, "f08a4b"]

func build_body(light: Dictionary) -> void:
	Geo.sphere(visual, Vector3(0, .4, 0), radius, color, maxf(.8, light.foe_body))
	Geo.cylinder(visual, Vector3(0, .78, 0), .2, .4, Color("ffc46b"), 1.4, .02)

func behave(delta: float, _distance: float, _direction: Vector3) -> Vector3:
	var move = steer_toward(game.player.global_position, delta)
	return move.rotated(Vector3.UP, sin(age * 4.0 + entity_id) * .6)

func on_death() -> void:
	if game.residue: game.residue.ignite(global_position, .8)
	if generation >= REKINDLES: return
	var ember: DungeonEnemy = game.spawn_enemy(global_position, "ember")
	ember.generation = generation + 1
