extends Node2D
## Procedural Terminid rig: mass-spring body, velocity-aligned heading with a speed-dependent turn-rate limit,
## planted-foot 2-segment IK legs (alternating tripod gait, swing arcs), spring-damper head / abdomen / antennae,
## additive hit flinches and cheap physical deaths (friction slide, progressive leg curl, settle bounce).
## The director only supplies intent (goal_dir / goal_speed / look_pos / posture); everything is integrated in
## fixed sub-steps (<= ~8 ms) so the motion is identical at 30 and 60 fps. Faces +x in rig space.

const Lib = preload("res://scripts/art_test/art_lib.gd")

signal stepped(pos: Vector2, heavy: bool)
signal landed(pos: Vector2)

const SUBSTEP := 1.0 / 120.0

var prefix := "scav"
var heavy := false
var meta: Dictionary
var k := 1.0

# ---- state owned by the rig
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var facing := 0.0
var yaw_rate := 0.0
var t := 0.0
var dead := false
var dead_t := 0.0

# ---- intent from the director
var goal_dir := Vector2.ZERO
var goal_speed := 0.0
var look_pos := Vector2.ZERO
var has_look := false
var crouch := 0.0            # 0..1 weight shift back, head lowered, rear legs brace
var tremble := 0.0           # 0..1 shaking (wind-up)
var breathe := 0.012         # breathing amplitude
var breathe_rate := 1.6
var mand_open := 0.25
var glow_phase := 0.0
var turn_mul := 1.0
var gait_mul := 1.0          # >1 = quicker, shorter swings (scrabbling)

# ---- physical parameters (preset per bug)
var vmax := 300.0
var acc := 400.0
var dec := 700.0
var grip := 6.0
var turn_idle := 3.0
var turn_fast := 1.5
var turn_acc := 12.0
var min_align := 0.2
var stride_min := 0.25
var stride_max := 0.45
var swing_min := 0.06
var swing_max := 0.14
var lean_k := 0.002
var step_impact := 0.2
var head_k := 120.0
var head_zeta := 0.55
var head_max := 0.9
var dead_visc := 4.0
var dead_coul := 150.0
var curl_time := 0.7

# ---- nodes
var body: Node2D
var legs_root: Node2D
var fx_root: Node2D
var thorax: Node2D
var head: Node2D
var abd: Node2D
var mands: Array[Node2D] = []
var ants: Array[Node2D] = []
var femurs: Array[Node2D] = []
var tibias: Array[Node2D] = []
var hips: Array[Vector2] = []
var rest_dirs: Array[Vector2] = []

# ---- legs
var feet_w: Array[Vector2] = []
var foot_from: Array[Vector2] = []
var step_u: Array[float] = []
var step_dur: Array[float] = []
var stepping: Array[bool] = []
var lift: Array[float] = []
var cool: Array[float] = []
var curl_j: Array[float] = []
var knee_fwd := [1.0, 1.0, -1.0, 1.0, 1.0, -1.0]

# ---- springs
var lean := Vector2.ZERO
var lean_v := Vector2.ZERO
var off := Vector2.ZERO          # flinch offset (body space)
var off_v := Vector2.ZERO
var sway := 0.0
var sway_v := 0.0
var zb := 0.0
var zb_v := 0.0
var sq := 0.0
var sq_v := 0.0
var head_a := 0.0
var head_av := 0.0
var abd_a := 0.0
var abd_av := 0.0
var ant_a := [0.0, 0.0]
var ant_av := [0.0, 0.0]
var mo := 0.25
var mo_v := 0.0
var crouch_s := 0.0
var crouch_v := 0.0
var breathe_s := 0.012
var trem_s := 0.0
var hit_part := {"head": 0.0, "thorax": 0.0, "abd": 0.0}
var acc_l := Vector2.ZERO
var _landed := false
var _pending_dead_impulse := 0.0
var death_tone := 1.0
var wobble_seed := 0.0

var _sprites: Array = []          # [Sprite2D, Material, Node2D]
var _glows: Array = []
var _shadows: Array = []          # [src Node2D, holder Node2D]
var shadow_off := Vector2(6, 7)
var dmg := 0
var _parts: Dictionary = {}


