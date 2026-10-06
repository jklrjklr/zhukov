class_name EnemyOverlay
extends Node2D
## ONE shared overlay for every enemy's real-time extras (HP bar, ? / ! badge, ricochet shield,
## telegraphs, damage numbers), replacing two canvas-item nodes per enemy with a few commands each.
## Enemies register while they have something to show (EnemyOverlay.set_active) and implement
## overlay_draw(o, cam); here everything is written into two MultiMeshes per frame:
##  - a ShapeBatch (rectangles, discs, rings, arcs: bars, telegraph rings / lines),
##  - an AtlasBatch with the pre-baked badge textures of the RigAtlas (? at 17 fill levels, !, shield),
## i.e. two draw calls for all enemies whatever their number. Damage numbers (rare) use draw_string
## on this node (strings batch by themselves).
## Screen-aligned pieces (bars, badges) are positioned in "billboard space": local units x
## BILLBOARD_SCALE rotated by -camera rotation around the enemy.

const B := Vis.BILLBOARD_SCALE
const SS := RigAtlas.SS

static var _inst: EnemyOverlay
static var _active: Array = []
static var _set := {}

var shapes: ShapeBatch
var icons: AtlasBatch
var cam := 0.0
var _numbers_on := false
var _atlas_size := Vector2.ONE


static func get_for(from: Node) -> EnemyOverlay:
	if _inst != null and is_instance_valid(_inst) and not _inst.is_queued_for_deletion():
		return _inst
	return attach(from.get_parent() if from.get_parent() != null else from.get_tree().current_scene)


## Create the shared overlay next to the enemies (Warmup does it at mission start).
static func attach(host: Node) -> EnemyOverlay:
	if _inst != null and is_instance_valid(_inst) and not _inst.is_queued_for_deletion():
		return _inst
	_inst = EnemyOverlay.new()
	_inst.name = "EnemyOverlay"
	_inst.z_index = 11
	_inst.z_as_relative = false
	host.add_child.call_deferred(_inst)
	return _inst


## Enemies call this when they start / stop having anything to show.
static func set_active(n: Node2D, on: bool) -> void:
	if on:
		if not _set.has(n):
			_set[n] = true
			_active.append(n)
			get_for(n)
	elif _set.has(n):
		_set.erase(n)
		_active.erase(n)


static func clear() -> void:
	_active.clear()
	_set.clear()


func _init() -> void:
	shapes = ShapeBatch.new(512, false)
	add_child(shapes)
	icons = AtlasBatch.new(RigAtlas.texture(), 128)
	add_child(icons)


func _process(_delta: float) -> void:
	if _active.is_empty() and not _numbers_on:
		if shapes.count() > 0:
			shapes.begin()
			shapes.end()
			icons.frame_begin()
			icons.frame_end()
		return
	cam = Enemies.cam_rot(self)
	_atlas_size = Vector2(RigAtlas.texture().get_size())
	shapes.begin()
	icons.frame_begin()
	var numbers := false
	var i := _active.size() - 1
	while i >= 0:
		var e: Variant = _active[i]
		if not is_instance_valid(e) or (e as Node).is_queued_for_deletion():
			_set.erase(e)
			_active.remove_at(i)
		elif (e as CanvasItem).is_visible_in_tree():
			e.overlay_draw(self)
			if e.overlay_has_numbers():
				numbers = true
		i -= 1
	shapes.end()
	icons.frame_end()
	if numbers or _numbers_on:
		queue_redraw()
	_numbers_on = numbers


func _draw() -> void:
	for e: Variant in _active:
		if is_instance_valid(e) and (e as CanvasItem).is_visible_in_tree() and e.overlay_has_numbers():
			draw_set_transform_matrix(Transform2D(-cam, Vector2(B, B), 0.0, (e as Node2D).global_position))
			e.overlay_numbers(self)


## Billboard-space offset (local units) -> world.
func bb(e: Node2D, v: Vector2) -> Vector2:
	return e.global_position + (v * B).rotated(-cam)


func _bb_box(e: Node2D, r: Rect2, col: Color) -> void:
	shapes.rect(bb(e, r.get_center()), r.size * B, -cam, col)


func hp_bar(e: Node2D, top: float, w: float, h: float, frac: float, a: float, heavy: bool, color_override := Color(0, 0, 0, 0)) -> void:
	var al := e.modulate.a
	var r := Rect2(-w * 0.5, top, w, h)
	_bb_box(e, r.grow(1.5), Color(0, 0, 0, 0.7 * a * al))
	var f := clampf(frac, 0.0, 1.0)
	var col := Color(0.4, 0.9, 0.3, a) if f > 0.5 else (Color(1, 0.8, 0.1, a) if f > 0.25 else Color(0.95, 0.2, 0.15, a))
	if color_override.a > 0.0:
		col = color_override if f > 0.3 else Color(1.0, 0.15, 0.1)
	col.a *= al
	if f > 0.0:
		_bb_box(e, Rect2(r.position, Vector2(r.size.x * f, r.size.y)), col)
	if heavy:
		var oc := Color(1, 1, 1, 0.3 * al)
		_bb_box(e, Rect2(r.position.x - 0.5, r.position.y - 0.5, r.size.x + 1.0, 1.0), oc)
		_bb_box(e, Rect2(r.position.x - 0.5, r.end.y - 0.5, r.size.x + 1.0, 1.0), oc)
		_bb_box(e, Rect2(r.position.x - 0.5, r.position.y + 0.5, 1.0, r.size.y - 1.0), oc)
		_bb_box(e, Rect2(r.end.x - 0.5, r.position.y + 0.5, 1.0, r.size.y - 1.0), oc)


## Thin vertical divider inside a bar (charger HP segments).
func bar_tick(e: Node2D, x: float, top: float, h: float, col: Color) -> void:
	col.a *= e.modulate.a
	_bb_box(e, Rect2(x - 0.5, top, 1.0, h), col)


func _sprite(e: Node2D, key: String, c: Vector2, k: float, col: Color) -> void:
	var ent := RigAtlas.entry(key)
	var r := Rect2(ent.rect)
	var bounds: Rect2 = ent.bounds
	var xf := Transform2D(-cam, Vector2(B * k, B * k), 0.0, bb(e, c)) * Transform2D(Vector2(1.0 / SS, 0), Vector2(0, 1.0 / SS), Vector2.ZERO) \
		* Transform2D(Vector2(r.size.x, 0), Vector2(0, r.size.y), bounds.position * SS)
	icons.frame_push(xf, col, Color(r.position.x / _atlas_size.x, r.position.y / _atlas_size.y, r.size.x / _atlas_size.x, r.size.y / _atlas_size.y))


## Awareness badge: "?" (fill 0..1 = suspicion) or "!" (alert, pops in); size 9 = the baked radius.
func icon(e: Node2D, kind: int, c: Vector2, size: float, fill: float, pop: float) -> void:
	if kind == EnemyUi.Icon.NONE:
		return
	var key := "ui/alert" if kind == EnemyUi.Icon.ALERT else "ui/susp%d" % clampi(int(round(fill * RigAtlas.ICON_LEVELS)), 0, RigAtlas.ICON_LEVELS)
	_sprite(e, key, c, size / 9.0 * pop, Color(1, 1, 1, e.modulate.a))


func shield(e: Node2D, c: Vector2, a: float, k := 1.0) -> void:
	_sprite(e, "ui/shield", c, k, Color(1, 1, 1, a * e.modulate.a))
