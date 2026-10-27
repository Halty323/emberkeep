class_name DungeonPickup
extends Node3D
var game: Node3D
var kind = "copper_coin"
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
	var def := ItemSystem.pickup_def(kind)
	var color := Color(def.get("color", "#e7bd70"))
	match def.get("visual", "coin"):
		"coin":
			var coin = Geo.cylinder(visual, Vector3(0, .3, 0), .14 if def.get("amount", 1) < 5 else .18, .075, color, .5)
			coin.rotation_degrees.x = 75
			Geo.halo(self, Vector3(0, .025, 0), .8, Color(color, .2))
		"heart":
			var size := .35 if def.get("amount", 1) > 1 else .27
			Geo.box(visual, Vector3(0, .3, 0), Vector3(size, .13, .13), color, .6)
			Geo.box(visual, Vector3(0, .3, 0), Vector3(.13, size, .13), color, .6)
		"ward":
			Geo.box(visual, Vector3(0, .32, 0), Vector3(.28, .32, .08), color, .7)
			Geo.halo(self, Vector3(0, .025, 0), .7, Color(color, .18))
		"key":
			Geo.cylinder(visual, Vector3(-.1, .32, 0), .09, .05, color, .6).rotation_degrees.x = 90
			Geo.box(visual, Vector3(.08, .32, 0), Vector3(.26, .05, .05), color, .6)
			Geo.box(visual, Vector3(.18, .27, 0), Vector3(.05, .1, .05), color, .6)
		"bomb":
			Geo.sphere(visual, Vector3(0, .3, 0), .18, color)
			Geo.box(visual, Vector3(.06, .5, 0), Vector3(.04, .1, .04), Color("f2b46b"), .9)
		"battery":
			Geo.box(visual, Vector3(0, .32, 0), Vector3(.16, .3, .16), color, .7)
			Geo.box(visual, Vector3(0, .5, 0), Vector3(.07, .06, .07), Color("f5ead2"), .5)
			Geo.halo(self, Vector3(0, .025, 0), .7, Color(color, .2))

func update_sim(delta: float) -> void:
	if collected:
		return
	age += delta
	visual.position.y = sin(age * 3) * .06
	visual.rotation.y += delta * 1.5
	var to_player: Vector3 = game.player.global_position - global_position
	# Pickups that would do nothing (a heart at full health) stay on the ground.
	if not game.pickup_useful(kind):
		return
	if age > .25 and to_player.length() < float(Run.stats.magnet):
		position += to_player.normalized() * delta * 8.0
	if age > .25 and to_player.length() < .65:
		game.perform_action({"type": "CollectPickup", "drop_id": drop_id})
