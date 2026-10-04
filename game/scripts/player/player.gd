class_name Player
extends CharacterBody3D
## First-person soldier: mouse / stick look (Controls look curve), walk, sprint, crouch, jump, swim, and riding
## moving decks (the platform's linear and angular velocity carry the player). F9 toggles a debug fly mode.
## Vehicles take over the camera through `enter_vehicle` / `exit_vehicle`.

const WALK := 4.6
const SPRINT := 7.6
const CROUCH := 2.2
const JUMP := 4.9
const ACCEL := 11.0
const AIR_ACCEL := 2.5
const EYE := 1.66
const EYE_CROUCH := 1.05

var head: Node3D
var camera: Camera3D
var pitch := 0.0
var crouching := false
var flying := false
var swimming := false
var zoomed := false
var vehicle: Node = null          # the vehicle the player is in, or null
var bob_t := 0.0
var _eye := EYE
var col_shape: CollisionShape3D
var health := 100.0
var weapons: Node = null
var _step_t := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.45
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY
	platform_floor_layers = 0xFFFFFFFF
	col_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.8
	col_shape.shape = cap
	col_shape.position.y = 0.9
	add_child(col_shape)
	head = Node3D.new()
	head.name = "Head"
	head.position.y = EYE
	add_child(head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = Settings.fov
	camera.near = 0.05
	camera.far = 160000.0
	head.add_child(camera)
	camera.make_current()
	G.cam = camera
	if ResourceLoader.exists("res://scripts/combat/weapons.gd"):
		weapons = load("res://scripts/combat/weapons.gd").new()
		weapons.name = "Weapons"
		camera.add_child(weapons)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if vehicle:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := Settings.mouse_sensitivity * 0.01 * (0.55 if zoomed else 1.0)
		rotation.y -= event.relative.x * s
		var dy: float = event.relative.y * s * (-1.0 if Settings.invert_y else 1.0)
		pitch = clampf(pitch - dy, deg_to_rad(-88.0), deg_to_rad(88.0))
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_F9:
		flying = not flying
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if vehicle:
		return
	zoomed = Input.is_action_pressed("aim")
	var look := Controls.look_delta(delta, zoomed)
	rotation.y -= look.x
	pitch = clampf(pitch - look.y, deg_to_rad(-88.0), deg_to_rad(88.0))
	head.rotation.x = pitch
	var target_fov := Settings.fov * (0.62 if zoomed else 1.0)
	if weapons and weapons.has_method("zoom_fov"):
		target_fov = weapons.zoom_fov(Settings.fov, zoomed)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-delta * 14.0))
	var target_eye := EYE_CROUCH if crouching else EYE
	_eye = lerpf(_eye, target_eye, 1.0 - exp(-delta * 10.0))
	# Head bob while walking on the ground.
	var hv := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hv > 0.5:
		bob_t += delta * hv * 1.6
	var bob := sin(bob_t) * 0.035 * clampf(hv / SPRINT, 0.0, 1.0)
	head.position.y = _eye + bob
	head.position.x = cos(bob_t * 0.5) * 0.02 * clampf(hv / SPRINT, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if vehicle:
		return
	if global_position.y < -500.0:
		global_position = G.world.site("spawn") + Vector3(0, 3, 0)
		velocity = Vector3.ZERO
	var mv := Controls.move_vector()
	var basis_y := Basis(Vector3.UP, rotation.y)
	var wish := basis_y * Vector3(mv.x, 0.0, -mv.y)
	if flying:
		var fwd := -camera.global_transform.basis.z
		var right := camera.global_transform.basis.x
		var spd := 220.0 if Input.is_action_pressed("sprint") else 45.0
		var up := float(Input.is_action_pressed("jump")) - float(Input.is_action_pressed("crouch"))
		velocity = (fwd * mv.y + right * mv.x + Vector3.UP * up) * spd
		global_position += velocity * delta
		return
	# Water: swim when the chest is under the surface.
	var wl: float = G.gen.water_at(global_position.x, global_position.z) if G.gen else -1e4
	swimming = wl > -100.0 and global_position.y + 1.1 < wl
	crouching = Input.is_action_pressed("crouch") and not swimming
	var sprint := Input.is_action_pressed("sprint") and mv.y > 0.3 and not crouching
	var speed := CROUCH if crouching else (SPRINT if sprint else WALK)
	if swimming:
		speed = 2.6
	var target := wish * speed
	var on_floor := is_on_floor()
	var a := ACCEL if on_floor else AIR_ACCEL
	if swimming:
		a = 3.0
	velocity.x = lerpf(velocity.x, target.x, 1.0 - exp(-a * delta))
	velocity.z = lerpf(velocity.z, target.z, 1.0 - exp(-a * delta))
	if swimming:
		var buoy := clampf((wl - (global_position.y + 1.2)) * 2.0, -1.0, 2.0)
		velocity.y = lerpf(velocity.y, buoy + (2.0 if Input.is_action_pressed("jump") else 0.0), 1.0 - exp(-3.0 * delta))
	elif not on_floor:
		velocity.y -= 9.81 * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP
	# Ride decks: turn with the platform as well as move with it.
	if on_floor:
		var av := get_platform_angular_velocity()
		rotation.y += av.y * delta
	move_and_slide()
	_footsteps(delta, on_floor)


func _footsteps(delta: float, on_floor: bool) -> void:
	var hv := Vector2(velocity.x, velocity.z).length()
	if not on_floor or hv < 1.0:
		_step_t = 0.0
		return
	_step_t += delta * hv / 1.5
	if _step_t > 1.0:
		_step_t -= 1.0
		if Sfx.has_method("footstep"):
			Sfx.footstep(global_position, hv)


func enter_vehicle(v: Node) -> void:
	vehicle = v
	col_shape.disabled = true
	visible = false


func exit_vehicle(at: Vector3) -> void:
	vehicle = null
	col_shape.disabled = false
	visible = true
	global_position = at
	velocity = Vector3.ZERO
	camera.make_current()
	G.cam = camera
