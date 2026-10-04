class_name CapitalCity
extends Node3D
## A Capital city on a raised white podium: a radial-and-grid plan (avenues every BLOCK metres, eight radial
## boulevards, two ring roads, a central plaza with reflecting pools), towers whose height falls off from the
## centre, a supertall spire flanked by four towers, setback terraces with gardens and trees, glass skyways,
## cantilevered landing pads, street trees and lamps. Geometry is merged into 256 m cells (full detail) under
## 768 m far cells (simplified) using Godot's visibility parents (HLOD). Buildings keep their data so that
## destruction can rebuild a cell without them.

const CELL := 256.0
const FAR_CELL := 768.0
const FAR_BEGIN := 1150.0
const BLOCK := 150.0
const AVENUE := 26.0
const BOULEVARD := 44.0

var center := Vector3.ZERO
var radius := 1500.0
var podium_y := 23.0
var name_ := "Candor"
var rng := RandomNumberGenerator.new()
var buildings: Array = []        # each: {id, pos, sections: [[prof, y0, y1, style]], top, h, xf, cell, alive}
var parks := {}                  # Vector2i block -> true
var trees: Array = []            # [species, variant, Transform3D, tint, phase]
var lamps := PackedVector3Array()
var pools: Array = []            # [Vector3 centre, Vector2 size]
var mat: ShaderMaterial
var ground_mat: ShaderMaterial
var cells := {}                  # Vector2i -> {"near": MeshInstance3D, "far": key}
var far_nodes := {}              # Vector2i -> MeshInstance3D
var _bodies: Node3D
var skyways: Array = []


func build(c: Vector3, r: float, seed: int, label: String) -> void:
	center = Vector3(c.x, 0.0, c.z)
	radius = r
	podium_y = c.y + 1.0
	name_ = label
	rng.seed = seed
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/building.gdshader")
	_bodies = Node3D.new()
	_bodies.name = "Bodies"
	add_child(_bodies)
	_plan()
	_place_spire()
	_place_towers()
	_place_skyways()
	_place_street_furniture()
	_build_ground()
	_build_cells()
	_build_collision()
	print("city %s: %d buildings, %d skyways, %d trees, %d lamps" % [name_, buildings.size(), skyways.size(), trees.size(), lamps.size()])


# -------------------------------------------------------------------------------------------- the plan

func in_city(x: float, z: float, margin: float = 0.0) -> bool:
	return _oct_dist(Vector2(x - center.x, z - center.z)) < radius - margin


## Distance metric of a regular octagon (flat sides on the axes).
func _oct_dist(p: Vector2) -> float:
	var a := absf(p.x)
	var b := absf(p.y)
	return maxf(maxf(a, b), (a + b) * 0.70710678)


func _block_of(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x + BLOCK * 0.5) / BLOCK), floori((p.y + BLOCK * 0.5) / BLOCK))


## Is a local point (relative to the centre) on a street, boulevard, ring or plaza?
func is_open(p: Vector2, margin: float = 0.0) -> bool:
	var d := p.length()
	if d < 300.0 + margin:
		return true                                    # central plaza
	if absf(d - 330.0) < 16.0 + margin or absf(d - 900.0) < 18.0 + margin:
		return true                                    # ring roads
	for k in 8:
		var a := TAU * k / 8.0
		var dir := Vector2(cos(a), sin(a))
		var along := p.dot(dir)
		if along > 0.0 and absf(p.dot(dir.orthogonal())) < BOULEVARD * 0.5 + margin:
			return true
	var gx := fposmod(p.x + BLOCK * 0.5, BLOCK)
	var gz := fposmod(p.y + BLOCK * 0.5, BLOCK)
	var half := AVENUE * 0.5 + margin
	if gx < half or gx > BLOCK - half or gz < half or gz > BLOCK - half:
		return true
	return false


