class_name BuildingGen
extends RefCounted
## The 1899 building kit. One instance builds one structure at a time from a spec (town_layout.gd) into shared
## sinks: `ext` (exterior + room shells, ~450 m), `inn` (interior furnishing, ~80 m), `far` (whole-town shell
## beyond ~450 m), prop transform lists for MultiMeshes, and one StaticBody3D of box collision per building.
## It also records what the town-life AI needs: doors, interaction spots, rooms and lights (see `rec`).
##
## Local frame of a building: x across the frontage (-w/2..w/2), z from the front wall (0) to the back (d),
## y up from the ground-floor level (0). The front faces -z (the street). Porches/boardwalks are at z < 0.
## Real proportions: doors 2.1-2.3 m, storeys 3.2-3.6 m, boardwalk ~0.45 m above the street with steps.

const STOREY := 3.6
const UPPER := 3.3
const T_WALL := 0.15
# interior wall finish by building type (the inner faces of every outer wall and the partitions)
const INNER := {"saloon": "wallpaper", "hotel": "wallpaper", "boarding": "planks_v", "bank": "plaster", "doctor": "plaster",
	"barber": "plaster", "church": "plaster", "school": "plaster", "post": "wallpaper", "land_office": "wallpaper",
	"newspaper": "planks_v", "house": "wallpaper", "restaurant": "wallpaper", "sheriff": "planks_v", "store": "planks_v",
	"gunsmith": "planks_v", "undertaker": "dark_planks", "butcher": "plaster", "depot": "planks_v", "assay": "planks_v"}
const DOOR_H := 2.15

const PAINTS := [Color(0.95, 0.93, 0.88), Color(0.95, 0.88, 0.70), Color(0.88, 0.74, 0.48), Color(0.62, 0.25, 0.18),
	Color(0.68, 0.74, 0.62), Color(0.76, 0.76, 0.74), Color(0.66, 0.72, 0.78), Color(0.58, 0.45, 0.33), Color(0.85, 0.80, 0.70)]
const TRIMS := [Color(0.96, 0.95, 0.9), Color(0.22, 0.32, 0.24), Color(0.35, 0.24, 0.16), Color(0.55, 0.18, 0.14),
	Color(0.18, 0.2, 0.22), Color(0.9, 0.86, 0.72)]
const WALLPAPERS := [Color(0.62, 0.7, 0.55), Color(0.85, 0.55, 0.45), Color(0.9, 0.8, 0.55), Color(0.6, 0.62, 0.75),
	Color(0.75, 0.5, 0.42), Color(0.88, 0.85, 0.7)]
const SIGN_BG := [Color(0.16, 0.2, 0.17), Color(0.92, 0.9, 0.84), Color(0.42, 0.14, 0.1), Color(0.12, 0.12, 0.14),
	Color(0.85, 0.78, 0.55), Color(0.2, 0.25, 0.35)]
const SIGN_FG := [Color(0.95, 0.88, 0.62), Color(0.12, 0.1, 0.09), Color(0.96, 0.92, 0.8), Color(0.85, 0.7, 0.35),
	Color(0.3, 0.1, 0.08), Color(0.95, 0.95, 0.9)]

var world: WorldData
var ext: MeshKit
var inn: MeshKit
var far: MeshKit
var props: Dictionary            # interior props: name -> Array[Transform3D] (world)
var oprops: Dictionary           # exterior props
var rec: Dictionary
var spec: Dictionary
var xf := Transform3D.IDENTITY   # local -> world
var rng := RandomNumberGenerator.new()
var floor_y := 0.0
var w := 8.0
var d := 12.0
var weather := 0.35
var col_wall := Color.WHITE
var col_trim := Color.WHITE
var mat_wall := "siding"
var mat_roof := "shingles"
var mat_in := "planks_v"
var col_in := Color(0.85, 0.72, 0.58)   # interior wall tint (wallpaper colour / stain)
var lit_rank := 0.5
var furnished := false
var _door_n := 0


# ------------------------------------------------------------------------------------------------ setup

## sinks: {ext, inn, far, props, oprops}. Returns the building record.
func begin(s: Dictionary, sinks: Dictionary) -> void:
	spec = s
	ext = sinks.ext
	inn = sinks.inn
	far = sinks.far
	props = sinks.props
	oprops = sinks.oprops
	xf = s.xf
	floor_y = xf.origin.y
	w = s.get("w", 8.0)
	d = s.get("d", 12.0)
	rng.seed = hash(s.id)
	weather = s.get("weather", 0.35)
	col_wall = s.get("paint", PAINTS[rng.randi() % PAINTS.size()])
	col_trim = s.get("trim", TRIMS[rng.randi() % TRIMS.size()])
	mat_wall = s.get("wall", "siding")
	mat_roof = s.get("roof", "shingles")
	mat_in = s.get("inner", INNER.get(s.get("interior", s.get("type", "")), "planks_v"))
	lit_rank = s.get("lit_rank", rng.randf())
	col_in = s.get("inner_tint", WALLPAPERS[rng.randi() % WALLPAPERS.size()] if mat_in == "wallpaper" else (Color(0.95, 0.92, 0.85) if mat_in == "plaster" else Color(0.8, 0.66, 0.52)))
	furnished = s.get("furnished", false)
	_door_n = 0
	var seedf := float(hash(s.id) % 1000) / 1000.0
	for k in [ext, inn, far]:
		k.xf = xf
		k.seed = seedf
		k.ground = ground_local(0.0, -0.5) if s.get("ground_ref", true) else -100.0
		k.uv_off = Vector2(rng.randf() * 3.0, rng.randf() * 3.0)
		k.uv_rot = false
	inn.ground = -100.0
	rec = {"id": s.id, "town": s.get("town", ""), "type": s.get("type", ""), "name": s.get("name", ""),
		"transform": xf, "size": Vector3(w, 0, d), "floor_y": floor_y, "doors": [], "spots": [], "rooms": [],
		"lights": [], "boxes": [], "body": null, "enterable": false, "storeys": s.get("storeys", 1),
		"hours": s.get("hours", [8.0, 18.0]), "role": s.get("role", "")}
	paint(col_wall)

func paint(c: Color, k: MeshKit = null) -> void:
	var col := Color(c.r, c.g, c.b, weather)
	if k != null:
		k.tint = col
	else:
		ext.tint = col
		inn.tint = Color(c.r, c.g, c.b, weather * 0.3)

func ground_local(lx: float, lz: float) -> float:
	var p := xf * Vector3(lx, 0.0, lz)
	return world.height(p.x, p.z) - floor_y

