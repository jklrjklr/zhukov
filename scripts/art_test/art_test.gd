extends Node2D
## ART TEST SCENE: scripted, deterministic ~14.8 s showcase (30 fps fixed step).
##  1. ash wasteland   2. player vs scavenger pack   3. Charger telegraph / charge / dive / recovery / turn
##  4. grenade explosion on the Charger, armor cracks, finishing shots, heavy death, pickup.
## Authored in a 1280x720 layout; the world node scales itself to the window height (1080p -> x1.5).

const Lib = preload("res://scripts/art_test/art_lib.gd")
const Bug = preload("res://scripts/art_test/bug_rig.gd")
const Pl = preload("res://scripts/art_test/player_rig.gd")
const Fx = preload("res://scripts/art_test/fx.gd")

const FPS := 30.0
const TOTAL_FRAMES := 444
const ARENA := Vector2(1280, 720)
const CAM_ZOOM := 1.2
const CAM_CENTER := Vector2(530, 405)

var frame := 0
var t := 0.0
var hitstop := 0
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
const SCAV_SPAWN := [
	[1.20, Vector2(1340, 330), 0.0], [1.40, Vector2(1350, 480), 0.31], [1.55, Vector2(1340, 570), 0.57],
	[1.80, Vector2(1360, 400), 0.83], [2.15, Vector2(1335, 250), 0.12], [2.65, Vector2(-70, 130), 0.44],
]

# charger
var chg: Node2D
var c_pos := Vector2(1400, 400)
var c_face := PI
var c_vel := Vector2.ZERO
var c_phase := "wait"
var c_w := 0.0
var c_dmg := 0
var c_dead := false
var c_dead_t := 0.0
var c_kb := Vector2.ZERO
var lane_dir := Vector2.LEFT
var lane: Sprite2D
var lane_a := 0.0
var c_last_dust := 0.0
var c_hits := 0
var c_goo_pool_t := -1.0
var c_pool_pos := Vector2.ZERO
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
		actors.add_child(b)
		b.setup("scav", shadow_layer, Vector2(5, 6), 2.0)
		b.step_dist_f = 0.22
		b.step_time = 0.075
		b.gait_lock = false
		b.visible = false
		b.glow_phase = e[2] * 9.0
		var sp: Vector2 = e[1]
		b.position = sp
		b.facing = (Vector2(480, 440) - sp).angle()
		b.reset_feet()
		var d := {"rig": b, "pos": sp, "spawn": e[0], "hp": 2, "state": "run", "kb": Vector2.ZERO, "ph": e[2], "dead_t": 0.0,
			"speed": 250.0 + e[2] * 90.0, "f": b.facing, "hit_dir": Vector2.RIGHT}
		scavs.append(d)
		b.shadow_off = Vector2(5, 6)
		b.visible = false
		_set_shadows_visible(b, false)
	chg = Bug.new()
	chg.z_index = 10
	actors.add_child(chg)
	chg.setup("chg", shadow_layer, Vector2(12, 14), 5.0)
	chg.step_dist_f = 0.36
	chg.step_time = 0.3
	chg.position = c_pos
	chg.facing = c_face
	chg.reset_feet()
	chg.visible = false
	chg.stepped.connect(_on_chg_step)
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
func _process(_d: float) -> void:
	var dt := 1.0 / FPS
	var sdt := dt
	if hitstop > 0:
		hitstop -= 1
		sdt = 0.0
	frame += 1
	if sdt > 0.0:
		t += sdt
		_step(sdt)
	_always(dt)
	if frame >= TOTAL_FRAMES:
		get_tree().quit()


