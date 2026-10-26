class_name DungeonPickup
extends Node3D
var game: Node3D
var kind = "coin"
var value = 1
var age = 0.0
var visual: Node3D
var collected = false
var drop_id = -1

func setup(owner_game: Node3D, at: Vector3, type: String, amount := 1) -> void:
	game = owner_game
	position = at
	kind = type
	value = amount
	visual = Node3D.new()
	add_child(visual)
	if kind == "coin":
		var coin = Geo.cylinder(visual, Vector3(0, .3, 0), .14, .075, Color("e7bd70"), .5)
		coin.rotation_degrees.x = 75
		Geo.halo(self, Vector3(0, .025, 0), .8, Color(1, .7, .25, .2))
	else:
		Geo.box(visual, Vector3(0, .3, 0), Vector3(.35, .13, .13), Color("d99083"), .6)
		Geo.box(visual, Vector3(0, .3, 0), Vector3(.13, .35, .13), Color("d99083"), .6)

func update_sim(delta: float) -> void:
	if collected:
		return
	age += delta
	visual.position.y = sin(age * 3) * .06
	visual.rotation.y += delta * 1.5
	var to_player: Vector3 = game.player.global_position - global_position
	if kind == "heart" and Run.hp >= Run.stats.max_hp:
		return
	if age > .25 and to_player.length() < float(Run.stats.magnet):
		position += to_player.normalized() * delta * 8.0
	if age > .25 and to_player.length() < .65:
		collected = true
		var data: Dictionary = Run.rooms[Run.current_room]
		if data.has("pickups"):
			data.pickups = data.pickups.filter(func(drop): return int(drop.id) != drop_id)
		if kind == "coin":
			Run.coins += value
			Audio.play_sound("coin", 1.0 + float(value) * .05)
		else:
			Run.heal(value)
			Audio.play_sound("item", 1.2)
		Run.changed.emit()
		if Run.rooms[Run.current_room].cleared:
			Run.save_run()
		queue_free()
