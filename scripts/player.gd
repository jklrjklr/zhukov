extends CharacterBody2D
## Top-down player. Swipes turn the camera (look_angle); the body (and weapon,
## sight cone) follows at a limited turn rate, so fast flicks lag behind like
## swinging a real weapon. The camera rig counter-rotates so the view stays on
## look_angle: screen-up is always where you are looking.
## Movement has light inertia (accel/decel).
## Draw order: feet, torso, hands (this node) -> Firearm -> Head (children).

@export var move_speed := 180.0 # px/s base walk (3 m/s); enemy speeds scale from this
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
## Sprint: joystick pushed to the edge. Speed multiplier and seconds of stamina.
@export var sprint_mult := 1.5
@export var stamina_seconds := 6.0
@export var stamina_regen_delay := 1.0
## Dive: distance (m) and time (s), then prone recovery (s).
@export var dive_distance := 3.5
@export var dive_time := 0.4
@export var prone_time := 0.55

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
## 0..1
var stamina := 1.0
var sprinting := false
## True while the hellpod is still coming down (hidden, no control).
var deploying := false
var _stamina_idle := 0.0
var _slow_t := 0.0
var _dive_t := 0.0
var _prone_t := 0.0
var _dive_dir := Vector2.UP
## Stratagem auto-typing (set by Stratagems): arm-raised pose, progress 0..1, glyph colour.
var typing := false
var typing_prog := 0.0
var typing_col := Color.WHITE
## Seconds left of a stagger / knock-down (interrupts stratagem typing).
var stagger_t := 0.0
var _edge_t := 0.0

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

## Recent damage sources for the HUD's direction indicator: {from: Vector2, t: s, amt}.
var hit_dirs: Array[Dictionary] = []
## Hip laser: length to the first obstacle (px), updated every physics tick.
var _laser_len := 0.0
var _laser_hit := false
var _heal_pulse := 0.0
var _ov: Node2D
var _step_t := 0.0
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
	_ov = Node2D.new()
	_ov.name = "FxOverlay"
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_ov.material = m
	_ov.draw.connect(_draw_overlay)
	add_child(_ov)
	look_angle = rotation


## Hunter strike etc.: move at half speed for t seconds.
func apply_slow(t: float) -> void:
	_slow_t = maxf(_slow_t, t)


func dive() -> void:
	if dead or deploying or _dive_t > 0.0 or _prone_t > 0.0:
		return
	var dir := move_input.rotated(look_angle) if move_input.length() > 0.2 else Vector2.UP.rotated(rotation)
	_dive_dir = dir.normalized()
	_dive_t = dive_time
	Fx.dust_puff(self, global_position, 1.2)
	weapon.trigger = false
	Sfx.play_ui("dive", -4.0, 0.08)


func is_diving() -> bool:
	return _dive_t > 0.0 or _prone_t > 0.0


func use_stim() -> void:
	if dead or stims <= 0 or hp >= max_hp or _heal_left > 0.0:
		return
	stims -= 1
	_heal_left = max_hp
	Game.add_stat("stims")
	Sfx.play_ui("stim", -6.0)


func throw_grenade() -> void:
	if dead or grenades <= 0:
		return
	grenades -= 1
	Game.add_stat("grenades")
	Sfx.play_ui("throw", -4.0, 0.1)
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
	stamina = 1.0
	_slow_t = 0.0
	_dive_t = 0.0
	_prone_t = 0.0
	hurt = 0.0
	stagger_t = 0.0
	typing = false
	_heal_left = 0.0
	stims = max_stims
	grenades = max_grenades
	global_position = pos
	velocity = Vector2.ZERO
	weapon.reset_all()


func take_damage(amount: float, from: Vector2, knock := true) -> void:
	if dead or deploying:
		return
	hp = maxf(hp - amount, 0.0)
	if amount >= 3.0:
		Sfx.play_ui("player_hit", -4.0, 0.1)
	hurt = maxf(hurt, minf(1.0, amount / 20.0))
	if from.distance_to(global_position) > 4.0:
		hit_dirs.append({"from": from, "t": 0.0, "amt": amount})
		if hit_dirs.size() > 6:
			hit_dirs.pop_front()
	if amount >= 3.0:
		Fx.shake(self, clampf(amount * 0.12, 1.0, 5.0))
	if knock:
		if amount >= 8.0:
			stagger_t = 0.5
		velocity += (global_position - from).normalized() * 160.0
		kick(randf_range(-0.06, 0.06))
	if hp <= 0.0:
		dead = true
		Sfx.play_ui("player_death", 0.0)
		Game.add_stat("deaths")
		move_input = Vector2.ZERO
		interacting = false
		weapon.trigger = false
		weapon.ads = false


