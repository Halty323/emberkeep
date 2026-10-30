extends DungeonEnemy
## A golem of candle wax. Fire melts it: while it burns it sheds wax, shrinks
## and quickens. Chill sets it hard, turning half of every blow aside but
## slowing it to a crawl. It falls into a great pool of wax.
const SLAM := 1.8
var slam_cooldown = 1.5
var shed = 0.0
var body: MeshInstance3D

func stats() -> Array:
	return [58, 1.0, .62, "d8c39a"]

func eye_height() -> float:
	return 1.15

func build_body(light: Dictionary) -> void:
	body = Geo.box(visual, Vector3(0, .7, 0), Vector3(1.1, 1.4, .95), color, light.foe_body)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geo.cylinder(visual, Vector3(0, 1.55, 0), .08, .3, Color("3a3028"))
	Geo.sphere(visual, Vector3(0, 1.78, 0), .1, Color("ffd890"), 2.0)

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	slam_cooldown -= delta * tempo()
	var melting = burn_time > 0
	# A burning golem runs down: smaller, quicker, dripping as it goes.
	var size = clampf(.55 + .45 * hp / max_hp, .55, 1.0) if melting else visual.scale.x
	visual.scale = visual.scale.lerp(Vector3.ONE * size, delta * 3.0)
	if melting:
		shed -= delta
		if shed <= 0:
			shed = .45
			if game.residue: game.residue.add("wax", global_position, .7)
	if windup > 0: return Vector3.ZERO
	if distance < SLAM + .3 and slam_cooldown <= 0:
		begin_windup(direction, .75, SLAM, Color("e8d6a8"))
		slam_cooldown = 2.4
		return Vector3.ZERO
	return steer_toward(game.player.global_position, delta) * (1.6 if melting else 1.0)

func windup_done() -> void:
	Effects.ring_burst(game.scene_root, global_position, Color("e8d6a8"), SLAM)
	game.shake = maxf(game.shake, .1)
	if game.residue: game.residue.add("wax", global_position, 1.2)
	if game.player.global_position.distance_to(global_position) < SLAM: game.player.hurt(1.0, global_position)

func damage_scale(cause: String) -> float:
	return .5 if chill_time > 0 and cause != "dot" else 1.0

func on_death() -> void:
	if game.residue: game.residue.add("wax", global_position, 2.2)
