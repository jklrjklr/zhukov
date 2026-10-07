class_name Poses
extends RefCounted
## Keyed procedural poses for clips the 3D pack doesn't have (dive, weapon hold), used by
## tools/bake_sprites.gd. A clip is an array of keys:
##   {"t": 0..1, "rot": Vector3(pitch, yaw, roll) deg of the whole body around the pivot,
##    "limbs": {limb: direction}}
## Directions are in the upright body frame: +Y up, +Z forward (chest side), +X the
## character's left. A limb missing from a key keeps the idle pose there. Pitch +90 = face
## down (lying on the chest), -90 = on the back; roll +90 = lying on the left side.

## limb -> [bone, child bone] (the bone is rotated to point at the child along the direction).
const LIMBS := {
	"Spine": ["Spine", "Chest"], "Head": ["Head", "Head_end"],
	"LArm": ["LeftArm", "LeftForeArm"], "LFore": ["LeftForeArm", "LeftHand"],
	"RArm": ["RightArm", "RightForeArm"], "RFore": ["RightForeArm", "RightHand"],
	"LThigh": ["LeftUpLeg", "LeftLeg"], "LShin": ["LeftLeg", "LeftFoot"],
	"RThigh": ["RightUpLeg", "RightLeg"], "RShin": ["RightLeg", "RightFoot"],
}
## Parents before children.
const ORDER := ["Spine", "Head", "LArm", "LFore", "RArm", "RFore", "LThigh", "LShin", "RThigh", "RShin"]


## Same directions on both sides (right = left mirrored), then per-limb overrides.
static func sym(arm: Vector3, fore: Vector3, thigh: Vector3, shin: Vector3, over := {}) -> Dictionary:
	var m := Vector3(-1, 1, 1)
	var d := {"LArm": arm, "LFore": fore, "LThigh": thigh, "LShin": shin,
		"RArm": arm * m, "RFore": fore * m, "RThigh": thigh * m, "RShin": shin * m}
	d.merge(over, true)
	return d


static func key(t: float, rot: Vector3, limbs: Dictionary) -> Dictionary:
	return {"t": t, "rot": rot, "limbs": limbs}


## Shouldered rifle hold, solved with 2-bone IK by the bake tool (so it fits any arm length):
## the stock sits in the right shoulder pocket, the gun runs straight ahead beside the right
## cheek, right hand on the grip just ahead of the pocket (elbow out to the side), left arm
## reaching forward to the foregrip (elbow down). Offsets are in the AIM frame (+X the
## character's left, +Y up, +Z ahead), which is the body frame counter-rotated by the body's
## forward pitch, so the gun stays level (points where he goes) even when the body is flat.
## POCKET is from the right upper-arm joint; GRIP / FOREGRIP from the pocket.
const POCKET := Vector3(0.16, 0.05, 0.1)
const GRIP := Vector3(0.0, -0.16, 0.42)
const FOREGRIP := Vector3(0.02, -0.1, 0.95)
const POLE_R := Vector3(-1.0, -0.5, -0.2)
const POLE_L := Vector3(0.3, -1.0, 0.0)


## Arms on the weapon (IK) at body pitch `pitch` (deg); `over` overrides limbs (e.g. a hand
## leaving the gun to push off the ground).
static func hold(pitch := 0.0, over := {}) -> Dictionary:
	var d := {"_hold": pitch}
	d.merge(over, true)
	return d


## Legs-only limb set merged into a hold.
static func legs(thigh: Vector3, shin: Vector3, over := {}) -> Dictionary:
	var m := Vector3(-1, 1, 1)
	var d := {"LThigh": thigh, "LShin": shin, "RThigh": thigh * m, "RShin": shin * m}
	d.merge(over, true)
	return d


static func _join(a: Dictionary, b: Dictionary) -> Dictionary:
	var d := a.duplicate()
	d.merge(b, true)
	return d


