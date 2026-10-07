extends Node2D
## ART TEST SCENE: scripted, deterministic ~14.8 s showcase (30 fps fixed step).
##  1. ash wasteland   2. player vs scavenger pack   3. Charger telegraph / charge / dive / recovery / turn
##  4. grenade explosion on the Charger, armor cracks, finishing shots, heavy death, pickup.
## Authored in a 1280x720 layout; the world node scales itself to the window height (1080p -> x1.5).

const Lib = preload("res://scripts/art_test/art_lib.gd")
const Bug = preload("res://scripts/art_test/bug_rig.gd")
const Pl = preload("res://scripts/art_test/player_rig.gd")
const Fx = preload("res://scripts/art_test/fx.gd")

const TOTAL_T := 14.8            # seconds of scripted timeline (frame-rate independent)
const HITSTOP := 2.0 / 30.0
const ARENA := Vector2(1280, 720)
const CAM_ZOOM := 1.2
const CAM_CENTER := Vector2(530, 405)
const FOLLOW_ZOOM := 1.45         # extra zoom for the charger gait close-up (--follow-charger)

var frame := 0
var t := 0.0
var rt := 0.0                    # real (render) time, keeps running during hit-stop
var hitstop := 0.0
var follow_chg := false
var follow_scav := false
var cam_c := Vector2(530, 405)
var dust_acc := 0.0
var probe := false
var shake := 0.0
var world: Node2D
var shadow_layer: Node2D
var props_layer: Node2D
var under_layer: Node2D
var actors: Node2D
var top_layer: Node2D
var fx: Node2D
var fade_rect: ColorRect
var flash_rect: ColorRect
var flash_a := 0.0
var rng := RandomNumberGenerator.new()

# player
var pl: Node2D
var p_pos := Vector2(-70, 440)
var p_vel := Vector2.ZERO
var p_face := 0.0
var fire_cd := 0.0
var p_target: Variant = null
var dive_t := -1.0
var dive_dir := Vector2.ZERO
var retreat_to := Vector2(690, 330)
var grenade: Node2D
var grenade_sh: Node2D
var grenade_state := 0
var throw_t := -1.0
var throw_from := Vector2.ZERO
var throw_to := Vector2.ZERO
var p_collect := false

# scavengers
var scavs: Array = []
const Rig = preload("res://scripts/art_test/bug_rig.gd")
const SCAV_SPAWN := [
	[1.20, Vector2(1340, 330), 0.0], [1.40, Vector2(1350, 480), 0.31], [1.55, Vector2(1340, 570), 0.57],
	[1.80, Vector2(1360, 400), 0.83], [2.15, Vector2(1335, 250), 0.12], [2.65, Vector2(-70, 130), 0.44],
]

# charger
var chg: Bug
var c_pos := Vector2(1400, 400)
var c_face := PI
var c_vel := Vector2.ZERO
var c_phase := "wait"
var c_w := 0.0
var c_dmg := 0
var c_dead := false
var c_dead_t := 0.0
var lane_dir := Vector2.LEFT
var lane: Sprite2D
var lane_a := 0.0
var c_last_dust := 0.0
var c_hits := 0
var c_goo_pool_t := -1.0
var c_pool_dir := Vector2.RIGHT
var charge_t0 := 8.1
var pool_sprite: Sprite2D

# pickup
var pickup: Node2D
var pickup_sh: Node2D
var pickup_glow: Sprite2D
var pickup_state := 0
var pickup_t := 0.0
var pickup_from := Vector2.ZERO
var pickup_pos := Vector2.ZERO

var debris_nodes: Array = []
var motes: Array = []
var shots_pre: Array = [6.75, 6.9, 7.05, 7.55, 7.7, 7.85, 8.0]
var shots_pre_i := 0
var shots_post: Array = []
var shots_post_i := 0
var exploded := false

const T_WALK_END := 1.9
const T_WINDUP := 7.4
const T_CHARGE := 8.1
const T_BRAKE := 8.66
const T_RECOVER := 9.14
const T_THROW := 9.3
const T_BOOM := 9.95
const T_TURN := 10.1


func _ready() -> void:
	Lib.init_lib()
	rng.seed = 7
	for a in OS.get_cmdline_user_args():
		if a == "--follow-charger":
			follow_chg = true
		if a == "--follow-scav":
			follow_chg = true
			follow_scav = true
		if a == "--probe":
			probe = true
	var vs := get_viewport_rect().size
	var sc := vs.y / ARENA.y
	world = Node2D.new()
	world.scale = Vector2.ONE * sc * CAM_ZOOM
	world.position = vs * 0.5 - CAM_CENTER * sc * CAM_ZOOM
	add_child(world)
	_build_ground()
	fx = Fx.new()
	fx.decal_layer = Node2D.new()
	fx.decal_layer.z_index = -90
	world.add_child(fx.decal_layer)
	shadow_layer = Node2D.new()
	shadow_layer.z_index = -80
	world.add_child(shadow_layer)
	props_layer = Node2D.new()
	props_layer.z_index = -70
	world.add_child(props_layer)
	under_layer = Node2D.new()
	under_layer.z_index = -55
	world.add_child(under_layer)
	actors = Node2D.new()
	world.add_child(actors)
	top_layer = Node2D.new()
	top_layer.z_index = 40
	world.add_child(top_layer)
	fx.under_layer = under_layer
	fx.top_layer = top_layer
	world.add_child(fx)
	_build_props()
	_build_actors()
	_build_overlay()
	seed_scatter()


