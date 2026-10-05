class_name SoldierMesh
## Procedural soldier bodies for GPU animation (soldier.gdshader). Each vertex carries its bone in UV2.x and its
## material slot in COLOR.r (slot / 8). Bones: 0 torso, 1 head, 2 L upper arm, 3 L forearm, 4 R upper arm,
## 5 R forearm, 6 L thigh, 7 L shin, 8 R thigh, 9 R shin, 10 weapon. Slots: 0 visor/face, 1 uniform, 2 trim,
## 3 boots and gloves, 4 weapon metal, 5 accent, 6 under-suit, 7 skin.
## Bodies: 0 trooper (helmet, armour plates), 1 officer (peaked cap, long coat), 2 heavy (bulky plates, pack,
## launcher). Soldiers face -Z, feet at y = 0, 1.8 m tall.

enum { TROOPER, OFFICER, HEAVY }

const PIVOTS := [Vector3(0, 0.95, 0), Vector3(0, 1.48, 0), Vector3(-0.21, 1.42, 0), Vector3(-0.21, 1.14, 0),
	Vector3(0.21, 1.42, 0), Vector3(0.21, 1.14, 0), Vector3(-0.1, 0.93, 0), Vector3(-0.1, 0.5, 0),
	Vector3(0.1, 0.93, 0), Vector3(0.1, 0.5, 0), Vector3(0.18, 1.2, -0.1)]

var st := SurfaceTool.new()
var bone := 0
var slot := 1


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


func _v(p: Vector3, n: Vector3) -> void:
	st.set_color(Color((slot + 0.5) / 8.0, 0, 0))
	st.set_uv2(Vector2(bone + 0.5, 0))
	st.set_normal(n)
	st.add_vertex(p)


