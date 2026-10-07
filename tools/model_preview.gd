extends SceneTree
## Front T-pose renders: original Kenney body vs the reshaped male / female bodies, per skin.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/model_preview.gd -- out.png
func _initialize():
	var out := Image.create(256 * 6, 320, false, Image.FORMAT_RGBA8)
	out.fill(Color("22382a"))
	var models := ["res://art/3d/survivors/Model/characterMedium.fbx", "res://art/3d/survivors/Model/characterHuman.glb", "res://art/3d/survivors/Model/characterHumanF.glb"]
	var col := 0
	for skin in ["survivorMaleB", "survivorFemaleA"]:
		for mi in models.size():
			var vp := SubViewport.new()
			vp.size = Vector2i(256, 320)
			vp.transparent_bg = true
			vp.own_world_3d = true
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
			sun.rotation_degrees = Vector3(-40, 30, 0)
			vp.add_child(sun)
			var cam := Camera3D.new()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 4.4
			cam.position = Vector3(0, 2.4, 10)
			vp.add_child(cam)
			var m: Node3D = load(models[mi]).instantiate()
			vp.add_child(m)
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = load("res://art/3d/survivors/Skins/%s.png" % skin)
			var mesh := m.find_children("*", "MeshInstance3D")[0] as MeshInstance3D
			mesh.material_override = mat
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			out.blend_rect(img, Rect2i(0, 0, 256, 320), Vector2i(col * 256, 0))
			col += 1
			vp.queue_free()
	out.save_png(OS.get_cmdline_user_args()[0])
	quit()
