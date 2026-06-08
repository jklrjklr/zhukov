class_name Player
extends CharacterBody2D

@export var move_speed: float = 180.0
@export var ergonomics: float = 0.5
@export_range(-3.1416, 3.1416, 0.1) var facing_offset: float = 0.0
@export_range(5.0, 90.0, 1.0) var ease_start_deg: float = 30.0
@export_range(0.0, 0.5, 0.01) var ease_min_factor: float = 0.5

@onready var _camera:      PlayerCamera     = $Camera2D
@onready var _sprite:      Node2D           = $Sprite2D
@onready var inventory:    InventorySystem  = $InventorySystem
@onready var state_machine: CharacterStateMachine = $CharacterStateMachine
@onready var survival:     SurvivalStats    = $SurvivalStats

# Body-part sprite refs
@onready var _head_spr:    Sprite2D = $Sprite2D/Head
@onready var _foot_l:      Sprite2D = $Sprite2D/FootL
@onready var _foot_r:      Sprite2D = $Sprite2D/FootR
@onready var _shoulder_l:  Node2D   = $Sprite2D/ShoulderL
@onready var _shoulder_r:  Node2D   = $Sprite2D/ShoulderR
@onready var _elbow_l:     Node2D   = $Sprite2D/ShoulderL/ElbowL
@onready var _elbow_r:     Node2D   = $Sprite2D/ShoulderR/ElbowR
@onready var _upper_arm_l: Sprite2D = $Sprite2D/ShoulderL/UpperArmL
@onready var _upper_arm_r: Sprite2D = $Sprite2D/ShoulderR/UpperArmR
@onready var _hand_l:      Node2D   = $Sprite2D/ShoulderL/ElbowL/HandL
@onready var _hand_r:      Node2D   = $Sprite2D/ShoulderR/ElbowR/HandR

# Public facing angle — head direction, used by AdsOverlay and WeaponSystem
var facing_angle: float:
	get: return _head_angle

var _facing_angle:  float = 0.0  # mirrors _head_angle for legacy callers
var _body_angle:    float = 0.0
var _head_angle:    float = 0.0
var _initialized:   bool  = false
var _turn_speed_rad: float = 0.0
var _reaction_delay: float = 0.0
var _ads_raise_time: float = 0.35
var _weapon_ergo:   float = 0.5
var _ads_ergo_mult: float = 1.0

# Head–body separation
const HEAD_MAX_LOCAL:  float = PI / 3.0   # 60° max head offset from body
const BODY_SPEED_MULT: float = 0.55       # body turns at 55 % of head speed

# Feet walk animation
const WALK_FREQ:      float   = 1.6
const WALK_AMP:       float   = 20.0
const FOOT_L_BASE:    Vector2 = Vector2(-15.0, 6.0)
const FOOT_R_BASE:    Vector2 = Vector2( 15.0, 6.0)
var   _walk_phase:    float   = 0.0

# Arm animation — keep in sync with ShoulderL/R position and ElbowL/R position in Player.tscn
const ARM_BASE_ROT:   float = PI
const ARM_SWING_AMP:  float = 0.22
const ARM_BASE_LEN:   float = 1.0
const ARM_LEN_VARY:   float = 0.06
const ARM_ELBOW_Y:    float = 24.0    # must match ElbowL/R position.y in Player.tscn
const ARM_HAND_Y:     float = 24.0    # must match HandL/R position.y in Player.tscn
const ELBOW_BEND:     float = 0.25
const SHOULDER_L_POS: Vector2 = Vector2(-27.0,  0.0)  # must match ShoulderL position in Player.tscn
const SHOULDER_R_POS: Vector2 = Vector2( 28.0,  0.0)  # must match ShoulderR position in Player.tscn

# Arm spring state
var _arm_l_rot: float = ARM_BASE_ROT
var _arm_r_rot: float = ARM_BASE_ROT
var _arm_l_vel: float = 0.0
var _arm_r_vel: float = 0.0
const ARM_SPRING_K: float = 18.0
const ARM_SPRING_D: float = 7.0

var max_health: int = 100
var health:     int = 100

signal health_changed(new_hp: int)
signal player_died
signal headshot_received
signal entered_ads(sight: SightData, raise_time: float)
signal exited_ads

