extends SceneTree
## Enemy CPU micro-benchmark (headless, deterministic): spawns 60 alerted bugs around the player,
## then calls every enemy's _physics_process / _process by hand for N frames and prints the mean
## cost per frame. Works on older trees too (no _process there). Run:
##   gd --headless -s res://tools/bench.gd

const PX := 60.0
const FRAMES := 300

var _scene: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Game").reset_stats()
	_scene = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	current_scene = _scene
	var m = _scene.get_node("Mission")
	var p = _scene.get_node("Player")
	m._pod_t = 0.01
	var guard := 0
	while not m.play_started and guard < 600:
		await process_frame
		guard += 1
	p.max_hp = 1.0e6
	p.hp = 1.0e6
	var actors: Node = m.get_node("Actors")
	var pp: Vector2 = p.global_position
	var bugs: Array = []
	for i in 12:
		var a := -1.2 + 2.4 * i / 11.0
		var got = Terminid.spawn_pack(actors, pp + Vector2.UP.rotated(a) * (7 + (i % 4) * 3) * PX, 5, 900 + i, func(_q): return true,
			[Terminid.Kind.SCAVENGER, Terminid.Kind.WARRIOR, Terminid.Kind.SCAVENGER, Terminid.Kind.HUNTER, Terminid.Kind.WARRIOR])
		for t in got:
			t.alert_to(pp, true)
			bugs.append(t)
	for i in 4:
		await process_frame
	var phys := 0
	var proc := 0
	var d := 1.0 / 60.0
	for f in FRAMES:
		var t0 := Time.get_ticks_usec()
		for b in bugs:
			if is_instance_valid(b):
				b._physics_process(d)
		var t1 := Time.get_ticks_usec()
		for b in bugs:
			if is_instance_valid(b) and b.has_method("_process"):
				b._process(d)
		var t2 := Time.get_ticks_usec()
		phys += t1 - t0
		proc += t2 - t1
	print("BENCH bugs=%d physics_ms/frame=%.2f process_ms/frame=%.2f" % [bugs.size(), phys / 1000.0 / FRAMES, proc / 1000.0 / FRAMES])
	quit()
