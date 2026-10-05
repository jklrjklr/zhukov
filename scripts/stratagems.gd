class_name Stratagems
extends Node2D
## Helldivers 2 stratagems.
## Input: the player picks a stratagem (HUD cards: swipe out of a card = quick throw, tap = aim
## mode; keyboard: Q radial / menu, 1-5 aim mode, see strat_menu.gd); the Helldiver types the HD2 code automatically (0.1 s
## per arrow, interrupted by a dive or stagger) and throws the beacon. After the call-in
## delay the effect arrives:
##   RESUPPLY            supply pod (2 pickups: ammo, grenades, stims)
##   EAGLE AIRSTRIKE     a line of bombs across the beacon (2 uses, then rearm)
##   EAGLE 500KG BOMB    one huge bomb (1 use, then rearm)
##   ORBITAL PRECISION   a single devastating shell after a longer delay
##   EAT-17              pod with 2 disposable anti-tank launchers
##   MG-43 SENTRY        machine gun sentry: shoots enemies it can see until out of ammo
##   ORBITAL 120MM      barrage: ~22 shells over 8 s, centre-weighted Gaussian scatter
## Pods and shells hurt everything nearby, the Helldiver included.
## METER SYSTEM (v0.5): every stratagem holds `charges` and a `meter` of points. Cost of
## a charge = HD2 cooldown x 10 points. The meter fills 10 pts/s and from kills and
## objectives (add_points); a full meter adds a charge (up to `cap`). Eagles have `uses`
## charges and only fill their (1500 pt) rearm meter once empty. Resupply refills by meter
## at most once per zone. `fill_enabled` is off in the departure stages, `locked` once the
## Super Destroyer has left (nothing can be called).
## Draws beacons, falling pods, eagle passes and orbital beams (world space, on top).

enum Dir { UP, DOWN, LEFT, RIGHT }

const PX := Firearm.PX_PER_M
const K := Vis.VISUAL_SCALE
const U := Dir.UP
const D := Dir.DOWN
const L := Dir.LEFT
const R := Dir.RIGHT
## Category colours: Eagle red, Orbital red-orange, Support blue, Defensive green, Supply blue-grey.
const BLUE := Color(0.35, 0.62, 1.0)
const RED := Color(1.0, 0.28, 0.25)
const ORANGE := Color(1.0, 0.48, 0.12)
const GREEN := Color(0.4, 0.85, 0.4)
const SUPPLY := Color(0.62, 0.74, 0.86)

## Code arrows are only used for the auto-typing time and the glyphs above the head.
const DEFS := {
	"resupply": {"name": "Resupply", "code": [D, D, U, R], "cooldown": 160.0, "uses": -1,
		"delay": 3.0, "color": SUPPLY, "cat": "supply", "cap": 1, "start": 1, "short": "SUP"},
	"eagle_airstrike": {"name": "Eagle Airstrike", "code": [U, R, D, R], "cooldown": 6.0, "uses": 2,
		"rearm": 120.0, "rearm_cost": 1500.0, "delay": 2.2, "color": RED, "cat": "eagle", "cap": 2, "start": 2,
		"airborne": true, "short": "EAG"},
	"eagle_500kg": {"name": "Eagle 500kg Bomb", "code": [U, R, D, D, D], "cooldown": 6.0, "uses": 1,
		"rearm": 120.0, "rearm_cost": 1500.0, "delay": 2.5, "color": RED, "cat": "eagle", "cap": 1, "start": 1,
		"airborne": true, "short": "500"},
	"orbital_precision": {"name": "Orbital Precision Strike", "code": [R, R, U], "cooldown": 90.0, "uses": -1,
		"delay": 3.5, "color": ORANGE, "cat": "orbital", "cap": 1, "start": 1, "airborne": true, "short": "OPS"},
	"orbital_120": {"name": "Orbital 120mm HE Barrage", "code": [R, R, D, L, R, D], "cooldown": 240.0, "uses": -1,
		"delay": 3.0, "color": ORANGE, "cat": "orbital", "cap": 1, "start": 1, "airborne": true, "short": "120"},
	"eat17": {"name": "EAT-17 Expendable Anti-Tank", "code": [D, D, L, U, R], "cooldown": 70.0, "uses": -1,
		"delay": 3.0, "color": BLUE, "cat": "support", "cap": 2, "start": 1, "short": "EAT"},
	"sentry_mg": {"name": "A/MG-43 Machine Gun Sentry", "code": [D, U, R, R, U], "cooldown": 90.0, "uses": -1,
		"delay": 3.0, "color": GREEN, "cat": "defense", "cap": 2, "start": 1, "short": "MG"},
}

