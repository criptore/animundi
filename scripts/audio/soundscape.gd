## Sound and music (1.0, docs/POLISH.md), made by the game itself: no recording ships with it.
## - Effects: each sound is synthesised once into a short wave (noise, tones, envelopes) and
##   played on the Effects bus: fire, lightning, rain, the fall of a meteor or a bomb, quakes,
##   blessings and miracles, sickness, curses, war drums, the fanfare of a new age...
## - Music: a slow generative piece on the Music bus. A soft drone holds the root while notes of
##   a scale fall one by one, now and then two together. The scale, the root and the pace follow
##   the mood of the world (sim/Eras.cs): bright eras in major, dark ones in minor, magical ones in
##   a whole-tone scale; a nuclear winter slows and darkens it.
## - Ambience: wind and the sea, a quiet loop on the Ambience bus.
## The buses are made here; the settings window sets their volumes.
extends Node

const RATE := 22050
const BUSES := ["Music", "Effects", "Ambience"]
## Scales by mood of the world: semitones over the root, the root's pitch (MIDI), seconds between notes.
const MOODS := {
	"calm": [[0, 2, 4, 7, 9], 57, 2.2], "bright": [[0, 2, 4, 5, 7, 9, 11], 60, 1.7],
	"dark": [[0, 2, 3, 5, 7, 8, 10], 52, 2.8], "rainy": [[0, 2, 3, 5, 7, 9, 10], 55, 2.4],
	"cold": [[0, 3, 5, 7, 10], 53, 3.2], "scorching": [[0, 1, 4, 5, 7, 8, 10], 56, 1.9],
	"magical": [[0, 2, 4, 6, 8, 10], 61, 2.0], "winter": [[0, 3, 7, 8], 48, 4.0],
}

var music_on := true
var _effects: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []
var _drone: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _sounds := {}
var _notes := {}
var _mood := "calm"
var _next_note := 1.0
var _rng := RandomNumberGenerator.new()
var _last_played := {}


func _init() -> void:
	_rng.seed = 7
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(0.55))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), linear_to_db(0.35))
	for k in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		_effects.append(p)
	for k in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_music.append(p)
	_drone = AudioStreamPlayer.new()
	_drone.bus = "Music"
	add_child(_drone)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Ambience"
	_ambience.stream = ambience_loop()
	add_child(_ambience)


## Starts the ambience and the music (once a world is shown).
func start() -> void:
	if not is_inside_tree():
		return
	if not _ambience.playing:
		_ambience.play()
	set_mood(_mood, true)


## Volume of a bus, 0..1 ("Master", "Music", "Effects", "Ambience").
func set_volume(bus: String, value: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(value, 0.0001)))
		AudioServer.set_bus_mute(i, value <= 0.001)


## The mood of the world changed (an era id of data/eras.json, or "winter"): the music follows.
func set_mood(mood: String, force := false) -> void:
	if not MOODS.has(mood):
		mood = "calm"
	if mood == _mood and not force:
		return
	_mood = mood
	var m: Array = MOODS[mood]
	_drone.stream = tone(m[1] - 12, 9.0, "pad", true)
	if music_on and is_inside_tree():
		_drone.play()


func _process(delta: float) -> void:
	if not music_on or not _drone.playing:
		return
	_next_note -= delta
	if _next_note > 0.0:
		return
	var m: Array = MOODS[_mood]
	var scale: Array = m[0]
	_next_note = m[2] * _rng.randf_range(0.6, 1.5)
	var count := 2 if _rng.randf() < 0.25 else 1
	for k in count:
		var octave := 12 * _rng.randi_range(0, 1)
		var pitch: int = m[1] + scale[_rng.randi_range(0, scale.size() - 1)] + octave
		var p := _free_player(_music)
		p.stream = tone(pitch, 3.5, "bell")
		p.volume_db = _rng.randf_range(-10.0, -4.0)
		p.play()


