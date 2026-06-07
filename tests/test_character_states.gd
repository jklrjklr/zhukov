extends Object

# --- CharacterStateMachine tests ---

func _make_sm() -> CharacterStateMachine:
	return CharacterStateMachine.new()

func test_initial_state_is_hipfire() -> void:
	var sm := _make_sm()
	assert(sm.state == CharacterStateMachine.State.HIPFIRE, "initial state should be HIPFIRE")
	sm.free()

func test_hipfire_to_ads() -> void:
	var sm := _make_sm()
	assert(sm.transition(CharacterStateMachine.State.ADS), "HIPFIRE→ADS should succeed")
	assert(sm.state == CharacterStateMachine.State.ADS)
	sm.free()

func test_hipfire_to_running() -> void:
	var sm := _make_sm()
	assert(sm.transition(CharacterStateMachine.State.RUNNING), "HIPFIRE→RUNNING should succeed")
	assert(sm.state == CharacterStateMachine.State.RUNNING)
	sm.free()

func test_ads_to_hipfire() -> void:
	var sm := _make_sm()
	sm.transition(CharacterStateMachine.State.ADS)
	assert(sm.transition(CharacterStateMachine.State.HIPFIRE), "ADS→HIPFIRE should succeed")
	assert(sm.state == CharacterStateMachine.State.HIPFIRE)
	sm.free()

func test_ads_cannot_go_to_running() -> void:
	var sm := _make_sm()
	sm.transition(CharacterStateMachine.State.ADS)
	assert(not sm.transition(CharacterStateMachine.State.RUNNING), "ADS→RUNNING should fail")
	assert(sm.state == CharacterStateMachine.State.ADS)
	sm.free()

func test_running_to_hipfire() -> void:
	var sm := _make_sm()
	sm.transition(CharacterStateMachine.State.RUNNING)
	assert(sm.transition(CharacterStateMachine.State.HIPFIRE), "RUNNING→HIPFIRE should succeed")
	sm.free()

func test_idle_only_goes_to_hipfire() -> void:
	var sm := _make_sm()
	sm.transition(CharacterStateMachine.State.IDLE)
	assert(not sm.transition(CharacterStateMachine.State.ADS), "IDLE→ADS should fail")
	assert(not sm.transition(CharacterStateMachine.State.RUNNING), "IDLE→RUNNING should fail")
	assert(sm.transition(CharacterStateMachine.State.HIPFIRE), "IDLE→HIPFIRE should succeed")
	sm.free()

func test_can_shoot_hipfire_and_ads() -> void:
	var sm := _make_sm()
	assert(sm.can_shoot(), "HIPFIRE can shoot")
	sm.transition(CharacterStateMachine.State.ADS)
	assert(sm.can_shoot(), "ADS can shoot")
	sm.free()

func test_cannot_shoot_running_or_idle() -> void:
	var sm := _make_sm()
	sm.transition(CharacterStateMachine.State.RUNNING)
	assert(not sm.can_shoot(), "RUNNING cannot shoot")
	sm.transition(CharacterStateMachine.State.HIPFIRE)
	sm.transition(CharacterStateMachine.State.IDLE)
	assert(not sm.can_shoot(), "IDLE cannot shoot")
	sm.free()

func test_can_reload_hipfire_and_ads() -> void:
	var sm := _make_sm()
	assert(sm.can_reload(), "HIPFIRE can reload")
	sm.transition(CharacterStateMachine.State.ADS)
	assert(sm.can_reload(), "ADS can reload")
	sm.free()

func test_state_changed_signal_fires() -> void:
	var sm := _make_sm()
	var fired := [false]
	sm.state_changed.connect(func(_old, _new): fired[0] = true)
	sm.transition(CharacterStateMachine.State.ADS)
	assert(fired[0], "state_changed should have fired")
	sm.free()

func test_same_state_transition_returns_false() -> void:
	var sm := _make_sm()
	assert(not sm.transition(CharacterStateMachine.State.HIPFIRE), "same-state transition should return false")
	sm.free()

# --- SightData tests ---

func test_sight_data_defaults() -> void:
	var s := SightData.iron_sights()
	assert(s.ergo_mult == 0.85, "default ergo_mult")
	assert(s.scope_mult == 1.0, "default scope_mult")
	assert(s.fov_radius == 0.45, "default fov_radius")
	assert(s.reticle_type == "dot", "default reticle_type")

func test_sight_data_from_dict() -> void:
	var d := {"display_name": "ACOG", "reticle_type": "circle", "ergo_mult": 0.7, "scope_mult": 1.3, "fov_radius": 0.3}
	var s := SightData.from_dict(d)
	assert(s.display_name == "ACOG")
	assert(s.reticle_type == "circle")
	assert(s.scope_mult == 1.3)
	assert(s.fov_radius == 0.3)