## Meter points per second, and per kill by size (see Mission.on_kill).
const PASSIVE_PTS := 10.0
## 120mm barrage: Gaussian scatter sigma = 0.45 R, radius R = 27 m, ~22 shells over 8 s.
const BARRAGE_R_M := 27.0
const BARRAGE_SIGMA := 0.45
const BARRAGE_SHELLS := 22
const BARRAGE_TIME := 8.0
const BARRAGE_BLAST := {"radius_m": 5.0, "damage": 700.0, "ap": 6, "armor_damage": 300.0, "destruction": 60,
	"stagger": 800.0, "sound": 150.0, "sound_falloff": 6.0, "self_mult": 1.0}

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
## id -> {"cd": s (short re-use lockout), "charges": n, "meter": points}
var status := {}
## Departed: nothing can be called. Departure stages: meters stop filling.
var locked := false
var fill_enabled := true
## Bumped whenever a charge is gained (HUD flash): id -> seconds since.
var gained := {}
var _resupply_refills := 0
## Selection UI (see "Selection" below): radial quick-throw menu, list menu, aim mode.
enum Ui { NONE, RADIAL, MENU, AIM }
const TYPE_PER_ARROW := 0.1
const DEFAULT_THROW_M := 12.0
const MAX_THROW_M := 20.0
var ui := Ui.NONE
var radial_center := Vector2.ZERO
var radial_pointer := Vector2.ZERO
var aim_id := ""
## Landing point relative to the player (world px), at most MAX_THROW_M long.
var aim_offset := Vector2.ZERO
## Aim mode from the keyboard: the mouse places the landing point.
var aim_mouse := false
## Stratagem being auto-typed ("" = none), seconds typed so far, flash after an interruption.
var typing_id := ""
var typing_t := 0.0
var typing_flash := 0.0
var throw_queued := false
## World direction of a swipe quick throw (ZERO = along the aim direction).
var _quick_dir := Vector2.ZERO
var _typing_ticks := 0
var _typing_mode := ""
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
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	_player = get_tree().get_first_node_in_group("player")
	_projectiles = get_tree().get_first_node_in_group("projectiles")
	for id in Game.loadout.stratagems:
		if DEFS.has(id):
			equipped.append(id)
			status[id] = {"cd": 0.0, "charges": int(DEFS[id].start), "meter": 0.0}
			gained[id] = 99.0


func available(id: String) -> bool:
	var st: Dictionary = status[id]
	return not locked and st.cd <= 0.0 and st.charges > 0


func charges(id: String) -> int:
	return int((status[id] as Dictionary).charges)


func cap(id: String) -> int:
	return int(DEFS[id].cap)


## Points needed for the next charge (rearm cost for empty Eagles).
func cost(id: String) -> float:
	var def: Dictionary = DEFS[id]
	if def.has("rearm_cost") and charges(id) == 0:
		return def.rearm_cost
	return def.cooldown * 10.0


## 0..1 fill of the meter toward the next charge (0 when full of charges).
func meter_frac(id: String) -> float:
	if not _filling(id):
		return 0.0
	return clampf((status[id] as Dictionary).meter / cost(id), 0.0, 1.0)