static func sn(x: float, s: float) -> float:
	## smooth deterministic noise in [-1, 1]
	return 0.5 * sin(x * 1.0 + s * 7.1) + 0.3 * sin(x * 2.37 + s * 3.7 + 1.3) + 0.2 * sin(x * 5.13 + s * 1.9 + 2.1)


static func _hash(i: int, s: float) -> float:
	return fposmod(sin(float(i) * 12.9898 + s * 78.233) * 43758.5453, 1.0)


func setup(prefix_: String, shadow_layer: Node2D, shadow_offset: Vector2, shadow_radius: float) -> void:
	prefix = prefix_
	meta = Lib.layout["meta"][prefix]
	heavy = meta["heavy"]
	k = meta["k"]
	shadow_off = shadow_offset
	_preset()
	body = Node2D.new()
	add_child(body)
	legs_root = Node2D.new()
	body.add_child(legs_root)
	fx_root = Node2D.new()
	body.add_child(fx_root)
	for j in 6:
		var side := -1.0 if j < 3 else 1.0
		var hp: Array = meta["hips"][j % 3]
		hips.append(Vector2(hp[0], side * hp[1]))
		rest_dirs.append(Vector2([0.5, 0.0, -0.6][j % 3], side).normalized())
		femurs.append(_mk("%s_femur" % prefix, legs_root, shadow_layer, shadow_radius))
		tibias.append(_mk("%s_tibia" % prefix, legs_root, shadow_layer, shadow_radius))
		feet_w.append(Vector2.ZERO)
		foot_from.append(Vector2.ZERO)
		step_u.append(0.0)
		step_dur.append(0.1)
		stepping.append(false)
		lift.append(0.0)
		cool.append(0.0)
		curl_j.append(0.0)
	abd = _mk("%s_abd" % prefix, fx_root, shadow_layer, shadow_radius)
	abd.position = Vector2(meta["abd"][0], 0)
	thorax = _mk("%s_thorax" % prefix, fx_root, shadow_layer, shadow_radius)
	head = Node2D.new()
	head.position = Vector2(meta["neck"][0], 0)
	fx_root.add_child(head)
	var ap: Array = meta["ant"]
	for s in [-1.0, 1.0]:
		var a := _mk("%s_ant" % prefix, head, shadow_layer, shadow_radius)
		a.position = Vector2(ap[0], s * absf(ap[1]))
		a.scale = Vector2(1, s)
		ants.append(a)
	var hd := _mk("%s_head" % prefix, head, shadow_layer, shadow_radius)
	hd.name = "headpart"
	var mp: Array = meta["mand"][0]
	for s in [-1.0, 1.0]:
		var m := _mk("%s_mand" % prefix, head, shadow_layer, shadow_radius)
		m.position = Vector2(mp[0], s * absf(mp[1]))
		m.scale = Vector2(1, s)
		mands.append(m)
	_parts = {"head": hd, "thorax": thorax, "abd": abd}
	wobble_seed = glow_phase
	mo = mand_open
	breathe_s = breathe
	place(Vector2.ZERO, 0.0)


func _preset() -> void:
	if heavy:
		vmax = 900.0; acc = 260.0; dec = 600.0; grip = 4.5
		turn_idle = 1.5; turn_fast = 0.55; turn_acc = 3.2; min_align = 0.0
		stride_min = 0.27; stride_max = 0.5; swing_min = 0.06; swing_max = 0.3
		lean_k = 0.007; step_impact = 1.0
		head_k = 38.0; head_zeta = 0.62; head_max = 0.8
		dead_visc = 3.0; dead_coul = 240.0; curl_time = 0.95
		breathe = 0.012; breathe_rate = 1.5
	else:
		vmax = 420.0; acc = 1500.0; dec = 1800.0; grip = 9.0
		turn_idle = 10.0; turn_fast = 7.0; turn_acc = 42.0; min_align = 0.35
		stride_min = 0.22; stride_max = 0.4; swing_min = 0.05; swing_max = 0.11
		lean_k = 0.0016; step_impact = 0.08
		head_k = 240.0; head_zeta = 0.5; head_max = 0.9
		dead_visc = 3.2; dead_coul = 110.0; curl_time = 0.65
		breathe = 0.01; breathe_rate = 7.0


