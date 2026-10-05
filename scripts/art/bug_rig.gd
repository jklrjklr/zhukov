class_name BugRig
extends Rig
## Terminid cutout rig: 6 legs (upper + lower segment, tripod gait), abdomen / bile sac, thorax,
## armor plates, head with mandibles and eyes (hunters also have raptor claws). Art is authored
## at radius 15 and drawn at radius / 15. Part art is baked once into the RigAtlas; the
## procedural animation (walk, turn lean, breathing, wind-up / strike, leap, spit, stagger,
## death curl) only writes transforms.

enum M { IDLE, ATTACK, LEAP, SPIT, STUN, DEAD }

const LEG_Y := [-6.0, 1.0, 8.0]
const BLOOD_DEAD := 0.45

## Walking leg angles per kind: kind -> {u: [PackedFloat32Array per leg], l: [...]} sampled over the
## swing -1..1 (LUT_N + 1 samples), so the per-frame gait is two lookups per leg.
const LUT_N := 32
static var _luts := {}

var kind := 0
var phase := 0.0
var _cfg: Dictionary
var _seed := 0.0
var _clock := 0.0
var _move := 0.0
var _reach := 0.0
var _tuck := 0.0
var _curl := 0.0
var _spit := 0.0
var _aware := false
var _flash_on := false
var _legs_idle := false
var _knee := Vector2.ZERO
var _tip := Vector2.ZERO
var _lu: Array[Node2D] = []
var _ll: Array[Node2D] = []
var _body: Node2D
var _abd: Node2D
var _head: Node2D
var _thorax: Node2D
var _sac: Node2D
var _glow: Sprite2D
var _mand: Array[Node2D] = []
var _eyes: Array[Sprite2D] = []
var _cu: Array[Node2D] = []
var _cl: Array[Node2D] = []
var _plates: Array[Node2D] = []
var _lut_u: Array
var _lut_l: Array
var _sgn := PackedFloat32Array()


static func make(k: int, art_scale: float) -> BugRig:
	var r := BugRig.new()
	r.kind = k
	r._cfg = Terminid.KINDS[k]
	r.setup(BugRig.rig_def(k), art_scale)
	r._bind()
	r._seed = randf() * TAU
	r.phase = randf() * TAU
	return r


static func _pal(cfg: Dictionary, mode: int) -> Dictionary:
	var body: Color = cfg.color
	var dark: Color = cfg.dark
	if mode == RigArt.Mode.DEAD:
		body = body.darkened(BLOOD_DEAD)
		dark = dark.darkened(BLOOD_DEAD)
	return {"body": body, "dark": dark, "plate": body.lightened(0.18)}


static func leg_rest(i: int, s: float) -> Array[Vector2]:
	var y: float = LEG_Y[i]
	return [Vector2(s * 6.0, y), Vector2(s * 14.0, y + (i - 1) * 3.0 - 3.0), Vector2(s * 18.0, y + (i - 1) * 6.0 + 2.0)]


## Knee and tip of leg `i` on side `s` (art units, body frame). gait = tripod swing -1..1,
## raise = front legs reared for a strike, tuck = pulled in for a leap, curl = dead.
static func leg_pose(i: int, s: float, gait: float, raise: float, tuck: float, curl: float) -> Array[Vector2]:
	var y: float = LEG_Y[i]
	var p := (gait if i % 2 == 0 else -gait) * s
	var root := Vector2(s * 6.0, y)
	var knee := Vector2(s * 14.0, y + (i - 1) * 3.0 - 3.0 + p * 3.0)
	var tip := Vector2(s * 18.0, y + (i - 1) * 6.0 + 2.0 + p * 5.0)
	if raise > 0.0 and i == 0:
		knee.y -= 3.0 * raise
		tip = tip.lerp(Vector2(s * 13.0, y - 13.0), raise)
	if tuck > 0.0:
		knee = knee.lerp(Vector2(s * 11.0, y - 1.0), tuck)
		tip = tip.lerp(Vector2(s * 8.0, y + 7.0), tuck)
	if curl > 0.0:
		knee = knee.lerp(root + Vector2(s * 6.5, (i - 1) * 1.5), curl)
		tip = tip.lerp(Vector2(s * 8.0, y + 4.5 + (i - 1) * 1.0), curl)
	return [knee, tip]