func ground_min(x0: float, z0: float, x1: float, z1: float) -> float:
	var m := INF
	for i in 4:
		for j in 4:
			m = minf(m, ground_local(lerpf(x0, x1, i / 3.0), lerpf(z0, z1, j / 3.0)))
	return m

func rand_pick(a: Array):
	return a[rng.randi() % a.size()]

# ------------------------------------------------------------------------------------------------ records

## Box collision in local coordinates.
func solid(a: Vector3, b: Vector3) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var s := hi - lo
	if s.x < 0.01 or s.y < 0.01 or s.z < 0.01:
		return
	solid_obb((lo + hi) * 0.5, s, Basis.IDENTITY)

func solid_obb(c: Vector3, s: Vector3, b: Basis) -> void:
	rec.boxes.append([Transform3D(b, c), s])

## Walkable ramp (stairs collision): from a (low end, top surface point) to b (high end), width w.
func ramp(a: Vector3, b: Vector3, width: float, thick := 0.3) -> void:
	var ax := b - a
	var L := ax.length()
	if L < 0.05:
		return
	var z := ax / L
	var x := Vector3.UP.cross(z).normalized()
	if x.length_squared() < 0.5:
		x = Vector3.RIGHT
	var y := z.cross(x).normalized()
	var c := (a + b) * 0.5 - y * thick * 0.5
	solid_obb(c, Vector3(width, thick, L), Basis(x, y, z))

## An interaction spot for town life. The actor stands at `pos` (local) and faces `face` (local direction).
func spot(type: String, pos: Vector3, face: Vector3, extra := {}) -> void:
	var f := Vector3(face.x, 0.0, face.z)
	var bas := Basis.IDENTITY
	if f.length_squared() > 1e-4:
		bas = Basis.looking_at(f.normalized(), Vector3.UP)
	var e := {"type": type, "transform": xf * Transform3D(bas, pos), "building": rec.id, "town": rec.town}
	e.merge(extra)
	rec.spots.append(e)

func light(pos: Vector3, kind: String, rng_m: float, energy: float, col := Color(1.0, 0.68, 0.36), shadow := false) -> void:
	rec.lights.append({"pos": xf * pos, "kind": kind, "range": rng_m, "energy": energy, "color": col, "shadow": shadow,
		"building": rec.id})

func room(name: String, x0: float, z0: float, x1: float, z1: float, y := 0.0) -> void:
	rec.rooms.append({"name": name, "rect": Rect2(x0, z0, x1 - x0, z1 - z0), "y": y, "floor_y": floor_y + y})

func prop(name: String, pos: Vector3, yaw_deg := 0.0, scale := 1.0, outside := false) -> void:
	if not TownProps.has(name):
		return
	var t := xf * Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(Vector3.ONE * scale), pos)
	var dict := oprops if outside else props
	if not dict.has(name):
		dict[name] = []
	dict[name].append(t)

# ------------------------------------------------------------------------------------------------ walls

## Wall frame: a straight wall from a to b (plan x,z), outside on the right of a->b.
func frame(a2: Vector2, b2: Vector2, t := T_WALL) -> Dictionary:
	var a := Vector3(a2.x, 0.0, a2.y)
	var b := Vector3(b2.x, 0.0, b2.y)
	var dir := (b - a)
	var L := dir.length()
	dir /= L
	return {"a": a, "dir": dir, "out": Vector3(-dir.z, 0.0, dir.x), "L": L, "t": t}

func fp(f: Dictionary, s: float, v: float, depth := 0.0) -> Vector3:
	return f.a + f.dir * s + Vector3.UP * v + f.out * depth

func fbasis(f: Dictionary) -> Basis:
	return Basis(f.dir, Vector3.UP, f.out)

static func _rects(L: float, y0: float, y1: float, ops: Array) -> Array:
	var xs := [0.0, L]
	for o in ops:
		xs.append(clampf(o.s0, 0.0, L))
		xs.append(clampf(o.s1, 0.0, L))
	xs.sort()
	var out := []
	for i in xs.size() - 1:
		var s0: float = xs[i]
		var s1: float = xs[i + 1]
		if s1 - s0 < 0.001:
			continue
		var mid := (s0 + s1) * 0.5
		var cov := []
		for o in ops:
			if o.s0 <= mid and mid <= o.s1:
				cov.append(o)
		cov.sort_custom(func(p, q): return p.v0 < q.v0)
		var cur := y0
		for o in cov:
			if o.v0 > cur + 0.001:
				out.append(Rect2(s0, cur, s1 - s0, minf(o.v0, y1) - cur))
			cur = maxf(cur, o.v1)
		if cur < y1 - 0.001:
			out.append(Rect2(s0, cur, s1 - s0, y1 - cur))
	return out

## Build a wall with openings. ops: [{s0, s1, v0, v1, kind: "door"|"window"|"open"}].
## mo/mi outer/inner materials ("" skips that face); reveals use `mr`.
func wall(f: Dictionary, y0: float, y1: float, ops: Array, mo: String, mi: String, mr := "", coll := true) -> void:
	var t: float = f.t
	if mr == "":
		mr = mo if mo != "" else mi
	var tint_out := ext.tint
	for r: Rect2 in _rects(f.L, y0, y1, ops):
		var p0 := fp(f, r.position.x, r.position.y)
		var du: Vector3 = f.dir * r.size.x
		var dv := Vector3.UP * r.size.y
		if mo != "":
			ext.tint = tint_out
			ext.face(mo, p0, du, dv)
		if mi != "":
			ext.tint = Color(col_in.r, col_in.g, col_in.b, 0.05)
			ext.face(mi, p0 - f.out * t + du, -du, dv)
	ext.tint = tint_out
	for o in ops:
		var W: float = o.s1 - o.s0
		var H: float = o.v1 - o.v0
		var ins: Vector3 = -f.out * t
		ext.face(mr, fp(f, o.s1, o.v1), -f.dir * W, ins)
		if o.v0 > y0 + 0.01:
			ext.face(mr, fp(f, o.s0, o.v0), f.dir * W, ins)
		ext.face(mr, fp(f, o.s0, o.v0), ins, Vector3.UP * H)
		ext.face(mr, fp(f, o.s1, o.v0), Vector3.UP * H, ins)
	if coll:
		var passes := []
		for o in ops:
			if o.kind == "door" or o.kind == "open":
				passes.append(o)
		var bas := fbasis(f)
		for r: Rect2 in _rects(f.L, y0, y1, passes):
			var c := fp(f, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5, -t * 0.5)
			solid_obb(c, Vector3(r.size.x, r.size.y, t), bas)

