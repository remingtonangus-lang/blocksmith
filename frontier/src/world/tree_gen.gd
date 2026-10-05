class_name TreeGen
extends RefCounted
## Procedural trees and shrubs for the Sable River country. Each species is a parameter set for a recursive branch
## grower; output is an ArrayMesh with surface 0 = bark tubes, surface 1 = foliage cards. Vertex COLOR carries wind
## data for shaders/foliage.gdshader: r = sway weight (0 at the root .. 1 at twig tips), g = branch phase,
## b = branch level / 3, a = 1 for foliage. UV2 holds the card's local offset for leaf flutter.
## Optional shrub keys: "spread" = crown radius / height (default 0.5: as wide as tall; sagebrush is low and wide),
## "lobes" = irregularity of the outline (uneven dome, lopsided sides) so no two bushes share a silhouette.

const SPECIES := {
	"ponderosa": {"height": [16.0, 26.0], "trunk_r": 0.32, "levels": 2, "branches": [26, 5], "start": 0.38,
		"angle": [72.0, 45.0], "len": [0.28, 0.35], "droop": 0.25, "crown": "cone_round", "leaf": "needles",
		"card": [0.75, 0.6], "cards_per_tip": 3, "fill": 1100, "bark": "pine", "leaf_tint": Color(0.36, 0.42, 0.22), "curve": 0.04},
	"fir": {"height": [12.0, 22.0], "trunk_r": 0.26, "levels": 2, "branches": [40, 4], "start": 0.12,
		"angle": [88.0, 40.0], "len": [0.22, 0.4], "droop": 0.45, "crown": "cone", "leaf": "needles",
		"card": [0.7, 0.55], "cards_per_tip": 3, "fill": 1300, "bark": "pine", "leaf_tint": Color(0.18, 0.28, 0.17), "curve": 0.02},
	"cottonwood": {"height": [13.0, 20.0], "trunk_r": 0.45, "levels": 3, "branches": [7, 5, 4], "start": 0.3,
		"angle": [38.0, 42.0, 45.0], "len": [0.55, 0.5, 0.45], "droop": 0.08, "crown": "round", "leaf": "broad",
		"card": [1.2, 1.0], "cards_per_tip": 2, "fill": 936, "bark": "cottonwood", "leaf_tint": Color(0.86, 0.68, 0.18), "curve": 0.18},
	"aspen": {"height": [9.0, 15.0], "trunk_r": 0.14, "levels": 2, "branches": [14, 5], "start": 0.5,
		"angle": [40.0, 45.0], "len": [0.25, 0.4], "droop": 0.05, "crown": "oval", "leaf": "broad",
		"card": [0.8, 0.7], "cards_per_tip": 2, "fill": 540, "bark": "aspen", "leaf_tint": Color(0.95, 0.74, 0.16), "curve": 0.05},
	"juniper": {"height": [3.0, 6.0], "trunk_r": 0.16, "levels": 3, "branches": [5, 4, 3], "start": 0.08,
		"angle": [42.0, 45.0, 40.0], "len": [0.65, 0.5, 0.4], "droop": 0.0, "crown": "bush", "leaf": "scale",
		"card": [0.9, 0.8], "cards_per_tip": 3, "fill": 360, "bark": "pine", "leaf_tint": Color(0.27, 0.33, 0.24), "curve": 0.35},
	"oak": {"height": [5.0, 9.0], "trunk_r": 0.22, "levels": 3, "branches": [6, 4, 3], "start": 0.25,
		"angle": [48.0, 45.0, 45.0], "len": [0.6, 0.5, 0.4], "droop": 0.1, "crown": "round", "leaf": "broad",
		"card": [1.0, 0.85], "cards_per_tip": 2, "fill": 504, "bark": "cottonwood", "leaf_tint": Color(0.55, 0.42, 0.16), "curve": 0.3},
	"mesquite": {"height": [3.0, 5.0], "trunk_r": 0.12, "levels": 3, "branches": [4, 4, 3], "start": 0.05,
		"angle": [55.0, 50.0, 45.0], "len": [0.7, 0.55, 0.45], "droop": 0.15, "crown": "bush", "leaf": "fine",
		"card": [0.9, 0.7], "cards_per_tip": 2, "fill": 252, "bark": "cottonwood", "leaf_tint": Color(0.42, 0.46, 0.25), "curve": 0.45},
	"snag": {"height": [8.0, 16.0], "trunk_r": 0.28, "levels": 2, "branches": [9, 3], "start": 0.35,
		"angle": [70.0, 40.0], "len": [0.25, 0.3], "droop": 0.1, "crown": "cone", "leaf": "",
		"card": [1.0, 1.0], "cards_per_tip": 0, "bark": "dead", "leaf_tint": Color(1, 1, 1), "curve": 0.08},
	"sagebrush": {"height": [0.7, 1.3], "trunk_r": 0.04, "levels": 2, "branches": [6, 3], "start": 0.0,
		"angle": [35.0, 40.0], "len": [0.8, 0.5], "droop": 0.0, "crown": "bush", "leaf": "sage",
		"card": [0.5, 0.42], "cards_per_tip": 3, "fill": 170, "bark": "dead", "leaf_tint": Color(0.52, 0.56, 0.46), "curve": 0.3,
		"spread": 0.95, "lobes": 0.32},
	"rabbitbrush": {"height": [0.6, 1.1], "trunk_r": 0.03, "levels": 2, "branches": [7, 3], "start": 0.0,
		"angle": [30.0, 35.0], "len": [0.8, 0.5], "droop": 0.0, "crown": "bush", "leaf": "fine",
		"card": [0.45, 0.4], "cards_per_tip": 3, "fill": 130, "bark": "dead", "leaf_tint": Color(0.85, 0.72, 0.22), "curve": 0.25,
		"spread": 0.75, "lobes": 0.22},
}

