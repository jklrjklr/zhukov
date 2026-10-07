extends Node2D
## Tiny deterministic sprite-particle / decal system for the art test.
## Every entry is a Sprite2D driven by a dictionary; `persist` entries stay (decals) after their ramp ends.

const Lib = preload("res://scripts/art_test/art_lib.gd")

var rng := RandomNumberGenerator.new()
var decal_layer: Node2D
var under_layer: Node2D
var top_layer: Node2D
var items: Array = []


func _init() -> void:
	rng.seed = 424242


func rf(a: float, b: float) -> float:
	return rng.randf_range(a, b)


## o keys: tex, pos, vel, life, s0, s1, a0, a1, rot, rot_v, drag, add, delay, layer, orient, tint, hold, persist, sx (extra x stretch),
## ease_out (bool), flat (bool: use texture as centred flat sprite; false = pivot at left for streaks)
func add_p(o: Dictionary) -> Sprite2D:
	var s := Lib.flat(o["tex"])
	if o.get("left", false):
		s.centered = false
		s.offset = Vector2(0, -s.texture.get_height() * 0.5)
	if o.get("add", false):
		s.material = Lib.add_mat()
	s.position = o["pos"]
	s.rotation = o.get("rot", 0.0)
	var layer: Node2D = o.get("layer", top_layer)
	layer.add_child(s)
	var d := {
		"n": s, "vel": o.get("vel", Vector2.ZERO), "life": o.get("life", 0.5), "age": -o.get("delay", 0.0),
		"s0": o.get("s0", 1.0), "s1": o.get("s1", 1.0), "a0": o.get("a0", 1.0), "a1": o.get("a1", 0.0),
		"rot_v": o.get("rot_v", 0.0), "drag": o.get("drag", 0.0), "orient": o.get("orient", false),
		"tint": o.get("tint", Color.WHITE), "hold": o.get("hold", 0.0), "persist": o.get("persist", false),
		"sx": o.get("sx", 1.0), "ease_out": o.get("ease_out", true), "base_scale": s.scale.x,
	}
	s.visible = d["age"] >= 0.0
	_apply(d, 0.0)
	items.append(d)
	return s


func _apply(d: Dictionary, u: float) -> void:
	var s: Sprite2D = d["n"]
	var e: float = (1.0 - (1.0 - u) * (1.0 - u)) if d["ease_out"] else u
	var sc: float = lerpf(d["s0"], d["s1"], e) * d["base_scale"]
	s.scale = Vector2(sc * d["sx"], sc)
	var fu := 0.0
	if u > d["hold"]:
		fu = (u - d["hold"]) / maxf(0.001, 1.0 - d["hold"])
	var c: Color = d["tint"]
	c.a = lerpf(d["a0"], d["a1"], fu) * c.a
	s.modulate = c


func update(dt: float) -> void:
	var i := 0
	while i < items.size():
		var d: Dictionary = items[i]
		var s: Sprite2D = d["n"]
		d["age"] += dt
		if d["age"] < 0.0:
			i += 1
			continue
		s.visible = true
		var u := clampf(d["age"] / d["life"], 0.0, 1.0)
		if u >= 1.0 and not d["persist"]:
			s.queue_free()
			items.remove_at(i)
			continue
		var v: Vector2 = d["vel"]
		s.position += v * dt
		d["vel"] = v * exp(-d["drag"] * dt)
		s.rotation += d["rot_v"] * dt
		if d["orient"] and v.length() > 1.0:
			s.rotation = v.angle()
		_apply(d, u)
		if u >= 1.0 and d["persist"]:
			items.remove_at(i)
			continue
		i += 1


func decal(tex: String, pos: Vector2, rot: float, scale: float, alpha: float, grow: float = 0.1, tint: Color = Color.WHITE) -> void:
	add_p({"tex": tex, "pos": pos, "rot": rot, "s0": scale * 0.25, "s1": scale, "a0": alpha, "a1": alpha,
		"life": maxf(grow, 0.001), "layer": decal_layer, "persist": true, "tint": tint})