func _plan() -> void:
	var n := int(radius / BLOCK) + 1
	for bz in range(-n, n + 1):
		for bx in range(-n, n + 1):
			var p := Vector2(bx, bz) * BLOCK
			var d := p.length()
			if d < 420.0 or d > radius - 80.0:
				continue
			if G.hash2(bx, bz, 777) < (0.16 if d < 900.0 else 0.1):
				parks[Vector2i(bx, bz)] = true
	# Reflecting pools along the main east-west axis, either side of the spire.
	pools.append([Vector3(center.x - 200.0, podium_y, center.z), Vector2(150.0, 26.0)])
	pools.append([Vector3(center.x + 200.0, podium_y, center.z), Vector2(150.0, 26.0)])


# ---------------------------------------------------------------------------------------------- towers

func _new_building(pos: Vector3, h: float) -> Dictionary:
	var b := {"id": buildings.size(), "pos": pos, "sections": [], "h": h, "alive": true, "seed": rng.randf(),
		"parts": [], "cell": Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))}
	buildings.append(b)
	return b


## A tower: podium, setback shaft sections with garden terraces, crown, optional pad and fins.
func _tower(pos: Vector3, lot: float, h: float, kind: int, allow_pad: bool) -> Dictionary:
	var b := _new_building(pos, h)
	var seed: float = b["seed"]
	var style := Kit.GLASS if rng.randf() < 0.55 else Kit.BANDED
	var w := lot * rng.randf_range(0.45, 0.62)
	var d := w * rng.randf_range(0.7, 1.0)
	var prof: PackedVector2Array
	match kind % 5:
		0: prof = Kit.chamfer_rect(w, d, w * 0.18)
		1: prof = Kit.rounded_rect(w, d, w * 0.3, 5)
		2: prof = Kit.ngon(w * 0.55, 8, PI / 8.0)
		3: prof = Kit.ngon(w * 0.55, 24, 0.0, 1.0, d / w)
		4: prof = Kit.lens(w * 1.15, d * 0.95, 8)
	var rot := rng.randi_range(0, 3) * PI * 0.5 + (PI * 0.25 if kind % 7 == 3 else 0.0)
	var xf := Transform3D(Basis(Vector3.UP, rot), pos)
	b["xf"] = xf
	# Podium: two to four floors of white stone with a glass lobby band.
	var pod_h := 4.5 * rng.randi_range(2, 4)
	var pod := Kit.chamfer_rect(lot * 0.86, lot * 0.86 * rng.randf_range(0.7, 1.0), 6.0)
	_section(b, pod, 0.0, 5.5, Kit.DARKGLASS, 5.5)
	_section(b, pod, 5.5, pod_h, Kit.STONE, 4.5)
	_part(b, "band", [pod, pod_h, 0.6, 0.35, Kit.TRIM])
	_terrace(b, pod, Kit.inset(pod, 3.0), prof, pod_h, xf)
	# Shaft sections with setbacks.
	var n_sec := 1 if h < 70.0 else (2 if h < 160.0 else 3)
	var y := pod_h
	var cur := prof
	for s in n_sec:
		var top := lerpf(pod_h, h, float(s + 1) / n_sec) if s < n_sec - 1 else h
		_section(b, cur, y, top, style if s % 2 == 0 or rng.randf() < 0.5 else (Kit.BANDED if style == Kit.GLASS else Kit.GLASS), 4.0)
		_part(b, "band", [cur, top - 0.9, 0.9, 0.45, Kit.TRIM])
		if rng.randf() < 0.45 and style == Kit.GLASS:
			_part(b, "fins", [cur, y, top])
		if s < n_sec - 1:
			var nxt := Kit.scaled(cur, rng.randf_range(0.74, 0.86))
			_terrace(b, cur, nxt, nxt, top, xf)
			cur = nxt
		y = top
	# Crown: a trim cap, then a roof garden, a mast or a pad.
	_section(b, Kit.inset(cur, 1.2), h, h + 3.0, Kit.TRIM, 3.0, false)
	var r := rng.randf()
	if r < 0.35:
		_part(b, "roofgarden", [Kit.inset(cur, 3.0), h + 3.0])
	elif r < 0.6:
		_part(b, "mast", [h + 3.0, h * rng.randf_range(0.08, 0.16)])
	else:
		_part(b, "plant", [Kit.inset(cur, 4.0), h + 3.0])
	if allow_pad and h > 110.0 and rng.randf() < 0.42:
		var ext := 0.0
		for v in cur:
			ext = maxf(ext, v.length())
		_part(b, "pad", [h * rng.randf_range(0.55, 0.8), rng.randf() * TAU, ext])
	return b