## Level-of-detail meshes built from one growth pass (identical skeleton and card placement, so switching LODs never
## changes the tree's shape): LOD 0 = everything; LOD 1 = every 2nd leaf card (1.4x larger), thinner tubes, half the
## tube rings; LOD 2 = every LOD_CARD_STEP[2]-th card (larger still), trunk and first-order boughs only.
const LODS := 3
const LOD_CARD_STEP := [1, 2, 7]
const LOD_RING_STEP := [1, 2, 3]
const LOD_MAX_TUBE_LEVEL := [9, 9, 1]

## Geometry buffers of one LOD.
class Buf:
	var bark := PackedVector3Array()
	var bark_n := PackedVector3Array()
	var bark_uv := PackedVector2Array()
	var bark_col := PackedColorArray()
	var bark_idx := PackedInt32Array()
	var leaf := PackedVector3Array()
	var leaf_n := PackedVector3Array()
	var leaf_uv := PackedVector2Array()
	var leaf_uv2 := PackedVector2Array()
	var leaf_col := PackedColorArray()
	var leaf_idx := PackedInt32Array()

var rng := RandomNumberGenerator.new()
var _bufs: Array = []
var _card_n := 0                      # running card counter: LOD l keeps cards with _card_n % LOD_CARD_STEP[l] == 0
var _sp: Dictionary
var _height := 10.0
var _crown_center := Vector3.ZERO
var _crown_radius := 3.0
var _leaf_row := 0
var _anchors: Array[Vector3] = []     # points on outer branches (crown fill attaches clusters here)
var _lobe_ph := Vector3.ZERO          # per-build phases of the shrub outline lobes
var _anchor_dirs: Array[Vector3] = []

## Build one tree variant at one level of detail (0 = full).
func build(species: String, seed: int, detail: int = 0) -> ArrayMesh:
	return build_lods(species, seed)[clampi(detail, 0, LODS - 1)]

