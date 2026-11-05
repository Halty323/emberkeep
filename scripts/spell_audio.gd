class_name SpellAudio
extends RefCounted
## The sounds spells make, synthesised from a few simple voices so no audio
## files ship with the game: sines swept in pitch, buzzing saws, filtered
## noise swept dull or bright, sparse crackle, and bright pings. Each recipe
## builds one sample buffer; Audio renders them all on a worker thread at
## start-up. Mono, 22050 Hz, peaks kept under clipping.
const RATE := 22050

static func recipes() -> Dictionary:
	return {
		# A flying spell's cast, by element (its look shifts the pitch).
		"cast_ember": func(): return mix([sweep(.24, 520, 600, .35, .004, 9.0), noise(.24, .45, .25, .05, .01, 10.0, 11), crackle(.24, 14, .35, 12)]),
		"cast_frost": func(): return mix([sweep(.28, 1180, 1260, .3, .003, 8.0), sweep(.28, 1771, 1890, .14, .003, 11.0), sweep(.28, 2360, 2400, .08, .002, 14.0)]),
		"cast_storm": func(): return mix([buzz(.2, 1200, 380, .32, .002, 10.0, 5), crackle(.2, 22, .4, 13)]),
		"cast_venom": func(): return mix([wobble(.24, 260, 520, .45, 18.0, .03), noise(.24, .18, .08, .02, .01, 12.0, 14)]),
		"cast_radiance": func(): return mix([sweep(.34, 880, 900, .28, .02, 6.0), sweep(.34, 1320, 1350, .18, .03, 6.5), sweep(.34, 1760, 1800, .08, .04, 7.0)]),
		"cast_glass": func(): return mix([ping(.24, 1600, .3, 0.0, 16.0), ping(.24, 2410, .22, .03, 18.0), ping(.24, 3200, .1, .055, 22.0)]),
		"cast_wax": func(): return mix([sweep(.22, 240, 140, .5, .004, 9.0), noise(.22, .25, .06, .02, .005, 14.0, 15)]),
		"cast_tide": func(): return mix([wobble(.26, 420, 260, .3, 26.0, .05), noise(.26, .35, .3, .04, .01, 9.0, 16)]),
		# A ray: a bright buzzing beam with a whine riding over it.
		"ray": func(): return mix([buzz(.34, 180, 170, .32, .006, 4.0, 6), sweep(.34, 1400, 2300, .12, .01, 5.0), noise(.34, .12, .5, .3, .005, 6.0, 21)]),
		"hum": func(): return mix([tremolo(buzz(1.3, 110, 104, .28, .08, 1.4, 5), 9.0)]),
		# Lightning: crackle gathering, then the crack and a rumble after it.
		"charge": func(): return mix([swell(crackle(.14, 40, .5, 31), 2.4), swell(sweep(.14, 300, 1300, .2, .0, 0.0), 2.0)]),
		"crack": func(): return mix([noise(.42, .45, .4, .08, .004, 16.0, 32), sweep(.42, 85, 50, .45, .004, 7.0), crackle(.42, 12, .22, 33)]),
		"thunder": func(): return mix([noise(.8, .4, .35, .05, .006, 9.0, 34), noise(.8, .4, .05, .02, .01, 3.0, 35), sweep(.8, 60, 32, .5, .01, 3.5)]),
		# An eruption: a breath drawn as the rune is drawn, the ground stirring
		# under it, and then what rises, each element its own way.
		"conjure": func(): return mix([swell(noise(.2, .3, .08, .3, .0, 0.0, 41), 1.6)]),
		"rumble": func(): return mix([swell(noise(.36, .6, .02, .05, .0, 0.0, 42), 2.2), swell(sweep(.36, 48, 62, .4, .0, 0.0), 2.0)]),
		"whistle": func(): return mix([swell(sweep(.36, 1900, 520, .32, .0, 0.0), 1.4), swell(noise(.36, .2, .3, .1, .0, 0.0, 43), 2.0)]),
		"rise_flame": func(): return mix([noise(.55, .55, .35, .04, .008, 6.0, 51), sweep(.55, 95, 48, .55, .004, 5.0), crackle(.55, 26, .35, 52)]),
		"rise_ice": func(): return mix([crackle(.5, 40, .55, 53), ping(.5, 1520, .25, 0.0, 9.0), ping(.5, 2280, .18, .05, 11.0), noise(.5, .25, .8, .4, .002, 12.0, 54)]),
		"rise_skyfall": func(): return mix([noise(.8, .4, .35, .05, .006, 9.0, 55), sweep(.8, 60, 32, .5, .01, 3.5), crackle(.8, 12, .2, 56)]),
		"rise_bubbles": func(): return mix([bubbles(.65, 7, 280, 640, .4, 57)]),
		"rise_pillar": func(): return mix([chord(.9, [440.0, 554.4, 659.3, 880.0], .16, .12, 2.6), sweep(.9, 1760, 1790, .05, .2, 3.0)]),
		"rise_crystal": func(): return mix([pings(.55, 16, 1800, 4200, .25, 58), noise(.55, .35, .9, .5, .001, 16.0, 59)]),
		"rise_geyser": func(): return mix([noise(.6, .7, .2, .03, .01, 5.0, 60), bubbles(.6, 5, 160, 320, .3, 61)]),
		"rise_spout": func(): return mix([noise(.6, .75, .45, .05, .004, 6.0, 62), pings(.6, 6, 700, 1400, .15, 63)]),
		"rise_meteor": func(): return mix([noise(.9, .6, .4, .03, .006, 5.0, 64), sweep(.9, 75, 34, .7, .003, 3.2), crackle(.9, 30, .35, 65)]),
	}