func place(p: Vector2, ang: float) -> void:
	pos = p
	facing = ang
	vel = Vector2.ZERO
	yaw_rate = 0.0
	position = pos
	for j in 6:
		feet_w[j] = _to_w(_rest_local(j))
		foot_from[j] = feet_w[j]
		stepping[j] = false
		step_u[j] = 0.0
		lift[j] = 0.0
		curl_j[j] = 0.0
	head_a = 0.0
	body.rotation = facing


func _to_w(p: Vector2) -> Vector2:
	return pos + p.rotated(facing)


func _to_l(w: Vector2) -> Vector2:
	return (w - pos).rotated(-facing)


func _mk(part_name: String, parent: Node2D, shadow_layer: Node2D, rad: float) -> Node2D:
	var n := Lib.part(part_name)
	parent.add_child(n)
	_sprites.append([n.get_meta("spr"), n.get_meta("spr").material, n])
	if n.has_meta("glows"):
		for g in n.get_meta("glows"):
			_glows.append(g)
	if shadow_layer != null:
		var h := Lib.shadow_for(n, rad)
		shadow_layer.add_child(h)
		_shadows.append([n, h])
	return n


func set_damage(level: int) -> void:
	if level == dmg:
		return
	dmg = level
	for pair in [[thorax, "thorax"], [head.get_node("headpart"), "head"]]:
		var n: Node2D = pair[0]
		var nm: String = (prefix if level == 0 else "chg_d%d" % level) + "_" + pair[1]
		var spr: Sprite2D = n.get_meta("spr")
		spr.texture = Lib.tex(nm)
		var mat := Lib.lit_mat(nm)
		spr.material = mat
		for e in _sprites:
			if e[0] == spr:
				e[1] = mat
		if n.has_meta("glows"):
			for g in n.get_meta("glows"):
				_glows.erase(g)
				g.queue_free()
			n.remove_meta("glows")
		Lib._add_glows(n, nm)
		if n.has_meta("glows"):
			for g in n.get_meta("glows"):
				_glows.append(g)


# ---------------------------------------------------------------------------------------------- reactions
func _part_at(local: Vector2) -> String:
	if local.x > meta["neck"][0] * 0.9:
		return "head"
	if local.x < meta["abd"][0] * 0.75:
		return "abd"
	return "thorax"


## Additive flinch: velocity impulse (px/s), spring push on the body, head jerk, short brighten on the hit part only.
func hit(dir: Vector2, impulse: float, point_w: Vector2 = Vector2.INF, flinch: float = -1.0, brighten: float = 0.5) -> void:
	if flinch < 0.0:
		flinch = impulse * 0.35
	vel += dir * impulse
	var dl := dir.rotated(-facing)
	off_v += dl * flinch
	lean_v += dl * flinch * 0.4
	sq_v += flinch * 0.004
	var pl := Vector2(meta["neck"][0], 0.0) if point_w == Vector2.INF else _to_l(point_w)
	var lat := dl.y if absf(dl.y) > 0.05 else (1.0 if int(t * 100.0) % 2 == 0 else -1.0)
	head_av += signf(lat) * clampf(flinch * (0.05 if not heavy else 0.025), 0.0, 5.0) * (1.4 if _part_at(pl) == "head" else 0.8)
	abd_av += -signf(lat) * clampf(flinch * 0.02, 0.0, 3.0)
	yaw_rate += (pl.x * dl.y - pl.y * dl.x) / maxf(meta["L1"] + meta["L2"], 1.0) * impulse * 0.004
	var part := _part_at(pl)
	hit_part[part] = maxf(hit_part[part], brighten)
	for kk in ant_av.size():
		ant_av[kk] += signf(lat) * 6.0 * (1.0 if not heavy else 0.4)


