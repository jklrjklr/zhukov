extends CanvasLayer

const _SHADER := preload("res://player/ads_vignette.gdshader")

const _HF_RADIUS := 0.58
const _HF_DARK   := 0.60
const _ADS_DARK  := 0.93
const _TWEEN_DUR := 0.12

var _vignette: ColorRect
var _reticle: AdsReticle
var _mat: ShaderMaterial
var _tween: Tween = null

func _ready() -> void:
	layer = 4
	visible = true
	_build()

func _build() -> void:
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = _SHADER
	_mat.set_shader_parameter("circle_radius", _HF_RADIUS)
	_mat.set_shader_parameter("dark_alpha",    _HF_DARK)
	_vignette.material = _mat
	add_child(_vignette)

	_reticle = AdsReticle.new()
	_reticle.visible = false
	add_child(_reticle)

func show_ads(sight: SightData, raise_time: float = _TWEEN_DUR) -> void:
	_tween_params(sight.fov_radius, _ADS_DARK, raise_time)
	_reticle.set_type(sight.reticle_type)
	_reticle.visible = true

func hide_ads() -> void:
	_tween_params(_HF_RADIUS, _HF_DARK)
	_reticle.visible = false

func _process(_dt: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect_ratio", vp.x / vp.y)
	_reticle.position = vp * 0.5

func _tween_params(radius: float, dark: float, duration: float = _TWEEN_DUR) -> void:
	if _tween != null:
		_tween.kill()
	var cur_r := float(_mat.get_shader_parameter("circle_radius"))
	var cur_d := float(_mat.get_shader_parameter("dark_alpha"))
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(
		func(v: float): _mat.set_shader_parameter("circle_radius", v),
		cur_r, radius, duration)
	_tween.tween_method(
		func(v: float): _mat.set_shader_parameter("dark_alpha", v),
		cur_d, dark, duration)
