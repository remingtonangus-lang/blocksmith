class_name WorldGen
extends RefCounted
## The landscape: a 16 km island continent. Northern mountains (snow above ~1300 m), the Cinder Pact's western
## plateau cut by canyons, rolling forested hills in the south, the Capital's coastal plain in the east, a main
## river from the mountains to the eastern sea plus a tributary from the plateau. Heights live in a 2048^2
## float grid (8 m texels) that the GPU samples with the same bilinear filter as height_at(), plus a tileable
## 0.25 m detail layer. Everything is deterministic for a seed and cached in user://.

const GEN_VERSION := 15
const SIZE := 16384.0
const HALF := 8192.0
const N := 2048
const CELL := SIZE / N
const DETAIL_N := 256
const DETAIL_PERIOD := 64.0
const DETAIL_AMP := 0.45
const SEA := 0.0
const SNOW_LINE := 1300.0

var seed := 1337
var heights := PackedFloat32Array()
var water := PackedFloat32Array()      # river / lake surface height per texel, -1e4 where none
var mask := PackedByteArray()          # RGBA per texel: r road, g urban, b wet, a forest density
var detail := PackedFloat32Array()     # DETAIL_N^2 tileable detail heights (-1..1)
var rivers: Array = []                 # [{ "pts": PackedVector3Array (x, surface y, z), "w": PackedFloat32Array }]
var roads: Array = []                  # [{ "pts": PackedVector3Array (x, deck y, z), "name": String }]
var sites := {}                        # name -> Vector3
var progress := 0.0
var stage := ""

var _n_warp := FastNoiseLite.new()
var _n_coast := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _n_hills := FastNoiseLite.new()
var _n_region := FastNoiseLite.new()
var _n_plat := FastNoiseLite.new()
var _n_canyon := FastNoiseLite.new()
var _n_forest := FastNoiseLite.new()
var _rows: Array = []

# Named places (x, z); y is filled in after generation.
const SITE_XZ := {
	"capital": Vector2(4300, 250), "harbor": Vector2(5650, 1750), "citadel": Vector2(2500, -900),
	"radar": Vector2(500, -3700), "fort_lumen": Vector2(-700, 1300), "front": Vector2(-1750, 1250),
	"cinder_camp": Vector2(-4300, 700), "cinder_outpost": Vector2(-2900, 2300), "forest": Vector2(1100, 3500),
	"spawn": Vector2(2420, -760), "artillery": Vector2(250, 1650), "airfield": Vector2(3300, -2300),
	"sea_patrol": Vector2(7300, 900),
}
# Flattened pads: name -> [radius, soft edge, height offset above local ground (or absolute if > 1e3)]
const FLATTEN := {
	"capital": [1700.0, 700.0, 0.0], "harbor": [420.0, 260.0, 0.0], "citadel": [260.0, 200.0, 0.0],
	"radar": [230.0, 200.0, 0.0], "fort_lumen": [240.0, 180.0, 0.0], "cinder_camp": [260.0, 200.0, 0.0],
	"cinder_outpost": [160.0, 140.0, 0.0], "artillery": [120.0, 120.0, 0.0], "airfield": [700.0, 400.0, 0.0],
	"front": [600.0, 500.0, 0.0],
}
const RIVER_MAIN := [Vector2(-350, -5700), Vector2(-500, -4300), Vector2(-150, -3000), Vector2(500, -1700),
	Vector2(1050, -500), Vector2(1350, 700), Vector2(2500, 1350), Vector2(3800, 1750), Vector2(5000, 1900),
	Vector2(5650, 1750), Vector2(6400, 1700), Vector2(8000, 1800)]
const RIVER_TRIB := [Vector2(-5300, -1600), Vector2(-4100, -900), Vector2(-3100, -200), Vector2(-2200, 450),
	Vector2(-1300, 750), Vector2(-200, 950), Vector2(1350, 700)]


func _init(s: int = 1337) -> void:
	seed = s
	var conf := [
		[_n_warp, 1.0 / 3200.0, 3, FastNoiseLite.FRACTAL_FBM],
		[_n_coast, 1.0 / 2600.0, 4, FastNoiseLite.FRACTAL_FBM],
		[_n_ridge, 1.0 / 2900.0, 6, FastNoiseLite.FRACTAL_RIDGED],
		[_n_hills, 1.0 / 1500.0, 5, FastNoiseLite.FRACTAL_FBM],
		[_n_region, 1.0 / 4200.0, 2, FastNoiseLite.FRACTAL_FBM],
		[_n_plat, 1.0 / 1100.0, 4, FastNoiseLite.FRACTAL_FBM],
		[_n_canyon, 1.0 / 1300.0, 3, FastNoiseLite.FRACTAL_FBM],
		[_n_forest, 1.0 / 700.0, 3, FastNoiseLite.FRACTAL_FBM],
	]
	var k := 0
	for c in conf:
		var n: FastNoiseLite = c[0]
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.seed = seed * 31 + k * 977
		n.frequency = c[1]
		n.fractal_octaves = c[2]
		n.fractal_type = c[3]
		n.fractal_gain = 0.5
		n.fractal_lacunarity = 2.05
		k += 1
	_n_ridge.fractal_weighted_strength = 0.6


# --------------------------------------------------------------------------------------------- generation

func cache_path() -> String:
	return "user://world_s%d_v%d.bin" % [seed, GEN_VERSION]