## Meter points toward the next charge (all stratagems that can still gain one).
func add_points(pts: float) -> void:
	if not fill_enabled or locked:
		return
	for id in equipped:
		_fill(id, pts)


## New zone: Resupply may refill by meter once more.
func new_zone() -> void:
	_resupply_refills = 0


func _filling(id: String) -> bool:
	var def: Dictionary = DEFS[id]
	var st: Dictionary = status[id]
	if def.has("rearm_cost"):
		return st.charges == 0
	if st.charges >= def.cap:
		return false
	if id == "resupply" and _resupply_refills >= 1:
		return false
	return true


func _fill(id: String, pts: float) -> void:
	if not _filling(id):
		return
	var st: Dictionary = status[id]
	var def: Dictionary = DEFS[id]
	st.meter += pts
	var need := cost(id)
	if st.meter < need:
		return
	st.meter = 0.0
	if def.has("rearm_cost"):
		st.charges = def.cap
	else:
		st.charges += 1
		if id == "resupply":
			_resupply_refills += 1
	gained[id] = 0.0
	Sfx.play_ui("strat_ready", -4.0)


## ---- Selection: quick throw (radial) and menu + aim mode ---------------------------------

## True while any selection UI (radial, menu or aim mode) is up.
func ui_open() -> bool:
	return ui != Ui.NONE


## Seconds the Helldiver needs to type id's code (0.1 s per arrow).
func code_time(id: String) -> float:
	return (DEFS[id].code as Array).size() * TYPE_PER_ARROW


func is_typing() -> bool:
	return typing_id != "" and typing_t < code_time(typing_id) - 0.0001


func typing_ready() -> bool:
	return typing_id != "" and not is_typing()


## Why id cannot be called right now ("" = it can). Shown as the menu tooltip.
func pick_error(id: String) -> String:
	if not status.has(id):
		return "NOT EQUIPPED"
	if locked:
		return "OFFLINE - SUPER DESTROYER LEFT"
	if _player == null or _player.dead:
		return "HELLDIVER DOWN"
	var st: Dictionary = status[id]
	if st.charges <= 0:
		if not fill_enabled:
			return "NO CHARGES - METER STOPPED"
		if DEFS[id].has("rearm_cost"):
			return "REARMING %d%%" % roundi(meter_frac(id) * 100.0)
		return "NO CHARGES - METER %d%%" % roundi(meter_frac(id) * 100.0)
	if st.cd > 0.0:
		return "RE-USE LOCKOUT"
	if DEFS[id].get("airborne", false) and roofed(_player.global_position):
		return "NO SKY ACCESS - ROOFED"
	return ""


func roofed(p: Vector2) -> bool:
	var mission := get_tree().get_first_node_in_group("mission")
	return mission != null and mission.has_method("is_roofed") and mission.is_roofed(p)


func _refuse(text: String, id := "") -> void:
	error_t = 0.6
	Sfx.play_ui("strat_error", -2.0)
	var msg := text
	if id != "":
		msg = "%s: %s" % [DEFS[id].name, text]
	get_tree().call_group("mission", "announce", msg, false)


## Tap Q: the list menu (keyboard).
func open_menu() -> void:
	if ui == Ui.MENU:
		return
	if locked:
		_refuse("STRATAGEMS OFFLINE")
		return
	if _player == null or _player.dead:
		return
	cancel(false)
	ui = Ui.MENU
	Sfx.play_ui("strat_open", -4.0)


## Press-and-hold: the radial menu around `center` (screen px); `pointer` follows the finger.
func open_radial(center: Vector2, pointer: Vector2) -> void:
	if locked:
		_refuse("STRATAGEMS OFFLINE")
		return
	if _player == null or _player.dead:
		return
	cancel(false)
	ui = Ui.RADIAL
	radial_center = center
	radial_pointer = pointer
	Sfx.play_ui("strat_open", -4.0)