func _ready() -> void:
	_update_ergonomics_stats()
	state_machine.state_changed.connect(_on_state_changed)
	# Arm rest pose
	_shoulder_l.position = SHOULDER_L_POS
	_shoulder_r.position = SHOULDER_R_POS
	_arm_l_rot = ARM_BASE_ROT
	_arm_r_rot = ARM_BASE_ROT
	_shoulder_l.rotation = ARM_BASE_ROT
	_shoulder_r.rotation = ARM_BASE_ROT
	_elbow_l.rotation =  ELBOW_BEND
	_elbow_r.rotation = -ELBOW_BEND
	await get_tree().process_frame
	$WeaponSystem.equip(0, "micro_uzi")
	add_to_group("player")

func _physics_process(delta: float) -> void:
	if not _initialized:
		var t := _get_target_angle()
		_body_angle  = t
		_head_angle  = t
		_facing_angle = t
		_sprite.rotation = t
		_initialized = true
		return
	_apply_movement(delta)
	_update_facing(delta)
	_update_feet(delta)
	_update_arms(delta)
	_check_run_state()

func _get_target_angle() -> float:
	return _camera.rotation + facing_offset

func _apply_movement(delta: float) -> void:
	var raw_dir: Vector2 = TouchInputHandler.get_move_vector()
	if raw_dir.length_squared() < 0.01:
		velocity = velocity.move_toward(Vector2.ZERO, move_speed * 8.0 * delta)
	else:
		velocity = raw_dir.rotated(_camera.rotation) * move_speed
	move_and_slide()

func _check_run_state() -> void:
	var wants_run := TouchInputHandler.is_running_joystick() \
		and survival.can_run() \
		and not TouchInputHandler.fire_held
	if wants_run and not state_machine.is_running() and not state_machine.is_ads():
		state_machine.transition(CharacterStateMachine.State.RUNNING)
	elif not wants_run and state_machine.is_running():
		state_machine.transition(CharacterStateMachine.State.HIPFIRE)
	survival.set_running(state_machine.is_running())

func _update_facing(delta: float) -> void:
	var target := _get_target_angle()

	# Head eases toward camera target at full turn speed
	var hgap := absf(angle_difference(_head_angle, target))
	if hgap > deg_to_rad(0.1):
		var ease_r := deg_to_rad(ease_start_deg)
		var spd    := _turn_speed_rad
		if hgap < ease_r:
			var t := hgap / ease_r
			spd = _turn_speed_rad * lerpf(ease_min_factor, 1.0, smoothstep(0.0, 1.0, t))
		_head_angle = rotate_toward(_head_angle, target, spd * delta)
	else:
		_head_angle = target

	# Clamp head within ± HEAD_MAX_LOCAL of body; body snaps if limit hit
	var hlocal := angle_difference(_body_angle, _head_angle)
	if absf(hlocal) > HEAD_MAX_LOCAL:
		_head_angle = _body_angle + sign(hlocal) * HEAD_MAX_LOCAL

	# Body eases toward (clamped) head at reduced speed
	_body_angle = rotate_toward(_body_angle, _head_angle,
			_turn_speed_rad * BODY_SPEED_MULT * delta)

	_facing_angle    = _head_angle
	_sprite.rotation = _body_angle
	_head_spr.rotation = angle_difference(_body_angle, _head_angle)

func _update_feet(delta: float) -> void:
	var spd := velocity.length()
	if spd > 10.0:
		_walk_phase = fmod(_walk_phase + delta * WALK_FREQ * TAU, TAU)

	var t      := minf(spd / move_speed, 1.0)
	var stride := t * WALK_AMP

	# Movement direction in body-local space so feet stride along travel path
	var local_dir := Vector2.ZERO
	if spd > 10.0:
		local_dir = velocity.normalized().rotated(-_body_angle)

	_foot_l.position = FOOT_L_BASE + local_dir * sin(_walk_phase)        * stride
	_foot_r.position = FOOT_R_BASE + local_dir * sin(_walk_phase + PI)   * stride

