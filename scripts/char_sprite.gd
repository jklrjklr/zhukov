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
## Mirror left/right (free variety for dives and deaths).
var flip := false
## Carries a weapon: plays the *_aim clips and draws the gun in the hands (per-frame anchors
## art/sprites/<skin>/<clip>.json from the bake: grip offset px, gun angle).
var armed := false
## Gun art in sprite pixels (placeholder rifle): length ahead of the grip, behind it, width.
const GUN_FRONT := 22
const GUN_BACK := 6
const GUN_W := 3
## Death variants by fall direction (baked by tools/bake_sprites.gd).
const DEATHS := {
	"back": ["death_back0", "death_back1", "death_back2"],
	"fwd": ["death_fwd0", "death_fwd1", "death_fwd2"],
	"crumple": ["death_crumple0", "death_crumple1"],
}
var _once_t := -1.0
var _once_dur := 1.0

var _sheets := {}
var _anchors := {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)
	for a in ["idle", "run", "idle_aim", "run_aim"] if armed else ["idle", "run"]:
		_sheet(a)


func _sheet(a: String) -> Texture2D:
	if not _sheets.has(a):
		_sheets[a] = load("res://art/sprites/%s/%s.png" % [skin, a])
		var jp := "res://art/sprites/%s/%s.json" % [skin, a]
		_anchors[a] = (load(jp) as JSON).data.frames if ResourceLoader.exists(jp) else []
	return _sheets[a]


## Plays a non-looping clip once over `duration` s, then holds its last frame.
func play_once(a: String, duration: float) -> void:
	_sheet(a)
	anim = a
	phase = 0.0
	_once_t = 0.0
	_once_dur = duration
	set_process(true)


## Picks a death clip for a body pushed along `push` (sprite space: -Y = the way it faces):
## pushed back -> falls on the back, forward -> on the face, sideways -> on that side,
## sometimes it just crumples. Back / face / crumple variants are mirrored at random.
func play_death(push: Vector2, duration := 0.75) -> void:
	var d := push.normalized()
	var clip: String
	if randf() < 0.2:
		clip = DEATHS.crumple.pick_random()
	elif absf(d.x) > 0.75:
		clip = "death_left" if d.x > 0.0 else "death_right"
	elif d.y > 0.0:
		clip = DEATHS.back.pick_random()
	else:
		clip = DEATHS.fwd.pick_random()
	flip = not clip.begins_with("death_left") and not clip.begins_with("death_right") and randf() < 0.5
	play_once(clip, duration)


func _process(delta: float) -> void:
	if _once_t < 0.0:
		set_process(false)
		return
	_once_t += delta
	phase = minf(_once_t / _once_dur, 0.999)
	if _once_t >= _once_dur:
		_once_t = -1.0
	queue_redraw()


## Shows a non-looping clip (dive) at phase 0..1 (clamped).
func show_clip(a: String, p: float) -> void:
	anim = a
	phase = clampf(p, 0.0, 0.999)
	queue_redraw()


## Picks the clip from the owner's speed and advances it (call once per tick).
func advance(delta: float, speed: float) -> void:
	var a := ("run" if speed > MOVE_THRESHOLD else "idle") + ("_aim" if armed else "")
	if a != anim:
		anim = a
		phase = 0.0
	phase = fposmod(phase + (speed * delta / RUN_PX_PER_CYCLE if a == "run" else delta / IDLE_LOOP), 1.0)
	queue_redraw()


func _draw() -> void:
	var tex: Texture2D = _sheet(anim)
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
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(-s if flip else s, s))
	if armed:
		_draw_gun(i)
	draw_texture_rect_region(tex, Rect2(-f / 2.0, -f / 2.0, f, f), Rect2(i * f, 0, f, f))


## Gun under the arms (hands and head cover its middle), at the frame's anchor.
func _draw_gun(i: int) -> void:
	var frames: Array = _anchors.get(anim, [])
	if i >= frames.size():
		return
	var a: Array = frames[i]
	var at := Vector2(a[0], a[1]).round()
	# Anchors point the gun straight ahead (-Y), so it stays on the pixel grid.
	var body := Rect2(at.x - 1, at.y - GUN_FRONT, GUN_W, GUN_FRONT + GUN_BACK)
	draw_rect(body.grow(1), Pal.INK)
	draw_rect(body, Pal.GUN)
	draw_rect(Rect2(at.x - 1, at.y - GUN_FRONT, 1, GUN_FRONT + GUN_BACK), Pal.GUN_LIGHT)
	draw_rect(Rect2(at.x - 2, at.y - 9, 1, 4), Pal.INK) # magazine
	draw_rect(Rect2(at.x, at.y - GUN_FRONT - 3, 1, 3), Pal.INK) # muzzle
