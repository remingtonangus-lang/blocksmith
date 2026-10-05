class_name RiderIK
extends SkeletonModifier3D
## Procedural riding pose for a FrontierCharacter (Godot humanoid bone names) astride a Horse, applied on top of
## whatever the character's AnimationTree plays (its "mounted" state holds the idle pose):
##   - hips sit in the saddle seat (a half seat out of the saddle at the gallop), following the saddle's motion
##   - legs open around the barrel with the feet in the stirrups (two-bone IK UpperLeg/LowerLeg/Foot, knees forward
##     and out)
##   - hands hold the reins above the horn (two-bone IK UpperArm/LowerArm/Hand, elbows down and back), and live
##     rein geometry runs from the bit rings to the hands (the horse's resting reins are hidden while ridden)
##   - the torso leans forward by gait (walk, trot, canter, gallop) with the neck and head counter-rotating so the
##     rider keeps looking ahead
##   - the duster/coat-tail spring chains collide with the horse's barrel and the saddle, so they drape over the
##     horse instead of passing through it
##   - mount and dismount clips: the near foot goes into the stirrup, the rider rises, the off leg swings over the
##     croup and settles (dismount plays it backwards, then the modifier removes itself)
## Added by Horse.mount() when the rider has a humanoid skeleton.
## Attachment points (horse model space, Godot axes, rest pose; they ride on bone spine_thorax, the bit on head):
##   seat (saddle seat, pelvis contact)   SEAT    = (0, 1.66, -0.12)
##   stirrup treads (where the foot rests) STIRRUP = (+-0.27, 0.76, -0.25)
##   rein grip (hands, above the horn)    GRIP    = (+-0.07, 1.80, -0.40)
##   bit rings (rein ends at the mouth)    BIT     = (+-0.058, 1.437, -1.385) on bone head

const SEAT := Vector3(0.0, 1.66, -0.12)
const STIRRUP := Vector3(0.27, 0.76, -0.25)
const GRIP := Vector3(0.07, 1.80, -0.40)
const BIT := Vector3(0.058, 1.437, -1.385)
const LEAN := {"idle": 0.03, "walk": 0.07, "trot": 0.16, "canter": 0.38, "gallop": 0.62, "swim": 0.2}
const MOUNT_TIME := 1.25
const DISMOUNT_TIME := 1.0

var horse: Node3D                    # Horse
var weight := 1.0
## -1 = seated; 0..1 = mount clip progress; 1..2 = dismount clip progress (1 = seated, 2 = standing beside)
var phase := -1.0
var phase_override := -1.0           # tests: hold a phase
var side := -1.0                     # side mounted from (-1 left, +1 right)
var _b := {}
var _lean := 0.0
var _reins: MeshInstance3D
var _rein_mesh: ImmediateMesh
var _horse_reins: Array = []         # the horse's resting rein meshes (hidden while ridden)
var _barrel: SpringBoneCollisionCapsule3D
var _cantle: SpringBoneCollisionSphere3D
var _springs: SpringBoneSimulator3D
var _dismount_from := Transform3D()
var _dismount_to := Transform3D()
var _rider: Node3D

func setup(h: Node3D) -> void:
	horse = h
	var sk := get_skeleton()
	if sk == null:
		return
	for n in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
			"RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
			"RightLowerArm", "RightHand"]:
		_b[n] = sk.find_bone(n)
	side = float(h.get("rider_side")) if h.get("rider_side") != null and float(h.get("rider_side")) != 0.0 else -1.0
	_setup_reins()
	_setup_cloth_collision(sk)

func valid() -> bool:
	return _b.get("Hips", -1) >= 0 and _b.get("LeftUpperLeg", -1) >= 0 and _b.get("LeftUpperArm", -1) >= 0

## Start the mount clip (Horse.mount calls this; the horse moves the rider's root from the side into the seat).
func start_mount() -> void:
	phase = 0.0

