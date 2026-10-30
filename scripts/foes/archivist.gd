extends DungeonEnemy
## The Hoarfrost Archivist, who files away every flame the keepers put out.
## A shell of frost turns most of every shot aside; only burning melts it, and
## only while it burns (a fire weapon, a blast, or a full kindle's flame). She
## reads passages aloud as fans and spirals of pages, and calls up shelves to
## hide behind. From half health the whole floor freezes over.
const SHELL := .3
const MELTED := 1.2
const SHELF_LIFE := 7.0
var read_cooldown = 2.0
var shelf_cooldown = 6.0
var shelves: Array = []
var frozen_floor = false
var frost: MeshInstance3D

func is_boss() -> bool:
	return true

func stats() -> Array:
	return [290, 1.2, .8, "a8c0d8"]

func eye_height() -> float:
	return 1.7

func build_body(light: Dictionary) -> void:
	var body = Geo.cylinder(visual, Vector3(0, 1.0, 0), .65, 2.0, color, light.foe_body, .4)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geo.sphere(visual, Vector3(0, 2.15, 0), .4, Color("dfe8f0"), light.foe_body)
	Geo.box(visual, Vector3(0, 1.3, -.7), Vector3(.9, .65, .12), Color("6a5a48"), light.foe_body)
	frost = Geo.sphere(self, Vector3(0, 1.1, 0), 1.35, Color(.8, .92, 1.0), .4)
	frost.material_override = ward_material()
	frost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func melted() -> bool:
	return burn_time > 0

func behave(delta: float, distance: float, direction: Vector3) -> Vector3:
	frost.visible = not melted()
	read_cooldown -= delta * tempo()
	shelf_cooldown -= delta
	for i in range(shelves.size() - 1, -1, -1):
		shelves[i].time -= delta
		var rise = clampf(minf(SHELF_LIFE - shelves[i].time, shelves[i].time) / .4, 0.0, 1.0)
		shelves[i].node.position.y = (rise - 1.0) * 1.7
		if shelves[i].time <= 0:
			shelves[i].node.queue_free()
			shelves.remove_at(i)
	if not frozen_floor and hp <= max_hp * .5: freeze_floor()
	if read_cooldown <= 0:
		read_cooldown = 2.6 if frozen_floor else 3.0
		if frozen_floor and int(age) % 2 == 0: spiral()
		else: fan(direction)
	if shelf_cooldown <= 0 and shelves.is_empty():
		shelf_cooldown = 11.0
		raise_shelves()
	var side = direction.cross(Vector3.UP)
	return (side * .6 + direction * (1.0 if distance > 7.0 else (-.6 if distance < 4.5 else 0.0))).normalized()

func fan(direction: Vector3) -> void:
	for i in 7:
		var d = direction.rotated(Vector3.UP, (i / 6.0 - .5) * 1.1)
		game.spawn_shot(global_position + Vector3.UP * .8 + d * 1.0, d, 1, 5.5, {}, Color("e8e4d8"), false)

func spiral() -> void:
	for i in 12:
		var d = Vector3.RIGHT.rotated(Vector3.UP, TAU * i / 12.0 + age * .7)
		game.spawn_shot(global_position + Vector3.UP * .8 + d * 1.0, d, 1, 4.2, {"wave": 1}, Color("cfe0f5"), false)

## Three shelves rise out of the floor, away from the player, and sink again.
func raise_shelves() -> void:
	for i in 3:
		var at2: Vector2 = game.room.geometry.random_point(rng, 1.6)
		for attempt in 6:
			if at2.distance_to(Vector2(game.player.global_position.x, game.player.global_position.z)) > 3.0: break
			at2 = game.room.geometry.random_point(rng, 1.6)
		var node = Node3D.new()
		game.scene_root.add_child(node)
		node.position = Vector3(at2.x, -1.7, at2.y)
		node.rotation.y = rng.randf() * PI
		Geo.box(node, Vector3(0, .85, 0), Vector3(2.6, 1.7, .5), Color("5a4a3a"))
		Geo.box(node, Vector3(0, 1.1, -.2), Vector3(2.3, .3, .15), Color("8a98a8"))
		Geo.collider(node, Vector3(0, .85, 0), Vector3(2.6, 1.7, .5))
		shelves.append({"node": node, "time": SHELF_LIFE})
	Audio.play_sound("door", .8)

func freeze_floor() -> void:
	frozen_floor = true
	var field: ResidueField = game.residue
	if field:
		for tile in field.floor_tiles():
			if not field.tiles.has(tile): field.set_tile(tile, "ice", true)
	game.shake = maxf(game.shake, .2)
	game.ui.notify("The floor freezes over", "Fire still melts her frost.", Color("cfe0f5"))

func damage_scale(cause: String) -> float:
	if cause == "dot": return 1.0
	return MELTED if melted() else SHELL

func on_death() -> void:
	for shelf in shelves:
		if is_instance_valid(shelf.node): shelf.node.queue_free()
	shelves.clear()
