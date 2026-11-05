class_name PartyMember
extends Adventurer
## Another player's little light, as everyone else sees it: a hooded figure
## in its party colour with a flame on its head, its open spellbook and its
## name. It goes where that player's own device says it is. On the host it
## also stands in for that player: foes chase it, and whatever strikes it is
## sent to the player it belongs to.
const EYE := 1.48
var member_name := ""
var tint := Color.WHITE
var flame: MeshInstance3D
var book: MeshInstance3D
var pages: MeshInstance3D
var glow: OmniLight3D
var label: Label3D
var revive_ring: MeshInstance3D
var target := Vector3.ZERO
var yaw := 0.0
var downed := false
var invulnerable := false
var page_color := Color("ffd395")
# A shove a foe gave this figure (push) goes to its player's device, which
# moves the real body; here it only fades.
var pushed := Vector3.ZERO

func setup_member(owner_game, peer_id: int, display_name: String, color: Color, solid: bool) -> void:
	game = owner_game
	owner_peer_id = peer_id
	member_name = display_name
	tint = color
	name = "Member%d" % peer_id
	# Foes bump into a teammate on the host; nobody else collides with one.
	collision_layer = 2 if solid else 0
	collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = .32
	shape.height = 1.7
	collider.shape = shape
	collider.position.y = .85
	add_child(collider)
	visual = Node3D.new()
	add_child(visual)
	var robe := tint.darkened(.42)
	var robe_body := Geo.cylinder(visual, Vector3(0, .5, 0), .3, 1.0, robe, 0.0, .2)
	robe_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Geo.sphere(visual, Vector3(0, 1.1, 0), .25, robe)
	Geo.sphere(visual, Vector3(0, 1.43, 0), .19, Color("e5bd80"))
	var hood := Geo.sphere(visual, Vector3(0, 1.47, .05), .23, robe.darkened(.15))
	hood.scale = Vector3(1, 1.05, 1.1)
	Geo.box(visual, Vector3(-.07, 1.45, -.18), Vector3(.04, .05, .02), Color("32383a"))
	Geo.box(visual, Vector3(.07, 1.45, -.18), Vector3(.04, .05, .02), Color("32383a"))
	flame = Geo.sphere(visual, Vector3(0, 1.78, 0), .09, tint.lightened(.3), 2.4)
	flame.scale = Vector3(.7, 1.4, .7)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The open book, held low in front, written in its spellbook's colour.
	book = Geo.box(visual, Vector3(.16, 1.0, -.3), Vector3(.34, .035, .24), Color("5b2f2a"))
	book.rotation = Vector3(deg_to_rad(-35), 0, 0)
	pages = Geo.box(book, Vector3(0, .025, 0), Vector3(.3, .015, .2), page_color, 1.2)
	glow = Geo.light(visual, Vector3(0, 1.75, 0), tint.lerp(Color("ffcb88"), .5), .55, 3.4)
	label = Label3D.new()
	label.text = display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = .0016
	label.font_size = 26
	label.outline_size = 8
	label.modulate = tint.lightened(.2)
	label.outline_modulate = Color(0, 0, 0, .75)
	label.position = Vector3(0, 2.1, 0)
	label.layers = 2
	add_child(label)
	revive_ring = Geo.ring(self, Vector3(0, .05, 0), .9, tint, .05)
	revive_ring.visible = false

## The latest report from that player's device.
func show_state(state: Dictionary, snap := false) -> void:
	var at = state.get("p", target)
	if at is Vector3: target = at
	yaw = float(state.get("y", yaw))
	velocity = state.get("v", Vector3.ZERO) if state.get("v") is Vector3 else Vector3.ZERO
	invulnerable = bool(state.get("inv", false))
	var was_down := downed
	downed = bool(state.get("down", false))
	var color = state.get("w")
	if color is Color and not color.is_equal_approx(page_color):
		page_color = color
		pages.material_override = Geo.material(color, 1.2)
	ghost(bool(state.get("spec", false)))
	if snap or position.distance_to(target) > 4.0:
		position = target
		last_valid = target
	if was_down != downed: pose()

func pose() -> void:
	visual.rotation.x = deg_to_rad(-84) if downed else 0.0
	visual.position = Vector3(0, .25, .75) if downed else Vector3.ZERO
	flame.scale = Vector3(.45, .7, .45) if downed else Vector3(.7, 1.4, .7)
	glow.light_energy = .2 if downed else .55
	label.text = member_name + ("  · fallen" if downed else "")
	label.position.y = .95 if downed else 2.1
	if not downed: revive_ring.visible = false

static var ghost_material: StandardMaterial3D
var ghosted := false

## Watching a teammate's trial: pale and translucent, out of the fight.
func ghost(on: bool) -> void:
	if on == ghosted: return
	ghosted = on
	if not ghost_material:
		ghost_material = StandardMaterial3D.new()
		ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost_material.albedo_color = Color(.86, .9, 1.0, .24)
	for part in visual.find_children("*", "MeshInstance3D", true, false):
		if on:
			part.set_meta("solid", [part.material_override, part.cast_shadow])
			part.material_override = ghost_material
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif part.has_meta("solid"):
			var solid: Array = part.get_meta("solid")
			part.material_override = solid[0]
			part.cast_shadow = solid[1]
			part.remove_meta("solid")
	glow.light_energy = .15 if on else (.2 if downed else .55)
	label.modulate = tint.lightened(.2) * Color(1, 1, 1, .5 if on else 1.0)
	label.text = member_name + ("  · watching" if on else ("  · fallen" if downed else ""))

## How much of a rekindling is done (0 to 1), shown as a ring at their feet.
func show_revive(progress: float) -> void:
	revive_ring.visible = downed and progress > 0
	if revive_ring.visible: revive_ring.scale = Vector3.ONE * lerpf(.35, 1.0, progress)

func _physics_process(delta: float) -> void:
	var before := position
	position = position.lerp(target, 1.0 - exp(-16.0 * delta))
	last_valid = position
	haste_time = maxf(0, haste_time - delta)
	if push.distance_to(pushed) > .01 and game.party: game.party.send_push(owner_peer_id, push)
	push = push.move_toward(Vector3.ZERO, delta * 14.0)
	pushed = push
	recoil = move_toward(recoil, 0.0, delta * 3.0)
	visual.rotation.y = lerp_angle(visual.rotation.y, yaw, 1.0 - exp(-14.0 * delta))
	var moved := Vector2(position.x - before.x, position.z - before.z).length()
	walk_time += moved * 2.7
	if not downed: visual.position.y = absf(sin(walk_time)) * .05
	flame.position.y = 1.78 + sin(Time.get_ticks_msec() * .006 + owner_peer_id) * .015

## Struck in the host's world: the blow goes to the player it belongs to.
func hurt(amount: float, source: Vector3) -> void:
	if game and game.party: game.party.strike(self, amount, source)