## Build every LOD of one tree variant in a single growth pass: [lod0, lod1, lod2].
func build_lods(species: String, seed: int) -> Array:
	_sp = SPECIES[species]
	rng.seed = seed
	_reset()
	_height = rng.randf_range(_sp.height[0], _sp.height[1])
	_leaf_row = {"needles": 0, "broad": 1, "scale": 2, "fine": 3, "sage": 2}.get(_sp.leaf, 0)
	var crown_top := _height
	var crown_bot := _height * float(_sp.start)
	_crown_center = Vector3(0, (crown_top + crown_bot) * 0.5, 0)
	_crown_radius = maxf((crown_top - crown_bot) * 0.5, _height * 0.25)
	var trunk_dir := Vector3(rng.randf_range(-0.04, 0.04), 1.0, rng.randf_range(-0.04, 0.04)).normalized()
	if _sp.crown == "bush":
		# shrubs: several stems from the ground, leaning out further on wide shrubs
		var stems := rng.randi_range(3, 6)
		var lean := 0.6 * float(_sp.get("spread", 0.5)) / 0.5
		_lobe_ph = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		for s in stems:
			var d := Vector3(rng.randf_range(-lean, lean), 1.0, rng.randf_range(-lean, lean)).normalized()
			_branch(Vector3.ZERO, d, _height * rng.randf_range(0.8, 1.1), float(_sp.trunk_r) * rng.randf_range(0.6, 1.0), 0, rng.randf())
	else:
		_branch(Vector3.ZERO, trunk_dir, _height, float(_sp.trunk_r) * rng.randf_range(0.85, 1.15), 0, rng.randf())
	if int(_sp.cards_per_tip) > 0:
		_fill_crown()
	var out := []
	for l in LODS:
		out.append(_commit(_bufs[l]))
	return out

## Fill the crown volume with leaf clusters attached to the nearest outer-branch point, so every species reads as
## a full canopy with the right silhouette (cone, rounded cone, round, oval, bush).
func _fill_crown() -> void:
	if _anchors.is_empty():
		return
	var count: int = int(_sp.get("fill", 220))
	var crown_bot: float = _height * float(_sp.start)
	var crown_h := _height - crown_bot
	var shaped: bool = _sp.has("spread")
	var tries := 0
	var placed := 0
	while placed < count and tries < count * 6:
		tries += 1
		var t := rng.randf()
		var a := rng.randf() * TAU
		var rad := _crown_radius_at(t) * maxf(crown_h, _height * 0.3) * 0.5
		if shaped:
			# low irregular dome: widest a third of the way up, uneven top, lopsided outline
			var lob: float = _sp.lobes
			var top := 1.0 - lob * (0.5 + 0.5 * sin(a * 2.0 + _lobe_ph.z))
			t *= top
			var u := (t - 0.3) / 0.7
			var prof := lerpf(0.75, 1.0, t / 0.3) if t < 0.3 else sqrt(maxf(1.0 - u * u, 0.0))
			rad = float(_sp.spread) * _height * prof * (1.0 + lob * (0.6 * sin(a * 2.0 + _lobe_ph.x) + 0.4 * sin(a * 3.0 + _lobe_ph.y)))
		var y := crown_bot + t * crown_h
		var rr := rad * sqrt(rng.randf()) * (0.75 + 0.25 * rng.randf())
		# bias outward: leaves live at the crown surface, not the core
		rr = lerpf(rr, rad, 0.55)
		var p := Vector3(cos(a) * rr, y, sin(a) * rr)
		# nearest anchor
		var best := -1
		var bd := INF
		for i in range(0, _anchors.size(), 2 if _anchors.size() > 400 else 1):
			var d := _anchors[i].distance_squared_to(p)
			if d < bd:
				bd = d
				best = i
		if best < 0 or bd > pow(rad * 0.6 + 1.2, 2):
			continue
		var anchor := _anchors[best].lerp(p, 0.7 if shaped else 0.35)
		_cluster(anchor, _anchor_dirs[best])
		placed += 1

func _crown_radius_at(t: float) -> float:
	match _sp.crown:
		"cone": return lerpf(1.0, 0.05, pow(t, 0.9))
		"cone_round": return 0.95 * sin(clampf(t * 1.05, 0.0, 1.0) * PI * 0.92 + 0.12) * lerpf(1.0, 0.65, t)
		"round": return sin(clampf(t, 0.02, 0.98) * PI) * 1.05
		"oval": return sin(clampf(t, 0.02, 0.98) * PI) * 0.8
		_: return 1.0

