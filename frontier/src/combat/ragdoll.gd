class_name Ragdoll
extends Node
## Death ragdoll for a FrontierCharacter: the death clip starts, then (after `delay`) a PhysicalBoneSimulator3D with
## PhysicalBone3D capsules generated from the Godot-humanoid skeleton blends in, the killing shot's impulse is
## applied at the bone of the hit zone, and once the body has settled (or after SETTLE_MAX seconds) the final pose is
## written back into the skeleton and the physics bodies are removed (a frozen corpse costs nothing).
## LOD: at most MAX_ACTIVE simulate at once (the oldest is frozen early) and only within RANGE of the camera.
## Bones collide with the world only (layer 32, mask 1), never with each other or with actors.
## Use: Ragdoll.begin(character, info) from FrontierCharacter.die(); Ragdoll.cancel(character) on revive.

const MAX_ACTIVE := 4
const RANGE := 70.0
const SETTLE_MAX := 5.0
const LAYER := 32
## bone, end bone ("" = along the parent->bone direction), radius, mass, joint (cone/hinge/none), extra length
const DEF := [
	["Hips", "", 0.115, 11.0, "none", 0.0],
	["Spine", "Chest", 0.105, 6.0, "cone", 0.0],
	["Chest", "UpperChest", 0.115, 6.0, "cone", 0.0],
	["UpperChest", "Neck", 0.125, 8.0, "cone", 0.0],
	["Head", "", 0.095, 4.5, "cone", 0.13],
	["LeftUpperArm", "LeftLowerArm", 0.048, 2.2, "cone", 0.0],
	["LeftLowerArm", "LeftHand", 0.042, 1.6, "hinge", 0.08],
	["RightUpperArm", "RightLowerArm", 0.048, 2.2, "cone", 0.0],
	["RightLowerArm", "RightHand", 0.042, 1.6, "hinge", 0.08],
	["LeftUpperLeg", "LeftLowerLeg", 0.075, 8.0, "cone", 0.0],
	["LeftLowerLeg", "LeftFoot", 0.058, 4.0, "hinge", 0.0],
	["LeftFoot", "LeftToes", 0.045, 1.0, "cone", 0.05],
	["RightUpperLeg", "RightLowerLeg", 0.075, 8.0, "cone", 0.0],
	["RightLowerLeg", "RightFoot", 0.058, 4.0, "hinge", 0.0],
	["RightFoot", "RightToes", 0.045, 1.0, "cone", 0.05],
]
const ZONE_BONE := {"head": "Head", "neck": "UpperChest", "chest": "Chest", "belly": "Spine", "arm": "RightUpperArm",
	"leg": "LeftUpperLeg"}

static var _active: Array = []

var ch: Node3D
var skel: Skeleton3D
var sim: PhysicalBoneSimulator3D
var bones := {}                   # bone name -> PhysicalBone3D
var info: Dictionary = {}
var delay := 0.3
var _t := 0.0
var _still := 0.0
var _started := false
var _done := false

static func begin(character: Node3D, hit: Dictionary, wait := 0.3) -> Ragdoll:
	if Game.headless or character == null or not character.is_inside_tree():
		return null
	var sk: Skeleton3D = character.get("skeleton")
	if sk == null or sk.find_bone("Hips") < 0:
		return null
	var cam := character.get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_to(character.global_position) > RANGE:
		return null
	cancel(character)
	var r := Ragdoll.new()
	r.name = "Ragdoll"
	r.ch = character
	r.skel = sk
	r.info = hit
	r.delay = wait
	character.add_child(r)
	return r

static func cancel(character: Node3D) -> void:
	var r := character.get_node_or_null("Ragdoll") as Ragdoll
	if r != null:
		r._teardown()
		r.queue_free()

static func active_count() -> int:
	_active = _active.filter(func(x): return is_instance_valid(x) and not x._done)
	return _active.size()

func _physics_process(dt: float) -> void:
	if _done:
		return
	_t += dt
	if not _started:
		if _t >= delay:
			_start()
		return
	# settle: every body slow for half a second, or time out
	var fast := false
	for pb in bones.values():
		if (pb as PhysicalBone3D).linear_velocity.length() > 0.12:
			fast = true
			break
	_still = 0.0 if fast else _still + dt
	if _still > 0.5 or _t > delay + SETTLE_MAX:
		freeze()