static func _lut(k: int) -> Dictionary:
	if _luts.has(k):
		return _luts[k]
	var u: Array = []
	var l: Array = []
	for i in 3:
		for s in [-1.0, 1.0]:
			var r := leg_rest(i, s)
			var ru := (r[1] - r[0]).angle()
			var rl := (r[2] - r[1]).angle() - ru
			var au := PackedFloat32Array()
			var al := PackedFloat32Array()
			for n in LUT_N + 1:
				var p := -1.0 + 2.0 * n / LUT_N
				var kt := leg_pose(i, s, p * s * (1.0 if i % 2 == 0 else -1.0), 0.0, 0.0, 0.0)
				var a := (kt[0] - r[0]).angle()
				au.append(ru + wrapf(a - ru, -PI, PI))
				var b := (kt[1] - kt[0]).angle() - a
				al.append(rl + wrapf(b - rl, -PI, PI))
			u.append(au)
			l.append(al)
	_luts[k] = {"u": u, "l": l}
	return _luts[k]


static func rig_def(kind: int) -> Dictionary:
	var cfg: Dictionary = Terminid.KINDS[kind]
	var armored: bool = cfg.armor > 0
	var blood: Color = Terminid.BLOOD[kind]
	var parts: Array = []
	var over := {}
	# --- Legs (drawn under the body): upper + lower segment per leg --------------------
	for i in 3:
		for s in [-1.0, 1.0]:
			var r := leg_rest(i, s)
			var up := r[1] - r[0]
			var lo := r[2] - r[1]
			var lu := up.length()
			var ll := lo.length()
			var tag := "%d%s" % [i, "r" if s > 0.0 else "l"]
			parts.append({"id": "lu" + tag, "tex": "lu%d" % i, "parent": "", "pos": r[0], "rot": up.angle(),
				"bounds": Rect2(-4.0, -4.0, lu + 8.0, 8.0),
				"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
					var pal := _pal(cfg, mode)
					RigArt.limb(ci, t, Vector2.ZERO, Vector2(lu, 0), 2.1, pal.dark, 0.85)})
			parts.append({"id": "ll" + tag, "tex": "ll%d" % i, "parent": "lu" + tag, "pos": Vector2(lu, 0), "rot": lo.angle() - up.angle(),
				"bounds": Rect2(-4.0, -4.0, ll + 9.0, 8.0),
				"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
					var pal := _pal(cfg, mode)
					RigArt.limb(ci, t, Vector2.ZERO, Vector2(ll, 0), 2.1, pal.dark, 0.85)
					ci.draw_circle(Vector2.ZERO, 1.5, (pal.body as Color).darkened(0.1))
					ci.draw_line(Vector2(ll, 0), Vector2(ll + 2.5, 0.8), RigArt.OUTLINE, 1.6)})
			var curled := leg_pose(i, s, 0.0, 0.0, 0.0, 1.0)
			var cu := curled[0] - r[0]
			over["lu" + tag] = {"rot": cu.angle()}
			over["ll" + tag] = {"rot": (curled[1] - curled[0]).angle() - cu.angle()}
	# --- Body group -----------------------------------------------------------------------
	parts.append({"id": "body", "parent": "", "pos": Vector2.ZERO, "rot": 0.0})
	match kind:
		Terminid.Kind.BILE_SPITTER:
			parts.append({"id": "sac", "parent": "body", "pos": Vector2(0, 14), "rot": 0.0, "bounds": Rect2(-16, -18, 32, 36),
				"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
					var pal := _pal(cfg, mode)
					var dead: bool = mode == RigArt.Mode.DEAD
					RigArt.ell(ci, t, Vector2.ZERO, Vector2(12, 14), pal.dark if dead else Color(0.75, 0.85, 0.2))
					RigArt.ell(ci, t, Vector2(0, 2), Vector2(7, 8), pal.dark if dead else Color(0.9, 1.0, 0.4, 0.8), false)
					if not dead:
						for a in [-0.8, 0.0, 0.8]:
							ci.draw_line(Vector2(0, 2), Vector2(sin(a) * 10.0, 2.0 + cos(a) * 8.0), Color(0.45, 0.6, 0.1, 0.8), 1.0)})
			parts.append({"id": "abd", "parent": "body", "pos": Vector2(0, 5), "rot": 0.0, "bounds": Rect2(-12, -9, 24, 18),
				"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
					RigArt.ell(ci, t, Vector2.ZERO, Vector2(8, 5), _pal(cfg, mode).dark)})
		Terminid.Kind.HUNTER:
			parts.append({"id": "abd", "parent": "body", "pos": Vector2(0, 11), "rot": 0.0, "bounds": Rect2(-10, -13, 20, 26),
				"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
					RigArt.ell(ci, t, Vector2.ZERO, Vector2(6, 9), _pal(cfg, mode).dark)
					ci.draw_line(Vector2(-4, -1), Vector2(4, -1), RigArt.OUTLINE, 1.0)
					ci.draw_line(Vector2(-4, 3), Vector2(4, 3), RigArt.OUTLINE, 1.0)})
		_:
			parts.append({"id": "abd", "parent": "body", "pos": Vector2(0, 11), "rot": 0.0, "bounds": Rect2(-12, -15, 24, 30),
				"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
					RigArt.ell(ci, t, Vector2.ZERO, Vector2(8, 10), _pal(cfg, mode).dark)
					for yy in [-3.0, 1.0, 5.0]:
						ci.draw_line(Vector2(-6, yy), Vector2(6, yy), RigArt.OUTLINE, 1.0)})
	# Thorax (wound variant: goo blots) and carapace plates.
	parts.append({"id": "thorax", "parent": "body", "pos": Vector2(0, -1), "rot": 0.0, "bounds": Rect2(-12, -13, 24, 28),
		"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
			_thorax_art(ci, t, mode, cfg, armored, blood, false),
		"variants": {"wound": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
			_thorax_art(ci, t, mode, cfg, armored, blood, true)}})
	if armored:
		for k in 3:
			var w := 8.5 - absf(k - 1.0) * 1.5
			parts.append({"id": "plate%d" % k, "parent": "body", "pos": Vector2(0, -5.0 + k * 4.5), "rot": 0.0, "bounds": Rect2(-12, -7, 24, 14),
				"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
					var pl: Color = _pal(cfg, mode).plate
					RigArt.ell(ci, t, Vector2.ZERO, Vector2(w, 3.2), pl.darkened(k * 0.08))
					ci.draw_line(Vector2(-w * 0.7, -1.6), Vector2(w * 0.7, -1.6), pl.lightened(0.35), 1.0)})
		for s in [-1.0, 1.0]:
			var tag := "r" if s > 0.0 else "l"
			parts.append({"id": "shoulder" + tag, "tex": "shoulder", "parent": "body", "pos": Vector2(s * 9.0, -3.0), "rot": 0.0, "bounds": Rect2(-7, -9, 14, 18),
				"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
					var pl: Color = _pal(cfg, mode).plate
					RigArt.ell(ci, t, Vector2.ZERO, Vector2(3.4, 5.0), pl.darkened(0.12))
					ci.draw_circle(Vector2(0, -1), 0.9, pl.lightened(0.4))})
			if kind == Terminid.Kind.WARRIOR:
				parts.append({"id": "spike" + tag, "tex": "spike" + tag, "parent": "body", "pos": Vector2(s * 4.0, 4.0), "rot": 0.0, "bounds": Rect2(-6, -3, 12, 12),
					"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
						ci.draw_set_transform_matrix(t)
						ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s * 3.0, 5.0), Vector2(-s * 2.0, 3.0)]),
							(_pal(cfg, mode).plate as Color).darkened(0.3))})
	# Hunter raptor claws (behind the head).
	if kind == Terminid.Kind.HUNTER:
		for s in [-1.0, 1.0]:
			var tag := "r" if s > 0.0 else "l"
			var base := Vector2(s * 5.0, -8.0)
			var mid := Vector2(s * 11.0, -17.0)
			var tip := Vector2(s * 7.0, -25.0)
			parts.append({"id": "cu" + tag, "tex": "cu", "parent": "body", "pos": base, "rot": (mid - base).angle(), "bounds": Rect2(-4, -4, 19, 8),
				"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
					RigArt.limb(ci, t, Vector2.ZERO, Vector2(11, 0), 2.0, (_pal(cfg, mode).body as Color).lightened(0.25), 0.9)})
			parts.append({"id": "cl" + tag, "tex": "cl", "parent": "cu" + tag, "pos": Vector2(11, 0), "rot": (tip - mid).angle() - (mid - base).angle(), "bounds": Rect2(-4, -4, 17, 8),
				"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
					RigArt.limb(ci, t, Vector2.ZERO, Vector2(9, 0), 2.0, (_pal(cfg, mode).body as Color).lightened(0.25), 0.9)})
	# Head, mandibles, eyes, bile-spit glow.
	parts.append({"id": "head", "parent": "body", "pos": Vector2(0, -11), "rot": 0.0, "bounds": Rect2(-10, -10, 20, 20),
		"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
			var pal := _pal(cfg, mode)
			RigArt.ell(ci, t, Vector2.ZERO, Vector2(6, 5.5), (pal.body as Color).darkened(0.15))
			if armored:
				ci.draw_arc(Vector2.ZERO, 4.5, PI * 1.15, PI * 1.85, 8, (pal.plate as Color).lightened(0.3), 1.2)})
	for s in [-1.0, 1.0]:
		var tag := "r" if s > 0.0 else "l"
		parts.append({"id": "mand" + tag, "tex": "mand", "parent": "head", "pos": Vector2(s * 3.0, -3.0), "rot": s * atan2(2.0, 6.0), "bounds": Rect2(-4, -11, 8, 13),
			"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
				var col: Color = Color(0.8, 0.72, 0.55) if mode != RigArt.Mode.DEAD else _pal(cfg, mode).dark
				RigArt.limb(ci, t, Vector2.ZERO, Vector2(0, -7), 1.4, col, 0.8)})
		parts.append({"id": "eye" + tag, "tex": "eye", "parent": "head", "pos": Vector2(s * 2.6, -1.0), "rot": 0.0, "bounds": Rect2(-3, -3, 6, 6),
			"draw": func(ci: CanvasItem, t: Transform2D, mode: int) -> void:
				ci.draw_set_transform_matrix(t)
				ci.draw_circle(Vector2.ZERO, 1.5, Color.WHITE if mode != RigArt.Mode.DEAD else Color(0.1, 0.05, 0.04))})
	if kind == Terminid.Kind.BILE_SPITTER:
		parts.append({"id": "glow", "parent": "head", "pos": Vector2(0, -6.0), "rot": 0.0, "bounds": Rect2(-4, -4, 8, 8), "skip_corpse": true,
			"draw": func(ci: CanvasItem, t: Transform2D, _mode: int) -> void:
				ci.draw_set_transform_matrix(t)
				ci.draw_circle(Vector2.ZERO, 3.0, Color.WHITE)})
	return {"key": "bug%d" % kind, "parts": parts,
		"corpse": {"bounds": Rect2(-30, -38, 60, 72), "over": over}}