func die(dir: Vector2, impulse: float, point_w: Vector2 = Vector2.INF) -> void:
	hit(dir, impulse, point_w, impulse * 0.3, 0.45)
	dead = true
	dead_t = 0.0
	_landed = false
	goal_speed = 0.0
	goal_dir = Vector2.ZERO
	var pl := Vector2(meta["neck"][0], 0.0) if point_w == Vector2.INF else _to_l(point_w)
	var dl := dir.rotated(-facing)
	var spin := (pl.x * dl.y - pl.y * dl.x) / maxf(meta["L1"] + meta["L2"], 1.0)
	if absf(spin) < 0.12:
		spin = 0.12 * (1.0 if _hash(int(pos.x), 3.3) > 0.5 else -1.0)
	yaw_rate += spin * impulse * (0.012 if not heavy else 0.0035)
	mand_open = 0.95
	has_look = false


# ---------------------------------------------------------------------------------------------- update
func update(dt: float) -> void:
	if dt > 0.0:
		var n := maxi(1, ceili(dt / SUBSTEP))
		var h := dt / float(n)
		for i in n:
			_sim(h)
	_apply(dt)


func _sim(h: float) -> void:
	t += h
	var v_old := vel
	if dead:
		_sim_dead(h)
	else:
		_sim_alive(h)
	# local acceleration for lean / squash
	var a_world := (vel - v_old) / h
	acc_l = acc_l.lerp(a_world.rotated(-facing), 1.0 - exp(-h * 40.0))
	_legs(h)
	_springs(h)


func _sim_alive(h: float) -> void:
	var speed := vel.length()
	var has_goal := goal_dir.length_squared() > 0.0001
	var goal_ang := goal_dir.angle() if has_goal else facing
	var err := wrapf(goal_ang - facing, -PI, PI)
	var rate := lerpf(turn_idle, turn_fast, clampf(speed / vmax, 0.0, 1.0)) * turn_mul
	var tw := 0.0
	if has_goal:
		tw = signf(err) * minf(rate, sqrt(2.0 * turn_acc * 0.75 * absf(err)))
	yaw_rate = move_toward(yaw_rate, tw, turn_acc * h)
	facing = wrapf(facing + yaw_rate * h, -PI, PI)
	var fwd := Vector2.from_angle(facing)
	var lat := fwd.rotated(PI * 0.5)
	var vf := vel.dot(fwd)
	var vl := vel.dot(lat)
	var want := 0.0
	if has_goal:
		var al := clampf(cos(err), 0.0, 1.0)
		want = goal_speed * lerpf(min_align, 1.0, al * al)
	var dv := want - vf
	var lim := acc if (dv > 0.0 and vf >= 0.0) else dec
	vf += clampf(dv * 6.0, -lim, lim) * h
	vl *= exp(-grip * h)
	vel = fwd * vf + lat * vl
	pos += vel * h


func _sim_dead(h: float) -> void:
	dead_t += h
	var sp := vel.length()
	if sp > 0.0:
		var sp2 := maxf(0.0, sp - (dead_coul + dead_visc * sp) * h)
		vel = vel / sp * sp2
		sp = sp2
	pos += vel * h
	yaw_rate *= exp(-(2.2 + (0.0 if sp > 30.0 else 3.0)) * h)
	facing = wrapf(facing + yaw_rate * h, -PI, PI)
	if not _landed and sp < 40.0 and dead_t > 0.12:
		_landed = true
		zb_v += (-1.1 if heavy else -0.7)
		landed.emit(pos)


