class_name GunHands
extends SkeletonModifier3D
## Shooter pose on a FrontierCharacter (Godot humanoid skeleton), applied after the animation each frame:
## 1. spine twist + pitch up the spine toward the aim (with a bladed stance for long guns), neck/head turned onto the
##    aim line (cheek tilted onto the comb for long guns);
## 2. while aiming, the gun itself is placed so its sight line runs through the right eye along the aim ray: a pistol
##    at arm's length (rear sight ~0.5 m from the eye), a long gun with the eye over the comb (butt in the shoulder);
## 3. analytic two-bone IK per arm (elbow poles per stance) to wrist targets on the gun's grip_r / grip_l markers,
##    then the hand ROTATION solved so the palm wraps the grip: each hand's anatomical frame (wrist->middle knuckle,
##    little->index knuckle) measured from the rest pose is matched to a per-stance frame in gun space;
## 4. a grip pose over the finger bones (wrapped fingers, index curled on the trigger, thumb over), applied on top of
##    the clip.
## Grip targets follow the moving parts (lever loop, pump, break-open fore-end) and switch for reloads and cycling
## (hand to the loading gate, bolt knob, breech). WeaponHolder sets the state fields every frame.
## Per-rig tuning: RIGS[rig] (wrist offsets and hand frames in gun space, finger curls, poles).

const SIDES := ["Right", "Left"]
const FINGERS := ["Index", "Middle", "Ring", "Little"]
const PH := ["Proximal", "Intermediate", "Distal"]
const RIGS := {
	"default": {
		# wrist offset from the grip point (gun space: -Z forward, +Y up, +X right), hand frame f/s in gun space
		"pistol_r": {"off": Vector3(0.020, 0.018, 0.050), "f": Vector3(0.0, 0.12, -1.0), "s": Vector3(0, 1, 0)},
		"pistol_l": {"off": Vector3(-0.040, -0.058, 0.058), "f": Vector3(0.45, 0.05, -1.0), "s": Vector3(0, 1, 0.15)},
		"rifle_r": {"off": Vector3(0.026, -0.030, 0.052), "f": Vector3(0.0, -0.45, -1.0), "s": Vector3(0, 1, -0.3)},
		"rifle_l": {"off": Vector3(-0.042, -0.040, 0.040), "f": Vector3(0.9, 0.15, -0.5), "s": Vector3(0.3, 0, -1)},
		"gate": {"off": Vector3(0.05, -0.02, 0.06), "f": Vector3(-0.4, 0.2, -1.0), "s": Vector3(0, 1, 0)},
		"knob": {"off": Vector3(0.02, 0.0, 0.07), "f": Vector3(0.0, -0.2, -1.0), "s": Vector3(0, 1, 0)},
		"curl": {"Index": [32.0, 42.0, 22.0], "Middle": [70.0, 85.0, 45.0], "Ring": [75.0, 85.0, 45.0],
			"Little": [78.0, 85.0, 45.0], "Thumb": [40.0, 20.0]},
		"curl_support": {"Index": [55.0, 65.0, 35.0], "Middle": [60.0, 70.0, 40.0], "Ring": [62.0, 70.0, 40.0],
			"Little": [64.0, 70.0, 40.0], "Thumb": [30.0, 15.0]},
	},
}
## Gun-local bolt knob positions (Godot space, relative to the bolt node) for the hand while cycling.
const BOLT_KNOB := {"bowden_bolt": Vector3(0.042, -0.0185, 0.062), "pellman_varmint": Vector3(0.029, -0.003, 0.017)}

# ---- state written by WeaponHolder every frame
var model: WeaponModel
var mode := ""                    # "" (off), "aim", "ready", "reload"
var weight := 0.0                 # overall blend (draw/holster)
var aim_dir := Vector3.FORWARD    # world, normalized
var body := Basis.IDENTITY        # body yaw basis (forward -Z)
var pistol := true
var place_gun := true
var two_hand_pistol := true
var rig := "default"

var ok := false
var _b := {}                      # name -> bone index
var _o := {}                      # side -> Basis: hand bone basis relative to its anatomical frame (rest)
var _len := {}                    # side -> [upper, lower]
var _curl := {}                   # bone index -> [axis_local, sign]
var _head_fwd := Vector3.FORWARD  # head-bone-local forward (rest)
var _fwd_l := {}                  # bone index -> [local forward, local up] at rest (character faces +Z, up +Y)
var _w_r := 0.0
var _w_l := 0.0