## Append one leaf quad (bottom-left, bottom-right, top-right, top-left) to every LOD that keeps card number _card_n,
## scaled about its bottom centre so sparser LODs keep the canopy's coverage.
func _emit_card(bottom: Vector3, right_v: Vector3, up_v: Vector3, nrm: Vector3, uv0: Vector2, cols: Array) -> void:
	for l in LODS:
		var step: int = LOD_CARD_STEP[l]
		if _card_n % step != 0:
			continue
		var b: Buf = _bufs[l]
		var k := sqrt(float(step))
		var rv := right_v * k
		var uv := up_v * k
		var base := b.leaf.size()
		b.leaf.append(bottom - rv)
		b.leaf.append(bottom + rv)
		b.leaf.append(bottom + rv + uv)
		b.leaf.append(bottom - rv + uv)
		b.leaf_uv.append(Vector2(uv0.x, uv0.y + 0.25))
		b.leaf_uv.append(Vector2(uv0.x + 0.25, uv0.y + 0.25))
		b.leaf_uv.append(Vector2(uv0.x + 0.25, uv0.y))
		b.leaf_uv.append(uv0)
		b.leaf_uv2.append(Vector2(-0.5, 0))
		b.leaf_uv2.append(Vector2(0.5, 0))
		b.leaf_uv2.append(Vector2(0.5, 1))
		b.leaf_uv2.append(Vector2(-0.5, 1))
		for q in 4:
			b.leaf_n.append(nrm)
			b.leaf_col.append(cols[q])
		b.leaf_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	_card_n += 1

## Two crossed cards (one cluster) at p, oriented along the branch with a droop for conifers.
func _cluster(p: Vector3, dir: Vector3) -> void:
	var card: Array = _sp.card
	var w: float = card[0] * rng.randf_range(0.75, 1.15)
	var h: float = card[1] * rng.randf_range(0.75, 1.15)
	var out := (p - Vector3(0, _crown_center.y, 0))
	out.y *= 0.5
	out = out.normalized() if out.length() > 0.01 else Vector3.UP
	var along := (dir * 0.6 + out * 0.4 + Vector3.DOWN * float(_sp.droop) * 0.5).normalized()
	var side := along.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var up2 := side.cross(along).normalized()
	var sway := clampf(p.y / maxf(_height, 0.5), 0.2, 1.0)
	var phase := rng.randf()
	var variant := rng.randi_range(0, 3)
	var nrm := (out * 0.8 + Vector3.UP * 0.2).normalized()
	var col := Color(sway, phase, 0.66, 1.0)
	var cols := [col, col, col, col]
	var uv0 := Vector2(variant * 0.25, _leaf_row * 0.25)
	# the two crossed cards of a cluster always share a LOD
	var n0 := _card_n
	for k in 2:
		_card_n = n0
		var right_v := (side if k == 0 else up2) * w * 0.5
		var up_v := along * h
		_emit_card(p - up_v * 0.2, right_v, up_v, nrm, uv0, cols)

func _reset() -> void:
	_anchors.clear()
	_anchor_dirs.clear()
	_card_n = 0
	_bufs = []
	for l in LODS:
		_bufs.append(Buf.new())

func _crown_scale(t: float) -> float:
	# relative branch length by height fraction t (0 crown base .. 1 top) for the crown silhouette
	match _sp.crown:
		"cone": return lerpf(1.0, 0.08, t)
		"cone_round": return lerpf(0.85, 0.15, pow(t, 1.3)) * (0.75 + 0.25 * sin(t * PI))
		"round": return 0.55 + 0.45 * sin(t * PI)
		"oval": return 0.45 + 0.55 * sin(t * PI)
		_: return 1.0

