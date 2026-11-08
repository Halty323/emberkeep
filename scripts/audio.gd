extends Node
var sounds: Dictionary = {}
var players: Array[AudioStreamPlayer] = []
var music_player: AudioStreamPlayer
var voice = 0
var spatial_players: Array[AudioStreamPlayer3D] = []
var spatial_voice := 0

func _exit_tree() -> void:
	# Stop looping playback explicitly before the audio server shuts down.
	if music_player:
		music_player.stop()
		music_player.stream = null
	for player in spatial_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	for player in players:
		player.stop()
		player.stream = null

func _ready() -> void:
	# Effects and music each have their own bus, so each has its own volume.
	make_bus("Effects")
	make_bus("Music")
	for i in 12:
		var player = AudioStreamPlayer.new()
		player.bus = "Effects"
		add_child(player)
		players.append(player)
	sounds["step"] = tone(95, 48, .075, .045)
	# A cast is a short bright chime, rising a little, not a gunshot.
	sounds["shoot"] = chime(740, .14, .13)
	sounds["hit"] = tone(170, 65, .1, .23)
	sounds["kill"] = tone(230, 55, .19, .23)
	sounds["dash"] = tone(150, 660, .2, .16)
	sounds["coin"] = tone(1100, 1550, .1, .16)
	sounds["item"] = tone(420, 1050, .45, .2)
	sounds["hurt"] = tone(190, 70, .3, .3)
	sounds["door"] = tone(260, 520, .25, .12)
	# Recorded impacts (Kenney's Impact Sounds, CC0): a few takes of each,
	# picked at random so no break or slam sounds twice the same.
	for group in RECORDED:
		for take in RECORDED[group]:
			var stream = load("res://assets/audio/impacts/%s.ogg" % take)
			if stream: sounds[take] = stream
	# One soft pass of the quill over a whole room, not a stroke per square.
	sounds["scribble"] = scratch(1.05, 7)
	# Spell sounds are rendered off the main thread; until one is ready the
	# cast falls back to the plain chime.
	if DisplayServer.get_name() != "headless":
		WorkerThreadPool.add_task(render_spell_sounds)
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	add_child(music_player)
	music_player.stream = make_ambient()
	music_player.volume_db = -14
	Settings.changed.connect(_on_setting_changed)
	apply_volumes()
	refresh()

const RECORDED := {
	"break_wood": ["impact_wood_heavy_000", "impact_wood_heavy_001", "impact_wood_heavy_002"],
	"break_planks": ["impact_plank_medium_000", "impact_plank_medium_001"],
	"break_pot": ["impact_plate_heavy_000", "impact_plate_medium_000", "impact_plate_medium_001"],
	"door_slam": ["impact_wood_heavy_003", "impact_wood_heavy_004"],
	"door_lock": ["impact_metal_heavy_001", "impact_metal_heavy_003"]}
const RECORDED_VOLUME := {"break_wood": -3.0, "break_planks": -9.0, "break_pot": -4.0, "door_slam": -1.0, "door_lock": -8.0}

## One take of a recorded group, where it happens, on this device alone
## (each device breaks props and shuts doors itself), a little detuned.
func play_recorded(group: String, parent: Node3D, at: Vector3, pitch := 1.0) -> void:
	var takes: Array = RECORDED.get(group, [])
	if takes.is_empty(): return
	var take: String = takes[randi() % takes.size()]
	play_local_at(take, parent, at, pitch * randf_range(.92, 1.08), float(RECORDED_VOLUME.get(group, -6.0)) + 12.0)

func _on_setting_changed(key: String) -> void:
	if key in ["sound", "music"]: refresh()
	if key in ["sound_volume", "music_volume"]: apply_volumes()

static func make_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0: return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")

## Settings "sound_volume" and "music_volume", 0-100: a fader on each bus.
func apply_volumes() -> void:
	for pair in [["Effects", "sound_volume"], ["Music", "music_volume"]]:
		var index := AudioServer.get_bus_index(pair[0])
		if index < 0: continue
		var level := clampf(float(Settings.values.get(pair[1], 100)) / 100.0, 0.0, 1.0)
		AudioServer.set_bus_mute(index, level <= 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(level, .001)))

func refresh() -> void:
	if DisplayServer.get_name() == "headless": return
	if Settings.values.music:
		if not music_player.playing:
			music_player.play()
	else:
		music_player.stop()

func play_sound(id: String, pitch := 1.0) -> void:
	NetHooks.sound(id, pitch)
	play_local(id, pitch)

## How loud each sound sits in the mix, in dB (the default is -4).
## Spell sounds sit well under the rest: they come often and close.
const VOLUMES := {"shoot": -9.0, "scribble": -19.0, "ray": -15.0, "hum": -19.0, "charge": -17.0, "crack": -17.0, "thunder": -14.0,
	"conjure": -18.0, "rumble": -14.0, "whistle": -16.0, "rise_flame": -13.0, "rise_ice": -14.0, "rise_skyfall": -14.0, "rise_bubbles": -13.0,
	"rise_pillar": -14.0, "rise_crystal": -15.0, "rise_geyser": -13.0, "rise_spout": -13.0, "rise_meteor": -11.0}
# The same spell sound starting again this soon is skipped, so rapid casts
# and chains never pile into one roar.
const REPEAT_GAP := .07
var last_played: Dictionary = {}

func too_soon(id: String) -> bool:
	if not VOLUMES.has(id) and not id.begins_with("cast_"): return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(last_played.get(id, -1.0)) < REPEAT_GAP: return true
	last_played[id] = now
	return false

