extends SceneTree
## Pre-renders the 3D characters (art/3d/...) straight down into pixel sprite sheets
## (art/sprites/<skin>/<anim>.png): one row of square frames, facing screen-up,
## binary alpha, 1 px ink outline. Clips come from the FBX files, or are posed procedurally
## here when the pack has none (the dive). Needs a real renderer:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/bake_sprites.gd
## Optional user arg after `--`: a directory to also write a contact sheet preview into.

## Bodies reshaped by tools/reshape_character.py (Blender) from Kenney's characterMedium:
## ~5 heads tall, narrow waist, rounded; each carries its own clips (Idle / Run / Jump).
## model -> skins rendered with it.
const MODELS := {
	"res://art/3d/survivors/Model/characterHuman.glb": ["survivorMaleB", "zombieA", "zombieC"],
	"res://art/3d/survivors/Model/characterHumanF.glb": ["survivorFemaleA"],
}
const SKIN_DIR := "res://art/3d/survivors/Skins/"
const OUT_DIR := "res://art/sprites/"
const SKINS := ["survivorMaleB", "survivorFemaleA", "zombieA", "zombieC"]
## Extra head scale at bake time (proportions now come from the reshaped model).
const HEAD_SCALE := 1.0
## Clips from the model: name -> {clip name in it, frames over one loop,
## hold: arms overridden with the two-handed weapon hold (Poses.hold), armed skins only}.
const ANIMS := {
	"idle": {"clip": "Idle", "frames": 8},
	"run": {"clip": "Run", "frames": 8},
	"idle_aim": {"clip": "Idle", "frames": 8, "hold": true},
	"run_aim": {"clip": "Run", "frames": 8, "hold": true},
}
## Skins that carry weapons (get the *_aim clips and the dive).
const ARMED := ["survivorMaleB", "survivorFemaleA"]
## Procedural clips (tools/poses.gd), not looping: frames sampled at t = i / (frames - 1).
## Lying flat the body is ~5 units long, so they get bigger frames. Pivot: the point the
## body turns around ("chest" keeps the dive centred, "hips" for falls).
const DIVE := {"frames": 16, "size": 128, "pivot": "chest"}
const DEATH := {"frames": 10, "size": 160, "pivot": "hips"}
## Death clip name -> [kind, seed]. Variants of one kind differ by seed.
const DEATHS := {
	"death_back0": ["back", 11], "death_back1": ["back", 23], "death_back2": ["back", 97],
	"death_fwd0": ["fwd", 31], "death_fwd1": ["fwd", 47], "death_fwd2": ["fwd", 89],
	"death_left": ["left", 53], "death_right": ["right", 61],
	"death_crumple0": ["crumple", 79], "death_crumple1": ["crumple", 83],
}

var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D
var _pivot: Node3D
var _model: Node3D
var _skel: Skeleton3D
## Weapon anchors of the frames baked by the last _bake(): [grip x, grip y, gun angle].
var _anchors: Array = []
## Stock point of the current pose's weapon hold (model space), INF when not holding.
var _hold_pocket := Vector3.INF


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_stage()
	var preview_rows: Array[Image] = []
	for path in MODELS:
		var skins: Array = MODELS[path].filter(func(k: String) -> bool: return k in SKINS)
		if not skins.is_empty():
			await _bake_model(path, skins, preview_rows)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_save_preview(preview_rows, args[0])
	quit()