func _branch(origin: Vector3, dir: Vector3, length: float, radius: float, level: int, phase: float) -> void:
	var segs := clampi(int(length / (1.2 if level == 0 else 0.8)), 3, 10)
	var sides := 8 if level == 0 else (5 if level == 1 else 3)
	var pts: Array[Vector3] = []
	var p := origin
	var d := dir
	var curve: float = _sp.curve
	var droop: float = _sp.droop * (0.0 if level == 0 else 1.0)
	for i in segs + 1:
		pts.append(p)
		var bend := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)) * curve
		d = (d + bend + Vector3.DOWN * droop * (float(i) / segs) * 0.5).normalized()
		if level == 0:
			d = (d + Vector3.UP * 0.25).normalized()
		p += d * (length / segs)
	var r_tip := radius * (0.12 if level == 0 else 0.25)
	for l in LODS:
		if level > LOD_MAX_TUBE_LEVEL[l]:
			continue
		var lp := pts
		var ring: int = LOD_RING_STEP[l]
		if ring > 1:
			lp = []
			for i in range(0, pts.size(), ring):
				lp.append(pts[i])
			if (pts.size() - 1) % ring != 0:
				lp.append(pts[pts.size() - 1])
		var ls := sides if l == 0 else maxi(3, sides - 3 * l)
		_tube(_bufs[l], lp, radius, r_tip, ls, level, phase)
	if level >= 1:
		for i in range(1, pts.size()):
			_anchors.append(pts[i])
			_anchor_dirs.append((pts[i] - pts[i - 1]).normalized())
	var max_level: int = _sp.levels
	if level < max_level:
		var count: int = _sp.branches[level]
		var start := float(_sp.start) if level == 0 else 0.2
		for b in count:
			var t := lerpf(start, 0.97, (float(b) + rng.randf_range(0.0, 0.8)) / count)
			var idx := clampi(int(t * segs), 0, segs - 1)
			var f := t * segs - idx
			var bp := pts[idx].lerp(pts[idx + 1], f)
			var axis := (pts[idx + 1] - pts[idx]).normalized()
			var ang := deg_to_rad(float(_sp.angle[level]) * rng.randf_range(0.8, 1.2))
			var az := (b * 2.39996) + rng.randf_range(-0.4, 0.4)     # golden-angle phyllotaxis
			var perp := axis.cross(Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT).normalized()
			perp = perp.rotated(axis, az)
			var nd := (axis * cos(ang) + perp * sin(ang)).normalized()
			var rel := float(_sp.len[level]) * rng.randf_range(0.75, 1.2)
			var bl := length * rel
			if level == 0 and _sp.crown != "bush":
				var ct := clampf((bp.y - _height * start) / maxf(_height * (1.0 - start), 0.1), 0.0, 1.0)
				bl = _height * rel * _crown_scale(ct)
			var br := radius * lerpf(1.0, 0.25, t) * 0.55
			_branch(bp, nd, bl, maxf(br, 0.012), level + 1, rng.randf())
	if level >= max_level - (1 if max_level >= 3 else 0) and int(_sp.cards_per_tip) > 0:
		_foliage(pts, level, phase)

func _tube(b: Buf, pts: Array[Vector3], r0: float, r1: float, sides: int, level: int, phase: float) -> void:
	var base := b.bark.size()
	var n := pts.size()
	var vlen := 0.0
	for i in n:
		var t := float(i) / (n - 1)
		var r := lerpf(r0, r1, pow(t, 0.8))
		if level == 0 and i == 0:
			r *= 1.35          # root flare
		var axis := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(axis).normalized()
		if i > 0:
			vlen += pts[i].distance_to(pts[i - 1])
		var sway := clampf(pts[i].y / maxf(_height, 0.5), 0.0, 1.0) * (0.35 if level == 0 else 1.0)
		for s in sides + 1:
			var a := TAU * s / sides
			var nrm := (side * cos(a) + up * sin(a))
			b.bark.append(pts[i] + nrm * r)
			b.bark_n.append(nrm)
			b.bark_uv.append(Vector2(float(s) / sides * maxf(r0 * 6.0, 1.0), vlen / maxf(r0 * 4.0, 0.6)))
			b.bark_col.append(Color(sway, phase, level / 3.0, 0.0))
	for i in n - 1:
		for s in sides:
			var a := base + i * (sides + 1) + s
			var c := a + sides + 1
			b.bark_idx.append_array([a, c, a + 1, a + 1, c, c + 1])

