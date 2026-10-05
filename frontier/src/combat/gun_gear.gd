class_name GunGear
extends RefCounted
## Leather gun gear built procedurally around the actual weapon models: a cartridge gun belt (sized to the body's
## hips), a holster shaped to the sidearm (mouth at the cylinder, toe past the muzzle, belt loop), a sling strap on
## long guns, and a saddle scabbard for the rifle. Plain StandardMaterial3D (triplanar leather from the CC0 pack when
## present) so it is cheap and safe on every renderer.

static var _leather: StandardMaterial3D
static var _leather_dark: StandardMaterial3D
static var _brass: StandardMaterial3D

static func leather(dark := false) -> StandardMaterial3D:
	if _leather == null:
		_leather = StandardMaterial3D.new()
		_leather.albedo_color = Color(0.46, 0.30, 0.18)
		_leather.roughness = 0.62
		var p := "res://assets/ext/packed/cloth_leather_ah.png"
		if ResourceLoader.exists(p):
			_leather.albedo_texture = load(p)
			_leather.uv1_triplanar = true
			_leather.uv1_scale = Vector3(4, 4, 4)
		_leather.cull_mode = BaseMaterial3D.CULL_DISABLED
		_leather_dark = _leather.duplicate()
		_leather_dark.albedo_color = Color(0.26, 0.16, 0.10)
		_brass = StandardMaterial3D.new()
		_brass.albedo_color = Color(0.78, 0.6, 0.32)
		_brass.metallic = 1.0
		_brass.roughness = 0.35
	return _leather_dark if dark else _leather

## Elliptical tube along the gun's Z axis (the bore) from the open mouth to a closed toe: sections
## [z, half_x, half_y, y_center] in the gun/socket frame (barrel toward -Z, gun top +Y).
static func _tube(st: SurfaceTool, sections: Array, n := 14, close_end := true) -> void:
	var rings := []
	for s in sections:
		var r := []
		for i in n:
			var a := TAU * i / n
			r.append(Vector3(cos(a) * s[1], s[3] + sin(a) * s[2], s[0]))
		rings.append(r)
	for k in rings.size() - 1:
		var ra: Array = rings[k]
		var rb: Array = rings[k + 1]
		for i in n:
			var j := (i + 1) % n
			st.add_vertex(ra[i]); st.add_vertex(rb[i]); st.add_vertex(rb[j])
			st.add_vertex(ra[i]); st.add_vertex(rb[j]); st.add_vertex(ra[j])
	if close_end:
		var last: Array = rings[-1]
		var s2: Array = sections[-1]
		var tip := Vector3(0, float(s2[3]), float(s2[0]) + 0.01 * signf(float(s2[0]) - float(sections[0][0])))
		for i in n:
			st.add_vertex(last[i]); st.add_vertex(tip); st.add_vertex(last[(i + 1) % n])

static func _box(st: SurfaceTool, c: Vector3, h: Vector3) -> void:
	var p := [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]
	var f := [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]
	for q in f:
		var v := []
		for i in q:
			v.append(c + p[i] * h)
		st.add_vertex(v[0]); st.add_vertex(v[1]); st.add_vertex(v[2])
		st.add_vertex(v[0]); st.add_vertex(v[2]); st.add_vertex(v[3])

static func _finish(st: SurfaceTool, mat: Material) -> ArrayMesh:
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m

## Holster mesh in the holster-socket frame used by WeaponHolder (= the gun's own frame with the origin on its
## holster_attach marker: barrel toward -Z, gun top +Y, gun right side +X; the socket hangs it muzzle-down).
static func holster_mesh(wm: WeaponModel) -> MeshInstance3D:
	var anchor := wm.marker_local("holster_attach")
	var muz := wm.marker_local("muzzle")
	var depth := absf(muz.origin.z - anchor.origin.z) + 0.014
	var bore_off := muz.origin.y - anchor.origin.y             # bore above the cylinder axis
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var secs := [[0.026, 0.026, 0.036, bore_off * 0.35], [0.0, 0.025, 0.034, bore_off * 0.3],
		[-0.05, 0.020, 0.023, bore_off * 0.9], [-depth * 0.6, 0.017, 0.018, bore_off],
		[-depth, 0.015, 0.015, bore_off]]
	_tube(st, secs, 16, true)
	_box(st, Vector3(-0.027, 0.0, 0.07), Vector3(0.004, 0.03, 0.055))        # belt loop flap up to the belt (body side)
	var mi := MeshInstance3D.new()
	mi.name = "Holster"
	mi.mesh = _finish(st, leather())
	return mi

