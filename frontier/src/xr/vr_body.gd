class_name VRBody
extends GunHands
## The player's own FrontierCharacter body in VR, posed after the animation each frame (a SkeletonModifier3D, so it
## reuses GunHands' rig measurements, two-bone arm IK and bone orienting):
## - head and neck follow the HMD (the neck takes half the turn), the chest leans a little with the head pitch;
## - each arm reaches its controller by two-bone IK: the wrist sits behind the fist (grip pose) and the hand's
##   anatomical frame matches the controller's aim frame, so the character's own hand closes round the held gun;
## - fingers curl from the controller (grip: middle/ring/little, trigger: index, thumb touch), or wrap the grip of a
##   held gun with the index on the trigger (GunHands' curl tables);
## - the head, hair and hat only cast shadows, so looking down shows the body from the neck down while shadows and
##   mirrors keep the whole person. VR (vr.gd) keeps the eyes a few cm behind the camera so the collar never clips.

const FIST_CURL := {"Index": [72.0, 88.0, 48.0], "Middle": [80.0, 95.0, 50.0], "Ring": [80.0, 95.0, 50.0],
	"Little": [80.0, 95.0, 50.0], "Thumb": [42.0, 26.0]}
const HIDE_WORDS := ["head", "hair", "hat", "beard", "brow", "lash", "eye", "teeth", "tongue", "mustache", "face"]

var vr: Node                       # VR rig (vr.gd)
var driving := false
var head_xf := Transform3D.IDENTITY             # world camera transform
var hand_xf := {"Right": Transform3D.IDENTITY, "Left": Transform3D.IDENTITY}   # world aim frames at the fists
var hand_on := {"Right": false, "Left": false}
var inputs := {"Right": {}, "Left": {}}         # grip, trigger, thumb, holding, support
var eye_height := 1.6                           # skeleton-space eye height at rest (for height calibration)
var eye_forward := 0.1                          # skeleton-space eye offset in front of the root
var head_run := 0
var mod_hips := Vector3.ZERO                    # debug: hips as seen during the modification stage
var _neck_to_eye := Vector3(0, 0.15, 0.1)       # skeleton space, rest pose

func setup_vr(sk: Skeleton3D, rig_vr: Node, character_id := "default") -> bool:
	vr = rig_vr
	if not setup(sk, character_id):
		return false
	var e: int = _b.get("RightEye", -1)
	var ep := sk.get_bone_global_rest(e if e >= 0 else _b["Head"]).origin
	if e < 0:
		ep += Vector3(0, 0.07, 0.09)
	var sc := sk.global_transform.basis.get_scale()   # skeletons may be imported scaled (cm rigs)
	eye_height = ep.y * sc.y
	eye_forward = ep.z * sc.z
	_neck_to_eye = ep - sk.get_bone_global_rest(_b["Neck"]).origin
	return true

## The eyes as the current (animated) pose carries them: the neck's position plus the rest neck->eye offset.
## Mounted, the rider animation puts the body on the saddle, so the camera follows this instead of the rest pose.
func posed_eye(push := 0.0) -> Vector3:
	var sk := get_skeleton()
	var n := sk.get_bone_global_pose(_b["Neck"]).origin
	return sk.global_transform * (n + _neck_to_eye + Vector3(0, 0, push))

## Head-ish meshes cast shadows only (the camera sits in the head); everything else draws normally. show=true puts
## the head back (third-person evidence shots, spectator views).
static func hide_head(visual: Node, show := false) -> void:
	for mi in visual.find_children("*", "GeometryInstance3D", true, false):
		var g := mi as GeometryInstance3D
		var n := String(g.name).to_lower()
		var head := false
		for w in HIDE_WORDS:
			if n.contains(w):
				head = true
				break
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if head and not show else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _process_modification() -> void:
	runs += 1
	var sk := get_skeleton()
	if not ok or sk == null or not driving:
		return
	head_run += 1
	var gt := sk.global_transform
	mod_hips = (gt * sk.get_bone_global_pose(GunHands.bone_index(sk, "Hips"))).origin
	var inv := gt.affine_inverse()
	var fwd := body * Vector3(0, 0, -1)
	# ---- head, neck, a little chest
	var hf := -head_xf.basis.z.normalized()
	var hu := head_xf.basis.y.normalized()
	var flat := Vector3(hf.x, 0, hf.z)
	if flat.length() < 0.05:
		flat = fwd
	flat = flat.normalized()
	var pitch := asin(clampf(hf.y, -0.95, 0.95))
	var right_h := flat.cross(Vector3.UP).normalized()
	var chest := Basis(right_h, clampf(pitch, -0.6, 0.3) * 0.35)
	_orient(sk, _b["UpperChest"], chest * fwd, chest * Vector3.UP, 1.0, gt, inv)
	var neck_f := (hf + fwd).normalized() if (hf + fwd).length() > 0.1 else hf
	_orient(sk, _b["Neck"], neck_f, (hu + Vector3.UP).normalized(), 1.0, gt, inv)
	_orient(sk, _b["Head"], hf, hu, 1.0, gt, inv)
	# ---- arms to the controllers (solved in the skeleton's readable pose: mounted, that sits off the drawn body by
	# WeaponHolder.mount_offset(), so the targets are shifted into it)
	var moff := Vector3.ZERO
	var holder = vr.player.get("holder") if vr != null and vr.player != null else null
	if holder != null and holder.has_method("mount_offset"):
		moff = holder.mount_offset()
	var r: Dictionary = RIGS[rig]
	for side in SIDES:
		if not hand_on[side]:
			continue
		var t: Transform3D = hand_xf[side]
		var mir := 1.0 if side == "Right" else -1.0
		var kr: Dictionary = r.pistol_r
		var off: Vector3 = kr.off
		off.x *= mir
		var b := t.basis.orthonormalized()
		var wrist := t.origin + b * off - moff
		var frame := b * _frame(kr.f, kr.s)
		var sh := _bone_world(side + "UpperArm")
		var pole := sh + body * Vector3(0.35 * mir, -0.6, 0.25)   # (sh is read-pose: already in the shifted space)
		_arm(sk, gt, inv, side, wrist, frame, pole, 1.0)
	# ---- fingers
	for bi in _curl:
		var c: Array = _curl[bi]
		var side2: String = c[4]
		if not hand_on[side2]:
			continue
		var inp: Dictionary = inputs[side2]
		var fn: String = c[2]
		var deg := 0.0
		var k := mini(int(c[3]), 2)
		if inp.get("holding", false):
			var table: Dictionary = r.curl if side2 == "Right" else r.curl_support
			var a: Array = table.get(fn, [0.0, 0.0, 0.0])
			deg = float(a[mini(k, a.size() - 1)])
			if fn == "Index" and side2 == "Right":
				deg *= lerpf(0.85, 1.25, float(inp.get("trigger", 0.0)))   # squeeze on the trigger
		else:
			var amt: float
			match fn:
				"Index": amt = float(inp.get("trigger", 0.0)) * 0.9
				"Thumb": amt = maxf(float(inp.get("thumb", 0.0)), float(inp.get("grip", 0.0)) * 0.6)
				_: amt = float(inp.get("grip", 0.0))
			var f: Array = FIST_CURL.get(fn, [0.0, 0.0, 0.0])
			deg = float(f[mini(k, f.size() - 1)]) * amt
		var target := sk.get_bone_rest(bi).basis.get_rotation_quaternion() * Quaternion(c[0], deg_to_rad(deg) * float(c[1]))
		sk.set_bone_pose_rotation(bi, target)