func _foliage(pts: Array[Vector3], level: int, phase: float) -> void:
	var per_tip: int = _sp.cards_per_tip
	var n := pts.size()
	var card: Array = _sp.card
	# cards along the outer half of the branch
	for i in range(maxi(1, n / 3), n):
		for c in per_tip:
			if rng.randf() > 0.75 and i < n - 1:
				continue
			var p := pts[i] + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.15, 0.2), rng.randf_range(-0.2, 0.2))
			var w: float = card[0] * rng.randf_range(0.8, 1.2)
			var h: float = card[1] * rng.randf_range(0.8, 1.2)
			var out := (p - _crown_center)
			out.y *= 0.6
			out = out.normalized() if out.length() > 0.01 else Vector3.UP
			var axis := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var rnd := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var right := axis.cross(rnd).normalized()
			if right.length() < 0.1:
				right = Vector3.RIGHT
			var upv := right.cross(axis).normalized()
			var right_v := right * w * 0.5
			var up_v := (axis * 0.6 + upv * 0.4).normalized() * h
			var variant := rng.randi_range(0, 3)
			var sway := clampf(p.y / maxf(_height, 0.5), 0.2, 1.0)
			# normals bent outward from the crown centre: volumetric shading of the canopy
			var nrm := (out * 0.75 + upv * 0.25).normalized()
			var cols := []
			for k in 4:
				cols.append(Color(sway, phase + rng.randf() * 0.3, level / 3.0, 1.0))
			_emit_card(p - up_v * 0.15, right_v, up_v, nrm, Vector2(variant * 0.25, _leaf_row * 0.25), cols)

func _commit(b: Buf) -> ArrayMesh:
	var m := ArrayMesh.new()
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = b.bark
	a[Mesh.ARRAY_NORMAL] = b.bark_n
	a[Mesh.ARRAY_TEX_UV] = b.bark_uv
	a[Mesh.ARRAY_COLOR] = b.bark_col
	a[Mesh.ARRAY_INDEX] = b.bark_idx
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	if b.leaf.size() > 0:
		var c := []
		c.resize(Mesh.ARRAY_MAX)
		c[Mesh.ARRAY_VERTEX] = b.leaf
		c[Mesh.ARRAY_NORMAL] = b.leaf_n
		c[Mesh.ARRAY_TEX_UV] = b.leaf_uv
		c[Mesh.ARRAY_TEX_UV2] = b.leaf_uv2
		c[Mesh.ARRAY_COLOR] = b.leaf_col
		c[Mesh.ARRAY_INDEX] = b.leaf_idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, c)
	return m

## Leaf atlas (4 x 4 cells: rows needles, broad leaves, scale/sage sprays, fine leaflets; 4 variants each).
## RGB = grey-green detail (tinted per species in the shader), A = coverage. Painted procedurally, 1024 px.
static func make_leaf_atlas() -> ImageTexture:
	var size := 1024
	var cell := size / 4
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5, 0.0))
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for row in 4:
		for v in 4:
			var ox := v * cell
			var oy := row * cell
			match row:
				0: _paint_needles(img, ox, oy, cell, r)
				1: _paint_broad(img, ox, oy, cell, r)
				2: _paint_scale(img, ox, oy, cell, r)
				3: _paint_fine(img, ox, oy, cell, r)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(preserve_alpha_coverage(img, 4, 0.45))