## Heard on this device alone: a spell every device draws for itself makes
## its own sound on each, rather than once more from the host.
func play_local(id: String, pitch := 1.0, louder := 0.0) -> void:
	if DisplayServer.get_name() == "headless": return
	if not Settings.values.sound or not sounds.has(id) or too_soon(id):
		return
	var player: AudioStreamPlayer = players[voice % players.size()]
	voice += 1
	player.stream = sounds[id]
	player.pitch_scale = pitch
	player.volume_db = float(VOLUMES.get(id, -15.0 if id.begins_with("cast_") else -4.0)) + louder
	player.play()

func render_spell_sounds() -> void:
	var made := {}
	var recipes: Dictionary = SpellAudio.recipes()
	for id in recipes: made[id] = recipes[id].call()
	call_deferred("adopt_sounds", made)

func adopt_sounds(made: Dictionary) -> void:
	sounds.merge(made, true)

func tone(start: float, end: float, duration: float, amplitude: float) -> AudioStreamWAV:
	var bytes = PackedByteArray()
	var count = int(22050 * duration)
	bytes.resize(count * 2)
	var phase = 0.0
	for i in count:
		var t = float(i) / count
		phase += TAU * lerpf(start, end, t) / 22050.0
		var sample = sin(phase) * pow(1.0 - t, 2.0) * minf(t * 25, 1.0) * amplitude
		bytes.encode_s16(i * 2, int(sample * 32767))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = bytes
	return stream

## A small bell-like note: a base tone with two softer overtones that rise a
## little and ring away quickly.
func chime(base: float, duration: float, amplitude: float) -> AudioStreamWAV:
	var bytes = PackedByteArray()
	var count = int(22050 * duration)
	bytes.resize(count * 2)
	var phases := [0.0, 0.0, 0.0]
	var ratios := [1.0, 2.01, 3.03]
	var weights := [1.0, .45, .2]
	for i in count:
		var t = float(i) / count
		var sample := 0.0
		for k in 3:
			phases[k] += TAU * base * ratios[k] * (1.0 + .12 * t) / 22050.0
			sample += sin(phases[k]) * weights[k]
		sample *= exp(-t * 5.0) * minf(t * 60, 1.0) * amplitude * .6
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = bytes
	return stream

## A quill scratching paper: short strokes of filtered noise, back and forth,
## each a little brighter or duller than the last as the nib changes way.
func scratch(duration: float, strokes: int) -> AudioStreamWAV:
	var noise = RandomNumberGenerator.new()
	noise.seed = 1307
	var bytes = PackedByteArray()
	var count = int(22050 * duration)
	bytes.resize(count * 2)
	var soft = 0.0
	var previous = 0.0
	for i in count:
		var t = float(i) / count
		var stroke = t * strokes
		var within = stroke - floorf(stroke)
		var bright = .5 if int(stroke) % 2 == 0 else .3
		soft += (noise.randf_range(-1.0, 1.0) - soft) * bright
		var edge = soft - previous
		previous = soft
		var envelope = pow(sin(within * PI), .7) * (1.0 - t * .45) * minf(t * 60.0, 1.0)
		bytes.encode_s16(i * 2, int(clampf((edge * .9 + soft * .25) * envelope * .55, -1.0, 1.0) * 32767))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = bytes
	return stream

func make_ambient() -> AudioStreamWAV:
	var bytes = PackedByteArray()
	var count = 22050 * 12
	# Godot mixes a forward loop up to and including loop_end, so the data
	# carries one frame past the period (the first frame again). Without it
	# the mixer reads past the buffer at every wrap, which crashes Android.
	bytes.resize((count + 1) * 2)
	# Frequencies align to the loop period. Soft, original A-minor pad.
	var notes = [110.0, 165.0, 220.0, 261.666667, 330.0]
	for i in count + 1:
		var t = float(i) / 22050
		var value = 0.0
		for n in notes.size():
			var swell = .55 + .3 * sin(TAU * t / 12.0 + n * 1.4)
			value += sin(TAU * notes[n] * t) * swell * .025
		bytes.encode_s16(i * 2, int(value * 32767))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	stream.data = bytes
	return stream

func play_at(id: String, parent: Node3D, at: Vector3, pitch := 1.0) -> void:
	NetHooks.sound(id, pitch, at)
	play_local_at(id, parent, at, pitch)

## A sound where something happens, on this device alone.
func play_local_at(id: String, parent: Node3D, at: Vector3, pitch := 1.0, louder := 0.0) -> void:
	if DisplayServer.get_name() == "headless" or not Settings.values.sound or not sounds.has(id) or too_soon(id): return
	if spatial_players.is_empty():
		for i in 8:
			var player = AudioStreamPlayer3D.new()
			player.bus = "Effects"
			parent.get_tree().root.add_child(player)
			player.max_distance = 24
			player.unit_size = 4
			spatial_players.append(player)
	var player = spatial_players[spatial_voice % spatial_players.size()]
	spatial_voice += 1
	player.global_position = at
	player.stream = sounds[id]
	player.pitch_scale = pitch
	# Spell sounds keep their own loudness, a little softened by distance.
	player.volume_db = (float(VOLUMES[id]) - 2.0 if VOLUMES.has(id) else -12.0) + louder
	# A spell's sound is full only right beside it and falls away from a step off.
	player.unit_size = 1.5 if VOLUMES.has(id) else 4.0
	player.play()
