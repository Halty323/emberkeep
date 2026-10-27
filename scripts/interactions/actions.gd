class_name GameActions
extends RefCounted
## One validated path for gameplay actions: validate -> apply once -> persist ->
## emit feedback. Local input calls perform(); a future authoritative host can
## call the same handlers with the same command dictionaries.
signal performed(action: Dictionary, result: Dictionary)
const EVENT_MEMORY := 256
var handlers: Dictionary = {}
var _seen_events: Dictionary = {}
var _event_order: Array = []

func register(type: String, handler: Callable) -> void:
	handlers[type] = handler

static func ok(extra := {}) -> Dictionary:
	var result = {"ok": true}
	result.merge(extra)
	return result

static func fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

func perform(action: Dictionary) -> Dictionary:
	var type: String = action.get("type", "")
	if not handlers.has(type):
		return fail("unknown_action")
	# Stable event IDs make a repeated delivery harmless.
	var event_id := str(action.get("event_id", ""))
	if event_id != "" and _seen_events.has(event_id):
		return fail("duplicate_event")
	var result: Dictionary = handlers[type].call(action)
	if event_id != "":
		_seen_events[event_id] = true
		_event_order.append(event_id)
		if _event_order.size() > EVENT_MEMORY:
			_seen_events.erase(_event_order.pop_front())
	if result.get("ok", false):
		performed.emit(action, result)
	return result
