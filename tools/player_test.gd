extends SceneTree
## Headless check of the player rules (movement, running, dive, firing):
##   gd --headless --script res://tools/player_test.gd
## - the stick direction is quantised to 8 directions relative to the look direction
## - running is refused in the 5 non-forward directions
## - a dive moves along the exact (unquantised) stick direction
## - the dive animation is the direction relative to the look direction, the sprite keeps facing the look
## - a firearm fires during the airborne part of the dive, melee never attacks during a dive

var _fails := 0
var _p: CharacterBody2D
var _main: Node


func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if ok else "  " + info))
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## Resets the player: standing at the origin, looking `look` rad, no stick, weapon ready.
func _reset(look := 0.0) -> void:
	_p.move_input = Vector2.ZERO
	_p.velocity = Vector2.ZERO
	_p.global_position = Vector2.ZERO
	_p.look_angle = look
	_p.rotation = look
	_p.stamina = 1.0
	_p.auto_fire = false
	_p.weapon_type = _p.Weapon.FIREARM
	await _frames(40)
	_p.global_position = Vector2.ZERO
	_p.velocity = Vector2.ZERO


## Angle (deg) of v relative to the look direction, clockwise, -180..180 (0 = forward).
func _rel_deg(v: Vector2, look: float) -> float:
	return rad_to_deg(wrapf(v.angle() + PI / 2.0 - look, -PI, PI))


func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await process_frame
	_p = _main.get_node("PixelView/SubViewport/Player")
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	await process_frame

	# 1. Movement is quantised to 8 directions (relative to look).
	var look := 0.7
	var all_ok := true
	var info := ""
	for deg in [0, 10, 30, 50, 80, 100, 130, 170, 200, 250, 290, 340]:
		await _reset(look)
		var stick := Vector2.UP.rotated(deg_to_rad(deg))
		_p.move_input = stick
		await _frames(12)
		var rel := _rel_deg(_p.get_real_velocity(), look)
		var want := roundi(deg / 45.0) % 8 * 45.0
		var d := absf(wrapf(rel - want, -180.0, 180.0))
		if d > 1.0:
			all_ok = false
			info += " stick %d -> moved %.1f (want %.0f)" % [deg, rel, want]
	check("movement direction quantised to 8 (relative to look)", all_ok, info)
	await _reset(look)
	_p.move_input = Vector2.UP.rotated(deg_to_rad(40.0))
	await _frames(8)
	check("move_index = nearest sector (40 deg -> 1)", _p.move_index == 1, str(_p.move_index))

	# 2. Running only toward the front three directions.
	var names := ["forward", "forward-right", "right", "back-right", "back", "back-left", "left", "forward-left"]
	for k in 8:
		await _reset(0.3)
		_p.move_input = Vector2.UP.rotated(deg_to_rad(k * 45.0)) # full stick
		await _frames(45)
		var allowed := k in [0, 1, 7]
		var a: String = _p.sprite.anim
		check("%s: %s" % [names[k], "runs" if allowed else "walks (run refused)"],
			_p.sprinting == allowed and a == ("run_" if allowed else "walk_") + CharSprite.TAGS[k], "%s sprinting=%s" % [a, _p.sprinting])
	await _reset()
	_p.move_input = Vector2.UP.rotated(deg_to_rad(180.0))
	await _frames(60)
	check("no stamina spent walking back with the stick at the edge", _p.stamina > 0.999, str(_p.stamina))

	# 3. Dive: exact direction, any angle.
	var exact_ok := true
	info = ""
	for deg in [0, 20, 67, 112, 200, 333]:
		await _reset(0.5)
		var stick := Vector2.UP.rotated(deg_to_rad(deg))
		_p.move_input = stick
		var start := _p.global_position
		_p.dive()
		await _frames(int(_p.DIVE_AIR_END * _p.dive_time * 60.0) + 2)
		var moved := _p.global_position - start
		var rel := _rel_deg(moved, 0.5)
		var d := absf(wrapf(rel - deg, -180.0, 180.0))
		var q := absf(wrapf(rel - roundi(deg / 45.0) * 45.0, -180.0, 180.0))
		if d > 1.0 or moved.length() < 150.0:
			exact_ok = false
			info += " stick %d -> %.1f (len %.0f)" % [deg, rel, moved.length()]
		if deg in [20, 67, 112, 333] and q < 5.0:
			exact_ok = false
			info += " stick %d looks quantised" % deg
		await _frames(110)
	check("dive moves along the exact stick direction (not quantised)", exact_ok, info)

	# 4. Dive animation index = direction relative to look; sprite keeps facing the look direction.
	var idx_ok := true
	var face_ok := true
	info = ""
	for deg in [0, 20, 50, 95, 130, 180, 215, 265, 300, 350]:
		await _reset(-1.0)
		_p.move_input = Vector2.UP.rotated(deg_to_rad(deg))
		_p.dive()
		var want := roundi(deg / 45.0) % 8
		await _frames(6)
		if _p.dive_index != want or _p.sprite.anim != "dive_%d" % want:
			idx_ok = false
			info += " stick %d -> dive_%d anim %s (want %d)" % [deg, _p.dive_index, _p.sprite.anim, want]
		for i in 4:
			_p.turn_look(0.05) # the camera keeps turning mid-dive
			await _frames(10)
			if absf(wrapf(_p.sprite.global_rotation - _p.look_angle, -PI, PI)) > 0.001:
				face_ok = false
				info += " facing off at stick %d" % deg
		await _frames(90)
		check_once_not_diving(deg)
	check("dive animation = dive direction relative to look (8 indices)", idx_ok, info)
	check("sprite keeps facing the look direction during the dive", face_ok, info)

	# 5. Firing mid-dive.
	await _reset(0.0)
	_p.weapon_type = _p.Weapon.FIREARM
	_p.move_input = Vector2.RIGHT
	_p.dive()
	await _frames(8)
	var before: int = _p.shots_fired
	var fired: bool = _p.try_attack()
	check("firearm: fire allowed while airborne in a dive", fired and _p.shots_fired == before + 1)
	var bullets := 0
	for n in _p.get_parent().get_children():
		if n is Bullet:
			bullets += 1
			check("bullet flies along the look direction", (n as Bullet).dir.is_equal_approx(Vector2.UP.rotated(_p.look_angle)))
			var lateral := absf((n.global_position - _p.global_position).dot(Vector2.RIGHT.rotated(_p.look_angle)))
			check("muzzle is on the aim line side of the body (< 40 px off axis)", lateral < 40.0, str(lateral))
	check("a bullet was spawned", bullets >= 1)
	await _frames(40) # past the airborne part
	await _frames(15)
	check("firearm: fire refused after landing (prone)", not _p.try_attack())
	await _frames(90)
	await _reset(0.0)
	_p.weapon_type = _p.Weapon.MELEE
	_p.move_input = Vector2.LEFT
	_p.dive()
	await _frames(8)
	var swings: int = _p.melee_swings
	check("melee: attack refused during a dive", not _p.try_attack() and _p.melee_swings == swings)
	await _frames(120)
	check("melee: attack allowed on foot", _p.try_attack() and _p.melee_swings == swings + 1)
	_p.weapon_type = _p.Weapon.FIREARM
	await _reset(0.0)
	check("firearm: attack allowed on foot", _p.try_attack())

	print("FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)


func check_once_not_diving(deg: int) -> void:
	if _p.is_diving():
		check("dive ended (stick %d)" % deg, false)
