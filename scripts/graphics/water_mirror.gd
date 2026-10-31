class_name WaterMirror
extends SubViewport
## What standing water reflects: the room seen from below the water's surface
## by a mirrored copy of the game camera, at a fraction of the screen's
## resolution. It renders only while the room holds water or ice and effects
## detail allows it; the ground sheets and the unlit effects layer are left
## out, since they lie at or under the water. The image is mirrored left to
## right so the copy is a true rotation; the water shader flips it back.
const SURFACE := .022
const SCALE := [0.0, .35, .5]
var source: Camera3D
var mirror: Camera3D

func setup(main_camera: Camera3D) -> void:
	source = main_camera
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Never inherit/use mobile MSAA for an auxiliary render target.
	msaa_3d = Viewport.MSAA_DISABLED
	positional_shadow_atlas_size = 0
	mirror = Camera3D.new()
	mirror.cull_mask = 0xFFFFF & ~(2 | 8)
	add_child(mirror)
	mirror.current = true

## Runs the mirror when wanted, matching the game camera each frame.
func follow(wanted: bool, _screen: Vector2) -> void:
	var level = Look.quality()
	var policy = RenderPolicy.current()
	var active = wanted and level > 0 and policy.reflections and is_instance_valid(source)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active: return
	# Use physical 3D pixels, including render scale, then cap both dimensions.
	# UI coordinates may be virtual on stretched/wide displays.
	var pixels = Vector2(source.get_viewport().size) * source.get_viewport().scaling_3d_scale
	var limit = Vector2(policy.reflection_limit)
	var factor = minf(SCALE[level], minf(limit.x / maxf(pixels.x, 1.0), limit.y / maxf(pixels.y, 1.0)))
	var target = Vector2i(maxi(1, int(pixels.x * factor)), maxi(1, int(pixels.y * factor)))
	if size != target: size = target
	mirror.projection = source.projection
	mirror.size = source.size
	mirror.near = source.near
	mirror.far = source.far
	mirror.keep_aspect = source.keep_aspect
	mirror.h_offset = -source.h_offset
	mirror.v_offset = source.v_offset
	var flip_y = Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1))
	var flip_x = Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	var at: Vector3 = source.global_position
	at.y = 2.0 * SURFACE - at.y
	mirror.global_transform = Transform3D(flip_y * source.global_basis * flip_x, at)