## Corner boards on a box-shaped shell (trim colour).
func corner_boards(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, wdt := 0.12) -> void:
	paint(col_trim)
	var sides := MeshKit.F_SIDES
	for c: Vector2 in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]:
		var sx := -1.0 if is_equal_approx(c.x, x0) else 1.0
		var sz := -1.0 if is_equal_approx(c.y, z0) else 1.0
		ext.box("paint", Vector3(c.x, y0, c.y + sz * 0.025), Vector3(c.x + sx * 0.025, y1, c.y - sz * wdt), sides)
		ext.box("paint", Vector3(c.x, y0, c.y), Vector3(c.x - sx * wdt, y1, c.y + sz * 0.025), sides)
	paint(col_wall)

## Window in a wall frame: casing, sill, head, sash with muntins, glass, optional shutters.
func window(f: Dictionary, s0: float, s1: float, v0: float, v1: float, style := "double_hung", shutters := false, trim_mat := "paint") -> void:
	var t: float = f.t
	var W := s1 - s0
	var H := v1 - v0
	var cw := 0.09
	paint(col_trim)
	var bas := fbasis(f)
	# casing (outside)
	if style != "adobe" and style != "none":
		_fbox(f, trim_mat, s0 - cw, s0, v0, v1 + cw, 0.0, 0.025)
		_fbox(f, trim_mat, s1, s1 + cw, v0, v1 + cw, 0.0, 0.025)
		_fbox(f, trim_mat, s0 - cw - 0.03, s1 + cw + 0.03, v1, v1 + cw + 0.04, 0.0, 0.04)
		if style == "fancy":
			_fbox(f, trim_mat, s0 - cw - 0.08, s1 + cw + 0.08, v1 + cw + 0.04, v1 + cw + 0.1, 0.0, 0.1)
	else:
		_fbox(f, "dark_planks", s0 - 0.12, s1 + 0.12, v1, v1 + 0.16, -0.05, 0.08)   # timber lintel
	if style != "none":
		_fbox(f, trim_mat, s0 - cw - 0.02, s1 + cw + 0.02, v0 - 0.045, v0, -t * 0.4, 0.06)   # sill
	# sash and glass at mid-depth
	var dg := -t * 0.5
	var bar := 0.045
	_fbox(f, trim_mat, s0, s1, v0, v0 + bar, dg - 0.02, dg + 0.02)
	_fbox(f, trim_mat, s0, s1, v1 - bar, v1, dg - 0.02, dg + 0.02)
	_fbox(f, trim_mat, s0, s0 + bar, v0, v1, dg - 0.02, dg + 0.02)
	_fbox(f, trim_mat, s1 - bar, s1, v0, v1, dg - 0.02, dg + 0.02)
	match style:
		"double_hung", "fancy":
			_fbox(f, trim_mat, s0, s1, (v0 + v1) * 0.5 - 0.025, (v0 + v1) * 0.5 + 0.025, dg - 0.03, dg + 0.03)
			_fbox(f, trim_mat, (s0 + s1) * 0.5 - 0.015, (s0 + s1) * 0.5 + 0.015, v0, v1, dg - 0.012, dg + 0.012)
		"small", "adobe":
			_fbox(f, trim_mat, s0, s1, (v0 + v1) * 0.5 - 0.015, (v0 + v1) * 0.5 + 0.015, dg - 0.012, dg + 0.012)
			_fbox(f, trim_mat, (s0 + s1) * 0.5 - 0.015, (s0 + s1) * 0.5 + 0.015, v0, v1, dg - 0.012, dg + 0.012)
		"display":
			if W > 2.2:
				_fbox(f, trim_mat, (s0 + s1) * 0.5 - 0.03, (s0 + s1) * 0.5 + 0.03, v0, v1, dg - 0.03, dg + 0.03)
		"tall":
			_fbox(f, trim_mat, s0, s1, v0 + H * 0.66 - 0.02, v0 + H * 0.66 + 0.02, dg - 0.02, dg + 0.02)
			_fbox(f, trim_mat, (s0 + s1) * 0.5 - 0.015, (s0 + s1) * 0.5 + 0.015, v0, v1, dg - 0.012, dg + 0.012)
	var rank := clampf(lit_rank + rng.randf_range(-0.18, 0.18), 0.0, 1.0)
	ext.tint = Color(rank, rng.randf(), 1.0 if furnished else 0.0, 1.0)
	ext.face("glass", fp(f, s0, v0, dg), f.dir * W, Vector3.UP * H)
	paint(col_wall)
	if shutters:
		var sc: Color = rand_pick([Color(0.2, 0.3, 0.22), Color(0.3, 0.2, 0.14), Color(0.25, 0.27, 0.3), Color(0.45, 0.18, 0.13)])
		paint(sc)
		var sw := W * 0.5 + 0.02
		_fbox(f, "boards_v", s0 - cw - sw, s0 - cw, v0 - 0.02, v1 + 0.02, 0.0, 0.035)
		_fbox(f, "boards_v", s1 + cw, s1 + cw + sw, v0 - 0.02, v1 + 0.02, 0.0, 0.035)
		for k in 3:
			var vv := v0 + H * (0.2 + 0.3 * k)
			_fbox(f, "boards_v", s0 - cw - sw, s0 - cw, vv, vv + 0.08, 0.035, 0.05)
			_fbox(f, "boards_v", s1 + cw, s1 + cw + sw, vv, vv + 0.08, 0.035, 0.05)
		paint(col_wall)

## Box in wall-frame coordinates (s along, v up, depth outwards from the wall's outer face).
func _fbox(f: Dictionary, key: String, s0: float, s1: float, v0: float, v1: float, d0: float, d1: float, k: MeshKit = null) -> void:
	if k == null:
		k = ext
	var c := fp(f, (s0 + s1) * 0.5, (v0 + v1) * 0.5, (d0 + d1) * 0.5)
	var s := Vector3(absf(s1 - s0), absf(v1 - v0), absf(d1 - d0))
	if absf(f.dir.x) > 0.999 or absf(f.dir.z) > 0.999:
		var hx: Vector3 = (f.dir * s.x + Vector3.UP * s.y + f.out * s.z) * 0.5
		var h := Vector3(absf(hx.x), absf(hx.y), absf(hx.z))
		k.box(key, c - h, c + h)
	else:
		k.obox(key, c, s, fbasis(f))

