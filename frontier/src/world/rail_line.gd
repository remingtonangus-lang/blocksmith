extends Node3D
## The Meridian & Western main line between the settlements (world.features.rail, graded profile): ballast bed,
## ties every 0.6 m and two rails at standard gauge, with timber trestle bents where the grade runs above the
## ground. Settlements build their own station track inside radius + 60 m (structures.gd _s_track); this covers the
## rest of the line.
##
## LOD: detail chunks (~200 m of track, one mesh, 3 surfaces) are built on a worker thread within DETAIL_R of the
## camera and freed beyond FREE_R; a single vertex-coloured far strip per ~1.5 km group (ballast top + rail sheen)
## sits just under the detail ballast and is always on (5 draw calls), so the line reads across the valley.

const CHUNK_PTS := 50              # rail samples per detail chunk (~4 m apart -> ~200 m)
const DETAIL_R := 520.0
const FREE_R := 700.0
const DETAIL_END := 480.0
const GAUGE := 1.435
const TIE_STEP := 0.6

var world: WorldData
var chunks: Array = []             # [{pts: PackedVector3Array, center: Vector3, node: MeshInstance3D|null}]
var _task := -1
var _task_chunk := -1
var _task_mesh: ArrayMesh = null
var _timer := 0.0
var stats := {"chunks": 0, "built": 0, "far_tris": 0}

func setup(w: WorldData, skip: Array) -> void:
	world = w
	var rail = w.features.get("rail", null)
	if rail == null or Game.args.has("no_rail"):
		return
	var cur := PackedVector3Array()
	var last_skipped := Vector3.INF
	for p in rail.points:
		var v := Vector3(p[0], p[2], p[1])
		var inside := false
		for s in skip:
			if Vector2(v.x - s.x, v.z - s.z).length() < float(s.r):
				inside = true
				break
		if inside:
			if not cur.is_empty():
				cur.append(v)            # close the gap to the station track's last tie
			_flush(cur)
			cur = PackedVector3Array()
			last_skipped = v
			continue
		if cur.is_empty() and last_skipped != Vector3.INF:
			cur.append(last_skipped)
		cur.append(v)
		if cur.size() >= CHUNK_PTS:
			_flush(cur)
			cur = PackedVector3Array([v])
	_flush(cur)
	_build_far()
	stats.chunks = chunks.size()
	print("rail: %d chunks of main line, far strip %d tris" % [chunks.size(), stats.far_tris])

func _flush(pts: PackedVector3Array) -> void:
	if pts.size() < 2:
		return
	var c := Vector3.ZERO
	for p in pts:
		c += p
	chunks.append({"pts": pts, "center": c / pts.size(), "node": null})

func _process(dt: float) -> void:
	_timer -= dt
	if _timer > 0.0 or chunks.is_empty():
		return
	_timer = 0.25
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		var ch: Dictionary = chunks[_task_chunk]
		if ch.node == null and _task_mesh != null:
			var mi := MeshInstance3D.new()
			mi.name = "Track"
			mi.mesh = _task_mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = DETAIL_END
			mi.visibility_range_end_margin = 30.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mi)
			ch.node = mi
			stats.built += 1
		_task_mesh = null
	var best := -1
	var bd := DETAIL_R
	for i in chunks.size():
		var ch: Dictionary = chunks[i]
		var d := _chunk_dist(ch, cp)
		if ch.node != null and d > FREE_R:
			ch.node.queue_free()
			ch.node = null
			stats.built -= 1
		elif ch.node == null and d < bd:
			bd = d
			best = i
	if best >= 0:
		_task_chunk = best
		var pts: PackedVector3Array = chunks[best].pts
		_task = WorkerThreadPool.add_task(func(): _task_mesh = _detail(pts), false, "rail chunk")

func _chunk_dist(ch: Dictionary, p: Vector3) -> float:
	var pts: PackedVector3Array = ch.pts
	var d := INF
	for i in [0, pts.size() / 2, pts.size() - 1]:
		d = minf(d, Vector2(pts[i].x - p.x, pts[i].z - p.z).length())
	return d

