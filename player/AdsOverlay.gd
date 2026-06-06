extends CanvasLayer

const _SHADER   := preload("res://player/ads_vignette.gdshader")
const _RETICLE  := preload("res://player/AdsReticle.gd")

var _vignette: ColorRect
var _reticle: Node2D
var _mat: ShaderMaterial

func _ready() -> void:
	layer = 4
	visible = false
	_build()

func _build() -> void:
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = _SHADER
	_vignette.material = _mat
	add_child(_vignette)

	_reticle = Node2D.new()
	_reticle.set_script(_RETICLE)
	add_child(_reticle)

func show_ads(sight: SightData) -> void:
	visible = true
	var vp := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect_ratio",  vp.x / vp.y)
	_mat.set_shader_parameter("circle_radius", sight.fov_radius)
	_reticle.set_type(sight.reticle_type)
	_center_reticle(vp)

func hide_ads() -> void:
	visible = false

func _process(_dt: float) -> void:
	if visible:
		_center_reticle(get_viewport().get_visible_rect().size)

func _center_reticle(vp: Vector2) -> void:
	_reticle.position = vp * 0.5