## A box with bevel-free faces, centred at c with size s, rotated by b.
func box(c: Vector3, s: Vector3, b: Basis = Basis.IDENTITY) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)],
		[Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var w: Vector3 = f[2]
		var cc := c + b * (n * h)
		var du := b * (u * h)
		var dw := b * (w * h)
		var nn := (b * n).normalized()
		# Scale du/dw to this face's extent.
		du = b * Vector3(u.x * h.x, u.y * h.y, u.z * h.z)
		dw = b * Vector3(w.x * h.x, w.y * h.y, w.z * h.z)
		var p0 := cc - du - dw
		var p1 := cc + du - dw
		var p2 := cc + du + dw
		var p3 := cc - du + dw
		for p in [p0, p2, p1, p0, p3, p2]:
			_v(p, nn)


## A tapered cylinder between a and b (radii ra, rb).
func limb(a: Vector3, b: Vector3, ra: float, rb: float, sides: int = 7) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var w := axis.cross(u).normalized()
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := u * cos(a0) + w * sin(a0)
		var d1 := u * cos(a1) + w * sin(a1)
		for q in [[a + d0 * ra, d0], [b + d1 * rb, d1], [b + d0 * rb, d0], [a + d0 * ra, d0], [a + d1 * ra, d1], [b + d1 * rb, d1]]:
			_v(q[0], q[1])
	# End caps.
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		_v(b, axis); _v(b + (u * cos(a0) + w * sin(a0)) * rb, axis); _v(b + (u * cos(a1) + w * sin(a1)) * rb, axis)
		_v(a, -axis); _v(a + (u * cos(a1) + w * sin(a1)) * ra, -axis); _v(a + (u * cos(a0) + w * sin(a0)) * ra, -axis)


## Low-poly ellipsoid.
func blob(c: Vector3, r: Vector3, rings: int = 5, seg: int = 8) -> void:
	for j in rings:
		var a0 := -PI * 0.5 + PI * j / rings
		var a1 := -PI * 0.5 + PI * (j + 1) / rings
		for i in seg:
			var b0 := TAU * i / seg
			var b1 := TAU * (i + 1) / seg
			var pts := []
			for ab in [[a0, b0], [a1, b0], [a1, b1], [a0, b1]]:
				var d := Vector3(cos(ab[0]) * cos(ab[1]), sin(ab[0]), cos(ab[0]) * sin(ab[1]))
				pts.append([c + d * r, Vector3(d.x / r.x, d.y / r.y, d.z / r.z).normalized()])
			for k in [0, 1, 2, 0, 2, 3]:
				_v(pts[k][0], pts[k][1])


static func build(body: int, cinder: bool = false) -> ArrayMesh:
	var m := SoldierMesh.new()
	m.cinder = cinder
	m._body(body)
	return m.st.commit()


var cinder := false


func _body(body: int) -> void:
	var heavy := body == HEAVY
	var officer := body == OFFICER
	var bulk := 1.18 if heavy else 1.0
	# Torso: under-suit core, chest plate, abdomen, belt, back pack.
	bone = 0
	slot = 6; box(Vector3(0, 1.2, 0), Vector3(0.34, 0.5, 0.2) * Vector3(bulk, 1, bulk))
	slot = 1; box(Vector3(0, 1.3, -0.02), Vector3(0.4 * bulk, 0.28, 0.24 * bulk))
	slot = 2; box(Vector3(0, 1.3, -0.145 * bulk), Vector3(0.14, 0.2, 0.01))
	slot = 1; box(Vector3(0, 1.06, -0.01), Vector3(0.32 * bulk, 0.16, 0.21 * bulk))
	slot = 3; box(Vector3(0, 0.96, 0), Vector3(0.36 * bulk, 0.06, 0.23 * bulk))
	slot = 2; box(Vector3(0.12, 0.96, -0.12), Vector3(0.08, 0.08, 0.04))
	slot = 2; box(Vector3(-0.12, 0.96, -0.12), Vector3(0.08, 0.08, 0.04))
	if heavy:
		slot = 2; box(Vector3(0, 1.25, 0.2), Vector3(0.38, 0.42, 0.18))
		slot = 4; limb(Vector3(-0.12, 1.5, 0.22), Vector3(-0.12, 0.95, 0.22), 0.05, 0.05)
	else:
		slot = 2; box(Vector3(0, 1.22, 0.15), Vector3(0.28, 0.3, 0.1))
	if officer:
		# Long coat skirt to the knees, high collar, shoulder boards.
		slot = 1; box(Vector3(0, 0.74, 0.0), Vector3(0.42, 0.42, 0.26))
		slot = 2; box(Vector3(0, 0.55, -0.135), Vector3(0.05, 0.04, 0.01))
		slot = 2; box(Vector3(0, 1.47, 0), Vector3(0.22, 0.08, 0.2))
	if not cinder:
		# Shoulder pauldrons (accent slot shows rank colour).
		slot = 5
		for side in [-1.0, 1.0]:
			blob(Vector3(side * 0.22, 1.42, 0), Vector3(0.1, 0.07, 0.11) * bulk)
	else:
		# Webbing: crossed straps and ammo pouches; a scarf wrapped at the neck.
		slot = 2
		box(Vector3(0, 1.28, -0.14 * bulk), Vector3(0.06, 0.34, 0.02), Basis(Vector3.FORWARD, 0.55))
		box(Vector3(0, 1.28, -0.14 * bulk), Vector3(0.06, 0.34, 0.02), Basis(Vector3.FORWARD, -0.55))
		for x in [-0.12, 0.0, 0.12]:
			box(Vector3(x, 1.05, -0.13 * bulk), Vector3(0.09, 0.09, 0.05))
		slot = 5
		blob(Vector3(0, 1.49, 0), Vector3(0.12, 0.06, 0.11))
		box(Vector3(0.05, 1.36, 0.13), Vector3(0.08, 0.2, 0.02))
	# Head and headgear.
	bone = 1
	if officer:
		slot = 7; blob(Vector3(0, 1.62, 0), Vector3(0.095, 0.115, 0.105))
		slot = 1; limb(Vector3(0, 1.69, 0), Vector3(0, 1.76, 0), 0.115, 0.13, 10)
		slot = 3; box(Vector3(0, 1.69, -0.12), Vector3(0.2, 0.015, 0.08))
		slot = 2; limb(Vector3(0, 1.685, 0), Vector3(0, 1.705, 0), 0.118, 0.118, 10)
	elif cinder:
		# Domed helmet with a flared skirt over the neck and sides and a short visor ridge (a wide flat brim read
		# as a conical straw hat), goggles over a gas mask with a filter canister.
		slot = 7; blob(Vector3(0, 1.6, 0), Vector3(0.1, 0.12, 0.11))
		slot = 2; blob(Vector3(0, 1.675, 0.005), Vector3(0.135, 0.095, 0.145) * bulk)
		slot = 2; limb(Vector3(0, 1.655, 0.02), Vector3(0, 1.585, 0.035), 0.132 * bulk, 0.15 * bulk, 12)
		slot = 3; box(Vector3(0, 1.665, -0.135 * bulk), Vector3(0.2, 0.025, 0.05))
		slot = 0
		for gx in [-0.045, 0.045]:
			blob(Vector3(gx, 1.62, -0.1), Vector3(0.035, 0.03, 0.02))
		slot = 0; blob(Vector3(0, 1.58, -0.08), Vector3(0.08, 0.07, 0.06))
		slot = 0; limb(Vector3(0, 1.55, -0.12), Vector3(0, 1.52, -0.2), 0.035, 0.035, 8)
		slot = 0; box(Vector3(0.0, 1.63, -0.105), Vector3(0.12, 0.035, 0.02))
	else:
		slot = 1; blob(Vector3(0, 1.64, 0.005), Vector3(0.13, 0.13, 0.14) * bulk)
		slot = 0; box(Vector3(0, 1.615, -0.11 * bulk), Vector3(0.18, 0.07, 0.06))
		slot = 2; box(Vector3(0, 1.72, 0.0), Vector3(0.03, 0.03, 0.26))
		slot = 6; limb(Vector3(0, 1.48, 0), Vector3(0, 1.55, 0), 0.06, 0.06, 6)
	# Arms.
	for side in [-1, 1]:
		var sx := float(side)
		bone = 2 if side < 0 else 4
		slot = 1; limb(Vector3(sx * 0.21, 1.42, 0), Vector3(sx * 0.21, 1.15, 0), 0.06 * bulk, 0.052 * bulk)
		bone = 3 if side < 0 else 5
		slot = 1 if not officer else 1; limb(Vector3(sx * 0.21, 1.14, 0), Vector3(sx * 0.21, 0.92, 0), 0.05 * bulk, 0.042 * bulk)
		slot = 2; limb(Vector3(sx * 0.21, 1.02, 0), Vector3(sx * 0.21, 0.97, 0), 0.053 * bulk, 0.05 * bulk)
		slot = 3; blob(Vector3(sx * 0.21, 0.87, -0.01), Vector3(0.045, 0.06, 0.05))
	# Legs.
	for side in [-1, 1]:
		var sx := float(side)
		bone = 6 if side < 0 else 8
		slot = 6; limb(Vector3(sx * 0.1, 0.93, 0), Vector3(sx * 0.1, 0.51, 0), 0.08 * bulk, 0.06 * bulk)
		slot = 1; box(Vector3(sx * 0.1, 0.74, -0.06 * bulk), Vector3(0.13 * bulk, 0.26, 0.04))
		bone = 7 if side < 0 else 9
		slot = 1; limb(Vector3(sx * 0.1, 0.5, 0), Vector3(sx * 0.1, 0.1, 0), 0.058 * bulk, 0.048 * bulk)
		slot = 2; box(Vector3(sx * 0.1, 0.48, -0.06), Vector3(0.11, 0.09, 0.04))
		slot = 3; box(Vector3(sx * 0.1, 0.05, -0.04), Vector3(0.11, 0.1, 0.27))
	# Weapon (held in both hands; the shader poses it): rifle, pistol for officers, launcher for heavies.
	bone = 10
	if heavy:
		slot = 4; limb(Vector3(0, 0, 0.45), Vector3(0, 0, -0.75), 0.075, 0.075, 8)
		slot = 2; box(Vector3(0, -0.11, 0.05), Vector3(0.05, 0.16, 0.08))
		slot = 5; box(Vector3(0, 0.06, -0.2), Vector3(0.04, 0.06, 0.18))
	elif officer:
		slot = 4; box(Vector3(0, 0, -0.08), Vector3(0.035, 0.05, 0.2))
		slot = 4; box(Vector3(0, -0.07, -0.0), Vector3(0.03, 0.1, 0.05))
	else:
		slot = 4; box(Vector3(0, 0, -0.1), Vector3(0.05, 0.08, 0.62))
		slot = 4; limb(Vector3(0, 0.015, -0.4), Vector3(0, 0.015, -0.72), 0.012, 0.012, 5)
		slot = 2; box(Vector3(0, -0.01, 0.28), Vector3(0.045, 0.12, 0.2))
		slot = 4; box(Vector3(0, -0.1, -0.07), Vector3(0.035, 0.14, 0.06))
		slot = 2; box(Vector3(0, 0.07, -0.05), Vector3(0.03, 0.04, 0.14))
