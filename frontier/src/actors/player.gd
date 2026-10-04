extends CharacterBody3D
## Ruth Caddell on foot: weighty third-person locomotion (walk / jog / sprint with stamina, acceleration and
## speed-dependent turn rates, slope slowdown, step-up, jumping), an over-the-shoulder orbit camera with collision,
## and an `intent` interface so bots drive exactly the same code path as a human (src/tests/bot_runner.gd).
## The visual body is a CharacterFactory character when available, else a simple stand-in.

signal mounted(horse: Node)
signal dismounted

const WALK := 1.55
const JOG := 3.7
const SPRINT := 6.6
const ACCEL := 7.0
const DECEL := 9.0
const GRAVITY := 9.81
const JUMP_V := 4.4
const STAMINA_MAX := 100.0

var camera: Camera3D
var cam_yaw := 0.0
var cam_pitch := -0.12
var cam_dist := 3.4
var cam_side := 0.55
var cam_shoulder := 1.0
var mouse_sens := 0.0025
var pad_sens := 2.6
var intent := {"move": Vector2.ZERO, "sprint": false, "walk": false, "jump": false, "aim": false, "fire": false,
	"interact": false, "crouch": false}
var bot_driven := false
var stamina := STAMINA_MAX
var health := 100.0
var speed := 0.0               # current planar speed (m/s)
var facing := 0.0              # body yaw (radians)
var on_horse: Node = null
var gait := "idle"
var visual: Node3D
var _cam_target := Vector3.ZERO
var _cam_cur_dist := 3.4
var _walk_mode := false
var _last_floor_y := 0.0
var _air_time := 0.0
var fall_damage_taken := 0.0

func setup(cam: Camera3D) -> void:
	camera = cam
	InputSetup.ensure()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.78
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.89
	add_child(cs)
	collision_layer = 2
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.45
	max_slides = 6
	_build_visual()
	cam_yaw = rotation.y
	facing = rotation.y
	_cam_target = global_position + Vector3(0, 1.6, 0)
	if not Game.headless and not bot_driven and not Game.args.has("bot") and not Game.args.has("benchmark"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_visual() -> void:
	var factory = load("res://src/actors/character_factory.gd") if ResourceLoader.exists("res://src/actors/character_factory.gd") else null
	if factory != null and factory.has_method("spawn_hero"):
		visual = factory.spawn_hero()
	if visual == null:
		visual = Node3D.new()
		var body := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.25
		cm.height = 1.5
		body.mesh = cm
		body.position.y = 0.8
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.36, 0.28, 0.22)
		mat.roughness = 0.85
		body.material_override = mat
		visual.add_child(body)
		var head := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		head.mesh = sm
		head.position.y = 1.66
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color(0.72, 0.55, 0.45)
		head.material_override = hm
		visual.add_child(head)
		var hat := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.2
		cyl.bottom_radius = 0.22
		cyl.height = 0.03
		hat.mesh = cyl
		hat.position.y = 1.76
		var hatm := StandardMaterial3D.new()
		hatm.albedo_color = Color(0.25, 0.2, 0.15)
		hat.material_override = hatm
		visual.add_child(hat)
	add_child(visual)

func _unhandled_input(event: InputEvent) -> void:
	if bot_driven:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * mouse_sens
		cam_pitch = clampf(cam_pitch - event.relative.y * mouse_sens, -1.2, 0.9)
	elif event.is_action_pressed("camera_side"):
		cam_shoulder = -cam_shoulder
	elif event.is_action_pressed("walk_toggle"):
		_walk_mode = not _walk_mode
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _read_human_intent(dt: float) -> void:
	var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	intent.move = Vector2(mv.x, -mv.y)
	intent.sprint = Input.is_action_pressed("sprint")
	intent.walk = _walk_mode
	intent.jump = Input.is_action_just_pressed("jump")
	intent.aim = Input.is_action_pressed("aim")
	intent.fire = Input.is_action_pressed("fire")
	intent.interact = Input.is_action_just_pressed("interact")
	intent.crouch = Input.is_action_pressed("crouch")
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	cam_yaw -= look.x * pad_sens * dt
	cam_pitch = clampf(cam_pitch - look.y * pad_sens * dt * 0.7, -1.2, 0.9)

