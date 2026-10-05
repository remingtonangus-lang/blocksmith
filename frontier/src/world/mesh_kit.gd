class_name MeshKit
extends RefCounted
## Static geometry builder for the settlement kit. Geometry goes into per-material buckets (packed arrays, no
## per-vertex SurfaceTool calls) and is committed as one ArrayMesh with one surface per material.
##
## Conventions (shared by building_gen.gd and shaders/building.gdshader):
##   * Callers work in a local frame (a building's: x along the frontage, y up from the floor, -z towards the street);
##     `xf` maps local -> mesh space (world space for settlement meshes).
##   * UVs are in METRES of the local frame so texture scale is set per material (tile size in the shader) and
##     continues across a whole wall. Walls: u runs horizontally along the face, v runs down the face. Horizontal
##     faces: u = local x, v = local z. `uv_rot` swaps u/v (vertical boards from a horizontal-board texture).
##   * UV2.x = height above the building's ground (dirt/splash near the ground), UV2.y = per-building seed.
##   * COLOR.rgb = paint tint (shader mixes it in by the material's tint amount), COLOR.a = weathering 0..1.
##   * Quads are given counter-clockwise as seen from the front; Godot's front faces are clockwise, handled here.

var buckets := {}                 # key -> [verts, normals, uvs, uv2s, colors, indices]
var xf := Transform3D.IDENTITY
var tint := Color(1, 1, 1, 0.3)
var seed := 0.0
var ground := 0.0                 # local y of the ground (UV2.x = local y - ground)
var uv_rot := false
var uv_off := Vector2.ZERO
var tris := 0

const F_PX := 1
const F_NX := 2
const F_PY := 4
const F_NY := 8
const F_PZ := 16
const F_NZ := 32
const F_ALL := 63
const F_SIDES := F_PX | F_NX | F_PZ | F_NZ

func _bucket(key: String) -> Array:
	var b = buckets.get(key)
	if b == null:
		b = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedVector2Array(), PackedColorArray(), PackedInt32Array()]
		buckets[key] = b
	return b

func is_empty() -> bool:
	for k in buckets:
		if not buckets[k][5].is_empty():
			return false
	return true

## Planar UV of local point p on a face with local normal n (metres), see header.
func _uv(p: Vector3, n: Vector3) -> Vector2:
	var uv: Vector2
	if absf(n.y) > 0.97:
		uv = Vector2(p.x, p.z)
	else:
		var u := Vector3(-n.z, 0.0, n.x).normalized()
		var v := n.cross(u)
		uv = Vector2(p.dot(u), p.dot(v))
	if uv_rot:
		uv = Vector2(uv.y, uv.x)
	return uv + uv_off

