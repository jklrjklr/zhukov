extends SceneTree
## Headless check: main scene loads, the player walks forward, turns, and the camera follows.
## Run: godot --headless --script res://tools/smoke_test.gd

var _fails := 0


func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if ok else "  " + info))
	if not ok:
		_fails += 1


func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var p: CharacterBody2D = main.get_node("PixelView/SubViewport/Player")
	var cam: PlayerCamera = p.get_node("CameraRig/ViewCamera")
	var pv: PixelView = main.get_node("PixelView")
	check("low-res buffer height", pv.buffer_size().y == Vis.PIXEL_HEIGHT, str(pv.buffer_size()))
	check("camera base zoom", absf(cam.zoom - Vis.CAM_ZOOM) < 0.01, str(cam.zoom))
	p.move_input = Vector2(0, -1)
	for i in 60:
		await physics_frame
	check("walks forward (up)", p.global_position.y < -100.0, str(p.global_position))
	p.move_input = Vector2.ZERO
	p.turn_look(PI / 2.0)
	for i in 60:
		await physics_frame
	check("body follows look angle", absf(wrapf(p.rotation - PI / 2.0, -PI, PI)) < 0.01, str(p.rotation))
	check("camera rig aligned", absf(cam.global_rotation - PI / 2.0) < 0.01)
	await process_frame
	var vxf: Transform2D = pv.get_child(0).canvas_transform
	check("buffer transform snapped to whole pixels", vxf.origin == vxf.origin.round(), str(vxf.origin))
	var on_screen: Vector2 = vxf * p.global_position
	check("player in lower half of buffer", on_screen.y > pv.get_child(0).size.y * 0.5, str(on_screen))
	var start := p.global_position
	p.move_input = Vector2(0, -1)
	for i in 30:
		await physics_frame
	check("forward follows turn (east)", p.global_position.x - start.x > 50.0, str(p.global_position - start))
	p.move_input = Vector2.ZERO
	for i in 30:
		await physics_frame
	var before := p.global_position
	p.move_input = Vector2(1, 0)
	p.dive()
	check("dive starts", p.is_diving())
	for i in 15:
		await physics_frame
	check("airborne dive is invulnerable", p.is_invulnerable())
	for i in 60:
		await physics_frame
	var moved := p.global_position.distance_to(before)
	check("dive ends", not p.is_diving())
	check("dive covers ~3.2-4 m", moved > 3.0 * 60.0 and moved < 4.5 * 60.0, str(moved))
	p.move_input = Vector2.ZERO
	var z := Zombie.new()
	z.position = p.global_position + Vector2(200, 0)
	main.get_node("PixelView/SubViewport/World").add_child(z)
	await physics_frame
	p.debug_kill_nearby()
	check("debug kill leaves a corpse", z.dead and z.collision_layer == 0 and z._sprite.anim.begins_with("death"), z._sprite.anim)
	print("FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)
