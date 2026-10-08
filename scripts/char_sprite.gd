class_name CharSprite
extends Node2D
## Draws a character from pre-rendered top-down sprite sheets (tools/bake_sprites.gd):
## art/sprites/<skin>/<anim>.png, one row of square frames (size = sheet height), facing up (-Y).
## One sprite pixel = one buffer pixel at the base camera zoom.

## Base frame size in pixels (idle / run) and model units per pixel used by the bake.
const FRAME := 64
const PX_PER_UNIT := 18.0

## Locomotion clips (mocap): world px travelled per loop (stride matching, no foot sliding).
## 1 model unit = PX_PER_UNIT buffer px = PX_PER_UNIT / CAM_ZOOM world px.
const UNIT_PX := PX_PER_UNIT / Vis.CAM_ZOOM
const CYCLE_PX := {"walk": 1.42 * UNIT_PX} # zombies (unarmed)
## Armed locomotion clips walk_<tag> / run_<tag>: 8 directions relative to the look direction,
## clockwise from forward. Their stride (model units per loop, measured by the bake from the
## planted feet) is in <clip>.json.
const TAGS := ["f", "fr", "r", "br", "b", "bl", "l", "fl"]
## Directions (indices into TAGS) where running is allowed: forward, forward-right, forward-left.
const RUN_DIRS := [0, 1, 7]
## Hand-keyed dives dive_<k>, k = dive direction relative to the look direction (same indices).
## Idle loop length (s).
const IDLE_LOOP := 41.0 / 30.0
## Below this speed (world px/s) the idle clip plays; above RUN_SPEED forward is a run.
const MOVE_THRESHOLD := 20.0
const RUN_SPEED := 135.0

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
var armed := false:
	set(v):
		armed = v
		if v and anim == "idle":
			anim = "idle_aim"
		if is_node_ready():
			_preload()
## Gun art in sprite pixels (placeholder rifle): length ahead of the grip, behind it, width.
const GUN_FRONT := 22
const GUN_BACK := 8
const GUN_W := 3
## Ragdoll deaths baked per push direction (8, 45 deg apart, 0 = pushed back / screen-down,
## clockwise) x variants: death_d<dir>_<variant>.
const DEATH_DIRS := 8
const DEATH_VARIANTS := 3
var _once_t := -1.0
var _once_dur := 1.0

var _sheets := {}
var _anchors := {}
var _strides := {}
## Key-pose timing: clip -> phase (0..1) at which each frame starts (frames hold until the next).
var _starts := {}
## Per-instance phase offset and pace so a crowd doesn't move in lockstep.
var phase_offset := 0.0
var pace := 1.0
## Cropped sheets: clip -> {frame (full frame size), frames_n, rect [x, y, w, h]}.
var _crops := {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)
	# Deferred: the owner (player) sets `armed` in its own _ready, after this one.
	_preload.call_deferred()


## Loads the sheets the idle / walk states need. Armed skins only have the *_aim clips baked,
## unarmed ones only idle / walk: asking for the wrong set is a missing-file error.
func _preload() -> void:
	for a in (["idle_aim", "walk_f", "run_f"] if armed else ["idle", "walk"]):
		_sheet(a)


func _sheet(a: String) -> Texture2D:
	if not _sheets.has(a):
		_sheets[a] = load("res://art/sprites/%s/%s.png" % [skin, a])
		var jp := "res://art/sprites/%s/%s.json" % [skin, a]
		var meta: Dictionary = (load(jp) as JSON).data if ResourceLoader.exists(jp) else {}
		_anchors[a] = meta.get("frames", [])
		_starts[a] = meta.get("starts", [])
		if meta.has("stride"):
			_strides[a] = float(meta.stride) * UNIT_PX
		if meta.has("rect"):
			_crops[a] = meta
	return _sheets[a]


## Plays a non-looping clip once over `duration` s, then holds its last frame.
func play_once(a: String, duration: float) -> void:
	_sheet(a)
	anim = a
	phase = 0.0
	_once_t = 0.0
	_once_dur = duration
	set_process(true)


## Plays a ragdoll death for a body pushed along `push` (sprite space: -Y = the way it faces):
## the nearest of the 8 baked directions, a random variant.
func play_death(push: Vector2, duration := 0.75) -> void:
	var k := posmod(roundi(rad_to_deg(atan2(push.x, push.y)) / (360.0 / DEATH_DIRS)), DEATH_DIRS)
	flip = false
	play_once("death_d%d_%d" % [k, randi() % DEATH_VARIANTS], duration)


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


## Direction index (0..7, clockwise from forward, TAGS) of `v` in look space (-Y = forward),
## snapped to the nearest 45 degrees.
static func dir_index(v: Vector2) -> int:
	return posmod(roundi(rad_to_deg(atan2(v.x, -v.y)) / 45.0), 8)


## Unit vector of direction index `k` in look space (-Y = forward).
static func dir_vector(k: int) -> Vector2:
	return Vector2.UP.rotated(deg_to_rad(k * 45.0))


func _cycle_px(a: String) -> float:
	return CYCLE_PX.get(a, _strides.get(a, 0.0))


func _is_cycle(a: String) -> bool:
	return a.begins_with("walk") or a.begins_with("run")


