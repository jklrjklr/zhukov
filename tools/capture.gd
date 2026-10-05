extends Node
## Visual check: runs the mission scene with a real renderer and saves screenshots of a
## scripted combat (hellpod, bugs, charger telegraph, bile, stratagems, damage).
##   xvfb-run -a gd --path . --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 \
##     res://tools/capture.tscn -- /tmp/cap/a
## The prefix after `--` is the PNG path prefix; frames: <prefix>_<name>.png

var _prefix := "/tmp/cap/shot"
var _m: Mission
var _p: CharacterBody2D
var _s: Stratagems
var _keep_alive := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	var scene := (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	add_child(scene)
	_m = scene.get_node("Mission")
	_p = scene.get_node("Player")
	_s = scene.get_node("Stratagems")
	_run.call_deferred()


func _process(_d: float) -> void:
	if _keep_alive and _p.hp < 60.0:
		_p.hp = 60.0


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [_prefix, name])
	print("saved ", name)


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func spawn(kinds: Array, at: Vector2, alert := true) -> Array:
	var got := Terminid.spawn_pack(_m.get_node("Actors"), at, kinds.size(), 900 + randi() % 99, func(_p): return true, kinds)
	for t in got:
		if alert:
			t.alert_to(_p.global_position, true)
	return got


func _run() -> void:
	await wait(1.35)
	await shot("1_hellpod_fall")
	await wait(0.75)
	await shot("2_landing")
	await wait(1.2)
	_keep_alive = true
	var pp := _p.global_position
	var P := 60.0
	# Bugs ahead: a pack coming, a spitter further, a few unaware ones with "?".
	spawn([Terminid.Kind.WARRIOR, Terminid.Kind.WARRIOR, Terminid.Kind.SCAVENGER, Terminid.Kind.SCAVENGER,
		Terminid.Kind.SCAVENGER, Terminid.Kind.HUNTER], pp + Vector2(0, -11 * P))
	spawn([Terminid.Kind.BILE_SPITTER], pp + Vector2(-4 * P, -14 * P))
	var unaware := spawn([Terminid.Kind.SCAVENGER, Terminid.Kind.WARRIOR], pp + Vector2(7 * P, -8 * P), false)
	for u in unaware:
		u.alert_to(pp + Vector2(0, -5 * P), false)
	var ch := Charger.new()
	ch.position = pp + Vector2(2 * P, -16 * P)
	_m.get_node("Actors").add_child(ch)
	await wait(0.3)
	_p.weapon.trigger = true
	_p.weapon.fire_mode_index = _p.weapon.stats.fire_modes.size() - 1
	await wait(2.0)
	await shot("3_combat_a")
	_p.look_angle += 0.15
	await wait(1.2)
	await shot("4_combat_b")
	# Charger telegraph: put it in wind-up facing the player.
	if is_instance_valid(ch):
		ch.global_position = _p.global_position + Vector2(0, -9 * P)
		ch.rotation = PI
		ch.state = Charger.State.WINDUP
		ch._t = 1.0
	await wait(0.35)
	await shot("5_charger_telegraph")
	_p.hp = 100.0
	_p.take_damage(22.0, _p.global_position + Vector2(200, 100))
	await wait(0.25)
	await shot("6_damage")
	# Stratagems: beacon + eagle + orbital barrage.
	_p.weapon.trigger = false
	_s.status["orbital_120"].charges = 1
	_s.locked = false
	_s._throw("orbital_120", _p.global_position + Vector2(0, -8 * 60.0))
	await wait(1.4)
	await shot("7_beacon")
	_s._throw("eagle_airstrike", _p.global_position + Vector2(0, -8 * 60.0))
	await wait(4.5)
	await shot("8_barrage")
	await wait(2.0)
	_keep_alive = false
	_p.hp = 22.0
	await shot("9_low_hp")
	await wait(3.0)
	await shot("10_aftermath")
	get_tree().quit()
