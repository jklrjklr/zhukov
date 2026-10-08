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
## Looping clips from the model (mocap retargeted by tools/reshape_character.py):
## sprite clip -> {clip in the model, frames over one loop, hold: arms on the weapon (IK,
## armed skins only; otherwise unarmed skins only)}.
const ANIMS := {
	"idle": {"clip": "Idle", "keys": 5},
	"walk": {"clip": "ZombieWalk", "keys": 8},
	"idle_aim": {"clip": "Idle", "keys": 5, "hold": true},
}
## Armed locomotion in 8 directions relative to the look direction (the sprite faces the look
## direction, the body moves along `go`). `go` = direction index 0..7: forward, forward-right,
## right, back-right, back, back-left, left, forward-left (clockwise from above). The four
## cardinal walks and the run are retargeted mocap; the diagonals RE-AIM the forward / back
## gait: each foot's swing around its neutral position is turned by `aim` degrees (about the
## vertical axis, + = toward the character's left) and the legs are re-solved with 2-bone IK,
## so the planted foot moves in a straight line against the travel direction and cadence,
## stride and leg timing stay those of the mocap. `stride` = travel per loop in model units
## (measured in Blender by tools/cmu_retarget.py, see the log); the foot slide is checked
## against it at bake time. Each loop is also phase-aligned: frame 0 = the left foot at its
## leading extreme, so switching direction mid-stride doesn't pop.
const GAIT := {
	"walk_f": {"clip": "KWalk", "go": 0, "aim": 0.0},
	"walk_fr": {"clip": "KWalk", "go": 1, "aim": -45.0},
	"walk_r": {"clip": "KWalkRight", "go": 2, "aim": 0.0},
	"walk_b": {"clip": "KWalkBack", "go": 4, "aim": 0.0},
	"walk_br": {"clip": "KWalkBack", "go": 3, "aim": 45.0},
	"walk_bl": {"clip": "KWalkBack", "go": 5, "aim": -45.0},
	"walk_l": {"clip": "KWalkLeft", "go": 6, "aim": 0.0},
	"walk_fl": {"clip": "KWalk", "go": 7, "aim": 45.0},
	"run_f": {"clip": "KRun", "go": 0, "aim": 0.0},
	"run_fr": {"clip": "KRun", "go": 1, "aim": -45.0},
	"run_fl": {"clip": "KRun", "go": 7, "aim": 45.0},
}
## Pixel-art timing (Dead Cells style): every clip is rendered densely (DENSE samples), then
## only key poses are kept - the extremes where the body slows down, plus fills for long gaps
## - each held until the next one (phase starts in the clip's .json). Motion snaps between
## poses with skipped in-betweens instead of evenly spaced time samples.
const DENSE := 32
## Rendered at SUPERSAMPLE x and reduced by majority vote per pixel (clean flat clusters).
const SUPERSAMPLE := 2
## Dive (armed skins): 8 hand-keyed dives, dive_<k> (k = direction relative to the look direction,
## same numbering as the gait), see Poses.dive(): the body always faces the look direction (sprite
## up), leans toward the dive heading, gun held level by IK. One sprite frame per key pose.
const DIVE_SIZE := 160
## Skins wearing the outfit painted into the body meshes (black suit, white shirt, tie).
const OUTFIT := ["survivorMaleB", "survivorFemaleA"]
## Skins that carry weapons (get the *_aim clips and the dive).
const ARMED := ["survivorMaleB", "survivorFemaleA"]
## Deaths are physics ragdolls (tools/ragdoll.gd): the body starts from its stance, takes a
## hit impulse and falls limp; frames sampled over DEATH_TIME seconds of simulation.
## DEATH_DIRS push directions (sprite space, 0 = pushed back / screen-down, clockwise in 45 deg
## steps) x DEATH_VARIANTS seeds: death_d<dir>_<variant>. Sheets are cropped to the area the
## fall uses (offset in the clip's .json) to keep memory down on phones.
const DEATH := {"frames": 30, "size": 192, "keys": 8}
const DEATH_TIME := 1.5
const DEATH_DIRS := 8
const DEATH_VARIANTS := 3

