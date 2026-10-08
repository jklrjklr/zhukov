extends SceneTree
## Renders the player-moves preview from the real game scene: 8 walk directions while looking up,
## the 3 run directions, then the 8 dives (relative to the look direction) firing forward.
## The low-res game buffer is cropped around the player and scaled up with nearest filtering (4x).
##   xvfb-run -a gd --path . --rendering-driver opengl3 --fixed-fps 60 \
##     --script res://tools/player_preview.gd -- <out dir>
## Writes <out dir>/f_00000.png ... (30 fps) and captions.txt (start s, end s, text); tools/player_preview.sh
## turns them into docs/preview/player_moves.mp4 / .gif.

const CROP := Vector2i(160, 120)
const SCALE := 4
const NAMES := ["forward", "forward-right", "right", "back-right", "back", "back-left", "left", "forward-left"]

var _out := "/tmp/player_preview"
var _frame := 0
var _shot := 0
var _caps: Array = []
var _p: CharacterBody2D
var _vp: SubViewport


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_p = main.get_node("PixelView/SubViewport/Player")
	_vp = main.get_node("PixelView/SubViewport")
	await _frames(2)
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	_p.auto_fire = false
	await _frames(30)

	for k in 8:
		await _segment("WALK  " + NAMES[k], Vector2.UP.rotated(deg_to_rad(k * 45.0)) * 0.6, 84, false)
	for k in [0, 1, 7]:
		await _segment("RUN  " + NAMES[k], Vector2.UP.rotated(deg_to_rad(k * 45.0)), 84, false)
	for k in 8:
		await _segment("DIVE  " + NAMES[k] + "  (firing forward)", Vector2.UP.rotated(deg_to_rad(k * 45.0)), 110, true)

	var f := FileAccess.open(_out.path_join("captions.txt"), FileAccess.WRITE)
	for c in _caps:
		f.store_line("%.3f|%.3f|%s" % [c[0], c[1], c[2]])
	f.close()
	print("frames ", _shot)
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## One move: the player starts at the origin looking up, holds `stick` for `n` ticks (a dive: starts
## it and fires every tick while airborne), then a short pause.
func _segment(caption: String, stick: Vector2, n: int, dive: bool) -> void:
	_p.move_input = Vector2.ZERO
	_p.global_position = Vector2.ZERO
	_p.velocity = Vector2.ZERO
	_p.look_angle = 0.0
	_p.stamina = 1.0
	await _frames(24)
	var t0 := _shot / 30.0
	_p.move_input = stick
	if dive:
		_p.dive()
	for i in n:
		if dive and _p.is_diving():
			_p.try_attack()
		await _capture()
	_p.move_input = Vector2.ZERO
	for i in 14:
		await _capture()
	_caps.append([t0, _shot / 30.0, caption])


func _capture() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_frame += 1
	if _frame % 2 != 0:
		return
	var img := _vp.get_texture().get_image()
	var at := Vector2i((_vp.canvas_transform * _p.global_position).round())
	var r := Rect2i(at - CROP / 2, CROP)
	r.position = r.position.clamp(Vector2i.ZERO, img.get_size() - CROP)
	var crop := img.get_region(r)
	crop.resize(CROP.x * SCALE, CROP.y * SCALE, Image.INTERPOLATE_NEAREST)
	crop.save_png(_out.path_join("f_%05d.png" % _shot))
	_shot += 1
