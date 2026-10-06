class_name TileLayer
extends Node2D
## Static visuals (ground, detail items, walls, rocks) baked into a few big textures instead of
## thousands of draw commands: circles / arcs / polygons never batch (one draw call EACH), so a
## zone drawn the vector way costs ~2200 calls on screen. The layer is a grid of TILE x TILE px
## tiles (layer-local coordinates). Tiles near the camera are rendered ONCE each into a SubViewport
## (the painter callable draws that tile's part of the layer through a canvas transform of SCALE)
## and shown as one Sprite2D: about 12-20 draw calls on screen whatever the zone contains.
## Tiles further than the prefetch radius are freed (bounded texture memory); baking is spread over
## frames (1 tile per frame in play, a burst on the first call so the mission starts with a ground).
## An Android resume re-renders every live tile (a lost GL render target comes back).

const TILE := 1024.0
const GRID_HALF := 4096.0
const N := 8
## Texels per layer px (matches a 1080p phone at the 0.5 camera zoom: 0.75 screen px per world px).
const SCALE := 0.75
const MARGIN := 8.0
const PREFETCH := 700.0

## paint(canvas: CanvasItem, clip: Rect2) draws everything of the layer intersecting clip (layer-local px).
var paint: Callable
## ready() -> bool: assets the painter needs (async noise textures) exist.
var assets_ready: Callable
var _tiles := {} # Vector2i -> {vp: SubViewport, sprite: Sprite2D, painter: Node2D}
var _first := true
var _cd := 0.0
var _last_center := Vector2(1.0e9, 1.0e9)
var _baked_count := 0
var _tile_cb := 0


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x + GRID_HALF) / TILE)), 0, N - 1), clampi(int(floor((p.y + GRID_HALF) / TILE)), 0, N - 1))


static func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c) * TILE - Vector2(GRID_HALF, GRID_HALF), Vector2(TILE, TILE))


func _ready() -> void:
	set_process(DisplayServer.get_name() != "headless")


func tile_count() -> int:
	return _tiles.size()


func _process(delta: float) -> void:
	if assets_ready.is_valid() and not assets_ready.call():
		return
	_cd -= delta
	var vp := get_viewport()
	var ct := vp.get_canvas_transform()
	var inv := ct.affine_inverse()
	var center := to_local(inv * (vp.get_visible_rect().size * 0.5))
	if _cd > 0.0 and center.distance_squared_to(_last_center) < 64.0 * 64.0:
		return
	_cd = 0.12
	_last_center = center
	var half_diag := inv.basis_xform(vp.get_visible_rect().size).length() * 0.5
	var r_vis := half_diag + 40.0
	var r_load := r_vis + PREFETCH
	var want: Array = []
	var c0 := cell_of(center - Vector2(r_load, r_load))
	var c1 := cell_of(center + Vector2(r_load, r_load))
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			var c := Vector2i(x, y)
			var rc := cell_rect(c)
			var d := _dist_to_rect(center, rc)
			if d <= r_load:
				want.append([d, c])
	want.sort_custom(func(a, b): return a[0] < b[0])
	var budget := 99 if _first else 1
	_first = false
	for w in want:
		if budget <= 0:
			break
		if not _tiles.has(w[1]):
			_bake_tile(w[1])
			budget -= 1
	# Free far tiles, one per update.
	for c in _tiles.keys():
		if _dist_to_rect(center, cell_rect(c)) > r_load + TILE * 1.2:
			_free_tile(c)
			break


static func _dist_to_rect(p: Vector2, r: Rect2) -> float:
	var q := Vector2(maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x), maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y))
	return q.length()


func _bake_tile(c: Vector2i) -> void:
	var rc := cell_rect(c)
	var origin := rc.position - Vector2(MARGIN, MARGIN)
	var px := int(ceil((TILE + MARGIN * 2.0) * SCALE))
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	# Cover the margin exactly: texels per px = px / (TILE + 2 MARGIN).
	var s := float(px) / (TILE + MARGIN * 2.0)
	var xf := Transform2D(Vector2(s, 0), Vector2(0, s), -origin * s)
	vp.tree_entered.connect(func() -> void: vp.canvas_transform = xf)
	add_child(vp)
	var sprite := Sprite2D.new()
	sprite.name = "GroundTile%d_%d" % [c.x, c.y]
	sprite.centered = false
	sprite.position = origin
	sprite.scale = Vector2.ONE / s
	sprite.texture = vp.get_texture()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(sprite)
	var t := {"vp": vp, "sprite": sprite, "painter": null, "rect": Rect2(origin, Vector2(TILE, TILE) + Vector2(MARGIN, MARGIN) * 2.0)}
	_tiles[c] = t
	_paint_tile(t)


func _paint_tile(t: Dictionary) -> void:
	var vp: SubViewport = t.vp
	var painter := Node2D.new()
	painter.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var clip: Rect2 = t.rect
	painter.draw.connect(func() -> void: paint.call(painter, clip))
	vp.add_child(painter)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	t.painter = painter
	_release_painter(t)


## The commands are only needed for the one render: free the painter afterwards (no retained
## recording per tile).
func _release_painter(t: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var p: Node = t.painter
	if is_instance_valid(p):
		p.queue_free()
	t.painter = null


func _free_tile(c: Vector2i) -> void:
	var t: Dictionary = _tiles[c]
	_tiles.erase(c)
	(t.sprite as Node).queue_free()
	(t.vp as Node).queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		for c in _tiles:
			var t: Dictionary = _tiles[c]
			if t.painter == null:
				_paint_tile(t)
