extends Node
## Sound effects, music and ambience by slot name (autoload "Sfx").
## A slot is res://audio/<name>.ogg (or .wav); extra variants <name>_1, <name>_2 ...
## are picked at random. Missing slots are silent, so any sound can be replaced or
## added by dropping a file with the slot's name into audio/ and rebuilding.
## See audio/README.md for the list of slots.
##
## API
##   play(name, pos, volume_db := 0.0, pitch_var := 0.06)   positional one-shot
##   play_ui(name, volume_db := 0.0, pitch_var := 0.0)      non-positional one-shot
##   hold(key, name, pos, on, volume_db := 0.0)             looped while on (engines, flamer)
##   music(state)        "calm" | "combat" | "extract" | "off"
##   ambience(names)     e.g. ["amb_wind", "amb_insects"]; [] fades everything out
##   set_bus_volume(bus, linear)   bus: "Master" | "Music" | "SFX" | "Ambience"
##   stop_all()          stops one-shots and held loops (not music / ambience)
##   stop_music()        music("off") + ambience([])
## Web: browsers only start audio after a user gesture, so music()/ambience() calls made
## before the first input event are remembered and started on that first tap/key.

const DIR := "res://audio/"
const EXTS := ["ogg", "wav"]
const MAX_VARIANTS := 8
const POOL := 32
## px per metre of the game world (Firearm.PX_PER_M).
const PX_PER_M := 60.0
## Positional sounds fade to silence at this distance from the camera (top-down view:
## things on screen, up to ~40 m away, stay clearly audible).
const MAX_DISTANCE := 90.0 * PX_PER_M
const ATTENUATION := 1.0
## s: the same slot will not restart faster than this (dozens of bots firing).
const MIN_GAP := 0.035
## At most this many simultaneous voices per slot (avoids clipping when many fire).
const MAX_VOICES := 6
const XFADE := 1.5
const SILENT_DB := -60.0
const BUSES := ["Music", "SFX", "Ambience"]
## Slots without their own file yet borrow another slot's sound.
const ALIASES := {
	"plasma_shot": "bot_heavy_blaster", "hit_flesh": "player_hit", "claw": "player_hit",
	"voteless_death": "player_hit", "illuminate_death": "bot_death", "shield_hit": "hit_armor",
	"shield_break": "explosion", "watcher_call": "beacon", "beam_charge": "strat_ready",
	"harvester_beam": "flamer", "warp_ship": "bot_drop", "evac_rocket": "explosion_big",
	"sentry_shot": "smg_shot",
}

var _cache := {} # name -> Array[AudioStream]
var _loop_cache := {} # name -> AudioStream (loop enabled copy)
var _players: Array[AudioStreamPlayer2D] = []
var _slots := PackedStringArray() # slot name each pool player last played (parallel to _players)
var _ui: Array[AudioStreamPlayer] = []
var _next := 0
var _next_ui := 0
var _last := {} # name -> msec
var _loops := {} # key -> AudioStreamPlayer2D

var _unlocked := false
var _music_state := "off"
var _music_wanted := "off"
var _calm: AudioStreamPlayer
var _combat: AudioStreamPlayer
var _stinger: AudioStreamPlayer
var _music_tween: Tween
var _amb_wanted: Array = []
var _amb := {} # name -> AudioStreamPlayer
var _sync_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # music keeps fading while the game is paused
	_setup_buses()
	for i in POOL:
		var p := AudioStreamPlayer2D.new()
		p.max_distance = MAX_DISTANCE
		p.attenuation = ATTENUATION
		p.panning_strength = 0.6
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
		_slots.append("")
	for i in 4:
		var u := AudioStreamPlayer.new()
		u.bus = "SFX"
		add_child(u)
		_ui.append(u)
	_calm = _make_music_player()
	_combat = _make_music_player()
	_stinger = _make_music_player()
	# Native platforms can play right away; the web has to wait for the first gesture.
	_unlocked = not OS.has_feature("web")
	set_process_input(not _unlocked)
	set_process(true)


func _setup_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")


func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = SILENT_DB
	add_child(p)
	return p


