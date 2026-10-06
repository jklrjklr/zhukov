extends Node
## Draw-call census of the big-fight scenario (40+ bugs, a charger, MG-43 sentry firing, Eagle airstrike).
## Needs a real renderer (no draw calls headless):
##   xvfb-run -a -s "-screen 0 1280x720x24" gd --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --fixed-fps 30 res://tools/drawcall_census.tscn
## Prints (grep CENSUS / PERF / POST):
##  - CAT lines: per category the visible canvas items and the MEASURED draw-call / object cost
##    (the scene is frozen with the tree paused, the category is hidden and the frame counters are
##    compared with the full frame, so batching across items is accounted for).
##  - PERF lines: averages over the fight window (draw calls, objects, process ms, max frame).
##  - POST lines: what happens after the fight (per-frame process time, node churn, queue_free /
##    node_added bursts, corpse / decal / particle counts) and the worst frames.

const P := 60.0
var _m: Mission
var _p: CharacterBody2D
var _s: Stratagems
var _sentry: Sentry
var _ch: Charger
var _keep_alive := true
var _vp_rid: RID
var _frames: Array[Dictionary] = []
var _rec := false
var _added := 0
var _removed := 0
var _last_t := 0
var _marks: Array[String] = []
var _fired := 0
var _t0 := 0
var _script_ms := 0.0
var _probe_end: Node


func _ready() -> void:
	process_priority = -100000
	_probe_end = _EndProbe.new()
	_probe_end.process_priority = 100000
	_probe_end.process_mode = Node.PROCESS_MODE_ALWAYS
	_probe_end.owner_ref = self
	add_child(_probe_end)
	get_tree().node_added.connect(func(_n): _added += 1)
	get_tree().node_removed.connect(func(_n): _removed += 1)
	var scene := (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	add_child(scene)
	_m = scene.get_node("Mission")
	_p = scene.get_node("Player")
	_s = scene.get_node("Stratagems")
	_run.call_deferred()


class _EndProbe extends Node:
	var owner_ref: Node
	func _process(_d: float) -> void:
		owner_ref._script_ms = (Time.get_ticks_usec() - owner_ref._t0) / 1000.0


func _process(_d: float) -> void:
	_t0 = Time.get_ticks_usec()
	if _keep_alive and _p.hp < 60.0:
		_p.hp = 60.0
	var now := Time.get_ticks_usec()
	if _rec:
		if not _vp_rid.is_valid():
			_vp_rid = get_viewport().get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
		var fx_inst: Variant = Fx._inst
		_frames.append({
			"dt": (now - _last_t) / 1000.0,
			"process": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"script": _script_ms,
			"physics": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			"render_cpu": RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid),
			"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			"added": _added, "removed": _removed,
			"enemies": Enemies.list.size(), "corpses": Enemies.corpses.size(),
			"decals": Fx.decal_count(), "particles": Fx.particle_count(),
			"t": now / 1.0e6, "mark": "; ".join(_marks),
		})
		_marks.clear()
	_added = 0
	_removed = 0
	_last_t = now


# --- Categorisation --------------------------------------------------------------------

func _script_file(n: Node) -> String:
	var s: Script = n.get_script()
	return s.resource_path.get_file() if s != null else ""


## Category of a node by script / class / path pattern.
func cat_of(n: Node) -> String:
	if n is CanvasLayer:
		return "hud"
	var a: Node = n
	while a != null:
		var f := _script_file(a)
		match f:
			"bug_rig.gd", "charger_rig.gd", "rig.gd", "rig_batch.gd":
				return "rig parts"
			"enemy_overlay.gd":
				return "enemy overlays (batched)"
			"fx.gd":
				if a != n:
					return "fx decals" if (n.name.begins_with("Decal") or (n is CanvasItem and (n as CanvasItem).z_index == -8)) else "fx particles"
				return "other"
			"projectiles.gd", "proj_batch.gd":
				return "projectiles / tracers / casings"
			"sentry.gd":
				return "sentry"
			"zone.gd":
				if a == n:
					return "other"
				if n.name == "Ground":
					return "zone ground (noise / patches)"
				if n.name == "Props":
					return "zone props / walls"
				if n.name.begins_with("GroundTile"):
					return "zone baked ground tiles"
				return "zone detail chunks"
			"mission.gd":
				if n == a.get("_overlay"):
					return "mission overlay"
			"stratagems.gd":
				if a == n:
					return "stratagem fx"
			"":
				pass
			_:
				if a != n or f != "mission.gd":
					return "other: " + f + " (incl. children)"
		if a is CanvasLayer:
			return "hud"
		var par := a.get_parent()
		if par != null and (par is Terminid or par is Charger) and a is Node2D and f == "":
			return "enemy overlays: _tele" if par.get("_tele") == a else ("enemy overlays: _bb (hp/icons)" if par.get("_bb") == a else "other")
		a = par
	return "other"


