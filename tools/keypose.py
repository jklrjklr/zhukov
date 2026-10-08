"""Key-pose selection and exaggeration for the player's mocap locomotion (Blender).

Input: a dense, retargeted, looping action (tools/cmu_retarget.py). Output: an action with one
frame per KEY POSE (frame i + 1 = key i) and a sidecar json (art/mocap/keys/<name>.json) with the
key names, their phase in the loop (pose-to-pose timing) and the measured stride.

Like a 2D animator the keys are the poses of the walk / run cycle, found in the mocap itself:
  walk: contact (lead foot lands, ahead), down (hips lowest, weight), passing (swing foot passes
        the stance leg), up (hips highest, push off the toe)
  run:  contact, down (hips lowest, knee absorbs), push (stance leg extended behind), flight
        (both feet off the ground, hips highest)
for each foot = 8 keys per cycle, starting at the LEFT foot contact. Keys are picked from foot
travel and hip height, not evenly in time.

Exaggeration (all relative to the cycle's mean pose):
  - spine / hips rotations scaled (counter-rotation of hips and shoulders reads from above),
  - hip bob and sway scaled (deeper down pose), forward lean added,
  - foot offsets from the hips scaled along the travel direction (longer strides), a little wider
    laterally, swing height scaled (knees and feet lift higher),
  - legs re-solved with 2-bone IK (knee forward) so a planted foot keeps its height: the lowest
    point of each foot stays on the ground plane at contacts and toe-off, and the hips are never
    raised past what the planted leg can reach.
Arms are not touched here: armed sprites put them on the weapon hold (IK) at bake time.
"""
import json
import math
import os
import bpy
from mathutils import Matrix, Quaternion, Vector

LEGS = {"Left": ("LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToes"),
        "Right": ("RightUpLeg", "RightLeg", "RightFoot", "RightToes")}
# Bones whose rotation deviation from the cycle mean is scaled, with their scale key.
SCALED = {"Hips": "hips", "Spine": "twist", "Chest": "twist", "UpperChest": "twist",
          "Neck": "head", "Head": "head"}
GO = {"fwd": (0.0, -1.0), "back": (0.0, 1.0), "right": (-1.0, 0.0), "left": (1.0, 0.0)}

# Per kind: exaggeration factors and step-phase targets (where in each step the 4 keys start;
# contacts and passing / flight are the strong poses and get the longer holds).
KINDS = {
    "walk": dict(stride=1.5, side=1.35, lift=2.4, bob=2.0, sway=1.3, hips=1.0, twist=1.0, head=0.8,
                 lean=5.0, crouch=0.09, timing=[0.0, 0.2, 0.5, 0.8], blend=0.5, stance_end=3),
    "strafe": dict(stride=1.4, side=1.2, lift=2.0, bob=1.8, sway=1.2, hips=1.0, twist=1.0, head=0.8,
                   lean=0.0, crouch=0.08, timing=[0.0, 0.2, 0.5, 0.8], blend=0.5, stance_end=3),
    "back": dict(stride=1.5, side=1.35, lift=2.2, bob=1.8, sway=1.3, hips=1.0, twist=1.0, head=0.8,
                 lean=-2.0, crouch=0.09, timing=[0.0, 0.2, 0.5, 0.8], blend=0.5, stance_end=3),
    "run": dict(stride=1.4, side=1.3, lift=1.9, bob=1.6, sway=1.3, hips=1.0, twist=1.0, head=0.8,
                lean=11.0, crouch=0.05, timing=[0.0, 0.2, 0.42, 0.62], blend=0.5, stance_end=2),
}


def _wpos(arm, name):
    return arm.matrix_world @ arm.pose.bones[name].head


def _mean_quat(qs):
    ref = qs[0]
    acc = Quaternion((0, 0, 0, 0))
    for q in qs:
        s = 1.0 if q.dot(ref) >= 0 else -1.0
        acc = Quaternion((acc.w + s * q.w, acc.x + s * q.x, acc.y + s * q.y, acc.z + s * q.z))
    return acc.normalized()


def _scale_dev(mean, q, s):
    """mean * slerp(identity, mean^-1 q, s): the deviation from the mean pose scaled by s."""
    d = mean.inverted() @ q
    if d.w < 0:
        d = Quaternion((-d.w, -d.x, -d.y, -d.z))
    ax, an = d.to_axis_angle()
    return mean @ Quaternion(ax, an * s)