var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D
var _pivot: Node3D
var _model: Node3D
var _skel: Skeleton3D
## Weapon anchors of the frames baked by the last _bake(): [grip x, grip y, gun angle].
var _anchors: Array = []
## Phase (0..1) at which each kept frame of the last _bake() starts.
var _starts: Array = []
## Stock point of the current pose's weapon hold (model space), INF when not holding.
var _hold_pocket := Vector3.INF


## Clip name prefixes to bake (user arg `only=walk_,dive_`); empty = everything.
var _only: Array = []
## User arg `skin=survivorMaleB`: bake only these skins.
var _skin_filter: Array = []
## User arg `side=<dir>`: also render each kept key pose from the SIDE (3D pose check) into
## <dir>/<skin>_<clip>_side.png (strip of SIDE_PX frames; used by tools/key_sheet.py).
var _side_dir := ""
var _sides: Array[Image] = []
var _side_strip: Image
const SIDE_PX := 128
## Phase starts forced for the next _bake() (hand-keyed clips: the key times).
var _force_starts: Array = []
## Extra fields for the next _save() json (locomotion: stride per loop, direction).
var _meta_extra := {}


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240 # ragdoll stability
	Engine.max_physics_steps_per_frame = 64
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var preview_dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			_only = a.substr(5).split(",")
		elif a.begins_with("side="):
			_side_dir = a.substr(5)
		elif a.begins_with("skin="):
			_skin_filter = a.substr(5).split(",")
		else:
			preview_dir = a
	_build_stage()
	var preview_rows: Array[Image] = []
	for path in MODELS:
		var skins: Array = MODELS[path].filter(func(k: String) -> bool: return k in SKINS and (_skin_filter.is_empty() or k in _skin_filter))
		if not skins.is_empty():
			await _bake_model(path, skins, preview_rows)
	if preview_dir != "":
		_save_preview(preview_rows, preview_dir)
	quit()


func _want(clip: String) -> bool:
	return _only.is_empty() or _only.any(func(p: String) -> bool: return clip.begins_with(p))


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
	for table in [ANIMS, GAIT]:
		for anim_name in table:
			lib.add_animation(anim_name, _load_clip(path, table[anim_name].clip))
	lib.add_animation("KDive", _load_clip(path, "KDive"))
	player.add_animation_library("", lib)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var skel := model.find_child("Skeleton3D") as Skeleton3D
	_skel = skel
	var mesh := _find_mesh(model)
	await _center_on_body(player, skel)
	for skin in skins:
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://tools/char_bake.gdshader")
		mat.set_shader_parameter("skin_tex", load(SKIN_DIR + skin + ".png"))
		mat.set_shader_parameter("outfit", 1.0 if skin in OUTFIT else 0.0)
		mesh.material_override = mat
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + skin))
		var armed: bool = skin in ARMED
		for anim_name in ANIMS:
			var spec: Dictionary = ANIMS[anim_name]
			var hold: bool = spec.get("hold", false)
			if hold != armed or not _want(anim_name):
				continue
			var anim := lib.get_animation(anim_name)
			player.play(anim_name)
			var sheet := await _bake(DENSE, CharSprite.FRAME, func(i: int) -> void:
				player.seek(anim.length * i / DENSE, true)
				_fix_head(skel)
				if hold:
					_pose_keys(skel, model, [Poses.key(0.0, Vector3.ZERO, Poses.hold())], 0.0)
				else:
					_hold_pocket = Vector3.INF, spec.keys, true)
			_save(sheet, skin, anim_name, preview_rows, _anchors if hold else [])
		if armed:
			for anim_name in GAIT:
				if _want(anim_name):
					await _bake_gait(player, lib, skel, model, anim_name, GAIT[anim_name], skin, preview_rows)
			for k in 8:
				if _want("dive_%d" % k):
					await _bake_dive(player, lib, skel, model, k, skin, preview_rows)
		if _want("death"):
			for k in DEATH_DIRS:
				for v in DEATH_VARIANTS:
					var clip := "death_d%d_%d" % [k, v]
					var sheet := await _bake_ragdoll(player, skel, model, armed, k, 1000 + k * 17 + v * 131)
					_save_cropped(sheet, DEATH.size, skin, clip, preview_rows)
	_model.queue_free()
	await process_frame


