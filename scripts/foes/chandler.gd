extends DungeonEnemy
## The Chandler, who dips candles for the crypt's dead. She pours wax across
## the floor in long lines, and every so often her wick catches and all the
## wax in the room goes up at once: stand on bare stone, or burn her lines
## early while she stands in them. From half health she casts wax effigies
## of the player that mirror their steps and fire their own weapon back.
const POUR := 9
const IGNITE_EVERY := 11.0
const CATCH := 2.0
var pour_cooldown = 2.0
var ignite_timer = IGNITE_EVERY
var catching = 0.0
var effigies_cast = 0
var wick: MeshInstance3D

func is_boss() -> bool:
	return true

func stats() -> Array:
	return [300, 1.3, .8, "d9c49a"]

func eye_height() -> float:
	return 1.9

func build_body(light: Dictionary) -> void:
	var body = Geo.cylinder(visual, Vector3(0, 1.1, 0), .6, 2.2, color, light.foe_body, .45)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geo.sphere(visual, Vector3(0, 2.35, 0), .38, Color("e8d8b8"), light.foe_body)
	Geo.cylinder(visual, Vector3(.7, 1.3, 0), .2, .45, Color("8a7a5a"), light.foe_body)
	Geo.cylinder(visual, Vector3(0, 2.85, 0), .04, .3, Color("3a3028"))
	wick = Geo.sphere(visual, Vector3(0, 3.05, 0), .1, Color("ffd890"), 2.0)

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	pour_cooldown -= delta * tempo()
	ignite_timer -= delta
	if effigies_cast == 0 and hp <= max_hp * .5: cast_effigies()
	elif effigies_cast == 1 and hp <= max_hp * .25: cast_effigies()
	if catching > 0:
		catching -= delta
		wick.scale = Vector3.ONE * (1.0 + 3.0 * (1.0 - catching / CATCH))
		if catching <= 0: set_alight()
		return Vector3.ZERO
	if ignite_timer <= 0:
		ignite_timer = IGNITE_EVERY * (.8 if hp <= max_hp * .5 else 1.0)
		catching = CATCH
		game.ui.notify("Her wick catches", "Get off the wax!", Color("ffb060"))
		return Vector3.ZERO
	if pour_cooldown <= 0:
		pour_cooldown = 2.6
		pour(direction)
	# Keeps her middle distance, stepping around the player.
	var side = direction.cross(Vector3.UP) * (1.0 if int(age / 4.0) % 2 == 0 else -1.0)
	return (side * .7 + direction * (1.0 if distance > 6.0 else (-.7 if distance < 3.5 else 0.0))).normalized()

## A line of wax poured toward the player and on past them.
func pour(direction: Vector3) -> void:
	if not game.residue: return
	var spread = direction.rotated(Vector3.UP, rng.randf_range(-.3, .3))
	for step in POUR:
		game.residue.add("wax", global_position + spread * (1.2 + step * .9), .65, true)
	visual.scale = Vector3(1.1, .92, 1.1)
	Audio.play_sound("hit", .5)

## Every wax tile in the room catches at once.
func set_alight() -> void:
	wick.scale = Vector3.ONE
	var field: ResidueField = game.residue
	if not field: return
	for tile in field.tiles.keys():
		if field.tiles[tile].kind == "wax": field.set_tile(tile, "fire")
	game.shake = maxf(game.shake, .2)
	Audio.play_sound("kill", .6)

func cast_effigies() -> void:
	effigies_cast += 1
	for mirror in [-1, 1]:
		var effigy = game.spawn_enemy(global_position + Vector3(mirror * 2.0, 0, 1.0), "effigy")
		effigy.mirror = mirror
		effigy.keeper = self
	game.ui.notify("She shapes you in wax", "Your effigies fire your own weapon. Wax melts.", Color("ffb060"))

func on_death() -> void:
	for enemy in game.enemies.duplicate():
		if is_instance_valid(enemy) and enemy.alive and enemy.kind == "effigy": enemy.die()