func _always(dt: float) -> void:
	# camera shake (deterministic hash noise), decays in real time even during hit-stop
	var n1 := fposmod(sin(frame * 12.9898) * 43758.5453, 1.0) * 2.0 - 1.0
	var n2 := fposmod(sin(frame * 78.233 + 1.7) * 43758.5453, 1.0) * 2.0 - 1.0
	var sc := world.scale.x
	var base := get_viewport_rect().size * 0.5 - CAM_CENTER * sc
	world.position = base + Vector2(n1, n2) * shake * sc
	shake = maxf(0.0, shake - (shake * 9.0 + 4.0) * dt)
	flash_a = maxf(0.0, flash_a - 0.16)
	flash_rect.color.a = flash_a
	var fa := clampf(1.0 - frame / 14.0, 0.0, 1.0)
	var fo := clampf((frame - (TOTAL_FRAMES - 22)) / 20.0, 0.0, 1.0)
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
	var tp: Vector2 = s["pos"] + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
	_fire_visuals(tp)
	var dir := (tp - p_pos).normalized()
	s["hp"] -= 1
	s["rig"].flash(1 if s["hp"] > 0 else 2)
	s["kb"] += dir * 150.0
	s["hit_dir"] = dir
	s["rig"].kick = dir * 3.0
	if s["hp"] <= 0:
		_kill_scav(s, tp, dir)
	else:
		fx.goo_hit(tp, dir, 0.8)


func _kill_scav(s: Dictionary, tp: Vector2, dir: Vector2) -> void:
	s["state"] = "dying"
	s["dead_t"] = 0.0
	s["kb"] = dir * 430.0
	fx.goo_hit(tp, dir, 1.3)
	for i in 7:
		var a := dir.angle() + rng.randf_range(-1.1, 1.1)
		fx.add_p({"tex": "droplet", "pos": tp, "vel": Vector2.from_angle(a) * rng.randf_range(100, 380), "life": rng.randf_range(0.3, 0.6),
			"s0": rng.randf_range(0.8, 1.6), "s1": 0.6, "a0": 1.0, "a1": 0.0, "hold": 0.6, "drag": 3.5})
	# lasting goo pool under the corpse
	fx.decal("goo%d" % rng.randi_range(0, 2), s["pos"] + dir * 14.0, rng.randf() * TAU, rng.randf_range(1.0, 1.4), 0.95, 0.25)
	var rig: Node2D = s["rig"]
	rig.dead = true
	rig.mand_open = 0.9
	rig.z_index = -50


func _shoot_charger(post: bool) -> void:
	c_hits += 1
	var dir := (c_pos - p_pos).normalized()
	var perp := dir.rotated(PI / 2.0)
	var hp := c_pos - dir * 70.0 + perp * rng.randf_range(-20, 20)
	hp = c_pos + Vector2.from_angle(c_face) * 72.0 + perp * rng.randf_range(-22, 22)
	_fire_visuals(hp)
	chg.flash(1)
	chg.kick = dir * 3.0
	if not post:
		fx.armor_hit(hp, dir)
		shake = maxf(shake, 1.5)
		return
	var idx := shots_post_i
	var last := idx >= shots_post.size()
	if not last:
		fx.goo_hit(hp, dir, 1.0 + 0.05 * idx)
		fx.armor_hit(hp + dir * 6.0, dir) if idx <= 1 else null
		c_kb += dir * 22.0
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
	hitstop = 2
	shake = 12.0
	c_kb = dir * 520.0
	fx.goo_hit(hp, dir, 2.0)
	fx.goo_hit(hp + dir.rotated(0.6) * 10.0, dir, 1.6)
	for i in 22:
		var a := dir.angle() + rng.randf_range(-1.3, 1.3)
		fx.add_p({"tex": "droplet", "pos": hp, "vel": Vector2.from_angle(a) * rng.randf_range(160, 640), "life": rng.randf_range(0.35, 0.8),
			"s0": rng.randf_range(1.0, 2.4), "s1": 0.7, "a0": 1.0, "a1": 0.0, "hold": 0.6, "drag": 3.0})
	_plate_burst(hp, dir, 6)
	chg.dead = true
	chg.mand_open = 1.0
	chg.z_index = -50
	c_pool_pos = c_pos + dir * 60.0
	c_goo_pool_t = t
	pool_sprite = Lib.flat("goo_big")
	pool_sprite.scale = Vector2.ONE * 0.05
	pool_sprite.position = c_pool_pos
	pool_sprite.rotation = 0.6
	fx.decal_layer.add_child(pool_sprite)
	pickup_state = 0
	pickup_t = 0.0