## Start the dismount clip: the rider's root has already been placed on the ground beside the horse by
## Horse.dismount(); the visual starts in the saddle and is carried down over DISMOUNT_TIME, then this frees itself.
func start_dismount(rider: Node3D, from: Transform3D) -> void:
	_rider = rider
	_dismount_from = from
	_dismount_to = rider.global_transform
	phase = 1.0
	_show_horse_reins(true)
	if _reins:
		_reins.visible = false

func _exit_tree() -> void:
	_show_horse_reins(true)
	if _reins and is_instance_valid(_reins):
		_reins.queue_free()
	for n in [_barrel, _cantle]:
		if n != null and is_instance_valid(n):
			n.queue_free()

## Horse attachment point (model space) -> world, following bone `bone` of the horse's skeleton.
func horse_point(local: Vector3, bone := "spine_thorax") -> Vector3:
	var vis = horse.visual
	if vis == null or vis.skeleton == null:
		return horse.global_transform * local
	var sk: Skeleton3D = vis.skeleton
	var bi := sk.find_bone(bone)
	if bi < 0:
		return vis.global_transform * local
	var rest := sk.get_bone_global_rest(bi)
	var pose := sk.get_bone_global_pose(bi)
	return sk.global_transform * (pose * (rest.affine_inverse() * local))

func _process(delta: float) -> void:
	if phase_override >= 0.0:
		phase = phase_override
		return
	if phase >= 0.0 and phase < 1.0:
		phase += delta / MOUNT_TIME
		if phase >= 1.0:
			phase = -1.0
	elif phase >= 1.0:
		phase += delta / DISMOUNT_TIME
		if _rider != null and is_instance_valid(_rider):
			var vis = _rider.get("visual")
			if vis is Node3D:
				var e := _ease(clampf(phase - 1.0, 0.0, 1.0))
				var t := _dismount_from.interpolate_with(_rider.global_transform, e)
				t.origin.y += sin(e * PI) * 0.25
				(vis as Node3D).global_transform = t
		if phase >= 2.0:
			if _rider != null and is_instance_valid(_rider) and _rider.get("visual") is Node3D:
				(_rider.get("visual") as Node3D).transform = Transform3D.IDENTITY
			queue_free()

static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

