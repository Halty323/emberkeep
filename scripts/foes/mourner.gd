extends DungeonEnemy
## A mourner from the crypt. It drifts straight through walls and furniture,
## and it can be seen and struck only inside light: the player's own glow or
## a burning lantern's pool. Its touch takes a heart and the kindle's warmth.
var touch_cooldown = 0.0

func stats() -> Array:
	return [28, 1.35, .42, "c9c0d8"]

func eye_height() -> float:
	return .95

func build_body(light: Dictionary) -> void:
	var body = Geo.cylinder(visual, Vector3(0, .62, 0), .4, 1.1, color, maxf(light.foe_body, .25), .22)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Geo.sphere(visual, Vector3(0, 1.22, 0), .26, color.lightened(.2), maxf(light.foe_body, .3))

func prepare() -> void:
	# Nothing solid stops it.
	collision_mask = 0
	contact_damage = false

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	touch_cooldown = maxf(0, touch_cooldown - delta)
	visual.position.y = .1 + sin(age * 2.0) * .08
	if targetable and distance < radius + .5 and touch_cooldown <= 0:
		touch_cooldown = 1.2
		game.player.hurt(1.0, global_position)
		game.kindle_heat = 0.0
	return direction

func footing_drag() -> float:
	return 1.0

## Light is all that shows it; outside light it cannot be struck either.
func update_light_state() -> void:
	var lit: bool = game.room.lit_at(global_position) or global_position.distance_to(game.player.global_position) <= game.player_light_radius()
	exposed = game.room.lit_at(global_position)
	targetable = lit
	set_shrouded(not lit)
