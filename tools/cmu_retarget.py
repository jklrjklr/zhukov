"""Retargets CMU Graphics Lab mocap (BVH, http://mocap.cs.cmu.edu) onto our character rig in
Blender. Used by tools/reshape_character.py.

Both rigs rest in a T-pose facing -Y (left = +X), so each mapped bone takes the source bone's
world rotation relative to its rest:   R_target = R_source * R_source_rest^-1 * R_target_rest.
The clip is turned so the body faces -Y, resampled to 30 fps, and (in place) the forward travel
is removed while the hip sway / bob is kept (scaled by the leg-length ratio). Looping clips get
an automatically found seamless loop.

CMU data: free to use, including in commercial games (the raw data itself may not be resold).
"""
import math
import bpy
from mathutils import Matrix, Quaternion, Vector

# CMU bone -> our bone.
MAP = {
    "Hips": "Hips", "LowerBack": "Spine", "Spine": "Chest", "Spine1": "UpperChest",
    "Neck": "Neck", "Head": "Head",
    "LeftShoulder": "LeftShoulder", "LeftArm": "LeftArm", "LeftForeArm": "LeftForeArm", "LeftHand": "LeftHand",
    "RightShoulder": "RightShoulder", "RightArm": "RightArm", "RightForeArm": "RightForeArm", "RightHand": "RightHand",
    "LeftUpLeg": "LeftUpLeg", "LeftLeg": "LeftLeg", "LeftFoot": "LeftFoot", "LeftToeBase": "LeftToes",
    "RightUpLeg": "RightUpLeg", "RightLeg": "RightLeg", "RightFoot": "RightFoot", "RightToeBase": "RightToes",
}
CMU_LEG = 16.26  # hip-to-toe length of the CMU skeleton in BVH units
SRC_FPS = 120.0  # default (CMU); read from the BVH header per file
FPS = 30.0
# 100STYLE (Mason, Starke, Komura; CC BY 4.0) skeleton -> the CMU names used by MAP (Chest3 is
# skipped: Chest4 drives UpperChest). Applied through temporary names so the swaps don't clash.
STYLE100 = {
    "Chest": "LowerBack", "Chest2": "Spine", "Chest4": "Spine1",
    "RightCollar": "RightShoulder", "RightShoulder": "RightArm", "RightElbow": "RightForeArm",
    "RightWrist": "RightHand", "LeftCollar": "LeftShoulder", "LeftShoulder": "LeftArm",
    "LeftElbow": "LeftForeArm", "LeftWrist": "LeftHand",
    "RightHip": "RightUpLeg", "RightKnee": "RightLeg", "RightAnkle": "RightFoot", "RightToe": "RightToeBase",
    "LeftHip": "LeftUpLeg", "LeftKnee": "LeftLeg", "LeftAnkle": "LeftFoot", "LeftToe": "LeftToeBase",
}


def _bvh_fps(path):
    with open(path) as f:
        for line in f:
            if line.startswith("Frame Time"):
                return 1.0 / float(line.split(":")[1])
    return SRC_FPS


def _to_cmu_names(src):
    """Renames a 100STYLE armature's bones to the CMU names."""
    if "Chest2" not in src.data.bones:
        return
    for a in STYLE100:
        src.data.bones[a].name = "tmp_" + a
    for a, b in STYLE100.items():
        src.data.bones["tmp_" + a].name = b
# Bones compared when looking for a seamless loop.
LOOP_BONES = ["LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg", "LeftArm", "RightArm"]


def _world_rot(obj, mat):
    return (obj.matrix_world.to_3x3() @ mat.to_3x3()).normalized().to_quaternion()


def _order(arm):
    """Target bones parents-first."""
    out = []

    def walk(b):
        out.append(b.name)
        for c in b.children:
            walk(c)
    for b in arm.data.bones:
        if b.parent is None:
            walk(b)
    return [n for n in out if n in MAP.values()]


def _swap(n):
    return n.replace("Left", "@").replace("Right", "Left").replace("@", "Right")


def _mirror_q(q):
    # Reflection across the YZ plane (x -> -x): conjugate by diag(-1, 1, 1).
    return Quaternion((q.w, q.x, -q.y, -q.z))


