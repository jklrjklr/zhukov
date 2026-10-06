class_name ChargerRig
extends Rig
## Charger cutout rig: four jointed claws (upper segment + foot), pulsing rear sac, carapace,
## side plates, three front armor plates, head with horns / mandibles / eyes. Art authored at 1x
## (the enemy scales the rig by Charger.ART_SCALE). Animation: stride (faster and wider when
## charging), rear-up wind-up (front plates and head lift), breathing, hit flash, death curl.

const PLATE := Color(0.45, 0.32, 0.22)
const DARK := Color(0.28, 0.2, 0.15)
const SAC := Color(1.0, 0.55, 0.15)
const LEG_L0 := 11.0

var phase := 0.0
var _clock := 0.0
var _move := 0.0
var _lift := 0.0
var _curl := 0.0
var _amp := 5.0
var _aware := false
var _flash_on := false
var _legs_idle := false
var _upper: Array[RigPart] = [] # fl, fr, bl, br
var _foot: Array[RigPart] = []
var _sac: RigPart
var _body: RigPart
var _head: RigPart
var _plates: Array[RigPart] = []
var _eyes: Array[RigPart] = []
var _glint: RigPart


static func make(art_scale: float) -> ChargerRig:
	var r := ChargerRig.new()
	r.setup(ChargerRig.rig_def(), art_scale)
	r._bind()
	r.phase = randf() * TAU
	return r


static func _pal(mode: int) -> Dictionary:
	var dead: bool = mode == RigArt.Mode.DEAD
	return {"plate": PLATE.darkened(0.5) if dead else PLATE, "dark": DARK.darkened(0.5) if dead else DARK,
		"sac": Color(0.35, 0.15, 0.08) if dead else SAC, "dead": dead}


static func leg_point(front: bool, s: float, stride: float, amp: float, curl: float) -> Vector2:
	var p := Vector2(s * 28.0, -16.0 + stride * s * amp) if front else Vector2(s * 26.0, 18.0 - stride * s * amp)
	if curl > 0.0:
		p = p.lerp(Vector2(s * 21.0, -5.0 if front else 9.0), curl)
	return p


static func leg_root(front: bool, s: float, p: Vector2) -> Vector2:
	return Vector2(s * 18.0, p.y * 0.7)