func _build_ground() -> void:
	var g := Sprite2D.new()
	g.texture = Lib.tex("ground_tile")
	g.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	g.centered = false
	g.region_enabled = true
	g.region_rect = Rect2(0, 0, (ARENA.x + 360) * 2, (ARENA.y + 360) * 2)
	g.scale = Vector2(0.5, 0.5)
	g.position = Vector2(-180, -180)
	g.z_index = -100
	world.add_child(g)


func _prop(n: String, pos: Vector2, rot: float, sh := Vector2(8, 9), rad := 3.0) -> Node2D:
	var p := Lib.part(n)
	p.position = pos
	p.rotation = rot
	props_layer.add_child(p)
	var h := Lib.shadow_for(p, rad)
	shadow_layer.add_child(h)
	var xf := p.transform
	xf.origin += sh
	h.transform = xf
	return p


func _build_props() -> void:
	# rocks (no outline) and wall pieces: framing the arena, clear of the fight lanes
	_prop("rock2", Vector2(110, 175), 0.4, Vector2(11, 12), 4.0)
	_prop("rock0", Vector2(1020, 160), 2.2, Vector2(9, 10))
	_prop("rock1", Vector2(930, 640), 1.0)
	_prop("rock3", Vector2(255, 650), 0.2, Vector2(5, 6))
	_prop("rock0", Vector2(1010, 560), 4.0, Vector2(9, 10))
	_prop("rock1", Vector2(520, 160), 3.0, Vector2(7, 8))
	_prop("rock2", Vector2(60, 585), 1.7, Vector2(11, 12), 4.0)
	_prop("wall0", Vector2(760, 125), 0.06, Vector2(9, 10), 4.0)
	_prop("wall1", Vector2(500, 668), -0.12, Vector2(8, 9))
	_prop("wall2", Vector2(1040, 340), 1.5, Vector2(9, 10), 4.0)
	_prop("rock3", Vector2(300, 120), 5.0, Vector2(5, 6))
	_prop("rock3", Vector2(740, 690), 2.0, Vector2(5, 6))
	_prop("rock1", Vector2(60, 330), 0.8, Vector2(7, 8))
	_prop("wall1", Vector2(150, 690), 0.5, Vector2(8, 9))
	# a couple of ground decals: dark hollows and ash drifts
	fx.decal("hollow", Vector2(300, 520), 0.0, 4.0, 0.35, 0.001)
	fx.decal("hollow", Vector2(930, 230), 0.0, 5.0, 0.3, 0.001)
	fx.decal("ash_drift", Vector2(640, 520), 0.3, 6.0, 0.5, 0.001)
	fx.decal("ash_drift", Vector2(160, 330), 1.0, 5.0, 0.4, 0.001)
	fx.decal("ash_drift", Vector2(900, 420), 2.0, 5.5, 0.45, 0.001)
	for i in 6:
		fx.decal("pock", Vector2(rng.randf_range(100, 1200), rng.randf_range(100, 640)), rng.randf() * TAU, rng.randf_range(0.8, 1.6), 0.5, 0.001)


func seed_scatter() -> void:
	for i in 70:
		var n := "debris%d" % rng.randi_range(0, 7)
		var p := Lib.part(n)
		p.position = Vector2(rng.randf_range(-20, 1300), rng.randf_range(-20, 740))
		p.rotation = rng.randf() * TAU
		p.scale = Vector2.ONE * rng.randf_range(0.8, 1.5)
		props_layer.add_child(p)
		var h := Lib.shadow_for(p, 2.0)
		shadow_layer.add_child(h)
		debris_nodes.append({"n": p, "h": h, "v": Vector2.ZERO, "w": 0.0})
	# drifting ash motes
	for i in 46:
		var s := Lib.flat("debris%d" % rng.randi_range(0, 3))
		s.material = null
		s.modulate = Color(0.78, 0.76, 0.72, rng.randf_range(0.18, 0.38))
		s.scale = Vector2.ONE * rng.randf_range(0.18, 0.4)
		s.position = Vector2(rng.randf_range(0, 1280), rng.randf_range(0, 720))
		top_layer.add_child(s)
		motes.append({"n": s, "v": Vector2(rng.randf_range(16, 34), rng.randf_range(4, 14)), "ph": rng.randf() * 6.0})