func _collect(root: Node, out: Dictionary) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is CanvasItem or n is CanvasLayer):
			continue
		if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
			continue
		if n is CanvasLayer and not (n as CanvasLayer).visible:
			continue
		var c := cat_of(n)
		if not out.has(c):
			out[c] = {"items": 0, "sprites": 0, "multimesh": 0, "custom": 0, "tops": []}
		var e: Dictionary = out[c]
		if n is CanvasItem:
			e.items += 1
			if n is Sprite2D:
				e.sprites += 1
			elif n is MultiMeshInstance2D:
				e.multimesh += 1
			elif n.get_script() != null or n.get_class() == "Node2D":
				e.custom += 1
		var par := n.get_parent()
		if par == null or cat_of(par) != c:
			(e.tops as Array).append(n)


func _draws() -> float:
	return Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)


func _objs() -> float:
	return Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)


func _settle() -> Vector2:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return Vector2(_draws(), _objs())


func _set_vis(n: Variant, v: bool) -> void:
	if is_instance_valid(n):
		n.set("visible", v)


## Frozen scene, each category hidden in turn: marginal draw calls / objects of the category.
func _ablate() -> void:
	var cats := {}
	_collect(get_tree().root, cats)
	cats.erase("other")
	cats.erase("other: mission.gd (incl. children)")
	get_tree().paused = true
	var full := await _settle()
	print("CENSUS frozen total draws=%d objects=%d" % [full.x, full.y])
	var rows: Array = []
	for c in cats:
		var e: Dictionary = cats[c]
		var before := await _settle()
		for t in e.tops:
			_set_vis(t, false)
		var r := await _settle()
		for t in e.tops:
			_set_vis(t, true)
		rows.append({"cat": c, "items": e.items, "sprites": e.sprites, "mm": e.multimesh, "custom": e.custom,
			"dd": before.x - r.x, "do": before.y - r.y})
	rows.sort_custom(func(a, b): return a.dd > b.dd)
	for r in rows:
		print("CENSUS CAT %-34s items=%4d (sprites=%d multimesh=%d drawn-by-script=%d)  draw_calls=%4d  objects=%4d" % [
			r.cat, r.items, r.sprites, r.mm, r.custom, r.dd, r.do])
	# Everything but the world (what remains when all categories are hidden).
	var hidden: Array = []
	for c in cats:
		for t in (cats[c].tops as Array):
			hidden.append(t)
			_set_vis(t, false)
	var base := await _settle()
	for t in hidden:
		_set_vis(t, true)
	print("CENSUS all categories hidden: draws=%d objects=%d" % [base.x, base.y])
	var other := {}
	_collect(get_tree().root, other)
	var oc := {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if (n is CanvasItem and (n as CanvasItem).is_visible_in_tree()) and cat_of(n) == "other":
			var k := _script_file(n) if _script_file(n) != "" else n.get_class()
			oc[k] = oc.get(k, 0) + 1
	print("CENSUS other visible canvas items: ", oc)
	get_tree().paused = false


func _sample(label: String, sec: float) -> void:
	_frames.clear()
	_rec = true
	await _wait(sec)
	_rec = false
	var n := _frames.size()
	if n == 0:
		return
	var sums := {}
	var maxes := {}
	for f in _frames:
		for k in ["dt", "process", "script", "physics", "render_cpu", "draws", "objects", "nodes", "enemies", "particles", "decals"]:
			sums[k] = sums.get(k, 0.0) + f[k]
			maxes[k] = maxf(maxes.get(k, 0.0), f[k])
	var out := "PERF %s frames=%d" % [label, n]
	for k in ["draws", "objects", "script", "process", "physics", "render_cpu", "dt", "enemies", "nodes", "particles", "decals"]:
		out += " %s=%.1f(max %.1f)" % [k, sums[k] / n, maxes[k]]
	print(out)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _spawn(kinds: Array, at: Vector2, alert := true) -> Array:
	var got := Terminid.spawn_pack(_m.get_node("Actors"), at, kinds.size(), 900 + randi() % 99, func(_p): return true, kinds)
	for t in got:
		if alert:
			t.alert_to(_p.global_position, true)
	return got


func _post_report(label: String) -> void:
	var n := _frames.size()
	if n == 0:
		return
	for f in _frames:
		f["work"] = f.script + f.physics # script + physics ms (the render side is llvmpipe here, so not comparable)
	var by_t := _frames.duplicate()
	by_t.sort_custom(func(a, b): return a.work > b.work)
	var med: float = by_t[n / 2].work
	var spikes := 0
	var qf := 0
	var qmax := 0
	var addmax := 0
	for f in _frames:
		if f.work > maxf(med * 2.5, 4.0):
			spikes += 1
		qf += f.removed
		qmax = maxi(qmax, f.removed)
		addmax = maxi(addmax, f.added)
	print("POST %s frames=%d script+physics median=%.2f ms p95=%.2f max=%.2f spikes(>2.5x median)=%d  node_removed total=%d max/frame=%d  node_added max/frame=%d" % [
		label, n, med, by_t[int(n * 0.05)].work, by_t[0].work, spikes, qf, qmax, addmax])
	for i in mini(7, n):
		var f: Dictionary = by_t[i]
		print("POST   worst#%d script=%.2fms physics=%.2fms dt=%.1fms render_cpu=%.1f draws=%d objs=%d nodes=%d removed=%d added=%d enemies=%d corpses=%d decals=%d particles=%d %s" % [
			i, f.script, f.physics, f.dt, f.render_cpu, f.draws, f.objects, f.nodes, f.removed, f.added, f.enemies, f.corpses, f.decals, f.particles, f.mark])


func _run() -> void:
	await _wait(3.3)
	var pp := _p.global_position
	# Sentry (as the stratagem pod would deploy it), a few meters ahead.
	_sentry = Sentry.new()
	_sentry.position = pp + Vector2(2.5 * P, -3.0 * P)
	_p.get_parent().add_child(_sentry)
	_spawn([Terminid.Kind.WARRIOR, Terminid.Kind.WARRIOR, Terminid.Kind.SCAVENGER, Terminid.Kind.SCAVENGER,
		Terminid.Kind.SCAVENGER, Terminid.Kind.HUNTER], pp + Vector2(0, -11 * P))
	_spawn([Terminid.Kind.BILE_SPITTER], pp + Vector2(-4 * P, -14 * P))
	for i in 8:
		var a := -0.9 + 1.8 * i / 7.0
		_spawn([Terminid.Kind.SCAVENGER, Terminid.Kind.WARRIOR, Terminid.Kind.SCAVENGER, Terminid.Kind.HUNTER, Terminid.Kind.WARRIOR],
			pp + Vector2.UP.rotated(a) * (9 + (i % 3) * 3) * P)
	_ch = Charger.new()
	_ch.position = pp + Vector2(2 * P, -16 * P)
	_m.get_node("Actors").add_child(_ch)
	await _wait(0.3)
	_p.weapon.trigger = true
	_p.weapon.fire_mode_index = _p.weapon.stats.fire_modes.size() - 1
	_marks.append("fight start")
	await _wait(1.0)
	await _sample("fight (sentry + player firing)", 3.0)
	await _ablate()
	# Airstrike + barrage on top of the fight.
	_marks.append("airstrike")
	_s.locked = false
	_s._throw("eagle_airstrike", _p.global_position + Vector2(0, -8 * P))
	await _sample("fight + airstrike", 4.5)
	# Aftermath: stop firing, keep the sentry going, watch the frame log until things settle.
	_p.weapon.trigger = false
	_marks.append("player stopped firing")
	_frames.clear()
	_rec = true
	await _wait(14.0)
	_rec = false
	_post_report("after the fight (14 s)")
	_keep_alive = false
	get_tree().quit()
