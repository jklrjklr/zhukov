extends CharacterBody2D
## Top-down player. Swipes turn the camera (look_angle); the body (and weapon,
## sight cone) follows at a limited turn rate, so fast flicks lag behind like
## swinging a real weapon. The camera rig counter-rotates so the view stays on
## look_angle: screen-up is always where you are looking.
## Movement has light inertia (accel/decel).
## Draw order: feet, torso, hands (this node) -> Firearm -> Head (children).

@export var move_speed := 180.0 # px/s base walk (3 m/s); zombies scale from this
@export var keyboard_turn_speed := 2.8 # rad/s, desktop testing only
## Body turn rate (deg/s) at hip; scaled by weapon turn_multiplier and ADS.
@export var body_turn_speed := 300.0
@export_range(0.0, 1.0) var ads_body_turn := 0.5
## px/s^2
@export var acceleration := 1100.0
@export var deceleration := 1400.0

@export var max_hp := 100.0
@export var max_stims := 4
@export var max_grenades := 4
## s for a stim to heal to full.
@export var stim_time := 1.2
## m: hip throw distance (ADS throws to the aim circle).
@export var throw_distance := 10.0

## Where the camera looks (radians). Body rotation chases it.
var look_angle := 0.0
var hp := 100.0
var dead := false
## 0..1 flash after taking damage (HUD vignette).
var hurt := 0.0
var stims := 4
var grenades := 4
## Held by the INTERACT button.
var interacting := false
## Interactable currently in reach (or null).
var interact_target: Interactable = null
var _heal_left := 0.0

## Movement input in screen/local space, set by TouchControls.
## Length 0..1, (0, -1) = forward.
var move_input := Vector2.ZERO

## Body look: floating head, torso, hands and feet (no arms/legs), top-down.
const SKIN := Color(0.96, 0.78, 0.6)
const ARMOR := Color(0.95, 0.75, 0.15)
const HELMET := Color(0.3, 0.32, 0.3)
const BOOT := Color(0.22, 0.2, 0.18)
const POUCH := Color(0.4, 0.38, 0.22)
const OUTLINE := Color(0.08, 0.08, 0.08)
## Full step cycles (left+right foot) per second at full speed. Decoupled from
## distance on purpose: feet may "skip" ground, the pace just reads calmer.
const STEP_CYCLES_PER_SEC := 1.5
## Speed multipliers by direction (relative to facing).
const FORWARD_SPEED := 1.0
const STRAFE_SPEED := 0.6
const BACK_SPEED := 0.7

var _walk_phase := 0.0 # radians, advances with distance moved
var _walk_amount := 0.0 # 0 idle .. 1 full stride, eased

@onready var weapon: Firearm = $Firearm
@onready var _head: Node2D = $Head
@onready var _rig: Node2D = $CameraRig


func _ready() -> void:
	add_to_group("player")
	hp = max_hp
	stims = max_stims
	grenades = max_grenades
	_head.draw.connect(_draw_head)
	look_angle = rotation


func use_stim() -> void:
	if dead or stims <= 0 or hp >= max_hp or _heal_left > 0.0:
		return
	stims -= 1
	_heal_left = max_hp
	Game.add_stat("stims")


func throw_grenade() -> void:
	if dead or grenades <= 0:
		return
	grenades -= 1
	Game.add_stat("grenades")
	var forward := Vector2.UP.rotated(rotation)
	var target := global_position + forward * throw_distance * Firearm.PX_PER_M
	if weapon.ads_amount() >= 0.5:
		target = weapon.aim_overlay().center
	var projectiles := get_tree().get_first_node_in_group("projectiles")
	projectiles.spawn_grenade(global_position + forward * 22.0, target, self)


## Ammo box: spare mags full, +2 grenades, +1 stim.
func resupply() -> void:
	weapon.refill()
	grenades = mini(grenades + 2, max_grenades)
	stims = mini(stims + 1, max_stims)


## Reinforced: back to full health and default loadout at pos.
func revive(pos: Vector2) -> void:
	dead = false
	hp = max_hp
	hurt = 0.0
	_heal_left = 0.0
	stims = max_stims
	grenades = max_grenades
	global_position = pos
	velocity = Vector2.ZERO
	weapon.reset_loadout()


func take_damage(amount: float, from: Vector2) -> void:
	if dead:
		return
	hp = maxf(hp - amount, 0.0)
	hurt = 1.0
	velocity += (global_position - from).normalized() * 160.0
	kick(randf_range(-0.06, 0.06))
	if hp <= 0.0:
		dead = true
		Game.add_stat("deaths")
		move_input = Vector2.ZERO
		interacting = false
		weapon.trigger = false
		weapon.ads = false


