class_name Lasso
extends Node3D
## Lasso and hogtie (Lasso: L, or Y while aiming on a controller). A throw catches the nearest person in a cone in
## front within RANGE; the rope then holds them inside its length (they can't run off), and pulling away from them
## while the rope is taut drags them down. A downed, roped person can be hogtied (Interact): they stay down and
## helpless until cut loose (meta "hogtied"; bounties take them in alive). The rope is a stretched cylinder from
## Ruth's hand to the catch, sagging a little when slack.

const RANGE := 16.0
const CONE := deg_to_rad(18.0)
const PULL_DOWN := 1.6          # s of pulling against a taut rope that drags the catch down

var owner_body: CharacterBody3D
var caught: Node3D = null
var length := 0.0
var _pull_t := 0.0
var _rope: MeshInstance3D
var throws := 0

func setup(body: CharacterBody3D) -> void:
	owner_body = body
	_rope = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.012
	cm.height = 1.0
	cm.radial_segments = 6
	cm.rings = 1
	_rope.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.45, 0.3)
	m.roughness = 0.95
	_rope.material_override = m
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope.visible = false
	_rope.top_level = true
	add_child(_rope)

func _hand() -> Vector3:
	return owner_body.global_position + Vector3(0, 1.35, 0)

func _catch_point() -> Vector3:
	if caught == null:
		return Vector3.ZERO
	var down: bool = Melee.is_down(caught) or caught.get_meta("hogtied", false)
	return caught.global_position + Vector3(0, 0.35 if down else 1.15, 0)

## Throw toward yaw. Returns the person caught, or null (a miss).
func throw(yaw: float) -> Node3D:
	throws += 1
	release()
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var best: Node3D = null
	var bd := RANGE
	for n in owner_body.get_tree().get_nodes_in_group("humans"):
		var d = n.get("damageable")
		if d == null or not d.alive:
			continue
		var v: Vector3 = (n as Node3D).global_position - owner_body.global_position
		v.y = 0.0
		var dist := v.length()
		if dist < bd and dist > 0.5 and fwd.angle_to(v / dist) < CONE:
			bd = dist
			best = n
	if Game.audio != null and Game.audio.has_sound("lasso_throw"):
		Game.audio.play("lasso_throw", _hand())
	if best == null:
		Game.log_event("lasso", {"caught": ""})
		return null
	caught = best
	length = maxf(bd, 2.5)
	_pull_t = 0.0
	caught.set_meta("lassoed", true)
	var br = caught.get("brain")
	if br != null and br.get("state") != null and br.state != br.State.SURRENDER:
		br.state = br.State.COWER          # caught: they stop and struggle
	Game.log_event("lasso", {"caught": str(caught.name), "dist": snappedf(bd, 0.1)})
	return caught

func release() -> void:
	if caught != null and is_instance_valid(caught):
		caught.set_meta("lassoed", false)
	caught = null
	_rope.visible = false

## Hogtie the catch if it is down and within reach. True on success.
func hogtie() -> bool:
	if caught == null or not is_instance_valid(caught) or not Melee.is_down(caught):
		return false
	if caught.global_position.distance_to(owner_body.global_position) > 2.6:
		return false
	caught.set_meta("hogtied", true)
	caught.set_meta("knocked_down", true)       # stays down: the get-up timer leaves a hogtied person on the ground
	Game.log_event("hogtie", {"target": str(caught.name)})
	release()
	return true

## Cut a hogtied person loose (they get up after a moment).
static func cut_loose(n: Node3D) -> void:
	n.set_meta("hogtied", false)
	n.get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(n):
			n.set_meta("knocked_down", false)
			var v = n.get("visual")
			if v != null and v.has_method("play_action"):
				v.play_action("get_up_back"))

func _physics_process(dt: float) -> void:
	if caught == null:
		return
	if not is_instance_valid(caught) or not caught.get("damageable").alive:
		release()
		return
	var a := owner_body.global_position
	var b := caught.global_position
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	var dist := flat.length()
	if dist > length + 6.0:
		release()                               # torn free (a horse at full gallop, a teleport)
		return
	var taut := dist >= length - 0.05
	# the catch can't go past the rope: clamp them back onto its circle
	if dist > length and not caught.get_meta("hogtied", false):
		var pos := a + flat.normalized() * length
		caught.global_position = Vector3(pos.x, b.y, pos.z)
	# pulling away while taut drags them off their feet
	var away := owner_body.velocity.dot(flat.normalized() * -1.0)
	if taut and away > 1.0 and not Melee.is_down(caught):
		_pull_t += dt
		if _pull_t >= PULL_DOWN:
			Melee.knock_down(caught, owner_body)
			caught.set_meta("knocked_down", true)
	else:
		_pull_t = maxf(_pull_t - dt * 0.5, 0.0)
	# reel in when Ruth walks toward them
	if dist < length - 0.5:
		length = maxf(dist + 0.4, 2.0)

func _process(_dt: float) -> void:
	if caught == null or not is_instance_valid(caught):
		_rope.visible = false
		return
	var h := _hand()
	var c := _catch_point()
	var mid := (h + c) * 0.5
	var span := h.distance_to(c)
	var slack := clampf(length - Vector3(c.x - h.x, 0, c.z - h.z).length(), 0.0, 3.0)
	mid.y -= slack * 0.25
	_rope.visible = span > 0.2
	if _rope.visible:
		var up := (c - h).normalized()
		var basis := Basis()
		basis.y = up
		basis.x = up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		basis.z = basis.x.cross(up).normalized()
		_rope.global_transform = Transform3D(Basis(basis.x, up * span, basis.z), mid)