func _build_actors() -> void:
	pl = Pl.new()
	pl.z_index = 20
	actors.add_child(pl)
	pl.setup(shadow_layer)
	pl.position = p_pos
	pl.shadow_off = Vector2(7, 8)
	for e in SCAV_SPAWN:
		var b := Bug.new()
		b.z_index = 5
		b.glow_phase = e[2] * 9.0
		actors.add_child(b)
		b.setup("scav", shadow_layer, Vector2(5, 6), 2.0)
		b.vmax = 520.0
		var sp: Vector2 = e[1]
		b.place(sp, (Vector2(480, 440) - sp).angle())
		b.visible = false
		b.landed.connect(_on_scav_landed)
		var d := {"rig": b, "pos": sp, "spawn": e[0], "hp": 2, "state": "run", "dead_t": 0.0,
			"speed": 340.0 + e[2] * 110.0, "hit_dir": Vector2.RIGHT, "ph": e[2], "pool": null}
		scavs.append(d)
		_set_shadows_visible(b, false)
	chg = Bug.new()
	chg.z_index = 10
	actors.add_child(chg)
	chg.setup("chg", shadow_layer, Vector2(12, 14), 5.0)
	chg.place(c_pos, c_face)
	chg.visible = false
	chg.stepped.connect(_on_chg_step)
	chg.landed.connect(_on_chg_landed)
	_set_shadows_visible(chg, false)
	# telegraph lane
	lane = Sprite2D.new()
	lane.texture = Lib.tex("telegraph")
	lane.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	lane.region_enabled = true
	lane.centered = false
	lane.offset = Vector2(0, -96)
	lane.scale = Vector2(0.5, 0.5)
	lane.visible = false
	under_layer.add_child(lane)
	# grenade
	grenade = Lib.part("grenade")
	grenade.visible = false
	top_layer.add_child(grenade)
	grenade_sh = Lib.shadow_for(grenade, 2.0)
	shadow_layer.add_child(grenade_sh)
	grenade_sh.visible = false
	# pickup
	pickup = Lib.part("pickup_crate")
	pickup.visible = false
	pickup.z_index = 15
	actors.add_child(pickup)
	pickup_sh = Lib.shadow_for(pickup, 2.0)
	shadow_layer.add_child(pickup_sh)
	pickup_sh.visible = false
	pickup_glow = Lib.flat("glow")
	pickup_glow.material = Lib.add_mat()
	pickup_glow.modulate = Color(0.3, 0.6, 1.0, 0.0)
	pickup_glow.scale = Vector2.ONE * 1.4
	pickup_glow.z_index = 14
	actors.add_child(pickup_glow)


func _set_shadows_visible(b: Node2D, v: bool) -> void:
	for pair in b._shadows:
		pair[1].visible = v


func _build_overlay() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 10
	add_child(cl)
	var vg := TextureRect.new()
	vg.texture = Lib.tex("vignette")
	vg.set_anchors_preset(Control.PRESET_FULL_RECT)
	vg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vg.stretch_mode = TextureRect.STRETCH_SCALE
	vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(vg)
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 0.96, 0.88, 0)
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(flash_rect)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.03, 0.03, 0.04, 1)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(fade_rect)


# ------------------------------------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var dt := delta
	var sdt := dt
	if hitstop > 0.0:
		hitstop -= dt
		sdt = 0.0
	frame += 1
	rt += dt
	if sdt > 0.0:
		t += sdt
		_step(sdt)
	_always(dt)
	if probe and absf(fposmod(rt + 0.0001, 0.5)) < dt:
		print("PROBE rt=%.2f t=%.3f chg=(%.1f,%.1f) f=%.3f v=%.1f s0=(%.1f,%.1f)" % [rt, t, chg.pos.x, chg.pos.y, chg.facing, chg.vel.length(), scavs[0]["rig"].pos.x, scavs[0]["rig"].pos.y])
	if probe:
		_probe_feet()
	if rt >= TOTAL_T - 0.0001:
		get_tree().quit()


var _pf := {}
var _slide := 0.0
var _slide_n := 0
var _steps := 0
var _maxhead := 0.0
var _prev_facing := 0.0
var _max_dyaw := 0.0
var _prev_vel := Vector2.ZERO
var _max_da := 0.0


func _probe_feet() -> void:
	if rt > TOTAL_T - 0.05:
		print("FEET slide_total=%.3f events=%d max_dyaw/frame=%.4f max_dv/frame=%.1f" % [_slide, _slide_n, _max_dyaw, _max_da])
	if not chg.visible or c_dead:
		return
	for j in 6:
		var f: Vector2 = chg.feet_w[j]
		if _pf.has(j) and not chg.stepping[j] and not _pf[j][1]:
			var d := f.distance_to(_pf[j][0])
			if d > 0.01:
				_slide += d
				_slide_n += 1
		_pf[j] = [f, chg.stepping[j]]
	_max_dyaw = maxf(_max_dyaw, absf(wrapf(chg.facing - _prev_facing, -PI, PI)))
	_prev_facing = chg.facing
	_max_da = maxf(_max_da, (chg.vel - _prev_vel).length())
	_prev_vel = chg.vel


func _hash1(i: int, sd: float) -> float:
	return fposmod(sin(float(i) * sd) * 43758.5453, 1.0) * 2.0 - 1.0


func _always(dt: float) -> void:
	# camera shake (deterministic hash noise at 30 Hz), decays in real time even during hit-stop
	var fi := int(rt * 30.0 + 0.001)
	var n1 := _hash1(fi, 12.9898)
	var n2 := _hash1(fi, 78.233)
	var sc := world.scale.x
	var vsz := get_viewport_rect().size
	if follow_chg:
		var tgt := CAM_CENTER if not chg.visible else chg.pos
		if follow_scav:
			tgt = scavs[0]["rig"].pos
		if follow_scav:
			tgt = scavs[0]["rig"].pos
		cam_c = cam_c.lerp(tgt, 1.0 - exp(-dt * 3.5))
		var z := vsz.y / ARENA.y * CAM_ZOOM * FOLLOW_ZOOM * (2.4 if follow_scav else 1.0)
		world.scale = Vector2.ONE * z
		world.position = vsz * 0.5 - cam_c * z + Vector2(n1, n2) * shake * z * 0.5
	else:
		var base := vsz * 0.5 - CAM_CENTER * sc
		world.position = base + Vector2(n1, n2) * shake * sc
	shake = maxf(0.0, shake - (shake * 9.0 + 4.0) * dt)
	flash_a = maxf(0.0, flash_a - 4.8 * dt)
	flash_rect.color.a = flash_a
	var fa := clampf(1.0 - rt / (14.0 / 30.0), 0.0, 1.0)
	var fo := clampf((rt - (TOTAL_T - 22.0 / 30.0)) / (20.0 / 30.0), 0.0, 1.0)
	fade_rect.color.a = maxf(fa, fo)
	# shadows follow the rigs (also while frozen)
	pl.sync_shadows()
	for s in scavs:
		s["rig"].sync_shadows()
	chg.sync_shadows()
	_sync_prop_shadow(grenade, grenade_sh, Vector2(7, 9) * (1.0 + grenade.get_meta("h", 0.0) * 0.02))
	_sync_prop_shadow(pickup, pickup_sh, Vector2(6, 7))


