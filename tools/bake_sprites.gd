extends SceneTree
## Pre-renders the 3D characters (art/3d/...) straight down into pixel sprite sheets
## (art/sprites/<skin>/<anim>.png): one row of square frames, facing screen-up,
## binary alpha, 1 px ink outline. Clips come from the FBX files, or are posed procedurally
## here when the pack has none (the dive). Needs a real renderer:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/bake_sprites.gd
## Optional user arg after `--`: a directory to also write a contact sheet preview into.

const MODEL := "res://art/3d/survivors/Model/characterMedium.fbx"
const ANIM_DIR := "res://art/3d/survivors/Animations/"
const SKIN_DIR := "res://art/3d/survivors/Skins/"
const OUT_DIR := "res://art/sprites/"
const SKINS := ["survivorMaleB", "survivorFemaleA", "zombieA", "zombieC"]
## Kenney's characters are chibi: from above the head hides the body. Scaling the head bone
## gives human proportions (OTXO-like silhouettes: shoulders, arms, legs readable).
const HEAD_SCALE := 0.6
## Clips from the FBX files: anim file -> {clip name in the file, frames over one loop}.
const ANIMS := {
	"idle": {"clip": "Root|Idle", "frames": 8},
	"run": {"clip": "Root|Run", "frames": 8},
}
## Procedural dive (dodge), not looping: frames sampled at t = i / (frames - 1). Lying flat
## the body is ~5 units long, so it gets a bigger frame.
const DIVE_FRAMES := 12
const DIVE_SIZE := 128
## Dive keys: [t, pitch forward (deg), arms 0 = down .. 1 = stretched ahead, legs 0 = idle .. 1 = straight back]
const DIVE_KEYS := [
	[0.00, 0.0, 0.0, 0.0],
	[0.15, 45.0, 0.8, 1.0], # take-off
	[0.30, 80.0, 1.0, 1.0], # airborne
	[0.55, 86.0, 1.0, 1.0],
	[0.70, 90.0, 0.9, 1.0], # landed, sliding prone
	[0.85, 50.0, 0.3, 0.5], # getting up
	[1.00, 0.0, 0.0, 0.0],
]

var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D
var _pivot: Node3D


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_stage()
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	_pivot.add_child(model)
	var player := AnimationPlayer.new()
	model.add_child(player)
	player.root_node = NodePath("..")
	var lib := AnimationLibrary.new()
	for anim_name in ANIMS:
		lib.add_animation(anim_name, _load_clip(anim_name, ANIMS[anim_name].clip))
	player.add_animation_library("", lib)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var skel := model.find_child("Skeleton3D") as Skeleton3D
	var mesh := _find_mesh(model)
	# The dive pitches the body around the chest, so the flat body (hands ahead, feet behind)
	# stays centred on the same point as the standing one.
	player.play("idle")
	player.seek(0.0, true)
	var chest_y := (_to_model(skel, model) * skel.get_bone_global_pose(skel.find_bone("UpperChest"))).origin.y
	_pivot.position.y = chest_y
	model.position.y = -chest_y
	await _center_on_body(player, skel)
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
			var sheet := await _bake(n, CharSprite.FRAME, func(i: int) -> void:
				player.seek(anim.length * i / n, true)
				_fix_head(skel))
			_save(sheet, skin, anim_name, preview_rows)
		player.play("idle")
		var dive := await _bake(DIVE_FRAMES, DIVE_SIZE, func(i: int) -> void:
			player.seek(0.0, true)
			_fix_head(skel)
			_pose_dive(skel, model, float(i) / (DIVE_FRAMES - 1)))
		_pivot.rotation = Vector3.ZERO
		_save(dive, skin, "dive", preview_rows)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_save_preview(preview_rows, args[0])
	quit()


## Renders n frames of size px; pose(i) sets up frame i.
func _bake(n: int, size: int, pose: Callable) -> Image:
	_vp.size = Vector2i(size, size)
	_cam.size = size / CharSprite.PX_PER_UNIT
	var sheet := Image.create(size * n, size, false, Image.FORMAT_RGBA8)
	for i in n:
		pose.call(i)
		await process_frame
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		_outline(img)
		sheet.blit_rect(img, Rect2i(0, 0, size, size), Vector2i(i * size, 0))
	return sheet


