class_name BombView
extends Node3D
## View of a pending bomb record. The record's fuse is the authority; this
## only shows it, with a visible blast radius so the danger is readable.
var record: Dictionary
var spark: MeshInstance3D
var ring: MeshInstance3D

func setup(bomb: Dictionary, radius: float) -> void:
	record = bomb
	position = Vector3(float(bomb.position[0]), 0, float(bomb.position[1]))
	Geo.sphere(self, Vector3(0, .32, 0), .3, Color("4b4f52"))
	Geo.cylinder(self, Vector3(0, .66, 0), .05, .16, Color("8a7b5c"))
	spark = Geo.sphere(self, Vector3(0, .78, 0), .07, Color("ffd38a"), 2.4)
	ring = Geo.ring(self, Vector3(0, .04, 0), radius, Color("e88a64"), .05)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Geo.halo(self, Vector3(0, .02, 0), 2.2, Color(1, .55, .25, .25))

func _process(_delta: float) -> void:
	var fuse = float(record.get("fuse", 0))
	var rate = lerpf(18.0, 5.0, clampf(fuse / GameActions.BOMB_FUSE, 0, 1))
	spark.visible = int(Time.get_ticks_msec() / 1000.0 * rate) % 2 == 0
	ring.scale = Vector3.ONE * (1.0 + .04 * sin(Time.get_ticks_msec() / 1000.0 * rate))