func generate(use_cache: bool = true) -> void:
	var t0 := Time.get_ticks_msec()
	_make_detail()
	if use_cache and _load_cache():
		_finish_sites()
		stage = "cached"
		progress = 1.0
		print("world: loaded cache in %d ms" % (Time.get_ticks_msec() - t0))
		return
	stage = "shaping the land"
	_rows.resize(N)
	var task := WorkerThreadPool.add_group_task(_gen_row, N, -1, true, "worldgen rows")
	WorkerThreadPool.wait_for_group_task_completion(task)
	heights = PackedFloat32Array()
	heights.resize(N * N)
	for z in N:
		var row: PackedFloat32Array = _rows[z]
		for x in N:
			heights[z * N + x] = row[x]
	_rows.clear()
	progress = 0.45
	print("world: base heights %d ms" % (Time.get_ticks_msec() - t0))
	stage = "flattening sites"
	_flatten_sites()
	progress = 0.55
	stage = "carving rivers"
	water = PackedFloat32Array()
	water.resize(N * N)
	water.fill(-10000.0)
	mask = PackedByteArray()
	mask.resize(N * N * 4)
	rivers.clear()
	rivers.append(_carve_river(RIVER_MAIN, 30.0, 150.0, 3.5, 7.0))
	rivers.append(_carve_river(RIVER_TRIB, 18.0, 60.0, 2.5, 4.0))
	for r in rivers:
		_river_finish(r)
	progress = 0.8
	print("world: rivers %d ms" % (Time.get_ticks_msec() - t0))
	stage = "planting forests"
	_paint_mask()
	progress = 0.88
	stage = "laying roads"
	_build_roads()
	print("world: roads %d ms" % (Time.get_ticks_msec() - t0))
	progress = 0.95
	_save_cache()
	_finish_sites()
	progress = 1.0
	stage = "done"
	print("world: generated in %d ms" % (Time.get_ticks_msec() - t0))