# ------------------------------------------------------------------------------------------ scavengers
func _scav(s: Dictionary, dt: float) -> void:
	var rig: Node2D = s["rig"]
	if t < s["spawn"]:
		return
	rig.visible = true
	_set_shadows_visible(rig, true)
	var pos: Vector2 = s["pos"]
	var kb: Vector2 = s["kb"]
	var v := Vector2.ZERO
	if s["state"] == "run":
		var to := (p_pos - pos)
		var dist := to.length()
		var dir := to.normalized()
		var ph: float = s["ph"]
		var burst := fposmod(t * 3.1 + ph * 2.7, 1.0) < 0.6
		var sp: float = s["speed"] * (1.55 if burst else 0.22)
		var zig := sin(t * 8.5 + ph * 17.0) * 0.6
		v = (dir + dir.rotated(PI / 2.0) * zig).normalized() * sp
		if dist < 60.0:
			v = Vector2.ZERO
		var tf: float = v.angle() if v.length() > 1.0 else s["f"]
		# twitch: quantised yaw jitter (12 Hz) on top of snappy turning
		var tw := sin(floor(t * 12.0) * 12.9 + ph * 40.0) * 0.32
		s["f"] = lerp_angle(s["f"], tf, 1.0 - exp(-dt * 30.0))
		rig.facing = s["f"] + tw * (1.0 if burst else 1.8)
		rig.head_rel = sin(floor(t * 14.0) * 7.7 + ph * 9.0) * 0.28
		rig.mand_open = 0.28 + 0.3 * absf(sin(t * 22.0 + ph * 5.0))
		rig.step_time = 0.07
		pos += (v + kb) * dt
	else:
		s["dead_t"] += dt
		var dtm: float = s["dead_t"]
		rig.crumple = minf(1.0, dtm / 0.2)
		rig.facing += (s["hit_dir"].angle() - rig.facing) * 0.0
		rig.head_rel = lerpf(rig.head_rel, 0.5, 0.2)
		pos += kb * dt
		var tone := lerpf(1.0, 0.58, clampf(dtm / 0.5, 0.0, 1.0))
		rig.modulate = Color(tone, tone * 0.96, tone * 0.94, 1.0)
		rig.abd_rot = 0.35 * clampf(dtm / 0.2, 0.0, 1.0)
	s["kb"] = kb * exp(-9.0 * dt)
	s["pos"] = pos
	rig.position = pos
	rig.update(dt, v)


# ------------------------------------------------------------------------------------------ charger
func _on_chg_step(pos: Vector2, _heavy: bool) -> void:
	if c_dead:
		return
	shake = maxf(shake, 1.6)
	fx.dust_puff(pos, 1.1, Vector2.ZERO, 0.5)
	fx.add_p({"tex": "pock", "pos": pos, "s0": 1.6, "s1": 1.8, "a0": 0.55, "a1": 0.55, "life": 0.01, "persist": true, "layer": fx.decal_layer,
		"rot": rng.randf() * TAU, "tint": Color(0.7, 0.7, 0.72)})


func _angle_to_player() -> float:
	return (p_pos - c_pos).angle()


