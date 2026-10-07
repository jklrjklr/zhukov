class_name CharSprite
extends Node2D
## Draws a character from pre-rendered top-down sprite sheets (tools/bake_sprites.gd):
## art/sprites/<skin>/<anim>.png, one row of square frames (size = sheet height), facing up (-Y).
## One sprite pixel = one buffer pixel at the base camera zoom.

## Base frame size in pixels (idle / run) and model units per pixel used by the bake.
const FRAME := 64
const PX_PER_UNIT := 18.0

## World px travelled per run cycle (two steps) and idle loop length (s), matching the clips.
const RUN_PX_PER_CYCLE := 170.0
const IDLE_LOOP := 1.07
## Below this speed (world px/s) the idle clip plays.
const MOVE_THRESHOLD := 20.0

@export var skin := "survivorMaleB"
## Current animation and its phase (0..1 over one loop); set by the owner each frame.
var anim := "idle"
var phase := 0.0
## 0..1 airborne height (dive): the body is drawn bigger and the shadow drifts away.
var lift := 0.0

var _sheets := {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for a in ["idle", "run", "dive"]:
		_sheets[a] = load("res://art/sprites/%s/%s.png" % [skin, a])


## Shows a non-looping clip (dive) at phase 0..1 (clamped).
func show_clip(a: String, p: float) -> void:
	anim = a
	phase = clampf(p, 0.0, 0.999)
	queue_redraw()


## Picks the clip from the owner's speed and advances it (call once per tick).
func advance(delta: float, speed: float) -> void:
	var a := "run" if speed > MOVE_THRESHOLD else "idle"
	if a != anim:
		anim = a
		phase = 0.0
	phase = fposmod(phase + (speed * delta / RUN_PX_PER_CYCLE if a == "run" else delta / IDLE_LOOP), 1.0)
	queue_redraw()


func _draw() -> void:
	var tex: Texture2D = _sheets.get(anim)
	if tex == null:
		return
	var f := tex.get_height()
	var n := tex.get_width() / f
	var i := clampi(int(fposmod(phase, 1.0) * n), 0, n - 1)
	# Undo the parent's scale so one texel = one buffer pixel (1 / CAM_ZOOM world px).
	var s := 1.0 / Vis.CAM_ZOOM / global_scale.x
	# Drop shadow, offset in world space (light from the top-left of the world).
	var sh := Vector2(4, 5) * (1.0 + lift * 2.5)
	draw_set_transform(sh.rotated(-global_rotation) / global_scale.x, 0.0, Vector2(13, 11) * (1.0 - lift * 0.25) / global_scale.x)
	draw_circle(Vector2.ZERO, 1.0, Color(Pal.SHADOW, Pal.SHADOW.a * (1.0 - lift * 0.4)))
	s *= 1.0 + lift * 0.18
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	draw_texture_rect_region(tex, Rect2(-f / 2.0, -f / 2.0, f, f), Rect2(i * f, 0, f, f))