func _smooth01(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Raw landscape height before rivers and sites.
func base_height(x: float, z: float) -> float:
	var u := x / HALF
	var v := z / HALF
	var wx := _n_warp.get_noise_2d(x, z) * 0.16
	var wz := _n_warp.get_noise_2d(x + 7100.0, z - 3900.0) * 0.16
	var d := Vector2(u * 0.97 + wx, v + wz).length() + _n_coast.get_noise_2d(x, z) * 0.11
	var land := 1.0 - _smooth01(0.6, 0.93, d)
	var reg := _n_region.get_noise_2d(x, z)
	var north := _smooth01(-0.12, -0.55, v + reg * 0.18)
	var west := _smooth01(-0.18, -0.48, u + reg * 0.14) * (1.0 - north * 0.7)
	var east := _smooth01(0.12, 0.42, u - reg * 0.1) * (1.0 - north)
	var hills := (_n_hills.get_noise_2d(x, z) * 0.5 + 0.5)
	var h := 18.0 + hills * hills * 170.0
	# Western plateau with escarpments and canyons.
	var plat := 330.0 + _n_plat.get_noise_2d(x, z) * 55.0
	var cn := absf(_n_canyon.get_noise_2d(x, z))
	if cn < 0.09:
		var c := (0.09 - cn) / 0.09
		plat -= c * c * 210.0
	h = lerpf(h, plat, west)
	# Eastern coastal plain.
	h = lerpf(h, 10.0 + hills * 26.0, east * 0.85)
	# Northern mountains.
	var r := _n_ridge.get_noise_2d(x, z) * 0.5 + 0.5
	h += pow(r, 1.7) * 2300.0 * north
	# Coast and sea floor.
	var shore := clampf(land * 1.6, 0.0, 1.0)
	h = lerpf(-6.0 - (1.0 - land) * 170.0, h, shore * shore)
	return h


func _gen_row(z: int) -> void:
	var row := PackedFloat32Array()
	row.resize(N)
	var wz := -HALF + (z + 0.5) * CELL
	for x in N:
		row[x] = base_height(-HALF + (x + 0.5) * CELL, wz)
	_rows[z] = row


func _flatten_sites() -> void:
	for name in FLATTEN:
		var p: Vector2 = SITE_XZ[name]
		var cfg: Array = FLATTEN[name]
		var r: float = cfg[0]
		var soft: float = cfg[1]
		var target := _raw(p.x, p.y)
		# Sample a ring to find a sensible pad height (the median of the area), never below sea level.
		var samples := PackedFloat32Array()
		for i in 24:
			var a := TAU * i / 24.0
			for f in [0.3, 0.7, 1.0]:
				samples.append(_raw(p.x + cos(a) * r * f, p.y + sin(a) * r * f))
		samples.sort()
		target = maxf(samples[samples.size() / 2], 6.0)
		if name == "capital":
			target = 22.0
		elif name == "harbor":
			target = 7.0
		elif name == "front":
			target = maxf(target, 40.0)
		target += cfg[2]
		var ext := r + soft
		var x0 := _tx(p.x - ext); var x1 := _tx(p.x + ext)
		var z0 := _tx(p.y - ext); var z1 := _tx(p.y + ext)
		for tz in range(z0, z1 + 1):
			for tx in range(x0, x1 + 1):
				var wx := -HALF + (tx + 0.5) * CELL
				var wz := -HALF + (tz + 0.5) * CELL
				var d := Vector2(wx - p.x, wz - p.y).length()
				if d > ext:
					continue
				var k := 1.0 - _smooth01(r, ext, d)
				var i := tz * N + tx
				if name == "front":
					heights[i] = lerpf(heights[i], lerpf(heights[i], target, 0.65), k)
				else:
					heights[i] = lerpf(heights[i], target, k)


func _tx(w: float) -> int:
	return clampi(int(floor((w + HALF) / CELL - 0.5)), 0, N - 1)


func _raw(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / CELL - 0.5, 0.0, N - 1.001)
	var fz := clampf((z + HALF) / CELL - 0.5, 0.0, N - 1.001)
	var ix := int(fx); var iz := int(fz)
	var ax := fx - ix; var az := fz - iz
	var i := iz * N + ix
	return lerpf(lerpf(heights[i], heights[i + 1], ax), lerpf(heights[i + N], heights[i + N + 1], ax), az)


## Densifies a control polyline with a gentle meander, builds a monotonic bed profile, carves the channel and
## a valley, and records the water surface.
func _carve_river(ctrl: Array, w0: float, w1: float, d0: float, d1: float) -> Dictionary:
	var pts := PackedVector2Array()
	var meander := FastNoiseLite.new()
	meander.seed = seed + ctrl.size() * 13
	meander.frequency = 1.0 / 900.0
	for i in ctrl.size() - 1:
		var a: Vector2 = ctrl[i]
		var b: Vector2 = ctrl[i + 1]
		var steps := maxi(1, int(a.distance_to(b) / 24.0))
		var nrm := (b - a).normalized().orthogonal()
		for s in steps:
			var t := float(s) / steps
			var p := a.lerp(b, t)
			var amp := 90.0 * sin(t * PI) if i > 0 and i < ctrl.size() - 2 else 50.0 * sin(t * PI)
			pts.append(p + nrm * meander.get_noise_2d(p.x, p.y) * amp)
	pts.append(ctrl[ctrl.size() - 1])
	var n := pts.size()
	# Bed profile: terrain along the path, made monotonic downhill and smoothed, ending below the sea.
	var bed := PackedFloat32Array()
	bed.resize(n)
	for i in n:
		bed[i] = _raw(pts[i].x, pts[i].y)
	for pass_i in 3:
		var sm := bed.duplicate()
		for i in range(1, n - 1):
			sm[i] = (bed[i - 1] + bed[i] * 2.0 + bed[i + 1]) * 0.25
		bed = sm
	for i in range(1, n):
		bed[i] = minf(bed[i], bed[i - 1] - 0.05)
	var widths := PackedFloat32Array()
	var depths := PackedFloat32Array()
	widths.resize(n); depths.resize(n)
	var total := 0.0
	for i in n:
		var t := float(i) / (n - 1)
		widths[i] = lerpf(w0, w1, t)
		depths[i] = lerpf(d0, d1, t)
		bed[i] = maxf(bed[i] - depths[i], -12.0) if bed[i] > 0.5 else minf(bed[i], -2.0) - depths[i] * 0.5
	# Carve: for each segment, lower the texels in a corridor to a channel plus valley walls.
	var surf := PackedVector3Array()
	surf.resize(n)
	for i in n:
		var level := bed[i] + depths[i]
		surf[i] = Vector3(pts[i].x, maxf(level, 0.0) if bed[i] + depths[i] > -0.5 else 0.0, pts[i].y)
	for i in n - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var reach := widths[i] * 0.5 + 420.0
		var x0 := _tx(minf(a.x, b.x) - reach); var x1 := _tx(maxf(a.x, b.x) + reach)
		var z0 := _tx(minf(a.y, b.y) - reach); var z1 := _tx(maxf(a.y, b.y) + reach)
		var ab := b - a
		var len2 := maxf(ab.length_squared(), 0.001)
		for tz in range(z0, z1 + 1):
			var wz := -HALF + (tz + 0.5) * CELL
			for tx in range(x0, x1 + 1):
				var wx := -HALF + (tx + 0.5) * CELL
				var p := Vector2(wx, wz)
				var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				if d > reach:
					continue
				var bh := lerpf(bed[i], bed[i + 1], t)
				var hw := lerpf(widths[i], widths[i + 1], t) * 0.5
				var dep := lerpf(depths[i], depths[i + 1], t)
				var target: float
				if d < hw:
					var c := d / hw
					target = bh + c * c * dep * 0.85
				else:
					var e := d - hw
					target = bh + dep * 0.85 + e * 0.06 + e * e * 0.0009
				var idx := tz * N + tx
				if target < heights[idx]:
					heights[idx] = target
	return {"pts": surf, "w": widths, "p2": pts, "dep": depths}


## After every river is carved: the surface follows the carved channel floor (the valley walls of steep
## downstream segments cut below upstream points; surfaces from the uncarved terrain hung up to 230 m in the
## air), kept monotonic downhill, then written into the water texels along the channel.
func _river_finish(r: Dictionary) -> void:
	var p2: PackedVector2Array = r["p2"]
	var dep: PackedFloat32Array = r["dep"]
	var widths: PackedFloat32Array = r["w"]
	var surf: PackedVector3Array = r["pts"]
	var n := p2.size()
	for i in n:
		var floor_h := _raw(p2[i].x, p2[i].y)
		var lvl := minf(surf[i].y, floor_h + dep[i] * 0.85) if surf[i].y > 0.0 else 0.0
		if i > 0:
			lvl = minf(lvl, surf[i - 1].y - 0.02) if lvl > 0.0 else lvl
		surf[i] = Vector3(p2[i].x, maxf(lvl, 0.0), p2[i].y)
	# Every texel near the channel takes its level and depth from its nearest segment (segments overlap where
	# the channel is wider than the 24 m point spacing; mixing them dug pits under steep stretches).
	var best := {}                     # texel -> [distance, level, depth, half width]
	for i in n - 1:
		var a := p2[i]
		var b := p2[i + 1]
		var reach := widths[i] * 0.5 + CELL * 2.0
		var x0 := _tx(minf(a.x, b.x) - reach); var x1 := _tx(maxf(a.x, b.x) + reach)
		var z0 := _tx(minf(a.y, b.y) - reach); var z1 := _tx(maxf(a.y, b.y) + reach)
		var ab := b - a
		var len2 := maxf(ab.length_squared(), 0.001)
		for tz in range(z0, z1 + 1):
			var wz := -HALF + (tz + 0.5) * CELL
			for tx in range(x0, x1 + 1):
				var wx := -HALF + (tx + 0.5) * CELL
				var p := Vector2(wx, wz)
				var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				var hw := lerpf(widths[i], widths[i + 1], t) * 0.5
				if d >= hw + CELL:
					continue
				var idx := tz * N + tx
				var cur: Variant = best.get(idx)
				if cur == null or d < (cur as Array)[0]:
					best[idx] = [d, lerpf(surf[i].y, surf[i + 1].y, t), lerpf(dep[i], dep[i + 1], t), hw]
	for idx in best:
		var e: Array = best[idx]
		var lvl: float = e[1]
		water[idx] = maxf(water[idx], lvl)
		# The channel bed is set to its designed profile under the final surface: that cuts bumps the monotonic
		# surface would sit below, and fills the narrow ravines of the base terrain (16 m wide, down to 70 m
		# deep) that the 24 m river sampling stepped over, leaving water bridging a crack.
		var d: float = e[0]
		var hw: float = e[3]
		if d < hw and lvl > 0.0:
			var c := d / hw
			heights[idx] = lvl - float(e[2]) * 0.85 * (1.0 - c * c) - 0.3
	r["pts"] = surf
	r.erase("p2")
	r.erase("dep")


func _paint_mask() -> void:
	for tz in N:
		var wz := -HALF + (tz + 0.5) * CELL
		for tx in N:
			var i := tz * N + tx
			var h := heights[i]
			var wx := -HALF + (tx + 0.5) * CELL
			var wet := 0
			if water[i] > -100.0:
				wet = 255
			var f := 0.0
			if h > 2.5 and h < 1500.0 and wet == 0:
				var slope := _slope_at(tx, tz)
				f = clampf(_n_forest.get_noise_2d(wx, wz) * 1.3 + 0.35, 0.0, 1.0)
				f *= 1.0 - _smooth01(0.55, 0.9, slope)
				f *= 1.0 - _smooth01(1100.0, 1500.0, h)
				f *= _smooth01(2.5, 9.0, h)
			mask[i * 4 + 2] = wet
			mask[i * 4 + 3] = int(f * 255.0)
	# Urban and base pads clear the forest.
	for name in FLATTEN:
		var p: Vector2 = SITE_XZ[name]
		var r: float = FLATTEN[name][0]
		# Cities and the battlefield paint their own ground: only clear the forest there.
		var pave := 0.0          # sites build their own platforms
		if name == "front":
			r *= 0.5
		var x0 := _tx(p.x - r); var x1 := _tx(p.x + r)
		var z0 := _tx(p.y - r); var z1 := _tx(p.y + r)
		for tz in range(z0, z1 + 1):
			for tx in range(x0, x1 + 1):
				var wx := -HALF + (tx + 0.5) * CELL
				var wz := -HALF + (tz + 0.5) * CELL
				var d := Vector2(wx - p.x, wz - p.y).length()
				if d < r:
					var i := tz * N + tx
					var k := 1.0 - _smooth01(r * 0.8, r, d)
					var kp := (1.0 - _smooth01(r * 0.4, r * 0.55, d)) * pave
					mask[i * 4 + 1] = maxi(mask[i * 4 + 1], int(kp * 255.0))
					mask[i * 4 + 3] = int(mask[i * 4 + 3] * (1.0 - k))


func _slope_at(tx: int, tz: int) -> float:
	var x0 := maxi(tx - 1, 0); var x1 := mini(tx + 1, N - 1)
	var z0 := maxi(tz - 1, 0); var z1 := mini(tz + 1, N - 1)
	var dx := (heights[tz * N + x1] - heights[tz * N + x0]) / ((x1 - x0) * CELL)
	var dz := (heights[z1 * N + tx] - heights[z0 * N + tx]) / ((z1 - z0) * CELL)
	return sqrt(dx * dx + dz * dz)


func _make_detail() -> void:
	var n := FastNoiseLite.new()
	n.seed = seed + 5
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 1.0 / 9.0
	n.fractal_octaves = 4
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail = PackedFloat32Array()
	detail.resize(DETAIL_N * DETAIL_N)
	var p := DETAIL_PERIOD
	for z in DETAIL_N:
		for x in DETAIL_N:
			var wx := x * p / DETAIL_N
			var wz := z * p / DETAIL_N
			var fx := wx / p; var fz := wz / p
			var a := n.get_noise_2d(wx, wz)
			var b := n.get_noise_2d(wx - p, wz)
			var c := n.get_noise_2d(wx, wz - p)
			var d := n.get_noise_2d(wx - p, wz - p)
			var v := lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)
			detail[z * DETAIL_N + x] = clampf(v * 1.6, -1.0, 1.0)


