class_name Enemies
extends RefCounted
## Shared registry of live enemies (Terminid, Charger, ...): maintained on spawn / death /
## despawn instead of scanning get_nodes_in_group("enemies") in every system.
## Enemies call Enemies.add(self) in _ready and Enemies.remove(self) when they die.
## Also: sound broadcast, the camera rotation (cached per frame), cheap separation vectors and
## the corpse cap.

static var list: Array[Node2D] = []
## Dead enemies whose corpse is baked into the decal layer: their (now empty) nodes are freed a
## couple per frame (Enemies.reap, called by Fx), never in one burst.
static var corpses := 0
static var _reap: Array = []
static var _cam_frame := -1
static var _cam_rot := 0.0


static func add(n: Node2D) -> void:
	if not list.has(n):
		list.append(n)
		n.tree_exiting.connect(remove.bind(n), CONNECT_ONE_SHOT)


static func remove(n: Node2D) -> void:
	list.erase(n)


static func count() -> int:
	return list.size()


static func clear() -> void:
	list.clear()
	_reap.clear()


## A dead enemy's corpse is baked into the decal layer: the node can go (queued, freed over frames).
static func add_corpse(n: Node2D) -> void:
	corpses += 1
	_reap.append(n)


static func reap(max_n: int) -> void:
	while max_n > 0 and not _reap.is_empty():
		var n: Variant = _reap.pop_front()
		if is_instance_valid(n) and not (n as Node).is_queued_for_deletion():
			(n as Node).queue_free()
			max_n -= 1


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


## Small overlay child of an enemy (the charger's lane / dust); `fn` draws it. Hidden until needed.
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
