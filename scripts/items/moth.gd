class_name Moth
extends Node3D
## A short-lived companion from the Moth Jar. It circles the player and darts
## friendly shots at the nearest foe. Moths belong to the room they were
## released in, like live enemies and shots, and leave with it.
const FIRE_INTERVAL := .7
var game: Node3D
var life := 10.0
var damage := 4.0
var phase := 0.0
var cooldown := 0.0

func setup(owner_game: Node3D, slot: int, duration: float, shot_damage: float) -> void:
	game = owner_game
	life = duration
	damage = shot_damage
	phase = PI * slot
	cooldown = FIRE_INTERVAL * (.5 + .5 * slot)
	var body := Geo.sphere(self, Vector3.ZERO, .11, Color("efe2b4"), 1.2)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1, 1]:
		var wing := Geo.box(self, Vector3(side * .16, .02, 0), Vector3(.22, .02, .16), Color("d8c690"), .6)
		wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func alive() -> bool:
	return life > 0

func update_sim(delta: float) -> void:
	life -= delta
	if life <= 0:
		queue_free()
		return
	phase += delta * 2.6
	var center: Vector3 = game.player.global_position if is_instance_valid(game.player) else global_position
	global_position = center + Vector3(cos(phase) * 1.1, .9 + sin(phase * 3.0) * .08, sin(phase) * 1.1)
	cooldown -= delta
	if cooldown > 0: return
	var target: Node3D = null
	var best := 49.0
	for enemy in game.enemies:
		if is_instance_valid(enemy) and enemy.alive:
			var d := global_position.distance_squared_to(enemy.global_position)
			if d < best:
				best = d
				target = enemy
	if target == null: return
	cooldown = FIRE_INTERVAL
	var aim := target.global_position + Vector3.UP * .5 - global_position
	aim.y = 0
	var stats := Run.projectile_stats()
	stats.split = 0
	game.spawn_shot(global_position, aim.normalized(), damage * float(Run.stats.damage), 13.0, stats, Color("f2e4b0"), true)