## Box-filtered mips average leaves with the gaps between them, so a card's alpha-tested coverage shrinks with every
## level and distant crowns thin out to twigs. Rescale each mip's alpha, per atlas cell, so the same fraction of
## texels passes `cut` as at full resolution (coverage-preserving mips). Cells are `cells` x `cells` squares.
static func preserve_alpha_coverage(img: Image, cells: int, cut: float) -> Image:
	var w := img.get_width()
	var data := img.get_data()
	var cut_b := int(cut * 255.0)
	var cell0 := w / cells
	# reference coverage per cell at full resolution (every other texel)
	var cov := PackedFloat32Array()
	cov.resize(cells * cells)
	for cy in cells:
		for cx in cells:
			var n := 0
			var hit := 0
			for y in range(cy * cell0, (cy + 1) * cell0, 2):
				var row := y * w
				for x in range(cx * cell0, (cx + 1) * cell0, 2):
					n += 1
					if data[(row + x) * 4 + 3] >= cut_b:
						hit += 1
			cov[cy * cells + cx] = float(hit) / maxf(n, 1)
	var hist := PackedInt32Array()
	for m in range(1, img.get_mipmap_count() + 1):
		var mw := maxi(w >> m, 1)
		var cs := mw / cells
		if cs < 1:
			break
		var off := img.get_mipmap_offset(m)
		for cy in cells:
			for cx in cells:
				hist.resize(0)
				hist.resize(256)
				for y in range(cy * cs, (cy + 1) * cs):
					var row := off + y * mw * 4
					for x in range(cx * cs, (cx + 1) * cs):
						hist[data[row + x * 4 + 3]] += 1
				# alpha value T with the reference fraction of texels at or above it
				var want := int(round(cov[cy * cells + cx] * cs * cs))
				if want <= 0:
					continue
				var acc := 0
				var t := 255
				while t > 0:
					acc += hist[t]
					if acc >= want:
						break
					t -= 1
				var k := clampf(float(cut_b) / maxf(t, 1.0), 1.0, 4.0)
				if k <= 1.001:
					continue
				for y in range(cy * cs, (cy + 1) * cs):
					var row := off + y * mw * 4
					for x in range(cx * cs, (cx + 1) * cs):
						var i := row + x * 4 + 3
						data[i] = mini(int(data[i] * k + 0.5), 255)
	return Image.create_from_data(w, img.get_height(), true, img.get_format(), data)

static func _plot(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var o := img.get_pixel(x, y)
	var a := c.a + o.a * (1.0 - c.a)
	if a <= 0.0:
		return
	var rgb := (Color(c.r, c.g, c.b) * c.a + Color(o.r, o.g, o.b) * o.a * (1.0 - c.a)) / a
	img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, a))

static func _line(img: Image, a: Vector2, b: Vector2, w: float, c: Color, clip: Rect2i) -> void:
	var steps := int(a.distance_to(b)) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		var ww := w
		for dy in range(-int(ww) - 1, int(ww) + 2):
			for dx in range(-int(ww) - 1, int(ww) + 2):
				var d := Vector2(dx, dy).length()
				if d <= ww:
					var x := int(p.x) + dx
					var y := int(p.y) + dy
					if clip.has_point(Vector2i(x, y)):
						_plot(img, x, y, Color(c.r, c.g, c.b, c.a * clampf(ww - d + 0.5, 0.0, 1.0)))

static func _paint_needles(img: Image, ox: int, oy: int, cell: int, r: RandomNumberGenerator) -> void:
	var clip := Rect2i(ox + 2, oy + 2, cell - 4, cell - 4)
	# twig running up the card with long needle bundles
	var base := Vector2(ox + cell * 0.5, oy + cell * 0.97)
	var tip := Vector2(ox + cell * 0.5 + r.randf_range(-12, 12), oy + cell * 0.08)
	_line(img, base, tip, 2.2, Color(0.32, 0.25, 0.18, 1.0), clip)
	for k in 150:
		var t := r.randf_range(0.02, 1.0)
		var p := base.lerp(tip, t)
		for j in 7:
			var ang := r.randf_range(-PI, PI)
			var ln := r.randf_range(cell * 0.10, cell * 0.24) * (1.0 - t * 0.4)
			var e := p + Vector2(cos(ang), sin(ang)) * ln
			var g := r.randf_range(0.55, 0.95)
			_line(img, p, e, 0.9, Color(g, g * 1.04, g * 0.85, 0.95), clip)