func _sync_prop_shadow(p: Node2D, h: Node2D, off: Vector2) -> void:
	var xf := p.global_transform
	xf.origin += off * world.scale.x
	h.global_transform = xf
	h.visible = p.visible


func _step(dt: float) -> void:
	fx.update(dt)
	_motes(dt)
	_player(dt)
	for s in scavs:
		_scav(s, dt)
	_charger(dt)
	_grenade(dt)
	_pickup(dt)
	_debris(dt)


func _motes(dt: float) -> void:
	for m in motes:
		var s: Sprite2D = m["n"]
		s.position += m["v"] * dt + Vector2(0, sin(t * 0.8 + m["ph"]) * 5.0 * dt)
		if s.position.x > 1300:
			s.position.x = -20
		if s.position.y > 740:
			s.position.y = -20


func _debris(dt: float) -> void:
	for d in debris_nodes:
		var v: Vector2 = d["v"]
		if v.length() > 2.0:
			var n: Node2D = d["n"]
			n.position += v * dt
			n.rotation += d["w"] * dt
			d["v"] = v * exp(-5.0 * dt)
			d["w"] *= exp(-4.0 * dt)
			var xf := n.transform
			xf.origin += Vector2(5, 6)
			d["h"].transform = xf
		else:
			d["v"] = Vector2.ZERO


func kick_debris(pos: Vector2, radius: float, power: float) -> void:
	for d in debris_nodes:
		var n: Node2D = d["n"]
		var dd := n.position.distance_to(pos)
		if dd < radius:
			var dir := (n.position - pos).normalized()
			d["v"] = dir * power * (1.0 - dd / radius) * rng.randf_range(0.6, 1.2)
			d["w"] = rng.randf_range(-12, 12)


# ------------------------------------------------------------------------------------------ player
func _player(dt: float) -> void:
	var vel := Vector2.ZERO
	if t < T_WALK_END:
		# walk in: instant start, instant stop
		vel = Vector2(320, 0)
		p_face = 0.0
	elif dive_t >= 0.0:
		var u := (t - dive_t) / 0.26
		if u < 1.0:
			vel = dive_dir * 900.0 * (1.0 - u * 0.75)
			p_face = dive_dir.angle()
			pl.squash = Vector2(1.28, 0.74)
			pl.gun_drop = 0.0
			if int((t - dive_t) * 30.0) % 2 == 0:
				fx.dust_puff(p_pos + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6)), 0.8)
		else:
			# popped up: quick overshoot squash back to normal
			var k := clampf((t - dive_t - 0.26) / 0.1, 0.0, 1.0)
			pl.squash = Vector2(1.0, 1.0).lerp(Vector2(0.88, 1.14), 1.0 - k) if k < 1.0 else Vector2.ONE
			if k >= 1.0:
				dive_t = -1.0
	elif t >= 8.8 and t < 9.2:
		# retreat to the throwing spot
		var to := retreat_to - p_pos
		if to.length() > 14.0:
			vel = to.normalized() * 430.0
		p_face = (c_pos - p_pos).angle()
	pl.squash = pl.squash if dive_t >= 0.0 else Vector2.ONE
	# dive trigger (when the charger is almost on top of the player)
	if t >= 8.34 and dive_t < 0.0 and t < 8.6 and p_pos.y > 380.0:
		dive_t = t
		dive_dir = Vector2(0.18, -1.0).normalized()
	# shooting
	_player_shoot(dt)
	p_pos += vel * dt
	p_vel = vel
	pl.position = p_pos
	pl.facing = p_face
	pl.recoil = lerpf(pl.recoil, 0.0, 1.0 - exp(-dt * 30.0))
	pl.twist = lerpf(pl.twist, 0.0, 1.0 - exp(-dt * 18.0)) if throw_t < 0.0 else pl.twist
	_throw(dt)
	pl.update(dt, vel)


func _alive_scavs() -> Array:
	var a := []
	for s in scavs:
		if s["state"] == "run" and t >= s["spawn"] + 0.2 and s["pos"].x > -30 and s["pos"].x < 1300:
			a.append(s)
	return a


