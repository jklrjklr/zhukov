class_name Stratagems
extends Node2D
## Helldivers 2 stratagems.
## Open the menu (STRATAGEM button), enter a code of arrows (swipe or D-pad); when a
## code matches an available stratagem the Helldiver throws its beacon (to the ADS
## circle, or ~8 m ahead). After the call-in delay the effect arrives:
##   RESUPPLY            supply pod (2 pickups: ammo, grenades, stims)
##   EAGLE AIRSTRIKE     a line of bombs across the beacon (2 uses, then rearm)
##   EAGLE 500KG BOMB    one huge bomb (1 use, then rearm)
##   ORBITAL PRECISION   a single devastating shell after a longer delay
##   EAT-17              pod with 2 disposable anti-tank launchers
## Pods and shells hurt everything nearby, the Helldiver included.
## Draws beacons, falling pods, eagle passes and orbital beams (world space, on top).

enum Dir { UP, DOWN, LEFT, RIGHT }

const PX := Firearm.PX_PER_M
const U := Dir.UP
const D := Dir.DOWN
const L := Dir.LEFT
const R := Dir.RIGHT
const BLUE := Color(0.3, 0.6, 1.0)
const RED := Color(1.0, 0.3, 0.2)
const GREEN := Color(0.4, 0.85, 0.4)

const DEFS := {
	"resupply": {"name": "Resupply", "code": [D, D, U, R], "cooldown": 160.0, "uses": -1,
		"delay": 3.0, "color": BLUE},
	"eagle_airstrike": {"name": "Eagle Airstrike", "code": [U, R, D, R], "cooldown": 6.0, "uses": 2,
		"rearm": 120.0, "delay": 2.2, "color": RED},
	"eagle_500kg": {"name": "Eagle 500kg Bomb", "code": [U, R, D, D, D], "cooldown": 6.0, "uses": 1,
		"rearm": 120.0, "delay": 2.5, "color": RED},
	"orbital_precision": {"name": "Orbital Precision Strike", "code": [R, R, U], "cooldown": 90.0, "uses": -1,
		"delay": 3.5, "color": RED},
	"eat17": {"name": "EAT-17 Expendable Anti-Tank", "code": [D, D, L, U, R], "cooldown": 70.0, "uses": -1,
		"delay": 3.0, "color": GREEN},
}

const POD_FALL := 1.0
const POD_BLAST := {"radius_m": 1.6, "damage": 500.0, "ap": 5, "armor_damage": 200.0, "destruction": 30,
	"stagger": 600.0, "sound": 120.0, "sound_falloff": 8.0, "self_mult": 1.0}
const ORBITAL_BLAST := {"radius_m": 4.5, "damage": 2000.0, "ap": 7, "armor_damage": 800.0, "destruction": 60,
	"stagger": 1200.0, "sound": 160.0, "sound_falloff": 5.0, "self_mult": 1.0}
const EAGLE_BOMB := {"radius_m": 3.5, "damage": 450.0, "ap": 4, "armor_damage": 200.0, "destruction": 40,
	"stagger": 400.0, "sound": 150.0, "sound_falloff": 6.0, "self_mult": 1.0}
const BOMB_500 := {"radius_m": 9.0, "damage": 1500.0, "ap": 6, "armor_damage": 600.0, "destruction": 60,
	"stagger": 1200.0, "sound": 170.0, "sound_falloff": 4.0, "self_mult": 1.0}

## Ids equipped for this run (from Game.loadout).
var equipped: Array[String] = []
## id -> {"cd": s, "uses": n (-1 unlimited), "rearm": s}
var status := {}
var entering := false
var input: Array[int] = []
## Feedback for the HUD: last thrown id and a short error flash.
var last_called := ""
var error_t := 0.0

var _player: CharacterBody2D
var _projectiles: Node
var _beacons: Array[Dictionary] = []
var _fx: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("stratagems")
	z_index = 19
	z_as_relative = false
	_player = get_tree().get_first_node_in_group("player")
	_projectiles = get_tree().get_first_node_in_group("projectiles")
	for id in Game.loadout.stratagems:
		if DEFS.has(id):
			equipped.append(id)
			status[id] = {"cd": 0.0, "uses": DEFS[id].uses, "rearm": 0.0}


func available(id: String) -> bool:
	var st: Dictionary = status[id]
	return st.cd <= 0.0 and st.uses != 0