static func rig_def(_unused := 0) -> Dictionary:
	var parts: Array = []
	var over := {}
	for fi in 2:
		var front := fi == 0
		for s in [-1.0, 1.0]:
			var tag := "%s%s" % ["f" if front else "b", "r" if s > 0.0 else "l"]
			var p0 := leg_point(front, s, 0.0, 5.0, 0.0)
			var root := leg_root(front, s, p0)
			parts.append({"id": "lu" + tag, "tex": "lu", "parent": "", "pos": root, "rot": (p0 - root).angle(),
				"bounds": Rect2(-6, -6, LEG_L0 + 12, 12),
				"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
					RigArt.limb(ci, t, Vector2.ZERO, Vector2(LEG_L0, 0), 4.5, _pal(mode).dark, 1.25)})
			parts.append({"id": "ft" + tag, "tex": "ft" + ("r" if s > 0.0 else "l"), "parent": "", "pos": p0, "rot": 0.0,
				"bounds": Rect2(-12, -12, 28, 24) if s > 0.0 else Rect2(-16, -12, 28, 24),
				"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
					var d: Color = _pal(mode).dark
					ci.draw_set_transform_matrix(t)
					ci.draw_circle(Vector2.ZERO, 8.5, RigArt.OUTLINE)
					ci.draw_circle(Vector2.ZERO, 7.0, d)
					for c in 3:
						ci.draw_line(Vector2.ZERO, Vector2(s * 6.0, (c - 1) * 5.0), RigArt.OUTLINE, 2.2)
					ci.draw_circle(Vector2(-1.5, -1.5), 2.5, d.lightened(0.25))})
			var pc := leg_point(front, s, 0.0, 5.0, 1.0)
			var rc := leg_root(front, s, pc)
			over["ft" + tag] = {"pos": pc}
			over["lu" + tag] = {"rot": (pc - rc).angle()}
	parts.append({"id": "sac", "parent": "", "pos": Vector2(0, 31), "rot": 0.0, "bounds": Rect2(-20, -19, 40, 40),
		"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
			var pal := _pal(mode)
			var sc: Color = pal.sac
			RigArt.ell(ci, t, Vector2.ZERO, Vector2(16, 15), sc.darkened(0.25), true, 1.6)
			RigArt.ell(ci, t, Vector2(0, 2), Vector2(9, 9), sc, false)
			if not pal.dead:
				for a in [-0.7, 0.0, 0.7]:
					ci.draw_line(Vector2(0, 2), Vector2(sin(a) * 13.0, 2.0 + cos(a) * 10.0), Color(0.6, 0.2, 0.05, 0.7), 1.2)
				ci.draw_arc(Vector2(0, 2), 12.0, 0.0, TAU, 20, Color(1, 0.85, 0.3, 0.3), 1.0)})
	parts.append({"id": "body", "parent": "", "pos": Vector2(0, 4), "rot": 0.0, "bounds": Rect2(-28, -34, 56, 68),
		"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
			RigArt.ell(ci, t, Vector2.ZERO, Vector2(24, 29), _pal(mode).dark, true, 1.6)
			ci.draw_set_transform_matrix(t)
			for k in 4:
				var y := -2.0 + k * 7.0
				ci.draw_arc(Vector2(0, y + 6.0 - 4.0), 22.0 - k * 1.5, PI * 1.12, PI * 1.88, 12, RigArt.OUTLINE, 1.6)})
	for s in [-1.0, 1.0]:
		var tag := "r" if s > 0.0 else "l"
		parts.append({"id": "side" + tag, "tex": "side" + tag, "parent": "body", "pos": Vector2(s * 21.0, -2.0), "rot": 0.0,
			"bounds": Rect2(-12, -24, 24, 48),
			"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
				var pl: Color = _pal(mode).plate
				RigArt.ell(ci, t, Vector2.ZERO, Vector2(7.5, 18), pl.darkened(0.12), true, 1.6)
				ci.draw_line(Vector2(-2.0 * s, -14), Vector2(-2.0 * s, 12), pl.lightened(0.25), 1.2)
				for y in [-8.0, 0.0, 8.0]:
					ci.draw_circle(Vector2(1.0 * s, y - 2.0), 1.3, pl.lightened(0.4))})
	for i in 3:
		parts.append({"id": "plate%d" % i, "parent": "body", "pos": Vector2(0, -22.0 + i * 9.0), "rot": 0.0,
			"bounds": Rect2(-33, -15, 66, 30),
			"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
				var pc: Color = (_pal(mode).plate as Color).darkened(i * 0.1)
				RigArt.ell(ci, t, Vector2.ZERO, Vector2(27 - i * 3, 9), pc, true, 1.6)
				ci.draw_set_transform_matrix(t)
				ci.draw_arc(Vector2.ZERO, 24.0 - i * 3.0, PI * 1.1, PI * 1.9, 14, pc.lightened(0.35), 1.6)
				for x in [-14.0 + i * 3.0, 14.0 - i * 3.0]:
					ci.draw_circle(Vector2(x, 1.0), 1.4, pc.lightened(0.45))})
	parts.append({"id": "head", "parent": "body", "pos": Vector2(0, -34), "rot": 0.0, "bounds": Rect2(-14, -14, 28, 28),
		"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
			RigArt.ell(ci, t, Vector2.ZERO, Vector2(10, 9.5), (_pal(mode).plate as Color).darkened(0.15), true, 1.6)})
	for s in [-1.0, 1.0]:
		var tag := "r" if s > 0.0 else "l"
		parts.append({"id": "horn" + tag, "tex": "horn", "parent": "head", "pos": Vector2(s * 7.0, -3.0), "rot": s * PI / 4.0, "behind": true,
			"bounds": Rect2(-5, -14, 10, 16),
			"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
				RigArt.limb(ci, t, Vector2.ZERO, Vector2(0, -9.9), 2.8, (_pal(mode).plate as Color).lightened(0.15), 1.1)})
		parts.append({"id": "mand" + tag, "tex": "mand", "parent": "head", "pos": Vector2(s * 6.0, -6.0), "rot": s * atan2(5.0, 10.0),
			"bounds": Rect2(-5, -15, 10, 17),
			"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
				var col: Color = Color(0.8, 0.72, 0.55) if mode != RigArt.Mode.DEAD else _pal(mode).dark
				RigArt.limb(ci, t, Vector2.ZERO, Vector2(0, -11.2), 1.8, col, 1.1)})
		parts.append({"id": "eye" + tag, "tex": "eye", "parent": "head", "pos": Vector2(s * 4.0, -1.0), "rot": 0.0,
			"bounds": Rect2(-4, -4, 8, 8),
			"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
				ci.draw_set_transform_matrix(t)
				ci.draw_circle(Vector2.ZERO, 2.0, Color.WHITE if mode != RigArt.Mode.DEAD else Color(0.1, 0.05, 0.04))})
	parts.append({"id": "glint", "parent": "head", "pos": Vector2.ZERO, "rot": 0.0, "bounds": Rect2(-5, -5, 10, 10), "skip_corpse": true,
		"draw": func(ci: CanvasItem, t: Transform2D, _mode: int) -> void:
			ci.draw_set_transform_matrix(t)
			ci.draw_circle(Vector2.ZERO, 4.0, Color.WHITE)})
	return {"key": "charger", "parts": parts, "corpse": {"bounds": Rect2(-48, -56, 96, 108), "over": over}}