func _player_shoot(dt: float) -> void:
	fire_cd -= dt
	if t >= 1.95 and t < 5.0 and dive_t < 0.0:
		var al := _alive_scavs()
		if al.size() > 0:
			var best: Dictionary = al[0]
			for s in al:
				if s["pos"].distance_to(p_pos) < best["pos"].distance_to(p_pos):
					best = s
			if p_target != best:
				p_target = best
				fire_cd = maxf(fire_cd, 0.1)      # sharp turn: instant aim, brief settle
			p_face = (best["pos"] - p_pos).angle()
			if fire_cd <= 0.0:
				fire_cd = 0.095
				_shoot_scav(best)
		else:
			p_face = lerp_angle(p_face, 0.0, 1.0) if t > 4.7 else p_face
			if t > 4.7:
				p_face = (c_pos - p_pos).angle() if chg.visible else 0.0
	elif t >= 5.0 and t < 6.7 and chg.visible:
		p_face = (c_pos - p_pos).angle()
	# armour-plinking before the charge
	if dive_t < 0.0 and t >= 6.7 and t < 8.3:
		p_face = (c_pos - p_pos).angle()
		while shots_pre_i < shots_pre.size() and t >= shots_pre[shots_pre_i]:
			shots_pre_i += 1
			_shoot_charger(false)
	# finishing shots
	if t >= 10.3 and dive_t < 0.0 and not p_collect:
		if not c_dead or t < c_dead_t + 0.1:
			p_face = (c_pos - p_pos).angle()
		while shots_post_i < shots_post.size() and t >= shots_post[shots_post_i]:
			shots_post_i += 1
			_shoot_charger(true)


func _muzzle_world() -> Vector2:
	return world.to_local(pl.muzzle.global_position)


func _fire_visuals(target: Vector2) -> void:
	pl.recoil = 3.2
	var mp := _muzzle_world()
	fx.muzzle_flash(mp + Vector2.from_angle(p_face) * 8.0, p_face)
	fx.tracer(mp, target)
	# ejected casing (tiny spark)
	fx.add_p({"tex": "spark", "pos": mp - Vector2.from_angle(p_face) * 12.0, "vel": Vector2.from_angle(p_face + 1.6) * 150.0 + Vector2(0, 40),
		"life": 0.2, "s0": 0.5, "s1": 0.3, "a0": 1.0, "a1": 0.0, "drag": 3.0, "orient": true})


func _shoot_scav(s: Dictionary) -> void:
	var rig: Bug = s["rig"]
	var tp: Vector2 = rig.pos + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
	_fire_visuals(tp)
	var dir := (tp - p_pos).normalized()
	s["hp"] -= 1
	s["hit_dir"] = dir
	if s["hp"] <= 0:
		_kill_scav(s, tp, dir)
	else:
		rig.hit(dir, 170.0, tp, 60.0, 0.5)
		fx.goo_hit(tp, dir, 0.8)


func _kill_scav(s: Dictionary, tp: Vector2, dir: Vector2) -> void:
	s["state"] = "dying"
	s["dead_t"] = 0.0
	fx.goo_hit(tp, dir, 1.3)
	for i in 7:
		var a := dir.angle() + rng.randf_range(-1.1, 1.1)
		fx.add_p({"tex": "droplet", "pos": tp, "vel": Vector2.from_angle(a) * rng.randf_range(100, 380), "life": rng.randf_range(0.3, 0.6),
			"s0": rng.randf_range(0.8, 1.6), "s1": 0.6, "a0": 1.0, "a1": 0.0, "hold": 0.6, "drag": 3.5})
	# goo pool under the corpse: starts small and spreads while the body slides
	var pool := Lib.flat("goo%d" % rng.randi_range(0, 2))
	pool.rotation = rng.randf() * TAU
	pool.modulate.a = 0.95
	s["pool_k"] = rng.randf_range(1.0, 1.4)
	pool.scale = Vector2.ONE * 0.1
	fx.decal_layer.add_child(pool)
	s["pool"] = pool
	var rig: Bug = s["rig"]
	rig.die(dir, 430.0, tp)
	rig.z_index = -50


func _shoot_charger(post: bool) -> void:
	c_hits += 1
	var dir := (c_pos - p_pos).normalized()
	var perp := dir.rotated(PI / 2.0)
	var hp := c_pos - dir * 70.0 + perp * rng.randf_range(-20, 20)
	hp = c_pos + Vector2.from_angle(c_face) * 72.0 + perp * rng.randf_range(-22, 22)
	_fire_visuals(hp)
	if not post:
		chg.hit(dir, 8.0, hp, 70.0, 0.4)
		fx.armor_hit(hp, dir)
		shake = maxf(shake, 1.5)
		return
	var idx := shots_post_i
	var last := idx >= shots_post.size()
	if not last:
		fx.goo_hit(hp, dir, 1.0 + 0.05 * idx)
		fx.armor_hit(hp + dir * 6.0, dir) if idx <= 1 else null
		chg.hit(dir, 24.0, hp, 110.0, 0.55)
		shake = maxf(shake, 2.6)
		if idx == 3:
			c_dmg = 2
			chg.set_damage(2)
			_plate_burst(hp, dir, 8)
	else:
		_kill_charger(hp, dir)


func _plate_burst(pos: Vector2, dir: Vector2, n: int) -> void:
	for i in n:
		var a := dir.angle() + rng.randf_range(-1.4, 1.4)
		fx.add_p({"tex": "chip_plate%d" % rng.randi_range(0, 1), "pos": pos, "vel": Vector2.from_angle(a) * rng.randf_range(160, 480),
			"life": 1.2, "s0": rng.randf_range(1.0, 1.9), "s1": 1.0, "a0": 1.0, "a1": 0.0, "hold": 0.8, "drag": 2.6,
			"rot": rng.randf() * TAU, "rot_v": rng.randf_range(-16, 16), "layer": under_layer})


