class_name Poses
extends RefCounted
## Keyed procedural poses for clips the 3D pack doesn't have (dive, deaths), used by
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


## HD2-style dive: crouch and push off with the gun held forward, flat flight with one knee
## kicked up, chest-first landing with elbows out, short slide, then a separate get-up
## (push up on the hands, one knee under the body, kneel, stand), not the take-off reversed.
static func dive() -> Array:
	var gun_arm := Vector3(0.25, -0.2, 1.0)
	var gun_fore := Vector3(-0.15, 0.1, 1.0)
	return [
		key(0.0, Vector3.ZERO, {}),
		key(0.08, Vector3(20, 0, 0), sym(gun_arm, gun_fore, Vector3(0.15, -0.7, 0.6), Vector3(0.1, -0.9, -0.45))),
		key(0.2, Vector3(62, 0, 0), sym(Vector3(0.25, 0.7, 0.6), Vector3(-0.12, 0.85, 0.45), Vector3(0.12, -1, -0.1), Vector3(0.1, -0.95, -0.2),
			{"RThigh": Vector3(-0.1, -0.8, 0.5), "RShin": Vector3(-0.1, -0.9, -0.4)})),
		key(0.34, Vector3(84, 0, 0), sym(Vector3(0.22, 1.0, 0.15), Vector3(-0.12, 1.0, 0.05), Vector3(0.15, -1, -0.05), Vector3(0.1, -0.55, -0.85),
			{"RThigh": Vector3(-0.08, -1, 0.05), "RShin": Vector3(-0.08, -1, -0.15)})),
		key(0.46, Vector3(90, 0, 0), sym(Vector3(0.24, 1.0, 0.15), Vector3(-0.12, 1.0, 0.1), Vector3(0.15, -1, -0.05), Vector3(0.1, -0.7, -0.7),
			{"RShin": Vector3(-0.1, -0.85, -0.5)})),
		key(0.55, Vector3(96, 0, 0), sym(Vector3(0.6, 0.6, 0.5), Vector3(-0.15, 0.85, 0.5), Vector3(0.18, -1, 0.0), Vector3(0.12, -0.95, -0.3))),
		key(0.66, Vector3(91, 0, 0), sym(Vector3(0.55, 0.65, 0.5), Vector3(-0.1, 0.9, 0.4), Vector3(0.2, -1, 0.05), Vector3(0.15, -1, 0.0))),
		key(0.76, Vector3(72, 0, 0), sym(Vector3(0.45, 0.1, 0.9), Vector3(0.05, -0.1, 1.0), Vector3(-0.15, -1, -0.05), Vector3(-0.1, -1, 0.0),
			{"LThigh": Vector3(0.18, -0.35, 0.9), "LShin": Vector3(0.05, -1, -0.15)})),
		key(0.87, Vector3(28, 0, 0), sym(gun_arm, gun_fore, Vector3(-0.15, -0.85, -0.45), Vector3(-0.05, -0.3, -1),
			{"LThigh": Vector3(0.15, -0.15, 1.0), "LShin": Vector3(0.05, -1, -0.1)})),
		key(1.0, Vector3.ZERO, {}),
	]


