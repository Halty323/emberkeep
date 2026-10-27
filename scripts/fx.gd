class_name Effects
extends Node3D

static func burst(parent: Node3D, at: Vector3, color: Color, count := 6, strength := 1.0) -> void:
	if parent.get_tree().get_nodes_in_group("effects").size() > 65:
		return
	count = maxi(1, roundi(count * Settings.effects_scale()))
	var fx = Node3D.new()
	parent.add_child(fx)
	fx.add_to_group("effects")
	fx.global_position = at
	var tween = fx.create_tween().set_parallel(true)
	for i in count:
		var piece = Geo.box(fx, Vector3.ZERO, Vector3.ONE * .11 * strength, color, 1.4)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var angle = TAU * float(i) / count + float(count) * .31
		var end = Vector3(cos(angle), .3 + sin(i * 2.7) * .8, sin(angle)) * strength
		tween.tween_property(piece, "position", end, .32)
		tween.tween_property(piece, "scale", Vector3.ONE * .02, .32)
	tween.chain().tween_callback(fx.queue_free)

static func ring_burst(parent: Node3D, at: Vector3, color: Color, radius: float) -> void:
	var fx = Geo.ring(parent, at + Vector3(0, .06, 0), .5, color, .04)
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tween = fx.create_tween().set_parallel(true)
	tween.tween_property(fx, "scale", Vector3(radius * 2, 1, radius * 2), .25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(fx, "position:y", at.y - .08, .26)
	tween.chain().tween_callback(fx.queue_free)

static func beam(parent: Node3D, a: Vector3, b: Vector3, color: Color) -> void:
	var length = a.distance_to(b)
	if length < .01:
		return
	var mesh = Geo.box(parent, (a + b) / 2, Vector3(.045, .045, length), color, 2.0)
	mesh.look_at(b)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tween = mesh.create_tween()
	tween.tween_property(mesh, "scale", Vector3(.05, .05, 1), .17)
	tween.tween_callback(mesh.queue_free)
