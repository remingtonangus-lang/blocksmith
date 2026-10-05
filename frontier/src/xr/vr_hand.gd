class_name VRHand
extends Node3D
## A gloved VR hand built procedurally (palm + jointed fingers and thumb, period leather gloves so it matches any
## character), parented to an XRController3D at its grip pose. Fingers curl from the controller: grip curls the
## middle/ring/little fingers, trigger the index, a thumb touch the thumb; set `holding` for a weapon grip (index
## following the trigger on the trigger guard, others wrapped). Hand frame = the controller's AIM frame: fingers
## extend along -Z, the knuckle line runs along Y (index on top), the palm faces -X on the right hand and +X on the
## left, so a closed fist wraps a pistol grip whose barrel points down the aim ray. The fist centre (FIST) sits on
## the controller's grip-pose origin, which is where held things go (aim_transform()).

const FIST := Vector3(-0.026, 0.0, -0.045)   # right hand; x mirrors for the left

var side := "right"
var grip := 0.0
var trigger := 0.0
var thumb := 0.0
var holding := false
var _fingers := []          # [[segment nodes...], kind]
var _thumb_segs := []
var _mat: StandardMaterial3D
var _cur := {}
var rel := Basis(Vector3.RIGHT, deg_to_rad(VRSim.GRIP_TO_AIM))   # grip -> aim rotation (read from the tracker)

func fist() -> Vector3:
	return Vector3(FIST.x * (1.0 if side == "right" else -1.0), FIST.y, FIST.z)

## World aim frame at the fist centre: -Z down the aim ray. Guns, rounds and reins are placed on this.
func aim_transform() -> Transform3D:
	var p := get_parent() as Node3D
	if p == null:
		return global_transform
	return Transform3D(p.global_basis.orthonormalized() * rel, p.global_position)

func setup(s: String) -> void:
	side = s
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.95, 0.78, 0.6)
	_mat.roughness = 0.72
	var p := "res://assets/ext/packed/cloth_leather_ah.png"
	if ResourceLoader.exists(p):
		_mat.albedo_texture = load(p)
		_mat.uv1_triplanar = true
		_mat.uv1_scale = Vector3(12, 12, 12)
	var mir := 1.0 if side == "right" else -1.0
	# palm: back of the hand outward, wrist behind
	var palm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.028, 0.086, 0.092)
	palm.mesh = bm
	palm.material_override = _mat
	palm.position = Vector3(0.006 * mir, 0.0, 0.035)
	add_child(palm)
	var cuff := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cuff.mesh = cm
	cuff.material_override = _mat
	cm.top_radius = 0.03
	cm.bottom_radius = 0.034
	cm.height = 0.05
	cuff.rotation.x = PI / 2
	cuff.position = Vector3(0.004 * mir, -0.004, 0.095)
	add_child(cuff)
	# shirt sleeve running back toward the elbow (out of view), angled slightly down like a relaxed wrist
	var sleeve := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.034
	sm.bottom_radius = 0.042
	sm.height = 0.26
	sleeve.mesh = sm
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.86, 0.82, 0.74)
	cloth.roughness = 0.9
	var cp := "res://assets/ext/packed/cloth_linen_ah.png"
	if ResourceLoader.exists(cp):
		cloth.albedo_texture = load(cp)
		cloth.uv1_triplanar = true
		cloth.uv1_scale = Vector3(8, 8, 8)
	sleeve.material_override = cloth
	sleeve.rotation.x = PI / 2 - 0.18
	sleeve.position = Vector3(0.004 * mir, -0.03, 0.235)
	add_child(sleeve)
	var lens := [[0.042, 0.026, 0.021], [0.047, 0.029, 0.023], [0.044, 0.027, 0.022], [0.035, 0.021, 0.019]]
	for i in 4:
		var root := Node3D.new()
		root.position = Vector3(0.0, 0.032 - i * 0.021, -0.012)
		add_child(root)
		var segs := []
		var parent: Node3D = root
		for k in 3:
			var seg := Node3D.new()
			parent.add_child(seg)
			var mi := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.0095 - k * 0.001
			cap.height = float(lens[i][k]) + cap.radius
			mi.mesh = cap
			mi.material_override = _mat
			mi.rotation.x = PI / 2
			mi.position.z = -float(lens[i][k]) * 0.5
			seg.add_child(mi)
			segs.append(seg)
			var nxt := Node3D.new()
			nxt.position.z = -float(lens[i][k])
			seg.add_child(nxt)
			parent = nxt
		_fingers.append([segs, "index" if i == 0 else "grip"])
	# thumb: from the inside of the palm, angled forward and up
	var troot := Node3D.new()
	troot.position = Vector3(-0.012 * mir, 0.03, 0.03)
	troot.rotation = Vector3(0.5, 0.55 * mir, 0.0)
	add_child(troot)
	var tp: Node3D = troot
	for k in 2:
		var seg2 := Node3D.new()
		tp.add_child(seg2)
		var mi2 := MeshInstance3D.new()
		var cap2 := CapsuleMesh.new()
		cap2.radius = 0.011
		cap2.height = 0.04
		mi2.mesh = cap2
		mi2.material_override = _mat
		mi2.rotation.x = PI / 2
		mi2.position.z = -0.016
		seg2.add_child(mi2)
		_thumb_segs.append(seg2)
		var n2 := Node3D.new()
		n2.position.z = -0.032
		seg2.add_child(n2)
		tp = n2

## Read the controller each frame (XRController3D parent) unless values are pushed by the owner.
func _process(dt: float) -> void:
	var c := get_parent() as XRController3D
	if c != null and c.get_is_active():
		var t := XRServer.get_tracker(c.tracker) as XRPositionalTracker
		if t != null:
			var pg := t.get_pose(c.pose)
			var pa := t.get_pose(&"aim")
			if pg != null and pa != null and pa.has_tracking_data:
				rel = (pg.transform.basis.orthonormalized().inverse() * pa.transform.basis.orthonormalized()).orthonormalized()
		transform = Transform3D(rel, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -fist())
		grip = c.get_float(&"grip")
		trigger = c.get_float(&"trigger")
		thumb = 1.0 if (c.is_button_pressed(&"primary_touch") or c.is_button_pressed(&"ax_touch") or c.is_button_pressed(&"by_touch")) else 0.0
	var mir := 1.0 if side == "right" else -1.0
	var k := 1.0 - exp(-24.0 * dt)
	for f in _fingers:
		var segs: Array = f[0]
		var amt: float
		if f[1] == "index":
			amt = lerpf(0.15, 0.55, trigger) if holding else trigger * 0.85
		else:
			amt = 0.92 if holding else grip * 0.95
		for j in segs.size():
			var target: float = amt * [1.35, 1.6, 1.0][j]
			var key: Node3D = segs[j]
			var cur: float = _cur.get(key, 0.0)
			cur = lerpf(cur, target, k)
			_cur[key] = cur
			# curl toward the palm side (about Y): -Z swings toward -X (right) / +X (left)
			key.rotation = Vector3(0.0, cur * mir, 0.0)
	var tamt := maxf(thumb, 0.6 if holding else grip * 0.5)
	for j in _thumb_segs.size():
		(_thumb_segs[j] as Node3D).rotation = Vector3(0.0, tamt * 0.6 * mir, 0.0)
