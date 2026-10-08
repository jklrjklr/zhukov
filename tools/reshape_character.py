"""Reshapes Kenney's chibi characterMedium into ~5-heads-tall stylised human proportions:
longer legs and torso, smaller head, narrow waist with broader shoulders, slimmer limbs,
then one level of subdivision so the boxy shapes become natural curves. Same skeleton,
bone names and UVs, so the Kenney skins and animation clips still apply.

  blender -b --python tools/reshape_character.py -- <in.fbx> <out.glb>

The animation clips (idle / run / jump FBX, same rig) are imported as actions, assigned to
the reshaped armature and exported in the same glb (Godot needs bone rest frames and clips
from one importer, or the rotations don't line up).

Bone scales are (thickness x, length y, thickness z) in each bone's own axes.
"""
import sys
import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = argv[0] if len(argv) > 0 else "art/3d/survivors/Model/characterMedium.fbx"
OUT = argv[1] if len(argv) > 1 else "art/3d/survivors/Model/characterHuman.glb"
BODY = argv[2] if len(argv) > 2 else "male"

## Torso silhouette (after the bone pass), as width / depth factors at landmark heights:
## hips, waist, chest, shoulders. Blended by each vertex's torso weight so the seams to the
## arms / legs don't tear. Female: wider hips, narrower waist, chest pushed forward (front only).
BODIES = {
    "male": {"width": [1.0, 0.88, 1.06, 1.1], "depth": [0.98, 0.9, 1.05, 1.0], "bust": 0.0},
    "female": {"width": [1.12, 0.82, 0.98, 0.98], "depth": [1.0, 0.88, 1.0, 0.96], "bust": 0.2},
}

## Proportion reference: stylised anime / VRoid body, 5 heads tall: legs about half the height,
## short torso, narrow shoulders, thin neck and limbs, small feet.
SCALES = {
    "Head": (0.51, 0.645, 0.58),  # narrower and shallower than Kenney's wide box head; 5 heads tall
    "Neck": (0.78, 0.9, 0.78),
    "UpperChest": (1.1, 1.0, 1.0),
    "Chest": (1.02, 1.0, 0.98),
    "Spine": (0.88, 1.0, 0.9),  # the waist
    "Hips": (1.0, 1.0, 0.95),
    "LeftShoulder": (1.0, 0.9, 1.0), "RightShoulder": (1.0, 0.9, 1.0),
    "LeftArm": (0.82, 1.25, 0.82), "RightArm": (0.82, 1.25, 0.82),
    "LeftForeArm": (0.78, 1.2, 0.78), "RightForeArm": (0.78, 1.2, 0.78),
    "LeftHand": (0.85, 0.85, 0.85), "RightHand": (0.85, 0.85, 0.85),
    "LeftUpLeg": (0.95, 1.55, 0.95), "RightUpLeg": (0.95, 1.55, 0.95),
    "LeftLeg": (0.82, 1.5, 0.82), "RightLeg": (0.82, 1.5, 0.82),
    "LeftFoot": (0.82, 0.8, 0.82), "RightFoot": (0.82, 0.8, 0.82),
}
SUBDIV = 2
ANIM_DIR = "art/3d/survivors/Animations/"
CLIPS = {}  # Kenney FBX clips (replaced by mocap)
MOCAP_DIR = "art/mocap/cmu/"
# Mocap clips: name -> (take, start s, end s, loop, loop length range s, direction[, mirror[,
# in_place[, align]]])
MOCAP = {
    "Idle": ("82_08", 0.2, 3.0, True, (1.2, 2.6), None),
    "Walk": ("16_15", 0.8, None, True, (0.8, 1.4), None),
    "Run": ("16_35", 0.2, None, True, (0.5, 0.9), None),
    "WalkBack": ("41_02", 0.0, None, True, (0.8, 1.4), "back"),
    "WalkLeft": ("41_02", 0.0, None, True, (0.6, 1.4), "left", True),  # mirrored walk-right
    "WalkRight": ("41_02", 0.0, None, True, (0.6, 1.4), "right"),
    "ZombieWalk": ("104_41", 0.5, None, True, (0.9, 1.8), None),
}
# Player source takes (dense, in place); tools/keypose.py turns them into key-pose clips.
# 100STYLE "Proud" (CC BY 4.0, art/mocap/100style/): confident, chest-out locomotion.
S100 = "art/mocap/100style/"
KEYED = {"PWalk": ("walk", "fwd"), "PRun": ("run", "fwd"), "PWalkBack": ("back", "back"),
         "PWalkRight": ("strafe", "right"), "PWalkLeft": ("strafe", "left")}
