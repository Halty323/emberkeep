class_name MothCompanion
extends Node3D
## A short-lived friendly moth from the Moth Jar. Its lifetime is the saved
## modifier's remaining time, so it survives room changes and reloads.
var game: Node3D
var slot = 0
var damage = 6.0
var target: Node3D
var retarget = 0.0
var bite_cooldown = 0.0
var age = 0.0
var wings: Array[MeshInstance3D] = []

func setup(owner_game: Node3D, companion_slot: int, bite: float) -> void:
	game = owner_game
	slot = companion_slot
	damage = bite
	Geo.sphere(self, Vector3.ZERO, .11, Color("efe2b4"), 1.1)
	for side in [-1, 1]:
		var wing = Geo.box(self, Vector3(side * .13, 0, 0), Vector3(.2, .02, .14), Color("e7d9a6"), .6)
		wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wings.append(wing)
	Geo.halo(self, Vector3(0, -.55, 0), 1.2, Color(1, .9, .55, .16))

func update_sim(delta: float) -> void:
	age += delta
	retarget -= delta
	bite_cooldown -= delta
	if retarget <= 0:
		retarget = .4
		target = game.nearest_enemy(global_position, 7.0)
	var home: Vector3 = game.player.global_position + Vector3(cos(age * 2.6 + slot * PI) * 1.2, .9, sin(age * 2.6 + slot * PI) * 1.2)
	var goal = home
	if is_instance_valid(target) and target.alive:
		goal = target.global_position + Vector3(0, .6, 0)
		if global_position.distance_to(goal) < target.radius + .3 and bite_cooldown <= 0:
			bite_cooldown = .45
			target.take_hit(damage * Run.stats.damage, Vector3.ZERO, false)
	global_position = global_position.move_toward(goal, delta * 7.5)
	for i in wings.size():
		wings[i].rotation.z = sin(age * 30.0) * .7 * (-1 if i == 0 else 1)