# ---------------------------------------------------------------------------------------------- springs
func _springs(h: float) -> void:
	var cs := crouch_s
	# crouch target (critically damped, smooth weight shift)
	crouch_v += (60.0 * (crouch - crouch_s) - 15.5 * crouch_v) * h
	crouch_s += crouch_v * h
	trem_s = lerpf(trem_s, tremble, 1.0 - exp(-h * 6.0))
	breathe_s = lerpf(breathe_s, breathe, 1.0 - exp(-h * 3.0))
	var c := _curl_all()
	# lean (body mass relative to the leg bases)
	var lm := 2.9 * k
	var lt := Vector2(-acc_l.x * lean_k, -acc_l.y * lean_k)
	lt = lt.limit_length(lm)
	lt.x += -crouch_s * 1.7 * k
	lean_v += (70.0 * (lt - lean) - 11.0 * lean_v) * h
	lean += lean_v * h
	# flinch offset
	off_v += (150.0 * (Vector2.ZERO - off) - 13.0 * off_v) * h
	off += off_v * h
	# gait sway / bob
	sway_v += (90.0 * (0.0 - sway) - 8.0 * sway_v) * h
	sway += sway_v * h
	var zt := -0.05 * c if dead else (-0.045 * crouch_s)
	zb_v += (170.0 * (zt - zb) - 11.0 * zb_v) * h
	zb += zb_v * h
	var sqt := clampf(-acc_l.x * 0.00006 * (1.0 if heavy else 0.5), -0.025, 0.06)
	sq_v += (110.0 * (sqt - sq) - 12.0 * sq_v) * h
	sq += sq_v * h
	# head: spring-damper toward the look target, with lag + overshoot
	var ht := 0.0
	if has_look and not dead:
		ht = clampf(wrapf((look_pos - pos).angle() - facing, -PI, PI), -head_max, head_max)
	if not dead:
		var gd := goal_dir.length_squared() > 0.0001
		if gd:
			ht += clampf(wrapf(goal_dir.angle() - facing, -PI, PI) * 0.35, -0.3, 0.3)
		ht += sn(t * (1.1 if heavy else 2.6), wobble_seed) * (0.03 if heavy else 0.07)
	else:
		ht = 0.55 * signf(yaw_rate + 0.001) * minf(1.0, dead_t * 3.0) + 0.0
	var hc := 2.0 * head_zeta * sqrt(head_k)
	head_av += (head_k * (ht - head_a) - hc * head_av) * h
	head_a += head_av * h
	# abdomen trails with its own (jiggly) spring
	var at := clampf(-yaw_rate * (0.12 if heavy else 0.05) - acc_l.y * 0.00012, -0.6, 0.6)
	if dead:
		at = 0.3 * minf(1.0, dead_t * 4.0)
	var ak := 36.0 if heavy else 120.0
	abd_av += (ak * (at - abd_a) - 2.0 * 0.32 * sqrt(ak) * abd_av) * h
	abd_a += abd_av * h
	# antennae: loose springs, lagging the head turn
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var tgt := 0.55 + 0.14 * sn(t * (2.2 if not heavy else 1.2) + i * 1.7, wobble_seed + 3.0)
		if dead:
			tgt = 0.9 + 0.1 * sn(t, 1.0) - 0.4 * minf(1.0, dead_t * 2.0)
		tgt -= head_av * 0.03
		ant_av[i] += (80.0 * (tgt - ant_a[i]) - 2.0 * 0.3 * sqrt(80.0) * ant_av[i]) * h
		ant_a[i] += ant_av[i] * h
	# mandibles
	var mt := mand_open + (0.07 * sn(t * 3.1, wobble_seed + 8.0) if not dead else 0.0) + 0.3 * crouch_s
	mo_v += (140.0 * (mt - mo) - 2.0 * 0.6 * sqrt(140.0) * mo_v) * h
	mo += mo_v * h
	for kk in hit_part.keys():
		hit_part[kk] = maxf(0.0, hit_part[kk] * exp(-h * 16.0) - h * 1.2)


# ---------------------------------------------------------------------------------------------- legs
func _rest_local(j: int) -> Vector2:
	var reach: float = meta["L1"] + meta["L2"]
	var ext := 0.8 - 0.55 * curl_j[j]
	var r := hips[j] + rest_dirs[j] * reach * ext
	if crouch_s != 0.0:
		var rear := j % 3 == 2
		var front := j % 3 == 0
		r += Vector2(-0.2 * reach * crouch_s if rear else (0.05 * reach * crouch_s if front else 0.0),
			signf(hips[j].y) * reach * 0.12 * crouch_s)
	return r


func _curl_all() -> float:
	var s := 0.0
	for j in 6:
		s += curl_j[j]
	return s / 6.0


func _group(j: int) -> int:
	return 0 if j in [0, 2, 4] else 1