func _process_modification_with_delta(delta: float) -> void:
	if horse == null or not valid() or weight <= 0.0:
		return
	var sk := get_skeleton()
	var inv := sk.global_transform.affine_inverse()
	var hb: Basis = horse.global_transform.basis
	var fwd := (inv.basis * -hb.z).normalized()
	var up := (inv.basis * hb.y).normalized()
	var right := (inv.basis * hb.x).normalized()
	# clip state: m = 0 standing beside the horse ... 1 seated (mount runs 0 -> 1, dismount 1 -> 0)
	var m := 1.0
	if phase >= 0.0 and phase < 1.0:
		m = phase
	elif phase >= 1.0:
		m = 1.0 - clampf(phase - 1.0, 0.0, 1.0)
	var seated := m >= 0.999
	var spd: float = absf(float(horse.get("speed")))
	var gait := str(horse.get("gait")) if horse.get("gait") != null else "idle"
	var want_lean: float = LEAN.get(gait, 0.05) if seated else 0.12
	_lean = lerpf(_lean, want_lean, 1.0 - exp(-4.0 * delta))
	# ---- hips: into the seat; half seat (out of the saddle, weight in the stirrups) at the gallop
	var half_seat := clampf((spd - 9.0) / 4.0, 0.0, 1.0) * 0.06 if seated else 0.0
	var seat_w := horse_point(SEAT) + horse.global_transform.basis.y * (0.08 + half_seat)
	var hips := sk.get_bone_global_pose(_b.Hips)
	var rise := _ease(clampf((m - 0.15) / 0.45, 0.0, 1.0))           # 0 standing, 1 up over the saddle
	var hips_target := inv * seat_w
	if not seated:
		# beside the horse on the near side, rising to stand in the stirrup, then swinging over
		var beside := inv * horse_point(Vector3(side * 0.62, 1.0, -0.12))
		var over := hips_target + up * 0.12 + right * side * 0.18 * (1.0 - _ease(clampf((m - 0.6) / 0.4, 0.0, 1.0)))
		hips_target = beside.lerp(over, rise)
	hips.origin = hips.origin.lerp(hips_target, weight)
	if not seated:
		# face the horse's side while mounting, turn forward as the leg comes over
		var turn := (1.0 - _ease(clampf((m - 0.45) / 0.4, 0.0, 1.0))) * side * 1.2
		hips.basis = Basis(up, turn) * hips.basis
	sk.set_bone_global_pose(_b.Hips, hips)
	# ---- torso lean forward, neck and head counter-rotate to keep the eyes level
	var spine_parts := [["Spine", 0.5], ["Chest", 0.3], ["UpperChest", 0.2], ["Neck", -0.35], ["Head", -0.45]]
	for sp in spine_parts:
		var bi: int = _b.get(sp[0], -1)
		if bi < 0:
			continue
		var t := sk.get_bone_global_pose(bi)
		t.basis = Basis(right, -_lean * float(sp[1])) * t.basis
		sk.set_bone_global_pose(bi, t)
	# ---- legs: stirrups (near foot first during the mount; the off leg swings over the croup)
	for s: float in [-1.0, 1.0]:
		var L := "Left" if s < 0 else "Right"
		var out := right * s
		var foot_w := inv * horse_point(Vector3(STIRRUP.x * s, STIRRUP.y, STIRRUP.z))
		if not seated:
			var ground := inv * horse_point(Vector3(side * 0.55 + s * 0.12, 0.05, -0.12 + s * side * 0.05))
			if is_equal_approx(s, side):
				# near leg: lifted into the near stirrup at the start, stays there
				foot_w = ground.lerp(foot_w, _ease(clampf(m / 0.15, 0.0, 1.0)))
			else:
				# off leg: from the ground, up and over the croup (behind the cantle), down into the far stirrup
				var u := clampf((m - 0.25) / 0.6, 0.0, 1.0)
				var croup := inv * horse_point(Vector3(0.0, 2.05, 0.45))
				var p0 := ground.lerp(ground + up * 0.3, clampf(m / 0.25, 0.0, 1.0))
				var a := p0.lerp(croup, u)
				var b := croup.lerp(foot_w, u)
				foot_w = a.lerp(b, u)
		_two_bone(sk, _b[L + "UpperLeg"], _b[L + "LowerLeg"], _b[L + "Foot"], foot_w, (fwd + out * 0.6).normalized())
		# ---- arms: hands on the reins above the horn (on the horn and the cantle while mounting)
		var hand_w := inv * horse_point(Vector3(GRIP.x * s - _lean * 0.0, GRIP.y, GRIP.z - _lean * 0.12))
		if not seated and not is_equal_approx(s, side):
			hand_w = inv * horse_point(Vector3(side * 0.1, 1.85, 0.25)).lerp(hand_w, _ease(clampf((m - 0.55) / 0.4, 0.0, 1.0)))
		_two_bone(sk, _b[L + "UpperArm"], _b[L + "LowerArm"], _b[L + "Hand"], hand_w, (-up - fwd * 0.4 + out * 0.3).normalized())
	_update_cloth_collision(m)
	if seated and phase < 1.0:
		_update_reins(sk)
	elif _reins:
		_reins.visible = false

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

# ---------------------------------------------------------------------------------------------------------------
# Reins: two leather straps from the bit rings to the hands, sagging a little, rebuilt every frame.
func _setup_reins() -> void:
	var vis = horse.get("visual")
	if vis == null:
		return
	var mat: Material = null
	for mi in vis.get("meshes"):
		if String(mi.name).to_lower().begins_with("reins"):
			_horse_reins.append(mi)
			if mi.mesh and mi.mesh.get_surface_count() > 0:
				mat = mi.mesh.surface_get_material(0)
	_rein_mesh = ImmediateMesh.new()
	_reins = MeshInstance3D.new()
	_reins.name = "RiderReins"
	_reins.mesh = _rein_mesh
	_reins.top_level = true
	_reins.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mat == null:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.16, 0.1, 0.06)
		sm.roughness = 0.6
		mat = sm
	_reins.material_override = mat
	horse.add_child(_reins)
	_reins.global_transform = Transform3D.IDENTITY
	_show_horse_reins(false)