## One 8-direction locomotion loop (see GAIT): one sprite frame per KEY POSE of a key-pose clip
## (tools/keypose.py: contact / down / passing / up per foot, picked from the mocap and
## exaggerated; sidecar art/mocap/keys/<clip>.json has their phases and the stride), the legs
## re-aimed for the diagonals, each key held until the next.
func _bake_gait(player: AnimationPlayer, lib: AnimationLibrary, skel: Skeleton3D, model: Node3D,
		name: String, spec: Dictionary, skin: String, preview_rows: Array[Image]) -> void:
	var anim := lib.get_animation(name)
	player.play(name)
	var info := _key_info(spec.clip)
	var phases: Array = info.phases
	var n := phases.size()
	var phi: float = spec.aim
	var at := func(i: int, aim: float, means: Array) -> void:
		player.seek(anim.length * float(i) / float(n - 1), true)
		_fix_head(skel)
		if means.size() > 0 and absf(aim) > 0.01:
			_reaim_legs(skel, model, means, aim)
	# Neutral (mean) foot offsets from the hips over the cycle, weighted by how long each key is held.
	var means := [Vector2.ZERO, Vector2.ZERO]
	for i in n:
		at.call(i, 0.0, [])
		var hold: float = (float(phases[(i + 1) % n]) - float(phases[i]) + (1.0 if i == n - 1 else 0.0))
		for f in 2:
			means[f] += _foot_off(skel, model, f) * hold
	var stride: float = info.stride
	print("GAIT %s from %s: stride %.3f units/loop, key phases %s" % [name, spec.clip, stride, phases])
	_force_starts = phases.duplicate()
	var sheet := await _bake(n, CharSprite.FRAME, func(i: int) -> void:
		at.call(i, phi, means)
		_pose_keys(skel, model, [Poses.key(0.0, Vector3.ZERO, Poses.hold())], 0.0), 0, true)
	_meta_extra = {"stride": snappedf(stride, 0.001), "go": spec.go, "labels": info.labels}
	_save(sheet, skin, name, preview_rows, _anchors)


