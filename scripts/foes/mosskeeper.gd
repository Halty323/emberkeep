extends DungeonEnemy
## The Mosskeeper, a rooted heart in the halls. Missed shots grow moss where
## they land, and moss joined to the heart through its roots heals it; fire
## runs along that moss and burns the heart through those same roots. Below
## 45% it withdraws into three bulbs, which grow back unless all three wilt
## within three seconds of one another.
const ROOT_EVERY := 2.4
const ROOT_WARN := .75
const ROOT_LENGTH := 12.0
const ROOT_REACH := 1.8
const HEAL_PER_TILE := .2
const MOST_HEAL := 4.0
const BURN_HIT := 9.0
const PHASE_TWO := .45
const BULB_RING := 5.5
var phase = 1
var root_line: Dictionary = {}
var heal_tick = 1.0
var burn_tick = .5
var spore = 8.0
var sprout = 14.0
var bulbs: Array = []
var finishing = false
var core: MeshInstance3D

func is_boss() -> bool:
	return true

func stats() -> Array:
	return [300, 0.0, 1.1, "6f9a5a"]

func eye_height() -> float:
	return 1.2

func build_body(light: Dictionary) -> void:
	core = Geo.sphere(visual, Vector3(0, 1.0, 0), radius, color, maxf(.3, light.foe_body))
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for i in 6:
		var petal = Geo.box(visual, Vector3(cos(i * TAU / 6) * 1.1, .35, sin(i * TAU / 6) * 1.1), Vector3(.5, .14, .9), Color("8fbf6a"), light.foe_body)
		petal.rotation.y = -i * TAU / 6
	Geo.ring(self, Vector3(0, .035, 0), 1.6, Color("7aa35a"), .06)

func moves() -> bool:
	return false

func turns() -> bool:
	return false

func health_fraction() -> float:
	if phase == 1: return hp / max_hp
	var total = 0.0
	var most = 0.0
	for bulb in bulbs:
		if is_instance_valid(bulb):
			total += maxf(0.0, bulb.hp) if bulb.wilted <= 0 else 0.0
			most += bulb.max_hp
	return PHASE_TWO * total / maxf(most, 1.0)

func behave(delta: float, _distance: float, direction: Vector3) -> Vector3:
	visual.scale = visual.scale.lerp(Vector3.ONE * (1.0 if phase == 1 else .45), delta * 3.0)
	core.scale = Vector3.ONE * (1.0 + .05 * sin(age * 3.0))
	if phase == 2: return Vector3.ZERO
	# Moss joined to the heart feeds it.
	heal_tick -= delta
	if heal_tick <= 0:
		heal_tick = 1.0
		var linked: int = game.residue.moss_linked(global_position, ROOT_REACH + radius).size() if game.residue else 0
		if linked > 0 and hp < max_hp:
			hp = minf(max_hp, hp + minf(MOST_HEAL, linked * HEAL_PER_TILE))
			Effects.play("pickup", global_position + Vector3.UP * 1.4, Color("9fe07a"))
	# Fire in its roots burns it.
	burn_tick -= delta
	if burn_tick <= 0:
		burn_tick = .5
		var burning = 0
		if game.residue:
			burning = game.residue.tiles_in(global_position, ROOT_REACH + radius).filter(func(tile): return game.residue.tiles.has(tile) and game.residue.tiles[tile].kind == "fire").size()
		if burning > 0:
			take_hit(BURN_HIT * mini(3, burning), Vector3.ZERO, false, false, "fire")
			if not alive or phase == 2: return Vector3.ZERO
	if root_line.is_empty() and timer <= 0:
		timer = ROOT_EVERY
		var from: Vector3 = global_position
		var to: Vector3 = from + direction * ROOT_LENGTH
		var mark = Geo.box(game.scene_root, Vector3.ZERO, Vector3(.7, .03, 1.0), Color("5a7a3a"))
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stretch(mark, from + Vector3.UP * .04, to + Vector3.UP * .04)
		root_line = {"from": from, "to": to, "time": ROOT_WARN, "mark": mark}
	if not root_line.is_empty():
		root_line.time -= delta * tempo()
		if root_line.time <= 0: erupt()
	spore -= delta
	if spore <= 0:
		spore = 9.0
		if game.residue: game.residue.add_cloud(global_position + direction * 2.4, 2.4)
	sprout -= delta
	if sprout <= 0:
		sprout = 15.0
		var rootlings = game.enemies.filter(func(e): return is_instance_valid(e) and e.alive and e.kind == "rootling").size()
		if rootlings < 2:
			var side: Vector3 = direction.cross(Vector3.UP)
			var a: DungeonEnemy = game.spawn_enemy(global_position + side * 3.0 + direction * 2.0, "rootling")
			var b: DungeonEnemy = game.spawn_enemy(global_position - side * 3.0 + direction * 2.0, "rootling")
			a.bind_partner(b)
	return Vector3.ZERO

## Roots burst up along the warned line and leave a trail of moss, joined
## to the heart: what grows there feeds it, and fire there reaches it.
func erupt() -> void:
	var from: Vector3 = root_line.from
	var to: Vector3 = root_line.to
	if is_instance_valid(root_line.mark): root_line.mark.queue_free()
	root_line = {}
	for i in 6:
		Effects.burst(game.scene_root, from.lerp(to, (i + .5) / 6.0) + Vector3.UP * .3, Color("7aa35a"), 4)
	if game.residue:
		var steps = ceili(from.distance_to(to) / .7)
		for i in steps + 1:
			var at: Vector3 = from.lerp(to, float(i) / steps)
			if game.room.geometry.contains(Vector2(at.x, at.z), .3): game.residue.add("moss", at, .45)
	var feet: Vector3 = game.player.global_position
	if Geometry3D.get_closest_point_to_segment(feet, from, to).distance_to(feet) < .6:
		game.player.hurt(1.0, feet)

func on_shot_missed(shot: EmberShot) -> void:
	if phase == 1 and game.residue: game.residue.add("moss", shot.global_position, 1.0)

## It cannot die while rooted: the blow that would kill it sends it below.
func allow_death() -> bool:
	if finishing: return true
	if phase == 1: enter_phase_two()
	return false

func enter_phase_two() -> void:
	phase = 2
	hp = max_hp * PHASE_TWO
	targetable = false
	contact_damage = false
	if not root_line.is_empty():
		if is_instance_valid(root_line.mark): root_line.mark.queue_free()
		root_line = {}
	for i in 3:
		var at: Vector3 = global_position + Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 3.0 + .5) * BULB_RING
		var bulb: DungeonEnemy = game.spawn_enemy(at, "bulb")
		bulb.heart = self
		bulbs.append(bulb)
	game.shake = maxf(game.shake, .25)
	game.ui.notify("The heart sinks into its roots", "Wilt all three bulbs within three seconds.", Color("b8e08a"))

## Each bulb that wilts asks: are all three wilted now?
func bulb_wilted() -> void:
	for bulb in bulbs:
		if not is_instance_valid(bulb) or bulb.wilted <= 0: return
	finishing = true
	for bulb in bulbs:
		if is_instance_valid(bulb): bulb.finish_off()
	targetable = true
	hp = 0.0
	die()
