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

## Proportion reference: stylised anime / VRoid body, ~6 heads: legs about half the height,
## short torso, narrow shoulders, thin neck and limbs, small feet.
SCALES = {
    "Head": (0.7, 0.7, 0.7),
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
CLIPS = {"idle": "Idle", "run": "Run", "jump": "Jump"}

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
                          export_animation_mode="NLA_TRACKS", export_skins=True, export_yup=True)
print("RESHAPE wrote", OUT)