## Door opening with casing; registers a TownDoor. style: panel|plank|glazed|batwing. Returns door spec.
func door(f: Dictionary, sc: float, dw: float, dh := DOOR_H, style := "panel", double := false, transom := false, v0 := 0.0) -> Dictionary:
	var t: float = f.t
	var cw := 0.1
	paint(col_trim)
	_fbox(f, "paint", sc - dw * 0.5 - cw, sc - dw * 0.5, v0, v0 + dh + cw, 0.0, 0.03)
	_fbox(f, "paint", sc + dw * 0.5, sc + dw * 0.5 + cw, v0, v0 + dh + cw, 0.0, 0.03)
	var top := v0 + dh
	if transom:
		_fbox(f, "paint", sc - dw * 0.5, sc + dw * 0.5, top, top + 0.07, -t * 0.5 - 0.03, -t * 0.5 + 0.03)
		var rank := clampf(lit_rank + 0.05, 0.0, 1.0)
		ext.tint = Color(rank, rng.randf(), 1.0 if furnished else 0.0, 1.0)
		ext.face("glass", fp(f, sc - dw * 0.5, top + 0.07, -t * 0.5), f.dir * dw, Vector3.UP * 0.45)
		paint(col_trim)
		top += 0.52
	_fbox(f, "paint", sc - dw * 0.5 - cw - 0.03, sc + dw * 0.5 + cw + 0.03, top, top + cw + 0.04, 0.0, 0.045)
	_fbox(f, "planks_brown", sc - dw * 0.5, sc + dw * 0.5, v0 - 0.02, v0 + 0.015, -t, 0.04)   # threshold
	paint(col_wall)
	var bas := fbasis(f)
	# hinge frame: leaf extends along +X (= wall dir), -Z = outwards
	var hb := Basis(f.dir, Vector3.UP, -f.out)
	var leaves := []
	var lw := dw * 0.5 if double else dw
	var hinge0 := fp(f, sc - dw * 0.5, v0, -t * 0.5)
	leaves.append({"hinge": xf * Transform3D(hb, hinge0), "sign": 1.0, "w": lw})
	if double:
		var hinge1 := fp(f, sc + dw * 0.5, v0, -t * 0.5)
		leaves.append({"hinge": xf * Transform3D(hb, hinge1), "sign": -1.0, "w": lw})
	_door_n += 1
	var did := "%s/door%d" % [rec.id, _door_n]
	var dspec := {"id": did, "building": rec.id, "leaves": leaves, "h": dh if style != "batwing" else 1.2,
		"style": style, "kind": "batwing" if style == "batwing" else "hinged", "thick": 0.05,
		"bottom": v0 + (0.45 if style == "batwing" else 0.0),
		"col": Color(col_trim.r, col_trim.g, col_trim.b, weather), "outside": xf * fp(f, sc, v0, 0.9),
		"inside": xf * fp(f, sc, v0, -t - 0.9)}
	rec.doors.append(dspec)
	rec.enterable = true
	spot("door_out", fp(f, sc, v0, 0.8), -f.out, {"door": did})
	spot("door_in", fp(f, sc, v0, -t - 0.8), f.out, {"door": did})
	return dspec

# ------------------------------------------------------------------------------------------------ floors, roofs

func floor_slab(x0: float, z0: float, x1: float, z1: float, y: float, key := "floor", thick := 0.2, k: MeshKit = null, coll := true) -> void:
	if k == null:
		k = ext
	var saved := k.tint
	if key == "floor":
		k.tint = Color(0.8, 0.58, 0.4, 0.04)            # oiled floorboards indoors
	k.box(key, Vector3(x0, y - thick, z0), Vector3(x1, y, z1), MeshKit.F_PY)
	k.tint = saved
	if coll:
		solid(Vector3(x0, y - thick, z0), Vector3(x1, y, z1))

func ceiling(x0: float, z0: float, x1: float, z1: float, y: float, key := "planks_v") -> void:
	var saved := ext.tint
	ext.tint = Color(0.82, 0.76, 0.68, 0.04)
	ext.face(key, Vector3(x0, y, z0), Vector3(x1 - x0, 0, 0), Vector3(0, 0, z1 - z0))
	ext.tint = saved

## Foundation skirt from the floor down into the ground around a rectangle.
func skirt(x0: float, z0: float, x1: float, z1: float, top := 0.0, key := "planks_v", faces := MeshKit.F_SIDES) -> void:
	var g := ground_min(x0, z0, x1, z1) - 0.35
	if g >= top - 0.02:
		return
	ext.box(key, Vector3(x0, g, z0), Vector3(x1, top, z1), faces)
	solid(Vector3(x0, g, z0), Vector3(x1, top, z1))