func _physics_process(dt: float) -> void:
	if on_horse != null:
		return
	if not bot_driven:
		_read_human_intent(dt)
	var mv: Vector2 = intent.move
	var want_dir := Vector3.ZERO
	if mv.length() > 0.08:
		var cam_basis := Basis(Vector3.UP, cam_yaw)
		want_dir = (cam_basis * Vector3(mv.x, 0, -mv.y))
		want_dir.y = 0
		want_dir = want_dir.normalized()
	# target speed from stick magnitude and gait
	var target := 0.0
	if want_dir != Vector3.ZERO:
		var mag := clampf(mv.length(), 0.0, 1.0)
		target = JOG * mag
		if intent.walk or mag < 0.45:
			target = WALK * clampf(mag / 0.45, 0.3, 1.0) if not intent.walk else WALK
		if intent.sprint and stamina > 1.0 and not intent.aim:
			target = SPRINT
		if intent.crouch:
			target = minf(target, 1.4)
		if intent.aim:
			target = minf(target, 2.2)
	# slope: slower uphill, a little faster downhill
	if is_on_floor() and want_dir != Vector3.ZERO:
		var n := get_floor_normal()
		var uphill := -want_dir.dot(Vector3(n.x, 0, n.z))
		target *= clampf(1.0 - uphill * 1.3, 0.45, 1.12)
	var rate := ACCEL if target > speed else DECEL
	speed = move_toward(speed, target, rate * dt)
	# body turns toward the move direction; slower when fast (momentum), instant-ish when aiming
	if want_dir != Vector3.ZERO:
		var want_yaw := atan2(-want_dir.x, -want_dir.z)
		var turn_rate := lerpf(10.0, 3.2, clampf(speed / SPRINT, 0.0, 1.0))
		if intent.aim:
			want_yaw = cam_yaw
			turn_rate = 14.0
		facing = lerp_angle(facing, want_yaw, 1.0 - exp(-turn_rate * dt))
	elif intent.aim:
		facing = lerp_angle(facing, cam_yaw, 1.0 - exp(-14.0 * dt))
	var fwd := Vector3(-sin(facing), 0, -cos(facing))
	var move_dir := fwd if not intent.aim or want_dir == Vector3.ZERO else want_dir
	var hv := move_dir * speed
	velocity.x = hv.x
	velocity.z = hv.z
	# stamina
	if speed > JOG + 0.5:
		stamina = maxf(stamina - 9.0 * dt, 0.0)
	else:
		stamina = minf(stamina + (6.0 if speed > 0.1 else 12.0) * dt, STAMINA_MAX)
	# vertical
	if is_on_floor():
		if _air_time > 0.6:
			var impact := -_last_vy
			if impact > 9.0:
				var dmg := (impact - 9.0) * 12.0
				health -= dmg
				fall_damage_taken += dmg
				Game.log_event("fall_damage", {"impact": impact, "damage": dmg})
		_air_time = 0.0
		velocity.y = -0.5
		if intent.jump:
			velocity.y = JUMP_V
			intent.jump = false
	else:
		_air_time += dt
		velocity.y -= GRAVITY * dt
	_last_vy = velocity.y
	move_and_slide()
	rotation.y = 0.0
	if visual:
		visual.rotation.y = facing
	gait = "idle" if speed < 0.2 else ("walk" if speed < 2.4 else ("jog" if speed < 4.8 else "sprint"))
	if visual and visual.has_method("set_locomotion"):
		visual.set_locomotion(speed, gait, is_on_floor())

var _last_vy := 0.0

func _process(dt: float) -> void:
	if camera == null or on_horse != null:
		return
	_update_camera(dt)

func _update_camera(dt: float) -> void:
	var aiming: bool = intent.aim
	var want_dist := 1.6 if aiming else cam_dist + clampf(speed - JOG, 0.0, 3.0) * 0.25
	var side := cam_side * cam_shoulder * (1.0 if not aiming else 0.85)
	var pivot := global_position + Vector3(0, 1.55 if not intent.crouch else 1.1, 0)
	_cam_target = _cam_target.lerp(pivot, 1.0 - exp(-14.0 * dt))
	var basis := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
	var back := basis * Vector3(side, 0.15, want_dist)
	# camera collision: pull in when something is behind the player
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(_cam_target, _cam_target + back)
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	var d := back.length()
	if not hit.is_empty():
		d = maxf(_cam_target.distance_to(hit.position) - 0.25, 0.4)
	_cam_cur_dist = lerpf(_cam_cur_dist, d, 1.0 - exp(-(20.0 if d < _cam_cur_dist else 5.0) * dt))
	var pos := _cam_target + back.normalized() * _cam_cur_dist
	# never below the terrain
	var gy := Game.world.height(pos.x, pos.z) + 0.3
	pos.y = maxf(pos.y, gy)
	camera.global_position = pos
	camera.global_basis = basis
	camera.fov = lerpf(camera.fov, 50.0 if aiming else 62.0 + clampf(speed - JOG, 0.0, 3.0) * 1.5, 1.0 - exp(-8.0 * dt))
