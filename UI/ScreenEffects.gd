class_name ScreenEffects
extends CanvasLayer

const _SHADER := preload("res://UI/screen_effects.gdshader")

var _mat: ShaderMaterial

func _ready() -> void:
	layer = 5  # below PauseMenu (layer 10), above game world
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = _SHADER
	rect.material = _mat
	add_child(rect)

func set_brightness(value: float) -> void:
	_mat.set_shader_parameter("brightness", value)

func set_contrast(value: float) -> void:
	_mat.set_shader_parameter("contrast", value)