## Gable roof. axis "z": ridge runs along z (gables at front/back); "x": ridge along x.
## Returns {ridge_y}. Gable triangles in `gmat` (inner face `gin`), fascia/barge boards in trim paint.
func gable_roof(x0: float, z0: float, x1: float, z1: float, eave: float, pitch_deg: float, axis := "z", oh := 0.45,
		key := "", gmat := "", gin := "", gable_front := true, gable_back := true) -> float:
	if key == "":
		key = mat_roof
	if gmat == "":
		gmat = mat_wall
	var th := 0.12
	var tn := tan(deg_to_rad(pitch_deg))
	if axis == "z":
		var xc := (x0 + x1) * 0.5
		var half := (x1 - x0) * 0.5
		var ridge := eave + half * tn
		var lo := eave - oh * tn
		var za := z0 - oh
		var zb := z1 + oh
		# left slope (-x), right slope (+x): underside points then top
		ext.hexa(key, [Vector3(x0 - oh, lo, za), Vector3(xc, ridge, za), Vector3(xc, ridge, zb), Vector3(x0 - oh, lo, zb),
			Vector3(x0 - oh, lo + th, za), Vector3(xc, ridge + th, za), Vector3(xc, ridge + th, zb), Vector3(x0 - oh, lo + th, zb)])
		ext.hexa(key, [Vector3(xc, ridge, za), Vector3(x1 + oh, lo, za), Vector3(x1 + oh, lo, zb), Vector3(xc, ridge, zb),
			Vector3(xc, ridge + th, za), Vector3(x1 + oh, lo + th, za), Vector3(x1 + oh, lo + th, zb), Vector3(xc, ridge + th, zb)])
		if gable_front:
			ext.tri(gmat, Vector3(x1, eave, z0), Vector3(x0, eave, z0), Vector3(xc, ridge, z0))
			if gin != "":
				ext.tri(gin, Vector3(x0, eave, z0 + T_WALL), Vector3(x1, eave, z0 + T_WALL), Vector3(xc, ridge, z0 + T_WALL))
		if gable_back:
			ext.tri(gmat, Vector3(x0, eave, z1), Vector3(x1, eave, z1), Vector3(xc, ridge, z1))
			if gin != "":
				ext.tri(gin, Vector3(x1, eave, z1 - T_WALL), Vector3(x0, eave, z1 - T_WALL), Vector3(xc, ridge, z1 - T_WALL))
		# barge boards along the gable edges, ridge cap
		paint(col_trim)
		for zz in ([za] if gable_front else []) + ([zb] if gable_back else []):
			ext.beam("paint", Vector3(x0 - oh, lo - 0.02, zz), Vector3(xc, ridge - 0.02, zz), 0.05, 0.2, Vector3(0, 0, 1))
			ext.beam("paint", Vector3(xc, ridge - 0.02, zz), Vector3(x1 + oh, lo - 0.02, zz), 0.05, 0.2, Vector3(0, 0, 1))
		paint(col_wall)
		ext.beam(key, Vector3(xc, ridge + th + 0.03, za), Vector3(xc, ridge + th + 0.03, zb), 0.16, 0.06)
		_roof_coll_z(x0 - oh, xc, x1 + oh, lo, ridge, za, zb, th)
		return ridge
	else:
		var zc := (z0 + z1) * 0.5
		var half2 := (z1 - z0) * 0.5
		var ridge2 := eave + half2 * tn
		var lo2 := eave - oh * tn
		var xa := x0 - oh
		var xb := x1 + oh
		ext.hexa(key, [Vector3(xa, lo2, z0 - oh), Vector3(xb, lo2, z0 - oh), Vector3(xb, ridge2, zc), Vector3(xa, ridge2, zc),
			Vector3(xa, lo2 + th, z0 - oh), Vector3(xb, lo2 + th, z0 - oh), Vector3(xb, ridge2 + th, zc), Vector3(xa, ridge2 + th, zc)])
		ext.hexa(key, [Vector3(xa, ridge2, zc), Vector3(xb, ridge2, zc), Vector3(xb, lo2, z1 + oh), Vector3(xa, lo2, z1 + oh),
			Vector3(xa, ridge2 + th, zc), Vector3(xb, ridge2 + th, zc), Vector3(xb, lo2 + th, z1 + oh), Vector3(xa, lo2 + th, z1 + oh)])
		if gable_front:
			ext.tri(gmat, Vector3(x0, eave, z0), Vector3(x0, eave, z1), Vector3(x0, ridge2, zc))
			if gin != "":
				ext.tri(gin, Vector3(x0 + T_WALL, eave, z1), Vector3(x0 + T_WALL, eave, z0), Vector3(x0 + T_WALL, ridge2, zc))
		if gable_back:
			ext.tri(gmat, Vector3(x1, eave, z1), Vector3(x1, eave, z0), Vector3(x1, ridge2, zc))
			if gin != "":
				ext.tri(gin, Vector3(x1 - T_WALL, eave, z0), Vector3(x1 - T_WALL, eave, z1), Vector3(x1 - T_WALL, ridge2, zc))
		paint(col_trim)
		for xx in ([xa] if gable_front else []) + ([xb] if gable_back else []):
			ext.beam("paint", Vector3(xx, lo2 - 0.02, z0 - oh), Vector3(xx, ridge2 - 0.02, zc), 0.05, 0.2, Vector3(1, 0, 0))
			ext.beam("paint", Vector3(xx, ridge2 - 0.02, zc), Vector3(xx, lo2 - 0.02, z1 + oh), 0.05, 0.2, Vector3(1, 0, 0))
		paint(col_wall)
		ext.beam(key, Vector3(xa, ridge2 + th + 0.03, zc), Vector3(xb, ridge2 + th + 0.03, zc), 0.16, 0.06)
		_roof_coll_x(xa, xb, z0 - oh, zc, z1 + oh, lo2, ridge2, th)
		return ridge2

func _roof_coll_z(xa: float, xc: float, xb: float, lo: float, ridge: float, za: float, zb: float, th: float) -> void:
	ramp(Vector3(xa, lo + th, (za + zb) * 0.5), Vector3(xc, ridge + th, (za + zb) * 0.5), zb - za, 0.2)
	ramp(Vector3(xb, lo + th, (za + zb) * 0.5), Vector3(xc, ridge + th, (za + zb) * 0.5), zb - za, 0.2)

func _roof_coll_x(xa: float, xb: float, za: float, zc: float, zb: float, lo: float, ridge: float, th: float) -> void:
	ramp(Vector3((xa + xb) * 0.5, lo + th, za), Vector3((xa + xb) * 0.5, ridge + th, zc), xb - xa, 0.2)
	ramp(Vector3((xa + xb) * 0.5, lo + th, zb), Vector3((xa + xb) * 0.5, ridge + th, zc), xb - xa, 0.2)

## Mono-pitch roof falling from y_hi at z0 to y_lo at z1 (overhangs on all sides).
func shed_roof(x0: float, z0: float, x1: float, z1: float, y_hi: float, y_lo: float, oh := 0.35, key := "", coll := true) -> void:
	if key == "":
		key = mat_roof
	var th := 0.1
	var slope := (y_hi - y_lo) / maxf(z1 - z0, 0.01)
	var ya := y_hi + oh * slope
	var yb := y_lo - oh * slope
	ext.hexa(key, [Vector3(x0 - oh, ya, z0 - oh), Vector3(x1 + oh, ya, z0 - oh), Vector3(x1 + oh, yb, z1 + oh), Vector3(x0 - oh, yb, z1 + oh),
		Vector3(x0 - oh, ya + th, z0 - oh), Vector3(x1 + oh, ya + th, z0 - oh), Vector3(x1 + oh, yb + th, z1 + oh), Vector3(x0 - oh, yb + th, z1 + oh)])
	if coll:
		ramp(Vector3((x0 + x1) * 0.5, yb + th, z1 + oh), Vector3((x0 + x1) * 0.5, ya + th, z0 - oh), x1 - x0 + oh * 2.0, 0.15)

func flat_roof(x0: float, z0: float, x1: float, z1: float, y: float, key := "roof_planks") -> void:
	ext.box(key, Vector3(x0, y, z0), Vector3(x1, y + 0.15, z1), MeshKit.F_PY)
	solid(Vector3(x0, y, z0), Vector3(x1, y + 0.15, z1))