static func _thorax_art(ci: CanvasItem, t: Transform2D, mode: int, cfg: Dictionary, armored: bool, blood: Color, wound: bool) -> void:
	var pal := _pal(cfg, mode)
	RigArt.ell(ci, t, Vector2.ZERO, Vector2(9, 9), pal.body)
	ci.draw_line(Vector2(-7, 0), Vector2(7, 0), pal.dark, 1.5)
	if not armored:
		ci.draw_circle(Vector2(-2.5, -3.0), 2.2, (pal.body as Color).lightened(0.3))
	if wound or mode == RigArt.Mode.DEAD:
		ci.draw_circle(Vector2(3.5, 1.5), 2.0, Color(blood, 0.8))
		ci.draw_circle(Vector2(-4.0, 7.0), 1.5, Color(blood, 0.8))


func _bind() -> void:
	for i in 3:
		for s in ["l", "r"]:
			var tag := "%d%s" % [i, s]
			_lu.append(nodes["lu" + tag])
			_ll.append(nodes["ll" + tag])
	_body = nodes["body"]
	_abd = nodes["abd"]
	_head = nodes["head"]
	_thorax = nodes["thorax"]
	_sac = nodes.get("sac")
	_glow = nodes.get("glow")
	for s in ["l", "r"]:
		_mand.append(nodes["mand" + s])
		_eyes.append(nodes["eye" + s])
		if nodes.has("cu" + s):
			_cu.append(nodes["cu" + s])
			_cl.append(nodes["cl" + s])
	var lut := _lut(kind)
	_lut_u = lut.u
	_lut_l = lut.l
	for i in 3:
		for si in 2:
			_sgn.append((-1.0 if si == 0 else 1.0) * (1.0 if i % 2 == 0 else -1.0))
	if _glow:
		_glow.visible = false
	for e in _eyes:
		e.self_modulate = Color(0.1, 0.05, 0.04)


