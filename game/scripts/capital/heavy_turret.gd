class_name HeavyTurret
extends Node3D
## A twin 42 cm gun turret at true scale: a 20 m-wide barbette, a 24 m armoured house that trains (yaw) on it,
## two 20 m L/48 barrels on a cradle that elevates, rangefinder arms and a muzzle point per barrel. Trains at
## 3 deg/s and elevates at 4 deg/s; `fire()` salvos when the guns are laid (Combat spawns the shells).
## Players can man it (seat, third-person camera behind the house).

signal fired(muzzles: Array)

const TRAIN_RATE := 3.0
const ELEV_RATE := 4.0
const RELOAD := 28.0
const SHELL_SPEED := 800.0

var faction := "capital"
var house: Node3D
var cradle: Node3D
var muzzles: Array[Node3D] = []
var target := Vector3.ZERO
var has_target := false
var yaw := 0.0
var pitch := 0.0
var reload_t := 0.0
var manned_by: Node = null
var mat: Material
var hp := 4000.0
var recoil := 0.0
var barrels: Array[Node3D] = []


func build(material: Material, f: String = "capital") -> void:
	mat = material
	faction = f
	var style := Kit.TRIM if f == "capital" else Kit.OLIVE
	var k := Kit.new()
	k.prism(Transform3D.IDENTITY, Kit.ngon(10.5, 24), -3.0, 2.2, k.col(Kit.CONCRETE if f != "capital" else Kit.STONE, 0.2, 2.0, false), true)
	k.band(Transform3D.IDENTITY, Kit.ngon(10.5, 24), 1.6, 0.6, 0.4, k.col(Kit.TRIM, 0.2))
	_mesh(self, k)
	house = Node3D.new()
	house.name = "House"
	house.position.y = 2.2
	add_child(house)
	var h := Kit.new()
	# Armoured house: a long chamfered body, a sloped front plate and a raised commander's cupola.
	var body := PackedVector2Array([Vector2(-7.0, -9.0), Vector2(7.0, -9.0), Vector2(8.0, -2.0), Vector2(8.0, 9.5), Vector2(6.5, 11.0),
		Vector2(-6.5, 11.0), Vector2(-8.0, 9.5), Vector2(-8.0, -2.0)])
	h.prism(Transform3D.IDENTITY, body, 0.0, 6.2, h.col(style, 0.3, 3.0, false), true, false, h.col(style, 0.35, 3.0, false))
	h.prism(Transform3D.IDENTITY, Kit.inset(body, 1.2), 6.2, 6.8, h.col(Kit.STONE if f == "capital" else Kit.RUST, 0.3), true)
	h.box(Transform3D.IDENTITY, Vector3(-3.5, 7.6, 4.0), Vector3(3.0, 1.6, 3.0), h.col(style, 0.3))
	# Rangefinder arms either side at the rear.
	h.box(Transform3D.IDENTITY, Vector3(0, 5.2, 7.5), Vector3(22.0, 1.4, 1.6), h.col(style, 0.3))
	h.tube(Vector3(-11.4, 5.2, 7.5), Vector3(-10.6, 5.2, 7.5), 1.0, 8, h.col(Kit.METAL, 0.3), true)
	h.tube(Vector3(10.6, 5.2, 7.5), Vector3(11.4, 5.2, 7.5), 1.0, 8, h.col(Kit.METAL, 0.3), true)
	_mesh(house, h)
	cradle = Node3D.new()
	cradle.name = "Cradle"
	cradle.position = Vector3(0, 3.2, -8.6)
	house.add_child(cradle)
	for side in [-1.0, 1.0]:
		var b := Node3D.new()
		b.position = Vector3(side * 3.0, 0, 0)
		cradle.add_child(b)
		var g := Kit.new()
		g.tube(Vector3(0, 0, 0.5), Vector3(0, 0, -6.0), 0.78, 14, g.col(Kit.METAL, 0.3), true)
		g.tube(Vector3(0, 0, -6.0), Vector3(0, 0, -20.0), 0.55, 14, g.col(Kit.METAL, 0.3), false)
		g.tube(Vector3(0, 0, -20.0), Vector3(0, 0, -20.8), 0.66, 14, g.col(Kit.METAL, 0.3), true)
		_mesh(b, g)
		barrels.append(b)
		var m := Node3D.new()
		m.name = "Muzzle"
		m.position = Vector3(0, 0, -21.0)
		b.add_child(m)
		muzzles.append(m)
	# Collision: barbette and house.
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 10.5
	cyl.height = 5.2
	cs.shape = cyl
	cs.position.y = -0.4
	sb.add_child(cs)
	add_child(sb)
	var hb := StaticBody3D.new()
	var hs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16, 6.8, 20)
	hs.shape = box
	hs.position = Vector3(0, 3.4, 1.0)
	hb.add_child(hs)
	house.add_child(hb)
	yaw = rotation.y


func _mesh(parent: Node3D, k: Kit) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	mi.material_override = mat
	mi.visibility_range_end = 9000.0
	parent.add_child(mi)


func aim_at(p: Vector3) -> void:
	target = p
	has_target = true


## Solves the elevation for a shell at SHELL_SPEED to land at the target (low-angle solution).
func solve_pitch(p: Vector3) -> float:
	var o := cradle.global_position
	var d := Vector2(p.x - o.x, p.z - o.z).length()
	var dy := p.y - o.y
	var v2 := SHELL_SPEED * SHELL_SPEED
	var g := 9.81
	var disc := v2 * v2 - g * (g * d * d + 2.0 * dy * v2)
	if disc < 0.0:
		return deg_to_rad(45.0)
	return atan((v2 - sqrt(disc)) / (g * d))


func is_laid() -> bool:
	if not has_target:
		return false
	var want := _want()
	return absf(angle_difference(yaw, want.x)) < 0.01 and absf(pitch - want.y) < 0.01


func _want() -> Vector2:
	var o := global_position
	var dir := target - o
	var want_yaw := atan2(-dir.x, -dir.z)
	return Vector2(want_yaw, clampf(solve_pitch(target), deg_to_rad(-3.0), deg_to_rad(40.0)))


func _process(delta: float) -> void:
	reload_t = maxf(0.0, reload_t - delta)
	recoil = maxf(0.0, recoil - delta * 0.6)
	if has_target:
		var want := _want()
		var dy := angle_difference(yaw, want.x)
		yaw += clampf(dy, -deg_to_rad(TRAIN_RATE) * delta, deg_to_rad(TRAIN_RATE) * delta)
		pitch = move_toward(pitch, want.y, deg_to_rad(ELEV_RATE) * delta)
	house.global_rotation.y = yaw
	cradle.rotation.x = pitch
	for b in barrels:
		b.position.z = recoil * 1.4


func fire() -> bool:
	if reload_t > 0.0:
		return false
	reload_t = RELOAD
	recoil = 1.0
	fired.emit(muzzles)
	return true
