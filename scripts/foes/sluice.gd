extends DungeonEnemy
## The Sluice Mother, who keeps the drowned cistern. She opens the sluices
## and the room floods, all but a few dry islands around the lanterns; under
## the flood she cannot be struck, and she lunges at anyone wading. When the
## water drains she is stranded and thrashing, open to everything. Lightning
## in the flood reaches her anyway, and frost that locks the water around her
## pins her fast. From half health she spits jets while she swims.
const FLOOD := 8.5
const DRAIN := 6.0
const ISLAND := 2.0
const LUNGE_REACH := 3.0
const THRASH := 2.6
const PINNED := 3.0
const MAX_LURKERS := 3
var state = "drained"
var state_time = 3.0
var flooded: Dictionary = {}
var thrash = 1.5
var spit = 2.5
var pinned = 0.0
var pin_cooldown = 0.0
var ripple: MeshInstance3D
var body: MeshInstance3D

func is_boss() -> bool:
	return true

func stats() -> Array:
	return [280, 1.7, .95, "4f7f86"]

func eye_height() -> float:
	return .7

func build_body(light: Dictionary) -> void:
	body = Geo.box(visual, Vector3(0, .55, 0), Vector3(1.4, .9, 2.6), color, light.foe_body)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geo.box(visual, Vector3(0, .5, 1.8), Vector3(.8, .6, 1.2), color.darkened(.2), light.foe_body)
	Geo.box(visual, Vector3(0, 1.08, -.2), Vector3(.12, .3, 1.8), Color("8ab8b0"), light.foe_body)

func prepare() -> void:
	ripple = Geo.ring(self, Vector3(0, .05, 0), 1.4, Color("a8d8e0"), .05)
	ripple.visible = false

func submerged() -> bool:
	return state == "flood" and pinned <= 0 and charge_time <= 0 and windup <= 0

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	state_time -= delta
	pin_cooldown = maxf(0, pin_cooldown - delta)
	if state == "drained" and state_time <= 0: open_sluices()
	elif state == "flood" and state_time <= 0: drain()
	if pinned > 0:
		# Frozen fast at the surface, and open to everything.
		pinned -= delta
		targetable = true
		visual.visible = true
		ripple.visible = false
		visual.rotation.z = sin(age * 20.0) * .05
		if pinned <= 0: pin_cooldown = 4.0
		return Vector3.ZERO
	visual.rotation.z = 0.0
	var hidden = submerged()
	targetable = not hidden
	visual.visible = not hidden
	ripple.visible = hidden
	if state == "drained":
		exposed = true
		thrash -= delta
		if thrash <= 0:
			thrash = 2.0
			tail_sweep()
		return Vector3.ZERO
	# Locked in ice where she swims.
	if game.residue.kind_at(global_position) == "ice" and pin_cooldown <= 0:
		pinned = PINNED
		game.ui.notify("The Sluice Mother is frozen in", "Strike while the ice holds.", Color("e0a18b"))
		return Vector3.ZERO
	if hp <= max_hp * .5:
		spit -= delta
		if spit <= 0:
			spit = 2.4
			for i in 8:
				var d = Vector3.RIGHT.rotated(Vector3.UP, TAU * i / 8.0 + age)
				game.spawn_shot(global_position + Vector3.UP * .5 + d * 1.2, d, 1, 4.8, {}, Color("9fd8e0"), false)
	if windup > 0 or charge_time > 0: return Vector3.ZERO
	var wading = game.residue.kind_at(game.player.global_position) == "water"
	if wading and distance < LUNGE_REACH and timer <= 0:
		timer = 2.2
		begin_windup(direction, .5, 1.4, Color("a8d8e0"))
		return Vector3.ZERO
	ripple.scale = Vector3.ONE * (1.0 + .1 * sin(age * 5.0))
	return steer_toward(game.player.global_position, delta) * (1.2 if wading else .5)

func charge_length() -> float:
	return .45

func charge_speed() -> float:
	return 8.5

## Water over everything but the islands around the lanterns. What the
## floor held before is kept, so draining gives it back.
func open_sluices() -> void:
	state = "flood"
	state_time = FLOOD
	exposed = false
	var islands: Array = game.room.lanterns.map(func(lantern): return Vector2(lantern.at.x, lantern.at.z))
	var field: ResidueField = game.residue
	for tile in field.floor_tiles():
		var at = ResidueField.center(tile)
		if islands.any(func(point): return point.distance_to(Vector2(at.x, at.z)) < ISLAND): continue
		if flooded.has(tile) or field.tiles.has(tile) and field.tiles[tile].kind == "water": continue
		flooded[tile] = field.tiles.get(tile, {}).get("kind", "")
		field.set_tile(tile, "water", true)
	var lurkers = game.enemies.filter(func(enemy): return is_instance_valid(enemy) and enemy.alive and enemy.kind == "lurker").size()
	for i in mini(2, MAX_LURKERS - lurkers):
		game.spawn_enemy(global_position + Vector3((i * 2 - 1) * 2.5, 0, 1.5), "lurker")
	game.shake = maxf(game.shake, .15)
	Audio.play_sound("door", .6)
	game.ui.notify("The sluices open", "Keep to the dry stone around the lanterns.", Color("9fd8e0"))

func drain() -> void:
	state = "drained"
	state_time = DRAIN
	thrash = 1.0
	var field: ResidueField = game.residue
	for tile in flooded:
		if field.tiles.has(tile) and field.tiles[tile].kind in ["water", "ice"]: field.set_tile(tile, flooded[tile], true)
	flooded.clear()
	if alive: game.ui.notify("The water drains away", "She is stranded. Strike now.", Color("9fd8e0"))

func tail_sweep() -> void:
	Effects.ring_burst(game.scene_root, global_position, Color("a8d8e0"), THRASH)
	game.shake = maxf(game.shake, .1)
	if game.player.global_position.distance_to(global_position) < THRASH: game.player.hurt(1.0, global_position)

func damage_scale(_cause: String) -> float:
	return 1.5 if pinned > 0 else 1.0

func footing_drag() -> float:
	return 1.0

func update_light_state() -> void:
	exposed = state == "drained" or pinned > 0

## Lightning in the flood finds her under the water.
func shocked(damage: float) -> void:
	var was = targetable
	targetable = true
	take_hit(damage * 1.5, Vector3.ZERO, false, false, "shot")
	targetable = was if alive else false

func on_death() -> void:
	drain()
