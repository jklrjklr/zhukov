extends Control
## Title screen: DEPLOY (sample mission), FIRING RANGE. Helldivers-style dressing.

var _buttons := {}
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _input(event: InputEvent) -> void:
	var t := event as InputEventScreenTouch
	if t == null or not t.pressed:
		return
	for k in _buttons:
		if (_buttons[k] as Rect2).has_point(t.position):
			match k:
				"deploy":
					Game.start_mission()
				"range":
					Game.start_range()
			return


func _draw() -> void:
	_buttons.clear()
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.065, 0.06))
	# Hazard stripes along the bottom and a slow scan line.
	var stripe_y := vp.y - 26
	draw_rect(Rect2(0, stripe_y, vp.x, 26), UiStyle.YELLOW)
	var x := -fmod(_t * 30.0, 60.0)
	while x < vp.x:
		draw_colored_polygon(PackedVector2Array([Vector2(x, vp.y), Vector2(x + 26, stripe_y), Vector2(x + 52, stripe_y), Vector2(x + 26, vp.y)]), Color(0.06, 0.06, 0.06))
		x += 60.0
	var scan := fmod(_t * 120.0, vp.y)
	draw_rect(Rect2(0, scan, vp.x, 2), Color(1, 0.9, 0.06, 0.06))
	# Planet silhouette
	draw_circle(Vector2(vp.x * 0.78, vp.y * 0.45), 210.0, Color(0.13, 0.16, 0.11))
	draw_arc(Vector2(vp.x * 0.78, vp.y * 0.45), 210.0, -2.6, -0.6, 48, Color(1, 0.9, 0.06, 0.25), 3.0)

	var left := vp.x * 0.1
	UiStyle.text(self, Vector2(left, vp.y * 0.26), "zhukov", 84, UiStyle.YELLOW)
	draw_rect(Rect2(left, vp.y * 0.26 + 16, 360, 4), UiStyle.YELLOW)
	UiStyle.text(self, Vector2(left, vp.y * 0.26 + 52), "operation: dead ground", 22, UiStyle.TEXT)
	UiStyle.text(self, Vector2(left, vp.y * 0.26 + 80), "terminals  /  nests  /  extraction", 16, UiStyle.TEXT_DIM)

	var w := 380.0
	_buttons["deploy"] = UiStyle.button(self, Rect2(left, vp.y * 0.5, w, 76), "DEPLOY", true, 30)
	_buttons["range"] = UiStyle.button(self, Rect2(left, vp.y * 0.5 + 96, w, 64), "FIRING RANGE", false, 22)
	UiStyle.text(self, Vector2(left, vp.y - 46), "left: move   right: swipe to aim   hold fire   ads: swipe distance", 14, UiStyle.TEXT_DIM)
