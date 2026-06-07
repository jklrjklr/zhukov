class_name SurvivalStats
extends Node

@export var max_stamina: float = 100.0
@export var stamina_drain_run: float = 15.0  # per second while running
@export var stamina_regen:     float = 8.0   # per second when not running

@export var max_hunger: float = 100.0
@export var hunger_drain: float = 0.3        # per second (~5.5 min from full to 0)

@export var max_thirst: float = 100.0
@export var thirst_drain: float = 0.7        # per second (~2.4 min from full to 0)

var stamina: float = 100.0
var hunger:  float = 100.0
var thirst:  float = 100.0

signal exhausted  # stamina first hits 0

var _is_running: bool = false
var _exhausted_fired: bool = false

func _physics_process(delta: float) -> void:
	if _is_running:
		stamina = maxf(0.0, stamina - stamina_drain_run * delta)
		if stamina == 0.0 and not _exhausted_fired:
			_exhausted_fired = true
			exhausted.emit()
	else:
		if stamina > 0.0:
			_exhausted_fired = false
		stamina = minf(max_stamina, stamina + stamina_regen * delta)

	hunger = maxf(0.0, hunger - hunger_drain * delta)
	thirst = maxf(0.0, thirst - thirst_drain * delta)

func set_running(running: bool) -> void:
	_is_running = running

func can_run() -> bool:
	return stamina > 0.0

func restore(stat: String, amount: float) -> void:
	match stat:
		"stamina": stamina = minf(max_stamina, stamina + amount)
		"hunger":  hunger  = minf(max_hunger,  hunger  + amount)
		"thirst":  thirst  = minf(max_thirst,  thirst  + amount)