func _section(b: Dictionary, prof: PackedVector2Array, y0: float, y1: float, style: int, floor_h: float, collide: bool = true) -> void:
	b["sections"].append({"prof": prof, "y0": y0, "y1": y1, "style": style, "floor": floor_h, "collide": collide})


func _part(b: Dictionary, kind: String, args: Array) -> void:
	b["parts"].append([kind, args])


## A terrace on the roof of `outer` around the next section `inner`: planter boxes and trees.
func _terrace(b: Dictionary, outer: PackedVector2Array, inner: PackedVector2Array, _next: PackedVector2Array, y: float, xf: Transform3D) -> void:
	_part(b, "terrace", [outer, inner, y])
	# Trees on the terrace ring (between the two outlines).
	var per := Kit.perimeter(outer)
	var count := clampi(int(per / 22.0), 2, 10)
	for i in count:
		var t := (i + 0.5) / count
		var p := _point_on(outer, t)
		var q := _point_on(inner, t)
		var m := p.lerp(q, 0.5)
		if p.distance_to(q) < 3.5:
			continue
		var w := xf * Vector3(m.x, y + 0.9, m.y)
		var sp := TreeBuilder.BIRCH if rng.randf() < 0.6 else TreeBuilder.BROADLEAF
		var s := rng.randf_range(0.42, 0.6)
		trees.append([sp, rng.randi_range(0, 2), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), w), rng.randf(), rng.randf()])


func _point_on(prof: PackedVector2Array, t: float) -> Vector2:
	var per := Kit.perimeter(prof)
	var target := t * per
	var acc := 0.0
	for i in prof.size():
		var a := prof[i]
		var bb := prof[(i + 1) % prof.size()]
		var l := a.distance_to(bb)
		if acc + l >= target:
			return a.lerp(bb, (target - acc) / maxf(l, 0.001))
		acc += l
	return prof[0]


func _place_spire() -> void:
	# The Spire: a 430 m octagonal supertall with four setbacks, white fins and a beacon needle.
	var c := Vector3(center.x, podium_y, center.z)
	var b := _new_building(c, 430.0)
	b["xf"] = Transform3D(Basis.IDENTITY, c)
	b["spire"] = true
	var widths := [72.0, 62.0, 52.0, 40.0, 28.0]
	var heights := [0.0, 120.0, 220.0, 310.0, 380.0, 430.0]
	_section(b, Kit.chamfer_rect(110.0, 110.0, 28.0), 0.0, 6.0, Kit.DARKGLASS, 6.0)
	_section(b, Kit.chamfer_rect(110.0, 110.0, 28.0), 6.0, 18.0, Kit.STONE, 6.0)
	_part(b, "terrace", [Kit.chamfer_rect(110.0, 110.0, 28.0), Kit.ngon(widths[0] * 0.55, 8, PI / 8.0), 18.0])
	for i in 5:
		var prof := Kit.ngon(widths[i] * 0.55, 8, PI / 8.0)
		var y0: float = maxf(heights[i], 18.0)
		var y1: float = heights[i + 1]
		_section(b, prof, y0, y1, Kit.GLASS if i % 2 == 0 else Kit.BANDED, 4.5)
		_part(b, "band", [prof, y1 - 1.5, 1.5, 0.8, Kit.TRIM])
		_part(b, "fins", [prof, y0, y1])
		if i < 4:
			var nxt := Kit.ngon(widths[i + 1] * 0.55, 8, PI / 8.0)
			_part(b, "terrace", [prof, nxt, y1])
			for k in 8:
				var a := TAU * (k + 0.5) / 8.0
				var rr: float = (widths[i] + widths[i + 1]) * 0.25 + 1.0
				trees.append([TreeBuilder.BIRCH, k % 3, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.45), c + Vector3(cos(a) * rr, y1 + 0.9, sin(a) * rr)), 0.3, float(k) / 8.0])
	_part(b, "mast", [430.0, 70.0])
	_part(b, "pad", [300.0, PI * 0.25, 34.0])
	_part(b, "pad", [300.0, PI * 1.25, 34.0])
	# Four flanking towers on the diagonals, joined to the spire by skyways.
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var p := c + Vector3(cos(a), 0.0, sin(a)) * 205.0
		var t := _tower(p, 90.0, rng.randf_range(250.0, 300.0), 2 if k % 2 == 0 else 0, true)
		t["flank"] = true
		skyways.append([b, t, rng.randf_range(150.0, 190.0)])


