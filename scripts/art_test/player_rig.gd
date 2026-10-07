extends Node2D
## Helldiver cutout rig: torso, helmet, rifle+arms, cape (lags turns), two boots.
## Snappy: facing is set instantly; only the cape lags.

const Lib = preload("res://scripts/art_test/art_lib.gd")

var body: Node2D
var torso: Node2D
var head: Node2D
var gun: Node2D
var cape: Node2D
var boots: Array[Node2D] = []
var muzzle: Marker2D

var facing := 0.0
var squash := Vector2.ONE
var recoil := 0.0
var walk_phase := 0.0
var speed := 0.0
var twist := 0.0          # extra torso/gun twist (throw)
var gun_drop := 0.0       # gun lowered/raised (radians)
var flash_frames := 0
var _cape_w := 0.0
var _cape_init := false
var _shadows: Array = []
var shadow_off := Vector2(5, 6)
var t := 0.0


func setup(shadow_layer: Node2D) -> void:
	body = Node2D.new()
	add_child(body)
	for s in [-1.0, 1.0]:
		var b := _mk("pl_boot", body, shadow_layer)
		b.position = Vector2(0, s * 5.0)
		boots.append(b)
	cape = _mk("pl_cape", body, shadow_layer)
	cape.position = Vector2(-8, 0)
	torso = _mk("pl_torso", body, shadow_layer)
	gun = _mk("pl_gun", body, shadow_layer)
	head = _mk("pl_head", body, shadow_layer)
	head.position = Vector2(1, 0)
	muzzle = Marker2D.new()
	muzzle.position = Vector2(Lib.layout["meta"]["player"]["muzzle"][0], 0)
	gun.add_child(muzzle)


func _mk(n: String, parent: Node2D, shadow_layer: Node2D) -> Node2D:
	var p := Lib.part(n)
	parent.add_child(p)
	var h := Lib.shadow_for(p, 2.0)
	shadow_layer.add_child(h)
	_shadows.append([p, h])
	return p


func flash(frames: int = 2) -> void:
	flash_frames = frames


func update(dt: float, vel: Vector2) -> void:
	t += dt
	body.rotation = facing
	body.scale = squash
	speed = vel.length()
	walk_phase += speed * dt * 0.16
	# boots alternate along the facing axis, sized by speed
	var amp := clampf(speed / 300.0, 0.0, 1.0) * 6.5
	boots[0].position = Vector2(sin(walk_phase) * amp, -5.0)
	boots[1].position = Vector2(-sin(walk_phase) * amp, 5.0)
	torso.rotation = twist * 0.5
	gun.rotation = twist + gun_drop
	gun.position = Vector2(-recoil, 0)
	torso.position = Vector2(-recoil * 0.35, 0)
	head.rotation = twist * 0.3
	# cape: world-space lag behind the facing direction
	var target := facing + PI
	if not _cape_init:
		_cape_w = target
		_cape_init = true
	var move_bias := 0.0
	if speed > 40.0:
		move_bias = clampf(-0.12 * speed / 300.0, -0.2, 0.0)
	_cape_w = lerp_angle(_cape_w, target, 1.0 - exp(-dt * 9.0))
	cape.rotation = wrapf(_cape_w - target, -PI, PI) + sin(t * 9.0 + walk_phase) * 0.05 * clampf(speed / 200.0, 0.0, 1.0)
	cape.scale = Vector2(1.0 + clampf(speed / 300.0, 0.0, 1.0) * 0.1, 1.0 + move_bias)
	for p in [torso, gun, head, cape] + boots:
		var spr: Sprite2D = p.get_meta("spr")
		spr.material = Lib.flash_mat() if flash_frames > 0 else Lib.lit_mat(p.get_meta("part"))
	if flash_frames > 0:
		flash_frames -= 1


func sync_shadows() -> void:
	for pair in _shadows:
		var xf: Transform2D = pair[0].global_transform
		xf.origin += shadow_off
		pair[1].global_transform = xf
