class_name RiderIK
extends SkeletonModifier3D
## Procedural riding pose for a FrontierCharacter (Godot humanoid bone names) astride a Horse, applied on top of
## whatever the character's AnimationTree plays (its "mounted" state holds the idle pose): hips sit in the saddle
## seat, legs open around the barrel with the feet in the stirrups (two-bone IK UpperLeg/LowerLeg/Foot, knees
## pointing forward and out), hands on the reins just above the horn (two-bone IK UpperArm/LowerArm/Hand, elbows
## down and back), the spine leans forward with speed and follows the saddle's motion. Added by Horse.mount() when
## the rider has a humanoid skeleton; removed on dismount.
## Attachment points (horse model space, Godot axes, rest pose; they ride on bone spine_thorax):
##   seat (saddle seat, pelvis contact)   SEAT    = (0, 1.66, -0.12)
##   stirrup treads (where the foot rests) STIRRUP = (+-0.27, 0.76, -0.25)
##   rein grip (hands, above the horn)    GRIP    = (+-0.07, 1.80, -0.40)

const SEAT := Vector3(0.0, 1.66, -0.12)
const STIRRUP := Vector3(0.27, 0.76, -0.25)
const GRIP := Vector3(0.07, 1.80, -0.40)

var horse: Node3D                    # Horse
var weight := 1.0
var _b := {}

func setup(h: Node3D) -> void:
	horse = h
	var sk := get_skeleton()
	if sk == null:
		return
	for n in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
			"RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
			"RightLowerArm", "RightHand"]:
		_b[n] = sk.find_bone(n)

func valid() -> bool:
	return _b.get("Hips", -1) >= 0 and _b.get("LeftUpperLeg", -1) >= 0 and _b.get("LeftUpperArm", -1) >= 0

## Horse attachment point (model space) -> world, following the saddle bone.
func horse_point(local: Vector3) -> Vector3:
	var vis = horse.visual
	if vis == null or vis.skeleton == null:
		return horse.global_transform * local
	var sk: Skeleton3D = vis.skeleton
	var bi := sk.find_bone("spine_thorax")
	if bi < 0:
		return vis.global_transform * local
	var rest := sk.get_bone_global_rest(bi)
	var pose := sk.get_bone_global_pose(bi)
	return sk.global_transform * (pose * (rest.affine_inverse() * local))

func _process_modification_with_delta(_delta: float) -> void:
	if horse == null or not valid() or weight <= 0.0:
		return
	var sk := get_skeleton()
	var inv := sk.global_transform.affine_inverse()
	# hips into the seat (keep the animated hip orientation, face the horse's forward)
	var seat_w := horse_point(SEAT) + Vector3(0, 0.08, 0)
	var hips := sk.get_bone_global_pose(_b.Hips)
	var hips_target := inv * seat_w
	hips.origin = hips.origin.lerp(hips_target, weight)
	sk.set_bone_global_pose(_b.Hips, hips)
	# lean forward with speed
	var spd: float = absf(float(horse.get("speed")))
	var lean := clampf(spd / 12.0, 0.0, 1.0) * 0.35
	if _b.Spine >= 0 and lean > 0.01:
		var sp := sk.get_bone_global_pose(_b.Spine)
		var right := (inv.basis * horse.global_transform.basis.x).normalized()
		sp.basis = Basis(right, -lean) * sp.basis
		sk.set_bone_global_pose(_b.Spine, sp)
	var fwd := (inv.basis * -horse.global_transform.basis.z).normalized()
	var up := (inv.basis * horse.global_transform.basis.y).normalized()
	for side: float in [-1.0, 1.0]:
		var L := "Left" if side < 0 else "Right"
		var foot_w := horse_point(Vector3(STIRRUP.x * side, STIRRUP.y, STIRRUP.z))
		var out := (inv.basis * horse.global_transform.basis.x).normalized() * side
		_two_bone(sk, _b[L + "UpperLeg"], _b[L + "LowerLeg"], _b[L + "Foot"], inv * foot_w, (fwd + out * 0.6).normalized())
		var hand_w := horse_point(Vector3(GRIP.x * side, GRIP.y, GRIP.z))
		_two_bone(sk, _b[L + "UpperArm"], _b[L + "LowerArm"], _b[L + "Hand"], inv * hand_w, (-up - fwd * 0.4 + out * 0.3).normalized())

## Analytic two-bone IK: rotate a (upper) and b (lower) so the end c reaches target t, bending toward pole.
func _two_bone(sk: Skeleton3D, a: int, b: int, c: int, t: Vector3, pole: Vector3) -> void:
	if a < 0 or b < 0 or c < 0:
		return
	var ta := sk.get_bone_global_pose(a)
	var tb := sk.get_bone_global_pose(b)
	var tc := sk.get_bone_global_pose(c)
	var A := ta.origin
	var B := tb.origin
	var C := tc.origin
	var l1 := A.distance_to(B)
	var l2 := B.distance_to(C)
	var at := t - A
	var d := clampf(at.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := at.normalized()
	var pl := (pole - dir * pole.dot(dir)).normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var nb := A + (dir * cos_a + pl * sin_a) * l1
	var q1 := Quaternion((B - A).normalized(), (nb - A).normalized())
	sk.set_bone_global_pose(a, Transform3D(Basis(q1) * ta.basis, A))
	var tb2 := sk.get_bone_global_pose(b)
	var tc2 := sk.get_bone_global_pose(c)
	var q2 := Quaternion((tc2.origin - tb2.origin).normalized(), (A + dir * d - tb2.origin).normalized())
	sk.set_bone_global_pose(b, Transform3D(Basis(q2) * tb2.basis, tb2.origin))
	var tc3 := sk.get_bone_global_pose(c)
	sk.set_bone_global_pose(c, Transform3D(tc.basis, tc3.origin))
