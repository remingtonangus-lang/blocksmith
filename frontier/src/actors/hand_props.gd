class_name HandProps
extends RefCounted
## Small things people hold, built procedurally (original geometry, flat PBR materials) and parented to a hand bone
## with BoneAttachment3D: a whiskey glass or beer schooner at the bar, a broom for a storekeeper sweeping the
## boardwalk, a newspaper on a bench, a fan of cards at the card table, a hammer at the forge, a coffee cup, a ledger.
##   HandProps.hold(visual, kind, hand := "right")   kind "" clears that hand
## Offsets are in the hand bone's frame (Y along the fingers, X across the palm); tuned on the town pose sheet
## (src/tests/town_poses.gd).

const KINDS := {
	# kind: [hand, offset transform builder name]
	"glass": "right", "schooner": "right", "broom": "right", "newspaper": "left", "cards": "left", "hammer": "right",
	"cup": "right", "ledger": "left", "bottle": "right", "cigar": "right",
}

static var _meshes := {}
static var _mats := {}

static func hold(visual: Node, kind: String, hand := "") -> void:
	if visual == null or not (visual is FrontierCharacter):
		return
	var ch := visual as FrontierCharacter
	var sk: Skeleton3D = ch.skeleton
	if sk == null:
		return
	if hand == "":
		hand = KINDS.get(kind, "right")
	var bone := "RightHand" if hand == "right" else "LeftHand"
	var node_name := "HandProp_" + hand
	var old := sk.get_node_or_null(node_name)
	if kind == "":
		if old:
			old.queue_free()
		return
	if old and old.get_meta("kind", "") == kind:
		return
	if old:
		old.free()
	var bi := sk.find_bone(bone)
	if bi < 0:
		return
	var att := BoneAttachment3D.new()
	att.name = node_name
	att.bone_name = bone
	att.set_meta("kind", kind)
	sk.add_child(att)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = _offset(kind, hand)
	att.add_child(mi)

static func held(visual: Node, hand := "right") -> String:
	if visual == null or not (visual is FrontierCharacter) or (visual as FrontierCharacter).skeleton == null:
		return ""
	var n := (visual as FrontierCharacter).skeleton.get_node_or_null("HandProp_" + hand)
	return str(n.get_meta("kind", "")) if n else ""

static func clear(visual: Node) -> void:
	hold(visual, "", "right")
	hold(visual, "", "left")

## Grip frames: the hand bone's +Y runs along the fingers; the grip sits ~8 cm out from the wrist in the palm (-Z of
## the bone for these rigs is the palm side). Mirrored for the left hand.
static func _offset(kind: String, hand: String) -> Transform3D:
	var m := -1.0 if hand == "left" else 1.0
	var t := Transform3D.IDENTITY
	match kind:
		"glass", "cup", "schooner":
			# upright vessel across the palm: axis along the bone's X (thumb side up when the hand is vertical)
			t = Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5 * m), Vector3(0.02 * m, 0.08, 0.035))
		"bottle":
			t = Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5 * m), Vector3(0.02 * m, 0.08, 0.035))
		"broom":
			# handle through the fist, running on along the fingers: down past the feet when the arm hangs
			t = Transform3D(Basis(Vector3(1, 0, 0), PI - 0.35), Vector3(0.0, 0.07, 0.03))
		"hammer":
			t = Transform3D(Basis(Vector3(1, 0, 0), PI - 0.2), Vector3(0.0, 0.06, 0.03))
		"newspaper", "ledger":
			# opened page held up in front (pairs with the "read" pose)
			t = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5 * m), Vector3(0.12 * m, 0.1, 0.05))
		"cards":
			t = Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0.0, 0.09, 0.04))
		"cigar":
			t = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.0, 0.1, 0.02))
	return t

static func _mat(key: String, col: Color, rough := 0.7, metal := 0.0, alpha := 1.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.roughness = rough
	m.metallic = metal
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m

static func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh := ArrayMesh.new()
	match kind:
		"glass":
			_cyl(mesh, 0.032, 0.028, 0.085, Vector3.ZERO, _mat("glass", Color(0.8, 0.85, 0.82), 0.05, 0.0, 0.45))
			_cyl(mesh, 0.026, 0.026, 0.03, Vector3(0, 0.006, 0), _mat("whiskey", Color(0.55, 0.3, 0.08), 0.1, 0.0, 0.85))
		"schooner":
			_cyl(mesh, 0.04, 0.034, 0.15, Vector3.ZERO, _mat("glass", Color(0.8, 0.85, 0.82), 0.05, 0.0, 0.45))
			_cyl(mesh, 0.036, 0.032, 0.11, Vector3(0, 0.005, 0), _mat("beer", Color(0.78, 0.5, 0.12), 0.15, 0.0, 0.85))
		"cup":
			_cyl(mesh, 0.04, 0.035, 0.08, Vector3.ZERO, _mat("enamel", Color(0.75, 0.78, 0.8), 0.35))
		"bottle":
			_cyl(mesh, 0.035, 0.035, 0.2, Vector3(0, -0.06, 0), _mat("bottle", Color(0.22, 0.32, 0.16), 0.08, 0.0, 0.8))
			_cyl(mesh, 0.012, 0.016, 0.08, Vector3(0, 0.14, 0), _mat("bottle", Color(0.22, 0.32, 0.16), 0.08, 0.0, 0.8))
		"broom":
			_cyl(mesh, 0.014, 0.014, 1.3, Vector3(0, -0.95, 0), _mat("wood", Color(0.55, 0.42, 0.28), 0.8))
			_cyl(mesh, 0.09, 0.03, 0.32, Vector3(0, -1.25, 0), _mat("straw", Color(0.78, 0.66, 0.38), 0.95))
		"hammer":
			_cyl(mesh, 0.013, 0.013, 0.34, Vector3(0, -0.04, 0), _mat("wood", Color(0.55, 0.42, 0.28), 0.8))
			_box(mesh, Vector3(0.11, 0.035, 0.035), Vector3(0, 0.14, 0), _mat("iron", Color(0.18, 0.17, 0.16), 0.5, 0.8))
		"newspaper":
			_box(mesh, Vector3(0.3, 0.004, 0.42), Vector3.ZERO, _mat("paper", Color(0.86, 0.83, 0.74), 0.95))
		"ledger":
			_box(mesh, Vector3(0.2, 0.03, 0.28), Vector3.ZERO, _mat("leather", Color(0.32, 0.14, 0.1), 0.7))
		"cards":
			for i in 5:
				var a := (i - 2) * 0.22
				var b := Basis(Vector3.UP, a)
				_box(mesh, Vector3(0.063, 0.002, 0.088), b * Vector3(0, 0.0, 0.03) + Vector3(0, i * 0.0015, 0),
					_mat("card", Color(0.93, 0.91, 0.86), 0.6), b)
		"cigar":
			_cyl(mesh, 0.008, 0.008, 0.12, Vector3.ZERO, _mat("cigar", Color(0.35, 0.22, 0.12), 0.9))
	_meshes[kind] = mesh
	return mesh

static func _cyl(mesh: ArrayMesh, r0: float, r1: float, h: float, base: Vector3, mat: Material) -> void:
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 1
	_append(mesh, cm, Transform3D(Basis.IDENTITY, base + Vector3(0, h * 0.5, 0)), mat)

static func _box(mesh: ArrayMesh, size: Vector3, c: Vector3, mat: Material, b := Basis.IDENTITY) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_append(mesh, bm, Transform3D(b, c), mat)

static func _append(mesh: ArrayMesh, src: PrimitiveMesh, xf: Transform3D, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.append_from(src, 0, xf)
	st.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