func _charger(dt: float) -> void:
	var spawn_t := 4.2
	if t < spawn_t:
		return
	chg.visible = true
	_set_shadows_visible(chg, true)
	var vel := Vector2.ZERO
	var heading := Vector2.from_angle(c_face)
	chg.shadow_off = Vector2(12, 14)
	if c_dead:
		var dtm := t - c_dead_t
		c_pos += c_kb * dt
		c_kb *= exp(-5.5 * dt)
		chg.crumple = clampf(dtm / 0.55, 0.0, 1.0)
		chg.head_rel = lerpf(chg.head_rel, 0.35, 1.0 - exp(-dt * 6.0))
		chg.head_sx = lerpf(chg.head_sx, 0.72, 1.0 - exp(-dt * 6.0))
		chg.thorax_off = lerpf(chg.thorax_off, -4.0, 1.0 - exp(-dt * 5.0))
		chg.abd_rot = lerpf(chg.abd_rot, 0.22, 1.0 - exp(-dt * 4.0))
		var tone := lerpf(1.0, 0.6, clampf((dtm - 0.2) / 0.9, 0.0, 1.0))
		chg.modulate = Color(tone, tone * 0.95, tone * 0.93, 1.0)
		chg.breathe = 0.0
		if pool_sprite != null:
			var u := clampf((t - c_goo_pool_t) / 0.9, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - u, 3.0)
			pool_sprite.scale = Vector2.ONE * lerpf(0.05, 0.62, e)
		chg.position = c_pos
		chg.update(dt, c_kb)
		return
	if t < T_WINDUP:
		# slow heavy approach: head low-ish bob, lagging turn
		var want := _angle_to_player()
		c_w = lerpf(c_w, clampf(wrapf(want - c_face, -PI, PI) * 1.5, -0.7, 0.7), 1.0 - exp(-dt * 3.0))
		c_face += c_w * dt
		heading = Vector2.from_angle(c_face)
		vel = heading * 150.0
		c_pos += vel * dt
		chg.step_time = 0.34
		chg.head_rel = lerpf(chg.head_rel, sin(t * 2.4) * 0.07 + c_w * 0.5, 1.0 - exp(-dt * 5.0))
		chg.mand_open = 0.2 + 0.08 * sin(t * 3.0)
		chg.breathe = 0.015
	elif t < T_CHARGE:
		var u := (t - T_WINDUP) / (T_CHARGE - T_WINDUP)
		if t >= T_WINDUP + 0.1 and lane_dir == Vector2.LEFT:
			pass
		if (t - T_WINDUP) < 0.12:
			var want := _angle_to_player()
			c_face = lerp_angle(c_face, want, 1.0 - exp(-dt * 7.0))
			lane_dir = Vector2.from_angle(want)
		else:
			c_face = lerp_angle(c_face, lane_dir.angle(), 1.0 - exp(-dt * 12.0))
		# wind-up: short, exaggerated crouch with head down and mandibles flared
		var ck := clampf((t - T_WINDUP) / 0.22, 0.0, 1.0)
		var ke := ck * ck * (3.0 - 2.0 * ck)
		chg.thorax_off = lerpf(0.0, -16.0, ke)
		chg.head_sx = lerpf(1.0, 0.78, ke)
		chg.head_rel = lerpf(chg.head_rel, 0.0, 0.3)
		chg.mand_open = lerpf(0.2, 0.78, ke)
		chg.crumple = 0.0
		var trem := clampf((u - 0.45) / 0.55, 0.0, 1.0)
		chg.kick = Vector2(sin(t * 90.0), cos(t * 77.0)) * 1.8 * trem
		chg.abd_rot = sin(t * 60.0) * 0.06 * trem
		shake = maxf(shake, 1.2 * trem)
		lane_a = clampf((t - (T_WINDUP + 0.05)) / 0.08, 0.0, 1.0)
		if u > 0.75:
			lane_a *= 0.65 + 0.35 * (1.0 if int(t * 30.0) % 2 == 0 else 0.0)
		heading = Vector2.from_angle(c_face)
		chg.step_time = 0.2
	elif t < T_BRAKE:
		var u := (t - T_CHARGE) / 0.07
		var spd := 820.0 * clampf(u, 0.0, 1.0)
		vel = lane_dir * spd
		c_pos += vel * dt
		chg.step_time = 0.075
		chg.step_dist_f = 0.2
		chg.thorax_off = lerpf(chg.thorax_off, 6.0, 1.0 - exp(-dt * 25.0))
		chg.head_sx = lerpf(chg.head_sx, 0.84, 1.0 - exp(-dt * 20.0))
		chg.mand_open = lerpf(chg.mand_open, 0.5, 1.0 - exp(-dt * 20.0))
		chg.kick = Vector2.ZERO
		shake = maxf(shake, 3.4)
		lane_a = lerpf(lane_a, 0.0, 0.5) if t > T_CHARGE + 0.08 else lane_a
		if t - c_last_dust > 0.035:
			c_last_dust = t
			for sgn in [-1.0, 1.0]:
				fx.dust_puff(c_pos - lane_dir * 70.0 + lane_dir.rotated(PI / 2.0) * sgn * 40.0, 1.6, -lane_dir * 90.0 + lane_dir.rotated(PI / 2.0) * sgn * 60.0, 0.6)
		kick_debris(c_pos, 120.0, 520.0)
		# charge shreds anything near the lane (visual only)
	elif t < T_RECOVER:
		var u := (t - T_BRAKE) / (T_RECOVER - T_BRAKE)
		var spd := 820.0 * pow(1.0 - u, 2.0)
		vel = lane_dir * spd
		c_pos += vel * dt
		chg.step_time = 0.1
		chg.step_dist_f = 0.2
		if t - c_last_dust > 0.04:
			c_last_dust = t
			fx.dust_puff(c_pos + lane_dir * 40.0 + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40)), 1.8, lane_dir * 120.0, 0.6)
		shake = maxf(shake, 2.0 * (1.0 - u))
		lane_a = 0.0
		chg.head_sx = lerpf(chg.head_sx, 0.9, 1.0 - exp(-dt * 8.0))
		chg.thorax_off = lerpf(chg.thorax_off, 0.0, 1.0 - exp(-dt * 6.0))
		kick_debris(c_pos, 100.0, 300.0)
	elif t < T_TURN:
		# held recovery: planted, heaving, head hanging low; no movement
		chg.step_dist_f = 0.36
		chg.step_time = 0.34
		chg.breathe = 0.035
		chg.head_rel = lerpf(chg.head_rel, 0.1, 1.0 - exp(-dt * 6.0))
		chg.head_sx = lerpf(chg.head_sx, 0.88, 1.0 - exp(-dt * 6.0))
		chg.mand_open = 0.4 + 0.12 * sin(t * 12.0)
		lane_a = 0.0
	else:
		# slow lagging turn: head leads, body follows with limited angular speed; feet step in place
		chg.step_dist_f = 0.3
		chg.step_time = 0.3
		var want := _angle_to_player()
		var diff := wrapf(want - c_face, -PI, PI)
		var tgt_w := clampf(diff * 1.6, -1.25, 1.25)
		c_w = move_toward(c_w, tgt_w, 2.6 * dt)
		c_face += c_w * dt
		var head_target := clampf(wrapf(want - c_face, -PI, PI), -0.7, 0.7)
		chg.head_rel = lerpf(chg.head_rel, head_target, 1.0 - exp(-dt * 7.0))
		chg.head_sx = lerpf(chg.head_sx, 1.0, 1.0 - exp(-dt * 4.0))
		chg.mand_open = lerpf(chg.mand_open, 0.3, 1.0 - exp(-dt * 4.0))
		chg.breathe = 0.02
		var adv := 36.0 if absf(diff) < 0.5 else 0.0
		vel = Vector2.from_angle(c_face) * adv
		c_pos += vel * dt
	# stagger knockback from hits
	c_pos += c_kb * dt
	c_kb *= exp(-8.0 * dt)
	# abdomen sway while walking
	if t < T_WINDUP:
		chg.abd_rot = sin(t * 3.0) * 0.07
	elif t > T_RECOVER:
		chg.abd_rot = lerpf(chg.abd_rot, 0.0, 0.1)
	chg.position = c_pos
	chg.facing = c_face
	if lane_a > 0.01:
		lane.visible = true
		var ln := 760.0
		var origin := c_pos + lane_dir * 40.0
		lane.position = origin
		lane.rotation = lane_dir.angle()
		lane.region_rect = Rect2(0, 0, ln * 2.0, 192)
		lane.modulate = Color(1, 1, 1, lane_a)
	else:
		lane.visible = false
	chg.update(dt, vel)


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
	hitstop = 2
	shake = 20.0
	flash_a = 0.24
	fx.explosion(pos)
	kick_debris(pos, 300.0, 780.0)
	# hits the Charger: flash, knockback away from the blast, armour breaks open
	var away := (c_pos - pos).normalized()
	if away.length() < 0.1:
		away = -Vector2.from_angle(c_face)
	c_kb += away * 300.0
	chg.flash(3)
	c_dmg = 1
	chg.set_damage(1)
	chg.head_rel = 0.5
	chg.kick = away * 10.0
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
