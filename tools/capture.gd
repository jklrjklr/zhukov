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
## Second argument `noenemies`: same scenario without any enemy (perf baseline of the world alone).
var _no_enemies := false
## Second argument `stress`: +40 alerted bugs in front of the player (draw / AI load test).
var _stress := false
## `vision=quad|rays|light`: vision mode for this run (not saved).
## `hide=hud|zones|actors|fx|light`: ablation for perf attribution (what costs how much).
var _hide := ""
## Perf sampling (combat window): per-frame monitors averaged and printed as PERF lines.
var _sampling := false
var _samples: Array[Dictionary] = []
var _vp_rid: RID


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	_no_enemies = "noenemies" in args
	_stress = "stress" in args
	for a in args:
		if a.begins_with("hide="):
			_hide = a.substr(5)
		if a.begins_with("vision="):
			Game.vision_mode = {"light": Vision.Mode.LIGHT, "rays": Vision.Mode.RAYS, "quad": Vision.Mode.QUAD}[a.substr(7)]
	var scene := (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	add_child(scene)
	_m = scene.get_node("Mission")
	_p = scene.get_node("Player")
	_s = scene.get_node("Stratagems")
	_run.call_deferred()


func _process(_d: float) -> void:
	if _keep_alive and _p.hp < 60.0:
		_p.hp = 60.0
	if _sampling:
		if not _vp_rid.is_valid():
			_vp_rid = get_viewport().get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
		_samples.append({
			"process": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"physics": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			"render_cpu": RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) if _vp_rid.is_valid() else 0.0,
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"enemies": get_tree().get_nodes_in_group("enemies").size(),
		})


func _apply_hide() -> void:
	var root := get_tree().root
	match _hide:
		"hud":
			root.find_children("HUD", "CanvasLayer", true, false).map(func(n): n.visible = false)
		"actors":
			_m.get_node("Actors").visible = false
		"zones":
			for z in _m.zones:
				z.visible = false
		"fx":
			var fx := root.find_children("Fx", "Node2D", true, false)
			fx.map(func(n): n.visible = false)
		"light":
			root.find_children("*", "PointLight2D", true, false).map(func(n): n.visible = false)
			root.find_children("*", "CanvasModulate", true, false).map(func(n): n.visible = false)


## Visible canvas items by owner script / class (what the renderer has to walk).
func census() -> void:
	var counts := {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var ci := n as CanvasItem
		if ci == null or not ci.is_visible_in_tree():
			continue
		var scr: Script = n.get_script()
		var key := (scr.resource_path.get_file() if scr != null else n.get_class())
		if n is Sprite2D:
			key += "/Sprite2D"
		counts[key] = counts.get(key, 0) + 1
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	var out := "CENSUS"
	for k in keys.slice(0, 12):
		out += " %s=%d" % [k, counts[k]]
	print(out)


func report_perf(label: String) -> void:
	_sampling = false
	if _samples.is_empty():
		return
	var sums := {}
	for s in _samples:
		for k in s:
			sums[k] = sums.get(k, 0.0) + s[k]
	var out := "PERF %s frames=%d" % [label, _samples.size()]
	for k in sums:
		out += " %s=%.2f" % [k, sums[k] / _samples.size()]
	print(out)
	_samples.clear()


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [_prefix, name])
	print("saved ", name)


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func spawn(kinds: Array, at: Vector2, alert := true) -> Array:
	if _no_enemies:
		return []
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
	if _stress:
		for i in 8:
			var a := -0.9 + 1.8 * i / 7.0
			spawn([Terminid.Kind.SCAVENGER, Terminid.Kind.WARRIOR, Terminid.Kind.SCAVENGER, Terminid.Kind.HUNTER, Terminid.Kind.WARRIOR],
				pp + Vector2.UP.rotated(a) * (9 + (i % 3) * 3) * P)
	var ch := Charger.new()
	ch.position = pp + Vector2(2 * P, -16 * P)
	if not _no_enemies:
		_m.get_node("Actors").add_child(ch)
	await wait(0.3)
	_p.weapon.trigger = true
	_p.weapon.fire_mode_index = _p.weapon.stats.fire_modes.size() - 1
	await wait(0.5)
	_apply_hide()
	_sampling = true
	await wait(2.5)
	report_perf("combat")
	census()
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
	# Awareness: a bug calling reinforcements (rears up, pulsing orange ring) and "?" icons filling.
	_p.hp = 100.0
	_m.call_chance = 1.0
	_m._breach_cd = 0.0
	_m._call_roll_cd = 0.0
	var cs := spawn([Terminid.Kind.WARRIOR], _p.global_position + Vector2(-3 * P, -8 * P), false)
	if not cs.is_empty():
		cs[0].rotation = 0.0
		cs[0]._become_alert(true)
	var qs := spawn([Terminid.Kind.SCAVENGER, Terminid.Kind.HUNTER, Terminid.Kind.WARRIOR], _p.global_position + Vector2(5 * P, -9 * P), false)
	for i in qs.size():
		qs[i].add_suspicion(0.3 + 0.3 * i, qs[i].global_position + Vector2(0, 40))
	await wait(0.9)
	await shot("5b_awareness_call")
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
	# Ready toasts: a refilled meter and rearmed Eagles.
	_s.status["orbital_120"].charges = 0
	_s._fill("orbital_120", 1.0e6)
	_s.status["eagle_airstrike"].charges = 0
	_s._fill("eagle_airstrike", 1.0e6)
	await wait(0.6)
	_keep_alive = false
	_p.hp = 22.0
	await shot("9_low_hp")
	await wait(3.0)
	await shot("10_aftermath")
	# Pause menu with the perf overlay on (layout check at the window size).
	var hud: Control = get_tree().root.find_child("Hud", true, false)
	Game.perf_overlay = true
	hud._set_paused(true)
	await wait(0.4)
	await shot("11_pause")
	hud._set_paused(false)
	Game.perf_overlay = false
	get_tree().quit()
