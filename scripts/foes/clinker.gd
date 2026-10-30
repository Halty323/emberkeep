extends DungeonEnemy
## A lump of fired clay in a stone shell. Cold, the shell turns most of a
## blow aside; set burning, it glows red, the shell cracks and every blow
## lands, but its touch burns and it bursts when it breaks.
const SHELL := .3
const HOT := 1.25
const BURST := 1.6
var body: MeshInstance3D
var cold_material: Material

func stats() -> Array:
	return [44, 1.25, .5, "6a5a50"]

func build_body(light: Dictionary) -> void:
	body = Geo.box(visual, Vector3(0, .55, 0), Vector3(.95, .9, .95), color, light.foe_body)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	cold_material = body.material_override
	Geo.box(visual, Vector3(0, .98, 0), Vector3(.7, .1, .7), color.darkened(.25), light.foe_body)

func hot() -> bool:
	return burn_time > 0

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	body.material_override = Geo.material(Color("d0603a"), 1.4) if hot() else cold_material
	if windup > 0: return Vector3.ZERO
	if timer <= 0 and distance < 7.0:
		timer = 4.0
		begin_windup(direction, .7, .8, Color("e88a5a"))
		return Vector3.ZERO
	return steer_toward(game.player.global_position, delta)

func charge_speed() -> float:
	return 7.0

func damage_scale(cause: String) -> float:
	if cause == "dot": return 1.0
	return HOT if hot() else SHELL

func after_move(_delta: float, distance: float, _direction: Vector3) -> void:
	if hot() and distance < radius + .5: game.player.hurt(1.0, global_position)

func on_death() -> void:
	if not hot(): return
	Effects.ring_burst(game.scene_root, global_position, Color("ff8a4a"), BURST)
	Effects.burst(game.scene_root, global_position + Vector3.UP * .5, Color("ff9a4a"), 12, 1.5)
	if game.residue: game.residue.scorch(global_position, BURST * .8)
	if game.player.global_position.distance_to(global_position) < BURST: game.player.hurt(1.0, global_position)