func _place_towers() -> void:
	var n := int(radius / BLOCK) + 1
	var kind := 0
	for bz in range(-n, n + 1):
		for bx in range(-n, n + 1):
			var bc := Vector2(bx, bz) * BLOCK
			var d := bc.length()
			if d < 380.0 or _oct_dist(bc) > radius - 110.0 or parks.has(Vector2i(bx, bz)):
				continue
			# Height profile: a skyline that peaks near the centre and falls toward the podium edge.
			var t := clampf((d - 380.0) / (radius - 380.0), 0.0, 1.0)
			var base := lerpf(240.0, 26.0, pow(t, 0.7))
			var lot := BLOCK - AVENUE - 8.0
			var sub := 1 if d < 700.0 else 2
			for sz in sub:
				for sx in sub:
					var off := (Vector2(sx, sz) - Vector2(sub - 1, sub - 1) * 0.5) * (lot / sub)
					var p := bc + off
					if is_open(p, lot / sub * 0.42):
						continue
					var h := base * rng.randf_range(0.6, 1.25)
					if rng.randf() < 0.08 and d < 1000.0:
						h *= 1.6
					h = clampf(roundf(h / 4.0) * 4.0, 16.0, 360.0)
					var pos := Vector3(center.x + p.x, podium_y, center.z + p.y)
					if h < 40.0:
						_lowrise(pos, lot / sub, h)
					else:
						_tower(pos, lot / sub, h, kind, true)
					kind += 1


## Low-rise terraced blocks near the edge: stepped white volumes with courtyard gardens.
func _lowrise(pos: Vector3, lot: float, h: float) -> void:
	var b := _new_building(pos, h)
	var xf := Transform3D(Basis(Vector3.UP, rng.randi_range(0, 3) * PI * 0.5), pos)
	b["xf"] = xf
	var w := lot * 0.88
	var prof := Kit.chamfer_rect(w, w * rng.randf_range(0.6, 1.0), 4.0)
	var steps := rng.randi_range(2, 3)
	var y := 0.0
	var cur := prof
	for s in steps:
		var top := h * float(s + 1) / steps
		_section(b, cur, y, top, Kit.BANDED if s % 2 == 0 else Kit.STONE, 4.0)
		_part(b, "band", [cur, top - 0.6, 0.6, 0.3, Kit.TRIM])
		var nxt := Kit.inset(cur, w * 0.09)
		_terrace(b, cur, nxt, nxt, top, xf)
		cur = nxt
		y = top
	_part(b, "roofgarden", [Kit.inset(cur, 2.0), h])


func _place_skyways() -> void:
	# Join neighbouring tall towers: enclosed glass bridges at a common height.
	var tall: Array = buildings.filter(func(b): return b["h"] > 120.0 and not b.has("spire"))
	var used := {}
	for i in tall.size():
		var a: Dictionary = tall[i]
		if used.get(a["id"], 0) >= 2:
			continue
		for j in range(i + 1, tall.size()):
			var bb: Dictionary = tall[j]
			var dd := (a["pos"] as Vector3).distance_to(bb["pos"])
			if dd < 70.0 or dd > 175.0 or used.get(bb["id"], 0) >= 2:
				continue
			var hgt := minf(a["h"], bb["h"]) * rng.randf_range(0.45, 0.7)
			var mid := ((a["pos"] as Vector3) + (bb["pos"] as Vector3)) * 0.5
			if is_open(Vector2(mid.x - center.x, mid.z - center.z)) == false and rng.randf() < 0.5:
				continue
			skyways.append([a, bb, hgt])
			used[a["id"]] = used.get(a["id"], 0) + 1
			used[bb["id"]] = used.get(bb["id"], 0) + 1
			break


