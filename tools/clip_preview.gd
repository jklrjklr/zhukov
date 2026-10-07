extends SceneTree
## Side-view filmstrips of the model's clips (check retargeted motion):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/clip_preview.gd -- out.png [model] [clips...]
const W := 128
const H := 192
const FRAMES := 10


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var model_path := args[1] if args.size() > 1 else "res://art/3d/survivors/Model/characterHuman.glb"
	var m: Node3D = load(model_path).instantiate()
	var ap := m.find_child("AnimationPlayer") as AnimationPlayer
	var clips: Array = args.slice(2) if args.size() > 2 else Array(ap.get_animation_list())
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.9)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 60, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.0
	cam.position = Vector3(10, 1.8, 0)
	cam.rotation_degrees = Vector3(0, 90, 0)
	vp.add_child(cam)
	vp.add_child(m)
	var mesh := m.find_children("*", "MeshInstance3D")[0] as MeshInstance3D
	var mat := ShaderMaterial.new()
	mat.shader = load("res://tools/char_bake.gdshader")
	mat.set_shader_parameter("skin_tex", load("res://art/3d/survivors/Skins/survivorMaleB.png"))
	mesh.material_override = mat
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var out := Image.create(W * FRAMES, H * clips.size(), false, Image.FORMAT_RGBA8)
	out.fill(Color("22382a"))
	for r in clips.size():
		ap.play(clips[r])
		var a := ap.get_animation(clips[r])
		for i in FRAMES:
			ap.seek(a.length * i / FRAMES, true)
			await process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			out.blend_rect(img, Rect2i(0, 0, W, H), Vector2i(i * W, r * H))
	out.save_png(args[0])
	print("clips ", clips)
	quit()