## Gun belt ring around the hips with a row of cartridges in loops along the back.
static func belt_mesh(rx: float, rz: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 40
	var h := 0.024
	var t := 0.006
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		for side in [0.0, t]:
			var p0 := Vector3(cos(a0) * (rx + side), 0, sin(a0) * (rz + side))
			var p1 := Vector3(cos(a1) * (rx + side), 0, sin(a1) * (rz + side))
			st.add_vertex(p0 + Vector3(0, -h, 0)); st.add_vertex(p1 + Vector3(0, -h, 0)); st.add_vertex(p1 + Vector3(0, h, 0))
			st.add_vertex(p0 + Vector3(0, -h, 0)); st.add_vertex(p1 + Vector3(0, h, 0)); st.add_vertex(p0 + Vector3(0, h, 0))
	_box(st, Vector3(0, 0, -rz - 0.006), Vector3(0.022, 0.026, 0.005))       # buckle plate (front)
	var mi := MeshInstance3D.new()
	mi.name = "GunBelt"
	mi.mesh = _finish(st, leather(true))
	# cartridges in loops: brass cases poking up along the back half
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 16:
		var a := PI * 0.1 + PI * 0.8 * k / 15.0                            # back half (+Z)
		var c := Vector3(cos(a) * (rx + 0.013), 0.006, sin(a) * (rz + 0.013))
		_box(st2, c, Vector3(0.0055, 0.022, 0.0055))
	var bm := _finish(st2, _brass)
	var b := MeshInstance3D.new()
	b.name = "Cartridges"
	b.mesh = bm
	mi.add_child(b)
	return mi

## Sling strap under a long gun (model space): from ahead of the fore-end to the toe of the butt, sagging a little.
static func sling_mesh(wm: WeaponModel) -> MeshInstance3D:
	var box := AABB()
	var first := true
	for c in wm.lod0.get_children():
		if c is MeshInstance3D:
			var b: AABB = (c as MeshInstance3D).transform * (c as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
	var gl := wm.marker_local("grip_l").origin
	var a := Vector3(0, gl.y - 0.025, gl.z - 0.18)
	var b2 := Vector3(0, box.position.y + 0.035, box.end.z - 0.06)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	var w := 0.014
	var pts := []
	for i in n + 1:
		var u := float(i) / n
		var p := a.lerp(b2, u)
		p.y -= sin(u * PI) * 0.07
		pts.append(p)
	for i in n:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		st.add_vertex(p0 + Vector3(-w, 0, 0)); st.add_vertex(p1 + Vector3(-w, 0, 0)); st.add_vertex(p1 + Vector3(w, 0, 0))
		st.add_vertex(p0 + Vector3(-w, 0, 0)); st.add_vertex(p1 + Vector3(w, 0, 0)); st.add_vertex(p0 + Vector3(w, 0, 0))
	var mi := MeshInstance3D.new()
	mi.name = "Sling"
	mi.mesh = _finish(st, leather())
	return mi

## Saddle scabbard in its socket frame (barrel along -Y from the receiver mouth).
static func scabbard_mesh(wm: WeaponModel) -> MeshInstance3D:
	var anchor := wm.marker_local("holster_attach")
	var muz := wm.marker_local("muzzle")
	var depth := absf(muz.origin.z - anchor.origin.z) + 0.02
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(st, [[0.10, 0.034, 0.052, 0.0], [0.0, 0.032, 0.046, 0.005], [-0.12, 0.024, 0.030, 0.01],
		[-depth, 0.020, 0.022, 0.01]], 16, true)
	_box(st, Vector3(-0.03, 0.0, -0.05), Vector3(0.004, 0.03, 0.04))         # strap to the saddle
	var mi := MeshInstance3D.new()
	mi.name = "Scabbard"
	mi.mesh = _finish(st, leather())
	return mi