func _legs(h: float) -> void:
	if dead:
		_legs_dead(h)
		return
	var reach: float = meta["L1"] + meta["L2"]
	var speed := vel.length()
	var sf := clampf(speed / vmax, 0.0, 1.0)
	var thr := reach * lerpf(stride_min, stride_max, sf)
	var interval := 1.8 * thr / maxf(speed, 10.0)
	var sw := clampf(0.45 * interval, swing_min, swing_max) / gait_mul
	var vdir := vel / speed if speed > 5.0 else Vector2.ZERO
	var lead := vdir * thr * 0.8 * clampf(speed / (0.12 * vmax), 0.0, 1.0)
	var rot_lead := clampf(yaw_rate * sw * 0.6, -0.5, 0.5)
	var lat := Vector2.from_angle(facing + PI * 0.5)
	var swinging := [false, false]
	for j in 6:
		cool[j] = maxf(0.0, cool[j] - h)
		if stepping[j]:
			var g := _group(j)
			swinging[g] = true
			step_u[j] += h / step_dur[j]
			var u := minf(step_u[j], 1.0)
			var rem := (1.0 - u) * step_dur[j]
			var tgt := _to_w(_rest_local(j).rotated(rot_lead)) + vel * rem + lead
			var e := u * u * (3.0 - 2.0 * u)
			e = lerpf(e, 1.0 - (1.0 - u) * (1.0 - u), 0.5)
			var side := signf(hips[j].y)
			feet_w[j] = foot_from[j].lerp(tgt, e) + lat * side * reach * 0.07 * sin(PI * u)
			lift[j] = sin(PI * u)
			if u >= 1.0:
				stepping[j] = false
				lift[j] = 0.0
				cool[j] = 0.04
				feet_w[j] = tgt
				_plant(j, speed)
	# decide new steps (tripod groups step together, only if the other tripod is on the ground)
	var trig := [false, false]
	var dist: Array[float] = []
	for j in 6:
		var rest_w := _to_w(_rest_local(j))
		var d := feet_w[j].distance_to(rest_w)
		dist.append(d)
		if stepping[j] or cool[j] > 0.0:
			continue
		var g := _group(j)
		var emergency := d > thr * 1.9 or feet_w[j].distance_to(_to_w(hips[j])) > reach * 0.96
		if emergency or (d > thr and not swinging[1 - g]):
			trig[g] = true
	for g in 2:
		if not trig[g] or swinging[1 - g]:
			if not (trig[g] and _any_emergency(g, reach)):
				continue
		for j in 6:
			if _group(j) != g or stepping[j] or cool[j] > 0.0:
				continue
			if dist[j] > thr * 0.5 or feet_w[j].distance_to(_to_w(hips[j])) > reach * 0.9:
				stepping[j] = true
				step_u[j] = 0.0
				step_dur[j] = sw * (0.9 + 0.2 * _hash(j, t * 0.0 + wobble_seed))
				foot_from[j] = feet_w[j]


func _any_emergency(g: int, reach: float) -> bool:
	for j in 6:
		if _group(j) == g and not stepping[j] and feet_w[j].distance_to(_to_w(hips[j])) > reach * 0.96:
			return true
	return false


func _plant(j: int, speed: float) -> void:
	var imp := step_impact * (0.35 + 0.65 * clampf(speed / (0.4 * vmax), 0.0, 1.0)) * (0.5 if speed < 8.0 else 1.0)
	zb_v -= imp * 0.34
	sway_v += signf(hips[j].y) * imp * 0.9 * k * 0.35
	if heavy:
		sq_v += imp * 0.1
	stepped.emit(feet_w[j], heavy)


func _legs_dead(h: float) -> void:
	var reach: float = meta["L1"] + meta["L2"]
	for j in 6:
		var delay := 0.1 + 0.18 * _hash(j, 5.5)
		var dur := curl_time * (0.75 + 0.5 * _hash(j, 9.1))
		var u := clampf((dead_t - delay) / dur, 0.0, 1.0)
		curl_j[j] = u * u * (3.0 - 2.0 * u)
		var tgt := _to_w(_rest_local(j))
		# death throes: a few weak twitches that fade out
		var tw := exp(-dead_t * 3.0) * 0.12 * reach
		tgt += Vector2(sn(t * 14.0 + j, 2.0), sn(t * 12.0 + j * 2.0, 4.0)) * tw
		if curl_j[j] > 0.0:
			feet_w[j] = feet_w[j].lerp(tgt, 1.0 - exp(-h * (4.0 + 10.0 * curl_j[j])))
		else:
			feet_w[j] += Vector2(sn(t * 14.0 + j, 2.0), 0.0) * 0.0
		# tether: a planted foot is dragged once the sliding body pulls it to full reach
		var hw := _to_w(hips[j])
		var dv := feet_w[j] - hw
		if dv.length() > reach * 0.97:
			feet_w[j] = hw + dv.normalized() * reach * 0.97
		lift[j] = 0.0
		stepping[j] = false