## All clips for the skins that use the model at `path`.
func _bake_model(path: String, skins: Array, preview_rows: Array[Image]) -> void:
	_cam.position = Vector3(0, 20, 0)
	var model: Node3D = (load(path) as PackedScene).instantiate()
	_pivot.add_child(model)
	_model = model
	var player := AnimationPlayer.new()
	model.add_child(player)
	player.root_node = NodePath("..")
	var lib := AnimationLibrary.new()
	for anim_name in ANIMS:
		lib.add_animation(anim_name, _load_clip(path, ANIMS[anim_name].clip))
	player.add_animation_library("", lib)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var skel := model.find_child("Skeleton3D") as Skeleton3D
	_skel = skel
	var mesh := _find_mesh(model)
	# The dive pitches the body around the chest, so the flat body (hands ahead, feet behind)
	# stays centred on the same point as the standing one.
	player.play("idle")
	player.seek(0.0, true)
	var pivots := {
		"chest": (_to_model(skel, model) * skel.get_bone_global_pose(skel.find_bone("UpperChest"))).origin.y,
		"hips": (_to_model(skel, model) * skel.get_bone_global_pose(skel.find_bone("Hips"))).origin.y,
	}
	await _center_on_body(player, skel)
	for skin in skins:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(SKIN_DIR + skin + ".png")
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mesh.material_override = mat
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + skin))
		var armed: bool = skin in ARMED
		for anim_name in ANIMS:
			var spec: Dictionary = ANIMS[anim_name]
			var hold: bool = spec.get("hold", false)
			if hold and not armed:
				continue
			var n: int = spec.frames
			var anim := lib.get_animation(anim_name)
			player.play(anim_name)
			var sheet := await _bake(n, CharSprite.FRAME, func(i: int) -> void:
				player.seek(anim.length * i / n, true)
				_fix_head(skel)
				if hold:
					_pose_keys(skel, model, [Poses.key(0.0, Vector3.ZERO, Poses.hold())], 0.0)
				else:
					_hold_pocket = Vector3.INF)
			_save(sheet, skin, anim_name, preview_rows)
			if hold:
				_save_anchors(skin, anim_name)
		player.play("idle")
		var clips := {}
		if armed:
			clips["dive"] = [DIVE, Poses.dive()]
		for d in DEATHS:
			clips[d] = [DEATH, Poses.death(DEATHS[d][0], DEATHS[d][1])]
		for clip in clips:
			var spec: Dictionary = clips[clip][0]
			var keys: Array = clips[clip][1]
			_pivot.position.y = pivots[spec.pivot]
			model.position.y = -pivots[spec.pivot]
			var sheet := await _bake(spec.frames, spec.size, func(i: int) -> void:
				player.seek(0.0, true)
				_fix_head(skel)
				_pose_keys(skel, model, keys, float(i) / (spec.frames - 1)))
			_pivot.transform = Transform3D.IDENTITY
			model.position = Vector3.ZERO
			_save(sheet, skin, clip, preview_rows)
			if clip == "dive":
				_save_anchors(skin, clip)
	_model.queue_free()
	await process_frame


## Renders n frames of size px; pose(i) sets up frame i.
func _bake(n: int, size: int, pose: Callable) -> Image:
	_vp.size = Vector2i(size, size)
	_cam.size = size / CharSprite.PX_PER_UNIT
	var sheet := Image.create(size * n, size, false, Image.FORMAT_RGBA8)
	_anchors.clear()
	for i in n:
		pose.call(i)
		var grip := _screen_px(_skel.find_bone("RightHand"), size)
		var fore := _screen_px(_skel.find_bone("LeftHand"), size)
		var line_x := (grip.x + fore.x) / 2.0
		if _hold_pocket != Vector3.INF:
			line_x = _model_to_screen(_hold_pocket, size).x
		var c := Vector2(size, size) / 2.0
		# The gun runs straight ahead (the hold keeps it level, sprites face up), centred
		# between the hands, its grip level with the right hand.
		var at := Vector2(line_x, grip.y)
		_anchors.append([snappedf(at.x - c.x, 0.1), snappedf(at.y - c.y, 0.1), snappedf(-PI / 2.0, 0.001)])
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


## Bone position in the frame (pixels from the top-left), from the current pose.
func _screen_px(bone: int, size: int) -> Vector2:
	return _model_to_screen(_to_model(_skel, _model) * _skel.get_bone_global_pose(bone).origin, size)


func _model_to_screen(m: Vector3, size: int) -> Vector2:
	var w := _holder.transform * _pivot.transform * _model.transform * m
	return Vector2(w.x - _cam.position.x, w.z - _cam.position.z) * CharSprite.PX_PER_UNIT + Vector2(size, size) / 2.0


## Weapon anchors per frame (grip offset from the frame centre in px, gun angle in rad,
## screen space, sprite facing up), for drawing any weapon in the hands in game.
func _save_anchors(skin: String, clip: String) -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "%s/%s.json" % [skin, clip]), FileAccess.WRITE)
	f.store_string(JSON.stringify({"frames": _anchors}))


func _fix_head(skel: Skeleton3D) -> void:
	skel.set_bone_pose_scale(skel.find_bone("Head"), Vector3.ONE * HEAD_SCALE)


