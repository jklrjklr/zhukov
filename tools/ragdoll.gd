class_name BakeRagdoll
extends RefCounted
## Physics ragdoll for death bakes (tools/bake_sprites.gd): capsules on the main bones,
## cone joints with limits, no self-collision (floor only), gravity scaled to the model's units.
## The body starts from the current pose, gets a hit impulse and falls limp.

## bone -> [child bone the capsule reaches to (or "" + length), radius, mass, swing deg, twist deg]
const PARTS := {
	"Hips": ["Spine", 0.3, 10.0, 0.0, 0.0],
	"Spine": ["Chest", 0.26, 6.0, 25.0, 15.0],
	"Chest": ["UpperChest", 0.28, 6.0, 20.0, 15.0],
	"UpperChest": ["Neck", 0.3, 7.0, 20.0, 15.0],
	"Head": ["Head_end", 0.3, 4.0, 40.0, 40.0],
	"LeftArm": ["LeftForeArm", 0.12, 2.0, 80.0, 40.0],
	"LeftForeArm": ["LeftHand", 0.1, 1.5, 70.0, 20.0],
	"RightArm": ["RightForeArm", 0.12, 2.0, 80.0, 40.0],
	"RightForeArm": ["RightHand", 0.1, 1.5, 70.0, 20.0],
	"LeftUpLeg": ["LeftLeg", 0.16, 6.0, 60.0, 20.0],
	"LeftLeg": ["LeftFoot", 0.13, 4.0, 70.0, 10.0],
	"LeftFoot": ["LeftToes", 0.1, 1.0, 30.0, 10.0],
	"RightUpLeg": ["RightLeg", 0.16, 6.0, 60.0, 20.0],
	"RightLeg": ["RightFoot", 0.13, 4.0, 70.0, 10.0],
	"RightFoot": ["RightToes", 0.1, 1.0, 30.0, 10.0],
}
## The model is ~4 units for a ~1.8 m person: scale gravity so falls take real time.
const GRAVITY := 9.8 * 2.2

var sim: PhysicalBoneSimulator3D
var bodies := {}
var floor_body: StaticBody3D


## Builds the ragdoll on `skel` (inside `world_root`, whose World3D gets a floor at y = floor_y).
func build(skel: Skeleton3D, world_root: Node3D, floor_y: float) -> void:
	sim = PhysicalBoneSimulator3D.new()
	skel.add_child(sim)
	for bone in PARTS:
		var spec: Array = PARTS[bone]
		var bi := skel.find_bone(bone)
		var ci := skel.find_bone(spec[0])
		if bi < 0 or ci < 0:
			continue
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + bone
		pb.bone_name = bone
		pb.mass = spec[2]
		pb.friction = 0.9
		pb.linear_damp = 0.15
		pb.angular_damp = 1.5
		pb.collision_layer = 2
		pb.collision_mask = 1
		if spec[3] > 0.0:
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			pb.set("joint_constraints/swing_span", spec[3])
			pb.set("joint_constraints/twist_span", spec[4])
			pb.set("joint_constraints/softness", 0.8)
			pb.set("joint_constraints/relaxation", 1.0)
		# Capsule from the bone to its child, in the bone's own frame.
		var rest := skel.get_bone_global_pose(bi)
		var d := rest.affine_inverse() * skel.get_bone_global_pose(ci).origin
		var r: float = spec[1]
		var cap := CapsuleShape3D.new()
		cap.radius = r
		cap.height = maxf(d.length() + r, r * 2.0 + 0.01)
		var cs := CollisionShape3D.new()
		cs.shape = cap
		cs.transform = Transform3D(Basis(Quaternion(Vector3.UP, d.normalized())), d * 0.5)
		pb.add_child(cs)
		sim.add_child(pb)
		bodies[bone] = pb
	floor_body = StaticBody3D.new()
	floor_body.collision_layer = 1
	var fs := CollisionShape3D.new()
	fs.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(fs)
	floor_body.position.y = floor_y
	world_root.add_child(floor_body)
	PhysicsServer3D.area_set_param(world_root.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, GRAVITY)


## Starts the fall from the current pose: a hit `push` (world units/s) at the chest, a bit
## less at the head and hips, plus a spin; legs stay put so the body topples.
func start(push: Vector3, spin: Vector3) -> void:
	sim.physical_bones_start_simulation()
	for bone in bodies:
		var pb: PhysicalBone3D = bodies[bone]
		var k := 1.0
		if bone in ["Chest", "UpperChest", "Head", "LeftArm", "RightArm"]:
			k = 1.0
		elif bone in ["Spine", "Hips", "LeftForeArm", "RightForeArm"]:
			k = 0.6
		else:
			k = 0.1
		pb.linear_velocity = push * k
		pb.angular_velocity = spin * k


func stop() -> void:
	if sim:
		sim.physical_bones_stop_simulation()
		sim.queue_free()
	if floor_body:
		floor_body.queue_free()
