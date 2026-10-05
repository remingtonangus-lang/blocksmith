class_name HumanFootIK
extends SkeletonModifier3D
## Ground contact for people (FrontierCharacter humanoid skeleton) on slopes, steps, porches and rocks, applied on
## top of the animation: each foot is ray-cast to the ground under it, the hips drop by the lower foot's offset so
## the far leg can reach, both legs are solved with two-bone IK (knees forward), and planted feet tilt to the
## ground normal. Weight follows speed (full at idle/walk, light at a run, off in the air and when mounted) and the
## whole thing sleeps past CAM_RANGE. Added by Human/Player when the character model has humanoid leg bones.

const CAM_RANGE := 28.0
const MAX_DROP := 0.38          # m the hips may sink for the lower foot
const MAX_RISE := 0.45          # m a foot may be lifted onto a step
const MAX_TILT := deg_to_rad(28.0)

var body: CharacterBody3D       # the actor (its origin is the floor contact the animation is authored against)
var _b := {}
var _off := [0.0, 0.0]          # smoothed per-foot ground offsets (L, R)
var _norm := [Vector3.UP, Vector3.UP]
var _drop := 0.0
var _w := 0.0
var calls := 0
var use_cam_range := true       # tests turn the camera-distance sleep off

## Adds foot IK under the actor's character skeleton (no-op headless, for stand-ins or skeletons without legs).
static func attach(actor: CharacterBody3D, force := false) -> HumanFootIK:
	if (Game.headless and not force) or not is_instance_valid(actor):
		return null
	var vis = actor.get("visual")
	var sk: Skeleton3D = vis.get("skeleton") if vis != null and vis.get("skeleton") != null else null
	if sk == null or sk.find_bone("LeftUpperLeg") < 0 or sk.has_node("FootIK"):
		return null
	var ik := HumanFootIK.new()
	ik.name = "FootIK"
	sk.add_child(ik)
	sk.move_child(ik, 0)       # before hand/gun modifiers, after the animation
	ik.setup(actor)
	return ik

func setup(actor: CharacterBody3D) -> void:
	body = actor
	var sk := get_skeleton()
	if sk == null:
		return
	for n in ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]:
		_b[n] = sk.find_bone(n)

func valid() -> bool:
	for k in _b:
		if _b[k] < 0:
			return false
	return not _b.is_empty()

func _target_weight() -> float:
	if body == null or not is_instance_valid(body) or not body.is_on_floor():
		return 0.0
	if body.get("on_horse") != null or body.get("alive") == false:
		return 0.0
	var cam := get_viewport().get_camera_3d()
	if use_cam_range and cam != null and cam.global_position.distance_squared_to(body.global_position) > CAM_RANGE * CAM_RANGE:
		return 0.0
	var spd := Vector2(body.velocity.x, body.velocity.z).length()
	return clampf(1.0 - (spd - 2.0) / 4.0, 0.25, 1.0)

func _process_modification_with_delta(delta: float) -> void:
	if not valid():
		return
	_w = move_toward(_w, _target_weight(), delta * 4.0)
	if _w <= 0.001:
		_drop = 0.0
		_off = [0.0, 0.0]
		return
	calls += 1
	var sk := get_skeleton()
	var sxf := sk.global_transform
	var inv := sxf.affine_inverse()
	var base_y := body.global_position.y
	var space := body.get_world_3d().direct_space_state
	var k := 1.0 - exp(-14.0 * delta)
	var feet := [_b.LeftFoot, _b.RightFoot]
	for i in 2:
		var fw: Vector3 = sxf * sk.get_bone_global_pose(feet[i]).origin
		var from := Vector3(fw.x, base_y + MAX_RISE + 0.3, fw.z)
		var q := PhysicsRayQueryParameters3D.create(from, Vector3(fw.x, base_y - MAX_DROP - 0.3, fw.z), 1)
		q.exclude = [body.get_rid()]
		var hit := space.intersect_ray(q)
		var off := 0.0
		var n := Vector3.UP
		if not hit.is_empty():
			off = clampf(hit.position.y - base_y, -MAX_DROP, MAX_RISE)
			n = hit.normal
		_off[i] = lerpf(_off[i], off, k)
		_norm[i] = _norm[i].slerp(n, k)
	var want_drop := minf(minf(_off[0], _off[1]), 0.0)
	_drop = lerpf(_drop, want_drop, k)
	# hips down (world up expressed in skeleton space; the skeleton may be scaled to the character's height)
	var up_s := (inv.basis * Vector3.UP)
	var hips := sk.get_bone_global_pose(_b.Hips)
	hips.origin += up_s * _drop * _w
	sk.set_bone_global_pose(_b.Hips, hips)
	var fwd_s := (inv.basis * -body.global_transform.basis.z).normalized()
	var sides := [["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"], ["RightUpperLeg", "RightLowerLeg", "RightFoot"]]
	for i in 2:
		var s: Array = sides[i]
		var foot := sk.get_bone_global_pose(_b[s[2]])
		# animated foot height is kept relative to the ground under it; the hip drop is compensated
		var target: Vector3 = foot.origin + up_s * ((_off[i] - _drop) * _w)   # the hip drop moved the foot too
		_two_bone(sk, _b[s[0]], _b[s[1]], _b[s[2]], target, fwd_s)
		# tilt the planted foot to the slope (limited), only when it is near the ground in the animation
		var n_s: Vector3 = (inv.basis * _norm[i]).normalized()
		var tilt := up_s.normalized().angle_to(n_s)
		if tilt > 0.01:
			var axis := up_s.normalized().cross(n_s).normalized()
			var fp := sk.get_bone_global_pose(_b[s[2]])
			fp.basis = Basis(axis, minf(tilt, MAX_TILT) * _w) * fp.basis
			sk.set_bone_global_pose(_b[s[2]], fp)

## Analytic two-bone IK (as RiderIK): rotate upper a and lower b so end c reaches t, knee toward pole.
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
		pl = (B - A) - dir * (B - A).dot(dir)
	pl = pl.normalized()
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