MOCAP_P = {
    "PWalk": (S100 + "Proud_FW.bvh", 0.0, None, True, (0.8, 1.5), "fwd"),
    "PRun": (S100 + "Proud_FR.bvh", 0.0, None, True, (0.5, 1.0), "fwd"),
    "PWalkBack": (S100 + "Proud_BW.bvh", 0.0, None, True, (0.8, 1.6), "back"),
    "PWalkRight": (S100 + "Proud_SW.bvh", 0.0, None, True, (0.6, 1.5), "right"),
    "PWalkLeft": (S100 + "Proud_SW.bvh", 0.0, None, True, (0.6, 1.5), "left", True),
}
sys.path.append("tools")
import cmu_retarget  # noqa: E402
import keypose  # noqa: E402

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SRC)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.data.objects if o.type == "MESH")

# Pose: scale bones without passing the scale on to children (children only follow the
# moved joints), so each bone gets exactly its own factor.
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
for eb in arm.data.edit_bones:
    eb.inherit_scale = "NONE"
bpy.ops.object.mode_set(mode="POSE")
for name, s in SCALES.items():
    pb = arm.pose.bones.get(name)
    if pb:
        pb.scale = s
bpy.context.view_layer.update()

# Bake the posed shape into the mesh, make the pose the new rest pose, re-bind.
bpy.ops.object.mode_set(mode="OBJECT")
bpy.context.view_layer.objects.active = mesh
mod = next(m for m in mesh.modifiers if m.type == "ARMATURE")
mod_name = mod.name
bpy.ops.object.modifier_apply(modifier=mod_name)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode="EDIT")
for eb in arm.data.edit_bones:
    eb.inherit_scale = "FULL"
bpy.ops.object.mode_set(mode="OBJECT")

# Torso sculpt: piecewise-linear width / depth profile over height, around the body axis.
def bone_z(name, at=0.0):
    b = arm.data.bones[name]
    return (arm.matrix_world @ b.head_local.lerp(b.tail_local, at)).z

body = BODIES[BODY]
zs_ = [bone_z("Hips", 0.3), bone_z("Spine", 0.6), bone_z("UpperChest", 0.2), bone_z("Neck", 0.0)]
TORSO = {"Hips", "Spine", "Chest", "UpperChest", "Neck"}
names = {g.index: g.name for g in mesh.vertex_groups}
center_y = (arm.matrix_world @ arm.data.bones["Spine"].head_local).y


def profile(vals, z):
    if z <= zs_[0]:
        return vals[0]
    for i in range(1, len(zs_)):
        if z <= zs_[i]:
            f = (z - zs_[i - 1]) / (zs_[i] - zs_[i - 1])
            f = f * f * (3 - 2 * f)
            return vals[i - 1] + (vals[i] - vals[i - 1]) * f
    return vals[-1]


mw = mesh.matrix_world
inv = mw.inverted()
for v in mesh.data.vertices:
    tw = sum(g.weight for g in v.groups if names.get(g.group) in TORSO)
    if tw <= 0.0:
        continue
    tw = min(tw, 1.0)
    co = mw @ v.co
    w = 1.0 + (profile(body["width"], co.z) - 1.0) * tw
    d = 1.0 + (profile(body["depth"], co.z) - 1.0) * tw
    dy = co.y - center_y
    # Bust: front of the chest only (-Y is the front in Blender's import of this rig).
    if body["bust"] > 0.0 and dy < 0.0:
        t = max(0.0, 1.0 - abs(co.z - bone_z("UpperChest", 0.0)) / 0.25)
        d += body["bust"] * t * tw
    co.x *= w
    co.y = center_y + dy * d
    v.co = inv @ co

# Rounder, more natural shapes (vertex groups are interpolated by the subdivision).
bpy.context.view_layer.objects.active = mesh
if SUBDIV > 0:
    sub = mesh.modifiers.new("Subdiv", "SUBSURF")
    sub.levels = SUBDIV
    sub.render_levels = SUBDIV
    bpy.ops.object.modifier_apply(modifier=sub.name)
bpy.ops.object.shade_smooth()
m = mesh.modifiers.new("Armature", "ARMATURE")
m.object = arm

# Outfit: formal suit painted per face into a colour attribute (alpha = how much the outfit
# replaces the skin texture; 0 on head / neck / hands so face and hair stay). The bake shader
# mixes it over the texture (zombie skins switch it off).
SUIT = (0.06, 0.06, 0.07, 1.0)
LAPEL = (0.19, 0.19, 0.22, 1.0)
TROUSERS = (0.05, 0.05, 0.06, 1.0)
SHIRT = (0.92, 0.92, 0.9, 1.0)
TIE = (0.03, 0.03, 0.035, 1.0)
SHOES = (0.025, 0.025, 0.03, 1.0)
KEEP = (1.0, 1.0, 1.0, 0.0)
JACKET = {"Hips", "Spine", "Chest", "UpperChest", "LeftShoulder", "RightShoulder",
          "LeftArm", "RightArm", "LeftForeArm", "RightForeArm"}
