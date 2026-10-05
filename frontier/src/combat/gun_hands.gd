class_name GunHands
extends Node3D
## Arm IK that puts a FrontierCharacter's hands on the gun: one TwoBoneIK3D per arm on the Godot-humanoid skeleton
## (UpperArm -> LowerArm -> Hand), targets at the weapon's grip_r / grip_l markers plus a per-rig wrist offset,
## poles keeping the elbows down and out. WeaponHolder drives it each frame: right hand while the gun is in hand,
## support hand for long guns and two-handed pistol aim; influences blend with the draw.
## Per-rig offsets: RIGS[rig] (gun-local wrist offsets from the grip markers, shoulder-local pole offsets).

const RIGS := {
	"default": {"grip_r": Vector3(0.0, -0.030, 0.062), "grip_l": Vector3(-0.012, -0.050, 0.030),
		"pole_r": Vector3(0.30, -0.42, 0.28), "pole_l": Vector3(-0.30, -0.45, 0.10),
		"long_l": Vector3(0.0, 0.0, 0.09)},     # long guns: support hand a little back along the fore-end (reach)
}

var skel: Skeleton3D
var rig := "default"
var ik_r: TwoBoneIK3D
var ik_l: TwoBoneIK3D
var t_r: Node3D
var t_l: Node3D
var p_r: Node3D
var p_l: Node3D
var ok := false

func setup(sk: Skeleton3D, rig_name := "default") -> bool:
	skel = sk
	rig = rig_name if RIGS.has(rig_name) else "default"
	for b in ["RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand"]:
		if sk.find_bone(b) < 0:
			return false
	t_r = _mk("TargetR")
	t_l = _mk("TargetL")
	p_r = _mk("PoleR")
	p_l = _mk("PoleL")
	ik_r = _ik("GunIK_R", "Right", t_r, p_r)
	ik_l = _ik("GunIK_L", "Left", t_l, p_l)
	ok = true
	return true

func _mk(n: String) -> Node3D:
	var t := Node3D.new()
	t.name = n
	t.top_level = true
	add_child(t)
	return t

func _ik(n: String, side: String, target: Node3D, pole: Node3D) -> TwoBoneIK3D:
	var ik := TwoBoneIK3D.new()
	ik.name = n
	skel.add_child(ik)
	ik.set_setting_count(1)
	ik.set_root_bone_name(0, side + "UpperArm")
	ik.set_middle_bone_name(0, side + "LowerArm")
	ik.set_end_bone_name(0, side + "Hand")
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.influence = 0.0
	return ik

func bone_global(n: String) -> Vector3:
	var i := skel.find_bone(n)
	return (skel.global_transform * skel.get_bone_global_pose(i)).origin if i >= 0 else skel.global_position

## Place the targets on the gun and set the arm weights (0..1).
func drive(m: WeaponModel, body: Basis, w_right: float, w_left: float) -> void:
	if not ok:
		return
	var r: Dictionary = RIGS[rig]
	if m != null:
		t_r.global_transform = m.grip_transform("grip_r") * Transform3D(Basis.IDENTITY, r.grip_r)
		var gl: Vector3 = r.grip_l
		if m.def.get("slot", "") != "sidearm":
			gl += r.get("long_l", Vector3.ZERO)
		t_l.global_transform = m.grip_transform("grip_l") * Transform3D(Basis.IDENTITY, gl)
	p_r.global_position = bone_global("RightUpperArm") + body * (r.pole_r as Vector3)
	p_l.global_position = bone_global("LeftUpperArm") + body * (r.pole_l as Vector3)
	ik_r.influence = clampf(w_right, 0.0, 1.0)
	ik_l.influence = clampf(w_left, 0.0, 1.0)

func clear() -> void:
	if ok:
		ik_r.influence = 0.0
		ik_l.influence = 0.0

func _exit_tree() -> void:
	for ik in [ik_r, ik_l]:
		if ik != null and is_instance_valid(ik):
			ik.queue_free()
