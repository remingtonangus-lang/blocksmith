class_name WorldData
extends RefCounted
## The generated Sable River country: heightmap, control map and authored features (towns, roads, rivers, rail).
## Data files come from tools/worldgen.py (data/world/). Height queries are CPU-side bilinear lookups so AI, props and
## physics proxies never need the GPU.

const DIR := "res://data/world/"

var size_m: float = 8192.0
var res: int = 4096            # height samples per side
var cell: float = 2.0          # metres per height sample
var h_range: float = 1600.0
var lake_level: float = 120.0
var ctrl_res: int = 2048
var heights: PackedByteArray   # uint16 LE
var control: PackedByteArray   # RGBA8
var features: Dictionary = {}
var height_image: Image        # FORMAT_R16 (for the GPU)
var control_image: Image       # FORMAT_RGBA8
var ok := false

func load_all() -> bool:
	var t0 := Time.get_ticks_msec()
	var fj := FileAccess.get_file_as_string(DIR + "features.json")
	if fj.is_empty():
		push_error("world data missing: run tools/worldgen.py")
		return false
	features = JSON.parse_string(fj)
	size_m = features.get("size_m", 8192.0)
	res = int(features.get("height_res", 4096))
	ctrl_res = int(features.get("control_res", 2048))
	h_range = features.get("h_range", 1600.0)
	lake_level = features.get("lake_level", 120.0)
	cell = size_m / res
	heights = FileAccess.get_file_as_bytes(DIR + "height.r16")
	control = FileAccess.get_file_as_bytes(DIR + "control.bin")
	if heights.size() != res * res * 2 or control.size() != ctrl_res * ctrl_res * 4:
		push_error("world data size mismatch")
		return false
	height_image = Image.create_from_data(res, res, false, Image.FORMAT_R16, heights)
	control_image = Image.create_from_data(ctrl_res, ctrl_res, false, Image.FORMAT_RGBA8, control)
	ok = true
	print("world: loaded %dx%d heights in %d ms" % [res, res, Time.get_ticks_msec() - t0])
	return true

## Raw sample (metres) at integer grid coords, clamped.
func sample(ix: int, iz: int) -> float:
	ix = clampi(ix, 0, res - 1)
	iz = clampi(iz, 0, res - 1)
	return heights.decode_u16((iz * res + ix) * 2) * h_range / 65535.0

## Bilinear terrain height at world x,z (metres; map centred on origin).
func height(x: float, z: float) -> float:
	var gx := (x + size_m * 0.5) / cell - 0.5
	var gz := (z + size_m * 0.5) / cell - 0.5
	var ix := floori(gx)
	var iz := floori(gz)
	var fx := gx - ix
	var fz := gz - iz
	var h00 := sample(ix, iz)
	var h10 := sample(ix + 1, iz)
	var h01 := sample(ix, iz + 1)
	var h11 := sample(ix + 1, iz + 1)
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)

func normal(x: float, z: float) -> Vector3:
	var e := cell
	var hl := height(x - e, z)
	var hr := height(x + e, z)
	var hd := height(x, z - e)
	var hu := height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()

## Control map at world x,z: r road, g moisture, b biome (0 desert .. 0.5 grass .. 1 forest), a sediment.
func ctrl(x: float, z: float) -> Color:
	var cx := clampi(int((x + size_m * 0.5) / size_m * ctrl_res), 0, ctrl_res - 1)
	var cz := clampi(int((z + size_m * 0.5) / size_m * ctrl_res), 0, ctrl_res - 1)
	var o := (cz * ctrl_res + cx) * 4
	return Color(control[o] / 255.0, control[o + 1] / 255.0, control[o + 2] / 255.0, control[o + 3] / 255.0)

func in_bounds(x: float, z: float, margin: float = 0.0) -> bool:
	var h := size_m * 0.5 - margin
	return x > -h and x < h and z > -h and z < h

func is_water(x: float, z: float) -> bool:
	return water_level(x, z) > height(x, z) + 0.05

## Water surface height at x,z (lake or nearest river), or -INF if dry land.
func water_level(x: float, z: float) -> float:
	var best := -INF
	if height(x, z) < lake_level:
		best = lake_level
	var r := river_at(x, z)
	if not r.is_empty() and r.dist < r.width * 0.5:
		best = maxf(best, r.surface)
	return best

var _river_cache: Array = []

func _river_segments() -> Array:
	if _river_cache.is_empty():
		for rv in features.get("rivers", []):
			var pts: Array = rv.points
			var segs := []
			for i in pts.size():
				segs.append(Vector3(pts[i][0], rv.surface[i], pts[i][1]))
			_river_cache.append({"name": rv.name, "pts": segs, "width": rv.width})
	return _river_cache

## Nearest river point: {dist, surface, width, dir, name} or {} if none within 200 m.
func river_at(x: float, z: float) -> Dictionary:
	var best := {}
	var bd := 200.0
	var p := Vector2(x, z)
	for rv in _river_segments():
		var pts: Array = rv.pts
		for i in range(0, pts.size() - 1):
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			if absf(a.x - x) > 260.0 or absf(a.y - z) > 260.0:
				continue
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < bd:
				bd = d
				best = {"dist": d, "surface": lerpf(pts[i].y, pts[i + 1].y, t),
					"width": lerpf(rv.width[i], rv.width[i + 1], t), "dir": ab.normalized(), "name": rv.name}
	return best

func town(id: String) -> Dictionary:
	for t in features.get("towns", []):
		if t.id == id:
			return t
	return {}

func poi(id: String) -> Dictionary:
	for t in features.get("pois", []):
		if t.id == id:
			return t
	return {}

func nearest_settlement(x: float, z: float) -> Dictionary:
	var best := {}
	var bd := INF
	for t in features.get("towns", []) + features.get("pois", []):
		var d := Vector2(t.x - x, t.z - z).length()
		if d < bd:
			bd = d
			best = t
	return best
