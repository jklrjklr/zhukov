class_name Vision
extends Node2D
## Player sight, without lights or shadow maps (cheap on mobile web):
## each frame RAYS rays are cast across the sight cone from the head; anything
## outside the resulting sight polygon is covered by a dark fan overlay. Walls,
## rocks, crates and tree trunks (collision layer 1) block sight; enemies and
## dummies (layer 2) do not.
## Nodes in group "concealable" (enemies, dummies) fade out when not in sight; close
## ones stay faintly visible ("you sense them"). Hidden ones are not drawn at all.
## Aiming down sights narrows the cone to the weapon's ads_fov.
## Child of Player (follows it), but draws in world space above the world and
## below the player (z_index).

const PX := Firearm.PX_PER_M
## Rays across the cone.
const RAYS := 96
## px; far edge of the darkness fan (must cover the screen at the widest zoom).
const FAR := 4000.0
## Collision layer that blocks sight (world geometry).
const SIGHT_MASK := 1
const DARK := Color(0.02, 0.03, 0.04, 0.8)
## Draw order: above world, zombies, props; below projectiles and the player.
const Z := 10

## Full sight angle in degrees.
@export var fov_degrees := 120.0
## m, how far the cone reaches.
@export var view_distance := 24.0
## m, unseen concealables start fading in at this distance...
@export var sense_start := 7.0
## m, ...and reach sense_alpha here.
@export var sense_full := 3.0
@export_range(0.0, 1.0) var sense_alpha := 0.55

var _player: CharacterBody2D
var _weapon: Firearm
## Visible end point of each ray (global), first to last across the cone.
var _ends := PackedVector2Array()
var _origin := Vector2.ZERO
var _forward := Vector2.UP
var _half_fov := 0.0


func _ready() -> void:
	_player = get_parent()
	_weapon = _player.get_node("Firearm")
	top_level = true
	z_as_relative = false
	z_index = Z


func _physics_process(delta: float) -> void:
	global_position = Vector2.ZERO
	global_rotation = 0.0
	_origin = _player.global_position
	_forward = Vector2.UP.rotated(_player.global_rotation)
	_half_fov = deg_to_rad(lerpf(fov_degrees, _weapon.stats.ads_fov, _weapon.ads_amount()) / 2.0)
	_cast_rays()
	_update_concealment(delta)
	queue_redraw()


func _cast_rays() -> void:
	var space := get_world_2d().direct_space_state
	var reach := view_distance * PX
	_ends.resize(RAYS + 1)
	for i in RAYS + 1:
		var a := lerpf(-_half_fov, _half_fov, float(i) / RAYS)
		var to := _origin + _forward.rotated(a) * reach
		var q := PhysicsRayQueryParameters2D.create(_origin, to, SIGHT_MASK)
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			_ends[i] = to
		else:
			# Let the near face of the blocker show before darkness starts.
			_ends[i] = (hit.position as Vector2) + _forward.rotated(a) * 10.0


func _update_concealment(delta: float) -> void:
	var space := get_world_2d().direct_space_state
	for n in get_tree().get_nodes_in_group("concealable"):
		var item := n as CanvasItem
		var to: Vector2 = item.global_position - _origin
		var meters := to.length() / PX
		var target := 0.0
		if meters <= view_distance and absf(_forward.angle_to(to)) <= _half_fov:
			var q := PhysicsRayQueryParameters2D.create(_origin, item.global_position, SIGHT_MASK)
			q.exclude = [_player.get_rid()]
			if space.intersect_ray(q).is_empty():
				target = 1.0
		if target < 1.0:
			target = (1.0 - smoothstep(sense_full, sense_start, meters)) * sense_alpha
		item.modulate.a = move_toward(item.modulate.a, target, delta * 5.0)
		item.visible = item.modulate.a > 0.01


func _draw() -> void:
	if _ends.is_empty():
		return
	# Darkness outside the cone: one big fan from the head around the back.
	var back := PackedVector2Array([_origin])
	var steps := 24
	for i in steps + 1:
		var a := lerpf(_half_fov, TAU - _half_fov, float(i) / steps)
		back.append(_origin + _forward.rotated(a) * FAR)
	draw_colored_polygon(back, DARK)
	# Darkness beyond each ray's visible end, inside the cone.
	for i in RAYS:
		var a0 := lerpf(-_half_fov, _half_fov, float(i) / RAYS)
		var a1 := lerpf(-_half_fov, _half_fov, float(i + 1) / RAYS)
		draw_colored_polygon(PackedVector2Array([
			_ends[i], _ends[i + 1],
			_origin + _forward.rotated(a1) * FAR, _origin + _forward.rotated(a0) * FAR,
		]), DARK)
