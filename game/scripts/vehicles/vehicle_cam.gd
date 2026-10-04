class_name VehicleCam
extends Camera3D
## Third-person vehicle camera: orbits a target with mouse / right stick (Controls look curve), keeps a
## distance with a spring arm that pulls in against terrain and walls, and leans into speed. Vehicles read
## `aim_dir()` to point their guns and, Halo-style, to steer toward where the camera looks.

var target: Node3D
var distance := 14.0
var height := 4.0
var yaw := 0.0
var pitch := -0.15
var _dist := 14.0
var exclude: Array[RID] = []
var min_pitch := -1.2
var max_pitch := 0.75


func attach(t: Node3D, dist: float, h: float, excl: Array[RID]) -> void:
	target = t
	distance = dist
	_dist = dist
	height = h
	exclude = excl
	yaw = t.global_rotation.y
	pitch = -0.12
	far = 160000.0
	near = 0.2
	fov = Settings.fov
	make_current()
	G.cam = self


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and current:
		var s := Settings.mouse_sensitivity * 0.01
		yaw -= event.relative.x * s
		pitch = clampf(pitch - event.relative.y * s * (-1.0 if Settings.invert_y else 1.0), min_pitch, max_pitch)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not current:
		return
	var look := Controls.look_delta(delta, Input.is_action_pressed("aim"))
	yaw -= look.x
	pitch = clampf(pitch - look.y, min_pitch, max_pitch)
	var pivot := target.global_position + Vector3(0, height, 0)
	var dir := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, 1)
	var want := distance * (0.6 if Input.is_action_pressed("aim") else 1.0)
	# Spring arm: ray from the pivot toward the camera.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pivot, pivot + dir * want)
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	var d := want
	if not hit.is_empty():
		d = maxf(1.5, pivot.distance_to(hit["position"]) - 0.6)
	_dist = lerpf(_dist, d, 1.0 - exp(-delta * (20.0 if d < _dist else 4.0)))
	var p := pivot + dir * _dist
	var g := G.world.ground_at(p.x, p.z) if G.world else -1e9
	p.y = maxf(p.y, g + 1.0)
	global_position = p
	look_at(pivot + (-dir) * 30.0, Vector3.UP)
	if G.fx and G.fx.shake > 0.0:
		rotation += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * G.fx.shake * 0.01


## Where the camera looks: guns aim here and Halo-style steering heads here.
func aim_dir() -> Vector3:
	return -global_transform.basis.z


## A world point under the crosshair (ray to 3 km), for turret aiming.
func aim_point(excl: Array[RID]) -> Vector3:
	var o := global_position
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(o, o + aim_dir() * 3000.0)
	q.exclude = excl
	var hit := space.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else o + aim_dir() * 3000.0