## Plays a sound effect by name (see SOUNDS). The same sound is not played twice in 80 ms.
func play(name: String, volume_db := 0.0) -> void:
	if not SOUNDS.has(name) or not is_inside_tree():
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(name, -1000)) < 80:
		return
	_last_played[name] = now
	if not _sounds.has(name):
		_sounds[name] = call(SOUNDS[name])
	var p := _free_player(_effects)
	p.stream = _sounds[name]
	p.volume_db = volume_db
	p.play()


func _free_player(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for p in pool:
		if not p.playing:
			return p
	return pool[_rng.randi_range(0, pool.size() - 1)]


## The effects: name → its maker.
const SOUNDS := {
	"click": "_click", "fire": "_fire", "lightning": "_lightning", "rain": "_rain", "boom": "_boom", "bomb": "_bomb",
	"quake": "_quake", "bless": "_bless", "miracle": "_miracle", "sick": "_sick", "curse": "_curse", "drums": "_drums",
	"fanfare": "_fanfare", "land": "_land", "wind": "_wind", "chime": "_chime", "rocket": "_rocket", "achievement": "_achievement",
}


# ---------------------------------------------------------------- synthesis

## A wave from float samples (-1..1).
static func wave(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w


static func midi_hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


## A note: "bell" (a sine and its overtones, struck then fading), "pad" (soft, slow, for the
## drone; looping), "pluck" (short).
func tone(pitch: float, seconds: float, kind := "bell", loop := false) -> AudioStreamWAV:
	var key := "%s:%s:%s:%s" % [pitch, seconds, kind, loop]
	if _notes.has(key):
		return _notes[key]
	var n := int(seconds * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var f := midi_hz(pitch)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		match kind:
			"pad":
				# A slow chorus of three detuned sines, the loop's ends meeting.
				v = (sin(TAU * f * t) + 0.6 * sin(TAU * f * 1.003 * t) + 0.4 * sin(TAU * f * 2.0 * t)) * 0.16
				v *= 0.75 + 0.25 * sin(TAU * t / seconds)
			"pluck":
				v = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 3.0 * t)) * exp(-t * 6.0) * 0.4
			_:
				v = (sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.0 * t) + 0.12 * sin(TAU * f * 3.01 * t)) * exp(-t * 1.4) * 0.35
				v *= minf(1.0, t * 80.0)
		s[i] = v
	var w := wave(s, loop)
	_notes[key] = w
	return w


## Noise shaped by an envelope and a one-pole low-pass (lower `cutoff` = darker).
func noise(seconds: float, attack: float, decay: float, cutoff: float, gain := 0.6) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	var a := clampf(cutoff, 0.001, 1.0)
	for i in n:
		var t := float(i) / RATE
		y += a * (_rng.randf_range(-1.0, 1.0) - y)
		var env := minf(1.0, t / maxf(attack, 0.0001)) * exp(-maxf(0.0, t - attack) * decay)
		s[i] = y * env * gain
	return s


func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate() if a.size() >= b.size() else b.duplicate()
	var other := b if a.size() >= b.size() else a
	for i in other.size():
		out[i] += other[i]
	return out