func _ik(j: int, hh: Vector2, f: Vector2, l1: float, l2: float) -> void:
	var d := f - hh
	var dist := clampf(d.length(), 0.22 * (l1 + l2), (l1 + l2) * 0.999)
	var base := d.angle()
	var cosa := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var a := acos(cosa)
	var k1 := hh + Vector2.from_angle(base + a) * l1
	var k2 := hh + Vector2.from_angle(base - a) * l1
	var want: float = knee_fwd[j]
	var kn := k1 if (k1.x - k2.x) * want > 0.0 else k2
	var fe := femurs[j]
	var ti := tibias[j]
	var th := 1.0 + (0.3 if heavy else 0.2) * lift[j]
	fe.position = hh
	fe.rotation = (kn - hh).angle()
	fe.scale = Vector2(1.0, th)
	ti.position = kn
	var tip := hh + d.normalized() * dist
	ti.rotation = (tip - kn).angle()
	ti.scale = Vector2((tip - kn).length() / l2, th)


# ---------------------------------------------------------------------------------------------- visuals
func _apply(dt: float) -> void:
	position = pos
	body.rotation = facing
	var c := _curl_all() if dead else 0.0
	head.rotation = head_a
	var hsx := 1.0 - 0.22 * crouch_s - 0.2 * c
	head.scale = Vector2(hsx, 1.0)
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		mands[i].rotation = s * mo
		ants[i].rotation = s * ant_a[i]
	thorax.position = Vector2(-5.2 * k * crouch_s - 1.3 * c * k, 0.0)
	abd.rotation = abd_a
	var tr := Vector2(sn(t * 61.0, 1.0), sn(t * 53.0, 6.0)) * trem_s * 1.6 * (k * 0.6 + 0.4)
	fx_root.position = lean + off + Vector2(0.0, sway) + tr
	var br := 1.0 + breathe_s * sin(t * TAU * breathe_rate)
	var sx := 1.0 - sq - 0.07 * c + 0.5 * zb
	var sy := (1.0 + 0.6 * sq - 0.09 * c + 0.5 * zb) * br
	fx_root.scale = Vector2(sx, sy)
	for j in 6:
		_ik(j, hips[j], _to_l(feet_w[j]), meta["L1"], meta["L2"])
	var tone := 1.0
	if dead:
		tone = lerpf(1.0, 0.58, clampf(dead_t / 0.9, 0.0, 1.0))
	modulate = Color(tone, tone * 0.96, tone * 0.94, 1.0)
	var gi := 0
	for g in _glows:
		if is_instance_valid(g):
			var a := 0.0 if dead and c > 0.6 else (0.42 + 0.2 * sin(t * 5.0 + gi * 1.7 + glow_phase))
			g.modulate.a = a
			gi += 1
	# hit brighten on the hit part only (multiplies the part's albedo before shading)
	for key in _parts.keys():
		var hv: float = hit_part[key]
		var spr: Sprite2D = _parts[key].get_meta("spr")
		spr.modulate = Color(1.0 + hv * 0.9, 1.0 + hv * 0.85, 1.0 + hv * 0.65, 1.0)


func sync_shadows() -> void:
	var a := modulate.a
	for pair in _shadows:
		var src: Node2D = pair[0]
		var h: Node2D = pair[1]
		var xf := src.global_transform
		xf.origin += shadow_off
		h.global_transform = xf
		h.modulate.a = a


func free_shadows() -> void:
	for pair in _shadows:
		pair[1].queue_free()
	_shadows.clear()