# ----------------------------------------------------------------- composite effects
func muzzle_flash(pos: Vector2, ang: float) -> void:
	add_p({"tex": "muzzle", "pos": pos, "rot": ang, "left": false, "s0": 1.1, "s1": 0.8, "a0": 1.0, "a1": 1.0,
		"life": 0.066, "add": false})
	add_p({"tex": "glow", "pos": pos, "s0": 2.2, "s1": 3.0, "a0": 0.5, "a1": 0.0, "life": 0.08, "add": true,
		"tint": Color(1.0, 0.8, 0.4)})


func tracer(a: Vector2, b: Vector2) -> void:
	var d := b - a
	var ln := d.length()
	var s := add_p({"tex": "tracer", "pos": a, "rot": d.angle(), "left": true, "s0": 1.0, "s1": 1.0, "a0": 1.0, "a1": 0.0,
		"life": 0.1, "hold": 0.25, "add": true})
	s.scale = Vector2(ln / 128.0, 0.5)
	items[items.size() - 1]["base_scale"] = 1.0
	items[items.size() - 1]["sx"] = 1.0
	items[items.size() - 1]["s0"] = 1.0
	# manual non-uniform scale: keep via custom sx/base_scale
	items[items.size() - 1]["base_scale"] = 0.5
	items[items.size() - 1]["sx"] = ln / 128.0 / 0.5


func goo_hit(pos: Vector2, dir: Vector2, power: float = 1.0) -> void:
	# 1) flash
	add_p({"tex": "flash", "pos": pos, "s0": 0.55 * power, "s1": 0.9 * power, "a0": 1.0, "a1": 0.0, "life": 0.066, "add": true,
		"tint": Color(1.0, 0.9, 0.6)})
	# 2) goo particles
	var n := int(7 * power)
	for i in n:
		var a := dir.angle() + rf(-0.7, 0.7)
		var sp := rf(160.0, 460.0) * power
		add_p({"tex": "droplet", "pos": pos, "vel": Vector2.from_angle(a) * sp, "life": rf(0.22, 0.5), "s0": rf(0.7, 1.4) * power,
			"s1": 0.5, "a0": 1.0, "a1": 0.0, "hold": 0.6, "drag": 4.0, "orient": false})
	# 3) lasting decal
	var tex := "goo%d" % rng.randi_range(0, 3)
	decal(tex, pos + dir * rf(6.0, 16.0), rf(0, TAU), rf(0.55, 0.8) * power, 0.92, 0.07)


func armor_hit(pos: Vector2, dir: Vector2) -> void:
	add_p({"tex": "flash", "pos": pos, "s0": 0.5, "s1": 0.8, "a0": 1.0, "a1": 0.0, "life": 0.066, "add": true})
	for i in 7:
		var a := (-dir).angle() + rf(-1.3, 1.3)
		add_p({"tex": "spark", "pos": pos, "vel": Vector2.from_angle(a) * rf(240.0, 640.0), "life": rf(0.1, 0.28), "s0": 0.9,
			"s1": 0.3, "a0": 1.0, "a1": 0.0, "drag": 3.0, "orient": true})
	var cp := Vector2.from_angle((-dir).angle() + rf(-0.9, 0.9)) * rf(120.0, 280.0)
	add_p({"tex": "chip_plate%d" % rng.randi_range(0, 1), "pos": pos, "vel": cp, "life": 0.7, "s0": 0.7, "s1": 0.5, "a0": 1.0,
		"a1": 0.0, "hold": 0.6, "drag": 3.0, "rot_v": rf(-18, 18), "rot": rf(0, TAU), "layer": under_layer})
	decal("pock", pos + dir * 30.0 + Vector2(rf(-14, 14), rf(-14, 14)), rf(0, TAU), 0.9, 0.7, 0.04)