func set_bus_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.0001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


func _input(event: InputEvent) -> void:
	if _unlocked:
		return
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey \
			or event is InputEventJoypadButton:
		if (event is InputEventMouseButton or event is InputEventScreenTouch) and not event.pressed:
			return
		_unlocked = true
		set_process_input(false)
		_apply_music(_music_wanted)
		_apply_ambience()


func streams(name: String) -> Array:
	if _cache.has(name):
		return _cache[name]
	var list: Array = []
	for i in MAX_VARIANTS:
		var base := name if i == 0 else "%s_%d" % [name, i]
		var found := false
		for ext in EXTS:
			var path: String = DIR + base + "." + ext
			if ResourceLoader.exists(path):
				list.append(load(path))
				found = true
				break
		if not found and i > 0:
			break
	if list.is_empty() and ALIASES.has(name):
		list = streams(ALIASES[name])
	_cache[name] = list
	return list


## Loop-enabled copy of a slot's first stream (the shared one stays one-shot).
func _loop_stream(name: String) -> AudioStream:
	if _loop_cache.has(name):
		return _loop_cache[name]
	var list := streams(name)
	var s: AudioStream = null
	if not list.is_empty():
		s = list[0].duplicate()
		if s is AudioStreamOggVorbis:
			s.loop = true
		elif s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
	_loop_cache[name] = s
	return s


func _pick(name: String) -> AudioStream:
	var list := streams(name)
	if list.is_empty():
		return null
	var now := Time.get_ticks_msec()
	if now - int(_last.get(name, -100000)) < MIN_GAP * 1000.0:
		return null
	_last[name] = now
	return list[randi() % list.size()]


func _voices(name: String) -> int:
	var n := 0
	for i in _slots.size():
		if _slots[i] == name and _players[i].playing:
			n += 1
	return n


## Starting a voice (decoder set-up) is the costly part of a sound: at most this many positional
## one-shots start per rendered frame (others of the low-priority kind are skipped).
const MAX_STARTS_PER_FRAME := 3
const PRIORITY := ["explosion", "death", "orbital", "eagle", "hellpod", "pelican", "deploy", "splash", "player", "beacon", "strat"]
var _start_frame := -1
var _starts := 0


func _is_priority(name: String) -> bool:
	for k in PRIORITY:
		if name.contains(k):
			return true
	return false


## Positional sound at a world position.
func play(name: String, pos: Vector2, volume_db := 0.0, pitch_var := 0.06) -> void:
	var s := _pick(name)
	if s == null or _voices(name) >= MAX_VOICES:
		return
	var f := Engine.get_process_frames()
	if f != _start_frame:
		_start_frame = f
		_starts = 0
	if _starts >= MAX_STARTS_PER_FRAME and not _is_priority(name):
		return
	_starts += 1
	var p := _players[_next]
	_slots[_next] = name
	_next = (_next + 1) % POOL
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


## Non-positional (UI, stratagem input, the player's own gun).
func play_ui(name: String, volume_db := 0.0, pitch_var := 0.0) -> void:
	var s := _pick(name)
	if s == null:
		return
	var u := _ui[_next_ui]
	_next_ui = (_next_ui + 1) % _ui.size()
	u.stream = s
	u.volume_db = volume_db
	u.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	u.play()


## Held sound (flamer, chainsaw, engines): call every frame with on=true while it
## should sound; on=false stops it. key identifies the source.
func hold(key: String, name: String, pos: Vector2, on: bool, volume_db := 0.0) -> void:
	var p: AudioStreamPlayer2D = _loops.get(key)
	if not on:
		if p:
			p.queue_free()
			_loops.erase(key)
		return
	if p == null:
		var s := _loop_stream(name)
		if s == null:
			return
		p = AudioStreamPlayer2D.new()
		p.max_distance = MAX_DISTANCE
		p.attenuation = ATTENUATION
		p.panning_strength = 0.6
		p.bus = "SFX"
		p.volume_db = volume_db
		add_child(p)
		p.stream = s
		p.finished.connect(p.play) # fallback for streams that did not loop
		_loops[key] = p
		p.global_position = pos
		p.play()
	p.global_position = pos


