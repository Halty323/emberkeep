extends DungeonEnemy
## A crystal that drinks embers and throws them back as a fan a moment
## later. A dash through it shatters it: it is badly hurt, takes shots for a
## while, and leaves glass on the floor. Blasts and burning hurt it as ever.
const HOLD := .9
const MOST := 6
const CRACKED := 4.0
var stored = 0
var release = 0.0
var cracked = 0.0
var crystal: MeshInstance3D

func stats() -> Array:
	return [40, 1.2, .5, "bfe6ff"]

func eye_height() -> float:
	return .9

func build_body(light: Dictionary) -> void:
	crystal = Geo.box(visual, Vector3(0, .8, 0), Vector3(.62, 1.3, .62), color, maxf(.4, light.foe_body))
	crystal.rotation_degrees = Vector3(0, 45, 0)
	crystal.material_override = crystal_material()

static func crystal_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(.75, .9, 1.0, .72)
	mat.emission_enabled = true
	mat.emission = Color(.55, .8, 1.0)
	mat.emission_energy_multiplier = .5
	mat.roughness = .1
	return mat

func catch_shot(shot: EmberShot) -> bool:
	if cracked > 0: return false
	stored = mini(stored + 1, MOST)
	if release <= 0: release = HOLD
	shot.remove()
	visual.scale = Vector3.ONE * (1.0 + stored * .04)
	Effects.play("impact", shot.global_position, Color("e8f6ff"))
	return true

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	cracked = maxf(0.0, cracked - delta)
	if release > 0:
		release -= delta * tempo()
		if release <= 0 or stored >= MOST:
			shoot_fan(direction, maxi(3, stored), .9, 7.5)
			stored = 0
			release = 0.0
	var move = steer_toward(game.player.global_position, delta)
	return move * (.7 if distance > 4.0 else -.4)

func dashed_through() -> void:
	super.dashed_through()
	if cracked > 0: return
	cracked = CRACKED
	stored = 0
	release = 0.0
	if game.residue: game.residue.add("glass", global_position, 1.6)
	Audio.play_sound("hurt", 1.4)
	take_hit(max_hp * .5, Vector3.ZERO, false, false, "dash")

func on_death() -> void:
	if game.residue: game.residue.add("glass", global_position, 1.4)