func dust_puff(pos: Vector2, size: float = 1.0, vel: Vector2 = Vector2.ZERO, alpha: float = 0.55) -> void:
	add_p({"tex": "dust", "pos": pos, "vel": vel + Vector2(rf(-14, 14), rf(-14, 14)), "life": rf(0.5, 0.8), "s0": 0.5 * size,
		"s1": 1.6 * size, "a0": alpha, "a1": 0.0, "hold": 0.1, "drag": 2.5, "rot": rf(0, TAU), "rot_v": rf(-1, 1),
		"layer": under_layer})


func explosion(pos: Vector2) -> void:
	# white flash
	add_p({"tex": "flash", "pos": pos, "s0": 4.5, "s1": 6.0, "a0": 1.0, "a1": 0.0, "life": 0.1, "add": true})
	add_p({"tex": "glow", "pos": pos, "s0": 11.0, "s1": 16.0, "a0": 0.75, "a1": 0.0, "life": 0.55, "add": true,
		"tint": Color(1.0, 0.55, 0.15), "hold": 0.2})
	# fireball
	for i in 5:
		var off := Vector2.from_angle(rf(0, TAU)) * rf(0, 34.0)
		add_p({"tex": "fireball%d" % (i % 2), "pos": pos + off, "vel": off * 2.0, "s0": 0.7, "s1": rf(3.0, 4.2), "a0": 1.0, "a1": 0.0,
			"life": rf(0.5, 0.7), "hold": 0.45, "rot": rf(0, TAU), "rot_v": rf(-1.5, 1.5), "drag": 3.0})
	# dark smoke
	for i in 11:
		var a := rf(0, TAU)
		var off := Vector2.from_angle(a) * rf(10.0, 46.0)
		add_p({"tex": "smoke%d" % (i % 3), "pos": pos + off, "vel": Vector2.from_angle(a) * rf(50.0, 150.0) + Vector2(14, -10),
			"s0": 0.7, "s1": rf(2.4, 3.6), "a0": 0.85, "a1": 0.0, "life": rf(1.1, 1.9), "hold": 0.3, "drag": 1.8,
			"rot": rf(0, TAU), "rot_v": rf(-0.5, 0.5), "delay": rf(0.06, 0.28), "layer": top_layer})
	# debris
	for i in 18:
		var a := rf(0, TAU)
		add_p({"tex": "chip_rock%d" % (i % 3), "pos": pos, "vel": Vector2.from_angle(a) * rf(280.0, 760.0), "s0": rf(1.0, 1.8), "s1": 0.9,
			"a0": 1.0, "a1": 0.0, "life": rf(1.0, 1.7), "hold": 0.7, "drag": 2.4, "rot": rf(0, TAU), "rot_v": rf(-16, 16)})
	for i in 26:
		add_p({"tex": "spark", "pos": pos, "vel": Vector2.from_angle(rf(0, TAU)) * rf(380.0, 980.0), "s0": 1.1, "s1": 0.3, "a0": 1.0,
			"a1": 0.0, "life": rf(0.25, 0.6), "drag": 3.2, "orient": true})
	# shockwave
	add_p({"tex": "ring", "pos": pos, "s0": 0.3, "s1": 3.6, "a0": 0.85, "a1": 0.0, "life": 0.38, "add": true, "hold": 0.1})
	# dust ring rolling outward
	for i in 10:
		var a := TAU * i / 10.0 + rf(-0.2, 0.2)
		dust_puff(pos + Vector2.from_angle(a) * 40.0, 1.8, Vector2.from_angle(a) * rf(240.0, 420.0), 0.7)
	# scorch decal (lasting)
	decal("scorch", pos, rf(0, TAU), 1.25, 0.96, 0.1)
	decal("hollow", pos, 0.0, 3.2, 0.5, 0.2)
