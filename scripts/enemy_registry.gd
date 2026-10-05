class_name Enemies
extends RefCounted
## Shared registry of live enemies (Terminid, Charger, ...): maintained on spawn / death /
## despawn instead of scanning get_nodes_in_group("enemies") in every system.
## Enemies call Enemies.add(self) in _ready and Enemies.remove(self) when they die.
## Also: sound broadcast, the camera rotation (cached per frame), cheap separation vectors and
## the corpse cap.

const CORPSE_CAP := 24

static var list: Array[Node2D] = []
static var corpses: Array[Node2D] = []
static var _cam_frame := -1
static var _cam_rot := 0.0


static func add(n: Node2D) -> void:
	if not list.has(n):
		list.append(n)
		n.tree_exiting.connect(remove.bind(n), CONNECT_ONE_SHOT)


static func remove(n: Node2D) -> void:
	list.erase(n)
	corpses.erase(n)


static func count() -> int:
	return list.size()


static func clear() -> void:
	list.clear()
	corpses.clear()


## A dead enemy froze into a static corpse sprite: the oldest ones beyond the cap are freed.
static func add_corpse(n: Node2D) -> void:
	corpses.append(n)
	while corpses.size() > CORPSE_CAP:
		var old: Node2D = corpses.pop_front()
		if is_instance_valid(old):
			old.queue_free()


## Sound broadcast: only enemies inside the sound's hard cap (Awareness.cap_m) are asked.
static func broadcast_sound(pos: Vector2, loudness: float, falloff_pct: float, kind := 0) -> void:
	var cap := Awareness.cap_m(kind, loudness) * 60.0
	for e in list:
		if is_instance_valid(e) and e.global_position.distance_squared_to(pos) <= cap * cap:
			if e.has_method("hear_sound"):
				e.hear_sound(pos, loudness, falloff_pct, kind)
			else:
				e.hear(pos, loudness, falloff_pct)


## Rotation of the camera (canvas transform), cached once per rendered frame.
static func cam_rot(from: CanvasItem) -> float:
	var f := Engine.get_process_frames()
	if f != _cam_frame:
		_cam_frame = f
		var vp := from.get_viewport()
		_cam_rot = vp.get_canvas_transform().get_rotation() if vp != null else 0.0
	return _cam_rot


## Small overlay child of an enemy; `fn` draws it. Hidden (and so free) until needed.
static func make_overlay(owner_node: Node2D, fn: Callable, z := 0) -> Node2D:
	var n := Node2D.new()
	n.visible = false
	n.z_index = z
	n.draw.connect(fn)
	owner_node.add_child(n)
	return n


## Push away from enemies that are too close (no raycasts): sum of unit vectors weighted by
## overlap, each neighbour at less than `reach` px (centre to centre) counts.
static func separation(me: Node2D, radius: float) -> Vector2:
	var out := Vector2.ZERO
	var p := me.global_position
	for o in list:
		if o == me:
			continue
		var orad: Variant = o.get("radius")
		var reach: float = radius + (radius if orad == null else float(orad)) + 6.0
		var d := p - o.global_position
		var l2 := d.length_squared()
		if l2 < reach * reach and l2 > 0.01:
			var l := sqrt(l2)
			out += d / l * (1.0 - l / reach)
	return out