## Seconds until usable again (0 = ready).
func wait_time(id: String) -> float:
	var st: Dictionary = status[id]
	return st.rearm if st.uses == 0 else st.cd


func toggle_menu() -> void:
	if entering:
		close_menu()
	elif _player and not _player.dead:
		entering = true
		input.clear()


func close_menu() -> void:
	entering = false
	input.clear()


## One arrow of the code. Completes (throws) or resets on a wrong arrow.
func push(dir: int) -> void:
	if not entering:
		return
	input.append(dir)
	var matches: Array[String] = []
	for id in equipped:
		if not available(id):
			continue
		if matches_prefix(id):
			matches.append(id)
	if matches.is_empty():
		input.clear()
		error_t = 0.4
		Sfx.play_ui("strat_error", -4.0)
		return
	Sfx.play_ui("strat_input", -4.0, 0.03 * input.size())
	for id in matches:
		if (DEFS[id].code as Array).size() == input.size():
			_throw(id)
			return


## Does id's code start with the current input? (HUD highlight)
func matches_prefix(id: String) -> bool:
	var code: Array = DEFS[id].code
	if code.size() < input.size():
		return false
	for i in input.size():
		if int(code[i]) != input[i]:
			return false
	return true


func _throw(id: String) -> void:
	close_menu()
	last_called = id
	Sfx.play_ui("strat_ready", -4.0)
	Sfx.play_ui("throw", -4.0, 0.1)
	var def: Dictionary = DEFS[id]
	var st: Dictionary = status[id]
	st.cd = def.cooldown
	if st.uses > 0:
		st.uses -= 1
		if st.uses == 0:
			st.rearm = def.rearm
	var from: Vector2 = _player.global_position
	var forward := Vector2.UP.rotated(_player.rotation)
	var to := from + forward * 8.0 * PX
	if _player.weapon.ads_amount() >= 0.5:
		to = _player.weapon.aim_overlay().center
	# Beacons bounce off walls like grenades.
	var q := PhysicsRayQueryParameters2D.create(from, to, 1)
	q.exclude = [_player.get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		to = (hit.position as Vector2) - (to - from).normalized() * 12.0
	_beacons.append({"id": id, "from": from, "to": to, "pos": from, "t": 0.0,
		"flight": clampf(from.distance_to(to) / 700.0, 0.3, 0.8), "dir": forward})
	Game.add_stat("stratagems")


func _physics_process(delta: float) -> void:
	error_t = maxf(error_t - delta, 0.0)
	for id in status:
		var st: Dictionary = status[id]
		st.cd = maxf(st.cd - delta, 0.0)
		if st.uses == 0:
			st.rearm -= delta
			if st.rearm <= 0.0:
				st.uses = DEFS[id].uses
				st.rearm = 0.0
	for b in _beacons:
		b.t += delta
		var k := clampf(b.t / b.flight, 0.0, 1.0)
		b.pos = (b.from as Vector2).lerp(b.to, 1.0 - pow(1.0 - k, 2.0))
		if k >= 1.0 and not b.get("landed", false):
			b.landed = true
			Sfx.play("beacon", b.pos, -4.0)
		if b.t >= b.flight + DEFS[b.id].delay:
			_arrive(b)
	_beacons = _beacons.filter(func(b): return b.t < b.flight + DEFS[b.id].delay)
	_update_fx(delta)
	queue_redraw()


func _arrive(b: Dictionary) -> void:
	var at: Vector2 = b.pos
	match b.id:
		"resupply":
			_fx.append({"kind": "pod", "pos": at, "t": 0.0, "pod": Interactable.Kind.RESUPPLY_POD})
		"eat17":
			_fx.append({"kind": "pod", "pos": at, "t": 0.0, "pod": Interactable.Kind.SUPPORT_POD})
		"orbital_precision":
			_fx.append({"kind": "beam", "pos": at, "t": 0.0})
			Sfx.play("orbital_shot", at, 2.0)
		"eagle_airstrike":
			Sfx.play_ui("eagle_flyby", -3.0, 0.05)
			var across: Vector2 = (b.dir as Vector2).orthogonal()
			_fx.append({"kind": "eagle", "pos": at, "t": 0.0, "dir": (b.dir as Vector2), "big": false})
			for i in 5:
				_fx.append({"kind": "bomb", "pos": at + across * (i - 2) * 3.0 * PX, "t": -0.45 - i * 0.09, "big": false})
		"eagle_500kg":
			Sfx.play_ui("eagle_flyby", -3.0, 0.05)
			_fx.append({"kind": "eagle", "pos": at, "t": 0.0, "dir": (b.dir as Vector2), "big": true})
			_fx.append({"kind": "bomb", "pos": at, "t": -0.7, "big": true})


func _update_fx(delta: float) -> void:
	for f in _fx:
		f.t += delta
		match f.kind:
			"pod":
				if f.t >= POD_FALL and not f.get("done", false):
					f.done = true
					_projectiles.explode(f.pos, POD_BLAST)
					Sfx.play("hellpod_impact", f.pos)
					var pod := Interactable.make(f.pod)
					pod.position = f.pos
					pod.activated.connect(_on_pod)
					get_parent().add_child(pod)
			"beam":
				if f.t >= 0.6 and not f.get("done", false):
					f.done = true
					_projectiles.explode(f.pos, ORBITAL_BLAST)
			"bomb":
				if f.t >= 0.0 and not f.get("done", false):
					f.done = true
					_projectiles.explode(f.pos, BOMB_500 if f.big else EAGLE_BOMB)
	_fx = _fx.filter(func(f): return f.t < 2.0)


func _on_pod(it: Interactable) -> void:
	Sfx.play_ui("pod_open", -6.0)
	match it.kind:
		Interactable.Kind.RESUPPLY_POD:
			_player.resupply()
			_player.weapon.refill()
		Interactable.Kind.SUPPORT_POD:
			_player.weapon.give_support(it.payload)


func _draw() -> void:
	var now := Time.get_ticks_msec() * 0.001
	for b in _beacons:
		var col: Color = DEFS[b.id].color
		var k := clampf(b.t / b.flight, 0.0, 1.0)
		var p: Vector2 = b.pos + Vector2(0, -sin(k * PI) * 16.0)
		draw_circle(p, 4.0, Color(0.1, 0.1, 0.1))
		if b.t >= b.flight:
			var pulse := 0.6 + 0.4 * sin(now * 12.0)
			draw_circle(b.pos, 10.0 + pulse * 6.0, Color(col, 0.25))
			draw_circle(b.pos, 4.0, col)
			draw_line(b.pos, b.pos + Vector2(0, -260), Color(col, 0.35 * pulse), 4.0) # light column
	for f in _fx:
		match f.kind:
			"pod":
				if f.t < POD_FALL:
					var k: float = f.t / POD_FALL
					draw_circle(f.pos, 34.0 * (0.3 + k * 0.7), Color(0, 0, 0, 0.35 * k))
					var top: Vector2 = f.pos + Vector2(0, -600.0 * (1.0 - k))
					draw_line(top + Vector2(0, -120), top, Color(1, 0.7, 0.3, 0.6), 8.0)
					draw_circle(top, 14.0, Color(0.3, 0.3, 0.32))
			"beam":
				var a := clampf(1.0 - absf(f.t - 0.6) * 2.0, 0.0, 1.0)
				draw_line(f.pos + Vector2(0, -1600), f.pos, Color(1, 0.35, 0.25, 0.8 * a), 10.0 + 20.0 * a)
				draw_circle(f.pos, 20.0 + 40.0 * a, Color(1, 0.4, 0.3, 0.4 * a))
			"eagle":
				# Jet shadow streaking across.
				var k := clampf(f.t / 0.9, 0.0, 1.0)
				var dir: Vector2 = f.dir
				var c: Vector2 = f.pos + dir * lerpf(-1400.0, 1400.0, k)
				var t := Transform2D(dir.angle() + PI / 2.0, c)
				var shape := PackedVector2Array([Vector2(0, -60), Vector2(70, 30), Vector2(20, 20), Vector2(0, 50),
					Vector2(-20, 20), Vector2(-70, 30)])
				draw_colored_polygon(t * shape, Color(0, 0, 0, 0.35))
			"bomb":
				if f.t < 0.0:
					var k := clampf(1.0 + f.t / 0.45, 0.0, 1.0)
					draw_circle(f.pos, (60.0 if f.big else 22.0) * k, Color(1, 0.3, 0.2, 0.25 * k))