## Detail mesh of one chunk (worker thread: MeshKit is plain data; meshes are committed here, attached later).
func _detail(pts: PackedVector3Array) -> ArrayMesh:
	var k := MeshKit.new()
	var carry := 0.0
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var ab := b - a
		var L := ab.length()
		if L < 0.01:
			continue
		var dirv := ab / L
		var side := Vector3(-dirv.z, 0.0, dirv.x).normalized()
		# ballast: trapezoid prism under the ties
		k.tint = Color(0.62, 0.58, 0.54, 0.5)
		var hb := 1.9
		var ht := 1.45
		var lo := Vector3(0, -0.3, 0)
		var hi := Vector3(0, 0.12, 0)
		k.quad("stone", a - side * ht + hi, a + side * ht + hi, b + side * ht + hi, b - side * ht + hi)
		k.quad("stone", a - side * hb + lo, a - side * ht + hi, b - side * ht + hi, b - side * hb + lo)
		k.quad("stone", a + side * ht + hi, a + side * hb + lo, b + side * hb + lo, b + side * ht + hi)
		# ties
		k.tint = Color(0.55, 0.45, 0.38, 0.6)
		var basis := Basis(side, Vector3.UP, side.cross(Vector3.UP))
		var tdist := TIE_STEP - carry
		while tdist < L:
			var tc := a + dirv * tdist
			k.obox("dark_planks", tc + Vector3(0, 0.2, 0), Vector3(2.6, 0.16, 0.22), basis, MeshKit.F_ALL & ~MeshKit.F_NY)
			tdist += TIE_STEP
		carry = L - (tdist - TIE_STEP)
		# rails
		k.tint = Color(1, 1, 1, 0.6)
		for sg: float in [-0.5, 0.5]:
			var off: Vector3 = side * GAUGE * sg
			k.beam("iron", a + off + Vector3(0, 0.34, 0), b + off + Vector3(0, 0.34, 0), 0.07, 0.13)
		# trestle bents where the grade runs well above the ground (or over water)
		if i % 2 == 0:
			var g := world.height(a.x, a.z)
			if a.y - g > 1.2 or world.is_water(a.x, a.z):
				k.tint = Color(0.5, 0.42, 0.34, 0.6)
				var base := minf(g, a.y - 1.0) - 0.3
				for sg2: float in [-1.0, -0.35, 0.35, 1.0]:
					var pp := a + side * sg2 * 1.3
					k.beam("log", Vector3(pp.x, base, pp.z), Vector3(pp.x, a.y - 0.25, pp.z), 0.24)
				k.beam("log", a - side * 1.7 + Vector3(0, -0.25, 0), a + side * 1.7 + Vector3(0, -0.25, 0), 0.26, 0.3)
	return k.commit(TownMats.get_all(), TownMats.plain_keys())

## Always-on far strip: the ballast top as a flat vertex-coloured ribbon, merged into a few meshes.
func _build_far() -> void:
	var group := MeshKit.new()
	var n := 0
	for ch in chunks:
		var pts: PackedVector3Array = ch.pts
		for i in range(0, pts.size() - 1, 2):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[mini(i + 2, pts.size() - 1)]
			var dirv := (b - a).normalized()
			var side := Vector3(-dirv.z, 0.0, dirv.x).normalized()
			group.tint = Color(0.42, 0.38, 0.34, 1.0)
			var up := Vector3(0, 0.06, 0)       # just under the detail ballast top: hidden by it up close
			group.quad("far", a - side * 1.6 + up, a + side * 1.6 + up, b + side * 1.6 + up, b - side * 1.6 + up)
		n += 1
		if n % 8 == 0:
			_far_mesh(group)
			group = MeshKit.new()
	_far_mesh(group)

func _far_mesh(k: MeshKit) -> void:
	if k.is_empty():
		return
	stats.far_tris += k.tris
	var mi := MeshInstance3D.new()
	mi.name = "TrackFar"
	mi.mesh = k.commit(TownMats.get_all(), TownMats.plain_keys() + ["far"])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 3200.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mi)