func _place_street_furniture() -> void:
	var n := int(radius / BLOCK) + 1
	# Avenue trees and lamps on both sidewalks of every grid street.
	for line in range(-n, n + 1):
		var c := line * BLOCK - BLOCK * 0.5
		var s := -radius
		while s < radius:
			for side in [-1.0, 1.0]:
				for axis in 2:
					var p := Vector2(s, c + side * (AVENUE * 0.5 - 2.5)) if axis == 0 else Vector2(c + side * (AVENUE * 0.5 - 2.5), s)
					if _oct_dist(p) > radius - 20.0 or p.length() < 310.0:
						continue
					var on_cross := fposmod(s + BLOCK * 0.5, BLOCK)
					if on_cross < AVENUE or on_cross > BLOCK - AVENUE * 0.5:
						continue
					var w := Vector3(center.x + p.x, podium_y, center.z + p.y)
					if fposmod(s, 30.0) < 15.0:
						trees.append([TreeBuilder.BIRCH if line % 2 == 0 else TreeBuilder.BROADLEAF, int(absf(s)) % 3,
							Transform3D(Basis(Vector3.UP, s).scaled(Vector3.ONE * 0.62), w), 0.4, fposmod(s * 0.01, 1.0)])
					else:
						lamps.append(w)
			s += 15.0
	# Parks: groves of trees.
	for k in parks:
		var bc := Vector2(k) * BLOCK
		for i in 14:
			var p := bc + Vector2(rng.randf_range(-55, 55), rng.randf_range(-55, 55))
			var w := Vector3(center.x + p.x, podium_y, center.z + p.y)
			trees.append([TreeBuilder.BROADLEAF if rng.randf() < 0.6 else TreeBuilder.BIRCH, rng.randi_range(0, 2),
				Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.6, 0.9)), w), rng.randf(), rng.randf()])
	# The plaza: double rows of birches along the pools.
	for side in [-1.0, 1.0]:
		for i in 24:
			var x := lerpf(-280.0, 280.0, i / 23.0)
			if absf(x) < 90.0:
				continue
			for row in [24.0, 34.0]:
				var w := Vector3(center.x + x, podium_y, center.z + side * row)
				trees.append([TreeBuilder.BIRCH, i % 3, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.55), w), 0.2, float(i) / 24.0])


# ------------------------------------------------------------------------------------------------ meshes

func _emit_building(k: Kit, b: Dictionary, far: bool) -> void:
	var xf: Transform3D = b["xf"]
	var seed: float = b["seed"]
	for s in b["sections"]:
		var prof: PackedVector2Array = s["prof"]
		if far:
			prof = _simplify(prof)
		k.prism(xf, prof, s["y0"], s["y1"], k.col(s["style"], seed, s["floor"]), true, false, k.col(Kit.STONE, seed))
	if far:
		return
	for part in b["parts"]:
		var kind: String = part[0]
		var a: Array = part[1]
		match kind:
			"band":
				k.band(xf, a[0], a[1], a[2], a[3], k.col(a[4], seed))
			"terrace":
				var outer: PackedVector2Array = a[0]
				var y: float = a[2]
				# Planter boxes along the terrace edge and a low glass balustrade line.
				var ring := Kit.inset(outer, 1.2)
				k.prism(xf, Kit.inset(outer, 0.4), y, y + 1.1, k.col(Kit.TRIM, seed), false)
				k.prism(xf, ring, y + 0.3, y + 0.9, k.col(Kit.GARDEN, seed), true)
			"roofgarden":
				var p: PackedVector2Array = a[0]
				k.prism(xf, p, a[1], a[1] + 0.7, k.col(Kit.GARDEN, seed), true)
			"plant":
				var p: PackedVector2Array = a[0]
				var c := Vector3.ZERO
				for v in p:
					c += Vector3(v.x, 0, v.y)
				c /= maxf(1, p.size())
				k.box(xf, c + Vector3(0, a[1] + 2.5, 0), Vector3(9, 5, 7), k.col(Kit.TRIM, seed, 5.0, false))
			"mast":
				var base := xf * Vector3(0, a[0], 0)
				k.tube(base, base + Vector3(0, a[1], 0), 1.2, 6, k.col(Kit.METAL, seed), true)
				k.tube(base, base + Vector3(0, a[1] * 0.3, 0), 2.6, 8, k.col(Kit.TRIM, seed), true)
			"fins":
				var p: PackedVector2Array = a[0]
				var step := maxi(1, p.size() / 8)
				for i in range(0, p.size(), step):
					var v: Vector2 = p[i]
					var out := Vector3(v.x, 0, v.y).normalized()
					var base := xf * Vector3(v.x, 0, v.y)
					var bxf := Transform3D(Basis(Vector3.UP, atan2(out.x, out.z)), base)
					k.box(bxf, Vector3(0, (a[1] + a[2]) * 0.5, 0.9), Vector3(0.8, a[2] - a[1], 1.8), k.col(Kit.STONE, seed))
			"pad":
				var y: float = a[0]
				var ang: float = a[1]
				var ext: float = a[2]
				var dir := xf.basis * Vector3(cos(ang), 0, sin(ang))
				var base := xf * Vector3(0, y, 0)
				var c := base + dir * (ext + 9.0)
				k.disc(c, 13.5, 0.9, 20, k.col(Kit.TRIM, seed), k.col(Kit.PAD, seed))
				k.tube(c + Vector3(0, -0.9, 0) - dir * 4.0, base + dir * (ext - 1.0) + Vector3(0, -14.0, 0), 1.1, 6, k.col(Kit.STONE, seed), true)
				k.tube(c + Vector3(0, -0.9, 0) + dir * 4.0, base + dir * (ext - 1.0) + Vector3(0, -22.0, 0), 1.1, 6, k.col(Kit.STONE, seed), true)