func chimney(x: float, z: float, y0: float, y1: float, key := "brick") -> void:
	paint(Color(0.85, 0.8, 0.75) if key == "brick" else col_wall)
	ext.box(key, Vector3(x - 0.3, y0, z - 0.3), Vector3(x + 0.3, y1, z + 0.3), MeshKit.F_SIDES)
	ext.box(key, Vector3(x - 0.36, y1, z - 0.36), Vector3(x + 0.36, y1 + 0.12, z + 0.36))
	ext.box("iron", Vector3(x - 0.2, y1 + 0.12, z - 0.2), Vector3(x + 0.2, y1 + 0.13, z + 0.2), MeshKit.F_PY)
	paint(col_wall)

func stovepipe(x: float, z: float, y0: float, y1: float) -> void:
	ext.tint = Color(1, 1, 1, 0)
	ext.cyl("iron", Vector3(x, y0, z), Vector3(x, y1, z), 0.09, 8, false)
	ext.cyl("iron", Vector3(x, y1, z), Vector3(x, y1 + 0.18, z), 0.16, 8, true, 0.04)
	paint(col_wall)

# ------------------------------------------------------------------------------------------------ porches, steps

## Steps down from (x, top, z_edge) towards -z (dir -1) or +z (dir +1) to the ground. Returns run length.
func steps(xc: float, z_edge: float, top: float, width: float, dir := -1.0, key := "planks_brown") -> float:
	var g := ground_local(xc, z_edge + dir * 0.6)
	var drop := top - g
	if drop < 0.1:
		return 0.0
	var treads := maxi(1, int(ceil(drop / 0.18)) - 1)
	var rise := drop / (treads + 1)
	var run := 0.3
	for i in treads:
		var ytop := top - rise * (i + 1)
		var za := z_edge + dir * run * i
		var zb := z_edge + dir * run * (i + 1)
		ext.box(key, Vector3(xc - width * 0.5, g - 0.25, minf(za, zb)), Vector3(xc + width * 0.5, ytop, maxf(za, zb)),
			MeshKit.F_ALL & ~MeshKit.F_NY)
	var zend := z_edge + dir * run * treads
	paint(col_trim)
	for sx: float in [-1.0, 1.0]:
		var xx: float = xc + sx * (width * 0.5 + 0.03)
		ext.beam("planks_brown", Vector3(xx, top - 0.1, z_edge), Vector3(xx, g + 0.03, zend + dir * 0.15), 0.05, 0.2)
	paint(col_wall)
	ramp(Vector3(xc, g, zend + dir * 0.3), Vector3(xc, top, z_edge), width)
	return run * treads

## Side steps along x at the end of a porch (dir -1 towards -x).
func steps_x(x_edge: float, zc: float, top: float, width: float, dir := -1.0) -> void:
	var g := ground_local(x_edge + dir * 0.6, zc)
	var drop := top - g
	if drop < 0.1:
		return
	var treads := maxi(1, int(ceil(drop / 0.18)) - 1)
	var rise := drop / (treads + 1)
	for i in treads:
		var ytop := top - rise * (i + 1)
		var xa := x_edge + dir * 0.3 * i
		var xb := x_edge + dir * 0.3 * (i + 1)
		ext.box("planks_brown", Vector3(minf(xa, xb), g - 0.25, zc - width * 0.5), Vector3(maxf(xa, xb), ytop, zc + width * 0.5),
			MeshKit.F_ALL & ~MeshKit.F_NY)
	ramp(Vector3(x_edge + dir * 0.3 * (treads + 1), g, zc), Vector3(x_edge, top, zc), width)

## Boardwalk/porch in front of the building: deck from z=-pd to 0 at y=0, posts, optional roof (awning).
## roof: "" none | "shed" | "balcony" (handled by caller). Returns post x positions.
func boardwalk(x0: float, x1: float, pd: float, roof := "shed", roof_y := 3.25, post_y := 3.0, steps_at := [], end_steps = true,
		roof_key := "", rail := false) -> Array:
	var deck := "planks_brown"
	# deck boards: boards run along x (the street)
	ext.uv_rot = true          # deck planks run across the boardwalk, on stringers along the street
	ext.box(deck, Vector3(x0, -0.06, -pd), Vector3(x1, 0.0, 0.0), MeshKit.F_PY | MeshKit.F_NZ | MeshKit.F_PX | MeshKit.F_NX)
	var bridge: float = spec.get("deck_bridge", 0.0)
	if bridge > 0.0 and is_equal_approx(x1, w * 0.5):
		ext.box(deck, Vector3(x1, -0.06, -pd), Vector3(x1 + bridge, 0.0, 0.0), MeshKit.F_PY | MeshKit.F_NZ)
		solid(Vector3(x1, -0.35, -pd), Vector3(x1 + bridge, 0.0, 0.0))
		ext.box("planks_v", Vector3(x1, ground_min(x1, -pd, x1 + bridge, -pd) - 0.3, -pd + 0.02), Vector3(x1 + bridge, -0.06, -pd + 0.06), MeshKit.F_NZ)
	ext.uv_rot = false
	solid(Vector3(x0, -0.35, -pd), Vector3(x1, 0.0, 0.0))
	# front skirt and joists down to the ground
	var g := minf(ground_min(x0, -pd, x1, -pd + 0.2), -0.06)
	ext.box("planks_v", Vector3(x0, g - 0.3, -pd + 0.02), Vector3(x1, -0.06, -pd + 0.06), MeshKit.F_NZ)
	ext.box("planks_v", Vector3(x0 + 0.02, g - 0.3, -pd), Vector3(x0 + 0.06, -0.06, 0.0), MeshKit.F_NX)
	ext.box("planks_v", Vector3(x1 - 0.06, g - 0.3, -pd), Vector3(x1 - 0.02, -0.06, 0.0), MeshKit.F_PX)
	var posts := []
	var span := x1 - x0
	var n := maxi(1, int(ceil(span / 3.2)))
	for i in n + 1:
		posts.append(lerpf(x0 + 0.12, x1 - 0.12, float(i) / n))
	if roof != "":
		paint(col_trim)
		for px in posts:
			ext.box("paint", Vector3(px - 0.07, 0.0, -pd + 0.06), Vector3(px + 0.07, post_y, -pd + 0.2), MeshKit.F_SIDES)
			ext.box("paint", Vector3(px - 0.1, 0.0, -pd + 0.03), Vector3(px + 0.1, 0.12, -pd + 0.23), MeshKit.F_SIDES | MeshKit.F_PY)
			# knee braces
			ext.beam("paint", Vector3(px, post_y - 0.5, -pd + 0.13), Vector3(px + (0.4 if px < x1 - 0.5 else -0.4), post_y, -pd + 0.13), 0.06, 0.06, Vector3(0, 0, 1))
			solid(Vector3(px - 0.07, 0.0, -pd + 0.06), Vector3(px + 0.07, post_y, -pd + 0.2))
		ext.box("paint", Vector3(x0, post_y, -pd + 0.04), Vector3(x1, post_y + 0.18, -pd + 0.22))
		paint(col_wall)
		if roof == "shed":
			var rk := roof_key if roof_key != "" else ("corrugated" if rng.randf() < 0.35 else mat_roof)
			paint(Color(0.9, 0.88, 0.85))
			shed_roof(x0, -pd, x1, 0.0, roof_y, post_y + 0.18, 0.25, rk, false)
			solid(Vector3(x0, post_y + 0.18, -pd), Vector3(x1, roof_y, 0.0))
			paint(col_wall)
	if rail:
		porch_rail(x0, x1, -pd + 0.13, 0.0, steps_at)
	for sx in steps_at:
		steps(sx, -pd, 0.0, 1.8)
	var e0: bool = end_steps[0] if end_steps is Array else bool(end_steps)
	var e1: bool = end_steps[1] if end_steps is Array else bool(end_steps)
	if e0:
		steps_x(x0, -pd * 0.5, 0.0, pd - 0.3, -1.0)
	if e1:
		steps_x(x1, -pd * 0.5, 0.0, pd - 0.3, 1.0)
	return posts

