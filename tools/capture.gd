extends SceneTree
## Visual check with a real renderer: walks and turns the player, saves screenshots.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x720 \
##     --script res://tools/capture.gd -- /tmp/cap/shot
## Frames: <prefix>_<name>.png

var _prefix := "/tmp/cap/shot"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	DirAccess.make_dir_recursive_absolute(_prefix.get_base_dir())
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var p: CharacterBody2D = main.get_node("PixelView/SubViewport/Player")
	await _frames(10)
	_shot("idle")
	p.move_input = Vector2(0.3, -1)
	await _frames(40)
	_shot("walk")
	p.move_input = Vector2.ZERO
	p.turn_look(0.6)
	await _frames(6)
	_shot("turning")
	await _frames(40)
	_shot("turned")
	# Dive to the right: airborne, then prone.
	p.move_input = Vector2(1, -0.3)
	p.dive()
	await _frames(14)
	_shot("dive_air")
	await _frames(18)
	_shot("dive_prone")
	p.move_input = Vector2.ZERO
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [_prefix, name])
	print("saved ", name)