func _simplify(p: PackedVector2Array) -> PackedVector2Array:
	if p.size() <= 8:
		return p
	var out := PackedVector2Array()
	var step := p.size() / 8.0
	for i in 8:
		out.append(p[int(i * step)])
	return out


func _emit_skyway(k: Kit, s: Array) -> void:
	var a: Dictionary = s[0]
	var b: Dictionary = s[1]
	var h: float = s[2]
	var pa: Vector3 = a["pos"] + Vector3(0, h, 0)
	var pb: Vector3 = b["pos"] + Vector3(0, h, 0)
	var dir := (pb - pa).normalized()
	# Start and end inside each tower so the tube meets the facade.
	k.tube(pa + dir * 8.0, pb - dir * 8.0, 4.2, 12, k.col(Kit.GLASS, 0.5, 4.2, true), false)
	var len := pa.distance_to(pb)
	var n := int(len / 12.0)
	for i in range(1, n):
		var p := pa.lerp(pb, float(i) / n)
		k.tube(p - dir * 0.4, p + dir * 0.4, 4.6, 12, k.col(Kit.STONE, 0.5), true)
	k.tube(pa + dir * 8.0 + Vector3(0, -4.4, 0), pb - dir * 8.0 + Vector3(0, -4.4, 0), 0.8, 6, k.col(Kit.TRIM, 0.5), false)