## Leave menu / radial / aim mode and drop any typing in progress.
func cancel(sound := true) -> void:
	var was := ui != Ui.NONE or typing_id != ""
	ui = Ui.NONE
	aim_id = ""
	aim_mouse = false
	typing_id = ""
	typing_t = 0.0
	_typing_ticks = 0
	throw_queued = false
	if was and sound:
		Sfx.play_ui("ui_back", -4.0)


## Quick throw: auto-type id's code, then throw at the default distance along `dir` (a world
## direction, e.g. the swipe on a card) or, without one, along the aim direction.
func select_quick(id: String, dir := Vector2.ZERO) -> bool:
	var why := pick_error(id)
	if why != "":
		cancel(false)
		_refuse(why, id)
		return false
	cancel(false)
	_begin_typing(id, "quick")
	_quick_dir = dir.normalized()
	throw_queued = true
	return true


## Aim mode (like ADS): auto-types while the landing point is placed; the throw waits for the code.
func select_aim(id: String, mouse := false) -> bool:
	var why := pick_error(id)
	if why != "":
		_refuse(why, id)
		return false
	cancel(false)
	ui = Ui.AIM
	aim_id = id
	aim_mouse = mouse
	aim_offset = Vector2.UP.rotated(_player.rotation) * DEFAULT_THROW_M * PX
	_begin_typing(id, "aim")
	Sfx.play_ui("ui_click", -6.0)
	return true


## Number keys: the i-th equipped stratagem straight into aim mode.
func select_index(i: int, mouse := true) -> bool:
	if i < 0 or i >= equipped.size():
		return false
	return select_aim(equipped[i], mouse)


func _begin_typing(id: String, mode: String) -> void:
	typing_id = id
	typing_t = 0.0
	_typing_ticks = 0
	_typing_mode = mode
	typing_flash = 0.0


## Move the landing point by a world-space delta (max throw range from the player).
func aim_move(world_delta: Vector2) -> void:
	aim_offset = (aim_offset + world_delta).limit_length(MAX_THROW_M * PX)


## Place the landing point at a world position (mouse), clamped to max range.
func aim_set_world(p: Vector2) -> void:
	aim_offset = (p - _player.global_position).limit_length(MAX_THROW_M * PX)


func aim_point() -> Vector2:
	return _player.global_position + aim_offset


## Throw button / drag release / left click. Waits for the code if it is still typing.
func aim_throw() -> void:
	if ui != Ui.AIM or aim_id == "":
		return
	throw_queued = true
	if typing_ready():
		_complete()