def capture(arm, act):
    """Dense per-frame data of the action."""
    arm.animation_data.action = act
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    out = []
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        pb = arm.pose.bones
        d = {"q": {b.name: b.rotation_quaternion.copy() for b in pb},
             "hips": _wpos(arm, "Hips"), "frame": f}
        for side, (up, kn, ft, to) in LEGS.items():
            d[side] = {"hip": _wpos(arm, up), "knee": _wpos(arm, kn), "foot": _wpos(arm, ft),
                       "toe": _wpos(arm, to),
                       "frot": (arm.matrix_world @ pb[ft].matrix).to_3x3().to_quaternion()}
        out.append(d)
    return out


def _fwd(d, side, go):
    o = d[side]["foot"] - d["hips"]
    return o.x * go[0] + o.y * go[1]


def _landings(cap, side):
    """Frames where the foot's lowest point comes down to the ground (airborne -> grounded)."""
    n = len(cap)
    z = [min(c[side]["foot"].z, c[side]["toe"].z) for c in cap]
    lo, hi = min(z), max(z)
    g = [(v - lo) < 0.12 * (hi - lo) for v in z]
    out = [i for i in range(n) if g[i] and not g[i - 1]]
    return out


def find_keys(cap, go, kind):
    """8 key frame indices (unwrapped, into cap), starting at the left foot's contact, + labels."""
    n = len(cap)
    hz = [c["hips"].z for c in cap]
    lead = {s: [_fwd(c, s, go) for c in cap] for s in ("Left", "Right")}
    cont = {}
    for s in ("Left", "Right"):
        if kind == "strafe":
            ls = _landings(cap, s)
            cont[s] = ls[0] if ls else max(range(n), key=lambda i: lead[s][i])
        else:
            cont[s] = max(range(n), key=lambda i: lead[s][i])
    cl, cr = cont["Left"], cont["Right"]
    if not (0.3 * n < (cr - cl) % n < 0.7 * n):
        cr = (cl + n // 2) % n
    low = {s: min(min(c[s]["foot"].z, c[s]["toe"].z) for c in cap) for s in ("Left", "Right")}
    keys = []
    labels = []
    cr_u = cr if cr > cl else cr + n
    for step, (s0, s1, stance, other) in enumerate(((cl, cr_u, "Left", "Right"), (cr_u, cl + n, "Right", "Left"))):
        s, e = s0, s1
        L = e - s
        idx = lambda i: i % n
        # down: hips lowest in the first part of the step
        D = min(range(s + 1, s + max(2, int(0.55 * L))), key=lambda i: hz[idx(i)])
        D = min(D, s + max(1, L // 3))
        if kind == "run":
            # flight: hips highest after the down pose; push: between them (stance leg extended)
            U = max(range(D + 2, e), key=lambda i: hz[idx(i)])
            M = D + max(2, int(round(0.55 * (U - D))))
            M = min(M, U - 1)
        else:
            # passing: the swing foot passes the stance foot; up: push-off before the next contact
            M = None
            for i in range(D + 1, e - 2):
                if lead[other][idx(i)] - lead[stance][idx(i)] >= 0:
                    M = i
                    break
            if M is None:
                M = D + (e - D) // 2
            M = max(M, D + 2)
            M = min(M, e - 3)
            U = M + max(2, int(round(0.5 * (e - M))))
            U = min(U, e - 1)
        keys += [s, D, M, U]
        names = ("contact", "down", "push", "flight") if kind == "run" else ("contact", "down", "passing", "up")
        labels += ["%s_%s" % (nm, stance[0]) for nm in names]
    return keys, labels, n


def make(arm, dense_act, name, kind, direction, out_dir="art/mocap/keys/"):
    """Builds the key-pose action `name` from the dense `dense_act`; returns it."""
    P = KINDS[kind]
    go = GO[direction]
    cap = capture(arm, dense_act)
    n = len(cap)
    keys, labels, n = find_keys(cap, go, kind)
    if os.environ.get("KEYDEBUG"):
        print("HZ", name, [round(c["hips"].z, 3) for c in cap])
        for sd in ("Left", "Right"):
            print("LEAD", name, sd, [round(_fwd(c, sd, go), 2) for c in cap])
    print("KEYPOSE %s keys at dense frames %s of %d" % (name, [k % n for k in keys], n))

    # Cycle means (the neutral pose the exaggeration works around).
    names = [b.name for b in arm.pose.bones]
    mean_q = {b: _mean_quat([c["q"][b] for c in cap]) for b in SCALED}
    mean_hips = sum((c["hips"] for c in cap), Vector()) / n
    mean_off = {}
    low = {}
    for side in LEGS:
        mean_off[side] = sum(((c[side]["foot"] - c["hips"]) for c in cap), Vector()) / n
        low[side] = min(min(c[side]["foot"].z, c[side]["toe"].z) for c in cap)
    awi = arm.matrix_world.inverted()
    bpy.context.view_layer.update()

    def set_world(pb, wm):
        pb.matrix = awi @ wm
        bpy.context.view_layer.update()

    def rot_about_head(bone, axis, ang):
        pb = arm.pose.bones[bone]
        wm = arm.matrix_world @ pb.matrix
        p = wm.translation.copy()
        r = Matrix.Rotation(ang, 4, axis)
        set_world(pb, Matrix.Translation(p) @ r @ Matrix.Translation(-p) @ wm)

    def aim(bone, child, want):
        pb = arm.pose.bones[bone]
        cur = (_wpos(arm, child) - _wpos(arm, bone)).normalized()
        q = cur.rotation_difference(want.normalized())
        wm = arm.matrix_world @ pb.matrix
        p = wm.translation.copy()
        set_world(pb, Matrix.Translation(p) @ q.to_matrix().to_4x4() @ Matrix.Translation(-p) @ wm)

    act = bpy.data.actions.new(name)
    arm.animation_data.action = act
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    result = []  # per key: info for the sidecar
    for ki, fi in enumerate(keys):
        c = cap[fi % n]
        # 1. rotations: deviations from the mean scaled, everything else as captured
        for b in names:
            arm.pose.bones[b].rotation_quaternion = c["q"][b]
        for b, kk in SCALED.items():
            arm.pose.bones[b].rotation_quaternion = _scale_dev(mean_q[b], c["q"][b], P[kk])
        bpy.context.view_layer.update()
        # 2. lean (forward pitch about the left axis, upper body takes more, head stays up)
        lean = math.radians(P["lean"])
        if abs(lean) > 1e-4:
            rot_about_head("Hips", Vector((1, 0, 0)), lean * 0.5)
            rot_about_head("Spine", Vector((1, 0, 0)), lean * 0.5)
            rot_about_head("Neck", Vector((1, 0, 0)), -lean * 0.5)
        # 3. hips position: bob scaled about the mean height, sway scaled
        hp = c["hips"]
        tgt = Vector((mean_hips.x + P["sway"] * (hp.x - mean_hips.x), mean_hips.y + P["sway"] * (hp.y - mean_hips.y),
                      mean_hips.z + P["bob"] * (hp.z - mean_hips.z) - P.get("crouch", 0.0)))
        pbh = arm.pose.bones["Hips"]
        wm = arm.matrix_world @ pbh.matrix
        wm.translation = tgt
        set_world(pbh, wm)
        # 4. feet targets
        goals = {}
        for side, (up, kn, ft, to) in LEGS.items():
            s = c[side]
            off = s["foot"] - c["hips"]
            m = mean_off[side]
            d = Vector((off.x - m.x, off.y - m.y))
            along = d.x * go[0] + d.y * go[1]
            lat = d - Vector((go[0], go[1])) * along
            d2 = Vector((go[0], go[1])) * along * P["stride"] + lat * P["side"]
            xy = Vector((tgt.x + m.x + d2.x, tgt.y + m.y + d2.y))
            h = min(s["foot"].z, s["toe"].z) - low[side]
            z = s["foot"].z + h * (P["lift"] - 1.0)
            goals[side] = (Vector((xy.x, xy.y, z)), h)
        # keep the planted legs reachable: lower the hips if needed
        for side, (up, kn, ft, to) in LEGS.items():
            g, h = goals[side]
            if h > 0.02:
                continue
            hip = _wpos(arm, up)
            reach = 0.985 * ((_wpos(arm, kn) - hip).length + (c[side]["knee"] - c[side]["foot"]).length)
            r = math.hypot(g.x - hip.x, g.y - hip.y)
            v = math.sqrt(max(reach * reach - r * r, 1e-4))
            over = hip.z - (g.z + v)
            if over > 0:
                wm = arm.matrix_world @ pbh.matrix
                wm.translation.z -= over
                set_world(pbh, wm)
                for s2 in LEGS:
                    pass
        # 5. legs: 2-bone IK to the goals, knee forward, foot keeps its captured orientation
        for side, (up, kn, ft, to) in LEGS.items():
            g, h = goals[side]
            hip = _wpos(arm, up)
            a = (c[side]["knee"] - c[side]["hip"]).length
            b = (c[side]["foot"] - c[side]["knee"]).length
            to_t = g - hip
            dd = min(max(to_t.length, abs(a - b) + 1e-3), a + b - 1e-3)
            u = to_t.normalized()
            ca = max(-1.0, min(1.0, (a * a + dd * dd - b * b) / (2 * a * dd)))
            pole = Vector((0.12 if side == "Left" else -0.12, -1.0, 0.0))
            nv = (pole - u * pole.dot(u)).normalized()
            knee = hip + u * a * ca + nv * a * math.sqrt(max(0.0, 1 - ca * ca))
            aim(up, kn, knee - hip)
            aim(kn, ft, (hip + u * dd) - _wpos(arm, kn))
            pbf = arm.pose.bones[ft]
            wm = arm.matrix_world @ pbf.matrix
            p = wm.translation.copy()
            set_world(pbf, Matrix.Translation(p) @ c[side]["frot"].to_matrix().to_4x4())
        for pb in arm.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=ki + 1)
            if pb.name == "Hips":
                pb.keyframe_insert("location", frame=ki + 1)
        info = {}
        for side, (up, kn, ft, to) in LEGS.items():
            info[side] = {"toe": _wpos(arm, to) - _wpos(arm, "Hips"), "foot": _wpos(arm, ft)}
        info["hips_z"] = _wpos(arm, "Hips").z
        result.append(info)

    # Timing: natural phase of each key, blended toward the strong-pose hold pattern per step.
    phases = []
    start = keys[0]
    for step in range(2):
        ks = keys[4 * step:4 * step + 4]
        s = ks[0]
        e = keys[4] if step == 0 else keys[0] + n
        for j, kf in enumerate(ks):
            nat = (kf - s) / float(e - s)
            w = nat + (P["timing"][j] - nat) * P["blend"] if j > 0 else 0.0
            phases.append(((s - start) + w * (e - s)) / n)
    # Stride (travel per loop): median ground speed of the planted feet relative to the hips in the
    # unexaggerated mocap (heel strike / toe off are outliers, mid stance is the ground speed),
    # times the stride exaggeration (feet travel that much farther per step).
    speeds = []
    for side in LEGS:
        z = [min(c[side]["foot"].z, c[side]["toe"].z) for c in cap]
        lo, hi = min(z), max(z)
        for i in range(n):
            j = (i + 1) % n
            if z[i] - lo < 0.12 * (hi - lo) and z[j] - lo < 0.12 * (hi - lo):
                dv = (cap[j][side]["foot"] - cap[j]["hips"]) - (cap[i][side]["foot"] - cap[i]["hips"])
                speeds.append(-(dv.x * go[0] + dv.y * go[1]))
    speeds.sort()
    stride = speeds[len(speeds) // 2] * n * P["stride"] if speeds else 1.0
    strides = [stride, stride]
    print("KEYPOSE %s phases %s stride %.3f units/loop (L %.3f R %.3f)" % (
        name, [round(p, 3) for p in phases], stride, strides[0], strides[1]))
    os.makedirs(out_dir, exist_ok=True)
    with open(out_dir + name + ".json", "w") as f:
        json.dump({"clip": name, "kind": kind, "direction": direction, "labels": labels,
                   "phases": [round(p, 4) for p in phases], "stride": round(stride, 3),
                   "loop_s": round(n / 30.0, 3)}, f, indent=1)
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    act.use_fake_user = True
    return act


def pick_frames(arm, dense_act, name, frames, labels, times, out_dir="art/mocap/keys/"):
    """Action `name` with the given dense frames (1-based, 30 fps) of `dense_act` as its keys (one
    frame per key, unchanged mocap pose) and a sidecar with their labels and phases `times`."""
    act = bpy.data.actions.new(name)
    snaps = []
    arm.animation_data.action = dense_act
    for f in frames:
        bpy.context.scene.frame_set(int(f))
        snaps.append(({b.name: b.rotation_quaternion.copy() for b in arm.pose.bones}, arm.pose.bones["Hips"].location.copy()))
    arm.animation_data.action = act
    for i, (q, loc) in enumerate(snaps):
        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = q[pb.name]
            pb.keyframe_insert("rotation_quaternion", frame=i + 1)
            if pb.name == "Hips":
                pb.location = loc
                pb.keyframe_insert("location", frame=i + 1)
    os.makedirs(out_dir, exist_ok=True)
    with open(out_dir + name + ".json", "w") as f:
        json.dump({"clip": name, "kind": "dive", "labels": labels, "phases": times, "frames": list(frames)}, f, indent=1)
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    act.use_fake_user = True
    print("KEYPOSE %s frames %s" % (name, list(frames)))
    return act