func _build_cells() -> void:
	var near_kits := {}
	var far_kits := {}
	for b in buildings:
		var p: Vector3 = b["pos"]
		var ck := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		var fk := Vector2i(floori(p.x / FAR_CELL), floori(p.z / FAR_CELL))
		if not near_kits.has(ck):
			near_kits[ck] = Kit.new()
		if not far_kits.has(fk):
			far_kits[fk] = Kit.new()
		_emit_building(near_kits[ck], b, false)
		_emit_building(far_kits[fk], b, true)
	for s in skyways:
		var mid: Vector3 = ((s[0]["pos"] as Vector3) + (s[1]["pos"] as Vector3)) * 0.5
		var ck := Vector2i(floori(mid.x / CELL), floori(mid.z / CELL))
		if not near_kits.has(ck):
			near_kits[ck] = Kit.new()
		_emit_skyway(near_kits[ck], s)
		var fk := Vector2i(floori(mid.x / FAR_CELL), floori(mid.z / FAR_CELL))
		if not far_kits.has(fk):
			far_kits[fk] = Kit.new()
		var a: Dictionary = s[0]
		var bb: Dictionary = s[1]
		far_kits[fk].tube(a["pos"] + Vector3(0, s[2], 0), bb["pos"] + Vector3(0, s[2], 0), 4.2, 6, far_kits[fk].col(Kit.GLASS, 0.5), false)
	for fk in far_kits:
		var mi := MeshInstance3D.new()
		mi.name = "Far_%d_%d" % [fk.x, fk.y]
		mi.mesh = (far_kits[fk] as Kit).commit()
		mi.material_override = mat
		mi.position = Vector3.ZERO
		mi.visibility_range_begin = FAR_BEGIN
		mi.visibility_range_begin_margin = 60.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		add_child(mi)
		far_nodes[fk] = mi
	for ck in near_kits:
		var mi := MeshInstance3D.new()
		mi.name = "Cell_%d_%d" % [ck.x, ck.y]
		mi.mesh = (near_kits[ck] as Kit).commit()
		mi.material_override = mat
		add_child(mi)
		var c := Vector3((ck.x + 0.5) * CELL, 0, (ck.y + 0.5) * CELL)
		var fk := Vector2i(floori(c.x / FAR_CELL), floori(c.z / FAR_CELL))
		if far_nodes.has(fk):
			mi.visibility_parent = mi.get_path_to(far_nodes[fk])
		cells[ck] = mi
	# Occluders: the solid cores of the big towers hide what is behind them.
	for b in buildings:
		if b["h"] < 50.0:
			continue
		var s: Dictionary = b["sections"][min(2, b["sections"].size() - 1)]
		var prof: PackedVector2Array = s["prof"]
		var ext := Vector2.ZERO
		for v in prof:
			ext = Vector2(maxf(ext.x, absf(v.x)), maxf(ext.y, absf(v.y)))
		var occ := OccluderInstance3D.new()
		var box := BoxOccluder3D.new()
		box.size = Vector3(ext.x * 1.3, b["h"] * 0.9, ext.y * 1.3)
		occ.occluder = box
		occ.transform = (b["xf"] as Transform3D) * Transform3D(Basis.IDENTITY, Vector3(0, b["h"] * 0.45, 0))
		add_child(occ)


func _build_collision() -> void:
	for b in buildings:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.transform = b["xf"]
		for s in b["sections"]:
			if not s["collide"]:
				continue
			var pts := PackedVector3Array()
			for v in s["prof"]:
				pts.append(Vector3(v.x, s["y0"], v.y))
				pts.append(Vector3(v.x, s["y1"], v.y))
			var cs := CollisionShape3D.new()
			var sh := ConvexPolygonShape3D.new()
			sh.points = pts
			cs.shape = sh
			body.add_child(cs)
		_bodies.add_child(body)
		b["body"] = body
	# The podium: an octagonal slab.
	var body := StaticBody3D.new()
	var pts := PackedVector3Array()
	for v in Kit.ngon(radius / cos(PI / 8.0), 8, PI / 8.0):
		pts.append(Vector3(center.x + v.x, podium_y - 6.0, center.z + v.y))
		pts.append(Vector3(center.x + v.x, podium_y, center.z + v.y))
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	sh.points = pts
	cs.shape = sh
	body.add_child(cs)
	_bodies.add_child(body)


# ----------------------------------------------------------------------------------------------- ground

