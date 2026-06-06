class_name CharacterController
extends Node2D

signal zone_clicked(zone_name: String)
signal reaction_started(reaction_id: String, text: String)
signal reaction_finished(reaction_id: String)
signal menu_action(action_id: String)

enum State { IDLE, REACTING }

const BLINK_MIN := 3.0
const BLINK_MAX := 8.0

@onready var sprite: AnimatedSprite2D = $Character/Sprite
@onready var blink_timer: Timer = $BlinkTimer

var _state := State.IDLE
var _current_reaction := ""
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	sprite.animation_finished.connect(_on_animation_finished)
	blink_timer.timeout.connect(_on_blink_timer_timeout)
	_start_idle()

func _start_idle() -> void:
	sprite.play("idle")
	_schedule_blink()

func _schedule_blink() -> void:
	blink_timer.wait_time = _rng.randf_range(BLINK_MIN, BLINK_MAX)
	blink_timer.start()

func _on_blink_timer_timeout() -> void:
	if _state == State.IDLE:
		sprite.play("blink")

## Entry point for any reaction. No-ops if already reacting.
func trigger_reaction(reaction_id: String) -> void:
	if _state == State.REACTING:
		return
	if not ReactionData.REACTIONS.has(reaction_id):
		return
	_state = State.REACTING
	_current_reaction = reaction_id
	blink_timer.stop()
	var data: Dictionary = ReactionData.REACTIONS[reaction_id]
	var texts: Array = data.get("texts", [])
	var text: String = texts[_rng.randi() % texts.size()] if not texts.is_empty() else ""
	sprite.play(data.animation)
	reaction_started.emit(reaction_id, text)

func _on_animation_finished() -> void:
	if sprite.animation == "blink":
		sprite.play("idle")
		return
	if _state == State.REACTING:
		var finished := _current_reaction
		_current_reaction = ""
		_state = State.IDLE
		reaction_finished.emit(finished)
		_start_idle()

# --- Zone handlers (connected in scene) ---

func _handle_zone_event(event: InputEvent, zone_name: String) -> void:
	var clicked := (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT)
	var touched := (event is InputEventScreenTouch and event.pressed)
	if clicked or touched:
		zone_clicked.emit(zone_name)
		trigger_reaction(zone_name)

func _on_head_zone_input_event(_vp: Node, event: InputEvent, _idx: int) -> void:
	_handle_zone_event(event, "head")

func _on_body_zone_input_event(_vp: Node, event: InputEvent, _idx: int) -> void:
	_handle_zone_event(event, "body")

func _on_lap_zone_input_event(_vp: Node, event: InputEvent, _idx: int) -> void:
	_handle_zone_event(event, "lap")

# --- Button handlers (connected in scene) ---

func _on_pet_button_pressed() -> void:
	menu_action.emit("pet")
	trigger_reaction("pet")

func _on_talk_button_pressed() -> void:
	menu_action.emit("talk")
	trigger_reaction("talk")

func _on_gift_button_pressed() -> void:
	menu_action.emit("gift")
	trigger_reaction("gift")