func _physics_process(delta: float) -> void:
	hurt = maxf(hurt - delta * 1.5, 0.0)
	if _heal_left > 0.0 and not dead:
		var h := minf(_heal_left, max_hp / stim_time * delta)
		hp = minf(hp + h, max_hp)
		_heal_left -= h
	_update_interact(delta)
	var input := Vector2.ZERO if dead else move_input
	var kb := _keyboard_move()
	if kb != Vector2.ZERO and not dead:
		input = kb
	input = input.limit_length(1.0)

	var kb_turn := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	if kb_turn != 0.0:
		turn_look(kb_turn * keyboard_turn_speed * delta)

	# Body chases the camera at a limited rate.
	var ads := weapon.ads_amount()
	var max_step := deg_to_rad(body_turn_speed * weapon.stats.turn_multiplier() * lerpf(1.0, ads_body_turn, ads)) * delta
	var diff := wrapf(look_angle - rotation, -PI, PI)
	rotation = wrapf(rotation + clampf(diff, -max_step, max_step), -PI, PI)
	_rig.rotation = wrapf(look_angle - rotation, -PI, PI)

	# Joystick is screen-relative (camera); speed penalties are body-relative.
	var dir_world := input.rotated(look_angle)
	var ads_mult := lerpf(1.0, weapon.stats.ads_move_mult, ads)
	var target := dir_world * move_speed * _direction_multiplier(dir_world.rotated(-rotation)) \
		* weapon.stats.move_multiplier() * ads_mult
	var rate := acceleration if target.length() > velocity.length() else deceleration
	velocity = velocity.move_toward(target, rate * delta)
	move_and_slide()
	_animate(delta)


func is_healing() -> bool:
	return _heal_left > 0.0


## Nearest usable interactable in reach; holding INTERACT fills its progress.
func _update_interact(delta: float) -> void:
	var best: Interactable = null
	var best_d := INF
	if not dead:
		for n in get_tree().get_nodes_in_group("interactables"):
			var it := n as Interactable
			if not it.usable():
				continue
			var d := global_position.distance_to(it.global_position)
			if d <= it.reach_m * Firearm.PX_PER_M and d < best_d:
				best = it
				best_d = d
	if interact_target and interact_target != best:
		interact_target.progress = 0.0
	interact_target = best
	if best:
		if interacting:
			best.hold(delta, self)
		else:
			best.progress = maxf(best.progress - delta * 2.0, 0.0)


## Swipe / keyboard turning: moves the camera; the body follows.
## Positive = clockwise (turn right).
func turn_look(radians: float) -> void:
	look_angle = wrapf(look_angle + radians, -PI, PI)


## Recoil: moves camera and body together.
func kick(radians: float) -> void:
	look_angle = wrapf(look_angle + radians, -PI, PI)
	rotation = wrapf(rotation + radians, -PI, PI)


## Blend forward/strafe/back multipliers by direction (squared components sum to 1).
func _direction_multiplier(input: Vector2) -> float:
	if input == Vector2.ZERO:
		return 1.0
	var d := input.normalized()
	var fb := FORWARD_SPEED if d.y < 0.0 else BACK_SPEED
	return d.x * d.x * STRAFE_SPEED + d.y * d.y * fb


func _keyboard_move() -> Vector2:
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	return v.normalized()


func _animate(delta: float) -> void:
	var speed := get_real_velocity().length()
	_walk_phase = fmod(_walk_phase + clampf(speed / move_speed, 0.0, 1.0) * STEP_CYCLES_PER_SEC * TAU * delta, TAU)
	_walk_amount = move_toward(_walk_amount, clampf(speed / move_speed, 0.0, 1.0), delta * 6.0)
	# Walking swings the weapon left/right (aim only, camera stays).
	weapon.sway = sin(_walk_phase) * _walk_amount
	queue_redraw()


func _draw() -> void:
	var swing := sin(_walk_phase) * _walk_amount
	var bob := absf(cos(_walk_phase)) * _walk_amount

	# Feet (alternate forward/back while walking)
	_shape_ellipse(Vector2(-9, -6 - swing * 9), Vector2(4.5, 6.5), BOOT)
	_shape_ellipse(Vector2(9, -6 + swing * 9), Vector2(4.5, 6.5), BOOT)

	# Torso (wide shoulders, sways slightly opposite to feet)
	draw_set_transform(Vector2.ZERO, -swing * 0.12)
	_shape_ellipse(Vector2(0, 1), Vector2(16, 10), ARMOR)
	draw_set_transform(Vector2.ZERO)

	# Chest mag pouches
	for x in [-14.0, -9.5]:
		draw_rect(Rect2(x - 2.5, -6, 5, 6.5), OUTLINE)
		draw_rect(Rect2(x - 2, -5.5, 4, 5.5), POUCH)

	# Mag in the support hand during reloads (under the hand)
	var mag = weapon.held_mag()
	if mag != null:
		var mp: Vector2 = mag + Vector2(0, bob * 1.5)
		draw_set_transform(mp, weapon.hold_rotation())
		draw_rect(Rect2(-Firearm.MAG_SIZE_PX / 2.0, Firearm.MAG_SIZE_PX).grow(1.0), OUTLINE)
		draw_rect(Rect2(-Firearm.MAG_SIZE_PX / 2.0, Firearm.MAG_SIZE_PX), Color(0.16, 0.16, 0.17))
		draw_set_transform(Vector2.ZERO)

	# Hands, under the weapon
	for p in weapon.hand_points():
		_shape_circle(self, p + Vector2(0, bob * 1.5), 4.0, SKIN)


func _draw_head() -> void:
	_shape_circle(_head, Vector2.ZERO, 7.0, HELMET)
	_head.draw_arc(Vector2.ZERO, 4.5, -PI * 0.8, -PI * 0.2, 10, Color(0.55, 0.85, 1.0), 2.5)


func _shape_circle(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c, r + 1.5, OUTLINE)
	ci.draw_circle(c, r, col)


func _shape_ellipse(c: Vector2, radii: Vector2, col: Color) -> void:
	draw_colored_polygon(_ellipse_points(c, radii + Vector2(1.5, 1.5)), OUTLINE)
	draw_colored_polygon(_ellipse_points(c, radii), col)


func _ellipse_points(c: Vector2, radii: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts
