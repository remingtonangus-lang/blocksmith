class_name HorseIK
extends SkeletonModifier3D
## Runtime foot IK on top of the keyframed gaits: each hoof is planted on the real ground. The keyframes assume a
## flat ground at the model's y = 0; for every leg we measure how far the actual ground under the hoof is from that
## plane (along the model's up axis) and move the knee (fore) / hock (hind) by that amount with an analytic two-bone
## solve on humerus+forearm / femur+tibia, keeping the cannon, pastern and hoof orientation from the animation.
## Stance hooves follow the ground both ways; swing hooves are only lifted (never pushed into a bump). The horse
## controller tilts/raises the whole body from the four ground contacts first, so the residual here stays small.

const CHAINS := {
	"LF": ["humerus_L", "forearm_L", "fcannon_L"], "RF": ["humerus_R", "forearm_R", "fcannon_R"],
	"LH": ["femur_L", "tibia_L", "hcannon_L"], "RH": ["femur_R", "tibia_R", "hcannon_R"],
}
const MAX_UP := 0.32
const MAX_DOWN := 0.14

var vis: HorseVisual
var ground_fn: Callable                 # (x, z) -> ground height in world metres
var enabled := true
var offsets := {"LF": 0.0, "RF": 0.0, "LH": 0.0, "RH": 0.0}   # last applied (model metres), for debugging/oracle
var _idx := {}

func setup(v: HorseVisual) -> void:
	vis = v
	var sk := v.skeleton
	for leg in CHAINS:
		var ids: Array[int] = []
		for b in CHAINS[leg]:
			ids.append(sk.find_bone(b))
		if ids.min() >= 0 and v.hoof_bone(leg) >= 0:
			_idx[leg] = ids

func _process_modification_with_delta(_delta: float) -> void:
	if not enabled or vis == null or not ground_fn.is_valid():
		return
	var sk := get_skeleton()
	if sk == null:
		return
	var sgt := sk.global_transform
	var up_w := sgt.basis.y.normalized()
	var inv := sgt.affine_inverse()
	for leg in _idx:
		var ids: Array = _idx[leg]
		var hb: int = vis.hoof_bone(leg)
		var sole_m := sk.get_bone_global_pose(hb) * vis.sole_local(leg)     # skeleton (model) space
		var h_anim := sole_m.y                                              # height above the anim ground plane
		var plane_pt := sgt * Vector3(sole_m.x, 0.0, sole_m.z)
		var g: float = ground_fn.call(plane_pt.x, plane_pt.z)
		var dy := (g - plane_pt.y) / maxf(up_w.y, 0.5)
		var stance := 1.0 - smoothstep(0.03, 0.09, h_anim)
		var off := clampf(dy, -MAX_DOWN, MAX_UP)
		off = lerpf(maxf(off, 0.0), off, stance)
		offsets[leg] = off
		if absf(off) < 0.002:
			continue
		_two_bone(sk, ids[0], ids[1], ids[2], Vector3(0, off, 0))

func _two_bone(sk: Skeleton3D, a: int, b: int, c: int, delta: Vector3) -> void:
	var ta := sk.get_bone_global_pose(a)
	var tb := sk.get_bone_global_pose(b)
	var tc := sk.get_bone_global_pose(c)
	var A := ta.origin
	var B := tb.origin
	var C := tc.origin
	var T := C + delta
	var l1 := A.distance_to(B)
	var l2 := B.distance_to(C)
	var at := T - A
	var d := clampf(at.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := at.normalized()
	var n := (B - A).cross(C - B)
	if n.length_squared() < 1e-8:
		n = Vector3.RIGHT
	n = n.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var ang := acos(cos_a)
	var b1 := A + dir.rotated(n, ang) * l1
	var b2 := A + dir.rotated(n, -ang) * l1
	var nb := b1 if b1.distance_squared_to(B) < b2.distance_squared_to(B) else b2
	var q1 := Quaternion((B - A).normalized(), (nb - A).normalized())
	sk.set_bone_global_pose(a, Transform3D(Basis(q1) * ta.basis, A))
	var tb2 := sk.get_bone_global_pose(b)
	var tc2 := sk.get_bone_global_pose(c)
	var q2 := Quaternion((tc2.origin - tb2.origin).normalized(), (A + dir * d - tb2.origin).normalized())
	sk.set_bone_global_pose(b, Transform3D(Basis(q2) * tb2.basis, tb2.origin))
	var tc3 := sk.get_bone_global_pose(c)
	sk.set_bone_global_pose(c, Transform3D(tc.basis, tc3.origin))
