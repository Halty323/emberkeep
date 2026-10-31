extends DungeonEnemy
## Rooted plants that grow in pairs, joined by a thorny vine that hurts to
## touch. Kill one and the other rages; kill both within two seconds of each
## other and a little extra falls.
const BOTH_WINDOW := 2.0
var partner: DungeonEnemy
var vine: MeshInstance3D
var enraged = false
var partner_fell_at = -100.0

func stats() -> Array:
	return [22, 0.0, .42, "6f8a4e"]

func eye_height() -> float:
	return .82

func build_body(light: Dictionary) -> void:
	Geo.cylinder(visual, Vector3(0, .35, 0), .14, .7, Color("4f6b37"), light.foe_body)
	Geo.sphere(visual, Vector3(0, .82, 0), radius, color, light.foe_body)

func prepare() -> void:
	timer = 1.6 + float(entity_id % 3) * .45

func moves() -> bool:
	return false

func bind_partner(other: DungeonEnemy) -> void:
	partner = other
	other.partner = self
	vine = Geo.box(game.scene_root, Vector3.ZERO, Vector3(.1, .1, 1.0), Color("5d7a3a"))
	vine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func behave(_delta: float, _distance: float, direction: Vector3) -> Vector3:
	if is_instance_valid(vine) and is_instance_valid(partner) and partner.alive:
		var a: Vector3 = global_position + Vector3.UP * .45
		var b: Vector3 = partner.global_position + Vector3.UP * .45
		stretch(vine, a, b)
		var chest: Vector3 = game.player.global_position + Vector3.UP * .45
		if Geometry3D.get_closest_point_to_segment(chest, a, b).distance_to(chest) < .4:
			game.player.hurt(1.0, Geometry3D.get_closest_point_to_segment(chest, a, b))
	if timer <= 0:
		if enraged:
			shoot_fan(direction, 3, .5, 6.0)
			timer = 1.5
		else:
			shoot_fan(direction, 1, 0.0, 5.5)
			timer = 2.6
	return Vector3.ZERO

func enrage() -> void:
	enraged = true
	partner_fell_at = game.sim_time
	if is_instance_valid(vine): vine.queue_free()
	visual.scale = Vector3.ONE * 1.2
	Effects.burst(game.scene_root, global_position + Vector3.UP * .8, Color("c8e08a"), 8)

func on_death() -> void:
	if is_instance_valid(vine): vine.queue_free()
	if is_instance_valid(partner) and partner.alive:
		partner.enrage()
	elif enraged and game.sim_time - partner_fell_at <= BOTH_WINDOW and source != "":
		var data: Dictionary = Run.rooms[Run.current_room]
		var key = source + ":pair"
		if key in data.get("credited", []): return
		if not data.has("credited"): data.credited = []
		data.credited.append(key)
		game.spawn_pickup(global_position, "silver_coin")
		Effects.play("discovery_glint", global_position + Vector3.UP * .6)
