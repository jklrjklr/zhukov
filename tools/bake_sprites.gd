extends SceneTree
## Pre-renders the 3D characters (art/3d/...) straight down into pixel sprite sheets
## (art/sprites/<skin>/<anim>.png): one row of FRAME x FRAME frames, facing screen-up,
## binary alpha, 1 px ink outline. Needs a real renderer:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/bake_sprites.gd
## Optional user arg after `--`: a directory to also write a contact sheet preview into.

const MODEL := "res://art/3d/survivors/Model/characterMedium.fbx"
const ANIM_DIR := "res://art/3d/survivors/Animations/"
const SKIN_DIR := "res://art/3d/survivors/Skins/"
const OUT_DIR := "res://art/sprites/"
const SKINS := ["survivorMaleB", "survivorFemaleA", "zombieA", "zombieC"]
## anim file -> {clip name in the file, frames to sample over one loop}
## Kenney's characters are chibi: from above the head hides the body. Scaling the head bone
## gives human proportions (OTXO-like silhouettes: shoulders, arms, legs readable).
const HEAD_SCALE := 0.6
const ANIMS := {
	"idle": {"clip": "Root|Idle", "frames": 8},
	"run": {"clip": "Root|Run", "frames": 8},
}

var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_stage()
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	_holder.add_child(model)
	var player := AnimationPlayer.new()
	model.add_child(player)
	player.root_node = NodePath("..")
	var lib := AnimationLibrary.new()
	for anim_name in ANIMS:
		lib.add_animation(anim_name, _load_clip(anim_name, ANIMS[anim_name].clip))
	player.add_animation_library("", lib)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var skel := model.find_child("Skeleton3D") as Skeleton3D
	var head := skel.find_bone("Head")
	var mesh := _find_mesh(model)
	await _center_on_body(player, mesh)
	var preview_rows: Array[Image] = []
	for skin in SKINS:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(SKIN_DIR + skin + ".png")
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mesh.material_override = mat
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + skin))
		for anim_name in ANIMS:
			var n: int = ANIMS[anim_name].frames
			var anim := lib.get_animation(anim_name)
			player.play(anim_name)
			var sheet := Image.create(CharSprite.FRAME * n, CharSprite.FRAME, false, Image.FORMAT_RGBA8)
			for i in n:
				player.seek(anim.length * i / n, true)
				skel.set_bone_pose_scale(head, Vector3.ONE * HEAD_SCALE)
				await process_frame
				await RenderingServer.frame_post_draw
				var img := _vp.get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				_outline(img)
				sheet.blit_rect(img, Rect2i(0, 0, CharSprite.FRAME, CharSprite.FRAME), Vector2i(i * CharSprite.FRAME, 0))
			var path := OUT_DIR + "%s/%s.png" % [skin, anim_name]
			sheet.save_png(ProjectSettings.globalize_path(path))
			preview_rows.append(sheet)
			print("baked ", path, " frames=", n)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_save_preview(preview_rows, args[0])
	quit()


## Orthographic camera straight down; light from above (sprites rotate in game, so the
## shading must not prefer a side), soft ambient so the shadowed parts keep their colour.
func _build_stage() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(CharSprite.FRAME, CharSprite.FRAME)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.9)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-90, 0, 0)
	sun.light_energy = 1.0
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = CharSprite.FRAME / CharSprite.PX_PER_UNIT # vertical extent in model units
	_cam.position = Vector3(0, 20, 0)
	_cam.rotation_degrees = Vector3(-90, 0, 0) # screen-up = world -Z
	_cam.near = 0.1
	_cam.far = 50.0
	_vp.add_child(_cam)
	_holder = Node3D.new()
	_holder.rotation_degrees = Vector3(0, 180, 0) # model faces +Z; turn it to face -Z (screen-up)
	_vp.add_child(_holder)


## Shifts the camera so the idle pose's silhouette centre is the frame centre (the sprite
## pivots there when the character turns).
func _center_on_body(player: AnimationPlayer, mesh: MeshInstance3D) -> void:
	var skel := mesh.get_parent() as Skeleton3D
	player.play("idle")
	player.seek(0.0, true)
	skel.set_bone_pose_scale(skel.find_bone("Head"), Vector3.ONE * HEAD_SCALE)
	await process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var used := img.get_used_rect()
	var off := Vector2(used.get_center()) - Vector2(CharSprite.FRAME, CharSprite.FRAME) / 2.0
	# Screen right = world +X, screen down = world +Z.
	_cam.position += Vector3(off.x, 0.0, off.y) / CharSprite.PX_PER_UNIT
	print("centre offset px ", off)


func _load_clip(file: String, clip: String) -> Animation:
	var scene: Node = (load(ANIM_DIR + file + ".fbx") as PackedScene).instantiate()
	var ap := scene.find_child("AnimationPlayer") as AnimationPlayer
	var anim := ap.get_animation(clip).duplicate() as Animation
	anim.loop_mode = Animation.LOOP_LINEAR
	scene.free()
	return anim


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _find_mesh(c)
		if m:
			return m
	return null


## Binary alpha, then a 1 px ink ring around the silhouette (4-neighbourhood).
func _outline(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			solid[y * w + x] = 1 if c.a >= 0.5 else 0
			if c.a >= 0.5:
				img.set_pixel(x, y, Color(c.r / c.a, c.g / c.a, c.b / c.a, 1.0) if c.a < 1.0 else c)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			if solid[y * w + x] == 1:
				continue
			var edge := (x > 0 and solid[y * w + x - 1] == 1) or (x < w - 1 and solid[y * w + x + 1] == 1) \
				or (y > 0 and solid[(y - 1) * w + x] == 1) or (y < h - 1 and solid[(y + 1) * w + x] == 1)
			if edge:
				img.set_pixel(x, y, Pal.INK)


func _save_preview(rows: Array[Image], dir: String) -> void:
	var w := 0
	for r in rows:
		w = maxi(w, r.get_width())
	var img := Image.create(w, CharSprite.FRAME * rows.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color("22382a"))
	for i in rows.size():
		img.blend_rect(rows[i], Rect2i(Vector2i.ZERO, rows[i].get_size()), Vector2i(0, i * CharSprite.FRAME))
	img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir.path_join("bake_preview.png"))