func _finish_sites() -> void:
	sites.clear()
	for name in SITE_XZ:
		var p: Vector2 = SITE_XZ[name]
		sites[name] = Vector3(p.x, height_at(p.x, p.y), p.y)


func _save_cache() -> void:
	var f := FileAccess.open(cache_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_32(GEN_VERSION)
	f.store_buffer(heights.to_byte_array())
	f.store_buffer(water.to_byte_array())
	f.store_buffer(mask)
	f.store_var({"rivers": rivers, "roads": roads})


func _load_cache() -> bool:
	if detail.is_empty():
		_make_detail()
	if not FileAccess.file_exists(cache_path()):
		return false
	var f := FileAccess.open(cache_path(), FileAccess.READ)
	if f == null or f.get_32() != GEN_VERSION:
		return false
	heights = f.get_buffer(N * N * 4).to_float32_array()
	water = f.get_buffer(N * N * 4).to_float32_array()
	mask = f.get_buffer(N * N * 4)
	var extra: Variant = f.get_var()
	if heights.size() != N * N or water.size() != N * N or mask.size() != N * N * 4 or not extra is Dictionary:
		return false
	rivers = extra["rivers"]
	roads = extra["roads"]
	return true


# ------------------------------------------------------------------------------------------------- roads

# Road network: [from site, to site, name, faction]. Capital roads are paved; Cinder tracks are gravel.
const ROADS := [
	["capital", "harbor", "Coast Road", "capital"], ["capital", "citadel", "Citadel Way", "capital"],
	["citadel", "airfield", "Airfield Road", "capital"], ["citadel", "radar", "Pass Road", "capital"],
	["capital", "fort_lumen", "Western Highway", "capital"], ["fort_lumen", "artillery", "Battery Lane", "capital"],
	["fort_lumen", "front", "Front Track", "capital"], ["cinder_camp", "cinder_outpost", "Ash Track", "cinder"],
	["cinder_outpost", "front", "Red Track", "cinder"],
]
## Roads meet walled bases at their gates, not their centres (Front Track ran from Fort Lumen's centre through
## its barracks; the patrol crawler hit the block and threw its passenger off the deck).
const ROAD_GATES := {"fort_lumen": Vector2(95, 95)}
const ROAD_CELL := 64.0
const ROAD_HALF := 5.0


func _build_roads() -> void:
	roads.clear()
	var gn := int(SIZE / ROAD_CELL)
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, gn, gn)
	astar.cell_size = Vector2(ROAD_CELL, ROAD_CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.update()
	for gz in gn:
		for gx in gn:
			var wx := -HALF + (gx + 0.5) * ROAD_CELL
			var wz := -HALF + (gz + 0.5) * ROAD_CELL
			var h := _raw(wx, wz)
			if h < 1.0:
				astar.set_point_solid(Vector2i(gx, gz), true)
				continue
			var sl := slope_at(wx, wz)
			var cost := 1.0 + sl * sl * 140.0 + maxf(0.0, h - 900.0) * 0.004
			# Water anywhere in the cell makes it a bridge (expensive: cross rivers rarely and straight); cells
			# next to water cost extra so roads keep to the valley sides instead of the river banks.
			var wet := 0
			for sz in 3:
				for sx in 3:
					if water[_tx(wz + (sz - 1) * 26.0) * N + _tx(wx + (sx - 1) * 26.0)] > -100.0:
						wet += 1
			if wet > 0:
				cost += 120.0
			elif water[_tx(wz + 64.0) * N + _tx(wx)] > -100.0 or water[_tx(wz - 64.0) * N + _tx(wx)] > -100.0 or water[_tx(wz) * N + _tx(wx + 64.0)] > -100.0 or water[_tx(wz) * N + _tx(wx - 64.0)] > -100.0:
				cost += 4.0
			astar.set_point_weight_scale(Vector2i(gx, gz), cost)
	_road_grid = {}
	for r in ROADS:
		var a: Vector2 = SITE_XZ[r[0]] + ROAD_GATES.get(r[0], Vector2.ZERO)
		var b: Vector2 = SITE_XZ[r[1]] + ROAD_GATES.get(r[1], Vector2.ZERO)
		var ia := Vector2i(clampi(int((a.x + HALF) / ROAD_CELL), 0, gn - 1), clampi(int((a.y + HALF) / ROAD_CELL), 0, gn - 1))
		var ib := Vector2i(clampi(int((b.x + HALF) / ROAD_CELL), 0, gn - 1), clampi(int((b.y + HALF) / ROAD_CELL), 0, gn - 1))
		astar.set_point_solid(ia, false)
		astar.set_point_solid(ib, false)
		var cells := astar.get_id_path(ia, ib)
		if cells.size() < 2:
			continue
		var pts := PackedVector2Array()
		pts.append(a)
		for c in cells:
			pts.append(Vector2(-HALF + (c.x + 0.5) * ROAD_CELL, -HALF + (c.y + 0.5) * ROAD_CELL))
		pts.append(b)
		for k in 3:
			pts = _chaikin(pts)
		pts = _resample(pts, 10.0)
		pts = _road_head(pts)
		roads.append(_road_profile(pts, r[2], r[3], _road_grid))
		_index_road(roads[roads.size() - 1])
	for road in roads:
		_carve_road(road)
		var pts: PackedVector3Array = road["pts"]
		var nb := 0
		var first_bridge := Vector3.ZERO
		for k in pts.size():
			if road["bridge"][k] == 1:
				if nb == 0:
					first_bridge = pts[k]
				nb += 1
		print("road %s: %.1f km, %d bridge points %s, mid %s" % [road["name"], pts.size() * 0.01, nb, first_bridge, pts[pts.size() / 2]])


func _chaikin(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(p[0])
	for i in p.size() - 1:
		out.append(p[i].lerp(p[i + 1], 0.25))
		out.append(p[i].lerp(p[i + 1], 0.75))
	out.append(p[p.size() - 1])
	return out


func _resample(p: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(p[0])
	var carry := 0.0
	for i in p.size() - 1:
		var a := p[i]
		var b := p[i + 1]
		var l := a.distance_to(b)
		var t := step - carry
		while t <= l:
			out.append(a.lerp(b, t / l))
			t += step
		carry = l - (t - step)
	out.append(p[p.size() - 1])
	return out


## Cuts a road short where it can no longer climb: beyond the point where the ground rises above what a 20 %
## grade from the start reaches (plus 60 m), the road ends at a road head. Pass Road climbed 1300 m in 5 km to
## the radar summit (26 %): its profile rode a 650 m embankment and its fills raised a 380 m mound at the
## citadel. The radar station is served by gunship pads instead.
func _road_head(pts: PackedVector2Array) -> PackedVector2Array:
	var h0 := _raw(pts[0].x, pts[0].y)
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	var last := pts[pts.size() - 1]
	if _raw(last.x, last.y) <= h0 + 0.2 * total + 60.0:
		return pts                                  # the destination is reachable: grades and ramps handle it
	var dist := 0.0
	for i in range(1, pts.size()):
		dist += pts[i].distance_to(pts[i - 1])
		if _raw(pts[i].x, pts[i].y) > h0 + 0.2 * dist + 60.0:
			return pts.slice(0, maxi(i - 20, 2))
	return pts


var _road_grid := {}                    # 16 m cell -> [Vector3 road point...] of the roads built so far


func _index_road(road: Dictionary) -> void:
	for p in (road["pts"] as PackedVector3Array):
		var k := Vector2i(floori(p.x / 16.0), floori(p.z / 16.0))
		if not _road_grid.has(k):
			_road_grid[k] = []
		(_road_grid[k] as Array).append(p)


## Height of an earlier road within 14 m of (x, z), or NAN. Roads that share a corridor must share a height:
## Red Track once carved its own profile 18 m above Front Track's where A* sent both down one valley.
func _road_pin(x: float, z: float) -> float:
	var best := 14.0
	var y := NAN
	var c := Vector2i(floori(x / 16.0), floori(z / 16.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for p in _road_grid.get(c + Vector2i(dx, dz), []):
				var d := Vector2(p.x - x, p.z - z).length()
				if d < best:
					best = d
					y = p.y
	return y


## Heights along the road: smoothed terrain, grades limited to 9 %, bridges held above rivers, pinned to earlier
## roads where they overlap.
func _road_profile(pts: PackedVector2Array, name: String, faction: String, grid: Dictionary = {}) -> Dictionary:
	var n := pts.size()
	var h := PackedFloat32Array()
	h.resize(n)
	var bridge := PackedByteArray()
	bridge.resize(n)
	for i in n:
		h[i] = _raw(pts[i].x, pts[i].y)
		var w := water[_tx(pts[i].y) * N + _tx(pts[i].x)]
		if w > -100.0:
			bridge[i] = 1
	# Widen bridge spans a little so the deck reaches the banks.
	var br := bridge.duplicate()
	for i in n:
		if bridge[i] == 1:
			for k in range(maxi(0, i - 3), mini(n, i + 4)):
				br[k] = 1
	bridge = br
	var pin := PackedFloat32Array()
	pin.resize(n)
	for i in n:
		pin[i] = _road_pin(pts[i].x, pts[i].y) if not grid.is_empty() else NAN
	for pass_i in 4:
		var sm := h.duplicate()
		for i in range(2, n - 2):
			sm[i] = (h[i - 2] + h[i - 1] * 2.0 + h[i] * 2.0 + h[i + 1] * 2.0 + h[i + 2]) / 8.0
		h = sm
		for i in n:
			if not is_nan(pin[i]):
				h[i] = pin[i]
	for i in n:
		if bridge[i] == 1 and is_nan(pin[i]):
			var w := maxf(water[_tx(pts[i].y) * N + _tx(pts[i].x)], 0.0)
			h[i] = maxf(h[i], w + 7.0)
	# Grade limit (12 %, a mountain road): violations are relaxed symmetrically, half cut and half fill, so a
	# steep climb is spread over both sides instead of becoming one deep cut (the forward/backward clamp alone
	# left Pass Road 190 m under a ridge); a final clamp guarantees the limit.
	# Both ends stay on their sites (relaxation once lowered the radar end by 740 m and its banks dug a crater),
	# 20 % grades (mountain roads), and the last 600 m before a site may climb at up to 30 % (an access ramp).
	if is_nan(pin[0]):
		pin[0] = h[0]
	if is_nan(pin[n - 1]):
		pin[n - 1] = h[n - 1]
	var gr := PackedFloat32Array()
	gr.resize(n)
	for i in n:
		gr[i] = 3.0 if mini(i, n - 1 - i) < 60 else 2.0
	for it in 300:
		var moved := false
		for i in range(1, n):
			var dh := h[i] - h[i - 1]
			var grade := minf(gr[i], gr[i - 1])
			if absf(dh) > grade + 0.01:
				var ex := (absf(dh) - grade) * 0.5 * signf(dh)
				var fi := not is_nan(pin[i])
				var fp := not is_nan(pin[i - 1])
				if fi and fp:
					continue
				if fi:
					h[i - 1] += ex * 2.0
				elif fp:
					h[i] -= ex * 2.0
				else:
					h[i] -= ex
					h[i - 1] += ex
				moved = true
		if not moved:
			break
	for i in range(1, n):
		var g1 := minf(gr[i], gr[i - 1])
		h[i] = pin[i] if not is_nan(pin[i]) else clampf(h[i], h[i - 1] - g1, h[i - 1] + g1)
	for i in range(n - 2, -1, -1):
		var g2 := minf(gr[i], gr[i + 1])
		h[i] = pin[i] if not is_nan(pin[i]) else clampf(h[i], h[i + 1] - g2, h[i + 1] + g2)
	var out := PackedVector3Array()
	for i in n:
		out.append(Vector3(pts[i].x, h[i], pts[i].y))
	return {"pts": out, "bridge": bridge, "name": name, "faction": faction}


## Cuts and fills the terrain to the road profile (except under bridges) and paints the road mask.
func _carve_road(road: Dictionary) -> void:
	var pts: PackedVector3Array = road["pts"]
	var bridge: PackedByteArray = road["bridge"]
	# Cut and fill with sloped banks: within the road the ground is the road; beyond it the ground may rise or
	# fall at most BANK metres per metre of distance. (A blend within 14 m of the shoulder left Pass Road in a
	# 200 m deep slot canyon where its 9 % grade cuts through a ridge.)
	const BANK := 0.8
	var flat := ROAD_HALF + 2.0 + CELL   # every texel the road's bilinear surface touches sits at road height
	# Cut depth per segment, measured before any carving (carving a segment lowers its neighbours' centreline,
	# so measuring as we go saw 2 m where Pass Road cuts 190 m through a ridge), widened over neighbours.
	var raw_depth := PackedFloat32Array()
	raw_depth.resize(pts.size())
	for i in pts.size() - 1:
		var a0 := Vector2(pts[i].x, pts[i].z)
		var b0 := Vector2(pts[i + 1].x, pts[i + 1].z)
		var dd := 0.0
		for t in [0.0, 0.5, 1.0]:
			var q := a0.lerp(b0, t)
			dd = maxf(dd, absf(_raw(q.x, q.y) - lerpf(pts[i].y, pts[i + 1].y, t)))
		raw_depth[i] = dd
	# Two passes: every segment's banks first, then every level strip, so the road surface always wins (on
	# 30 % ramps a later segment's fill bank rose up to 4.5 m above the strip of the segments before it).
	for pass_i in 2:
		_carve_road_pass(pts, bridge, raw_depth, flat, BANK, pass_i == 1)


func _carve_road_pass(pts: PackedVector3Array, bridge: PackedByteArray, raw_depth: PackedFloat32Array, flat: float, BANK: float, strips: bool) -> void:
	for i in pts.size() - 1:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		var ab := b - a
		var len2 := maxf(ab.length_squared(), 0.001)
		var on_bridge := bridge[i] == 1 or bridge[i + 1] == 1
		var depth := 0.0
		for k in range(maxi(0, i - 3), mini(pts.size() - 1, i + 4)):
			depth = maxf(depth, raw_depth[k])
		var reach := minf(flat + (depth + 25.0) / BANK, 320.0) if not on_bridge else ROAD_HALF + 14.0
		if strips:
			reach = minf(reach, flat + ROAD_HALF + 8.0)
		var x0 := _tx(minf(a.x, b.x) - reach); var x1 := _tx(maxf(a.x, b.x) + reach)
		var z0 := _tx(minf(a.y, b.y) - reach); var z1 := _tx(maxf(a.y, b.y) + reach)
		for tz in range(z0, z1 + 1):
			var wz := -HALF + (tz + 0.5) * CELL
			for tx in range(x0, x1 + 1):
				var wx := -HALF + (tx + 0.5) * CELL
				var p := Vector2(wx, wz)
				var tu := (p - a).dot(ab) / len2
				var t := clampf(tu, 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				if d > reach:
					continue
				var idx := tz * N + tx
				# Level only texels that project onto this segment (the strip is wider than a segment is long:
				# clamped projections raised the previous segment's texels by up to 2.4 m on 16 % climbs).
				var own := (tu >= -0.02 or i == 0) and (tu <= 1.02 or i == pts.size() - 2)
				var y := lerpf(pts[i].y, pts[i + 1].y, t) - 0.15
				if on_bridge:
					pass
				elif strips:
					if d <= flat and own:
						heights[idx] = y
				elif d > flat and water[idx] < -100.0:
					# (Banks never cut under a river: wide cuts once left the water 118 m above the ground.)
					var e := (d - flat) * BANK
					heights[idx] = clampf(heights[idx], y - e, y + e)
				if not strips:
					continue
				var m := 1.0 - _smooth01(ROAD_HALF, ROAD_HALF + 8.0, d)
				mask[idx * 4] = maxi(mask[idx * 4], int(m * 200.0))
				mask[idx * 4 + 3] = int(mask[idx * 4 + 3] * (1.0 - minf(1.0, m * 1.5)))


# ----------------------------------------------------------------------------------------------- queries

func macro_height(x: float, z: float) -> float:
	return _raw(x, z)


func detail_at(x: float, z: float) -> float:
	var fx := fposmod(x, DETAIL_PERIOD) / DETAIL_PERIOD * DETAIL_N - 0.5
	var fz := fposmod(z, DETAIL_PERIOD) / DETAIL_PERIOD * DETAIL_N - 0.5
	var ix := int(floor(fx)); var iz := int(floor(fz))
	var ax := fx - ix; var az := fz - iz
	var x0 := posmod(ix, DETAIL_N); var x1 := posmod(ix + 1, DETAIL_N)
	var z0 := posmod(iz, DETAIL_N) * DETAIL_N; var z1 := posmod(iz + 1, DETAIL_N) * DETAIL_N
	return lerpf(lerpf(detail[z0 + x0], detail[z0 + x1], ax), lerpf(detail[z1 + x0], detail[z1 + x1], ax), az)


## Detail amplitude at a point: suppressed on roads, urban pads and river beds (mask r, g, b).
func detail_amp(x: float, z: float) -> float:
	var i := (_tx(z) * N + _tx(x)) * 4
	var flat := maxf(mask[i] / 255.0, mask[i + 1] / 255.0)
	return DETAIL_AMP * (1.0 - flat)


## Ground height, matching the terrain shader.
func height_at(x: float, z: float) -> float:
	if heights.is_empty():
		return 0.0
	return _raw(x, z) + detail_at(x, z) * detail_amp(x, z)


func normal_at(x: float, z: float) -> Vector3:
	var e := 1.5
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


## Water surface height (ocean 0, rivers above), or -1e4 when the point is dry land.
func water_at(x: float, z: float) -> float:
	var w := water[_tx(z) * N + _tx(x)]
	if w > -100.0:
		return w
	if _raw(x, z) < SEA + 0.5:
		return SEA
	return -10000.0


## Macro slope (rise over run) from the height grid.
func slope_at(x: float, z: float) -> float:
	return _slope_at(_tx(x), _tx(z))


func forest_at(x: float, z: float) -> float:
	return mask[(_tx(z) * N + _tx(x)) * 4 + 3] / 255.0


func urban_at(x: float, z: float) -> float:
	return mask[(_tx(z) * N + _tx(x)) * 4 + 1] / 255.0


func in_world(x: float, z: float) -> bool:
	return absf(x) < HALF and absf(z) < HALF


# ---------------------------------------------------------------------------------------------- textures

func height_image() -> Image:
	return Image.create_from_data(N, N, false, Image.FORMAT_RF, heights.to_byte_array())


func mask_image() -> Image:
	var img := Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, mask)
	return img


func normal_image() -> Image:
	var data := PackedByteArray()
	data.resize(N * N * 4)
	for tz in N:
		var z0 := maxi(tz - 1, 0) * N; var z1 := mini(tz + 1, N - 1) * N
		var row := tz * N
		for tx in N:
			var x0 := maxi(tx - 1, 0); var x1 := mini(tx + 1, N - 1)
			var dx := heights[row + x1] - heights[row + x0]
			var dz := heights[z1 + tx] - heights[z0 + tx]
			var nrm := Vector3(-dx, 4.0 * CELL, -dz).normalized()
			var o := (row + tx) * 4
			data[o] = int((nrm.x * 0.5 + 0.5) * 255.0)
			data[o + 1] = int((nrm.y * 0.5 + 0.5) * 255.0)
			data[o + 2] = int((nrm.z * 0.5 + 0.5) * 255.0)
			data[o + 3] = 255
	var img := Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return img


func detail_image() -> Image:
	var data := PackedByteArray()
	data.resize(DETAIL_N * DETAIL_N * 4)
	for z in DETAIL_N:
		for x in DETAIL_N:
			var i := z * DETAIL_N + x
			var h := detail[i]
			var hx := detail[z * DETAIL_N + (x + 1) % DETAIL_N] - detail[z * DETAIL_N + (x - 1 + DETAIL_N) % DETAIL_N]
			var hz := detail[((z + 1) % DETAIL_N) * DETAIL_N + x] - detail[((z - 1 + DETAIL_N) % DETAIL_N) * DETAIL_N + x]
			data[i * 4] = int(clampf(h * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			data[i * 4 + 1] = int(clampf(hx * 2.0 + 0.5, 0.0, 1.0) * 255.0)
			data[i * 4 + 2] = int(clampf(hz * 2.0 + 0.5, 0.0, 1.0) * 255.0)
			data[i * 4 + 3] = 255
	return Image.create_from_data(DETAIL_N, DETAIL_N, false, Image.FORMAT_RGBA8, data)