def _src_pose(src, frame, mirror=False):
    bpy.context.scene.frame_set(frame)
    rots = {n: _world_rot(src, src.pose.bones[n].matrix) for n in MAP if n in src.pose.bones}
    pb = src.pose.bones
    hips = src.matrix_world @ pb["Hips"].head
    left = (src.matrix_world @ pb["LeftUpLeg"].head) - (src.matrix_world @ pb["RightUpLeg"].head)
    local = {n: pb[n].matrix_basis.to_quaternion() for n in LOOP_BONES if n in pb}
    head = src.matrix_world @ pb["Head"].head
    if mirror:
        rots = {_swap(n): _mirror_q(q) for n, q in rots.items()}
        hips = Vector((-hips.x, hips.y, hips.z))
        left = Vector((left.x, -left.y, -left.z))  # mirrored right-to-left vector
        local = {_swap(n): _mirror_q(q) for n, q in local.items()}
        head = Vector((-head.x, head.y, head.z))
    return rots, hips, left, local, head


def _find_loop(poses, min_len, max_len):
    """Start / end sample indices whose poses match best (end exclusive)."""
    best = (1e9, 0, len(poses))
    n = len(poses)
    for s in range(0, max(1, n // 3)):
        for e in range(s + min_len, min(n, s + max_len)):
            d = 0.0
            for k in (0, 1):
                a = poses[s + k][3]
                b = poses[min(e + k, n - 1)][3]
                d += sum(a[b_].rotation_difference(b[b_]).angle for b_ in a)
            if d < best[0]:
                best = (d, s, e)
    return best[1], best[2]


def _segment(poses, direction, min_speed=0.25, unit=17.0):
    """Longest run of samples moving `direction` ('fwd', 'back', 'left', 'right') relative to
    the pelvis facing. Returns (start, end) sample indices."""
    want = {"fwd": (1, 0), "back": (-1, 0), "left": (0, 1), "right": (0, -1)}[direction]
    best = (0, 0, 0)
    run = None
    for i in range(1, len(poses)):
        v = poses[i][1] - poses[i - 1][1]
        l = poses[i][2].copy()
        l.z = 0
        l.normalize()
        f = Vector((l.y, -l.x, 0))
        v.z = 0
        sp = v.length * FPS
        ok = False
        if sp > min_speed * unit:  # `unit` = source units per leg length (CMU ~17)
            d = (v.dot(f) / v.length, v.dot(l) / v.length)
            ok = d[0] * want[0] + d[1] * want[1] > 0.8
        if ok:
            run = run if run is not None else i
            if i - run > best[0]:
                best = (i - run, run, i)
        else:
            run = None
    return best[1], best[2]


def retarget(arm, bvh, name, start=0.0, end=None, loop=False, in_place=True,
             loop_len=(0.6, 1.6), keep_yaw=False, direction=None, mirror=False, align="pelvis"):
    """Imports `bvh`, bakes clip `name` onto armature `arm` (seconds start..end of the take;
    `direction` = pick the longest stretch walking that way relative to the body; `mirror` =
    left / right swapped, applied before `direction`), returns the new action."""
    scene = bpy.context.scene
    before = set(bpy.data.objects)
    bpy.ops.import_anim.bvh(filepath=bvh, update_scene_fps=False, update_scene_duration=False)
    src = next(o for o in bpy.data.objects if o not in before)
    _to_cmu_names(src)
    src_fps = _bvh_fps(bvh)
    f0, f1 = src.animation_data.action.frame_range
    a = int(f0 + start * src_fps)
    b = int(min(f1, f0 + (end if end is not None else 1e9) * src_fps))
    step = int(round(src_fps / FPS))
    poses = [_src_pose(src, f, mirror) for f in range(a, b + 1, step)]
    if direction:
        leg_u = -(src.matrix_world @ src.data.bones["LeftToeBase"].head_local).z + (src.matrix_world @ src.data.bones["Hips"].head_local).z
        s0, e0 = _segment(poses, direction, unit=17.0 * leg_u / CMU_LEG)
        print("RETARGET %s %s segment %.2f..%.2f s" % (name, direction, start + s0 / FPS, start + e0 / FPS))
        poses = poses[s0:e0 + 1]
    if loop:
        s, e = _find_loop(poses, int(loop_len[0] * FPS), int(loop_len[1] * FPS))
        poses = poses[s:e]
        print("RETARGET %s loop %d frames (%.2f s from %.2f s)" % (name, len(poses), len(poses) / FPS, start + s / FPS))

    # Facing: average pelvis direction -> -Y (left = +X); or, for lying poses, the body line
    # (hips -> head) of the last ("end_body") / first ("start_body") frames -> -Y.
    yaw = 0.0
    if not keep_yaw:
        if align.startswith("body@"):
            # hips -> head of the samples a..b (30 fps indices) points -Y (e.g. a dive's flight)
            a_, b_ = (int(v) for v in align[5:].split("-"))
            bv = sum((p[4] - p[1] for p in poses[a_:b_ + 1]), Vector((0, 0, 0)))
            yaw = -math.pi / 2 - math.atan2(bv.y, bv.x)
        elif align in ("end_body", "start_body"):
            sel = poses[-6:] if align == "end_body" else poses[:6]
            bv = sum((p[4] - p[1] for p in sel), Vector((0, 0, 0)))
            yaw = -math.pi / 2 - math.atan2(bv.y, bv.x)
        else:
            lv = sum((p[2] for p in poses), Vector((0, 0, 0)))
            yaw = -math.atan2(lv.y, lv.x)
    rz = Quaternion((0, 0, 1), yaw)
    rzm = rz.to_matrix()

    # Rest frames.
    src_rest = {n: _world_rot(src, src.data.bones[n].matrix_local) for n in MAP if n in src.data.bones}
    if mirror:
        src_rest = {_swap(n): _mirror_q(q) for n, q in src_rest.items()}
    tgt_rest = {MAP[n]: _world_rot(arm, arm.data.bones[MAP[n]].matrix_local) for n in MAP if MAP[n] in arm.data.bones}
    src_leg = -(src.matrix_world @ src.data.bones["LeftToeBase"].head_local).z + (src.matrix_world @ src.data.bones["Hips"].head_local).z
    tgt_hips0 = arm.matrix_world @ arm.data.bones["Hips"].head_local
    toes = min((arm.matrix_world @ arm.data.bones[t].head_local).z for t in ("LeftToes", "RightToes"))
    tgt_leg = tgt_hips0.z - toes
    k = tgt_leg / src_leg

    # Hips travel: remove the straight-line trend (in place), keep sway / bob.
    hp = [rzm @ p[1] for p in poses]
    n = len(hp)
    lin0, lin1 = hp[0], hp[-1]
    if loop:
        # average velocity over the loop
        vel = (lin1 - lin0) / max(1, n - 1)
    else:
        vel = Vector((0, 0, 0))

    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    order = _order(arm)
    inv_tgt_to_src = {v: k_ for k_, v in MAP.items()}
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    awi = arm.matrix_world.inverted()
    for i, pose in enumerate(poses):
        rots = pose[0]
        for tname in order:
            sname = inv_tgt_to_src[tname]
            if sname not in rots:
                continue
            rt = rz @ rots[sname] @ src_rest[sname].inverted() @ tgt_rest[tname]
            pb = arm.pose.bones[tname]
            m = awi @ Matrix.Translation(arm.matrix_world @ pb.head) @ rt.to_matrix().to_4x4()
            if tname == "Hips":
                p = hp[i]
                if in_place == "lock":
                    # Hips pinned over the origin (the game moves the character): only height.
                    p = Vector((lin0.x, lin0.y, p.z))
                    off = Vector((0, 0, 0))
                elif in_place:
                    p = p - vel * i - Vector((lin0.x, lin0.y, 0))
                    off = Vector((p.x * k, p.y * k, 0))
                else:
                    off = Vector(((p.x - lin0.x) * k, (p.y - lin0.y) * k, 0))
                z = tgt_hips0.z + (p.z - src_leg) * k
                m.translation = awi @ Vector((tgt_hips0.x + off.x, tgt_hips0.y + off.y, z))
            pb.matrix = m
            bpy.context.view_layer.update()
        for tname in order:
            pb = arm.pose.bones[tname]
            pb.keyframe_insert("rotation_quaternion", frame=i + 1)
            if tname == "Hips":
                pb.keyframe_insert("location", frame=i + 1)
    # Reset the rig and drop the source.
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    src_act = src.animation_data.action
    bpy.data.objects.remove(src, do_unlink=True)
    if src_act:
        bpy.data.actions.remove(src_act)
    act.use_fake_user = True
    travel = ((hp[-1] - hp[0]) * k)
    travel.z = 0
    if loop:
        travel = vel * len(poses) * k
        travel.z = 0
    print("RETARGET %s: %d frames, travel per clip %.3f units" % (name, len(poses), travel.length))
    return act
