class_name CharacterLook
extends SkeletonModifier3D
## Procedural gaze layer applied after animation: turns Neck/Head part of the way and aims LeftEye/RightEye fully at
## a target (world position or node), with angle limits and smoothing. Added by FrontierCharacter.setup().

var enabled := false
var target_position := Vector3.ZERO
var target_node: Node3D
var head_weight := 0.6
var max_head_angle := deg_to_rad(65.0)
var max_eye_angle := deg_to_rad(28.0)
var speed := 8.0

var _blend := 0.0
var _smoothed := Vector3.ZERO
var _has_smoothed := false


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	_blend = move_toward(_blend, 1.0 if enabled else 0.0, delta * 4.0)
	if _blend <= 0.001:
		_has_smoothed = false
		return
	var world_t := target_node.global_position if is_instance_valid(target_node) else target_position
	var t := skel.global_transform.affine_inverse() * world_t
	if not _has_smoothed:
		_smoothed = t
		_has_smoothed = true
	_smoothed = _smoothed.lerp(t, 1.0 - exp(-speed * delta))
	var neck := skel.find_bone("Neck")
	var head := skel.find_bone("Head")
	if neck >= 0:
		_aim(skel, neck, _smoothed, max_head_angle * 0.4, head_weight * 0.35 * _blend)
	if head >= 0:
		_aim(skel, head, _smoothed, max_head_angle * 0.7, head_weight * 0.75 * _blend)
	for e in ["LeftEye", "RightEye"]:
		var b := skel.find_bone(e)
		if b >= 0:
			_aim(skel, b, _smoothed, max_eye_angle, _blend)


func _aim(skel: Skeleton3D, bone: int, target: Vector3, max_angle: float, weight: float) -> void:
	var gp := skel.get_bone_global_pose(bone)
	var rest := skel.get_bone_global_rest(bone)
	var local_fwd := rest.basis.inverse() * Vector3(0, 0, 1)   # model faces +Z in skeleton space
	var fwd := (gp.basis * local_fwd).normalized()
	var to := target - gp.origin
	if to.length_squared() < 1e-6:
		return
	to = to.normalized()
	var axis := fwd.cross(to)
	if axis.length_squared() < 1e-10:
		return
	var ang := minf(fwd.angle_to(to), max_angle) * weight
	var q := Quaternion(axis.normalized(), ang)
	var new_global := Transform3D(Basis(q) * gp.basis, gp.origin)
	var parent := skel.get_bone_parent(bone)
	var pg := skel.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var local := pg.affine_inverse() * new_global
	skel.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