func _build_ground() -> void:
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = load("res://shaders/city_ground.gdshader")
	ground_mat.set_shader_parameter("center", Vector2(center.x, center.z))
	ground_mat.set_shader_parameter("block", BLOCK)
	ground_mat.set_shader_parameter("avenue", AVENUE)
	ground_mat.set_shader_parameter("boulevard", BOULEVARD)
	ground_mat.set_shader_parameter("radius", radius)
	# Park blocks as a small lookup texture.
	var n := int(radius / BLOCK) + 2
	var img := Image.create(n * 2 + 1, n * 2 + 1, false, Image.FORMAT_R8)
	for k in parks:
		var kk: Vector2i = k
		if absi(kk.x) <= n and absi(kk.y) <= n:
			img.set_pixel(kk.x + n, kk.y + n, Color(1, 0, 0))
	ground_mat.set_shader_parameter("parks", ImageTexture.create_from_image(img))
	ground_mat.set_shader_parameter("parks_n", float(n))
	var k := Kit.new()
	var oct := Kit.ngon(radius / cos(PI / 8.0), 8, PI / 8.0)
	# Top surface as a grid of tiles so it is lit and culled in pieces, and a white plinth wall.
	var tiles := 12
	var size := radius * 2.0 / tiles
	for tz in tiles:
		for tx in tiles:
			var x0 := -radius + tx * size
			var z0 := -radius + tz * size
			var poly := Geometry2D.intersect_polygons(PackedVector2Array([Vector2(x0, z0), Vector2(x0 + size, z0), Vector2(x0 + size, z0 + size), Vector2(x0, z0 + size)]), oct)
			for p in poly:
				k.cap(Transform3D(Basis.IDENTITY, Vector3(center.x, 0, center.z)), p, podium_y, true, Color(0, 0, 0, 1))
	var ground := MeshInstance3D.new()
	ground.name = "CityGround"
	ground.mesh = k.commit()
	ground.material_override = ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	var wall := Kit.new()
	wall.prism(Transform3D(Basis.IDENTITY, Vector3(center.x, 0, center.z)), oct, podium_y - 8.0, podium_y, wall.col(Kit.STONE, 0.3, 2.0, false), false)
	wall.band(Transform3D(Basis.IDENTITY, Vector3(center.x, 0, center.z)), oct, podium_y - 0.5, 0.7, 0.4, wall.col(Kit.TRIM, 0.3), false)
	var wm := MeshInstance3D.new()
	wm.mesh = wall.commit()
	wm.material_override = mat
	add_child(wm)
	# Reflecting pools.
	for pl in pools:
		var c: Vector3 = pl[0]
		var sz: Vector2 = pl[1]
		var pm := MeshInstance3D.new()
		var q := PlaneMesh.new()
		q.size = sz
		pm.mesh = q
		pm.position = c + Vector3(0, -0.25, 0)
		pm.material_override = G.world.water.river_mat if G.world and G.world.water else null
		pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pm)
		var rim := Kit.new()
		rim.band(Transform3D(Basis.IDENTITY, c), Kit.rect(sz.x, sz.y), -0.6, 0.8, 0.9, rim.col(Kit.STONE, 0.2), false)
		var rm := MeshInstance3D.new()
		rm.mesh = rim.commit()
		rm.material_override = mat
		add_child(rm)
	# Lamp posts (one MultiMesh) with glowing heads.
	_build_lamps()


func _build_lamps() -> void:
	var lk := Kit.new()
	lk.tube(Vector3.ZERO, Vector3(0, 7.5, 0), 0.12, 6, lk.col(Kit.METAL, 0.1), true)
	lk.tube(Vector3(0, 7.4, 0), Vector3(1.4, 7.6, 0), 0.08, 5, lk.col(Kit.METAL, 0.1), true)
	var mesh := lk.commit()
	var head := BoxMesh.new()
	head.size = Vector3(0.9, 0.12, 0.35)
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.9, 0.9, 0.88)
	hm.emission_enabled = true
	hm.emission = Color(1.0, 0.86, 0.62)
	hm.emission_energy_multiplier = 0.0
	head.material = hm
	_lamp_mat = hm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = lamps.size()
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.mesh = head
	mm2.instance_count = lamps.size()
	for i in lamps.size():
		var yaw := G.hash2(i, 3, 1) * 0.0
		var b := Basis(Vector3.UP, yaw)
		mm.set_instance_transform(i, Transform3D(b, lamps[i]))
		mm2.set_instance_transform(i, Transform3D(b, lamps[i] + Vector3(1.3, 7.5, 0)))
	var a := MultiMeshInstance3D.new()
	a.multimesh = mm
	a.material_override = mat
	a.visibility_range_end = 900.0
	add_child(a)
	var h2 := MultiMeshInstance3D.new()
	h2.multimesh = mm2
	h2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h2.visibility_range_end = 2500.0
	add_child(h2)


var _lamp_mat: StandardMaterial3D


func _process(_delta: float) -> void:
	if _lamp_mat and G.sky:
		var night := 1.0 - (G.sky as SkySystem).daylight
		_lamp_mat.emission_energy_multiplier = night * 6.0
		ground_mat.set_shader_parameter("lamp_glow", night)