## Where a beacon thrown from the player toward `to` actually lands (walls stop it).
func landing_point(to: Vector2) -> Vector2:
	var from: Vector2 = _player.global_position
	var q := PhysicsRayQueryParameters2D.create(from, to, 1)
	q.exclude = [_player.get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return (hit.position as Vector2) - (to - from).normalized() * 12.0
	return to


## Effect footprint for the aim overlay: {"kind": "circle"|"line", "r_m", "span_m"}.
func preview(id: String) -> Dictionary:
	match id:
		"orbital_120":
			return {"kind": "circle", "r_m": BARRAGE_R_M}
		"orbital_precision":
			return {"kind": "circle", "r_m": ORBITAL_BLAST.radius_m}
		"eagle_500kg":
			return {"kind": "circle", "r_m": BOMB_500.radius_m}
		"eagle_airstrike":
			return {"kind": "line", "r_m": EAGLE_BOMB.radius_m, "span_m": 12.0}
		"sentry_mg":
			return {"kind": "circle", "r_m": POD_BLAST.radius_m, "sentry": true}
	return {"kind": "circle", "r_m": POD_BLAST.radius_m}


## The code finished and the throw was requested: throw now.
func _complete() -> void:
	var id := typing_id
	var mode := _typing_mode
	var fwd := Vector2.UP.rotated(_player.rotation)
	if mode == "quick" and _quick_dir != Vector2.ZERO:
		fwd = _quick_dir
	var to: Vector2 = _player.global_position + fwd * DEFAULT_THROW_M * PX
	if mode == "aim":
		to = aim_point()
	var why := pick_error(id)
	if why == "" and DEFS[id].get("airborne", false) and roofed(landing_point(to)):
		why = "NO SKY ACCESS - ROOFED"
	if why != "":
		_refuse(why, id)
		if mode == "aim" and why.begins_with("NO SKY"):
			throw_queued = false # stay in aim mode: pick another spot
		else:
			cancel(false)
		return
	cancel(false)
	_throw(id, to)


func _throw(id: String, target: Vector2) -> void:
	var from: Vector2 = _player.global_position
	var to := landing_point(target)
	var dir := (target - from).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP.rotated(_player.rotation)
	last_called = id
	Sfx.play_ui("throw", -4.0, 0.1)
	var st: Dictionary = status[id]
	st.cd = 1.0
	st.charges -= 1
	_beacons.append({"id": id, "from": from, "to": to, "pos": from, "t": 0.0,
		"flight": clampf(from.distance_to(to) / 700.0, 0.3, 0.8), "dir": dir})
	Game.add_stat("stratagems")


## Typing advances 0.1 s per arrow; a dive or stagger interrupts it (quick throws are
## dropped, aim mode starts typing over once the Helldiver is back on their feet).
func _update_typing(delta: float) -> void:
	typing_flash = maxf(typing_flash - delta, 0.0)
	if typing_id == "":
		return
	if _player.dead or locked:
		cancel(false)
		return
	if _player.is_diving() or _player.stagger_t > 0.0:
		_typing_ticks = 0
		if typing_t > 0.0:
			typing_flash = 0.6
			Sfx.play_ui("strat_error", -4.0)
		typing_t = 0.0
		if _typing_mode == "quick":
			get_tree().call_group("mission", "announce", "STRATAGEM INPUT INTERRUPTED", false)
			cancel(false)
		return
	if is_typing():
		typing_t = minf(typing_t + delta, code_time(typing_id))
		var n := (DEFS[typing_id].code as Array).size()
		var ticks := mini(int(typing_t / TYPE_PER_ARROW + 0.0001), n)
		while _typing_ticks < ticks:
			_typing_ticks += 1
			Sfx.play_ui("strat_input", -4.0, 0.03)
		if not is_typing():
			Sfx.play_ui("strat_ready", -4.0)
	if typing_ready() and throw_queued:
		_complete()


func _sync_player() -> void:
	var typing: bool = is_typing() and not _player.is_diving() and _player.stagger_t <= 0.0
	_player.typing = typing
	if typing:
		_player.typing_prog = typing_t / code_time(typing_id)
		_player.typing_col = DEFS[typing_id].color
	var weapon: Firearm = _player.weapon
	weapon.strat_cam_on = ui == Ui.AIM
	if ui == Ui.AIM:
		weapon.strat_cam_local = aim_offset.rotated(-_player.look_angle)


func _physics_process(delta: float) -> void:
	error_t = maxf(error_t - delta, 0.0)
	_update_typing(delta)
	if ui == Ui.AIM and aim_mouse:
		aim_set_world(get_global_mouse_position())
	_sync_player()
	for id in status:
		var st: Dictionary = status[id]
		st.cd = maxf(st.cd - delta, 0.0)
		gained[id] = minf(gained[id] + delta, 99.0)
	add_points(PASSIVE_PTS * delta)
	for b in _beacons:
		b.t += delta
		var k := clampf(b.t / b.flight, 0.0, 1.0)
		b.pos = (b.from as Vector2).lerp(b.to, 1.0 - pow(1.0 - k, 2.0))
		if k >= 1.0 and not b.get("landed", false):
			b.landed = true
			Fx.dust_puff(self, b.pos, 0.6)
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
			Sfx.play("hellpod_streak", at, -2.0)
		"eat17":
			_fx.append({"kind": "pod", "pos": at, "t": 0.0, "pod": Interactable.Kind.SUPPORT_POD})
			Sfx.play("hellpod_streak", at, -2.0)
		"sentry_mg":
			_fx.append({"kind": "pod", "pos": at, "t": 0.0, "pod": -1})
			Sfx.play("hellpod_streak", at, -2.0)
		"orbital_120":
			Sfx.play("orbital_shot", at, 2.0)
			for i in BARRAGE_SHELLS:
				_fx.append({"kind": "shell", "pos": _barrage_point(at), "t": -1.0 - randf() * BARRAGE_TIME})
		"orbital_precision":
			_fx.append({"kind": "beam", "pos": at, "t": 0.0})
			Sfx.play("orbital_whistle", at, 2.0)
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


## Gaussian scatter around the beacon (sigma = 0.45 R); redrawn until inside R.
func _barrage_point(center: Vector2) -> Vector2:
	var r := BARRAGE_R_M * PX
	var sigma := BARRAGE_SIGMA * r
	var off := Vector2(randfn(0.0, sigma), randfn(0.0, sigma))
	for i in 20:
		if off.length() <= r:
			break
		off = Vector2(randfn(0.0, sigma), randfn(0.0, sigma))
	return center + off.limit_length(r)


func _update_fx(delta: float) -> void:
	for f in _fx:
		f.t += delta
		match f.kind:
			"pod":
				if f.t >= POD_FALL and not f.get("done", false):
					f.done = true
					_projectiles.explode(f.pos, POD_BLAST)
					Fx.landing(self, f.pos, 100.0)
					Sfx.play("hellpod_impact", f.pos)
					if f.pod < 0:
						var sentry := Sentry.new()
						sentry.position = f.pos
						get_parent().add_child(sentry)
						Sfx.play("sentry_deploy", f.pos, 0.0)
						continue
					var pod := Interactable.make(f.pod)
					pod.position = f.pos
					pod.activated.connect(_on_pod)
					get_parent().add_child(pod)
			"beam":
				if f.t >= 0.6 and not f.get("done", false):
					f.done = true
					Sfx.play("orbital_shot", f.pos, 2.0)
					_projectiles.explode(f.pos, ORBITAL_BLAST)
			"bomb":
				if f.t >= 0.0 and not f.get("done", false):
					f.done = true
					Sfx.play("eagle_bomb", f.pos, 0.0)
					_projectiles.explode(f.pos, BOMB_500 if f.big else EAGLE_BOMB)
			"shell":
				if f.t >= -0.9 and not f.get("whistled", false):
					f.whistled = true
					Sfx.play("orbital_whistle", f.pos, -2.0)
				if f.t >= 0.0 and not f.get("done", false):
					f.done = true
					_projectiles.explode(f.pos, BARRAGE_BLAST)
	_fx = _fx.filter(func(f): return f.t < 2.0)


func _on_pod(it: Interactable) -> void:
	Sfx.play_ui("resupply_open", -6.0)
	match it.kind:
		Interactable.Kind.RESUPPLY_POD:
			_player.resupply()
			_player.weapon.refill()
		Interactable.Kind.SUPPORT_POD:
			_player.weapon.give_support(it.payload)


func _draw() -> void:
	var now := Time.get_ticks_msec() * 0.001
	var up := Fx.screen_up(self)
	for b in _beacons:
		var col: Color = DEFS[b.id].color
		var k := clampf(b.t / b.flight, 0.0, 1.0)
		var p: Vector2 = b.pos + up * (sin(k * PI) * 26.0 * K)
		if Game.shadows_enabled: draw_circle(b.pos + Vector2(3, 4), 4.0 * K, Color(0, 0, 0, 0.3))
		draw_circle(p, 5.0 * K, Color(0.1, 0.1, 0.1))
		draw_circle(p, 3.3 * K, col.lightened(0.2))
		if b.t >= b.flight:
			var wait: float = b.t - b.flight
			var delay: float = DEFS[b.id].delay
			var pulse := 0.6 + 0.4 * sin(now * 12.0)
			_pillar(b.pos, col, pulse, up, 560.0)
			draw_circle(b.pos, (12.0 + pulse * 6.0) * K, Color(col, 0.28))
			draw_circle(b.pos, 4.5 * K, Color(1, 1, 1, 0.95))
			draw_circle(b.pos, 3.0 * K, col)
			# Rotating dashes and an arrival countdown ring.
			for i in 4:
				var a := now * 2.5 + i * TAU / 4.0
				draw_arc(b.pos, 24.0 * K, a, a + 0.7, 6, Color(col, 0.8), 3.0 * K)
			draw_arc(b.pos, 34.0 * K, 0.0, TAU, 28, Color(0, 0, 0, 0.3), 4.0 * K)
			draw_arc(b.pos, 34.0 * K, -PI / 2.0, -PI / 2.0 + TAU * clampf(wait / delay, 0.0, 1.0), 28, Color(col, 0.95), 4.0 * K)
			if b.id == "orbital_120":
				draw_arc(b.pos, BARRAGE_R_M * PX, 0.0, TAU, 72, Color(col, 0.22 + 0.1 * pulse), 2.0)
	for f in _fx:
		match f.kind:
			"pod":
				if f.t < POD_FALL:
					var k: float = f.t / POD_FALL
					draw_circle(f.pos, 34.0 * K * (0.3 + k * 0.7), Color(0, 0, 0, 0.5 * k))
					draw_arc(f.pos, 40.0 * (1.2 - k * 0.4), 0.0, TAU, 24, Color(1, 0.6, 0.2, 0.6 * k), 2.0)
					_falling_pod(f.pos, up, k, 700.0, 14.0 * K)
			"beam":
				var a := clampf(1.0 - absf(f.t - 0.6) * 2.0, 0.0, 1.0)
				var warn := clampf(f.t / 0.6, 0.0, 1.0)
				draw_arc(f.pos, ORBITAL_BLAST.radius_m * PX, 0.0, TAU, 48, Color(1, 0.4, 0.15, 0.3 + 0.2 * warn), 2.0)
				draw_arc(f.pos, ORBITAL_BLAST.radius_m * PX * (1.0 - warn * 0.8), 0.0, TAU, 40, Color(1, 0.8, 0.3, 0.8), 3.0)
				draw_line(f.pos + up * 1600.0, f.pos, Color(1, 0.35, 0.25, 0.8 * a), 10.0 + 24.0 * a)
				draw_line(f.pos + up * 1600.0, f.pos, Color(1, 0.9, 0.7, 0.9 * a), 3.0 + 8.0 * a)
				draw_circle(f.pos, 20.0 + 40.0 * a, Color(1, 0.4, 0.3, 0.4 * a))
			"eagle":
				# Jet shadow streaking across, with wings, tail and engine glow.
				var k := clampf(f.t / 0.9, 0.0, 1.0)
				var dir: Vector2 = f.dir
				var c: Vector2 = f.pos + dir * lerpf(-1500.0, 1500.0, k)
				var sc := (1.5 if f.big else 1.0) * K
				var t := Transform2D(dir.angle() + PI / 2.0, Vector2(sc, sc), 0.0, c + Vector2(26, 34))
				var body := PackedVector2Array([Vector2(0, -70), Vector2(8, -30), Vector2(10, 40), Vector2(0, 56), Vector2(-10, 40), Vector2(-8, -30)])
				var wings := PackedVector2Array([Vector2(-8, -10), Vector2(-86, 34), Vector2(-80, 46), Vector2(-8, 28), Vector2(8, 28), Vector2(80, 46), Vector2(86, 34), Vector2(8, -10)])
				var tail := PackedVector2Array([Vector2(-5, 38), Vector2(-30, 62), Vector2(-5, 54), Vector2(5, 54), Vector2(30, 62), Vector2(5, 38)])
				var sh := Color(0, 0, 0, 0.38)
				if Game.shadows_enabled:
					draw_colored_polygon(t * body, sh)
					draw_colored_polygon(t * wings, sh)
					draw_colored_polygon(t * tail, sh)
				# Dust wake on the ground behind the jet.
				draw_line(c - dir * 40.0, c - dir * 380.0, Color(0.8, 0.7, 0.5, 0.18 * (1.0 - k * 0.5)), 26.0 * K)
			"shell":
				if f.t >= -0.9 and f.t < 0.0:
					var k := clampf(1.0 + f.t / 0.9, 0.0, 1.0)
					var br: float = BARRAGE_BLAST.radius_m * PX
					draw_arc(f.pos, br, 0.0, TAU, 40, Color(1, 0.45, 0.2, 0.2 + 0.15 * k), 1.5)
					draw_arc(f.pos, br * (1.0 - k * 0.85), 0.0, TAU, 32, Color(1, 0.8, 0.4, 0.6 * k + 0.2), 2.0)
					draw_circle(f.pos, 5.0 * K, Color(1, 0.3, 0.2, 0.7))
					if f.t > -0.28: # incoming shell streak
						var fall: float = 1.0 - (-f.t / 0.28)
						draw_line(f.pos + up * (900.0 * (1.0 - fall)), f.pos + up * (900.0 * (1.0 - fall) + 160.0), Color(1, 0.7, 0.4, 0.8), 4.0 * K)
			"bomb":
				if f.t < 0.0:
					var k := clampf(1.0 + f.t / 0.45, 0.0, 1.0)
					var br: float = (BOMB_500.radius_m if f.big else EAGLE_BOMB.radius_m) * PX
					draw_arc(f.pos, br, 0.0, TAU, 40, Color(1, 0.35, 0.2, 0.25 + 0.2 * k), 2.0)
					draw_circle(f.pos, br * 0.9 * k, Color(1, 0.3, 0.2, 0.12))
					# The falling bomb with its small shadow.
					var h := (1.0 - k) * 500.0
					if Game.shadows_enabled: draw_circle(f.pos, 5.0, Color(0, 0, 0, 0.3))
					draw_line(f.pos + up * (h + 10.0), f.pos + up * h, Color(0.2, 0.2, 0.22), (6.0 if f.big else 4.0) * K)
					draw_line(f.pos + up * (h + 40.0), f.pos + up * (h + 10.0), Color(1, 0.7, 0.3, 0.4), 3.0 * K)


## Tapered light column in the stratagem colour, fading toward the sky.
func _pillar(pos: Vector2, col: Color, pulse: float, up: Vector2, height: float) -> void:
	var side := up.orthogonal()
	var w0 := (15.0 + pulse * 4.0) * K
	var w1 := w0 * 0.35
	var pts := PackedVector2Array([pos + side * w0, pos - side * w0, pos - side * w1 + up * height, pos + side * w1 + up * height])
	var cols := PackedColorArray([Color(col, 0.5 * pulse + 0.15), Color(col, 0.5 * pulse + 0.15), Color(col, 0.0), Color(col, 0.0)])
	draw_polygon(pts, cols)
	var inner := PackedVector2Array([pos + side * 4.0 * K, pos - side * 4.0 * K, pos - side * 1.5 * K + up * height * 0.8, pos + side * 1.5 * K + up * height * 0.8])
	var ic := PackedColorArray([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0)])
	draw_polygon(inner, ic)
	var now := Time.get_ticks_msec() * 0.001
	for i in 5: # rising motes
		var tt := fmod(now * 0.9 + i * 0.2, 1.0)
		draw_circle(pos + up * (tt * height * 0.8) + side * sin(i * 7.0 + now * 3.0) * 8.0, (2.0 * (1.0 - tt) + 0.5) * K, Color(1, 1, 1, 0.8 * (1.0 - tt)))


func _falling_pod(pos: Vector2, up: Vector2, k: float, height: float, size: float) -> void:
	Fx.draw_pod(self, pos, up, k, height, size)
