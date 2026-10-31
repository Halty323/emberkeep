class_name DungeonPickup
extends Node3D
## View of one stable drop record. Collection goes through the shared action
## handler, which removes the record and grants its effect exactly once.
var game: Node3D
var def_id = "copper_coin"
var definition: Dictionary = {}
var kind = "coin"
var value = 1.0
var age = 0.0
var visual: Node3D
var collected = false
var drop_id = ""

func setup(owner_game: Node3D, at: Vector3, pickup_id: String, amount := -1.0) -> void:
	game = owner_game
	position = at
	def_id = pickup_id
	definition = Content.record("pickups", pickup_id)
	kind = definition.kind
	value = amount if amount > 0 else float(definition.value)
	visual = Node3D.new()
	add_child(visual)
	visual.scale = Vector3.ONE * float(definition.get("scale", 1.0))
	var color = Color(definition.color)
	match definition.visual:
		"coin":
			var coin = Geo.cylinder(visual, Vector3(0, .3, 0), .14, .075, color, .5)
			coin.rotation_degrees.x = 75
			Geo.halo(self, Vector3(0, .025, 0), .8, Color(color, .2))
		"heart":
			Geo.box(visual, Vector3(0, .3, 0), Vector3(.35, .13, .13), color, .6)
			Geo.box(visual, Vector3(0, .3, 0), Vector3(.13, .35, .13), color, .6)
		"ward":
			var shell = Geo.sphere(visual, Vector3(0, .32, 0), .17, color, .8)
			shell.scale = Vector3(1, 1.25, .45)
			var band = Geo.ring(visual, Vector3(0, .32, 0), .2, Color("e9f5ef"), .02)
			band.rotation_degrees.x = 90
			Geo.halo(self, Vector3(0, .025, 0), 1.0, Color(color, .2))
		"key":
			Geo.box(visual, Vector3(0, .3, 0), Vector3(.32, .05, .05), color, .5)
			var bow = Geo.ring(visual, Vector3(-.2, .3, 0), .08, color, .025)
			bow.rotation_degrees.x = 90
			Geo.box(visual, Vector3(.12, .25, 0), Vector3(.04, .1, .05), color, .5)
		"bomb":
			Geo.sphere(visual, Vector3(0, .26, 0), .17, color)
			Geo.cylinder(visual, Vector3(0, .46, 0), .03, .1, Color("a08c64"))
			Geo.sphere(visual, Vector3(0, .53, 0), .045, Color("ffd38a"), 2.0)
		"battery":
			Geo.cylinder(visual, Vector3(0, .3, 0), .1, .3, color, .7)
			Geo.cylinder(visual, Vector3(0, .48, 0), .045, .06, Color("d8d8c8"))
			Geo.halo(self, Vector3(0, .025, 0), 1.0, Color(color, .22))

func update_sim(delta: float) -> void:
	if collected:
		return
	age += delta
	visual.position.y = sin(age * 3) * .06
	visual.rotation.y += delta * 1.5
	# Unneeded pickups stay put: no magnet pull, no collection.
	if age <= .25 or not PickupRules.can_collect(definition):
		return
	var to_player: Vector3 = game.player.global_position - global_position
	if not game.first_person: to_player.y = 0
	if to_player.length() < float(Run.stats.magnet):
		position += to_player.normalized() * delta * 8.0
	if to_player.length() < .65:
		game.submit({"type": "collect_pickup", "target": drop_id})