func setup(sk: Skeleton3D, rig_name := "default") -> bool:
	rig = rig_name if RIGS.has(rig_name) else "default"
	for n in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "RightUpperArm", "RightLowerArm", "RightHand",
			"LeftUpperArm", "LeftLowerArm", "LeftHand"]:
		var i := bone_index(sk, n)
		if i < 0:
			var names := []
			for k in sk.get_bone_count():
				names.append(sk.get_bone_name(k))
			push_warning("GunHands: skeleton has no bone %s (%s)" % [n, ",".join(names)])
			return false
		_b[n] = i
	for n in ["RightEye", "LeftEye"]:
		_b[n] = bone_index(sk, n)
	var rest := func(n: String) -> Transform3D: return sk.get_bone_global_rest(_b[n] if _b.has(n) else bone_index(sk, n))
	# characters face +Z in skeleton space (the glTF convention)
	_head_fwd = (rest.call("Head") as Transform3D).basis.inverse() * Vector3(0, 0, 1)
	for n in ["Spine", "Chest", "UpperChest", "Neck", "Head"]:
		var rb := (rest.call(n) as Transform3D).basis.orthonormalized().inverse()
		_fwd_l[_b[n]] = [(rb * Vector3(0, 0, 1)).normalized(), (rb * Vector3(0, 1, 0)).normalized()]
	for side in SIDES:
		var up: Transform3D = rest.call(side + "UpperArm")
		var lo: Transform3D = rest.call(side + "LowerArm")
		var ha: Transform3D = rest.call(side + "Hand")
		_len[side] = [up.origin.distance_to(lo.origin), lo.origin.distance_to(ha.origin)]
		var a := _anat(sk, side, true)
		_o[side] = a.inverse() * ha.basis.orthonormalized()
		# finger curl axes: across the palm, curling toward the palm side (sign from the rest bend of the fingers)
		var f := a.y
		var s := a.x
		var bend := Vector3.ZERO
		for fn in FINGERS:
			var i0 := sk.find_bone(side + fn + "Proximal")
			var i1 := sk.find_bone(side + fn + "Intermediate")
			var i2 := sk.find_bone(side + fn + "Distal")
			if i0 >= 0 and i1 >= 0 and i2 >= 0:
				var p0 := sk.get_bone_global_rest(i0).origin
				var p1 := sk.get_bone_global_rest(i1).origin
				var p2 := sk.get_bone_global_rest(i2).origin
				bend += (p2 - p1).normalized() - (p1 - p0).normalized()
		# frame z = s x f is the palm side of a right hand and the back of a left hand (mirror), and +angle about s
		# moves f toward z, so right fingers curl with +angle, left with -angle
		var palm_sign := 1.0 if side == "Right" else -1.0
		for fn in FINGERS:
			for ph in PH:
				var bi := sk.find_bone(side + fn + ph)
				if bi >= 0:
					_curl[bi] = [(sk.get_bone_global_rest(bi).basis.orthonormalized().inverse() * s).normalized(), palm_sign, fn,
						PH.find(ph), side]
		for ph in ["Proximal", "Distal"]:
			var ti := sk.find_bone(side + "Thumb" + ph)
			if ti >= 0:
				# thumb swings from the index side toward the fingers' direction (about the palm normal z = s x f)
				_curl[ti] = [(sk.get_bone_global_rest(ti).basis.orthonormalized().inverse() * a.z).normalized(),
					1.0, "Thumb", 0 if ph == "Proximal" else 1, side]
	ok = true
	return true

## Bone lookup tolerant of the importer's de-duplication suffixes ("Head" becomes "Head_2" when a mesh node is
## also called Head).
static func bone_index(sk: Skeleton3D, n: String) -> int:
	var i := sk.find_bone(n)
	if i >= 0:
		return i
	for suf in ["_2", "_1", "_3", "_001"]:
		i = sk.find_bone(n + suf)
		if i >= 0:
			return i
	return -1

## Anatomical hand frame: x = little->index knuckles (across the palm), y = wrist->middle knuckle, z = x cross y.
func _anat(sk: Skeleton3D, side: String, use_rest: bool) -> Basis:
	var g := func(n: String) -> Vector3:
		var i := sk.find_bone(side + n)
		return (sk.get_bone_global_rest(i) if use_rest else sk.get_bone_global_pose(i)).origin
	var y: Vector3 = (g.call("MiddleProximal") - g.call("Hand")).normalized()
	var x: Vector3 = g.call("IndexProximal") - g.call("LittleProximal")
	x = (x - y * x.dot(y)).normalized()
	return Basis(x, y, x.cross(y))

static func _frame(f: Vector3, s: Vector3) -> Basis:
	var y := f.normalized()
	var x := s - y * s.dot(y)
	x = x.normalized()
	return Basis(x, y, x.cross(y))