## One frame of procedural animation. move 0..1 (fraction of run speed), turn rad/s (signed),
## mode M.*, k attack / spit progress 0..1, flash 0..1 (hit), wounded below half hp.
func animate(delta: float, move: float, turn: float, mode: int, k: float, aware: bool, flash: float, wounded: bool) -> void:
	_clock += delta
	_move = move_toward(_move, move, delta * 6.0)
	phase = fmod(phase + _move * 2.4 * TAU * delta, TAU)
	var reach_t := 0.0
	var tuck_t := 0.0
	var curl_t := 0.0
	var spit_t := 0.0
	match mode:
		M.ATTACK:
			reach_t = k
		M.LEAP:
			reach_t = 1.0
			tuck_t = 1.0
		M.SPIT:
			spit_t = k
		M.DEAD:
			curl_t = 1.0
	_reach = move_toward(_reach, reach_t, delta * 8.0)
	_tuck = move_toward(_tuck, tuck_t, delta * 10.0)
	_curl = move_toward(_curl, curl_t, delta * 2.2)
	_spit = move_toward(_spit, spit_t, delta * 6.0)
	# Legs (tripod gait): LUT while walking, exact poses for strikes / leaps / death, nothing when still.
	var special := _reach > 0.001 or _tuck > 0.001 or _curl > 0.001
	var still := _move < 0.005 and not special
	if not (still and _legs_idle):
		_legs_idle = still
		var gait := sin(phase) * _move
		if not special:
			for li in 6:
				# p = +-gait: mirror the sample position for legs with a negative sign.
				var p := gait * _sgn[li]
				var x := (p * 0.5 + 0.5) * LUT_N
				var n := clampi(int(x), 0, LUT_N - 1)
				var f := x - n
				var au: PackedFloat32Array = _lut_u[li]
				var al: PackedFloat32Array = _lut_l[li]
				(_lu[li] as Node2D).rotation = au[n] + (au[n + 1] - au[n]) * f
				(_ll[li] as Node2D).rotation = al[n] + (al[n + 1] - al[n]) * f
		else:
			for i in 3:
				for si in 2:
					var s := -1.0 if si == 0 else 1.0
					var li := i * 2 + si
					var kt := leg_pose(i, s, gait, _reach, _tuck, _curl)
					var root: Vector2 = (_lu[li] as Node2D).position / RigAtlas.SS
					var ur := (kt[0] - root).angle()
					(_lu[li] as Node2D).rotation = ur
					(_ll[li] as Node2D).rotation = (kt[1] - kt[0]).angle() - ur
	# Body: bob, breathing, lunge.
	var bob := sin(phase * 2.0) * 0.45 * _move
	var breathe := 1.0 + 0.022 * sin(_clock * 2.3 + _seed) * (1.0 - _move)
	_body.position = Vector2(0, bob) * RigAtlas.SS
	_body.scale = Vector2(1.0 + _reach * 0.05 + _spit * 0.04, breathe + _reach * 0.06 + _tuck * 0.1 + _spit * 0.05)
	var lean := clampf(turn * 0.05, -0.3, 0.3)
	var stun := sin(_clock * 9.0) * 0.25 if mode == M.STUN else 0.0
	Rig.place(_head, Vector2(0, -11.0 - _reach * 4.5 - _spit * 2.5 + (sin(phase * 2.0) * 0.4 * _move)))
	_head.rotation = lean * 0.6 + stun + sin(phase) * 0.04 * _move
	_abd.rotation = -lean + sin(phase) * 0.06 * _move
	# Mandibles open with the strike.
	var open := 0.5 + _reach * 0.6 + sin(_clock * 3.1 + _seed) * 0.04 * (1.0 - _reach)
	var ma := atan2(4.0 * open, 6.0)
	_mand[0].rotation = -ma
	_mand[1].rotation = ma
	if not _cu.is_empty():
		for si in 2:
			var s := -1.0 if si == 0 else 1.0
			var base := Vector2(s * 5.0, -8.0)
			var mid := Vector2(s * (11.0 - _reach * 3.0), -17.0 - _reach * 3.0)
			var tip := Vector2(s * (7.0 - _reach * 4.0), -25.0 - _reach * 7.0)
			var ua := (mid - base).angle()
			(_cu[si] as Node2D).rotation = ua
			(_cl[si] as Node2D).rotation = (tip - mid).angle() - ua
	if _sac:
		var pulse := 1.0 + 0.06 * sin(_clock * 8.0) + _spit * 0.18
		_sac.scale = Vector2(pulse, pulse)
	if _glow:
		_glow.visible = _spit > 0.02
		if _glow.visible:
			var gs := (2.0 + _spit * 3.2) / 3.0
			_glow.scale = Vector2(gs, gs)
			_glow.self_modulate = Color(0.8, 1.0, 0.3, 0.8)
	if aware != _aware:
		_aware = aware
		var ec := Color(1.0, 0.18, 0.1) if aware else Color(0.1, 0.05, 0.04)
		for e in _eyes:
			e.self_modulate = ec
	if wounded:
		set_variant("thorax", "wound")
	# Hit flash / death tint via modulate.
	var tint := 1.0 + 1.0 * clampf(flash * 10.0, 0.0, 1.0)
	if _curl > 0.0:
		var c := Color(1, 1, 1).lerp(Color(0.62, 0.55, 0.55), _curl)
		modulate = c
		_flash_on = false
	elif tint > 1.0 or _flash_on:
		_flash_on = tint > 1.0
		modulate = Color(tint, tint, tint)


## The death curl has finished.
func settled() -> bool:
	return _curl >= 0.999