func _kill_charger(hp: Vector2, dir: Vector2) -> void:
	c_dead = true
	c_dead_t = t
	hitstop = HITSTOP
	shake = 12.0
	fx.goo_hit(hp, dir, 2.0)
	fx.goo_hit(hp + dir.rotated(0.6) * 10.0, dir, 1.6)
	for i in 22:
		var a := dir.angle() + rng.randf_range(-1.3, 1.3)
		fx.add_p({"tex": "droplet", "pos": hp, "vel": Vector2.from_angle(a) * rng.randf_range(160, 640), "life": rng.randf_range(0.35, 0.8),
			"s0": rng.randf_range(1.0, 2.4), "s1": 0.7, "a0": 1.0, "a1": 0.0, "hold": 0.6, "drag": 3.0})
	_plate_burst(hp, dir, 6)
	chg.die(dir, 520.0, hp)
	chg.z_index = -50
	c_pool_dir = dir
	c_goo_pool_t = t
	pool_sprite = Lib.flat("goo_big")
	pool_sprite.scale = Vector2.ONE * 0.05
	pool_sprite.position = c_pos + dir * 30.0
	pool_sprite.rotation = 0.6
	fx.decal_layer.add_child(pool_sprite)
	pickup_state = 0
	pickup_t = 0.0


# ------------------------------------------------------------------------------------------ scavengers
func _on_scav_landed(pos: Vector2) -> void:
	fx.dust_puff(pos, 0.5, Vector2.ZERO, 0.35)


func _scav(s: Dictionary, dt: float) -> void:
	var rig: Bug = s["rig"]
	if t < s["spawn"]:
		return
	rig.visible = true
	_set_shadows_visible(rig, true)
	var ph: float = s["ph"]
	if s["state"] == "run":
		var to: Vector2 = p_pos - rig.pos
		var dist := to.length()
		# light and quick but continuous: smooth speed variation, smooth weaving, no bursts
		var wob := 0.5 + 0.5 * Rig.sn(t * 1.6, ph * 20.0)
		var spd: float = s["speed"] * (0.78 + 0.5 * wob + 0.12 * Rig.sn(t * 4.3, ph * 9.0))
		var weave := 0.45 * Rig.sn(t * 1.25, ph * 13.0)
		rig.goal_dir = to.normalized().rotated(weave)
		rig.goal_speed = spd * smoothstep(40.0, 150.0, dist)
		rig.look_pos = p_pos
		rig.has_look = true
		rig.mand_open = 0.3 + 0.1 * (0.5 + 0.5 * Rig.sn(t * 2.2, ph * 5.0))
		rig.gait_mul = 1.0
	else:
		s["dead_t"] += dt
		var pool: Sprite2D = s["pool"]
		if pool != null:
			var u := clampf(s["dead_t"] / 0.9, 0.0, 1.0)
			pool.scale = Vector2.ONE * lerpf(0.1, 0.9 * s["pool_k"], 1.0 - pow(1.0 - u, 3.0))
			pool.position = rig.pos + s["hit_dir"] * 6.0 * (1.0 - u)
	rig.update(dt)
	s["pos"] = rig.pos


# ------------------------------------------------------------------------------------------ charger
func _on_chg_step(pos: Vector2, _heavy: bool) -> void:
	if c_dead:
		return
	var sp := chg.vel.length() / 900.0
	shake = maxf(shake, 0.5 + 1.6 * sp)
	fx.dust_puff(pos, 0.8 + 0.5 * sp, Vector2.ZERO, 0.38 + 0.25 * sp)
	fx.add_p({"tex": "pock", "pos": pos, "s0": 1.5, "s1": 1.7, "a0": 0.45, "a1": 0.45, "life": 0.01, "persist": true, "layer": fx.decal_layer,
		"rot": rng.randf() * TAU, "tint": Color(0.7, 0.7, 0.72)})


func _on_chg_landed(pos: Vector2) -> void:
	for i in 4:
		fx.dust_puff(pos + Vector2.from_angle(i * 1.6) * 40.0, 1.6, Vector2.from_angle(i * 1.6) * 90.0, 0.55)
	shake = maxf(shake, 4.0)


func _angle_to_player() -> float:
	return (p_pos - chg.pos).angle()