## Death fall around the feet. kind: "back", "fwd", "left", "right", "crumple"; seed varies
## the limb splay so variants of one kind differ. Timeline: hit flinch, accelerating fall,
## impact with limbs flung past their rest, settle limp.
static func death(kind: String, seed_: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var j := func(v: Vector3, amt := 0.5) -> Vector3:
		return (v + Vector3(rng.randf_range(-amt, amt), rng.randf_range(-amt, amt), rng.randf_range(-amt, amt))).normalized()
	var rot := Vector3.ZERO
	var flinch := Vector3.ZERO
	var limbs := {}
	var flail := {}
	match kind:
		"back": # thrown onto the back, arms flung out above the head, legs apart
			rot = Vector3(-90, rng.randf_range(-15, 15), rng.randf_range(-8, 8))
			flinch = Vector3(-12, 0, 0)
			limbs = {"LArm": j.call(Vector3(0.9, 0.5, -0.1)), "LFore": j.call(Vector3(0.6, 0.8, 0.1)),
				"RArm": j.call(Vector3(-0.8, 0.2, -0.2)), "RFore": j.call(Vector3(-0.9, -0.3, 0.2)),
				"LThigh": j.call(Vector3(0.3, -1, 0.1), 0.2), "LShin": j.call(Vector3(0.2, -1, -0.3), 0.3),
				"RThigh": j.call(Vector3(-0.2, -1, 0.3), 0.2), "RShin": j.call(Vector3(-0.3, -1, -0.1), 0.3),
				"Head": j.call(Vector3(0.4, 1, 0.2), 0.3)}
			flail = Poses.sym(Vector3(0.5, 0.6, 0.6), Vector3(0.2, 0.9, 0.4), Vector3(0.1, -1, 0.2), Vector3(0.1, -1, -0.2))
		"fwd": # pitched onto the face, one arm under the body, the other out
			rot = Vector3(90, rng.randf_range(-15, 15), rng.randf_range(-8, 8))
			flinch = Vector3(14, 0, 0)
			limbs = {"LArm": j.call(Vector3(0.2, -0.6, 0.8)), "LFore": j.call(Vector3(-0.6, -0.2, 0.8)),
				"RArm": j.call(Vector3(-0.9, 0.4, 0.2)), "RFore": j.call(Vector3(-0.5, 0.9, -0.1)),
				"LThigh": j.call(Vector3(0.2, -1, 0.0), 0.2), "LShin": j.call(Vector3(0.15, -0.8, -0.6), 0.3),
				"RThigh": j.call(Vector3(-0.3, -1, 0.1), 0.2), "RShin": j.call(Vector3(-0.2, -1, -0.1), 0.2),
				"Head": j.call(Vector3(-0.6, 1, 0.3), 0.2)}
			flail = Poses.sym(Vector3(0.6, 0.3, -0.6), Vector3(0.5, 0.6, -0.4), Vector3(0.1, -1, -0.2), Vector3(0.1, -1, -0.3))
		"left", "right": # spun onto a side, knees drawn up, arms tangled in front
			var s := 1.0 if kind == "left" else -1.0
			rot = Vector3(rng.randf_range(-15, 15), rng.randf_range(-20, 20), 90 * s)
			flinch = Vector3(0, 0, 14 * s)
			var m := Vector3(s, 1, 1)
			limbs = {"LArm": j.call(Vector3(0.3, 0.8, 0.5) * m), "LFore": j.call(Vector3(-0.2, 0.6, 0.8) * m),
				"RArm": j.call(Vector3(-0.2, -0.4, 0.9) * m), "RFore": j.call(Vector3(0.4, -0.3, 0.85) * m),
				"LThigh": j.call(Vector3(0.1, -0.6, 0.75) * m, 0.2), "LShin": j.call(Vector3(0.05, -1, -0.4) * m, 0.2),
				"RThigh": j.call(Vector3(-0.1, -0.9, 0.35) * m, 0.2), "RShin": j.call(Vector3(-0.1, -0.9, -0.5) * m, 0.2),
				"Head": j.call(Vector3(-0.4 * s, 1, 0.3), 0.2)}
			flail = Poses.sym(Vector3(0.8, 0.2, 0.3), Vector3(0.6, 0.6, 0.3), Vector3(0.1, -1, 0.1), Vector3(0.1, -1, -0.2))
		_: # crumple: knees give, folds forward and twists down
			rot = Vector3(80, rng.randf_range(25, 45) * (1 if rng.randf() < 0.5 else -1), rng.randf_range(-25, 25))
			flinch = Vector3(8, 0, 0)
			limbs = {"LArm": j.call(Vector3(0.4, -0.7, 0.6)), "LFore": j.call(Vector3(-0.3, -0.5, 0.8)),
				"RArm": j.call(Vector3(-0.6, 0.2, 0.7)), "RFore": j.call(Vector3(-0.2, 0.8, 0.5)),
				"LThigh": j.call(Vector3(0.2, -0.3, 0.95), 0.2), "LShin": j.call(Vector3(0.1, -1, -0.3), 0.2),
				"RThigh": j.call(Vector3(-0.2, -0.6, 0.75), 0.2), "RShin": j.call(Vector3(-0.1, -0.7, -0.7), 0.2),
				"Head": j.call(Vector3(0.3, 0.7, 0.8), 0.2), "Spine": Vector3(0, 0.7, 0.7)}
			flail = Poses.sym(Vector3(0.3, -0.7, 0.6), Vector3(0.1, -0.5, 0.85), Vector3(0.1, -0.7, 0.6), Vector3(0.05, -1, -0.4))
	# Ragdoll looseness: random bends at elbows and knees (relative to the upper limb), a
	# twisted spine and a lolling head, so no two bodies lie the same.
	for side in ["L", "R"]:
		var arm: Vector3 = limbs[side + "Arm"]
		limbs[side + "Fore"] = (arm + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-0.6, 1)) * rng.randf_range(0.4, 1.1)).normalized()
		var thigh: Vector3 = limbs[side + "Thigh"]
		limbs[side + "Thigh"] = (thigh + Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.2, 0.6))).normalized()
		limbs[side + "Shin"] = (limbs[side + "Thigh"] + Vector3(rng.randf_range(-0.3, 0.3), 0, -rng.randf_range(0.0, 1.2))).normalized()
	limbs["Spine"] = (limbs.get("Spine", Vector3.UP) + Vector3(rng.randf_range(-0.45, 0.45), 0, rng.randf_range(-0.3, 0.3))).normalized()
	limbs["Head"] = (limbs["Head"] + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.4, 0.4))).normalized()
	rot.y += rng.randf_range(-25, 25)
	# Impact: limbs overshoot (flung further along their direction), then settle.
	var overshoot := {}
	for k in limbs:
		var v: Vector3 = limbs[k]
		overshoot[k] = (v + Vector3(v.x, v.y * 0.3, v.z) * 0.35).normalized()
	return [
		key(0.0, Vector3.ZERO, {}),
		key(0.12, flinch, flail),
		key(0.45, rot * 0.45, _mix(flail, limbs, 0.4)),
		key(0.72, rot * 1.03, overshoot),
		key(0.86, rot * 0.99, limbs),
		key(1.0, rot, limbs),
	]


## Per-limb slerp between two limb sets (limbs only in one set are taken as-is).
static func _mix(a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = (a[k] as Vector3).normalized().slerp((b[k] as Vector3).normalized(), f) if a.has(k) else b[k]
	return out
