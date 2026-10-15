class_name PoseOverride
extends SkeletonModifier3D
## Procedural full-body poses layered over whatever the AnimationTree plays (FrontierCharacter.set_pose):
##   "hands_up"  surrender: both arms raised, palms out (hold-ups, a gun levelled at a bystander)
##   "cower"     arms wrapped over the head, chest folded forward (pairs with the idle_crouch activity)
##   "slump"     passed out: head and chest sagging forward, arms hanging (drunk asleep on a bench)
##   "play"      at the piano: forearms forward, hands on the keys (seated)
##   "read"      a newspaper held open in front of the chest;  "cards"  a hand of cards over the table
## Arm chains are aimed in skeleton space (direction from bone to child -> target direction), so the poses fit every
## generated body without authored clips; `amount` blends in/out over ~0.3 s.

var mode := ""
var amount := 0.0
var target := 0.0
var _bones := {}
var _fwd := Vector3(0, 0, 1)
var _right := Vector3(1, 0, 0)
var _ready_bones := false
var _t := 0.0

func set_mode(m: String) -> void:
	if m == "":
		target = 0.0
		return
	mode = m
	target = 1.0

func _setup_bones(sk: Skeleton3D) -> void:
	_ready_bones = true
	for n in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
			"RightUpperArm", "RightLowerArm", "RightHand", "LeftFoot", "LeftToes"]:
		_bones[n] = sk.find_bone(n)
	# body frame from the rest pose: forward = foot -> toes, right = left shoulder -> right shoulder
	if _bones.LeftFoot >= 0 and _bones.LeftToes >= 0:
		var f := sk.get_bone_global_rest(_bones.LeftToes).origin - sk.get_bone_global_rest(_bones.LeftFoot).origin
		f.y = 0.0
		if f.length() > 0.001:
			_fwd = f.normalized()
	if _bones.LeftUpperArm >= 0 and _bones.RightUpperArm >= 0:
		var r := sk.get_bone_global_rest(_bones.RightUpperArm).origin - sk.get_bone_global_rest(_bones.LeftUpperArm).origin
		r.y = 0.0
		if r.length() > 0.001:
			_right = r.normalized()

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if not _ready_bones:
		_setup_bones(sk)
	var dt := 1.0 / 60.0
	amount = move_toward(amount, target, dt * 3.5)
	if amount <= 0.001:
		return
	_t += dt
	var up := Vector3.UP
	var f := _fwd
	var r := _right
	match mode:
		"hands_up":
			for side: float in [-1.0, 1.0]:
				var s := "Right" if side > 0.0 else "Left"
				_aim_chain(sk, s, (up * 0.8 + r * side * 0.55 + f * 0.1).normalized(),
					(up + r * side * 0.12 - f * 0.05).normalized())
		"cower":
			_bend(sk, "Chest", f, 0.45)
			_bend(sk, "Neck", f, 0.5)
			for side: float in [-1.0, 1.0]:
				var s := "Right" if side > 0.0 else "Left"
				_aim_chain(sk, s, (f * 0.75 + up * 0.55 + r * side * 0.2).normalized(),
					(up * 0.55 - r * side * 0.75 - f * 0.2).normalized())
		"slump":
			_bend(sk, "Spine", f, 0.3)
			_bend(sk, "Chest", f, 0.25)
			_bend(sk, "Neck", f, 0.55)
			_bend(sk, "Head", r * 0.0 + f, 0.25)
			for side: float in [-1.0, 1.0]:
				var s := "Right" if side > 0.0 else "Left"
				_aim_chain(sk, s, (-up + f * 0.35 + r * side * 0.15).normalized(), (-up + f * 0.25).normalized())
		"read", "cards":
			# forearms raised in front of the chest (a newspaper held open, a hand of cards over the table)
			var hi := 0.55 if mode == "read" else 0.15
			for side: float in [-1.0, 1.0]:
				var s := "Right" if side > 0.0 else "Left"
				_aim_chain(sk, s, (-up * 0.9 + f * 0.35 + r * side * 0.15).normalized(),
					(f + up * hi - r * side * 0.35).normalized())
			_bend(sk, "Neck", f, 0.2)
		"play":
			for side: float in [-1.0, 1.0]:
				var s := "Right" if side > 0.0 else "Left"
				var wob := sin(_t * (6.0 + side) + side) * 0.06
				_aim_chain(sk, s, (-up * 0.85 + f * 0.45 + r * side * 0.12).normalized(),
					(f + up * (0.05 + wob) - r * side * 0.15).normalized())

## Tilt one bone so its child moves towards `toward` by `ang` radians (spine/neck bends).
func _bend(sk: Skeleton3D, bone: String, toward: Vector3, ang: float) -> void:
	var b: int = _bones.get(bone, -1)
	if b < 0:
		return
	var g := sk.get_bone_global_pose(b)
	var axis := Vector3.UP.cross(toward).normalized()
	if axis.length() < 0.5:
		return
	var q := Quaternion(axis, ang * amount)
	_set_global_basis(sk, b, Basis(q) * g.basis)

## Aim upper arm then forearm along the given skeleton-space directions.
func _aim_chain(sk: Skeleton3D, side: String, upper_dir: Vector3, lower_dir: Vector3) -> void:
	var ua: int = _bones.get(side + "UpperArm", -1)
	var la: int = _bones.get(side + "LowerArm", -1)
	var hd: int = _bones.get(side + "Hand", -1)
	if ua < 0 or la < 0 or hd < 0:
		return
	var g_ua := sk.get_bone_global_pose(ua)
	var g_la := sk.get_bone_global_pose(la)
	var new_ua := _aim(g_ua, g_la.origin, upper_dir)
	_set_global_basis(sk, ua, new_ua.basis)
	# forearm: its global pose follows the new upper arm
	var l_la := sk.get_bone_pose(la)
	var g_la2 := new_ua * l_la
	var g_hd := g_la2 * sk.get_bone_pose(hd)
	var new_la := _aim(g_la2, g_hd.origin, lower_dir)
	_set_local_from_global(sk, la, new_ua, new_la.basis)

func _aim(g: Transform3D, child_origin: Vector3, want: Vector3) -> Transform3D:
	var cur := child_origin - g.origin
	if cur.length() < 1e-5:
		return g
	var q := Quaternion(cur.normalized(), want.normalized())
	q = Quaternion.IDENTITY.slerp(q, amount)
	return Transform3D(Basis(q) * g.basis, g.origin)

func _set_global_basis(sk: Skeleton3D, b: int, gb: Basis) -> void:
	var p := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(p) if p >= 0 else Transform3D.IDENTITY
	_set_local_from_global(sk, b, pg, gb)

func _set_local_from_global(sk: Skeleton3D, b: int, parent_global: Transform3D, gb: Basis) -> void:
	var local := parent_global.basis.inverse() * gb
	sk.set_bone_pose_rotation(b, local.get_rotation_quaternion())
