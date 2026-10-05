class_name Interactable
extends StaticBody2D
## Something the player holds INTERACT on: radio terminal, extraction console, ammo box.
## Progress fills while held in reach; at hold_time it fires `activated`.

signal activated(it: Interactable)

enum Kind { TERMINAL, EXTRACT_CONSOLE, AMMO, RESUPPLY_POD, SUPPORT_POD, SAMPLE }

@export var kind := Kind.TERMINAL
@export var hold_time := 6.0
## m from the player.
@export var reach_m := 2.2
@export var label := "ACTIVATE TERMINAL"
## Disabled ones can't be used (e.g. extraction before objectives are done).
@export var enabled := true

var progress := 0.0
var used := false
## Times it can be used (pods hold several boxes / launchers).
var uses := 1
## Support pod: weapon it hands out.
var payload: FirearmStats
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
		Kind.SAMPLE:
			it.hold_time = 0.5
			it.label = "COLLECT SAMPLE"
			it.reach_m = 1.8
		Kind.RESUPPLY_POD:
			it.hold_time = 0.6
			it.label = "TAKE SUPPLIES"
			it.uses = 2
		Kind.SUPPORT_POD:
			it.hold_time = 0.6
			it.label = "TAKE EAT-17"
			it.uses = 2
			it.payload = load("res://weapons/eat17.tres")
	return it


func _ready() -> void:
	add_to_group("interactables")
	var col := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(34, 26) if kind != Kind.AMMO else Vector2(30, 22)
	if kind == Kind.RESUPPLY_POD or kind == Kind.SUPPORT_POD:
		r.size = Vector2(36, 36)
	col.shape = r
	add_child(col)


func usable() -> bool:
	return enabled and not used


func hold(delta: float, _by: Node) -> void:
	if not usable():
		return
	progress += delta
	if progress >= hold_time:
		progress = 0.0
		uses -= 1
		used = uses <= 0
		activated.emit(self)
		queue_redraw()


func _process(delta: float) -> void:
	_blink += delta
	queue_redraw()


func _draw() -> void:
	var outline := Color(0.08, 0.08, 0.08)
	var so := Vector2(6, 8).rotated(-global_rotation)
	if not (kind == Kind.SAMPLE and used):
		draw_rect(Rect2(Vector2(-17, -13) + so, Vector2(34, 27)), Color(0, 0, 0, 0.28))
	match kind:
		Kind.TERMINAL, Kind.EXTRACT_CONSOLE:
			draw_rect(Rect2(-18.5, -14.5, 37, 29), outline)
			draw_rect(Rect2(-17, -13, 34, 26), Color(0.32, 0.34, 0.33))
			var screen := Color(0.2, 0.9, 0.4) if used else (UiStyle.YELLOW if enabled else Color(0.4, 0.4, 0.4))
			if enabled and not used and int(_blink * 2.0) % 2 == 0:
				screen = screen.darkened(0.4)
			draw_rect(Rect2(-12, -9, 24, 12), screen)
			for i in 3: # screen text lines
				draw_line(Vector2(-10, -6 + i * 3.5), Vector2(-10 + 8 + (i * 5) % 10, -6 + i * 3.5), Color(0.05, 0.1, 0.05, 0.6), 1.2)
			for i in 4: # keys
				draw_rect(Rect2(-11 + i * 6, 6, 4, 4), Color(0.15, 0.16, 0.16))
			draw_rect(Rect2(-17, -13, 34, 3), Color(1, 1, 1, 0.12))
			if kind == Kind.TERMINAL:
				draw_line(Vector2(10, -13), Vector2(16, -30), outline, 3.0) # antenna
				draw_circle(Vector2(16, -30), 3.0, Color(0.9, 0.2, 0.15) if not used else Color(0.2, 0.9, 0.4))
		Kind.RESUPPLY_POD, Kind.SUPPORT_POD:
			# Drop pod: round hull, colored fins, hatch.
			var fin := Color(0.25, 0.55, 0.95) if kind == Kind.RESUPPLY_POD else Color(0.3, 0.75, 0.35)
			for i in 4:
				var a := TAU * i / 4.0 + PI / 4.0
				draw_line(Vector2.ZERO, Vector2.from_angle(a) * 26.0, outline, 7.0)
				draw_line(Vector2.ZERO, Vector2.from_angle(a) * 25.0, fin, 4.0)
			draw_circle(Vector2.ZERO, 19.5, outline)
			draw_circle(Vector2.ZERO, 18.0, Color(0.32, 0.34, 0.36) if not used else Color(0.2, 0.2, 0.2))
			draw_circle(Vector2.ZERO, 10.0, fin.darkened(0.2) if not used else Color(0.15, 0.15, 0.15))
			for i in uses:
				draw_circle(Vector2(-6 + i * 12, 0), 3.0, UiStyle.YELLOW)
		Kind.SAMPLE:
			if not used:
				var glow := 0.5 + 0.5 * sin(_blink * 4.0)
				draw_circle(Vector2.ZERO, 16.0 + glow * 4.0, Color(0.3, 0.9, 1.0, 0.18))
				draw_circle(Vector2.ZERO, 9.5, outline)
				draw_circle(Vector2.ZERO, 8.0, Color(0.35, 0.95, 0.9))
				draw_circle(Vector2(-2, -2), 3.0, Color(0.9, 1.0, 1.0, 0.8))
		Kind.AMMO:
			var c := Color(0.25, 0.35, 0.2) if not used else Color(0.18, 0.2, 0.17)
			draw_rect(Rect2(-16.5, -12.5, 33, 25), outline)
			draw_rect(Rect2(-15, -11, 30, 22), c)
			if not used:
				for i in 3:
					draw_line(Vector2(-12 + i * 9, -11), Vector2(-6 + i * 9, 11), UiStyle.YELLOW, 3.0)
				draw_rect(Rect2(-15, -11, 30, 3), Color(1, 1, 1, 0.14))
				draw_rect(Rect2(-5, -3, 10, 6), Color(0.1, 0.12, 0.08)) # handle plate
				var gl := 0.5 + 0.5 * sin(_blink * 3.0)
				draw_arc(Vector2.ZERO, 22.0 + gl * 3.0, 0.0, TAU, 20, Color(UiStyle.YELLOW, 0.25), 2.0)