func _start() -> void:
	_started = true
	# LOD: make room
	active_count()
	while _active.size() >= MAX_ACTIVE:
		var old: Ragdoll = _active.pop_front()
		if is_instance_valid(old):
			old.freeze()
	_active.append(self)
	_build()
	if bones.is_empty():
		_done = true
		return
	sim.influence = 0.0
	sim.physical_bones_start_simulation()
	var tw := create_tween()
	tw.tween_property(sim, "influence", 1.0, 0.12)
	# the killing shot shoves the bone it hit (and a little of the hips)
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	if dir.length() < 0.01:
		dir = ch.global_transform.basis.z           # fall backwards
	dir = dir.normalized()
	var strength := clampf(float(info.get("amount", 40.0)) * 0.06, 1.5, 6.0)
	var bn: String = ZONE_BONE.get(str(info.get("zone", "chest")), "Chest")
	var pb: PhysicalBone3D = bones.get(bn, bones.get("Chest"))
	if pb != null:
		pb.apply_central_impulse(dir * strength + Vector3.UP * 0.4)
	if bones.has("Hips"):
		(bones["Hips"] as PhysicalBone3D).apply_central_impulse(dir * strength * 0.5)

func _bone_global(name: String) -> Transform3D:
	var i := skel.find_bone(name)
	return skel.global_transform * skel.get_bone_global_pose(i) if i >= 0 else skel.global_transform

func _build() -> void:
	sim = PhysicalBoneSimulator3D.new()
	sim.name = "RagdollSim"
	skel.add_child(sim)
	for d in DEF:
		var bname: String = d[0]
		var bi := skel.find_bone(bname)
		if bi < 0:
			continue
		var bg := _bone_global(bname)
		var a := bg.origin
		var b: Vector3
		if bname == "Hips":
			# across the pelvis between the hip joints
			var l := _bone_global("LeftUpperLeg").origin
			var r := _bone_global("RightUpperLeg").origin
			a = l
			b = r
		elif str(d[1]) != "" and skel.find_bone(d[1]) >= 0:
			b = _bone_global(d[1]).origin
		else:
			var par := skel.get_bone_parent(bi)
			var pdir := (a - (skel.global_transform * skel.get_bone_global_pose(par)).origin).normalized() if par >= 0 else Vector3.UP
			b = a + pdir * float(d[5])
		if float(d[5]) > 0.0 and str(d[1]) != "":
			b = b + (b - a).normalized() * float(d[5])
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + bname
		pb.set("bone_name", bname)
		pb.mass = float(d[3])
		pb.friction = 0.9
		pb.bounce = 0.05
		pb.linear_damp = 0.15
		pb.angular_damp = 1.2
		pb.collision_layer = LAYER
		pb.collision_mask = 1
		match str(d[4]):
			"cone":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
				pb.set("joint_constraints/swing_span", 42.0)
				pb.set("joint_constraints/twist_span", 28.0)
			"hinge":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
				pb.set("joint_constraints/angular_limit_enabled", true)
				pb.set("joint_constraints/angular_limit_upper", 0.0)
				pb.set("joint_constraints/angular_limit_lower", -130.0)
			_:
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		sim.add_child(pb)
		pb.global_transform = bg
		# capsule from a to b, expressed in the bone's frame
		var inv := bg.affine_inverse()
		var la := inv * a
		var lb := inv * b
		var v := lb - la
		var ln := maxf(v.length(), 0.02)
		var y := v / ln
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		var rad := float(d[2])
		cap.radius = rad
		cap.height = ln + rad * 2.0
		cs.shape = cap
		cs.transform = Transform3D(Basis(x, y, z), (la + lb) * 0.5)
		pb.add_child(cs)
		bones[bname] = pb

## Write the simulated pose into the skeleton and drop the physics bodies.
func freeze() -> void:
	if _done:
		return
	_done = true
	if sim == null or not is_instance_valid(sim):
		return
	var inv := skel.global_transform.affine_inverse()
	var target := {}
	for bname in bones:
		var pb: PhysicalBone3D = bones[bname]
		target[skel.find_bone(bname)] = inv * pb.global_transform * pb.body_offset.affine_inverse()
	var anim: AnimationPlayer = ch.get("anim")
	if anim != null:
		anim.pause()
	var cur := {}
	for i in skel.get_bone_count():
		var p := skel.get_bone_parent(i)
		var pg: Transform3D = cur.get(p, Transform3D.IDENTITY) if p >= 0 else Transform3D.IDENTITY
		if target.has(i):
			var g: Transform3D = target[i]
			var lt := pg.affine_inverse() * g
			skel.set_bone_pose_position(i, lt.origin)
			skel.set_bone_pose_rotation(i, lt.basis.orthonormalized().get_rotation_quaternion())
			cur[i] = g
		else:
			cur[i] = pg * skel.get_bone_pose(i)
	_teardown()

func _teardown() -> void:
	if sim != null and is_instance_valid(sim):
		if sim.is_simulating_physics():
			sim.physical_bones_stop_simulation()
		sim.queue_free()
	sim = null
	bones.clear()
	_done = true
