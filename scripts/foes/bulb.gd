extends DungeonEnemy
## One of the Mosskeeper's three bulbs, joined to the sunken heart by a vine.
## It never simply dies: it wilts, and grows back after three seconds unless
## the other two wilt in that time.
const REGROW := 3.0
var heart: DungeonEnemy
var wilted = 0.0
var finishing = false
var vine: MeshInstance3D
var bloom: MeshInstance3D
var bloom_material: Material

func stats() -> Array:
	return [70, 0.0, .55, "9bc46a"]

func eye_height() -> float:
	return .75

func build_body(light: Dictionary) -> void:
	Geo.cylinder(visual, Vector3(0, .3, 0), .18, .6, Color("5d7a3a"), light.foe_body)
	bloom = Geo.sphere(visual, Vector3(0, .75, 0), radius, color, maxf(.3, light.foe_body))
	bloom_material = bloom.material_override

func prepare() -> void:
	timer = 1.0 + float(entity_id % 3) * .6
	vine = Geo.box(game.scene_root, Vector3.ZERO, Vector3(.12, .12, 1.0), Color("5d7a3a"))
	vine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func moves() -> bool:
	return false

func behave(delta: float, _distance: float, direction: Vector3) -> Vector3:
	if is_instance_valid(heart) and is_instance_valid(vine):
		stretch(vine, global_position + Vector3.UP * .3, heart.global_position + Vector3.UP * .3)
	if wilted > 0:
		wilted -= delta
		# The window shows as the bulb lifts again.
		visual.scale = Vector3(1.0, .35 + .65 * (1.0 - wilted / REGROW), 1.0)
		if wilted <= 0: regrow()
		return Vector3.ZERO
	if timer <= 0:
		shoot_fan(direction, 3, .6, 5.5)
		timer = 2.2
	return Vector3.ZERO

func allow_death() -> bool:
	if finishing: return true
	if wilted <= 0: wilt()
	return false

func wilt() -> void:
	wilted = REGROW
	targetable = false
	contact_damage = false
	bloom.material_override = Geo.material(Color("6b6a4e"))
	Effects.burst(game.scene_root, global_position + Vector3.UP * .7, Color("b8c98a"), 8)
	if is_instance_valid(heart): heart.bulb_wilted()

func regrow() -> void:
	hp = max_hp * .5
	targetable = true
	contact_damage = true
	bloom.material_override = bloom_material
	visual.scale = Vector3.ONE
	Effects.burst(game.scene_root, global_position + Vector3.UP * .7, color, 8)

func finish_off() -> void:
	finishing = true
	targetable = true
	hp = 0.0
	die()

func on_death() -> void:
	if is_instance_valid(vine): vine.queue_free()