## Simple porch railing along x at z with gaps around step positions.
func porch_rail(x0: float, x1: float, z: float, y: float, gaps: Array, h := 0.95) -> void:
	paint(col_trim)
	var segs := [[x0, x1]]
	for g in gaps:
		var nxt := []
		for s in segs:
			if g - 1.0 > s[0] and g + 1.0 < s[1]:
				nxt.append([s[0], g - 1.0])
				nxt.append([g + 1.0, s[1]])
			else:
				nxt.append(s)
		segs = nxt
	for s in segs:
		ext.box("paint", Vector3(s[0], y + h - 0.06, z - 0.05), Vector3(s[1], y + h, z + 0.05))
		ext.box("paint", Vector3(s[0], y + 0.1, z - 0.03), Vector3(s[1], y + 0.16, z + 0.03))
		var nb := int((s[1] - s[0]) / 0.15)
		for i in nb:
			var bx: float = s[0] + 0.075 + i * 0.15
			ext.box("paint", Vector3(bx - 0.02, y + 0.16, z - 0.018), Vector3(bx + 0.02, y + h - 0.06, z + 0.018), MeshKit.F_PZ | MeshKit.F_NZ)
		solid(Vector3(s[0], y, z - 0.06), Vector3(s[1], y + h, z + 0.06))
	paint(col_wall)

func hitching_rail(xc: float, z: float, length := 3.0, outside := true) -> void:
	paint(Color(0.85, 0.8, 0.72))
	var y0 := ground_local(xc, z)
	for sx: float in [-1.0, 1.0]:
		var px := xc + sx * length * 0.5
		var gy := ground_local(px, z)
		ext.box("planks_brown", Vector3(px - 0.06, gy - 0.2, z - 0.06), Vector3(px + 0.06, y0 + 1.0, z + 0.06), MeshKit.F_SIDES | MeshKit.F_PY)
	ext.cyl("log", Vector3(xc - length * 0.5 - 0.1, y0 + 0.95, z), Vector3(xc + length * 0.5 + 0.1, y0 + 0.95, z), 0.06, 7, true)
	solid(Vector3(xc - length * 0.5 - 0.06, y0, z - 0.06), Vector3(xc + length * 0.5 + 0.06, y0 + 1.0, z + 0.06))
	spot("hitch", Vector3(xc - length * 0.25, y0, z - 0.8), Vector3(0, 0, 1))
	spot("hitch", Vector3(xc + length * 0.25, y0, z - 0.8), Vector3(0, 0, 1))
	paint(col_wall)

func trough(xc: float, z: float, length := 2.2, yaw90 := false) -> void:
	var y0 := ground_local(xc, z)
	paint(Color(0.8, 0.75, 0.68))
	var a := Vector3(xc - length * 0.5, y0, z - 0.3)
	var b := Vector3(xc + length * 0.5, y0 + 0.6, z + 0.3)
	if yaw90:
		a = Vector3(xc - 0.3, y0, z - length * 0.5)
		b = Vector3(xc + 0.3, y0 + 0.6, z + length * 0.5)
	ext.box("dark_planks", a, b, MeshKit.F_SIDES)
	ext.box("dark_planks", a + Vector3(0.06, 0.0, 0.06), b - Vector3(0.06, 0.0, 0.06), MeshKit.F_SIDES)
	ext.box("dark_planks", a, Vector3(b.x, a.y + 0.08, b.z), MeshKit.F_PY)
	ext.tint = Color(1, 1, 1, 0)
	ext.face("water", Vector3(a.x + 0.06, b.y - 0.1, b.z - 0.06), Vector3(b.x - a.x - 0.12, 0, 0), Vector3(0, 0, -(b.z - a.z - 0.12)))
	solid(a, b)
	spot("trough", Vector3(xc, y0, z - (0.9 if not yaw90 else 0.0)) + (Vector3(-0.9, 0, 0) if yaw90 else Vector3.ZERO),
		Vector3(0, 0, 1) if not yaw90 else Vector3(1, 0, 0))
	paint(col_wall)

## Street lamp post with a lantern (light registered for night).
func lamp_post(x: float, z: float, h := 3.2) -> void:
	var y0 := ground_local(x, z)
	paint(Color(0.3, 0.26, 0.22))
	ext.box("dark_planks", Vector3(x - 0.08, y0 - 0.3, z - 0.08), Vector3(x + 0.08, y0 + h, z + 0.08), MeshKit.F_SIDES)
	ext.box("dark_planks", Vector3(x - 0.06, y0 + h - 0.3, z - 0.06), Vector3(x + 0.55, y0 + h - 0.2, z + 0.06))
	lantern_mesh(Vector3(x + 0.45, y0 + h - 0.75, z))
	solid(Vector3(x - 0.08, y0, z - 0.08), Vector3(x + 0.08, y0 + h, z + 0.08))
	light(Vector3(x + 0.45, y0 + h - 0.6, z), "street", 10.0, 1.6)
	paint(col_wall)

