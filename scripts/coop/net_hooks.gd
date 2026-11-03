class_name NetHooks
extends RefCounted
## The co-op host's ears on the lowest-level helpers (effects, sounds and
## simple geometry). It names no autoload, so anything may use it; Party
## sets itself as the recorder, and nothing is recorded while alone.
static var recorder: Object

static func recording() -> bool:
	return recorder != null and is_instance_valid(recorder) and recorder.recording > 0

static func fx(method: String, args: Array) -> void:
	if recording(): recorder.share("fx", [method, args])

static func sound(id: String, pitch: float, at = null) -> void:
	if recording(): recorder.shared_sound(id, pitch, at)

static func geo(node: Node3D, method: String, args: Array) -> Node3D:
	if recording(): recorder.note_geo(node, method, args)
	return node

## The game's party, if it has one (test fixtures and tools may not).
static func party(game) -> Object:
	return game.get("party") if game != null else null

## Who the world can strike: the party's standing bodies, or the lone player.
static func bodies(game) -> Array:
	var net = party(game)
	if net != null: return net.bodies()
	var player = game.get("player") if game != null else null
	return [player] if is_instance_valid(player) else []

## Whether this device's player has fallen (co-op only).
static func downed(game) -> bool:
	var net = party(game)
	return net != null and net.downed