## Sidecar of a key-pose clip written by tools/keypose.py.
func _key_info(clip: String) -> Dictionary:
	var f := FileAccess.open("res://art/mocap/keys/%s.json" % clip, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


## Foot (0 = left, 1 = right) position relative to the hips, horizontal (x = character's left,
## y = forward), model space.
func _foot_off(skel: Skeleton3D, model: Node3D, foot: int) -> Vector2:
	var d := _bone_pos(skel, model, "LeftFoot" if foot == 0 else "RightFoot") - _bone_pos(skel, model, "Hips")
	return Vector2(d.x, d.z)


## Re-aims the current leg pose: each foot's offset from its neutral position (`means`) is turned
## by `deg` about the vertical axis, then thigh + shin are solved with 2-bone IK (knee forward),
## the foot keeps its orientation.
func _reaim_legs(skel: Skeleton3D, model: Node3D, means: Array, deg: float) -> void:
	var hips := _bone_pos(skel, model, "Hips")
	for f in 2:
		var side := "Left" if f == 0 else "Right"
		var foot := _bone_pos(skel, model, side + "Foot")
		var off := Vector2(foot.x - hips.x, foot.z - hips.z)
		var swing := (off - means[f] as Vector2).rotated(deg_to_rad(-deg))
		# Vector2.rotated turns x toward y (x = left, y = forward): toward-left is -angle here.
		var want_xz: Vector2 = Vector2(hips.x, hips.z) + (means[f] as Vector2) + swing
		var goal := Vector3(want_xz.x, foot.y, want_xz.y)
		var h := _bone_pos(skel, model, side + "UpLeg")
		var k := _bone_pos(skel, model, side + "Leg")
		var a := h.distance_to(k)
		var b := k.distance_to(foot)
		var to := goal - h
		var d := clampf(to.length(), absf(a - b) + 0.001, a + b - 0.001)
		var u := to.normalized()
		var ca := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
		var pole := Vector3(0, 0, 1)
		var n := (pole - u * pole.dot(u)).normalized()
		var knee := h + u * a * ca + n * a * sqrt(1.0 - ca * ca)
		var foot_basis := skel.get_bone_global_pose(skel.find_bone(side + "Foot")).basis
		_aim_bone(skel, model, side + "UpLeg", side + "Leg", (knee - h).normalized())
		var k2 := _bone_pos(skel, model, side + "Leg")
		_aim_bone(skel, model, side + "Leg", side + "Foot", (h + u * d - k2).normalized())
		var fb := skel.find_bone(side + "Foot")
		var gp := skel.get_bone_global_pose(fb)
		gp.basis = foot_basis
		skel.set_bone_global_pose(fb, gp)


## Dive k (direction relative to the look direction, 45 deg steps): the key poses are real mocap
## frames (CMU 127_23 dive and shoulder roll, picked in tools/reshape_character.py DIVE_KEYS,
## clip KDive). The whole pose is turned toward the heading about the vertical axis, then twisted
## about its own long axis (hips -> head) by the opposite angle: upright it is exactly the look
## direction again, flat it lies tipped toward the heading with the chest still facing forward, so
## the body always faces where the player looks. In the air (coil .. reach) and when standing again
## the arms hold the rifle on the aim line (IK, world frame); on the ground the mocap arms push
## off and the gun is slung (not drawn). Last key = the standing hold. Each key held to the next.
func _bake_dive(player: AnimationPlayer, lib: AnimationLibrary, skel: Skeleton3D, model: Node3D, k: int, skin: String, preview_rows: Array[Image]) -> void:
	var info := _key_info("KDive")
	var phases: Array = info.phases
	var labels: Array = info.labels
	var nm := phases.size()
	var anim := lib.get_animation("KDive")
	var psi := deg_to_rad(float(k) * 45.0)
	var holds: Array = labels.map(func(l: String) -> bool: return l in ["coil", "push", "extend", "reach", "stand"])
	holds.append(true)
	_force_starts = phases.duplicate()
	_force_starts.append(1.0)
	var sheet := await _bake(nm + 1, DIVE_SIZE, func(i: int) -> void:
		if i < nm:
			player.play("KDive")
			player.seek(anim.length * float(i) / float(nm - 1), true)
		else:
			player.play("idle_aim")
			player.seek(0.0, true)
		_fix_head(skel)
		var a0 := (_bone_pos(skel, model, "Head") - _bone_pos(skel, model, "Hips")).normalized() if i < nm else Vector3.UP
		var body := Basis(Basis(Vector3.UP, -psi) * a0, psi) * Basis(Vector3.UP, -psi)
		var centre := _model.transform * _bone_pos(skel, model, "Hips")
		_pivot.transform = Transform3D(body, centre - body * centre)
		_hold_pocket = Vector3.INF
		if holds[i]:
			_hold_arms(skel, model, body.inverse()), 0, false)
	_meta_extra = {"labels": labels + ["stand_hold"], "mocap": "CMU 127_23"}
	_save_cropped(sheet, DIVE_SIZE, skin, "dive_%d" % k, preview_rows, _anchors)


## Arms on the shouldered rifle (IK in the aim frame `rp`, see _hold_targets).
func _hold_arms(skel: Skeleton3D, model: Node3D, rp: Basis) -> void:
	var targets := _hold_targets(skel, model, rp)
	_hold_pocket = targets.pocket
	for limb in ["LArm", "LFore", "RArm", "RFore"]:
		var bones: Array = Poses.LIMBS[limb]
		var from := _bone_pos(skel, model, bones[0])
		_aim_bone(skel, model, bones[0], bones[1], ((targets[limb] as Vector3) - from).normalized())


## Ragdoll death from the standing pose (gun hold if armed), pushed toward direction `dir`.
func _bake_ragdoll(player: AnimationPlayer, skel: Skeleton3D, model: Node3D, armed: bool, dir: int, seed_: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	player.play("idle_aim" if armed else "idle")
	player.seek(0.0, true)
	_fix_head(skel)
	if armed:
		_pose_keys(skel, model, [Poses.key(0.0, Vector3.ZERO, Poses.hold())], 0.0)
	_hold_pocket = Vector3.INF
	var floor_y := INF
	for b in ["LeftToes", "RightToes", "LeftFoot", "RightFoot"]:
		floor_y = minf(floor_y, _bone_pos(skel, model, b).y)
	var rag := BakeRagdoll.new()
	rag.build(skel, _holder, floor_y - 0.08)
	# Push in sprite / screen space (screen x = world X, screen y = world Z): direction `dir`
	# times 45 deg clockwise from screen-down, jittered; force, lift and spin from the seed.
	var ang := deg_to_rad(dir * 45.0 + rng.randf_range(-12.0, 12.0))
	var speed := rng.randf_range(4.5, 9.0)
	var push := Vector3(sin(ang), rng.randf_range(0.1, 0.5), cos(ang)).normalized() * speed
	var spin := Vector3(rng.randf_range(-3, 3), rng.randf_range(-4, 4), rng.randf_range(-3, 3))
	var steps := maxi(1, int(DEATH_TIME * Engine.physics_ticks_per_second / (DEATH.frames - 1)))
	var sheet := await _bake(DEATH.frames, DEATH.size, func(i: int) -> void:
		if i == 1:
			rag.start(push, spin)
		if i >= 1:
			for k in steps:
				await physics_frame, DEATH.keys, false, func(size: int) -> PackedVector2Array:
			# Simulated bodies (the skeleton query returns the animated pose during the ragdoll).
			var js := PackedVector2Array()
			for b in ["Hips", "Head", "LeftForeArm", "RightForeArm", "LeftLeg", "RightLeg"]:
				var pb: PhysicalBone3D = rag.bodies.get(b)
				if pb:
					var w := pb.global_position
					js.append(Vector2(w.x - _cam.position.x, w.z - _cam.position.z) * CharSprite.PX_PER_UNIT + Vector2(size, size) / 2.0)
			return js)
	rag.stop()
	await process_frame
	return sheet


## Renders n dense frames of size px (pose(i) sets up frame i, may await), each at
## SUPERSAMPLE x and reduced by majority vote, then keeps `keys` key poses (0 = all): the
## frames where the visible joints move least (pose extremes) plus fills for long gaps. Sets
## _anchors / _starts for the kept frames and returns their sheet.
func _bake(n: int, size: int, pose: Callable, keys := 0, loop := true, joints_fn := Callable()) -> Image:
	var big := size * SUPERSAMPLE
	_vp.size = Vector2i(big, big)
	_cam.size = size / CharSprite.PX_PER_UNIT
	var frames: Array[Image] = []
	var anchors: Array = []
	var joints: Array = []
	var sides: Array[Image] = []
	for i in n:
		await pose.call(i)
		var grip := _screen_px(_skel.find_bone("RightHand"), size)
		var fore := _screen_px(_skel.find_bone("LeftHand"), size)
		var line_x := (grip.x + fore.x) / 2.0
		if _hold_pocket != Vector3.INF:
			line_x = _model_to_screen(_hold_pocket, size).x
		var c := Vector2(size, size) / 2.0
		# The gun runs straight ahead (the hold keeps it level, sprites face up), centred
		# between the hands, its grip level with the right hand.
		var at := Vector2(line_x, grip.y)
		# 4th value: gun drawn (hold) or slung (not drawn)
		anchors.append([snappedf(at.x - c.x, 0.1), snappedf(at.y - c.y, 0.1), snappedf(-PI / 2.0, 0.001), 1 if _hold_pocket != Vector3.INF else 0])
		var js := PackedVector2Array()
		if joints_fn.is_valid():
			js = joints_fn.call(size)
		else:
			for b in ["Hips", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
				js.append(_screen_px(_skel.find_bone(b), size))
		joints.append(js)
		await process_frame
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img = _majority_down(img, SUPERSAMPLE)
		_outline(img)
		frames.append(img)
		if _side_dir != "":
			sides.append(await _side_image(size))
	var kept: Array = range(n) if keys <= 0 or keys >= n else _pick_keys(joints, keys, loop)
	var sheet := Image.create(size * kept.size(), size, false, Image.FORMAT_RGBA8)
	_anchors.clear()
	_starts.clear()
	for j in kept.size():
		sheet.blit_rect(frames[kept[j]], Rect2i(0, 0, size, size), Vector2i(j * size, 0))
		_anchors.append(anchors[kept[j]])
		_starts.append(snappedf(float(kept[j]) / n, 0.0001) if _force_starts.is_empty() else _force_starts[j])
	_force_starts = []
	_side_strip = null
	if _side_dir != "":
		_side_strip = Image.create(SIDE_PX * kept.size(), SIDE_PX, false, Image.FORMAT_RGBA8)
		for j in kept.size():
			_side_strip.blit_rect(sides[kept[j]], Rect2i(0, 0, SIDE_PX, SIDE_PX), Vector2i(j * SIDE_PX, 0))
	return sheet


## The current pose seen from the side (character faces screen-right), SIDE_PX square.
func _side_image(top_size: int) -> Image:
	var p := _cam.position
	var r := _cam.rotation_degrees
	var sz := _cam.size
	_vp.size = Vector2i(SIDE_PX * SUPERSAMPLE, SIDE_PX * SUPERSAMPLE)
	_cam.size = 4.6
	_cam.rotation_degrees = Vector3(0, 90, 0)
	_cam.position = Vector3(20, 1.75, p.z)
	await process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img = _majority_down(img, SUPERSAMPLE)
	_cam.position = p
	_cam.rotation_degrees = r
	_cam.size = sz
	_vp.size = Vector2i(top_size * SUPERSAMPLE, top_size * SUPERSAMPLE)
	return img


## Key poses: local minima of joint speed (screen space, i.e. what reads from above), the
## stillest first, at least 2 dense frames apart; then the longest gaps are split until there
## are `k`. Non-looping clips always keep the first and last frame.
func _pick_keys(joints: Array, k: int, loop: bool) -> Array:
	var n := joints.size()
	var speed: Array[float] = []
	for i in n:
		var p := (i - 1 + n) % n if loop else maxi(i - 1, 0)
		var sp := 0.0
		for j in joints[i].size():
			var d: float = joints[i][j].distance_to(joints[p][j])
			if not is_nan(d):
				sp += minf(d, 24.0)  # a glitchy joint jump must not swamp the curve
		speed.append(sp)
	if not loop:
		# One-shot clips: keys at equal amounts of visible pose change (arc length of the
		# joints' screen paths). Fast stretches skip in time, slow / settled ones collapse to
		# a single held pose.
		var cum: Array[float] = [0.0]
		for i in range(1, n):
			cum.append(cum[i - 1] + speed[i])
		var total: float = cum[n - 1]
		var keys_: Array = []
		for j in k:
			var target := total * j / (k - 1)
			var i := 0
			while i < n - 1 and cum[i] < target - 1e-4:
				i += 1
			if keys_.is_empty() or i > keys_[-1]:
				keys_.append(i)
		if keys_[-1] != n - 1:
			keys_.append(n - 1)
		if OS.is_stdout_verbose():
			print("speeds ", speed, " keys ", keys_)
		return keys_
	var dist := func(a: int, b: int) -> int:
		var d := absi(a - b)
		return mini(d, n - d) if loop else d
	# A body lying still is one pose: in a run of near-motionless frames only the first one
	# can be a key (so keys go to the motion, not the settled tail).
	var top: float = speed.max()
	var still := func(i: int) -> bool: return speed[i] < top * 0.12
	var mins: Array = []
	for i in n:
		var a := speed[(i - 1 + n) % n] if loop or i > 0 else INF
		var b := speed[(i + 1) % n] if loop or i < n - 1 else INF
		if speed[i] <= a and speed[i] <= b:
			if still.call(i) and i > 0 and still.call(i - 1):
				continue
			mins.append(i)
	mins.sort_custom(func(x: int, y: int) -> bool: return speed[x] < speed[y])
	var chosen: Array = [] if loop else [0, n - 1]
	for m in mins:
		if chosen.size() >= k:
			break
		if chosen.all(func(c: int) -> bool: return dist.call(m, c) >= 2):
			chosen.append(m)
	# Fill the longest gaps, but not inside a still stretch.
	while chosen.size() < k:
		chosen.sort()
		var best := -1
		var gap := 1
		for j in chosen.size():
			var a: int = chosen[j]
			var b: int = chosen[(j + 1) % chosen.size()] if (loop or j + 1 < chosen.size()) else a
			var g := (b - a + n) % n if loop else b - a
			if loop and chosen.size() == 1:
				g = n
			if g > gap and not (still.call((a + g / 2) % n) and still.call(a)):
				gap = g
				best = j
		if best < 0:
			break
		chosen.append((int(chosen[best]) + gap / 2) % n)
	chosen.sort()
	return chosen


## Downscale by f: each output pixel is opaque if most of its f x f block is, and takes the
## block's most common opaque colour (flat clusters, no averaged in-between colours).
func _majority_down(img: Image, f: int) -> Image:
	if f <= 1:
		return img
	var w := img.get_width() / f
	var h := img.get_height() / f
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var counts := {}
			var opaque := 0
			for dy in f:
				for dx in f:
					var c := img.get_pixel(x * f + dx, y * f + dy)
					if c.a >= 0.5:
						opaque += 1
						var key := c.to_rgba32()
						counts[key] = counts.get(key, 0) + 1
			if opaque * 2 < f * f:
				continue
			var best := 0
			var bc := 0
			for key in counts:
				if counts[key] > bc:
					bc = counts[key]
					best = key
			out.set_pixel(x, y, Color.hex(best))
	return out


## Saves a sheet cropped to the union of its frames' used areas; the crop rect (in frame
## pixels) goes to <clip>.json as "rect" so the game draws it at the right offset.
func _save_cropped(sheet: Image, size: int, skin: String, clip: String, preview_rows: Array[Image], anchors := []) -> void:
	var n := sheet.get_width() / size
	var u := Rect2i()
	for i in n:
		var r := sheet.get_region(Rect2i(i * size, 0, size, size)).get_used_rect()
		if r.size != Vector2i.ZERO:
			u = r if u.size == Vector2i.ZERO else u.merge(r)
	var out := Image.create(u.size.x * n, u.size.y, false, Image.FORMAT_RGBA8)
	for i in n:
		out.blit_rect(sheet, Rect2i(i * size + u.position.x, u.position.y, u.size.x, u.size.y), Vector2i(i * u.size.x, 0))
	_write_side(skin, clip)
	out.save_png(ProjectSettings.globalize_path(OUT_DIR + "%s/%s.png" % [skin, clip]))
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "%s/%s.json" % [skin, clip]), FileAccess.WRITE)
	var meta := {"frame": size, "frames_n": n, "rect": [u.position.x, u.position.y, u.size.x, u.size.y], "starts": _starts}
	if not anchors.is_empty():
		meta["frames"] = anchors
	f.store_string(JSON.stringify(meta))
	preview_rows.append(sheet)
	print("baked ", clip, " frames=", n, " crop=", u.size)


func _write_side(skin: String, clip: String) -> void:
	if _side_dir != "" and _side_strip != null:
		DirAccess.make_dir_recursive_absolute(_side_dir)
		_side_strip.save_png(_side_dir.path_join("%s_%s_side.png" % [skin, clip]))


## Saves a sheet plus <clip>.json: frame phase starts and (armed) weapon anchors per frame
## (grip offset from the frame centre in px, gun angle in rad, sprite facing up).
func _save(sheet: Image, skin: String, anim_name: String, preview_rows: Array[Image], anchors := []) -> void:
	var path := OUT_DIR + "%s/%s.png" % [skin, anim_name]
	sheet.save_png(ProjectSettings.globalize_path(path))
	_write_side(skin, anim_name)
	var meta := {"starts": _starts}
	meta.merge(_meta_extra)
	_meta_extra = {}
	if not anchors.is_empty():
		meta["frames"] = anchors
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "%s/%s.json" % [skin, anim_name]), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	preview_rows.append(sheet)
	print("baked ", path, " frames=", sheet.get_width() / sheet.get_height())


