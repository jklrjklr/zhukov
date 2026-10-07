extends Node2D
## Cutout Terminid rig (thorax, head, 2 mandibles, abdomen, 6 two-segment legs with planted-foot IK).
## Faces +x in rig space; `facing` rotates `body`. Feet live in world space and only move when stepping,
## so heavy bugs plant their feet and small bugs skitter.

const Lib = preload("res://scripts/art_test/art_lib.gd")

signal stepped(pos: Vector2, heavy: bool)

var prefix := "scav"
var heavy := false
var meta: Dictionary
var k := 1.0

var body: Node2D
var legs_root: Node2D
var fx_root: Node2D
var thorax: Node2D
var head: Node2D
var abd: Node2D
var mands: Array[Node2D] = []
var femurs: Array[Node2D] = []
var tibias: Array[Node2D] = []
var hips: Array[Vector2] = []
var rest_dirs: Array[Vector2] = []
var feet_w: Array[Vector2] = []
var foot_from: Array[Vector2] = []
var foot_to: Array[Vector2] = []
var step_t: Array[float] = []
var stepping: Array[bool] = []
var knee_fwd := [1.0, 1.0, -1.0, 1.0, 1.0, -1.0]

var facing := 0.0
var head_rel := 0.0
var head_sx := 1.0
var mand_open := 0.25
var thorax_off := 0.0
var abd_rot := 0.0
var abd_lag := 0.0
var crumple := 0.0
var breathe := 0.0
var step_dist_f := 0.3
var step_time := 0.2
var gait_lock := true
var dead := false
var flash_frames := 0
var dmg := 0
var kick := Vector2.ZERO
var t := 0.0
var glow_phase := 0.0

var _sprites: Array = []          # [Sprite2D, Material]
var _glows: Array = []
var _shadows: Array = []          # [src Node2D, holder Node2D]
var shadow_off := Vector2(6, 7)
var _prev_facing := 0.0


func setup(prefix_: String, shadow_layer: Node2D, shadow_offset: Vector2, shadow_radius: float) -> void:
	prefix = prefix_
	meta = Lib.layout["meta"][prefix]
	heavy = meta["heavy"]
	k = meta["k"]
	shadow_off = shadow_offset
	body = Node2D.new()
	add_child(body)
	legs_root = Node2D.new()
	body.add_child(legs_root)
	fx_root = Node2D.new()
	body.add_child(fx_root)
	var l1: float = meta["L1"]
	var l2: float = meta["L2"]
	for j in 6:
		var side := -1.0 if j < 3 else 1.0
		var hp: Array = meta["hips"][j % 3]
		hips.append(Vector2(hp[0], side * hp[1]))
		var dir := Vector2([0.5, 0.0, -0.6][j % 3], side).normalized()
		rest_dirs.append(dir)
		var fe := _mk("%s_femur" % prefix, legs_root, shadow_layer, shadow_radius)
		var ti := _mk("%s_tibia" % prefix, legs_root, shadow_layer, shadow_radius)
		femurs.append(fe)
		tibias.append(ti)
		feet_w.append(Vector2.ZERO)
		foot_from.append(Vector2.ZERO)
		foot_to.append(Vector2.ZERO)
		step_t.append(0.0)
		stepping.append(false)
	abd = _mk("%s_abd" % prefix, fx_root, shadow_layer, shadow_radius)
	abd.position = Vector2(meta["abd"][0], 0)
	thorax = _mk("%s_thorax" % prefix, fx_root, shadow_layer, shadow_radius)
	head = Node2D.new()
	head.position = Vector2(meta["neck"][0], 0)
	fx_root.add_child(head)
	var hd := _mk("%s_head" % prefix, head, shadow_layer, shadow_radius)
	hd.name = "headpart"
	var mp: Array = meta["mand"][0]
	for s in [-1.0, 1.0]:
		var m := _mk("%s_mand" % prefix, head, shadow_layer, shadow_radius)
		m.position = Vector2(mp[0], s * absf(mp[1]))
		m.scale = Vector2(1, s)
		mands.append(m)
	# glow sprites keep a stable pulse
	for e in _sprites:
		pass
	reset_feet()


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
	var suf := "" if level == 0 else "_d%d" % level
	var pre := prefix if level == 0 else "chg_d%d" % level
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
		# glows: remove old, add new
		if n.has_meta("glows"):
			for g in n.get_meta("glows"):
				_glows.erase(g)
				g.queue_free()
			n.remove_meta("glows")
		Lib._add_glows(n, nm)
		if n.has_meta("glows"):
			for g in n.get_meta("glows"):
				_glows.append(g)