func _save(sheet: Image, skin: String, anim_name: String, preview_rows: Array[Image]) -> void:
	var path := OUT_DIR + "%s/%s.png" % [skin, anim_name]
	sheet.save_png(ProjectSettings.globalize_path(path))
	preview_rows.append(sheet)
	print("baked ", path, " frames=", sheet.get_width() / sheet.get_height())


func _fix_head(skel: Skeleton3D) -> void:
	skel.set_bone_pose_scale(skel.find_bone("Head"), Vector3.ONE * HEAD_SCALE)


## Dive pose at t (0..1) on top of the idle pose: body pitched forward around the hips,
## arms swung up past the head (= stretched ahead when flat), legs straightened back.
func _pose_dive(skel: Skeleton3D, model: Node3D, t: float) -> void:
	var k := _dive_key(t)
	_pivot.rotation = Vector3(deg_to_rad(k[0]), 0.0, 0.0)
	# Directions in the model's own space: it faces +Z, up is +Y, its left is +X.
	for side in [1.0, -1.0]:
		var pre := "Left" if side > 0.0 else "Right"
		if k[1] > 0.0:
			var down := Vector3(side * 0.2, -1.0, 0.1).normalized()
			var up := Vector3(side * 0.28, 1.0, 0.25).normalized()
			var arm := down.slerp(up, k[1])
			_aim_bone(skel, model, pre + "Arm", pre + "ForeArm", arm)
			_aim_bone(skel, model, pre + "ForeArm", pre + "Hand", arm)
		if k[2] > 0.0:
			var leg := Vector3(side * 0.12, -1.0, -0.15).normalized()
			var cur := _bone_dir(skel, model, pre + "UpLeg", pre + "Leg")
			var d := cur.slerp(leg, k[2])
			_aim_bone(skel, model, pre + "UpLeg", pre + "Leg", d)
			_aim_bone(skel, model, pre + "Leg", pre + "Foot", d)


## Interpolated [pitch, arms, legs] from DIVE_KEYS.
func _dive_key(t: float) -> Array:
	for i in range(1, DIVE_KEYS.size()):
		var b: Array = DIVE_KEYS[i]
		if t <= b[0]:
			var a: Array = DIVE_KEYS[i - 1]
			var f := inverse_lerp(a[0], b[0], t)
			return [lerpf(a[1], b[1], f), lerpf(a[2], b[2], f), lerpf(a[3], b[3], f)]
	var last: Array = DIVE_KEYS[-1]
	return [last[1], last[2], last[3]]


## Skeleton space -> model space, from the local transforms (global transforms of nodes in
## this off-screen viewport are not up to date while posing).
func _to_model(skel: Skeleton3D, model: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = skel
	while n != model:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Direction from a bone to its child, in model space.
func _bone_dir(skel: Skeleton3D, model: Node3D, bone: String, child: String) -> Vector3:
	var to_model := _to_model(skel, model).basis
	var p := skel.get_bone_global_pose(skel.find_bone(bone)).origin
	var c := skel.get_bone_global_pose(skel.find_bone(child)).origin
	return (to_model * (c - p)).normalized()


## Rotates `bone` (in skeleton space) so it points from itself to `child` along dir (model space).
func _aim_bone(skel: Skeleton3D, model: Node3D, bone: String, child: String, dir: Vector3) -> void:
	var to_model := _to_model(skel, model).basis
	var b := skel.find_bone(bone)
	var p := skel.get_bone_global_pose(b).origin
	var c := skel.get_bone_global_pose(skel.find_bone(child)).origin
	var cur := (c - p).normalized()
	var want := (to_model.inverse() * dir).normalized()
	if cur.is_equal_approx(want):
		return
	var gp := skel.get_bone_global_pose(b)
	gp.basis = Basis(Quaternion(cur, want)) * gp.basis
	skel.set_bone_global_pose(b, gp)


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
	_pivot = Node3D.new()
	_holder.add_child(_pivot)


## Shifts the camera so the idle pose's silhouette centre is the frame centre (the sprite
## pivots there when the character turns).
func _center_on_body(player: AnimationPlayer, skel: Skeleton3D) -> void:
	player.play("idle")
	player.seek(0.0, true)
	_fix_head(skel)
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
	var h := 0
	for r in rows:
		w = maxi(w, r.get_width())
		h += r.get_height()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color("22382a"))
	var y := 0
	for r in rows:
		img.blend_rect(r, Rect2i(Vector2i.ZERO, r.get_size()), Vector2i(0, y))
		y += r.get_height()
	img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir.path_join("bake_preview.png"))