## Bone position in the frame (pixels from the top-left), from the current pose.
func _screen_px(bone: int, size: int) -> Vector2:
	return _model_to_screen(_to_model(_skel, _model) * _skel.get_bone_global_pose(bone).origin, size)


func _model_to_screen(m: Vector3, size: int) -> Vector2:
	var w := _holder.transform * _pivot.transform * _model.transform * m
	return Vector2(w.x - _cam.position.x, w.z - _cam.position.z) * CharSprite.PX_PER_UNIT + Vector2(size, size) / 2.0


func _fix_head(skel: Skeleton3D) -> void:
	skel.set_bone_pose_scale(skel.find_bone("Head"), Vector3.ONE * HEAD_SCALE)


## Whole-body rotation of a key: Euler `rot` then the lean (heading deg clockwise from forward as
## seen from above, tilt deg) about the horizontal axis that tips the head toward the heading.
func _key_basis(k: Dictionary) -> Basis:
	var b := Basis.from_euler((k.rot as Vector3) * (PI / 180.0))
	var lean: Vector2 = k.get("lean", Vector2.ZERO)
	if absf(lean.y) > 0.001:
		var h := deg_to_rad(lean.x)
		var d := Vector3(-sin(h), 0.0, cos(h)) # x = character's left, z = forward
		b = Basis(Vector3.UP.cross(d).normalized(), deg_to_rad(lean.y)) * b
	return b


