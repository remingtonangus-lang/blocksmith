class_name WorldGen
extends RefCounted
## The landscape: a 16 km island continent. Northern mountains (snow above ~1300 m), the Cinder Pact's western
## plateau cut by canyons, rolling forested hills in the south, the Capital's coastal plain in the east, a main
## river from the mountains to the eastern sea plus a tributary from the plateau. Heights live in a 2048^2
## float grid (8 m texels) that the GPU samples with the same bilinear filter as height_at(), plus a tileable
## 0.25 m detail layer. Everything is deterministic for a seed and cached in user://.

const GEN_VERSION := 9
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
	progress = 0.8
	print("world: rivers %d ms" % (Time.get_ticks_msec() - t0))
	stage = "planting forests"
	_paint_mask()
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
				if d < hw + CELL:
					var lvl := lerpf(surf[i].y, surf[i + 1].y, t)
					water[idx] = maxf(water[idx], lvl)
	return {"pts": surf, "w": widths}


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