## Quad p0..p3 counter-clockwise seen from the front.
func quad(key: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	var n := (p1 - p0).cross(p3 - p0)
	if n.length_squared() < 1e-12:
		n = (p2 - p1).cross(p0 - p1)
		if n.length_squared() < 1e-12:
			return
	n = n.normalized()
	var b := _bucket(key)
	var base: int = b[0].size()
	var wn := (xf.basis * n).normalized()
	var c := tint
	for p in [p0, p1, p2, p3]:
		b[0].append(xf * p)
		b[1].append(wn)
		b[2].append(_uv(p, n))
		b[3].append(Vector2(p.y - ground, seed))
		b[4].append(c)
	b[5].append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	tris += 2

## Quad with explicit UVs (glyphs, decals). UV2 still carries height above ground and the seed.
func quad_uv(key: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t0: Vector2, t1: Vector2, t2: Vector2, t3: Vector2) -> void:
	var n := (p1 - p0).cross(p3 - p0)
	if n.length_squared() < 1e-14:
		return
	var b := _bucket(key)
	var base: int = b[0].size()
	var wn := (xf.basis * n).normalized()
	b[0].append(xf * p0)
	b[0].append(xf * p1)
	b[0].append(xf * p2)
	b[0].append(xf * p3)
	for i in 4:
		b[1].append(wn)
		b[4].append(tint)
	b[2].append(t0)
	b[2].append(t1)
	b[2].append(t2)
	b[2].append(t3)
	b[3].append(Vector2(p0.y - ground, seed))
	b[3].append(Vector2(p1.y - ground, seed))
	b[3].append(Vector2(p2.y - ground, seed))
	b[3].append(Vector2(p3.y - ground, seed))
	b[5].append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	tris += 2

func tri(key: String, p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	var n := (p1 - p0).cross(p2 - p0)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var b := _bucket(key)
	var base: int = b[0].size()
	var wn := (xf.basis * n).normalized()
	for p in [p0, p1, p2]:
		b[0].append(xf * p)
		b[1].append(wn)
		b[2].append(_uv(p, n))
		b[3].append(Vector2(p.y - ground, seed))
		b[4].append(tint)
	b[5].append_array(PackedInt32Array([base, base + 2, base + 1]))
	tris += 1

## Face from an origin and two edge vectors (normal = du x dv).
func face(key: String, o: Vector3, du: Vector3, dv: Vector3) -> void:
	quad(key, o, o + du, o + du + dv, o + dv)

## Axis-aligned box between corners a and b (local frame). `faces` masks which faces to emit.
func box(key: String, a: Vector3, b: Vector3, faces: int = F_ALL) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var w := hi.x - lo.x
	var h := hi.y - lo.y
	var d := hi.z - lo.z
	# vertical members (posts, casings, corner boards): grain runs up the piece
	var saved_rot := uv_rot
	if h > 2.5 * maxf(w, d) and h > 0.3:
		uv_rot = not uv_rot
	_box_faces(key, lo, hi, w, h, d, faces)
	uv_rot = saved_rot

func _box_faces(key: String, lo: Vector3, hi: Vector3, w: float, h: float, d: float, faces: int) -> void:
	if faces & F_PX:
		face(key, Vector3(hi.x, lo.y, hi.z), Vector3(0, 0, -d), Vector3(0, h, 0))
	if faces & F_NX:
		face(key, Vector3(lo.x, lo.y, lo.z), Vector3(0, 0, d), Vector3(0, h, 0))
	if faces & F_PZ:
		face(key, Vector3(lo.x, lo.y, hi.z), Vector3(w, 0, 0), Vector3(0, h, 0))
	if faces & F_NZ:
		face(key, Vector3(hi.x, lo.y, lo.z), Vector3(-w, 0, 0), Vector3(0, h, 0))
	if faces & F_PY:
		face(key, Vector3(lo.x, hi.y, hi.z), Vector3(w, 0, 0), Vector3(0, 0, -d))
	if faces & F_NY:
		face(key, Vector3(lo.x, lo.y, lo.z), Vector3(w, 0, 0), Vector3(0, 0, d))

## Box from centre and size.
func cbox(key: String, c: Vector3, s: Vector3, faces: int = F_ALL) -> void:
	box(key, c - s * 0.5, c + s * 0.5, faces)

## General hexahedron: c[0..3] bottom (x-z-, x+z-, x+z+, x-z+), c[4..7] top in the same order.
func hexa(key: String, c: Array, faces: int = F_ALL) -> void:
	if faces & F_NZ:
		quad(key, c[1], c[0], c[4], c[5])
	if faces & F_PZ:
		quad(key, c[3], c[2], c[6], c[7])
	if faces & F_PX:
		quad(key, c[2], c[1], c[5], c[6])
	if faces & F_NX:
		quad(key, c[0], c[3], c[7], c[4])
	if faces & F_PY:
		quad(key, c[7], c[6], c[5], c[4])
	if faces & F_NY:
		quad(key, c[0], c[1], c[2], c[3])

## A box rotated about its own centre (Basis) — braces, fallen beams, rafters.
func obox(key: String, c: Vector3, s: Vector3, rot: Basis, faces: int = F_ALL) -> void:
	var h := s * 0.5
	var pts := []
	for k in [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1),
			Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
		pts.append(c + rot * (k * h))
	hexa(key, pts, faces)

## Square beam from a to b (cross-section w x h, h measured along `up`).
func beam(key: String, a: Vector3, b: Vector3, w: float, h: float = -1.0, up := Vector3.UP) -> void:
	if h < 0.0:
		h = w
	var ax := b - a
	var L := ax.length()
	if L < 1e-4:
		return
	var z := ax / L
	var x := up.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	obox(key, (a + b) * 0.5, Vector3(w, h, L), Basis(x, y, z))

## Vertical-axis cylinder (or any axis via a->b) with `sides` facets; caps optional.
func cyl(key: String, a: Vector3, b: Vector3, r: float, sides: int = 8, caps := true, r2: float = -1.0) -> void:
	if r2 < 0.0:
		r2 = r
	var ax := b - a
	var L := ax.length()
	if L < 1e-4:
		return
	var z := ax / L
	var x := Vector3.UP.cross(z) if absf(z.y) < 0.95 else Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	var ring_a := []
	var ring_b := []
	for i in sides:
		var t := TAU * float(i) / sides
		var d := x * cos(t) + y * sin(t)
		ring_a.append(a + d * r)
		ring_b.append(b + d * r2)
	for i in sides:
		var j := (i + 1) % sides
		quad(key, ring_a[j], ring_a[i], ring_b[i], ring_b[j])
	if caps:
		for i in range(1, sides - 1):
			tri(key, ring_a[0], ring_a[i + 1], ring_a[i])
			tri(key, ring_b[0], ring_b[i], ring_b[i + 1])

## Append arbitrary triangle arrays (e.g. TextMesh glyphs) transformed by `local` (local frame).
func add_arrays(key: String, arrays: Array, local: Transform3D, col: Color) -> void:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if v.is_empty():
		return
	var nr: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx = arrays[Mesh.ARRAY_INDEX]
	var b := _bucket(key)
	var base: int = b[0].size()
	var m := xf * local
	var nb := m.basis.orthonormalized()
	for i in v.size():
		var p: Vector3 = local * v[i]
		b[0].append(m * v[i])
		b[1].append((nb * nr[i]).normalized())
		b[2].append(Vector2(p.x, -p.y))
		b[3].append(Vector2(p.y - ground, seed))
		b[4].append(col)
	# PrimitiveMesh arrays already use Godot's clockwise winding
	if idx == null or idx.is_empty():
		for i in v.size():
			b[5].append(base + i)
	else:
		for i in idx.size():
			b[5].append(base + idx[i])
	tris += v.size() / 3

## Commit every bucket as a surface. mats: key -> Material. Tangents via mikktspace for normal-mapped keys.
## Fold the untextured vertex-colour buckets (TownMats.VC: iron, brass, bottle, cloth, water, mirror) into one
## "vc" bucket: colour *= the material's base colour, UV = (roughness, metallic). Saves a draw call per material.
func merge_vc() -> void:
	for key in TownMats.VC:
		if not buckets.has(key):
			continue
		var src: Array = buckets[key]
		var spec: Array = TownMats.VC[key]
		var base_col: Color = spec[0]
		var uvv := Vector2(spec[1], spec[2])
		var dst := _bucket("vc")
		var base: int = dst[0].size()
		dst[0].append_array(src[0])
		dst[1].append_array(src[1])
		var n: int = src[0].size()
		var uvs := PackedVector2Array()
		uvs.resize(n)
		uvs.fill(uvv)
		dst[2].append_array(uvs)
		dst[3].append_array(src[3])
		var cols: PackedColorArray = src[4]
		for i in n:
			var c: Color = cols[i]
			dst[4].append(Color(c.r * base_col.r, c.g * base_col.g, c.b * base_col.b, 1.0))
		var idx: PackedInt32Array = src[5]
		for i in idx.size():
			dst[5].append(idx[i] + base)
		buckets.erase(key)

func commit(mats: Dictionary, no_tangent_keys: Array = []) -> ArrayMesh:
	merge_vc()
	var mesh := ArrayMesh.new()
	var keys := buckets.keys()
	keys.sort()
	for key in keys:
		var b: Array = buckets[key]
		if b[5].is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = b[0]
		arr[Mesh.ARRAY_NORMAL] = b[1]
		arr[Mesh.ARRAY_TEX_UV] = b[2]
		arr[Mesh.ARRAY_TEX_UV2] = b[3]
		arr[Mesh.ARRAY_COLOR] = b[4]
		arr[Mesh.ARRAY_INDEX] = b[5]
		if not no_tangent_keys.has(key) and not key.begins_with("text_"):
			var st := SurfaceTool.new()
			st.create_from_arrays(arr)
			st.generate_tangents()
			arr = st.commit_to_arrays()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var si := mesh.get_surface_count() - 1
		mesh.surface_set_name(si, key)
		if mats.has(key):
			mesh.surface_set_material(si, mats[key])
	return mesh

## Position-only single-surface copy of every opaque bucket, for a SHADOWS_ONLY proxy: the shadow passes then
## draw one surface per cell instead of one per material.
func commit_shadow(skip_keys: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for key in buckets:
		if skip_keys.has(key) or str(key).begins_with("text_"):
			continue
		var b: Array = buckets[key]
		var base := verts.size()
		verts.append_array(b[0])
		var src: PackedInt32Array = b[5]
		var off := PackedInt32Array()
		off.resize(src.size())
		for i in src.size():
			off[i] = src[i] + base
		idx.append_array(off)
	var mesh := ArrayMesh.new()
	if idx.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

func vertex_count() -> int:
	var n := 0
	for k in buckets:
		n += buckets[k][0].size()
	return n
