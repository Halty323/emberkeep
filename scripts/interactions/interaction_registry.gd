class_name InteractionRegistry
extends RefCounted
## Stable-ID interaction targets: pedestals, exits, chests, paintings and dropped
## actives. One eligible target is focused at a time, with deterministic ties and
## hysteresis so the prompt does not flicker between neighbours.
const HYSTERESIS := .45
## Higher priority wins inside range. A decorative painting never steals the exit.
const PRIORITY := {"exit": 100, "treasure": 80, "shop": 80, "rest": 80, "chest": 60, "active": 40, "painting": 20}
var targets: Dictionary = {}
var focused_id := ""

func register(id: String, kind: String, position: Vector3, prompt: String, radius := 2.1, data := {}) -> Dictionary:
	var target = {"id": id, "kind": kind, "position": position, "prompt": prompt, "radius": radius,
		"priority": PRIORITY.get(kind, 0), "enabled": true, "data": data}
	targets[id] = target
	return target

func unregister(id: String) -> void:
	targets.erase(id)
	if focused_id == id:
		focused_id = ""

func clear() -> void:
	targets.clear()
	focused_id = ""

func get_target(id: String) -> Dictionary:
	return targets.get(id, {})

func _better(a: Dictionary, b: Dictionary, from: Vector3) -> bool:
	if a.priority != b.priority:
		return a.priority > b.priority
	var da = from.distance_to(a.position)
	var db = from.distance_to(b.position)
	if not is_equal_approx(da, db):
		return da < db
	return a.id < b.id

## blocked(target) may return true when a wall or solid prop obstructs it.
func select(from: Vector3, blocked := Callable()) -> Dictionary:
	var eligible: Array = []
	for target in targets.values():
		if not target.enabled or from.distance_to(target.position) >= target.radius:
			continue
		if blocked.is_valid() and blocked.call(target):
			continue
		eligible.append(target)
	if eligible.is_empty():
		focused_id = ""
		return {}
	var best: Dictionary = eligible[0]
	for target in eligible:
		if _better(target, best, from):
			best = target
	if focused_id != "" and focused_id != best.id:
		for target in eligible:
			# Keep the current focus while it stays nearly as good.
			if target.id == focused_id and target.priority >= best.priority \
					and from.distance_to(target.position) <= from.distance_to(best.position) + HYSTERESIS:
				return target
	focused_id = best.id
	return best