func _charger(dt: float) -> void:
	var spawn_t := 4.2
	if t < spawn_t:
		return
	chg.visible = true
	_set_shadows_visible(chg, true)
	chg.shadow_off = Vector2(12, 14)
	if c_dead:
		if pool_sprite != null:
			var u := clampf((t - c_goo_pool_t) / 1.3, 0.0, 1.0)
			pool_sprite.scale = Vector2.ONE * lerpf(0.05, 1.05, 1.0 - pow(1.0 - u, 3.0))
			pool_sprite.position = chg.pos + c_pool_dir * 26.0 * (1.0 - 0.5 * u)
		chg.update(dt)
		c_pos = chg.pos
		c_face = chg.facing
		return
	var to := p_pos - chg.pos
	chg.has_look = true
	chg.look_pos = p_pos
	# defaults (heavy walk)
	chg.acc = 260.0
	chg.dec = 600.0
	chg.grip = 4.5
	chg.gait_mul = 1.0
	chg.crouch = 0.0
	chg.tremble = 0.0
	chg.breathe = 0.012
	chg.breathe_rate = 1.5
	chg.turn_mul = 1.0
	if t < T_WINDUP:
		# slow heavy approach: velocity-aligned heading, wide turns, body sway from the gait
		chg.goal_dir = to.normalized()
		chg.goal_speed = 150.0
		chg.mand_open = 0.2 + 0.05 * Rig.sn(t * 1.3, 2.0)
	elif t < T_CHARGE:
		var u := (t - T_WINDUP) / (T_CHARGE - T_WINDUP)
		if (t - T_WINDUP) < 0.12:
			lane_dir = Vector2.from_angle(_angle_to_player())
		# wind-up: weight shifts back, head lowers, rear legs brace, mandibles flare
		chg.goal_dir = lane_dir
		chg.goal_speed = 0.0
		chg.dec = 900.0
		chg.has_look = false
		chg.crouch = 1.0
		chg.mand_open = 0.62
		var trem := clampf((u - 0.45) / 0.55, 0.0, 1.0)
		chg.tremble = trem
		shake = maxf(shake, 1.2 * trem)
		lane_a = clampf((t - (T_WINDUP + 0.05)) / 0.08, 0.0, 1.0)
		if u > 0.75:
			lane_a *= 0.65 + 0.35 * (1.0 if int(t * 30.0) % 2 == 0 else 0.0)
	elif t < T_BRAKE:
		chg.goal_dir = lane_dir
		chg.goal_speed = 840.0
		chg.acc = 2800.0
		chg.has_look = false
		chg.gait_mul = 1.15
		chg.mand_open = 0.5
		chg.crouch = 0.0
		lane_a *= exp(-dt * 20.0) if t > T_CHARGE + 0.08 else 1.0
		_charge_dust(dt, 1.0)
		kick_debris(chg.pos, 120.0, 520.0)
	elif t < T_RECOVER:
		# overshoot: long skid, little lateral grip, legs scrabbling for traction
		chg.goal_dir = lane_dir
		chg.goal_speed = 0.0
		chg.dec = 1500.0
		chg.grip = 0.9
		chg.gait_mul = 1.5
		chg.has_look = false
		chg.mand_open = 0.45
		lane_a = 0.0
		_charge_dust(dt, 0.7)
		shake = maxf(shake, 2.0 * clampf(chg.vel.length() / 800.0, 0.0, 1.0))
		kick_debris(chg.pos, 100.0, 300.0)
	elif t < T_TURN:
		# recovery: planted, heaving, head hanging low
		chg.goal_dir = Vector2.ZERO
		chg.goal_speed = 0.0
		chg.dec = 1500.0
		chg.grip = 1.5
		chg.breathe = 0.04
		chg.breathe_rate = 2.4
		chg.crouch = 0.4
		chg.has_look = false
		chg.mand_open = 0.4 + 0.1 * Rig.sn(t * 4.0, 1.0)
		lane_a = 0.0
		if t < T_RECOVER + 0.2:
			_charge_dust(dt, 0.4)
	else:
		# slow multi-step pivot toward the player, then a heavy walk
		var diff := wrapf(_angle_to_player() - chg.facing, -PI, PI)
		chg.goal_dir = to.normalized()
		chg.goal_speed = 40.0 if absf(diff) < 0.6 else 0.0
		chg.breathe = 0.02
		chg.mand_open = 0.3
	if lane_a > 0.01:
		lane.visible = true
		lane.position = chg.pos + lane_dir * 40.0
		lane.rotation = lane_dir.angle()
		lane.region_rect = Rect2(0, 0, 760.0 * 2.0, 192)
		lane.modulate = Color(1, 1, 1, lane_a)
	else:
		lane.visible = false
	chg.update(dt)
	c_pos = chg.pos
	c_face = chg.facing


func _charge_dust(dt: float, amount: float) -> void:
	dust_acc += dt
	var heading := Vector2.from_angle(chg.facing)
	while dust_acc > 0.04:
		dust_acc -= 0.04
		if chg.vel.length() < 120.0:
			continue
		var vd := chg.vel.normalized()
		for sgn in [-1.0, 1.0]:
			fx.dust_puff(chg.pos - vd * 70.0 + heading.rotated(PI / 2.0) * sgn * 40.0, 1.6 * amount + 0.4, -vd * 90.0 + heading.rotated(PI / 2.0) * sgn * 60.0, 0.6 * amount)


# ------------------------------------------------------------------------------------------ grenade
func _throw(dt: float) -> void:
	if t >= T_THROW and throw_t < 0.0 and grenade_state == 0:
		throw_t = t
		throw_from = p_pos
		# aim at the charger head
		throw_to = c_pos + Vector2.from_angle(c_face) * 55.0
		p_face = (throw_to - p_pos).angle()
	if throw_t >= 0.0:
		var u := t - throw_t
		if u < 0.09:
			pl.twist = lerpf(0.0, -0.9, u / 0.09)       # short wind-up
		elif u < 0.14:
			pl.twist = lerpf(-0.9, 0.7, (u - 0.09) / 0.05)  # very fast strike
			if grenade_state == 0:
				grenade_state = 1
				grenade.visible = true
		else:
			pl.twist = lerpf(pl.twist, 0.0, 1.0 - exp(-dt * 9.0))   # held recovery
		if u > 0.5:
			throw_t = -2.0
			pl.twist = 0.0