func _show_horse_reins(on: bool) -> void:
	for mi in _horse_reins:
		if is_instance_valid(mi):
			mi.visible = on

func _update_reins(sk: Skeleton3D) -> void:
	if _reins == null:
		return
	_reins.visible = true
	_reins.global_transform = Transform3D.IDENTITY
	_rein_mesh.clear_surfaces()
	_rein_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var upw: Vector3 = horse.global_transform.basis.y
	for s: float in [-1.0, 1.0]:
		var L := "Left" if s < 0 else "Right"
		var bit := horse_point(Vector3(BIT.x * s, BIT.y, BIT.z), "head")
		var hand_bone: int = _b[L + "Hand"]
		var hand := sk.global_transform * (sk.get_bone_global_pose(hand_bone) * Vector3(0.0, 0.07, 0.02))
		var mid := (bit + hand) * 0.5 - upw * (0.05 + 0.03 * bit.distance_to(hand))
		var prev_ring := PackedVector3Array()
		var n := 16
		for i in n + 1:
			var t := float(i) / n
			var p := bit.lerp(mid, t).lerp(mid.lerp(hand, t), t)
			var p2 := bit.lerp(mid, minf(t + 0.02, 1.0)).lerp(mid.lerp(hand, minf(t + 0.02, 1.0)), minf(t + 0.02, 1.0))
			var tan := (p2 - p).normalized() if i < n else (hand - mid).normalized()
			var a := tan.cross(upw).normalized() * 0.008
			var b := tan.cross(a).normalized() * 0.003
			var ring := PackedVector3Array([p + a + b, p - a + b, p - a - b, p + a - b])
			if prev_ring.size() == 4:
				for k in 4:
					var k2 := (k + 1) % 4
					var nrm := ((ring[k] + ring[k2]) * 0.5 - p).normalized()
					for v in [prev_ring[k], prev_ring[k2], ring[k2], prev_ring[k], ring[k2], ring[k]]:
						_rein_mesh.surface_set_normal(nrm)
						_rein_mesh.surface_add_vertex(v)
			prev_ring = ring
	_rein_mesh.surface_end()

# ---------------------------------------------------------------------------------------------------------------
# Cloth: the rider's garment spring chains (duster / coat tails) collide with the horse's barrel and the saddle.
func _setup_cloth_collision(sk: Skeleton3D) -> void:
	for c in sk.get_children():
		if c is SpringBoneSimulator3D:
			_springs = c
	if _springs == null:
		return
	_barrel = SpringBoneCollisionCapsule3D.new()
	_barrel.name = "HorseBarrel"
	_barrel.radius = 0.36
	_barrel.height = 1.5
	_springs.add_child(_barrel)
	_cantle = SpringBoneCollisionSphere3D.new()
	_cantle.name = "SaddleCantle"
	_cantle.radius = 0.17
	_springs.add_child(_cantle)
	_update_cloth_collision(1.0)

func _update_cloth_collision(m := 1.0) -> void:
	if _barrel == null or not is_instance_valid(_barrel):
		return
	var hb: Basis = horse.global_transform.basis
	var c := horse_point(Vector3(0.0, 1.28, -0.05))
	if m < 0.8:                       # mounting / dismounting beside the horse: the barrel would grab the coat
		c += Vector3(0.0, -50.0, 0.0)
	# capsule axis (local Y) along the horse's body
	_barrel.global_transform = Transform3D(Basis(hb.x, -hb.z, hb.y).orthonormalized(), c)
	_cantle.global_transform = Transform3D(Basis.IDENTITY, horse_point(Vector3(0.0, 1.62, 0.12)))
