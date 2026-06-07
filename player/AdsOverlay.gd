extends CanvasLayer

const _SHADER := preload("res://player/fov.gdshader")

const _HF_HALF_ANGLE := 0.90   # radians (~104° total cone)
const _HF_DARK       := 0.88
const _ADS_DARK      := 0.93
const _TWEEN_DUR     := 0.12

var _vignette: ColorRect
var _reticle: AdsReticle
var _mat: ShaderMaterial
var _tween: Tween = null
var _player: Player = null

func _ready() -> void:
	layer = 4
	visible = true
	_build()

func setup(player: Player) -> void:
	_player = player

func _build() -> void:
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = _SHADER
	_mat.set_shader_parameter("sight_half_angle", _HF_HALF_ANGLE)
	_mat.set_shader_parameter("dark_alpha",       _HF_DARK)
	_vignette.material = _mat
	add_child(_vignette)

	_reticle = AdsReticle.new()
	_reticle.visible = false
	add_child(_reticle)

func show_ads(sight: SightData, raise_time: float = _TWEEN_DUR) -> void:
	_tween_cone(sight.fov_radius, _ADS_DARK, raise_time)
	_reticle.set_type(sight.reticle_type)
	_reticle.visible = true

func hide_ads() -> void:
	_tween_cone(_HF_HALF_ANGLE, _HF_DARK, _TWEEN_DUR)
	_reticle.visible = false

func _process(_dt: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect_ratio", vp.x / vp.y)
	_reticle.position = vp * 0.5

	if _player == null:
		return

	var ct := get_viewport().get_canvas_transform()
	var player_screen := ct * _player.global_position
	_mat.set_shader_parameter("player_uv", player_screen / vp)

	var fwd_world  := _player.global_position + Vector2.UP.rotated(_player.facing_angle)
	var fwd_screen := ct * fwd_world
	var dir        := (fwd_screen - player_screen).normalized()
	_mat.set_shader_parameter("facing_angle", atan2(dir.x, -dir.y))

func _tween_cone(half_angle: float, dark: float, duration: float) -> void:
	if _tween != null:
		_tween.kill()
	var cur_a := float(_mat.get_shader_parameter("sight_half_angle"))
	var cur_k := float(_mat.get_shader_parameter("dark_alpha"))
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(
		func(v: float): _mat.set_shader_parameter("sight_half_angle", v),
		cur_a, half_angle, duration)
	_tween.tween_method(
		func(v: float): _mat.set_shader_parameter("dark_alpha", v),
		cur_k, dark, duration)