LEGS = {"LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg"}
FEET = {"LeftFoot", "RightFoot", "LeftToes", "RightToes"}
neck_z = bone_z("Neck", 0.0) + 0.05
# Faceless: head faces in front, below the hairline, get the plain skin colour (alpha 0.5 =
# "skin" marker; the bake shader samples the skin tone from the texture at the neck, so every
# skin keeps its own tone). Hair, ears and the back of the head keep the texture.
FACE = (1.0, 1.0, 1.0, 0.5)
head_zs = [(mw @ v.co).z for v in mesh.data.vertices
           if any(names.get(g.group) == "Head" and g.weight > 0.5 for g in v.groups)]
hairline = min(head_zs) + 0.66 * (max(head_zs) - min(head_zs))
v_bottom = bone_z("Chest", 0.3)
hands = {s_: arm.matrix_world @ arm.data.bones[s_ + "Hand"].head_local for s_ in ("Left", "Right")}
names = {g.index: g.name for g in mesh.vertex_groups}


def outfit(poly):
    weights = {}
    for vi in poly.vertices:
        for g in mesh.data.vertices[vi].groups:
            n = names.get(g.group)
            if n:
                weights[n] = weights.get(n, 0.0) + g.weight
    if not weights:
        return KEEP
    top = max(weights, key=weights.get)
    c = mw @ poly.center
    nrm = (mw.to_3x3() @ poly.normal).normalized()
    if top == "Head":
        return FACE if nrm.y < -0.15 and c.z < hairline else KEEP
    if top in FEET:
        return SHOES
    if top in LEGS:
        return SUIT
    if top in JACKET or top == "Neck":
        # Shirt collar: a white ring around the neck (what reads from straight above).
        neck = arm.matrix_world @ arm.data.bones["Neck"].head_local
        if c.z > neck_z - 0.1 and (c.xy - neck.xy).length < 0.3:
            return SHIRT
        if top == "Neck":
            return KEEP
        if "ForeArm" in top:
            hand = hands["Left" if top.startswith("Left") else "Right"]
            if (c - hand).length < 0.12:
                return SHIRT  # cuff
        if nrm.y < -0.25 and v_bottom < c.z < neck_z:
            k = (c.z - v_bottom) / (neck_z - v_bottom)
            if abs(c.x) < 0.035 + 0.02 * k:
                return TIE
            if abs(c.x) < 0.05 + 0.2 * k:
                return SHIRT
            if abs(c.x) < 0.1 + 0.24 * k:
                return LAPEL
        return SUIT
    return KEEP


# Crease shading: per-vertex concavity (neighbours rising above the surface = a fold),
# smoothed, darkens the cloth in armpits, elbows, crotch, under the collar.
me = mesh.data
nbrs = [[] for _ in me.vertices]
for e in me.edges:
    a_, b_ = e.vertices
    nbrs[a_].append(b_)
    nbrs[b_].append(a_)
cav = []
for v in me.vertices:
    if not nbrs[v.index]:
        cav.append(0.0)
        continue
    d = sum(v.normal.dot((me.vertices[n].co - v.co).normalized()) for n in nbrs[v.index]) / len(nbrs[v.index])
    cav.append(max(0.0, d))
for _ in range(3):
    cav = [(cav[i] + sum(cav[n] for n in nbrs[i])) / (1 + len(nbrs[i])) for i in range(len(cav))]
CREASE = 2.2

attr = me.color_attributes.new("outfit", "BYTE_COLOR", "CORNER")
for poly in me.polygons:
    col = outfit(poly)
    for li in poly.loop_indices:
        vi = me.loops[li].vertex_index
        shade = max(0.45, 1.0 - cav[vi] * CREASE) if col[3] > 0 else 1.0
        attr.data[li].color = (col[0] * shade, col[1] * shade, col[2] * shade, col[3])
mesh.data.color_attributes.active_color = attr
# Where the skin tone is in the texture: average UV over the neck faces.
uvl = me.uv_layers.active.data
neck_uv = [uvl[li].uv for poly in me.polygons for li in poly.loop_indices
           if outfit(poly) is KEEP and any(names.get(g.group) == "Neck" for g in me.vertices[me.loops[li].vertex_index].groups)]