func _physics_process(delta: float) -> void:
	hurt = maxf(hurt - delta * 1.5, 0.0)
	for h in hit_dirs:
		h.t += delta
	if not hit_dirs.is_empty() and (hit_dirs[0].t as float) > 1.6:
		hit_dirs = hit_dirs.filter(func(h): return h.t < 1.6)
	_heal_pulse = fmod(_heal_pulse + delta, 1.0) if _heal_left > 0.0 else 0.0
	_update_laser()
	_slow_t = maxf(_slow_t - delta, 0.0)
	stagger_t = maxf(stagger_t - delta, 0.0)
	if deploying:
		velocity = Vector2.ZERO
		return
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

	var kb_turn := float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
	if kb_turn != 0.0:
		turn_look(kb_turn * keyboard_turn_speed * delta)

	# Body chases the camera at a limited rate.
	var ads := weapon.ads_amount()
	var max_step := deg_to_rad(body_turn_speed * weapon.stats.turn_multiplier() * lerpf(1.0, ads_body_turn, ads)) * delta
	var diff := wrapf(look_angle - rotation, -PI, PI)
	rotation = wrapf(rotation + clampf(diff, -max_step, max_step), -PI, PI)
	_rig.rotation = wrapf(look_angle - rotation, -PI, PI)

	# Dive: fast lunge, then a moment prone (can't move).
	if _dive_t > 0.0:
		_dive_t -= delta
		velocity = _dive_dir * dive_distance * Firearm.PX_PER_M / dive_time
		move_and_slide()
		if _dive_t <= 0.0:
			_prone_t = prone_time
		_animate(delta)
		return
	if _prone_t > 0.0:
		_prone_t -= delta
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * 2.0 * delta)
		move_and_slide()
		_animate(delta)
		return

	# Sprint: stick held at the edge (or Shift), not aiming, with stamina left.
	_edge_t = _edge_t + delta if input.length() >= 0.97 else 0.0
	var want_sprint := (_edge_t > 0.12 or Input.is_physical_key_pressed(KEY_SHIFT)) and input.length() > 0.5
	sprinting = want_sprint and stamina > 0.0 and ads < 0.1 and not dead and not typing
	if sprinting:
		stamina = maxf(stamina - delta / stamina_seconds, 0.0)
		_stamina_idle = 0.0
		weapon.ads = false
	else:
		_stamina_idle += delta
		if _stamina_idle > stamina_regen_delay:
			stamina = minf(stamina + delta / (stamina_seconds * 0.6), 1.0)

	# Joystick is screen-relative (camera); speed penalties are body-relative.
	var dir_world := input.rotated(look_angle)
	var ads_mult := lerpf(1.0, weapon.stats.ads_move_mult, ads)
	var target := dir_world * move_speed * _direction_multiplier(dir_world.rotated(-rotation)) \
		* weapon.stats.move_multiplier() * ads_mult
	if sprinting:
		target *= sprint_mult
	if _slow_t > 0.0:
		target *= 0.5
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
	_step_t -= delta
	if speed > 30.0 and not dead and _dive_t <= 0.0 and _prone_t <= 0.0:
		if _step_t <= 0.0:
			_step_t = 0.35 if not sprinting else 0.26
			Fx.dust_puff(self, global_position - velocity.normalized() * 8.0, 0.35 if sprinting else 0.18)
			Sfx.play_ui("footstep_run" if sprinting else "footstep", -8.0, 0.08)
	else:
		_step_t = minf(_step_t, 0.1)
	_walk_phase = fmod(_walk_phase + clampf(speed / move_speed, 0.0, 1.0) * STEP_CYCLES_PER_SEC * TAU * delta, TAU)
	_walk_amount = move_toward(_walk_amount, clampf(speed / move_speed, 0.0, 1.0), delta * 6.0)
	# Walking swings the weapon left/right (aim only, camera stays).
	weapon.sway = sin(_walk_phase) * _walk_amount
	queue_redraw()
	_ov.queue_redraw()


## Ray from the muzzle along the weapon to the first obstacle (laser sight length).
func _update_laser() -> void:
	if dead or deploying or weapon == null:
		_laser_len = 0.0
		return
	var from := weapon.to_global(weapon.muzzle_local())
	var dir := Vector2.UP.rotated(weapon.global_rotation)
	var reach := 14.0 * Firearm.PX_PER_M
	var q := PhysicsRayQueryParameters2D.create(from, from + dir * reach, 3)
	q.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	_laser_hit = not hit.is_empty()
	_laser_len = from.distance_to(hit.position) if _laser_hit else reach


