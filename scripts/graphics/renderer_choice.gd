class_name RendererChoice
extends RefCounted
## Which renderer the game starts with. Computers use Forward+ (Vulkan or
## Direct3D 12) and phones the Mobile renderer (Vulkan, Metal on iOS); the
## Compatibility renderer (OpenGL) is the fallback, and Godot itself drops to
## it when a device has no usable Vulkan (rendering_device/fallback_to_opengl3).
##
## Godot picks the renderer before any script runs, so the player's choice
## (Settings "renderer") is written to user://renderer.cfg, which project.godot
## names as its settings override, and takes effect on the next launch.
##
## Auto also guards against a driver that starts but then dies: each launch on
## Vulkan is marked pending until the first room has been drawn for a few
## seconds. After MAX_FAILED launches in a row that never got there, the next
## launch uses Compatibility. Choosing Vulkan by hand retries it unguarded.
const OVERRIDE := "user://renderer.cfg"
const PROBE := "user://renderer_probe.json"
const CHOICES := ["auto", "vulkan", "compatibility"]
const MAX_FAILED := 2
const COMPAT := "gl_compatibility"

static var _healthy_marked := false

## The renderer this launch runs on: forward_plus, mobile or gl_compatibility.
static func method() -> String:
	return RenderingServer.get_current_rendering_method()

## Forward+ or Mobile: Vulkan, Direct3D 12 or Metal.
static func modern(current := "") -> bool:
	return (current if current != "" else method()) != COMPAT

## The renderer a choice launches with.
static func method_for(choice: String, mobile: bool) -> String:
	if choice == "compatibility": return COMPAT
	return "mobile" if mobile else "forward_plus"

## What the settings row shows, e.g. "Auto · Vulkan" or "Auto · OpenGL (fallback)".
static func label(choice: String, current := "", fell_back := false) -> String:
	var running := name_of(current if current != "" else method())
	match choice:
		"vulkan": return "Vulkan" + ("" if modern(current) else " · next launch")
		"compatibility": return "Compatibility" + ("" if not modern(current) else " · next launch")
	return "Auto · " + running + (" (fallback)" if fell_back and not modern(current) else "")

static func name_of(rendering_method: String) -> String:
	match rendering_method:
		"forward_plus": return "Forward+"
		"mobile": return "Mobile"
	return "OpenGL"

## The text of user://renderer.cfg for a choice, or "" for none (the
## project's own per-platform renderers).
static func override_text(choice: String) -> String:
	if choice != "compatibility": return ""
	return "[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\nrenderer/rendering_method.mobile=\"gl_compatibility\"\n"

## The player picked a renderer: saved for the next launch, with a fresh guard.
static func choose(choice: String, override_path := OVERRIDE, probe_path := PROBE) -> void:
	write(choice, override_path)
	write_probe({"failed": 0, "pending": false, "fell_back": false}, probe_path)

## Saves a choice for the next launch.
static func write(choice: String, path := OVERRIDE) -> void:
	var text := override_text(choice)
	if text == "":
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()

## Whether this launch should guard the renderer: exported games only, so
## tests and editor runs never write a fallback.
static func guarded() -> bool:
	return OS.has_feature("template") and DisplayServer.get_name() != "headless"

## Called once at start-up. Returns the probe's state after this launch:
## {"failed": launches on Vulkan that never got healthy, "fell_back": bool}.
## With failed >= MAX_FAILED under Auto, Compatibility is written for the next
## launch (this one is already running and carries on).
static func begin(choice: String, current: String, probe_path := PROBE, override_path := OVERRIDE) -> Dictionary:
	var probe := read_probe(probe_path)
	if choice != "auto":
		probe = {"failed": 0, "pending": false, "fell_back": false}
		write(choice, override_path)
	elif not bool(probe.fell_back):
		# Keep the override file in step with the saved choice.
		write("auto", override_path)
	if choice == "auto" and modern(current):
		if bool(probe.get("pending", false)): probe.failed = int(probe.get("failed", 0)) + 1
		probe.pending = true
		if int(probe.failed) >= MAX_FAILED:
			write("compatibility", override_path)
			probe.fell_back = true
			probe.pending = false
	write_probe(probe, probe_path)
	return probe

## The first room has been drawn for a while: this renderer works here.
static func healthy(probe_path := PROBE) -> void:
	if _healthy_marked and probe_path == PROBE: return
	_healthy_marked = true
	var probe := read_probe(probe_path)
	if not bool(probe.get("pending", false)) and int(probe.get("failed", 0)) == 0: return
	probe.pending = false
	probe.failed = 0
	write_probe(probe, probe_path)

static func fell_back(probe_path := PROBE) -> bool:
	return bool(read_probe(probe_path).get("fell_back", false))

static func read_probe(path: String) -> Dictionary:
	var empty := {"failed": 0, "pending": false, "fell_back": false}
	if not FileAccess.file_exists(path): return empty
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return empty
	empty.merge(parsed, true)
	return empty

static func write_probe(probe: Dictionary, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(probe))
		file.close()