## Armed locomotion: walk_<tag> / run_<tag> for direction `idx` (0..7 relative to the look
## direction), played by distance travelled (`speed` world px/s) so the feet stay planted.
## Running only exists in the three forward directions; any other direction walks.
func advance_dir(delta: float, speed: float, idx: int, running: bool) -> void:
	var a := "idle_aim"
	if speed > MOVE_THRESHOLD:
		a = ("run_" if running and idx in RUN_DIRS else "walk_") + TAGS[idx]
	_play_loop(a, delta, speed)


## Picks the locomotion clip from the owner's velocity in sprite space (-Y = facing, world
## px/s) and advances it by distance travelled (call once per tick). Unarmed (zombies).
func advance(delta: float, vel: Vector2) -> void:
	var speed := vel.length()
	if armed:
		advance_dir(delta, speed, dir_index(vel), speed > RUN_SPEED)
		return
	_play_loop("walk" if speed > MOVE_THRESHOLD else "idle", delta, speed)


func _play_loop(a: String, delta: float, speed: float) -> void:
	if a != anim:
		# Keep the step phase across walk / run / direction switches (clips are phase-aligned).
		if not (_is_cycle(anim) and _is_cycle(a)):
			phase = 0.0
		anim = a
		_sheet(a)
	var c := _cycle_px(a)
	if c > 0.0:
		phase = fposmod(phase + speed * delta / c, 1.0)
	else:
		phase = fposmod(phase + delta * pace / IDLE_LOOP, 1.0)
	queue_redraw()


## Tip of the gun in sprite pixels (facing up) for the frame on screen, or INF without a weapon.
func muzzle_local() -> Vector2:
	var tex: Texture2D = _sheet(anim)
	if tex == null or not armed:
		return Vector2.INF
	var n := tex.get_width() / tex.get_height()
	if _crops.has(anim):
		n = int((_crops[anim] as Dictionary).frames_n)
	var frames: Array = _anchors.get(anim, [])
	var i := _frame_at(anim, n)
	if i >= frames.size():
		return Vector2.INF
	var a: Array = frames[i]
	if a.size() > 3 and int(a[3]) == 0:
		return Vector2.INF # gun slung (rolling on the ground)
	var p := Vector2(a[0], a[1]).round() + Vector2(0, -GUN_FRONT - 3)
	return Vector2(-p.x if flip else p.x, p.y)


func _draw() -> void:
	var tex: Texture2D = _sheet(anim)
	if tex == null:
		return
	var f := tex.get_height()
	var n := tex.get_width() / f
	var src_w := f
	var dst := Rect2(-f / 2.0, -f / 2.0, f, f)
	if _crops.has(anim):
		var c: Dictionary = _crops[anim]
		var full: float = c.frame
		var r: Array = c.rect
		n = int(c.frames_n)
		src_w = int(r[2])
		dst = Rect2(r[0] - full / 2.0, r[1] - full / 2.0, r[2], r[3])
	var i := _frame_at(anim, n)
	# Undo the parent's scale so one texel = one buffer pixel (1 / CAM_ZOOM world px).
	var s := 1.0 / Vis.CAM_ZOOM / global_scale.x
	# Drop shadow, offset in world space (light from the top-left of the world).
	# Drop shadow while upright (a ragdoll corpse lies on the ground and has moved off its origin).
	if not anim.begins_with("death"):
		var sh := Vector2(4, 5) * (1.0 + lift * 2.5)
		draw_set_transform(sh.rotated(-global_rotation) / global_scale.x, 0.0, Vector2(13, 11) * (1.0 - lift * 0.25) / global_scale.x)
		draw_circle(Vector2.ZERO, 1.0, Color(Pal.SHADOW, Pal.SHADOW.a * (1.0 - lift * 0.4)))
	s *= 1.0 + lift * 0.18
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(-s if flip else s, s))
	if armed:
		_draw_gun(i)
	draw_texture_rect_region(tex, dst, Rect2(i * src_w, 0, src_w, dst.size.y))


## Frame shown at the current phase: the last key pose that started at or before it (key
## timing from the bake), or evenly spaced frames for sheets without starts. Looping clips
## use the per-instance offset.
func _frame_at(a: String, n: int) -> int:
	var looping := not (a.begins_with("death") or a.begins_with("dive"))
	var p := fposmod(phase + (phase_offset if looping else 0.0), 1.0) if looping else clampf(phase, 0.0, 0.999)
	var st: Array = _starts.get(a, [])
	if st.size() != n:
		return clampi(int(p * n), 0, n - 1)
	var i := n - 1 if looping else 0
	for j in n:
		if p >= float(st[j]):
			i = j
	return i


## Gun under the arms (hands and head cover its middle), at the frame's anchor.
func _draw_gun(i: int) -> void:
	var frames: Array = _anchors.get(anim, [])
	if i >= frames.size():
		return
	var a: Array = frames[i]
	if a.size() > 3 and int(a[3]) == 0:
		return
	var at := Vector2(a[0], a[1]).round()
	# Anchors point the gun straight ahead (-Y), so it stays on the pixel grid.
	var body := Rect2(at.x - 1, at.y - GUN_FRONT, GUN_W, GUN_FRONT + GUN_BACK)
	draw_rect(body.grow(1), Pal.INK)
	draw_rect(body, Pal.GUN)
	draw_rect(Rect2(at.x - 1, at.y - GUN_FRONT, 1, GUN_FRONT + GUN_BACK), Pal.GUN_LIGHT)
	draw_rect(Rect2(at.x - 2, at.y - 9, 1, 4), Pal.INK) # magazine
	draw_rect(Rect2(at.x, at.y - GUN_FRONT - 3, 1, 3), Pal.INK) # muzzle
