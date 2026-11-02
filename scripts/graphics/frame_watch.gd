class_name FrameWatch
extends RefCounted
## Long frames and what the game was doing just before each, for the FPS
## readout (Settings > Show FPS). A frame over 25 ms, a missed beat at
## 60 FPS and then some, counts as a hitch. Its cause is the last event the
## game named within two frames of it; with none, the time went to drawing
## (the GPU, the driver or a shader being built).
const HITCH_MS := 25.0
const WINDOW := 10.0
static var label := ""
static var label_frame := -100
static var clock := 0.0
# [time, milliseconds, cause] within the last WINDOW seconds.
static var hitches: Array = []

static func mark(what: String) -> void:
	label = what
	label_frame = Engine.get_process_frames()

static func frame(delta: float) -> void:
	clock += delta
	var ms := delta * 1000.0
	if ms > HITCH_MS:
		var cause := label if Engine.get_process_frames() - label_frame <= 2 else "drawing"
		hitches.append([clock, ms, cause])
		if Settings.values.show_fps: print("EMBERKEEP HITCH %d ms (%s)" % [roundi(ms), cause])
	while not hitches.is_empty() and clock - float(hitches[0][0]) > WINDOW: hitches.pop_front()

static func summary() -> String:
	if hitches.is_empty(): return "no hitches"
	var worst: Array = hitches[0]
	for hitch in hitches:
		if hitch[1] > worst[1]: worst = hitch
	return "%d hitches in 10 s, worst %d ms: %s" % [hitches.size(), roundi(worst[1]), worst[2]]
