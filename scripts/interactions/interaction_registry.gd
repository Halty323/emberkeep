class_name InteractionRegistry
extends RefCounted
## Stable-id registry for pedestals, exits, chests, dropped items and
## paintings. One eligible target is chosen at a time: highest priority, then
## nearest, then id order. The current focus is kept until another target is
## clearly better, so prompts do not flicker between neighbours, and a
## decorative painting can never take the prompt from an exit or pedestal.
const PRIORITY := {"exit": 100, "treasure": 90, "shop": 90, "rest": 90, "chest": 70, "item": 60, "painting": 40}
const HYSTERESIS := .35
var targets: Dictionary = {}
var focused := ""

func register(id: String, kind: String, position: Vector3, radius: float, prompt: String, node: Node3D = null) -> void:
	targets[id] = {"id": id, "kind": kind, "position": position, "radius": radius, "prompt": prompt,
		"node": node, "priority": PRIORITY.get(kind, 10)}

func unregister(id: String) -> void:
	targets.erase(id)
	if focused == id:
		focused = ""

func clear() -> void:
	targets.clear()
	focused = ""

static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

static func ranks_before(a: Dictionary, a_distance: float, b: Dictionary, b_distance: float) -> bool:
	if a.priority != b.priority:
		return a.priority > b.priority
	if not is_equal_approx(a_distance, b_distance):
		return a_distance < b_distance
	return a.id < b.id

func choose(at: Vector3, eligible: Callable) -> Dictionary:
	var best: Dictionary = {}
	var best_distance = INF
	for target in targets.values():
		var distance = flat_distance(at, target.position)
		if distance > target.radius or not eligible.call(target):
			continue
		if best.is_empty() or ranks_before(target, distance, best, best_distance):
			best = target
			best_distance = distance
	if not best.is_empty() and focused != "" and focused != best.id and targets.has(focused):
		var current: Dictionary = targets[focused]
		var distance = flat_distance(at, current.position)
		if distance <= current.radius and current.priority >= best.priority and distance < best_distance + HYSTERESIS and eligible.call(current):
			best = current
	focused = best.get("id", "")
	return best
