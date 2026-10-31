extends DungeonEnemy
## The scenery of a fight. A shackle post holds the Shackled's chain until it
## is shot down. A dropped lantern keeps burning where its Lampwright fell and
## bursts when shot. A cinder ember kindles a new Cinderling three seconds
## after one falls, unless the player steps on it first.
const REKINDLE := 3.0
var prisoner: DungeonEnemy
var generation = 1

func stats() -> Array:
	return {"shackle_post": [30, 0.0, .35, "5a5550"], "dropped_lantern": [1, 0.0, .3, "f7bb6d"], "ember": [1, 0.0, .25, "ff9a4a"]}[kind]

func build_body(light: Dictionary) -> void:
	match kind:
		"shackle_post":
			Geo.cylinder(visual, Vector3(0, .55, 0), .22, 1.1, color, light.foe_body)
			Geo.ring(visual, Vector3(0, .9, 0), .28, Color("4f4a44"), .07)
		"dropped_lantern":
			Geo.box(visual, Vector3(0, .3, 0), Vector3(.42, .5, .42), color, 1.2)
			Geo.box(visual, Vector3(0, .6, 0), Vector3(.5, .1, .5), Color("826d51"))
		"ember":
			Geo.sphere(visual, Vector3(0, .18, 0), radius, color, 1.6)

func prepare() -> void:
	contact_damage = false
	eyes.visible = false
	match kind:
		"shackle_post", "dropped_lantern":
			inert = true
		"ember":
			targetable = false
			timer = REKINDLE
	# A lantern on the floor bursts at the first hit, on any floor.
	if kind in ["dropped_lantern", "ember"]:
		max_hp = 1.0
		hp = 1.0
	if kind == "dropped_lantern":
		set_meta("reach", 3.2)
		game.room.extra_lights.append(self)

func moves() -> bool:
	return false

func turns() -> bool:
	return false

func update_light_state() -> void:
	exposed = false

func behave(delta: float, distance: float, _direction: Vector3) -> Vector3:
	if kind == "ember":
		visual.scale = Vector3.ONE * (1.0 + .25 * sin(age * 9.0))
		if distance < .8:
			Effects.play("death_puff", global_position, Color("5a4a3a"), 6)
			die()
		elif timer <= 0:
			rekindle()
	return Vector3.ZERO

func rekindle() -> void:
	alive = false
	var flame: DungeonEnemy = game.spawn_enemy(global_position, "cinderling")
	flame.generation = generation
	flame.hp = flame.max_hp * .6
	Effects.burst(game.scene_root, global_position + Vector3.UP * .4, color, 10, 1.4)
	queue_free()

func on_death() -> void:
	match kind:
		"shackle_post":
			if is_instance_valid(prisoner) and prisoner.alive: prisoner.post_broken()
		"dropped_lantern":
			game.room.extra_lights.erase(self)
			game.blast(global_position, 2.6, 25.0, true, self)
			Audio.play_sound("kill", .5)