if neck_uv:
    u = sum(x[0] for x in neck_uv) / len(neck_uv)
    v_ = sum(x[1] for x in neck_uv) / len(neck_uv)
    print("RESHAPE skin uv (gltf, v flipped) %.4f %.4f" % (u, 1.0 - v_))
mesh.data.color_attributes.render_color_index = mesh.data.color_attributes.active_color_index

# Clips: import each animation FBX, take its action, drop its armature / meshes.
keep = {arm.name, mesh.name}
actions = []
for f, clip in CLIPS.items():
    before = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=ANIM_DIR + f + ".fbx")
    new = [a for a in bpy.data.actions if a not in before]
    act = next((a for a in new if a.name.endswith(clip) or clip in a.name), new[-1])
    act.name = clip
    act.use_fake_user = True
    actions.append(act)
    for o in list(bpy.data.objects):
        if o.name not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    for a in new:
        if a is not act:
            bpy.data.actions.remove(a)
for clip, spec in MOCAP.items():
    take, st, en, lp, ll, dr = spec[:6]
    ip = spec[7] if len(spec) > 7 else True
    actions.append(cmu_retarget.retarget(arm, MOCAP_DIR + take + ".bvh", clip, st, en, lp, ip, ll or (0.6, 1.6),
                                         direction=dr, mirror=len(spec) > 6 and spec[6],
                                         align=spec[8] if len(spec) > 8 else "pelvis"))
dense = {}
for clip, spec in MOCAP_P.items():
    take, st, en, lp, ll, dr = spec[:6]
    dense[clip] = cmu_retarget.retarget(arm, take, clip, st, en, lp, True, ll, direction=dr,
                                        mirror=len(spec) > 6 and spec[6])
    kind, kdir = KEYED[clip]
    actions.append(keypose.make(arm, dense[clip], "K" + clip[1:], kind, kdir))
# Dive: CMU 127_23 "Run Dive Over Roll Run" (diving superman, shoulder roll, crouch, stand). The
# dive keys are mocap frames (30 fps, 1-based) picked for strong silhouettes; time = phase of the
# whole dive (air to 0.34, roll to 0.5, get up to 1.0).
DIVE_TAKE = ("127_23", "body@8-15")
DIVE_KEYS = [  # label, mocap frame, phase
    ("coil", 3, 0.0), ("push", 9, 0.05), ("extend", 13, 0.12), ("reach", 16, 0.22), ("impact", 19, 0.32),
    ("flip", 23, 0.38), ("inverted", 26, 0.43), ("roll", 30, 0.48), ("ball", 34, 0.54),
    ("crouch", 40, 0.64), ("rise", 48, 0.76), ("stand", 58, 0.88)]
dd = cmu_retarget.retarget(arm, MOCAP_DIR + DIVE_TAKE[0] + ".bvh", "DDive", 0, None, False, "lock", align=DIVE_TAKE[1])
actions.append(keypose.pick_frames(arm, dd, "KDive", [k[1] for k in DIVE_KEYS], [k[0] for k in DIVE_KEYS], [k[2] for k in DIVE_KEYS]))
import os  # noqa: E402
for take in os.environ.get("MOCAP_DEBUG", "").split(","):
    if take:  # exploration: any CMU take as a dense clip "D<take>" (hips locked), for tools/clip_preview.gd
        actions.append(cmu_retarget.retarget(arm, MOCAP_DIR + take + ".bvh", "D" + take, 0, None, False, "lock",
                                             align=os.environ.get("ALIGN", "pelvis")))
arm.animation_data_create()
for act in actions:
    tr = arm.animation_data.nla_tracks.new()
    tr.name = act.name
    tr.strips.new(act.name, int(act.frame_range[0]), act)
    print("RESHAPE clip", act.name, act.frame_range[:])
arm.animation_data.action = None

zs = [(mesh.matrix_world @ v.co).z for v in mesh.data.vertices]
head = [(mesh.matrix_world @ v.co).z for v in mesh.data.vertices
        if any(mesh.vertex_groups[g.group].name == "Head" and g.weight > 0.5 for g in v.groups)]
h = max(zs) - min(zs)
hh = max(head) - min(head)
crotch = bone_z("LeftUpLeg") - min(zs)
print("RESHAPE height %.2f head %.2f -> %.2f heads, legs %.0f%% of height, verts %d"
      % (h, hh, h / hh, 100 * crotch / h, len(mesh.data.vertices)))

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=True,
                          export_animation_mode="NLA_TRACKS", export_skins=True, export_yup=True,
                          export_colors=True)
print("RESHAPE wrote", OUT)