static func mix(layers: Array) -> AudioStreamWAV:
	var length := 0
	for layer in layers: length = maxi(length, layer.size())
	var out := PackedFloat32Array()
	out.resize(length)
	for layer in layers:
		for i in layer.size(): out[i] += layer[i]
	var peak := 0.0
	for value in out: peak = maxf(peak, absf(value))
	var scale := .92 / peak if peak > .92 else 1.0
	var bytes := PackedByteArray()
	bytes.resize(length * 2)
	for i in length: bytes.encode_s16(i * 2, int(clampf(out[i] * scale, -1.0, 1.0) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream

static func blank(duration: float) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(int(RATE * duration))
	return buffer

## A rise from nothing over `attack` seconds, then an exponential fall.
static func envelope(t: float, attack: float, decay: float) -> float:
	return (minf(t / attack, 1.0) if attack > 0 else 1.0) * exp(-t * decay)

## A sine swept from one pitch to another.
static func sweep(duration: float, start: float, end: float, amplitude: float, attack: float, decay: float) -> PackedFloat32Array:
	var buffer := blank(duration)
	var phase := 0.0
	for i in buffer.size():
		var t := float(i) / RATE
		phase += TAU * lerpf(start, end, t / duration) / RATE
		buffer[i] = sin(phase) * amplitude * envelope(t, attack, decay)
	return buffer

## A sine whose pitch wobbles as it sweeps: a bubble, a splash.
static func wobble(duration: float, start: float, end: float, amplitude: float, rate: float, depth: float) -> PackedFloat32Array:
	var buffer := blank(duration)
	var phase := 0.0
	for i in buffer.size():
		var t := float(i) / RATE
		phase += TAU * lerpf(start, end, t / duration) * (1.0 + depth * sin(TAU * rate * t)) / RATE
		buffer[i] = sin(phase) * amplitude * envelope(t, .006, 8.0)
	return buffer

## A buzzing saw of a few harmonics, swept.
static func buzz(duration: float, start: float, end: float, amplitude: float, attack: float, decay: float, harmonics: int) -> PackedFloat32Array:
	var buffer := blank(duration)
	var phase := 0.0
	for i in buffer.size():
		var t := float(i) / RATE
		phase += TAU * lerpf(start, end, t / duration) / RATE
		var value := 0.0
		for k in range(1, harmonics + 1): value += sin(phase * k) / k
		buffer[i] = value * .55 * amplitude * envelope(t, attack, decay)
	return buffer

## Noise through a one-pole filter swept from bright (1) to dull (0).
static func noise(duration: float, amplitude: float, bright_start: float, bright_end: float, attack: float, decay: float, seed_value: int) -> PackedFloat32Array:
	var gen := RandomNumberGenerator.new()
	gen.seed = seed_value
	var buffer := blank(duration)
	var low := 0.0
	for i in buffer.size():
		var t := float(i) / RATE
		var bright := clampf(lerpf(bright_start, bright_end, t / duration), .005, 1.0)
		low += (gen.randf_range(-1.0, 1.0) - low) * bright
		buffer[i] = low * amplitude * (1.0 + (1.0 - bright) * 2.0) * envelope(t, attack, decay)
	return buffer

## Sparse sharp clicks: sparks, ice, crackling fire.
static func crackle(duration: float, count: int, amplitude: float, seed_value: int) -> PackedFloat32Array:
	var gen := RandomNumberGenerator.new()
	gen.seed = seed_value
	var buffer := blank(duration)
	for c in count:
		var at := gen.randi_range(0, maxi(1, buffer.size() - 200))
		var level := gen.randf_range(.3, 1.0) * amplitude
		for j in 140:
			if at + j >= buffer.size(): break
			buffer[at + j] += gen.randf_range(-1.0, 1.0) * level * exp(-j / 18.0)
	return buffer

## One bell-like ping starting a moment in.
static func ping(duration: float, pitch: float, amplitude: float, delay: float, decay: float) -> PackedFloat32Array:
	var buffer := blank(duration)
	for i in buffer.size():
		var t := float(i) / RATE - delay
		if t < 0: continue
		buffer[i] = (sin(TAU * pitch * t) + .3 * sin(TAU * pitch * 2.76 * t)) * amplitude * envelope(t, .002, decay)
	return buffer

## Many pings scattered in pitch and time: tinkling glass, droplets.
static func pings(duration: float, count: int, low: float, high: float, amplitude: float, seed_value: int) -> PackedFloat32Array:
	var gen := RandomNumberGenerator.new()
	gen.seed = seed_value
	var buffer := blank(duration)
	for c in count:
		var start := gen.randf_range(0.0, duration * .7)
		var pitch := gen.randf_range(low, high)
		var level := gen.randf_range(.4, 1.0) * amplitude
		for i in range(int(start * RATE), buffer.size()):
			var t := float(i) / RATE - start
			if t > .25: break
			buffer[i] += sin(TAU * pitch * t) * level * envelope(t, .001, 22.0)
	return buffer

## Bubbles rising and popping one after another, each a little higher.
static func bubbles(duration: float, count: int, low: float, high: float, amplitude: float, seed_value: int) -> PackedFloat32Array:
	var gen := RandomNumberGenerator.new()
	gen.seed = seed_value
	var buffer := blank(duration)
	for c in count:
		var start := duration * .8 * c / count + gen.randf_range(0.0, .04)
		var pitch := lerpf(low, high, float(c) / count) * gen.randf_range(.9, 1.1)
		var phase := 0.0
		for i in range(int(start * RATE), buffer.size()):
			var t := float(i) / RATE - start
			if t > .09: break
			phase += TAU * pitch * (1.0 + t * 9.0) / RATE
			buffer[i] += sin(phase) * amplitude * envelope(t, .004, 30.0)
	return buffer

## A soft held chord swelling and fading: light.
static func chord(duration: float, pitches: Array, amplitude: float, attack: float, decay: float) -> PackedFloat32Array:
	var buffer := blank(duration)
	for i in buffer.size():
		var t := float(i) / RATE
		var value := 0.0
		for pitch in pitches: value += sin(TAU * pitch * t * (1.0 + .002 * sin(t * 5.0)))
		buffer[i] = value * amplitude * envelope(t, attack, decay)
	return buffer

## Shapes a buffer to grow louder toward its end: a build-up.
static func swell(buffer: PackedFloat32Array, power: float) -> PackedFloat32Array:
	var count := buffer.size()
	for i in count: buffer[i] *= pow(float(i) / count, power) * (1.0 if i < count - 60 else float(count - i) / 60.0)
	return buffer

## A slow pulse in loudness: a held beam.
static func tremolo(buffer: PackedFloat32Array, rate: float) -> PackedFloat32Array:
	for i in buffer.size(): buffer[i] *= .7 + .3 * sin(TAU * rate * float(i) / RATE)
	return buffer
