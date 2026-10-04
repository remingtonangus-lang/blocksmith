class_name Kit
extends RefCounted
## Mesh kit for the Capital's architecture: plan profiles (chamfered rectangles, octagons, rounded rectangles,
## ellipses, lenses) and builders for prisms, tubes, discs and boxes. Facade parameters travel in vertex COLOR:
## r = facade style (see building.gdshader), g = per-building seed, b = floor height / 8, a = lights allowed.
## UV = (metres along the perimeter, metres of height) so the facade shader lays out floors and mullions.

enum { GLASS, BANDED, STONE, TRIM, METAL, GARDEN, PAD, DARKGLASS, CONCRETE, OLIVE, RUST }
const STYLE_V := {GLASS: 0.03, BANDED: 0.12, STONE: 0.21, TRIM: 0.3, METAL: 0.39, GARDEN: 0.48, PAD: 0.57,
	DARKGLASS: 0.66, CONCRETE: 0.75, OLIVE: 0.84, RUST: 0.93}

var st := SurfaceTool.new()
var verts := 0


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


func commit(mesh: ArrayMesh = null) -> ArrayMesh:
	if verts == 0:
		return mesh
	st.generate_tangents()
	return st.commit(mesh)


# --------------------------------------------------------------------------------------------- profiles

static func rect(w: float, d: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-w, -d) * 0.5, Vector2(w, -d) * 0.5, Vector2(w, d) * 0.5, Vector2(-w, d) * 0.5])


static func chamfer_rect(w: float, d: float, c: float) -> PackedVector2Array:
	var hw := w * 0.5
	var hd := d * 0.5
	c = minf(c, minf(hw, hd) * 0.9)
	return PackedVector2Array([Vector2(-hw + c, -hd), Vector2(hw - c, -hd), Vector2(hw, -hd + c), Vector2(hw, hd - c),
		Vector2(hw - c, hd), Vector2(-hw + c, hd), Vector2(-hw, hd - c), Vector2(-hw, -hd + c)])


static func rounded_rect(w: float, d: float, r: float, seg: int = 4) -> PackedVector2Array:
	var hw := w * 0.5
	var hd := d * 0.5
	r = minf(r, minf(hw, hd) * 0.95)
	var out := PackedVector2Array()
	var corners := [Vector2(hw - r, -hd + r), Vector2(hw - r, hd - r), Vector2(-hw + r, hd - r), Vector2(-hw + r, -hd + r)]
	var start := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for k in 4:
		for i in seg + 1:
			var a: float = start[k] + PI * 0.5 * i / seg
			out.append(corners[k] + Vector2(cos(a), sin(a)) * r)
	return out