func stop_all() -> void:
	for k in _loops.keys():
		hold(k, "", Vector2.ZERO, false)
	for p in _players:
		p.stop()


func stop_music() -> void:
	music("off")
	ambience([])


# ---------------------------------------------------------------- music

## Music state: "calm" (bed), "combat" (bed + percussion layer, 1.5 s crossfade),
## "extract" (stinger over the bed, then calm), "off" (fade out).
func music(state: String) -> void:
	if not state in ["calm", "combat", "extract", "off"]:
		push_warning("Sfx.music: unknown state '%s'" % state)
		return
	_music_wanted = state
	if _unlocked:
		_apply_music(state)


func _kill_tween() -> void:
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)


func _fade(p: AudioStreamPlayer, to_db: float, t := XFADE) -> void:
	_music_tween.tween_property(p, "volume_db", to_db, t)


func _start_beds() -> void:
	if _calm.playing:
		return
	var a := _loop_stream("music_calm")
	var b := _loop_stream("music_combat")
	if a == null:
		return
	_calm.stream = a
	_calm.volume_db = SILENT_DB
	_calm.play()
	if b:
		_combat.stream = b
		_combat.volume_db = SILENT_DB
		_combat.play() # same frame as calm: the two loops stay in sync


func _stop_beds() -> void:
	_calm.stop()
	_combat.stop()


func _apply_music(state: String) -> void:
	_kill_tween()
	match state:
		"off":
			for p in [_calm, _combat, _stinger]:
				_fade(p, SILENT_DB)
			_music_tween.chain().tween_callback(func():
				if _music_state == "off":
					_stop_beds()
					_stinger.stop())
		"calm", "combat":
			_start_beds()
			_fade(_calm, 0.0 if state == "calm" else -3.0)
			_fade(_combat, SILENT_DB if state == "calm" else 0.0)
			_fade(_stinger, SILENT_DB, 0.5)
		"extract":
			_start_beds()
			var sl := streams("music_extract") # the stinger plays once (not looped)
			var dur := 6.0
			if not sl.is_empty():
				dur = sl[0].get_length()
				_stinger.stream = sl[0]
				_stinger.volume_db = 0.0
				_stinger.play()
			_fade(_combat, SILENT_DB)
			_fade(_calm, -8.0, 0.5)
			_music_tween.chain().tween_interval(maxf(dur - 1.5, 0.5))
			_music_tween.chain().tween_property(_calm, "volume_db", 0.0, 2.0)
	_music_state = state


# ---------------------------------------------------------------- ambience

## Loops the given amb_* slots (e.g. ["amb_wind", "amb_insects"]) and crossfades from
## whatever was playing before. An empty array fades the ambience out.
func ambience(names: Array) -> void:
	_amb_wanted = names.duplicate()
	if _unlocked:
		_apply_ambience()


func _apply_ambience() -> void:
	for n in _amb.keys():
		if not n in _amb_wanted:
			var old: AudioStreamPlayer = _amb[n]
			_amb.erase(n)
			var t := create_tween()
			t.tween_property(old, "volume_db", SILENT_DB, XFADE)
			t.tween_callback(old.queue_free)
	for n in _amb_wanted:
		if _amb.has(n):
			continue
		var s := _loop_stream(n)
		if s == null:
			continue
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		p.stream = s
		p.volume_db = SILENT_DB
		add_child(p)
		p.play()
		var t := create_tween()
		t.tween_property(p, "volume_db", 0.0, XFADE)
		_amb[n] = p


func _process(delta: float) -> void:
	# Keep the combat layer locked to the calm bed (both are 90 s loops).
	_sync_t += delta
	if _sync_t < 1.0:
		return
	_sync_t = 0.0
	if _calm.playing and _combat.playing:
		var a := _calm.get_playback_position()
		var b := _combat.get_playback_position()
		var span := _calm.stream.get_length()
		var d := absf(a - b)
		if minf(d, span - d) > 0.08:
			_combat.seek(a)
