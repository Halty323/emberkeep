extends Node
var sounds: Dictionary = {}
var players: Array[AudioStreamPlayer] = []
var music_player: AudioStreamPlayer
var voice = 0

func _exit_tree() -> void:
	# Stop looping playback explicitly before the audio server shuts down.
	if music_player:
		music_player.stop()
		music_player.stream = null
	for player in players:
		player.stop()
		player.stream = null

func _ready() -> void:
	for i in 12:
		var player = AudioStreamPlayer.new()
		add_child(player)
		players.append(player)
	sounds["shoot"] = tone(650, 180, .08, .16)
	sounds["hit"] = tone(170, 65, .1, .23)
	sounds["kill"] = tone(230, 55, .19, .23)
	sounds["dash"] = tone(150, 660, .2, .16)
	sounds["coin"] = tone(1100, 1550, .1, .16)
	sounds["item"] = tone(420, 1050, .45, .2)
	sounds["hurt"] = tone(190, 70, .3, .3)
	sounds["door"] = tone(260, 520, .25, .12)
	sounds["scribble"] = scratch(.72, 6)
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	music_player.stream = make_ambient()
	music_player.volume_db = -14
	Settings.changed.connect(_on_setting_changed)
	refresh()

func _on_setting_changed(key: String) -> void:
	if key in ["sound", "music"]: refresh()

func refresh() -> void:
	if DisplayServer.get_name() == "headless": return
	if Settings.values.music:
		if not music_player.playing:
			music_player.play()
	else:
		music_player.stop()

func play_sound(id: String, pitch := 1.0) -> void:
	if DisplayServer.get_name() == "headless": return
	if not Settings.values.sound or not sounds.has(id):
		return
	var player: AudioStreamPlayer = players[voice % players.size()]
	voice += 1
	player.stream = sounds[id]
	player.pitch_scale = pitch
	player.volume_db = {"shoot": -9.0, "scribble": -10.0}.get(id, -4.0)
	player.play()

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
