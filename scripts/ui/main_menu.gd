extends Control
## Super Destroyer bridge: title screen -> loadout -> launch hellpod.
## Loadout: one primary weapon and up to 4 stratagems (Game.loadout).

const MAX_STRATAGEMS := 4

var _screen := "title"
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
	var hit := ""
	for k in _buttons:
		if (_buttons[k] as Rect2).has_point(t.position):
			hit = k
			break
	if hit == "":
		return
	if hit == "deploy":
		_screen = "loadout"
	elif hit == "range":
		Game.start_range()
	elif hit == "back":
		_screen = "title"
	elif hit == "launch":
		Game.start_mission()
	elif hit.begins_with("primary:"):
		Game.loadout.primary = hit.substr(8)
	elif hit.begins_with("strat:"):
		var id := hit.substr(6)
		var list: Array = Game.loadout.stratagems
		if list.has(id):
			list.erase(id)
		elif list.size() < MAX_STRATAGEMS:
			list.append(id)


func _draw() -> void:
	_buttons.clear()
	var vp := get_viewport_rect().size
	_draw_backdrop(vp)
	if _screen == "title":
		_draw_title(vp)
	else:
		_draw_loadout(vp)


func _draw_backdrop(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.05, 0.055, 0.06))
	var stripe_y := vp.y - 26
	draw_rect(Rect2(0, stripe_y, vp.x, 26), UiStyle.YELLOW)
	var x := -fmod(_t * 30.0, 60.0)
	while x < vp.x:
		draw_colored_polygon(PackedVector2Array([Vector2(x, vp.y), Vector2(x + 26, stripe_y), Vector2(x + 52, stripe_y), Vector2(x + 26, vp.y)]), Color(0.06, 0.06, 0.06))
		x += 60.0
	draw_rect(Rect2(0, fmod(_t * 120.0, vp.y), vp.x, 2), Color(1, 0.9, 0.06, 0.05))
	# Planet below the destroyer window
	var pc := Vector2(vp.x * 0.78, vp.y * 0.48)
	draw_circle(pc, 220.0, Color(0.16, 0.12, 0.08))
	draw_circle(pc + Vector2(-40, -30), 160.0, Color(0.2, 0.15, 0.09))
	draw_arc(pc, 220.0, -2.6, -0.6, 48, Color(1, 0.6, 0.2, 0.3), 3.0)
	if _screen == "title":
		UiStyle.text(self, pc + Vector2(-110, 250), "automaton occupied zone", 14, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, 220)


func _draw_title(vp: Vector2) -> void:
	var left := vp.x * 0.08
	UiStyle.text(self, Vector2(left, vp.y * 0.2), "super destroyer", 20, UiStyle.TEXT_DIM)
	UiStyle.text(self, Vector2(left, vp.y * 0.2 + 78), "zhukov", 84, UiStyle.YELLOW)
	draw_rect(Rect2(left, vp.y * 0.2 + 94, 380, 4), UiStyle.YELLOW)
	UiStyle.text(self, Vector2(left, vp.y * 0.2 + 128), "helldivers mobile ops", 22, UiStyle.TEXT)
	UiStyle.text(self, Vector2(left, vp.y * 0.2 + 154), "spread managed democracy", 15, UiStyle.TEXT_DIM)
	var w := 380.0
	_buttons["deploy"] = UiStyle.button(self, Rect2(left, vp.y * 0.55, w, 76), "DEPLOY", true, 30)
	_buttons["range"] = UiStyle.button(self, Rect2(left, vp.y * 0.55 + 96, w, 60), "FIRING RANGE", false, 22)
	UiStyle.text(self, Vector2(left, vp.y - 44), "left: move  /  push stick to sprint  /  swipe right side to aim  /  strat: swipe the code", 13, UiStyle.TEXT_DIM)


func _draw_loadout(vp: Vector2) -> void:
	var left := vp.x * 0.06
	UiStyle.text(self, Vector2(left, 70), "loadout", 40, UiStyle.YELLOW)
	UiStyle.text(self, Vector2(left, 100), Mission.NAME, 16, UiStyle.TEXT_DIM)

	UiStyle.text(self, Vector2(left, 150), "primary", 16, UiStyle.TEXT_DIM)
	var x := left
	for path in Game.PRIMARIES:
		var st := load(path) as FirearmStats
		var sel: bool = Game.loadout.primary == path
		var r := Rect2(x, 162, 300, 92)
		UiStyle.panel(self, r, Color(1, 0.9, 0.06, 0.18) if sel else UiStyle.PANEL_SOLID)
		UiStyle.panel_outline(self, r, UiStyle.YELLOW if sel else Color(1, 1, 1, 0.2))
		UiStyle.text(self, r.position + Vector2(16, 30), st.display_name, 20, UiStyle.YELLOW if sel else UiStyle.TEXT)
		UiStyle.text(self, r.position + Vector2(16, 56), "%d dmg  %d rpm  %d rds" % [st.damage, st.rpm, st.mag_size], 14, UiStyle.TEXT_DIM)
		UiStyle.text(self, r.position + Vector2(16, 78), "ap %d  ergo %d" % [st.armor_penetration, st.ergonomics], 14, UiStyle.TEXT_DIM)
		_buttons["primary:" + path] = r
		x += 320

	var picked: Array = Game.loadout.stratagems
	UiStyle.text(self, Vector2(left, 290), "stratagems  %d/%d" % [picked.size(), MAX_STRATAGEMS], 16, UiStyle.TEXT_DIM)
	var i := 0
	for id in Stratagems.DEFS:
		var def: Dictionary = Stratagems.DEFS[id]
		var sel := picked.has(id)
		var r := Rect2(left + (i % 3) * 330, 302 + (i / 3) * 96, 310, 84)
		UiStyle.panel(self, r, Color(def.color, 0.22) if sel else UiStyle.PANEL_SOLID)
		UiStyle.panel_outline(self, r, def.color if sel else Color(1, 1, 1, 0.2))
		draw_rect(Rect2(r.position + Vector2(14, 14), Vector2(26, 26)), def.color)
		UiStyle.text(self, r.position + Vector2(52, 34), def.name, 15, UiStyle.TEXT if sel else UiStyle.TEXT_DIM)
		var code: Array = def.code
		for j in code.size():
			var c := r.position + Vector2(60 + j * 22, 62)
			var v: Vector2 = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT][int(code[j])]
			var side := v.orthogonal()
			draw_colored_polygon(PackedVector2Array([c + v * 7.0, c - v * 5.0 + side * 6.0, c - v * 5.0 - side * 6.0]),
				UiStyle.YELLOW if sel else UiStyle.TEXT_DIM)
		_buttons["strat:" + id] = r
		i += 1

	_buttons["launch"] = UiStyle.button(self, Rect2(vp.x - 360, vp.y - 140, 320, 76), "LAUNCH HELLPOD", true, 26)
	_buttons["back"] = UiStyle.button(self, Rect2(vp.x - 560, vp.y - 140, 180, 76), "BACK", false, 22)
