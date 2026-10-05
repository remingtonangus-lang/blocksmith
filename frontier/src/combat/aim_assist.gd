class_name AimAssist
extends RefCounted
## Third-person aim assist (settings > Accessibility > Aim assist; controller-only by default):
## - snap: raising the gun turns the camera onto the best target inside a 9 degree cone (hostiles first),
## - slowdown: look speed drops while the crosshair sits on a target,
## - tracking: a gentle pull keeps the crosshair on a target that moves while it is already close.
## Line of sight is checked against the world, so nothing behind walls or hills is ever picked.

const SNAP_CONE := deg_to_rad(9.0)
const STICKY_CONE := deg_to_rad(3.0)
const TRACK_CONE := deg_to_rad(4.5)
const MAX_DIST := 90.0

static func _aim_point(n: Node3D) -> Vector3:
	if n.has_method("aim_point"):
		return n.aim_point()
	if n.is_in_group("humans"):
		var crouch: bool = n.get("intent") is Dictionary and n.intent.get("crouch", false)
		return n.global_position + Vector3(0, 1.0 if crouch else 1.3, 0)
	return n.global_position + Vector3(0, 0.6, 0)

static func _hostile(n: Node, player: Node) -> bool:
	var b = n.get("brain")
	if b == null or not is_instance_valid(b):
		return n.is_in_group("predator")
	if b.get("target") == player:
		return true
	return b.has_method("is_hostile_to") and b.is_hostile_to(player)

static func _forward(p) -> Vector3:
	return (Basis(Vector3.UP, p.cam_yaw) * Basis(Vector3.RIGHT, p.cam_pitch)) * Vector3.FORWARD

## Best target and its aim point within `cone` of the camera direction, or {} when none.
static func pick(p, cone: float) -> Dictionary:
	var cam: Camera3D = p.camera
	if cam == null:
		return {}
	var origin := cam.global_position
	var fwd := _forward(p)
	var best := {}
	var best_score := INF
	for g in ["humans", "animals"]:
		for n in p.get_tree().get_nodes_in_group(g):
			if n == p or not is_instance_valid(n) or not n.get("alive"):
				continue
			var pt := _aim_point(n)
			var d := pt - origin
			var dist := d.length()
			if dist < 1.0 or dist > MAX_DIST:
				continue
			var ang := fwd.angle_to(d / dist)
			if ang > cone:
				continue
			var score := ang + (0.0 if _hostile(n, p) else 0.06) + dist * 0.0004
			if score < best_score:
				best_score = score
				best = {"node": n, "point": pt, "angle": ang}
	if best.is_empty():
		return {}
	var q := PhysicsRayQueryParameters3D.create(origin, best.point)
	q.exclude = [p.get_rid()]
	q.collision_mask = 1
	if not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return {}
	return best

static func _face(p, point: Vector3, amount: float) -> void:
	var d: Vector3 = point - p.camera.global_position
	var want_yaw := atan2(-d.x, -d.z)
	var want_pitch := asin(clampf(d.y / maxf(d.length(), 0.001), -1.0, 1.0))
	p.cam_yaw += wrapf(want_yaw - p.cam_yaw, -PI, PI) * amount
	p.cam_pitch = clampf(lerpf(p.cam_pitch, want_pitch, amount), -1.2, 0.9)

## Called on the frame aiming starts.
static func snap(p) -> bool:
	var t := pick(p, SNAP_CONE)
	if t.is_empty():
		return false
	_face(p, t.point, 1.0)
	return true

## Look-speed multiplier while aiming (1 = no assist).
static func slow_factor(p) -> float:
	var t := pick(p, STICKY_CONE)
	return 1.0 if t.is_empty() else 0.45

## Per-frame pull toward a nearby moving target while aiming.
static func track(p, dt: float) -> void:
	var t := pick(p, TRACK_CONE)
	if t.is_empty():
		return
	# only a moving target pulls: a still one leaves the player free to pick the head or a limb
	var v = t.node.get("velocity")
	if v is Vector3 and Vector2(v.x, v.z).length() > 0.8:
		_face(p, t.point, 1.0 - exp(-3.0 * dt))
