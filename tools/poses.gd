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


## `lean` = Vector2(heading, tilt) deg: the body tips toward `heading` (clockwise from forward,
## seen from above, in the body frame) by `tilt` (90 = lying flat), on top of the Euler `rot`.
static func key(t: float, rot: Vector3, limbs: Dictionary, lean := Vector2.ZERO) -> Dictionary:
	return {"t": t, "rot": rot, "limbs": limbs, "lean": lean}


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


## Key times of every dive (fractions of the whole dive: coil, launch, flight, landing, slide,
## prone, get up). Pose-to-pose: each key is one sprite frame held until the next, so the fast
## parts (launch to landing, 0.05 -> 0.38) are few hard cuts and the recovery lingers.
const DIVE_T := [0.0, 0.05, 0.12, 0.22, 0.32, 0.38, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]


## Hand-keyed dive toward `heading` degrees RELATIVE TO THE BODY (0 forward, 90 right, 180 back,
## 270 left; any angle works). The body keeps facing forward (the look direction) and tips toward
## the heading like a stiff board pivoting on the hips: belly-down superman for forward, lying on
## the back for back, on the side for left / right, in between for the diagonals. The weapon hold
## (IK, aim frame) keeps the gun level and pointing ahead the whole time, so it can be fired
## during the flight. Exaggerated on purpose (snappy superhero): a deep coil, a hard kick off,
## one knee driven up in the air, a flat skid, then a quick get up.
static func dive(heading: float) -> Array:
	var h := hold()
	# Which leg drives: the one on the dive side (right for right-ish headings).
	var s := -1.0 if sin(deg_to_rad(heading)) > 0.1 else 1.0 # +1: left leg leads
	var m := Vector3(-1, 1, 1)
	var leg := func(lead_thigh: Vector3, lead_shin: Vector3, trail_thigh: Vector3, trail_shin: Vector3) -> Dictionary:
		var lt: Vector3 = lead_thigh
		var ls: Vector3 = lead_shin
		var tt: Vector3 = trail_thigh * m
		var ts: Vector3 = trail_shin * m
		if s > 0.0:
			return _join(h, {"LThigh": lt, "LShin": ls, "RThigh": tt, "RShin": ts})
		return _join(h, {"LThigh": trail_thigh, "LShin": trail_shin, "RThigh": lt * m, "RShin": ls * m})
	var back := heading + 180.0
	var straight: Dictionary = leg.call(Vector3(0.06, -1, -0.1), Vector3(0.05, -1, -0.1), Vector3(0.06, -1, -0.1), Vector3(0.05, -1, -0.1))
	var coil: Dictionary = leg.call(Vector3(0.1, -0.72, 0.69), Vector3(0.02, -0.78, -0.62), Vector3(0.1, -0.72, 0.69), Vector3(0.02, -0.78, -0.62))
	var kick: Dictionary = leg.call(Vector3(0.05, -0.75, 0.6), Vector3(0.0, -0.85, -0.5), Vector3(0.05, -1, -0.3), Vector3(0.0, -1, -0.15))
	var tuck: Dictionary = leg.call(Vector3(0.1, -0.55, 0.8), Vector3(0.0, -0.4, -0.9), Vector3(0.12, -0.9, -0.4), Vector3(0.0, -0.55, -0.85))
	var prop: Dictionary = leg.call(Vector3(0.05, -0.5, 0.85), Vector3(0.0, -0.95, -0.2), Vector3(0.1, -1, -0.2), Vector3(0.0, -1, -0.1))
	var kneel: Dictionary = leg.call(Vector3(0.1, -0.35, 0.9), Vector3(0.0, -1.0, -0.15), Vector3(0.12, -0.8, 0.5), Vector3(0.0, -0.4, -0.9))
	var rise: Dictionary = leg.call(Vector3(0.1, -0.85, 0.5), Vector3(0.02, -0.85, -0.5), Vector3(0.1, -0.9, 0.4), Vector3(0.02, -0.85, -0.5))
	var T := DIVE_T
	return [
		key(T[0], Vector3.ZERO, coil, Vector2(back, 12)),
		key(T[1], Vector3.ZERO, kick, Vector2(heading, 32)),
		key(T[2], Vector3.ZERO, kick, Vector2(heading, 66)),
		key(T[3], Vector3.ZERO, tuck, Vector2(heading, 84)),
		key(T[4], Vector3.ZERO, straight, Vector2(heading, 88)),
		key(T[5], Vector3.ZERO, straight, Vector2(heading, 90)),
		key(T[6], Vector3.ZERO, straight, Vector2(heading, 90)),
		key(T[7], Vector3.ZERO, straight, Vector2(heading, 90)),
		key(T[8], Vector3.ZERO, prop, Vector2(heading, 62)),
		key(T[9], Vector3.ZERO, kneel, Vector2(heading, 34)),
		key(T[10], Vector3.ZERO, rise, Vector2(heading, 12)),
		key(T[11], Vector3.ZERO, h, Vector2(heading, 0)),
	]