static func _paint_broad(img: Image, ox: int, oy: int, cell: int, r: RandomNumberGenerator) -> void:
	var clip := Rect2i(ox + 2, oy + 2, cell - 4, cell - 4)
	for k in 58:
		var cx := ox + r.randf_range(cell * 0.14, cell * 0.86)
		var cy := oy + r.randf_range(cell * 0.12, cell * 0.85)
		var rad := r.randf_range(cell * 0.07, cell * 0.12)
		var rot := r.randf_range(0, TAU)
		var g := r.randf_range(0.6, 1.0)
		var col := Color(g, g * r.randf_range(0.9, 1.05), g * 0.8, 1.0)
		for y in range(-int(rad * 1.6), int(rad * 1.6) + 1):
			for x in range(-int(rad * 1.6), int(rad * 1.6) + 1):
				var q := Vector2(x, y).rotated(rot)
				# heart/ovate leaf (cottonwood/aspen): ellipse with a pointed tip
				var e := pow(q.x / rad, 2.0) + pow(q.y / (rad * 1.25), 2.0) + maxf(0.0, -q.y / rad) * 0.25
				if e < 1.0:
					var vein := 1.0 - 0.25 * exp(-absf(q.x) * 1.5)
					var shade := 0.85 + 0.15 * (q.x / rad)
					var px := int(cx) + x
					var py := int(cy) + y
					if clip.has_point(Vector2i(px, py)):
						_plot(img, px, py, Color(col.r * vein * shade, col.g * vein * shade, col.b * vein * shade, clampf((1.0 - e) * 6.0, 0.0, 1.0)))
		_line(img, Vector2(cx, cy), Vector2(ox + cell * 0.5, oy + cell * 0.98), 0.8, Color(0.35, 0.3, 0.2, 0.9), clip)

static func _paint_scale(img: Image, ox: int, oy: int, cell: int, r: RandomNumberGenerator) -> void:
	var clip := Rect2i(ox + 2, oy + 2, cell - 4, cell - 4)
	for k in 16:
		var base := Vector2(ox + cell * 0.5 + r.randf_range(-20, 20), oy + cell * 0.95)
		var ang := r.randf_range(-PI * 0.85, -PI * 0.15)
		var ln := r.randf_range(cell * 0.4, cell * 0.8)
		var tip := base + Vector2(cos(ang), sin(ang)) * ln
		for s in 60:
			var t := float(s) / 60.0
			var p := base.lerp(tip, t)
			var g := r.randf_range(0.55, 0.9)
			var rad := lerpf(5.0, 2.0, t) * r.randf_range(0.8, 1.3)
			for j in 2:
				var side := Vector2(-(tip - base).y, (tip - base).x).normalized() * r.randf_range(-6, 6)
				_line(img, p + side, p + side * 1.5 + (tip - base).normalized() * 4.0, rad * 0.5, Color(g, g * 1.02, g * 0.9, 1.0), clip)

static func _paint_fine(img: Image, ox: int, oy: int, cell: int, r: RandomNumberGenerator) -> void:
	var clip := Rect2i(ox + 2, oy + 2, cell - 4, cell - 4)
	for k in 12:
		var base := Vector2(ox + cell * 0.5, oy + cell * 0.97)
		var ang := r.randf_range(-PI * 0.9, -PI * 0.1)
		var tip := base + Vector2(cos(ang), sin(ang)) * r.randf_range(cell * 0.45, cell * 0.85)
		_line(img, base, tip, 1.0, Color(0.38, 0.32, 0.22, 1.0), clip)
		for s in 22:
			var t := float(s + 2) / 24.0
			var p := base.lerp(tip, t)
			var dirv := (tip - base).normalized()
			var nrm := Vector2(-dirv.y, dirv.x)
			for sgn in [-1.0, 1.0]:
				var e: Vector2 = p + nrm * sgn * r.randf_range(7, 13) + dirv * 4.0
				var g := r.randf_range(0.6, 1.0)
				_line(img, p, e, 1.6, Color(g, g, g * 0.75, 1.0), clip)
