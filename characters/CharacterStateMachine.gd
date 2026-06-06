class_name CharacterStateMachine
extends Node

enum State { HIPFIRE = 0, ADS = 1, RUNNING = 2, IDLE = 3 }

signal state_changed(old_state: State, new_state: State)

var state: State = State.HIPFIRE

# Attempt a state transition. Returns true if it succeeded.
func transition(new_state: State) -> bool:
	if new_state == state:
		return false
	if not _valid(state, new_state):
		return false
	var old := state
	state = new_state
	state_changed.emit(old, state)
	return true

func can_shoot() -> bool:
	return state == State.HIPFIRE or state == State.ADS

func can_reload() -> bool:
	return state == State.HIPFIRE or state == State.ADS

func is_ads() -> bool:
	return state == State.ADS

func is_running() -> bool:
	return state == State.RUNNING

func state_name() -> String:
	return State.keys()[state]

func _valid(from: State, to: State) -> bool:
	match to:
		State.HIPFIRE:
			return from != State.HIPFIRE
		State.ADS:
			return from == State.HIPFIRE
		State.RUNNING:
			return from == State.HIPFIRE
		State.IDLE:
			return from in [State.HIPFIRE, State.ADS, State.RUNNING]
	return false