func _grenade(dt: float) -> void:
	if grenade_state != 1:
		return
	var fly := 0.56
	var start_t := throw_from_time()
	var u := clampf((t - start_t) / fly, 0.0, 1.0)
	var land := throw_to
	var p := throw_from.lerp(land, u)
	var h := sin(u * PI) * 70.0
	grenade.position = p + Vector2(0, -h * 0.35)
	grenade.scale = Vector2.ONE * (1.0 + sin(u * PI) * 0.55)
	grenade.rotation = u * 22.0
	grenade.set_meta("h", h)
	if u >= 1.0:
		grenade_state = 2
		grenade.visible = false
		_explode(land)


func throw_from_time() -> float:
	return T_THROW + 0.14


func _explode(pos: Vector2) -> void:
	exploded = true
	hitstop = HITSTOP
	shake = 20.0
	flash_a = 0.24
	fx.explosion(pos)
	kick_debris(pos, 300.0, 780.0)
	# hits the Charger: additive flinch (push + head jerk), brighten on the hit part, armour breaks open
	var away := (chg.pos - pos).normalized()
	if away.length() < 0.1:
		away = -Vector2.from_angle(chg.facing)
	chg.hit(away, 300.0, chg.pos + Vector2.from_angle(chg.facing) * 40.0, 190.0, 0.7)
	c_dmg = 1
	chg.set_damage(1)
	_plate_burst(c_pos + Vector2.from_angle(c_face) * 40.0, away, 12)
	for i in 14:
		var a := rng.randf() * TAU
		fx.add_p({"tex": "droplet", "pos": c_pos + Vector2.from_angle(a) * 30.0, "vel": Vector2.from_angle(a) * rng.randf_range(120, 420), "life": rng.randf_range(0.3, 0.7),
			"s0": rng.randf_range(0.9, 1.8), "s1": 0.6, "a0": 1.0, "a1": 0.0, "hold": 0.6, "drag": 3.0})
	fx.decal("goo1", c_pos + Vector2(30, 20), 0.5, 1.7, 0.9, 0.2)
	fx.decal("goo2", c_pos + Vector2(-40, -26), 2.5, 2.0, 0.9, 0.2)
	# finishing shots start after the blast
	shots_post = []
	for i in 7:
		shots_post.append(t + 0.52 + 0.17 * i)
	shots_post_i = 0
	shots_pre_i = 99


# ------------------------------------------------------------------------------------------ pickup
func _pickup(dt: float) -> void:
	if not c_dead:
		return
	var dtm := t - c_dead_t
	if pickup_state == 0 and dtm > 0.85:
		pickup_state = 1
		pickup_t = t
		pickup_from = c_pos
		pickup_pos = (c_pos + Vector2(170, -70)).clamp(Vector2(200, 160), Vector2(1100, 600))
		pickup.visible = true
	if pickup_state == 1:
		var u := clampf((t - pickup_t) / 0.55, 0.0, 1.0)
		var h := sin(u * PI) * 90.0
		pickup.position = pickup_from.lerp(pickup_pos, u) + Vector2(0, -h)
		pickup.rotation = u * 9.0
		pickup.scale = Vector2.ONE * (1.0 + sin(u * PI) * 0.5)
		if u >= 1.0:
			pickup_state = 2
			pickup.rotation = 0.35
			pickup.scale = Vector2.ONE
			fx.dust_puff(pickup_pos, 1.4)
			fx.add_p({"tex": "ring", "pos": pickup_pos, "s0": 0.1, "s1": 0.8, "a0": 0.7, "a1": 0.0, "life": 0.3, "add": true,
				"tint": Color(0.5, 0.75, 1.0)})
			shake = maxf(shake, 2.0)
			p_collect = true
			# player walks over to grab it
	if pickup_state == 2:
		var pulse := 0.5 + 0.5 * sin(t * 6.0)
		pickup_glow.position = pickup_pos
		pickup_glow.modulate.a = 0.28 + 0.22 * pulse
		pickup.position = pickup_pos + Vector2(0, -1.5 * pulse)
		pickup.scale = Vector2.ONE * (1.0 + 0.04 * pulse)
		# player walks to it (snappy)
		var to := (pickup_pos - Vector2(40, 0)) - p_pos
		if to.length() > 8.0 and t > pickup_t + 0.7:
			var v := to.normalized() * 300.0
			p_pos += v * dt
			p_face = v.angle()
			pl.position = p_pos
			pl.facing = p_face
			pl.update(dt, v)
		elif t > pickup_t + 0.7 and pickup.visible and to.length() <= 8.0:
			pickup.visible = false
			pickup_glow.modulate.a = 0.0
			fx.add_p({"tex": "flash", "pos": pickup_pos, "s0": 1.4, "s1": 2.4, "a0": 0.9, "a1": 0.0, "life": 0.12, "add": true,
				"tint": Color(1.0, 0.9, 0.5)})
			for i in 10:
				fx.add_p({"tex": "spark", "pos": pickup_pos, "vel": Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(100, 300), "life": 0.4,
					"s0": 1.0, "s1": 0.3, "a0": 1.0, "a1": 0.0, "drag": 3.0, "orient": true, "tint": Color(0.7, 0.9, 1.0)})