static func ngon(r: float, n: int, rot: float = 0.0, sx: float = 1.0, sz: float = 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := rot + TAU * i / n
		out.append(Vector2(cos(a) * r * sx, sin(a) * r * sz))
	return out


static func lens(w: float, d: float, seg: int = 10) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in seg:
		var t := float(i) / seg
		out.append(Vector2(lerpf(-w * 0.5, w * 0.5, t), -sin(t * PI) * d * 0.5))
	for i in seg:
		var t := float(i) / seg
		out.append(Vector2(lerpf(w * 0.5, -w * 0.5, t), sin(t * PI) * d * 0.5))
	return out


static func scaled(p: PackedVector2Array, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in p:
		out.append(v * s)
	return out


static func inset(p: PackedVector2Array, d: float) -> PackedVector2Array:
	var r: Array = Geometry2D.offset_polygon(p, -d, Geometry2D.JOIN_MITER)
	return r[0] if r.size() > 0 else p


static func perimeter(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		s += p[i].distance_to(p[(i + 1) % p.size()])
	return s


# ---------------------------------------------------------------------------------------------- builders

func _v(p: Vector3, n: Vector3, uv: Vector2, col: Color) -> void:
	st.set_color(col)
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)
	verts += 1


func col(style: int, seed: float, floor_h: float = 4.0, lights: bool = true) -> Color:
	return Color(STYLE_V[style], seed, floor_h / 8.0, 1.0 if lights else 0.0)


## Walls of a vertical prism over a plan profile (counter-clockwise seen from above, in the xz plane), at `xf`.
func prism(xf: Transform3D, prof: PackedVector2Array, y0: float, y1: float, c: Color, cap_top: bool = true, cap_bottom: bool = false, top_col: Color = Color(-1, 0, 0)) -> void:
	var n := prof.size()
	var u := 0.0
	# Orientation: make the polygon clockwise in (x, z) so the walls face out with Godot's winding.
	var ccw := Geometry2D.is_polygon_clockwise(prof)
	var pts := prof if ccw else _reversed(prof)
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var len := a.distance_to(b)
		var e := (b - a).normalized()
		var nrm := xf.basis * Vector3(e.y, 0.0, -e.x)
		nrm = nrm.normalized()
		var p0 := xf * Vector3(a.x, y0, a.y)
		var p1 := xf * Vector3(b.x, y0, b.y)
		var p2 := xf * Vector3(b.x, y1, b.y)
		var p3 := xf * Vector3(a.x, y1, a.y)
		var uv0 := Vector2(u, y0)
		var uv1 := Vector2(u + len, y0)
		var uv2 := Vector2(u + len, y1)
		var uv3 := Vector2(u, y1)
		_v(p0, nrm, uv0, c); _v(p1, nrm, uv1, c); _v(p2, nrm, uv2, c)
		_v(p0, nrm, uv0, c); _v(p2, nrm, uv2, c); _v(p3, nrm, uv3, c)
		u += len
	var tc := c if top_col.r < 0.0 else top_col
	if cap_top:
		cap(xf, prof, y1, true, tc)
	if cap_bottom:
		cap(xf, prof, y0, false, c)


func _reversed(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(p.size() - 1, -1, -1):
		out.append(p[i])
	return out


## A flat cap over the profile at height y (facing up or down).
func cap(xf: Transform3D, prof: PackedVector2Array, y: float, up: bool, c: Color) -> void:
	var tri := Geometry2D.triangulate_polygon(prof)
	if tri.is_empty():
		return
	var nrm := (xf.basis * (Vector3.UP if up else Vector3.DOWN)).normalized()
	var cw := Geometry2D.is_polygon_clockwise(prof)
	for k in range(0, tri.size(), 3):
		var ids := [tri[k], tri[k + 1], tri[k + 2]]
		# Godot front faces are clockwise from the viewer.
		var flip := (cw == up)
		if flip:
			ids = [tri[k], tri[k + 2], tri[k + 1]]
		for id in ids:
			var p: Vector2 = prof[id]
			_v(xf * Vector3(p.x, y, p.y), nrm, Vector2(p.x, p.y), c)


## A ring band (frame) around a profile: an outer prism slightly larger than the facade.
func band(xf: Transform3D, prof: PackedVector2Array, y: float, h: float, out: float, c: Color, caps: bool = true) -> void:
	var p2 := inset(prof, -out)
	prism(xf, p2, y, y + h, c, caps, caps)


## An axis-aligned box (centre, size) under a transform.
func box(xf: Transform3D, center: Vector3, size: Vector3, c: Color) -> void:
	var t := xf * Transform3D(Basis.IDENTITY, center)
	prism(t, rect(size.x, size.z), -size.y * 0.5, size.y * 0.5, c, true, true)


## A cylinder/tube between two points (sides n), with optional end caps.
func tube(a: Vector3, b: Vector3, r: float, n: int, c: Color, caps: bool = false) -> void:
	var axis := b - a
	var len := axis.length()
	if len < 0.001:
		return
	var y := axis / len
	var ref := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	var xf := Transform3D(Basis(x, y, z), a)
	prism(xf, ngon(r, n), 0.0, len, c, caps, caps)


## A flat disc (cylinder) of radius r, thickness t, top at y.
func disc(center: Vector3, r: float, t: float, n: int, side: Color, top: Color) -> void:
	prism(Transform3D(Basis.IDENTITY, center), ngon(r, n), -t, 0.0, side, true, true, top)


## A dome (hemisphere) of radius r on a centre, `rings` x `seg` quads.
func dome(center: Vector3, r: float, rings: int, seg: int, c: Color, squash: float = 1.0) -> void:
	for j in rings:
		var a0 := PI * 0.5 * j / rings
		var a1 := PI * 0.5 * (j + 1) / rings
		for i in seg:
			var b0 := TAU * i / seg
			var b1 := TAU * (i + 1) / seg
			var p := []
			for ab in [[a0, b0], [a0, b1], [a1, b1], [a1, b0]]:
				var dir := Vector3(cos(ab[0]) * cos(ab[1]), sin(ab[0]) * squash, cos(ab[0]) * sin(ab[1]))
				p.append([center + dir * r, Vector3(dir.x, dir.y / maxf(squash, 0.01), dir.z).normalized(), Vector2(ab[1] * r, ab[0] * r)])
			for k in [0, 2, 1, 0, 3, 2]:
				_v(p[k][0], p[k][1], p[k][2], c)


## Low-poly sphere (for radar domes and the like).
func sphere(center: Vector3, r: float, rings: int, seg: int, c: Color) -> void:
	for j in rings:
		var a0 := -PI * 0.5 + PI * j / rings
		var a1 := -PI * 0.5 + PI * (j + 1) / rings
		for i in seg:
			var b0 := TAU * i / seg
			var b1 := TAU * (i + 1) / seg
			var p := []
			for ab in [[a0, b0], [a0, b1], [a1, b1], [a1, b0]]:
				var dir := Vector3(cos(ab[0]) * cos(ab[1]), sin(ab[0]), cos(ab[0]) * sin(ab[1]))
				p.append([center + dir * r, dir, Vector2(ab[1] * r, ab[0] * r)])
			for k in [0, 2, 1, 0, 3, 2]:
				_v(p[k][0], p[k][1], p[k][2], c)


## A quad from four corners (clockwise when seen from the front).
func quad(a: Vector3, b: Vector3, c2: Vector3, d: Vector3, c: Color) -> void:
	var n := (b - a).cross(d - a).normalized() * -1.0
	_v(a, n, Vector2(0, 0), c); _v(b, n, Vector2(a.distance_to(b), 0), c); _v(c2, n, Vector2(a.distance_to(b), a.distance_to(d)), c)
	_v(a, n, Vector2(0, 0), c); _v(c2, n, Vector2(a.distance_to(b), a.distance_to(d)), c); _v(d, n, Vector2(0, a.distance_to(d)), c)
