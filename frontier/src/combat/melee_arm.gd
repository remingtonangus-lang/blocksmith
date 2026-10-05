class_name MeleeArm
extends SkeletonModifier3D
## Procedural punch for characters without punch clips: the fist travels from its animated place to the target
## and back (fast out, brief hold, slower recovery) with two-bone arm IK, the chest turning into the blow.

var _b := {}
var _t := 1.0
var _dur := 0.4
var _side := 1
var _target := Vector3.ZERO

func setup() -> void:
	var sk := get_skeleton()
	for n in ["Chest", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"]:
		_b[n] = sk.find_bone(n)

func throw(side: int, world_target: Vector3, duration: float) -> void:
	_side = side
	_target = world_target
	_dur = maxf(duration, 0.2)
	_t = 0.0

func _weight() -> float:
	var f := _t / _dur
	if f >= 1.0:
		return 0.0
	if f < 0.3:
		var a := f / 0.3
		return a * a * (3.0 - 2.0 * a)
	if f < 0.45:
		return 1.0
	var r := (f - 0.45) / 0.55
	return 1.0 - r * r * (3.0 - 2.0 * r)

func _process_modification_with_delta(delta: float) -> void:
	if _t >= _dur:
		return
	_t += delta
	var w := _weight()
	if w <= 0.001:
		return
	var sk := get_skeleton()
	var L := "Left" if _side < 0 else "Right"
	var a: int = _b.get(L + "UpperArm", -1)
	var b: int = _b.get(L + "LowerArm", -1)
	var c: int = _b.get(L + "Hand", -1)
	if a < 0 or b < 0 or c < 0:
		return
	var inv := sk.global_transform.affine_inverse()
	# chest turns into the blow
	var ch: int = _b.get("Chest", -1)
	if ch >= 0:
		var cp := sk.get_bone_global_pose(ch)
		cp.basis = Basis(Vector3.UP, -0.35 * _side * w) * cp.basis
		sk.set_bone_global_pose(ch, cp)
	var hand := sk.get_bone_global_pose(c).origin
	var goal := hand.lerp(inv * _target, w)
	var elbow_pole := (inv.basis * Vector3(0, -1, 0)).normalized() + (inv.basis * Vector3(_side, 0, 0)).normalized() * 0.5
	_two_bone(sk, a, b, c, goal, elbow_pole.normalized())

func _two_bone(sk: Skeleton3D, a: int, b: int, c: int, t: Vector3, pole: Vector3) -> void:
	var ta := sk.get_bone_global_pose(a)
	var tb := sk.get_bone_global_pose(b)
	var tc := sk.get_bone_global_pose(c)
	var A := ta.origin
	var B := tb.origin
	var C := tc.origin
	var l1 := A.distance_to(B)
	var l2 := B.distance_to(C)
	if l1 < 0.001 or l2 < 0.001:
		return
	var at := t - A
	var d := clampf(at.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := at.normalized()
	var pl := pole - dir * pole.dot(dir)
	if pl.length_squared() < 1e-6:
		return
	pl = pl.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var nb := A + (dir * cos_a + pl * sin_a) * l1
	sk.set_bone_global_pose(a, Transform3D(Basis(Quaternion((B - A).normalized(), (nb - A).normalized())) * ta.basis, A))
	var tb2 := sk.get_bone_global_pose(b)
	var tc2 := sk.get_bone_global_pose(c)
	var q2 := Quaternion((tc2.origin - tb2.origin).normalized(), (A + dir * d - tb2.origin).normalized())
	sk.set_bone_global_pose(b, Transform3D(Basis(q2) * tb2.basis, tb2.origin))
	var tc3 := sk.get_bone_global_pose(c)
	sk.set_bone_global_pose(c, Transform3D(tc.basis, tc3.origin))
