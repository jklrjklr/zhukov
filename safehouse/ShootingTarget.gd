class_name ShootingTarget
extends Node2D

signal hit_registered(damage: int, is_headshot: bool)

var hits:         int = 0
var total_damage: int = 0

var _body_vis:  ColorRect = null
var _head_vis:  ColorRect = null
var _count_lbl: Label     = null

const _COL_DEFAULT  := Color(0.62, 0.48, 0.30)
const _COL_HIT      := Color(0.92, 0.20, 0.10)
const _COL_HEADSHOT := Color(1.00, 0.72, 0.00)

func _ready() -> void:
	_build_visuals()
	_build_hurtboxes()

func _build_visuals() -> void:
	_body_vis = ColorRect.new()
	_body_vis.position = Vector2(-18, -60)
	_body_vis.size     = Vector2(36, 60)
	_body_vis.color    = _COL_DEFAULT
	add_child(_body_vis)

	_head_vis = ColorRect.new()
	_head_vis.position = Vector2(-12, -82)
	_head_vis.size     = Vector2(24, 22)
	_head_vis.color    = _COL_DEFAULT
	add_child(_head_vis)

	_count_lbl = Label.new()
	_count_lbl.position = Vector2(-50, -102)
	_count_lbl.size     = Vector2(100, 18)
	_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_lbl.add_theme_font_size_override("font_size", 9)
	_count_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	add_child(_count_lbl)

func _build_hurtboxes() -> void:
	var hb_script := load("res://characters/HurtBox.gd")

	# Body HurtBox
	var body_hb := Area2D.new()
	body_hb.set_script(hb_script)
	var body_col   := CollisionShape2D.new()
	var body_rect  := RectangleShape2D.new()
	body_rect.size     = Vector2(36, 60)
	body_col.position  = Vector2(0, -30)
	body_col.shape     = body_rect
	body_hb.add_child(body_col)
	add_child(body_hb)

	# Head HurtBox
	var head_hb := Area2D.new()
	head_hb.set_script(hb_script)
	head_hb.set("hit_type", 1)   # HurtBox.HitType.HEAD = 1
	var head_col    := CollisionShape2D.new()
	var head_circle := CircleShape2D.new()
	head_circle.radius  = 12.0
	head_col.position   = Vector2(0, -71)
	head_col.shape      = head_circle
	head_hb.add_child(head_col)
	add_child(head_hb)

func take_damage(amount: int, is_headshot: bool) -> void:
	hits         += 1
	total_damage += amount
	hit_registered.emit(amount, is_headshot)

	var flash_col := _COL_HEADSHOT if is_headshot else _COL_HIT
	_body_vis.color = flash_col
	_head_vis.color = flash_col

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_body_vis, "color", _COL_DEFAULT, 0.20)
	t.tween_property(_head_vis, "color", _COL_DEFAULT, 0.20)

	_count_lbl.text = "%d hits" % hits

func reset() -> void:
	hits         = 0
	total_damage = 0
	_body_vis.color = _COL_DEFAULT
	_head_vis.color = _COL_DEFAULT
	_count_lbl.text = ""