## Keyed pose at t (0..1) on top of the current (idle) pose: whole-body rotation around the hips,
## limbs aimed along interpolated directions (see tools/poses.gd). With a weapon hold the arms are
## solved by IK in the AIM frame: the body rotation undone, so the gun stays level, pointing
## ahead (the look direction) however the body is tilted.
func _pose_keys(skel: Skeleton3D, model: Node3D, keys: Array, t: float) -> void:
	var ka: Dictionary = keys[0]
	var kb: Dictionary = keys[-1]
	for i in range(1, keys.size()):
		if t <= keys[i].t:
			ka = keys[i - 1]
			kb = keys[i]
			break
	var f := smoothstep(0.0, 1.0, inverse_lerp(ka.t, kb.t, t)) if kb.t > ka.t else 1.0
	var qa := _key_basis(ka).get_rotation_quaternion()
	var qb := _key_basis(kb).get_rotation_quaternion()
	var body := Basis(qa.slerp(qb, f))
	# Rotate about the hips (centre of the silhouette), not the feet.
	var centre := _model.transform * _bone_pos(skel, model, "Hips")
	_pivot.transform = Transform3D(body, centre - body * centre)
	# Weapon hold (IK) when either key holds.
	var ha = ka.limbs.get("_hold")
	var hb = kb.limbs.get("_hold")
	var holding: bool = ha != null or hb != null
	var targets := {}
	_hold_pocket = Vector3.INF
	for limb in Poses.ORDER:
		if limb == "LArm" and holding:
			# Spine and head are placed: the shoulders are where they will stay.
			targets = _hold_targets(skel, model, body.inverse())
			_hold_pocket = targets.get("pocket", Vector3.INF)
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
	if holding and targets.is_empty():
		_hold_pocket = Vector3.INF


## IK targets for the shouldered hold in the aim frame `rp` (undoes the body rotation):
## {"RArm": elbow, "RFore": hand, "LArm": elbow, "LFore": hand, "pocket": stock point}, model space.
func _hold_targets(skel: Skeleton3D, model: Node3D, rp: Basis) -> Dictionary:
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
	if img.get_width() * img.get_height() < 16_000_000:
		img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir.path_join("bake_preview.png"))