## Keyed pose at t (0..1) on top of the idle pose: whole-body rotation around the pivot,
## limbs aimed along interpolated directions (see tools/poses.gd).
func _pose_keys(skel: Skeleton3D, model: Node3D, keys: Array, t: float) -> void:
	var ka: Dictionary = keys[0]
	var kb: Dictionary = keys[-1]
	for i in range(1, keys.size()):
		if t <= keys[i].t:
			ka = keys[i - 1]
			kb = keys[i]
			break
	var f := smoothstep(0.0, 1.0, inverse_lerp(ka.t, kb.t, t)) if kb.t > ka.t else 1.0
	var rot := (ka.rot as Vector3).lerp(kb.rot, f) * (PI / 180.0)
	_pivot.basis = Basis.from_euler(rot)
	# Weapon hold (IK) when either key holds: pitch interpolated between the keys.
	var ha = ka.limbs.get("_hold")
	var hb = kb.limbs.get("_hold")
	var holding: bool = ha != null or hb != null
	var targets := {}
	if holding:
		var hp := lerpf(ha if ha != null else hb, hb if hb != null else ha, f)
		targets = _hold_targets(skel, model, hp)
	_hold_pocket = targets.get("pocket", Vector3.INF)
	for limb in Poses.ORDER:
		var arm_ik: bool = holding and targets.has(limb)
		if not (ka.limbs.has(limb) or kb.limbs.has(limb) or arm_ik):
			continue
		var bones: Array = Poses.LIMBS[limb]
		var cur := _bone_dir(skel, model, bones[0], bones[1])
		var ik := cur
		if arm_ik:
			# Upper arm: toward the solved elbow. Forearm: from the actual elbow to the hand target.
			var from := _bone_pos(skel, model, bones[0])
			ik = ((targets[limb] as Vector3) - from).normalized()
		var dfa: Vector3 = ik if ha != null and arm_ik else cur
		var dfb: Vector3 = ik if hb != null and arm_ik else cur
		var da: Vector3 = (ka.limbs.get(limb, dfa) as Vector3).normalized()
		var db: Vector3 = (kb.limbs.get(limb, dfb) as Vector3).normalized()
		# Body frame: +X is the character's left; the model's own +X is its left too.
		_aim_bone(skel, model, bones[0], bones[1], da.slerp(db, f))


## IK targets for the shouldered hold at body pitch `pitch`: {"RArm": elbow, "RFore": hand,
## "LArm": elbow, "LFore": hand, "pocket": stock point}, model space.
func _hold_targets(skel: Skeleton3D, model: Node3D, pitch: float) -> Dictionary:
	var rp := Basis(Vector3.RIGHT, -deg_to_rad(pitch))
	var pocket := _bone_pos(skel, model, "RightArm") + rp * Poses.POCKET
	var out := {"pocket": pocket}
	for side in ["R", "L"]:
		var pre := "Right" if side == "R" else "Left"
		var hand := pocket + rp * (Poses.GRIP if side == "R" else Poses.FOREGRIP)
		var pole := rp * (Poses.POLE_R if side == "R" else Poses.POLE_L)
		var sh := _bone_pos(skel, model, pre + "Arm")
		var a := sh.distance_to(_bone_pos(skel, model, pre + "ForeArm"))
		var b := _bone_pos(skel, model, pre + "ForeArm").distance_to(_bone_pos(skel, model, pre + "Hand"))
		var to := hand - sh
		var d := clampf(to.length(), absf(a - b) + 0.001, a + b - 0.001)
		var u := to.normalized()
		var ca := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
		var n := (pole - u * pole.dot(u)).normalized()
		out[side + "Arm"] = sh + u * a * ca + n * a * sqrt(1.0 - ca * ca)
		out[side + "Fore"] = sh + u * d
	return out


func _bone_pos(skel: Skeleton3D, model: Node3D, bone: String) -> Vector3:
	return _to_model(skel, model) * skel.get_bone_global_pose(skel.find_bone(bone)).origin


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
	_vp.size = Vector2i(CharSprite.FRAME, CharSprite.FRAME)
	_cam.size = CharSprite.FRAME / CharSprite.PX_PER_UNIT
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


func _load_clip(path: String, clip: String) -> Animation:
	var scene: Node = (load(path) as PackedScene).instantiate()
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