# ------------------------------------------------------------------------------------------------- per frame
var runs := 0                     # debug: modification passes executed

func _process_modification() -> void:
	runs += 1
	var sk := get_skeleton()
	if not ok or sk == null or model == null or not is_instance_valid(model) or mode == "" or weight <= 0.001:
		_w_r = 0.0
		_w_l = 0.0
		return
	var gt := sk.global_transform
	var inv := gt.affine_inverse()
	var aiming := mode == "aim"
	# ---- 1. spine and head toward the aim
	var fwd := body * Vector3(0, 0, -1)
	var ah := Vector3(aim_dir.x, 0, aim_dir.z).normalized()
	var yaw := atan2(fwd.cross(ah).y, fwd.dot(ah)) if ah.length() > 0.1 else 0.0
	var pitch := asin(clampf(aim_dir.y, -0.95, 0.95))
	var stance := 0.0
	if aiming:
		stance = deg_to_rad(-30.0) if not pistol else deg_to_rad(-6.0)
	else:
		pitch *= 0.3
		stance = deg_to_rad(-12.0) if not pistol else 0.0
	var right_h := ah.cross(Vector3.UP).normalized() if ah.length() > 0.1 else body.x
	# absolute orientations (idempotent even if the clip leaves a bone's pose untouched between frames)
	var spine := [["Spine", 0.25], ["Chest", 0.55], ["UpperChest", 1.0]]
	for e in spine:
		var bi: int = _b[e[0]]
		var c: float = e[1]
		var rot := Basis(Vector3.UP, (yaw + stance) * c) * Basis(right_h, pitch * c * 0.8)
		_orient(sk, bi, rot * fwd, rot * Vector3.UP, weight * 0.9, gt, inv)
	# head: face the aim line; long guns roll the cheek onto the comb
	var want := aim_dir if aiming else (body * Vector3(0, -0.25, -1)).normalized()
	var hup := Vector3.UP
	if aiming and not pistol:
		hup = Basis(want, deg_to_rad(-14.0)) * Vector3.UP
	var mid := (want + (Basis(Vector3.UP, yaw + stance) * fwd)).normalized()
	_orient(sk, _b["Neck"], mid, Vector3.UP, weight, gt, inv)
	_orient(sk, _b["Head"], want, hup, weight, gt, inv)
	# ---- 2. gun on the eye line
	if aiming and place_gun:
		var eye := _eye(sk, gt)
		var gb := Basis.looking_at(aim_dir, Vector3.UP)
		var sr := model.marker_local("sight_rear").origin
		var eye_local: Vector3
		if pistol:
			eye_local = Vector3(0, sr.y + 0.004, sr.z + 0.50)
		else:
			eye_local = Vector3(0, sr.y + 0.014, _butt_z(model) - 0.215)
		var want_x := Transform3D(gb, eye - gb * eye_local)
		# keep the grip within arm's reach: slide the gun back along the aim line if the wrist could not get there
		var kr0: Dictionary = (RIGS[rig] as Dictionary)["pistol_r" if pistol else "rifle_r"]
		var grip_l0 := model.marker_local("grip_r").origin + (kr0.off as Vector3)
		var wrist0 := want_x * grip_l0
		var reach: float = (_len["Right"][0] + _len["Right"][1]) * 0.96
		var over := wrist0.distance_to(_bone_world("RightUpperArm")) - reach
		if over > 0.0:
			want_x.origin -= aim_dir * over
		model.global_transform = model.global_transform.interpolate_with(want_x, weight)
	# ---- 3. arms + hands
	var gx := model.global_transform
	var r: Dictionary = RIGS[rig]
	var targets := _targets(gx, r, aiming)
	for side in SIDES:
		var t = targets.get(side)
		var w: float = 0.0 if t == null else float(t.w) * weight
		if side == "Right":
			_w_r = w
		else:
			_w_l = w
		if w <= 0.001:
			continue
		_arm(sk, gt, inv, side, t.pos, t.basis, t.pole, w)
	# ---- 4. fingers
	for bi in _curl:
		var c: Array = _curl[bi]
		var side: String = c[4]
		var w2 := _w_r if side == "Right" else _w_l
		if w2 <= 0.001:
			continue
		var table: Dictionary = r.curl if side == "Right" else r.curl_support
		var angs: Array = table.get(c[2], [0.0, 0.0, 0.0])
		var deg: float = angs[mini(int(c[3]), angs.size() - 1)]
		var pose := sk.get_bone_pose_rotation(bi)
		var target := sk.get_bone_rest(bi).basis.get_rotation_quaternion() * Quaternion(c[0], deg_to_rad(deg) * float(c[1]))
		sk.set_bone_pose_rotation(bi, pose.slerp(target, w2))