func _draw() -> void:
	var swing := sin(_walk_phase) * _walk_amount
	var bob := absf(cos(_walk_phase)) * _walk_amount
	if not dead:
		# Drop shadow (world-fixed light) and aim laser.
		var so := Vector2(6, 8).rotated(-global_rotation)
		draw_set_transform_matrix(Transform2D(Vector2(19, 0), Vector2(0, 14), so))
		draw_circle(Vector2.ZERO, 1.0, Color(0, 0, 0, 0.28))
		draw_set_transform(Vector2.ZERO)

	# Feet (alternate forward/back while walking)
	_shape_ellipse(Vector2(-9, -6 - swing * 9), Vector2(4.5, 6.5), BOOT)
	_shape_ellipse(Vector2(9, -6 + swing * 9), Vector2(4.5, 6.5), BOOT)

	# Torso (wide shoulders, sways slightly opposite to feet)
	draw_set_transform(Vector2.ZERO, -swing * 0.12)
	# Backpack, then the torso, shoulder pads and chest plate.
	draw_rect(Rect2(-8.5, 5.0, 17, 10.5), OUTLINE)
	draw_rect(Rect2(-7.5, 6.0, 15, 8.5), Color(0.28, 0.3, 0.22))
	draw_line(Vector2(-7.5, 10), Vector2(7.5, 10), OUTLINE, 1.0)
	draw_rect(Rect2(-3, 7, 6, 3), Color(0.5, 0.45, 0.2))
	_shape_ellipse(Vector2(0, 1), Vector2(16, 10), ARMOR)
	draw_arc(Vector2(0, 1), 12.5, PI * 1.1, PI * 1.9, 12, ARMOR.lightened(0.35), 1.5)
	for sx in [-1.0, 1.0]:
		_shape_circle(self, Vector2(sx * 14.0, 0.5), 5.0, ARMOR.darkened(0.15))
		draw_circle(Vector2(sx * 14.0 - 1.0, -1.0), 2.0, ARMOR.lightened(0.3))
	draw_line(Vector2(-15, 5), Vector2(15, 5), ARMOR.darkened(0.45), 1.5) # belt
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

	# Typing a stratagem code: left arm raised to the wrist console, fingers tapping.
	if typing and not dead:
		var tap := sin(typing_prog * 40.0) * 1.6
		var sh := Vector2(-14, 0.5)
		var hand := Vector2(-12, -17 + tap)
		draw_line(sh, hand, OUTLINE, 6.5)
		draw_line(sh, hand, ARMOR.darkened(0.1), 4.0)
		draw_rect(Rect2(hand.x - 5.5, hand.y - 3.5, 11, 8), OUTLINE)
		draw_rect(Rect2(hand.x - 4.5, hand.y - 2.5, 9, 6), typing_col.darkened(0.2))
		_shape_circle(self, hand + Vector2(3, -6 + tap * 0.5), 3.4, SKIN)


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


## Faint laser sight along the weapon; stronger when hip-firing, almost gone when aimed.
func _draw_laser() -> void:
	if _laser_len < 20.0 or sprinting or is_diving() or weapon.state == Firearm.State.RELOADING:
		return
	var a := lerpf(0.5, 0.12, weapon.ads_amount())
	var from := to_local(weapon.to_global(weapon.muzzle_local()))
	var dir := Vector2.UP.rotated(weapon.global_rotation - global_rotation)
	var n := 6
	for i in n:
		var t0 := _laser_len * float(i) / n
		var t1 := _laser_len * float(i + 1) / n
		var fade := 1.0 - float(i) / n
		_ov.draw_line(from + dir * t0, from + dir * t1, Color(1.0, 0.15, 0.1, a * fade * 0.8), 1.6)
	var end := from + dir * _laser_len
	if _laser_hit:
		_ov.draw_circle(end, 5.0, Color(1.0, 0.2, 0.1, a * 0.4))
		_ov.draw_circle(end, 2.0, Color(1.0, 0.5, 0.4, a * 1.4))


func _draw_overlay() -> void:
	if dead or deploying:
		return
	_draw_laser()
	_draw_rings()


## Reload ring, stamina arc and stim pulse around the player.
func _draw_rings() -> void:
	var busy := weapon.state == Firearm.State.RELOADING or weapon.state == Firearm.State.CLEARING
	if busy:
		var k := weapon.state_progress()
		_ov.draw_arc(Vector2.ZERO, 32.0, 0.0, TAU, 40, Color(0, 0, 0, 0.45), 6.0)
		_ov.draw_arc(Vector2.ZERO, 32.0, -PI / 2.0, -PI / 2.0 + TAU * k, 40, UiStyle.BLUE if not weapon.jammed else UiStyle.RED, 4.0)
		_ov.draw_circle(Vector2.from_angle(-PI / 2.0 + TAU * k) * 32.0, 3.0, Color.WHITE)
	if stamina < 0.995:
		var col := Color(0.4, 0.8, 1.0, 0.85) if stamina > 0.25 else Color(1.0, 0.55, 0.2, 0.9)
		_ov.draw_arc(Vector2.ZERO, 26.0, PI * 0.15, PI * 0.85, 12, Color(0, 0, 0, 0.35), 4.0)
		_ov.draw_arc(Vector2.ZERO, 26.0, PI * 0.15, PI * 0.15 + PI * 0.7 * stamina, 12, col, 3.0)
	if _heal_left > 0.0:
		var p := _heal_pulse
		_ov.draw_arc(Vector2.ZERO, 20.0 + p * 18.0, 0.0, TAU, 24, Color(0.4, 1.0, 0.4, 0.7 * (1.0 - p)), 3.0)
		for i in 2:
			var c := Vector2(-10.0 + i * 20.0, -22.0 - fmod(p + i * 0.5, 1.0) * 16.0)
			_ov.draw_line(c + Vector2(-4, 0), c + Vector2(4, 0), Color(0.4, 1.0, 0.4, 0.9), 2.5)
			_ov.draw_line(c + Vector2(0, -4), c + Vector2(0, 4), Color(0.4, 1.0, 0.4, 0.9), 2.5)