func _notes_seq(pitches: Array, step: float, length: float, kind := "bell", gain := 1.0) -> PackedFloat32Array:
	var n := int((step * pitches.size() + length) * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for k in pitches.size():
		var f := midi_hz(pitches[k])
		var start := int(k * step * RATE)
		for i in int(length * RATE):
			if start + i >= n:
				break
			var t := float(i) / RATE
			var v := (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * exp(-t * (4.0 if kind == "pluck" else 1.8)) * minf(1.0, t * 100.0)
			s[start + i] += v * 0.3 * gain
	return s


func _click() -> AudioStreamWAV:
	return wave(_notes_seq([84], 0.0, 0.06, "pluck", 0.8))


func _fire() -> AudioStreamWAV:
	return wave(noise(0.7, 0.05, 3.5, 0.25, 0.7))


func _lightning() -> AudioStreamWAV:
	return wave(_mix(noise(0.25, 0.001, 18.0, 0.9, 0.9), noise(1.6, 0.05, 1.8, 0.03, 1.4)))


func _rain() -> AudioStreamWAV:
	return wave(noise(1.4, 0.2, 1.2, 0.6, 0.35))


func _boom() -> AudioStreamWAV:
	return wave(_mix(noise(0.15, 0.001, 20.0, 0.6, 0.8), noise(2.2, 0.02, 1.4, 0.02, 1.8)))


func _bomb() -> AudioStreamWAV:
	var s := _mix(noise(0.3, 0.001, 9.0, 0.7, 1.0), noise(5.0, 0.05, 0.6, 0.012, 2.4))
	return wave(s)


func _quake() -> AudioStreamWAV:
	var s := noise(2.5, 0.3, 1.0, 0.01, 2.6)
	for i in s.size():
		s[i] *= 0.7 + 0.3 * sin(TAU * 7.0 * i / RATE)
	return wave(s)


func _bless() -> AudioStreamWAV:
	return wave(_notes_seq([72, 76, 79, 84], 0.09, 1.0))


func _miracle() -> AudioStreamWAV:
	return wave(_mix(_notes_seq([67, 71, 74, 79, 83, 86], 0.08, 1.6), _notes_seq([55], 0.0, 2.2)))


func _sick() -> AudioStreamWAV:
	return wave(_notes_seq([50, 49, 47], 0.22, 0.7))


func _curse() -> AudioStreamWAV:
	return wave(_mix(_notes_seq([46, 52], 0.0, 1.4), noise(1.0, 0.3, 2.0, 0.05, 0.4)))


func _drums() -> AudioStreamWAV:
	var s := PackedFloat32Array()
	s.resize(int(1.6 * RATE))
	for hit in [0.0, 0.35, 0.7, 0.85, 1.05]:
		var start := int(hit * RATE)
		for i in int(0.4 * RATE):
			if start + i >= s.size():
				break
			var t := float(i) / RATE
			s[start + i] += sin(TAU * (90.0 - 40.0 * t) * t) * exp(-t * 9.0) * 0.9
	return wave(s)


func _fanfare() -> AudioStreamWAV:
	return wave(_notes_seq([60, 64, 67, 72, 67, 72], 0.16, 0.9))


func _achievement() -> AudioStreamWAV:
	return wave(_notes_seq([76, 79, 84, 88], 0.07, 0.8, "pluck", 1.2))


func _land() -> AudioStreamWAV:
	return wave(noise(0.6, 0.02, 4.0, 0.04, 1.4))


func _wind() -> AudioStreamWAV:
	return wave(noise(1.8, 0.5, 1.2, 0.08, 0.6))


func _chime() -> AudioStreamWAV:
	return wave(_notes_seq([79, 84], 0.12, 0.8))


func _rocket() -> AudioStreamWAV:
	return wave(noise(3.0, 0.4, 0.9, 0.15, 0.8))


## Wind over the land and a far sea: two filtered noises swelling slowly, looped.
func ambience_loop() -> AudioStreamWAV:
	var seconds := 6.0
	var n := int(seconds * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var a := 0.0
	var b := 0.0
	for i in n:
		var t := float(i) / RATE
		a += 0.02 * (_rng.randf_range(-1.0, 1.0) - a)
		b += 0.15 * (_rng.randf_range(-1.0, 1.0) - b)
		var swell := 0.6 + 0.4 * sin(TAU * t / seconds)
		var waves := 0.5 + 0.5 * sin(TAU * t * 2.0 / seconds + 1.0)
		s[i] = a * 1.6 * swell + b * 0.12 * waves
	# The loop's ends fade into each other.
	var fade := int(0.3 * RATE)
	for i in fade:
		var k := float(i) / fade
		s[i] = s[i] * k + s[n - fade + i] * (1.0 - k)
	return wave(s.slice(0, n - fade), true)
