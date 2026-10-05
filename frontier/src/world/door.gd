class_name TownDoor
extends Node3D
## A hinged door leaf in a settlement building. The node sits on the hinge axis at floor level; the leaf extends
## along local +X (width) and its closed position faces the building's local -Z. Its mesh is one instance of a
## per-cell MultiMesh (doors cost no extra draw calls); collision is an AnimatableBody3D that swings with it.
##
## API (players, NPCs, AI):
##   interact(by)        toggle; opens away from `by` (a Node3D or Vector3)
##   open_from(pos, hold) open away from pos and close again after `hold` seconds (NPCs walking through)
##   close(), is_open(), push(from) (saloon batwings: swing and settle back by themselves)
##   door_id, building_id, kind ("hinged" | "batwing"), partner (other leaf of a double door)

signal opened(door)
signal closed(door)

var door_id := ""
var building_id := ""
var kind := "hinged"
var width := 1.0
var height := 2.1
var partner: TownDoor = null
var hinge_sign := 1.0          # +1 hinge on the left (leaf extends +X), -1 mirrored leaf
var mm: MultiMesh = null
var mm_index := -1
var leaf_local := Transform3D.IDENTITY
var angle := 0.0               # radians, + opens towards the inside (local +Z)
var target := 0.0
var vel := 0.0
var max_open := deg_to_rad(100.0)
var _hold := 0.0
var body: AnimatableBody3D

func setup(w: float, h: float, thickness: float, with_collision := true) -> void:
	width = w
	height = h
	if with_collision:
		body = AnimatableBody3D.new()
		body.sync_to_physics = false
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(w, h, thickness)
		cs.shape = bs
		cs.position = Vector3(w * 0.5 * hinge_sign, h * 0.5, 0.0)
		body.add_child(cs)
		body.set_meta("door", self)
		add_child(body)
	set_process(false)

func _ready() -> void:
	_sync()

func is_open() -> bool:
	return absf(angle) > 0.2 or absf(target) > 0.01

func _dir_from(by) -> float:
	var p: Vector3
	if by is Node3D:
		p = (by as Node3D).global_position
	elif by is Vector3:
		p = by
	else:
		return 1.0
	var local := global_transform.affine_inverse() * p
	# open away from the actor: actor on the outside (-Z) -> swing inwards (+angle)
	return 1.0 if local.z < 0.0 else -1.0

func interact(by = null) -> void:
	if is_open():
		close()
		if partner != null:
			partner.close()
	else:
		var d := _dir_from(by)
		_open(d, 0.0)
		if partner != null:
			partner._open(d, 0.0)

func open_from(pos: Vector3, hold := 3.0) -> void:
	var d := _dir_from(pos)
	_open(d, hold)
	if partner != null:
		partner._open(d, hold)

## Keep an already open door open a little longer without changing its swing (someone is still in the doorway).
func keep_open(hold := 2.0) -> void:
	if absf(target) < 0.01:
		return
	if _hold > 0.0:
		_hold = maxf(_hold, hold)
		set_process(true)
	if partner != null and partner._hold > 0.0:
		partner._hold = maxf(partner._hold, hold)
		partner.set_process(true)

func push(from) -> void:
	open_from(from if from is Vector3 else (from as Node3D).global_position, 0.6)

func _open(dir: float, hold: float) -> void:
	target = max_open * dir * hinge_sign
	_hold = hold
	set_process(true)
	opened.emit(self)

func close() -> void:
	target = 0.0
	_hold = 0.0
	set_process(true)

func _process(dt: float) -> void:
	if _hold > 0.0:
		_hold -= dt
		if _hold <= 0.0:
			target = 0.0
	if kind == "batwing":
		# double-acting spring hinge: underdamped return
		var k := 38.0
		var c := 4.5
		vel += (-(angle - target) * k - vel * c) * dt
		angle += vel * dt
		if target == 0.0 and absf(angle) < 0.003 and absf(vel) < 0.01:
			angle = 0.0
			vel = 0.0
			set_process(false)
	else:
		var step := dt * 2.4
		var prev := angle
		angle = move_toward(angle, target, step)
		if is_equal_approx(angle, target):
			set_process(false)
			if target == 0.0 and prev != 0.0:
				closed.emit(self)
	_sync()

func _sync() -> void:
	rotation.y = -angle
	if mm != null and mm_index >= 0 and is_inside_tree():
		mm.set_instance_transform(mm_index, global_transform * leaf_local)
