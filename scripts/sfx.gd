extends Node
## Sound effects by slot name (autoload "Sfx").
## A slot is res://audio/<name>.ogg (or .wav); extra variants <name>_1, <name>_2 ...
## are picked at random. Missing slots are silent, so any sound can be replaced or
## added by dropping a file with the slot's name into audio/ and rebuilding.
## See audio/README.md for the list of slots.

const DIR := "res://audio/"
const EXTS := ["ogg", "wav"]
const MAX_VARIANTS := 8
const POOL := 24
## px: positional sounds fade to silence at this distance from the camera.
const MAX_DISTANCE := 2200.0
## s: the same slot will not restart faster than this (dozens of bots firing).
const MIN_GAP := 0.035

var _cache := {} # name -> Array[AudioStream]
var _players: Array[AudioStreamPlayer2D] = []
var _ui: Array[AudioStreamPlayer] = []
var _next := 0
var _next_ui := 0
var _last := {} # name -> msec
var _loops := {} # key -> AudioStreamPlayer2D


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer2D.new()
		p.max_distance = MAX_DISTANCE
		p.attenuation = 1.4
		add_child(p)
		_players.append(p)
	for i in 4:
		var u := AudioStreamPlayer.new()
		u.process_mode = Node.PROCESS_MODE_ALWAYS # menu clicks while paused
		add_child(u)
		_ui.append(u)


func streams(name: String) -> Array:
	if _cache.has(name):
		return _cache[name]
	var list: Array = []
	for i in MAX_VARIANTS:
		var base := name if i == 0 else "%s_%d" % [name, i]
		var found := false
		for ext in EXTS:
			var path := DIR + base + "." + ext
			if ResourceLoader.exists(path):
				list.append(load(path))
				found = true
				break
		if not found and i > 0:
			break
	_cache[name] = list
	return list


func _pick(name: String) -> AudioStream:
	var list := streams(name)
	if list.is_empty():
		return null
	var now := Time.get_ticks_msec()
	if now - int(_last.get(name, -100000)) < MIN_GAP * 1000.0:
		return null
	_last[name] = now
	return list[randi() % list.size()]


## Positional sound at a world position.
func play(name: String, pos: Vector2, volume_db := 0.0, pitch_var := 0.06) -> void:
	var s := _pick(name)
	if s == null:
		return
	var p := _players[_next]
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
		var list := streams(name)
		if list.is_empty():
			return
		p = AudioStreamPlayer2D.new()
		p.max_distance = MAX_DISTANCE
		p.attenuation = 1.4
		p.volume_db = volume_db
		add_child(p)
		p.stream = list[0]
		p.finished.connect(p.play)
		_loops[key] = p
		p.global_position = pos
		p.play()
	p.global_position = pos


func stop_all() -> void:
	for k in _loops.keys():
		hold(k, "", Vector2.ZERO, false)
	for p in _players:
		p.stop()