func _eye(sk: Skeleton3D, gt: Transform3D) -> Vector3:
	var e: int = _b.get("RightEye", -1)
	if e >= 0:
		return (gt * sk.get_bone_global_pose(e)).origin
	return (gt * sk.get_bone_global_pose(_b["Head"])).origin + body * Vector3(0.03, 0.07, -0.09)

static func _butt_z(m: WeaponModel) -> float:
	var z := 0.0
	for c in m.lod0.get_children():
		if c is MeshInstance3D:
			var bb: AABB = (c as MeshInstance3D).transform * (c as MeshInstance3D).get_aabb()
			z = maxf(z, bb.end.z)
	return z

## Wrist targets {pos, basis (hand anatomical frame, world), pole, w} for each side.
func _targets(gx: Transform3D, r: Dictionary, aiming: bool) -> Dictionary:
	var out := {}
	var gb := gx.basis.orthonormalized()
	var sh_r := _bone_world("RightUpperArm")
	var sh_l := _bone_world("LeftUpperArm")
	var grip_r := model.grip_transform("grip_r")
	var grip_l := model.grip_transform("grip_l")
	# parts that carry a hand with them
	if model.parts.has("lever"):
		grip_r = _follow(model.parts["lever"], grip_r)
	if not pistol:
		for pn in ["pump", "barrels"]:
			if model.parts.has(pn):
				grip_l = _follow(model.parts[pn], grip_l)
				break
	var kr: Dictionary = r.pistol_r if pistol else r.rifle_r
	var tr := {"pos": grip_r.origin + gb * (kr.off as Vector3), "basis": gb * _frame(kr.f, kr.s), "w": 1.0,
		"pole": sh_r + body * (Vector3(0.45, -0.25, 0.15) if (aiming and not pistol) else Vector3(0.3, -0.6, 0.2))}
	var tl = null
	if pistol:
		if (aiming and two_hand_pistol) or mode == "reload":
			var kl: Dictionary = r.pistol_l
			tl = {"pos": grip_r.origin + gb * (kl.off as Vector3), "basis": gb * _frame(kl.f, kl.s), "w": 1.0 if aiming else 0.0,
				"pole": sh_l + body * Vector3(-0.3, -0.55, 0.1)}
	else:
		var kl2: Dictionary = r.rifle_l
		tl = {"pos": grip_l.origin + gb * (kl2.off as Vector3), "basis": gb * _frame(kl2.f, kl2.s), "w": 1.0,
			"pole": sh_l + body * Vector3(-0.1, -0.7, 0.0)}
	# reloading / cycling: the free hand works the action
	var gate = model.parts.get("loading_gate")
	if mode == "reload" and gate != null:
		var gpos: Vector3 = (gate.node as Node3D).global_position
		var kg: Dictionary = r.gate
		var t := {"pos": gpos + gb * (kg.off as Vector3), "basis": gb * _frame(kg.f, kg.s), "w": 1.0,
			"pole": (sh_l if pistol else sh_r) + body * Vector3(0.0, -0.6, 0.1)}
		if pistol:
			t.basis = gb * _frame(Vector3(0.6, 0.2, -1.0), Vector3(0, 1, 0))
			t.pos = gpos + gb * Vector3(0.035, -0.03, 0.05)
			tl = t
		else:
			tr = t
	if model.parts.has("bolt") and BOLT_KNOB.has(model.weapon_id):
		var bv := float(model._ch.get("bolt", 0.0)) + float(model._ch.get("bolt_rot", 0.0))
		if bv > 0.01 or mode == "reload":
			var bn: Node3D = model.parts["bolt"].node
			var knob: Vector3 = bn.global_transform * (BOLT_KNOB[model.weapon_id] as Vector3)
			var kk: Dictionary = r.knob
			tr = {"pos": knob + gb * (kk.off as Vector3), "basis": gb * _frame(kk.f, kk.s), "w": 1.0, "pole": tr.pole}
	if mode == "reload" and model.parts.has("barrels") and not pistol:
		var se := model.marker("shell_eject")
		if se != null:
			tr = {"pos": se.global_position + gb * Vector3(0.03, -0.04, 0.08), "basis": tr.basis, "w": 1.0, "pole": tr.pole}
	out["Right"] = tr
	if tl != null:
		out["Left"] = tl
	return out