func _bind() -> void:
	for pre in ["f", "b"]:
		for s in ["l", "r"]:
			_upper.append(nodes["lu" + pre + s])
			_foot.append(nodes["ft" + pre + s])
	_sac = nodes["sac"]
	_body = nodes["body"]
	_head = nodes["head"]
	for i in 3:
		_plates.append(nodes["plate%d" % i])
	for s in ["l", "r"]:
		_eyes.append(nodes["eye" + s])
	_glint = nodes["glint"]
	_glint.visible = false
	_glint.self_modulate = Color(1, 0.25, 0.1)
	for e in _eyes:
		e.self_modulate = Color(0.1, 0.05, 0.04)
	touch_colors()


## move 0..1 of stalk speed (>1 when charging), charging widens the stride, rear 0..1 = wind-up
## rear-up, glint blinking at the head during the wind-up, stun = swaying head.
func animate(delta: float, move: float, charging: bool, rear: float, glint: bool, stunned: bool, aware: bool, flash: float, dead: bool) -> void:
	_clock += delta
	_move = move_toward(_move, move, delta * 6.0)
	_amp = move_toward(_amp, 9.0 if charging else 5.0, delta * 30.0)
	phase = fmod(phase + (3.0 if charging else _move * 1.2) * TAU * delta, TAU)
	_lift = move_toward(_lift, rear, delta * 8.0)
	_curl = move_toward(_curl, 1.0 if dead else 0.0, delta * 2.2)
	var still := _move < 0.005 and _curl < 0.001
	if not (still and _legs_idle):
		_legs_idle = still
		var stride := sin(phase) * (1.0 if charging else clampf(_move, 0.0, 1.0))
		for i in 4:
			var front := i < 2
			var s := -1.0 if i % 2 == 0 else 1.0
			var p := leg_point(front, s, stride, _amp, _curl)
			var root := leg_root(front, s, p)
			var v := p - root
			var up: RigPart = _upper[i]
			up.rotation = v.angle()
			up.scale.x = v.length() / LEG_L0
			Rig.place(_foot[i], p)
	var breathe := 1.0 + 0.018 * sin(_clock * 2.0) * (1.0 - _move)
	_body.scale = Vector2(1.0, breathe + _lift * 0.04)
	var pulse := 1.0 + 0.08 * sin(_clock * 6.0)
	_sac.scale = Vector2(pulse, pulse)
	for i in 3:
		Rig.place(_plates[i], Vector2(0, -22.0 + i * 9.0 - 6.0 * _lift))
	Rig.place(_head, Vector2(0, -34.0 - 6.0 * _lift))
	_head.rotation = sin(_clock * 8.0) * 0.2 if stunned else 0.0
	_glint.visible = glint
	if aware != _aware:
		_aware = aware
		var ec := Color(1, 0.2, 0.1) if aware else Color(0.1, 0.05, 0.04)
		for e in _eyes:
			e.self_modulate = ec
		touch_colors()
	var tint := 1.0 + 0.9 * clampf(flash * 12.0, 0.0, 1.0)
	if _curl > 0.0:
		modulate = Color.WHITE.lerp(Color(0.6, 0.55, 0.55), _curl)
		_flash_on = false
	elif tint > 1.0 or _flash_on:
		_flash_on = tint > 1.0
		modulate = Color(tint, tint, tint)
	commit()


func settled() -> bool:
	return _curl >= 0.999
