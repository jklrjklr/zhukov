class_name Interactable
extends StaticBody2D
## Something the player holds INTERACT on: radio terminal, extraction console, ammo box.
## Progress fills while held in reach; at hold_time it fires `activated`.

signal activated(it: Interactable)

enum Kind { TERMINAL, EXTRACT_CONSOLE, AMMO }

@export var kind := Kind.TERMINAL
@export var hold_time := 6.0
## m from the player.
@export var reach_m := 2.2
@export var label := "ACTIVATE TERMINAL"
## Disabled ones can't be used (e.g. extraction before objectives are done).
@export var enabled := true

var progress := 0.0
var used := false
var _blink := 0.0


static func make(k: Kind) -> Interactable:
	var it := Interactable.new()
	it.kind = k
	match k:
		Kind.TERMINAL:
			it.hold_time = 6.0
			it.label = "ACTIVATE TERMINAL"
		Kind.EXTRACT_CONSOLE:
			it.hold_time = 2.0
			it.label = "CALL EXTRACTION"
			it.enabled = false
		Kind.AMMO:
			it.hold_time = 0.6
			it.label = "RESUPPLY"
			it.reach_m = 1.8
	return it


func _ready() -> void:
	add_to_group("interactables")
	var col := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(34, 26) if kind != Kind.AMMO else Vector2(30, 22)
	col.shape = r
	add_child(col)


func usable() -> bool:
	return enabled and not used


func hold(delta: float, _by: Node) -> void:
	if not usable():
		return
	progress += delta
	if progress >= hold_time:
		progress = hold_time
		used = true
		activated.emit(self)
		queue_redraw()


func _process(delta: float) -> void:
	_blink += delta
	queue_redraw()


func _draw() -> void:
	var outline := Color(0.08, 0.08, 0.08)
	match kind:
		Kind.TERMINAL, Kind.EXTRACT_CONSOLE:
			draw_rect(Rect2(-18.5, -14.5, 37, 29), outline)
			draw_rect(Rect2(-17, -13, 34, 26), Color(0.32, 0.34, 0.33))
			var screen := Color(0.2, 0.9, 0.4) if used else (UiStyle.YELLOW if enabled else Color(0.4, 0.4, 0.4))
			if enabled and not used and int(_blink * 2.0) % 2 == 0:
				screen = screen.darkened(0.4)
			draw_rect(Rect2(-12, -9, 24, 12), screen)
			if kind == Kind.TERMINAL:
				draw_line(Vector2(10, -13), Vector2(16, -30), outline, 3.0) # antenna
				draw_circle(Vector2(16, -30), 3.0, Color(0.9, 0.2, 0.15) if not used else Color(0.2, 0.9, 0.4))
		Kind.AMMO:
			var c := Color(0.25, 0.35, 0.2) if not used else Color(0.18, 0.2, 0.17)
			draw_rect(Rect2(-16.5, -12.5, 33, 25), outline)
			draw_rect(Rect2(-15, -11, 30, 22), c)
			if not used:
				for i in 3:
					draw_line(Vector2(-12 + i * 9, -11), Vector2(-6 + i * 9, 11), UiStyle.YELLOW, 3.0)