## A marker frame carried along by a moving part (rest-relative).
func _follow(part: Dictionary, x: Transform3D) -> Transform3D:
	var node: Node3D = part.node
	var parent := node.get_parent() as Node3D
	if parent == null:
		return x
	var rest_g: Transform3D = parent.global_transform * (part.rest as Transform3D)
	return node.global_transform * rest_g.affine_inverse() * x

func _bone_world(n: String) -> Vector3:
	var sk := get_skeleton()
	return (sk.global_transform * sk.get_bone_global_pose(_b[n])).origin

static func _arc(a: Vector3, b: Vector3) -> Basis:
	var an := a.normalized()
	var bn := b.normalized()
	var d := an.dot(bn)
	if d > 0.99999:
		return Basis.IDENTITY
	if d < -0.9999:
		var ax := an.cross(Vector3.UP)
		if ax.length() < 0.01:
			ax = an.cross(Vector3.RIGHT)
		return Basis(ax.normalized(), PI)
	return Basis(Quaternion(an, bn))

## Turn a bone (about its own origin) so its rest forward/up axes point along f/u in world space, blended by w.
func _orient(sk: Skeleton3D, bi: int, f: Vector3, u: Vector3, w: float, gt: Transform3D, inv: Transform3D) -> void:
	var fl: Array = _fwd_l[bi]
	var gb := (gt * sk.get_bone_global_pose(bi)).basis.orthonormalized()
	var cf := (gb * (fl[0] as Vector3)).normalized()
	var cu := (gb * (fl[1] as Vector3)).normalized()
	var C := _frame3(cf, cu)
	var D := _frame3(f.normalized(), u.normalized())
	var R := D * C.inverse()
	_rotate_global(sk, bi, Basis(Quaternion.IDENTITY.slerp(R.get_rotation_quaternion(), clampf(w, 0.0, 1.0))), gt, inv)

static func _frame3(f: Vector3, u: Vector3) -> Basis:
	var x := u.cross(f).normalized()
	var y := f.cross(x).normalized()
	return Basis(x, y, f)

## Rotate a bone in world space about its own origin (children follow).
func _rotate_global(sk: Skeleton3D, bi: int, rw: Basis, gt: Transform3D, inv: Transform3D) -> void:
	var cur := sk.get_bone_global_pose(bi)
	var rs := inv.basis * rw * gt.basis
	sk.set_bone_global_pose(bi, Transform3D((rs * cur.basis).orthonormalized().scaled(cur.basis.get_scale()), cur.origin))

func _arm(sk: Skeleton3D, gt: Transform3D, inv: Transform3D, side: String, wrist: Vector3, hand_frame: Basis, pole: Vector3, w: float) -> void:
	var iu: int = _b[side + "UpperArm"]
	var il: int = _b[side + "LowerArm"]
	var ih: int = _b[side + "Hand"]
	var a: float = _len[side][0]
	var b: float = _len[side][1]
	var S := (gt * sk.get_bone_global_pose(iu)).origin
	var d := wrist - S
	var L := clampf(d.length(), 0.05, (a + b) * 0.999)
	var dn := d.normalized()
	var cos_a := clampf((a * a + L * L - b * b) / (2.0 * a * L), -1.0, 1.0)
	var bend := pole - S
	bend = bend - dn * bend.dot(dn)
	if bend.length() < 0.001:
		bend = body * Vector3(0, -1, 0)
	bend = bend.normalized()
	var E := S + dn * (a * cos_a) + bend * (a * sqrt(maxf(1.0 - cos_a * cos_a, 0.0)))
	var Wc := S + dn * L
	# upper arm: point at the elbow
	var ug := gt * sk.get_bone_global_pose(iu)
	var lg := gt * sk.get_bone_global_pose(il)
	var r1 := _arc(lg.origin - ug.origin, E - S)
	_rotate_global(sk, iu, Basis(Quaternion.IDENTITY.slerp(r1.get_rotation_quaternion(), w)), gt, inv)
	# forearm: point at the wrist
	lg = gt * sk.get_bone_global_pose(il)
	var hg := gt * sk.get_bone_global_pose(ih)
	var r2 := _arc(hg.origin - lg.origin, Wc - lg.origin)
	_rotate_global(sk, il, Basis(Quaternion.IDENTITY.slerp(r2.get_rotation_quaternion(), w)), gt, inv)
	# hand: anatomical frame onto the grip frame
	var cur := sk.get_bone_global_pose(ih)
	var want := (inv.basis * hand_frame * (_o[side] as Basis)).orthonormalized()
	var q := cur.basis.orthonormalized().get_rotation_quaternion().slerp(want.get_rotation_quaternion(), w)
	sk.set_bone_global_pose(ih, Transform3D(Basis(q).scaled(cur.basis.get_scale()), cur.origin))
