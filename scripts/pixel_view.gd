class_name PixelView
extends Control
## Renders the world (children of the SubViewport) into a low-res buffer
## (Vis.PIXEL_HEIGHT tall) and draws it scaled up to fill the screen.
##
## - Cheap: the world costs fragments at buffer size, not at the phone's native resolution;
##   the upscale is one full-screen quad.
## - Crisp: the buffer uses nearest filtering; the upscale shader (pixel_upscale.gdshader)
##   keeps pixels square but blends their edges over one screen pixel, so non-integer
##   scales and the rotating camera don't shimmer.
## - Smooth: the canvas transform is snapped to whole buffer pixels (stable pixel grid) and
##   the leftover fraction shifts the upscaled image instead, so the camera still glides at
##   sub-pixel speed. The buffer has a MARGIN on each side so the shift never shows an edge.
## UI lives outside (root viewport, native resolution) so text and controls stay sharp.

const MARGIN := 2

var _vp: SubViewport
var _scale := 1.0
var _frac := Vector2.ZERO
var _cam: Node2D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR # the shader needs bilinear taps
	process_priority = 100 # after the camera has moved this frame
	_vp = get_child(0) as SubViewport
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_vp.handle_input_locally = false
	_vp.gui_disable_input = true
	_vp.physics_object_picking = false
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/pixel_upscale.gdshader")
	material = mat
	resized.connect(_resize)
	_resize()


## Buffer pixel size (without the margin) for the current screen.
func buffer_size() -> Vector2i:
	return _vp.size - Vector2i(MARGIN, MARGIN) * 2


func _resize() -> void:
	if _vp == null or size.y <= 0.0:
		return
	_scale = size.y / Vis.PIXEL_HEIGHT
	var w := ceili(size.x / _scale)
	_vp.size = Vector2i(w + MARGIN * 2, Vis.PIXEL_HEIGHT + MARGIN * 2)


func _process(_delta: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_tree().get_first_node_in_group("view_camera") as Node2D
	if _cam:
		var center := Vector2(_vp.size) / 2.0
		var xf := Transform2D(0.0, Vector2.ONE * float(_cam.get("zoom")), 0.0, center) \
			* _cam.global_transform.affine_inverse()
		var snapped := xf.origin.round()
		_frac = xf.origin - snapped
		xf.origin = snapped
		_vp.canvas_transform = xf
	queue_redraw()


func _draw() -> void:
	var tex := _vp.get_texture()
	var vs := Vector2(_vp.size) * _scale
	draw_texture_rect(tex, Rect2((size - vs) / 2.0 + _frac * _scale, vs), false)