func _update_arms(delta: float) -> void:
	var spd := velocity.length()
	var t   := minf(spd / move_speed, 1.0)

	# Target shoulder rotations: base pointing forward ± walking swing
	var tgt_l := ARM_BASE_ROT + sin(_walk_phase + PI) * ARM_SWING_AMP * t
	var tgt_r := ARM_BASE_ROT + sin(_walk_phase)      * ARM_SWING_AMP * t

	# Spring physics — loose shoulder feel
	var err_l := angle_difference(_arm_l_rot, tgt_l)
	_arm_l_vel = _arm_l_vel * maxf(0.0, 1.0 - ARM_SPRING_D * delta) \
			+ err_l * ARM_SPRING_K * delta
	_arm_l_rot += _arm_l_vel * delta

	var err_r := angle_difference(_arm_r_rot, tgt_r)
	_arm_r_vel = _arm_r_vel * maxf(0.0, 1.0 - ARM_SPRING_D * delta) \
			+ err_r * ARM_SPRING_K * delta
	_arm_r_rot += _arm_r_vel * delta

	_shoulder_l.rotation = _arm_l_rot
	_shoulder_r.rotation = _arm_r_rot

	# Upper arm length stretches slightly during stride
	var len_l := ARM_BASE_LEN + sin(_walk_phase + PI) * ARM_LEN_VARY * t
	var len_r := ARM_BASE_LEN + sin(_walk_phase)      * ARM_LEN_VARY * t
	_upper_arm_l.scale = Vector2( 1.0, len_l)
	_upper_arm_r.scale = Vector2(-1.0, len_r)
	_elbow_l.position  = Vector2(0.0, ARM_ELBOW_Y * len_l)
	_elbow_r.position  = Vector2(0.0, ARM_ELBOW_Y * len_r)
	_hand_l.position   = Vector2(0.0, ARM_HAND_Y)
	_hand_r.position   = Vector2(0.0, ARM_HAND_Y)

	# Subtle elbow flex during swing
	_elbow_l.rotation =  ELBOW_BEND + sin(_walk_phase + PI) * 0.08 * t
	_elbow_r.rotation = -(ELBOW_BEND + sin(_walk_phase)      * 0.08 * t)

func _update_ergonomics_stats() -> void:
	_turn_speed_rad = deg_to_rad(lerpf(90.0, 480.0, ergonomics))
	_reaction_delay = lerpf(0.5, 0.05, ergonomics)
	_ads_raise_time = lerpf(0.65, 0.08, ergonomics)

func set_ergonomics(value: float) -> void:
	_weapon_ergo = clampf(value, 0.0, 1.0)
	_apply_combined_ergo()

func set_ads_ergo_mult(mult: float) -> void:
	_ads_ergo_mult = mult
	_apply_combined_ergo()

func _apply_combined_ergo() -> void:
	ergonomics = clampf(_weapon_ergo * _ads_ergo_mult, 0.0, 1.0)
	_update_ergonomics_stats()

func on_ads_pressed(sight: SightData) -> void:
	if state_machine.transition(CharacterStateMachine.State.ADS):
		set_ads_ergo_mult(sight.ergo_mult)
		_camera.set_ads_scope(sight.scope_mult)
		entered_ads.emit(sight, _ads_raise_time)

func on_ads_released() -> void:
	if state_machine.transition(CharacterStateMachine.State.HIPFIRE):
		set_ads_ergo_mult(1.0)
		_camera.clear_ads_scope()
		exited_ads.emit()

func _on_state_changed(_old: CharacterStateMachine.State, _new: CharacterStateMachine.State) -> void:
	pass

func take_damage(amount: int, is_headshot: bool = false) -> void:
	health = max(0, health - amount)
	health_changed.emit(health)
	if is_headshot:
		headshot_received.emit()
	if health == 0:
		player_died.emit()

func heal(amount: int) -> void:
	health = min(max_health, health + amount)
	health_changed.emit(health)

func enter_idle() -> void:
	state_machine.transition(CharacterStateMachine.State.IDLE)

func exit_idle() -> void:
	state_machine.transition(CharacterStateMachine.State.HIPFIRE)

func angle_difference(from: float, to: float) -> float:
	return fposmod(to - from + PI, TAU) - PI

func rotate_toward(current: float, target: float, step: float) -> float:
	var diff := angle_difference(current, target)
	if absf(diff) <= step:
		return target
	return current + sign(diff) * step