## Small glass lantern geometry (iron frame + glowing glass) hanging at p (bottom).
func lantern_mesh(p: Vector3, k: MeshKit = null) -> void:
	if k == null:
		k = ext
	k.tint = Color(1, 1, 1, 0)
	k.box("iron", p + Vector3(-0.11, 0.0, -0.11), p + Vector3(0.11, 0.04, 0.11))
	k.box("lamp", p + Vector3(-0.085, 0.04, -0.085), p + Vector3(0.085, 0.32, 0.085))
	k.cyl("iron", p + Vector3(0, 0.32, 0), p + Vector3(0, 0.45, 0), 0.13, 4, true, 0.02)
	k.box("iron", p + Vector3(-0.01, 0.45, -0.01), p + Vector3(0.01, 0.55, 0.01))

# ------------------------------------------------------------------------------------------------ signs

## Painted letters: text centred at c (local), facing `out`, fitting height h and width maxw.
func text(k: MeshKit, s: String, c: Vector3, dir: Vector3, out: Vector3, h: float, maxw: float, col: Color, fnt := "Rye") -> void:
	if s.strip_edges() == "":
		return
	SignText.add(k, s, c, dir, out, h, maxw, col, fnt)

## Sign board on a wall frame: board (paint) with border and painted text. Lines split by "\n".
func sign_board(f: Dictionary, sc: float, vc: float, bw: float, bh: float, txt: String, style := -1, fnt := "Rye", depth := 0.0) -> void:
	if style < 0:
		style = rng.randi() % SIGN_BG.size()
	var bg: Color = SIGN_BG[style]
	var fg: Color = SIGN_FG[style]
	paint(bg)
	_fbox(f, "paint", sc - bw * 0.5, sc + bw * 0.5, vc - bh * 0.5, vc + bh * 0.5, depth, depth + 0.04)
	paint(fg.lerp(bg, 0.3))
	_fbox(f, "paint", sc - bw * 0.5 - 0.04, sc + bw * 0.5 + 0.04, vc + bh * 0.5, vc + bh * 0.5 + 0.06, depth, depth + 0.07)
	_fbox(f, "paint", sc - bw * 0.5 - 0.04, sc + bw * 0.5 + 0.04, vc - bh * 0.5 - 0.06, vc - bh * 0.5, depth, depth + 0.07)
	paint(col_wall)
	var lines := txt.split("\n")
	var n := lines.size()
	var lh := bh * 0.62 / n if n > 1 else bh * 0.58
	for i in n:
		var vv := vc + bh * 0.5 - bh * (i + 0.5) / n
		var lf := fnt if i == 0 else "OldStandard-Bold"
		var hh := lh if i == 0 else lh * 0.75
		text(ext, lines[i], fp(f, sc, vv, depth + 0.042), f.dir, f.out, hh, bw * 0.9, fg, lf)

## Hanging/projecting sign under a porch roof: two-sided board perpendicular to the facade at x.
func hanging_sign(x: float, z: float, y: float, bw: float, bh: float, txt: String, style := -1) -> void:
	if style < 0:
		style = rng.randi() % SIGN_BG.size()
	var bg: Color = SIGN_BG[style]
	var fg: Color = SIGN_FG[style]
	paint(bg)
	ext.box("paint", Vector3(x - 0.025, y - bh * 0.5, z - bw * 0.5), Vector3(x + 0.025, y + bh * 0.5, z + bw * 0.5))
	ext.tint = Color(1, 1, 1, 0)
	ext.box("iron", Vector3(x - 0.01, y + bh * 0.5, z - bw * 0.35), Vector3(x + 0.01, y + bh * 0.5 + 0.25, z - bw * 0.35 + 0.02))
	ext.box("iron", Vector3(x - 0.01, y + bh * 0.5, z + bw * 0.35), Vector3(x + 0.01, y + bh * 0.5 + 0.25, z + bw * 0.35 + 0.02))
	text(ext, txt, Vector3(x + 0.027, y, z), Vector3(0, 0, -1), Vector3(1, 0, 0), bh * 0.5, bw * 0.85, fg, "OldStandard-Bold")
	text(ext, txt, Vector3(x - 0.027, y, z), Vector3(0, 0, 1), Vector3(-1, 0, 0), bh * 0.5, bw * 0.85, fg, "OldStandard-Bold")
	paint(col_wall)

# ------------------------------------------------------------------------------------------------ far LOD

func far_box(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, key: String, tint := Color.WHITE) -> void:
	var c: Color = TownMats.FAR_COL.get(key, Color(0.5, 0.45, 0.4))
	if key == "paint" or key == "plaster" or key == "boards_v":
		c = Color(0.8, 0.78, 0.74) * tint
	far.tint = Color(c.r, c.g, c.b, 1.0)
	far.box("far", Vector3(x0, y0, z0), Vector3(x1, y1, z1), MeshKit.F_ALL & ~MeshKit.F_NY)

func far_gable(x0: float, z0: float, x1: float, z1: float, eave: float, ridge: float, axis: String, key: String) -> void:
	var c: Color = TownMats.FAR_COL.get(key, Color(0.35, 0.3, 0.26))
	far.tint = Color(c.r, c.g, c.b, 1.0)
	var oh := 0.3
	if axis == "z":
		var xc := (x0 + x1) * 0.5
		far.quad("far", Vector3(x0 - oh, eave, z0 - oh), Vector3(x0 - oh, eave, z1 + oh), Vector3(xc, ridge, z1 + oh), Vector3(xc, ridge, z0 - oh))
		far.quad("far", Vector3(x1 + oh, eave, z1 + oh), Vector3(x1 + oh, eave, z0 - oh), Vector3(xc, ridge, z0 - oh), Vector3(xc, ridge, z1 + oh))
		far.tri("far", Vector3(x1, eave, z0), Vector3(x0, eave, z0), Vector3(xc, ridge, z0))
		far.tri("far", Vector3(x0, eave, z1), Vector3(x1, eave, z1), Vector3(xc, ridge, z1))
	else:
		var zc := (z0 + z1) * 0.5
		far.quad("far", Vector3(x1 + oh, eave, z0 - oh), Vector3(x0 - oh, eave, z0 - oh), Vector3(x0 - oh, ridge, zc), Vector3(x1 + oh, ridge, zc))
		far.quad("far", Vector3(x0 - oh, eave, z1 + oh), Vector3(x1 + oh, eave, z1 + oh), Vector3(x1 + oh, ridge, zc), Vector3(x0 - oh, ridge, zc))
		far.tri("far", Vector3(x0, eave, z0), Vector3(x0, eave, z1), Vector3(x0, ridge, zc))
		far.tri("far", Vector3(x1, eave, z1), Vector3(x1, eave, z0), Vector3(x1, ridge, zc))