func rest_local(j: int) -> Vector2:
	var reach: float = meta["L1"] + meta["L2"]
	var ext := 0.8 - 0.5 * crumple
	return hips[j] + rest_dirs[j] * reach * ext


func reset_feet() -> void:
	for j in 6:
		feet_w[j] = body.to_global(rest_local(j))
		foot_from[j] = feet_w[j]
		foot_to[j] = feet_w[j]


func flash(frames: int = 2) -> void:
	flash_frames = frames


func update(dt: float, vel: Vector2) -> void:
	t += dt
	body.rotation = facing
	# abdomen lags behind turns
	var dy := wrapf(facing - _prev_facing, -PI, PI)
	_prev_facing = facing
	if dt > 0.0:
		abd_lag = lerpf(abd_lag, clampf(-dy / dt * 0.08, -0.5, 0.5), 1.0 - exp(-dt * 10.0))
	abd.rotation = abd_rot + abd_lag
	head.rotation = head_rel
	head.scale = Vector2(head_sx, 1.0)
	for i in 2:
		mands[i].rotation = (-1.0 if i == 0 else 1.0) * mand_open
	thorax.position = Vector2(thorax_off, 0.0)
	var cs := Vector2(1.0 - 0.16 * crumple, 1.0 - 0.24 * crumple)
	var br := 1.0 + breathe * sin(t * 6.0)
	fx_root.scale = cs * Vector2(1.0, br)
	kick = kick.lerp(Vector2.ZERO, 1.0 - exp(-dt * 14.0))
	fx_root.position = kick
	_update_legs(dt, vel)
	# glows pulse
	var gi := 0
	for g in _glows:
		if is_instance_valid(g):
			var a := 0.0 if dead and crumple > 0.6 else (0.42 + 0.2 * sin(t * 5.0 + gi * 1.7 + glow_phase))
			g.modulate.a = a
			gi += 1
	# flash / normal materials
	for e in _sprites:
		var spr: Sprite2D = e[0]
		spr.material = Lib.flash_mat() if flash_frames > 0 else e[1]
	if flash_frames > 0:
		flash_frames -= 1


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


func _group(j: int) -> int:
	return 0 if j in [0, 2, 4] else 1


func _update_legs(dt: float, vel: Vector2) -> void:
	var l1: float = meta["L1"]
	var l2: float = meta["L2"]
	var reach := l1 + l2
	var sd := reach * step_dist_f
	var sp := vel.length()
	for j in 6:
		var rest_w := body.to_global(rest_local(j))
		if dead:
			feet_w[j] = rest_w
			stepping[j] = false
		elif stepping[j]:
			step_t[j] += dt / step_time
			var f := minf(step_t[j], 1.0)
			f = f * f * (3.0 - 2.0 * f)
			feet_w[j] = foot_from[j].lerp(foot_to[j], f)
			if step_t[j] >= 1.0:
				stepping[j] = false
				stepped.emit(feet_w[j], heavy)
		else:
			var d := feet_w[j].distance_to(rest_w)
			var other_busy := false
			if gait_lock:
				for o in 6:
					if stepping[o] and _group(o) != _group(j):
						other_busy = true
			if (d > sd and not other_busy) or d > sd * 1.9:
				stepping[j] = true
				step_t[j] = 0.0
				foot_from[j] = feet_w[j]
				foot_to[j] = rest_w + vel * step_time * 0.55
		# IK in body space
		var fl := body.to_local(feet_w[j])
		_ik(j, hips[j], fl, l1, l2)


func _ik(j: int, h: Vector2, f: Vector2, l1: float, l2: float) -> void:
	var d := f - h
	var dist := clampf(d.length(), 0.4 * (l1 + l2), (l1 + l2) * 0.999)
	var base := d.angle()
	var cosa := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var a := acos(cosa)
	var k1 := h + Vector2.from_angle(base + a) * l1
	var k2 := h + Vector2.from_angle(base - a) * l1
	var want: float = knee_fwd[j]
	var kn := k1 if (k1.x - k2.x) * want > 0.0 else k2
	var fe := femurs[j]
	var ti := tibias[j]
	fe.position = h
	fe.rotation = (kn - h).angle()
	ti.position = kn
	var tip := h + d.normalized() * dist
	ti.rotation = (tip - kn).angle()
	# stretch tibia slightly so the tip always reaches the foot
	var need := (tip - kn).length()
	ti.scale = Vector2(need / l2, 1.0)
