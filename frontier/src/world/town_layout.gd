class_name TownLayout
extends RefCounted
## Plans one settlement from world.features: streets in a town frame (x along the main street at the town's
## `angle`, z across it), lots along both sides with alleys, side streets with houses, the special buildings each
## town is known for, road connectors from the worldgen roads to the main street, a bridge where the main street
## meets the river, the depot beside the rail, street furniture. Every footprint is checked against the river
## (world.river_at), the lake, the rail corridor, steep ground and the town radius.
##
## Output (plan): {id, name, kind, frame: Transform3D (town -> world, y = town level), radius, streets: [{a, b, w}]
## (town-local Vector2), specs: [building spec for SettlementKit.build], weather}

const MAIN_W := 20.0           # main street width between boardwalk fronts
const SIDE_W := 12.0

var world: WorldData
var t: Dictionary              # the feature (town or POI)
var plan: Dictionary
var frame := Transform3D.IDENTITY
var rng := RandomNumberGenerator.new()
var _foot: Array = []          # placed footprints: [center Vector2, half Vector2, angle] in town space
var _rail: Array = []          # rail polyline in town space (Vector2)
var _roads: Array = []         # [{pts: PackedVector2Array (town space), other: id}] for roads ending here
var _river: Array = []         # [a, b, half width] river segments near the town (town space)
var _n := 0
var weather := 0.35

func make(w: WorldData, feature: Dictionary, is_town: bool) -> Dictionary:
	world = w
	t = feature
	rng.seed = hash(str(t.id))
	var a := deg_to_rad(float(t.get("angle", 0.0)))
	var xa := Vector3(cos(a), 0.0, sin(a))
	var za := Vector3(-sin(a), 0.0, cos(a))
	frame = Transform3D(Basis(xa, Vector3.UP, za), Vector3(t.x, t.y, t.z))
	plan = {"id": t.id, "name": t.name, "kind": t.kind, "frame": frame, "radius": float(t.r), "streets": [],
		"specs": [], "is_town": is_town}
	_prepare_lines()
	match str(t.kind):
		"rail_town": _bitter_spring()
		"mining_camp": _coldwater()
		"desert_stop": _mesquite_wells()
		"port_town": _port_linden()
		"camp": _camp()
		"ranch": _ranch()
		"homestead": _homestead()
		"logging": _logging()
		"ruin": _ruin()
		"trading_post": _trading_post()
		"cabin": _trapper()
		_: _homestead()
	plan["weather"] = weather
	return plan

# ------------------------------------------------------------------------------------------------ frame helpers

func W(p: Vector2) -> Vector3:
	return frame * Vector3(p.x, 0.0, p.y)

func gh(p: Vector2) -> float:
	var q := W(p)
	return world.height(q.x, q.z)

func to_town(wx: float, wz: float) -> Vector2:
	var p := frame.affine_inverse() * Vector3(wx, frame.origin.y, wz)
	return Vector2(p.x, p.z)

func _prepare_lines() -> void:
	var R := float(t.r) + 120.0
	var rail = world.features.get("rail", null)
	if rail != null:
		for p in rail.points:
			var q := to_town(p[0], p[1])
			if q.length() < R + 200.0:
				_rail.append(q)
	for rv in world.features.get("rivers", []):
		var rp: Array = rv.points
		for i in rp.size() - 1:
			var qa := to_town(rp[i][0], rp[i][1])
			var qb := to_town(rp[i + 1][0], rp[i + 1][1])
			if qa.length() < R + 150.0 or qb.length() < R + 150.0:
				_river.append([qa, qb, float(rv.width[i]) * 0.5])
	for r in world.features.get("roads", []):
		if r.a != t.id and r.b != t.id:
			continue
		var pts := PackedVector2Array()
		var src: Array = r.points
		if r.b == t.id:
			src = src.duplicate()
			src.reverse()
		for p in src:
			pts.append(to_town(p[0], p[1]))
		_roads.append({"pts": pts, "other": r.b if r.a == t.id else r.a})

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * tt)

func rail_dist(p: Vector2) -> float:
	var best := INF
	for i in range(_rail.size() - 1):
		best = minf(best, _seg_dist(p, _rail[i], _rail[i + 1]))
	return best

func river_clear(p: Vector2, margin: float) -> bool:
	for sg in _river:
		if _seg_dist(p, sg[0], sg[1]) < sg[2] + margin:
			return false
	var q := W(p)
	return world.height(q.x, q.z) > world.lake_level + 1.2

func street_dist(p: Vector2) -> float:
	var best := INF
	for s in plan.streets:
		best = minf(best, _seg_dist(p, s.a, s.b) - s.w * 0.5)
	return best

## Is a rectangle (centre c, half extents h, rotation ang in town space) free to build on?
func free_rect(c: Vector2, h: Vector2, ang: float, margin := 1.0, street_margin := 0.5, ignore_streets := false, rail_margin := 9.0) -> bool:
	if c.length() + h.length() > float(t.r) * 1.08:
		return false
	var ax := Vector2(cos(ang), sin(ang))
	var az := Vector2(-sin(ang), cos(ang))
	var hmin := INF
	var hmax := -INF
	for i in 5:
		for j in 5:
			var p := c + ax * h.x * lerpf(-1.0, 1.0, i / 4.0) + az * h.y * lerpf(-1.0, 1.0, j / 4.0)
			if not river_clear(p, 5.0):
				return false
			if rail_dist(p) < rail_margin:
				return false
			if not ignore_streets and street_dist(p) < street_margin:
				return false
			var y := gh(p)
			hmin = minf(hmin, y)
			hmax = maxf(hmax, y)
	if hmax - hmin > 2.4:
		return false
	for f in _foot:
		if _obb_overlap(c, h + Vector2(margin, margin), ang, f[0], f[1], f[2]):
			return false
	return true

static func _obb_overlap(c1: Vector2, h1: Vector2, a1: float, c2: Vector2, h2: Vector2, a2: float) -> bool:
	var axes := [Vector2(cos(a1), sin(a1)), Vector2(-sin(a1), cos(a1)), Vector2(cos(a2), sin(a2)), Vector2(-sin(a2), cos(a2))]
	var d := c2 - c1
	for ax in axes:
		var r1: float = absf(h1.x * Vector2(cos(a1), sin(a1)).dot(ax)) + absf(h1.y * Vector2(-sin(a1), cos(a1)).dot(ax))
		var r2: float = absf(h2.x * Vector2(cos(a2), sin(a2)).dot(ax)) + absf(h2.y * Vector2(-sin(a2), cos(a2)).dot(ax))
		if absf(d.dot(ax)) > r1 + r2:
			return false
	return true

## Add a structure. p = front-centre (town space), face = direction the front faces (town space, Vector2).
## Footprint: w x d behind the front plus `front` metres in front (porch/boardwalk).
func add(spec: Dictionary, p: Vector2, face: Vector2, front := 0.0, check := true, margin := 1.0, street_margin := 0.5, rail_margin := 9.0) -> bool:
	var w: float = spec.get("w", 8.0)
	var d: float = spec.get("d", 10.0)
	var f := face.normalized()
	var back := -f
	var c := p + back * (d - front) * 0.5
	var h := Vector2(w * 0.5, (d + front) * 0.5)
	var ang := atan2(back.y, back.x) - PI * 0.5
	if check and not free_rect(c, h, ang, margin, street_margin, street_margin < -50.0, rail_margin):
		return false
	_foot.append([c, h, ang])
	# floor height: highest ground under the footprint + the porch raise
	var hmax := -INF
	for i in 4:
		for j in 4:
			var q := c + Vector2(cos(ang), sin(ang)) * h.x * lerpf(-1, 1, i / 3.0) + Vector2(-sin(ang), cos(ang)) * h.y * lerpf(-1, 1, j / 3.0)
			hmax = maxf(hmax, gh(q))
	var fy: float = spec.get("floor_y", hmax + float(spec.get("raise", 0.42)))
	var bas := Basis.looking_at(Vector3(f.x, 0.0, f.y), Vector3.UP)
	var local := Transform3D(bas, Vector3(p.x, 0.0, p.y))
	var wx := frame * local
	wx.origin.y = fy
	_n += 1
	spec["id"] = "%s/%02d_%s" % [t.id, _n, spec.get("type", spec.get("style", "x"))]
	spec["town"] = t.id
	spec["xf"] = wx
	spec["weather"] = clampf(weather + rng.randf_range(-0.12, 0.15), 0.0, 1.0)
	spec["lit_rank"] = rng.randf()
	spec["town_pos"] = p
	spec["town_face"] = f
	plan.specs.append(spec)
	return true

func street(a: Vector2, b: Vector2, w: float) -> void:
	plan.streets.append({"a": a, "b": b, "w": w})

## Walk along a line placing lots from a program. line from s0 to s1 along `dir` at offset `off` (perpendicular,
## along `nrm`); buildings face `face`. Returns the placed specs.
func row(program: Array, origin: Vector2, dir: Vector2, face: Vector2, s0: float, s1: float, porch := 2.8, gaps := Vector2(0.0, 2.5), alley_every := 4) -> Array:
	var placed := []
	var s := s0
	var count := 0
	for item in program:
		var spec: Dictionary = item.duplicate(true)
		var w: float = spec.get("w", 8.0)
		var tries := 0
		while s + w <= s1 and tries < 40:
			var p := origin + dir * (s + w * 0.5)
			if add(spec, p, face, spec.get("porch", porch), true, 0.3, -0.8):
				placed.append(spec)
				break
			s += 2.0
			tries += 1
		if not spec.has("xf"):
			continue
		count += 1
		s += w + rng.randf_range(gaps.x, gaps.y)
		if alley_every > 0 and count % alley_every == 0:
			s += rng.randf_range(3.0, 5.0)
	return placed

## Mark neighbour gaps so boardwalks join (no end steps where the next boardwalk touches).
func join_boardwalks(specs: Array) -> void:
	for a in specs:
		var pa: Vector2 = a.town_pos
		var fa: Vector2 = a.town_face
		var bx: Vector3 = a.xf.basis.x
		var lxt := Vector2((frame.basis.inverse() * bx).x, (frame.basis.inverse() * bx).z)
		var ends := [true, true]
		for b in specs:
			if b == a:
				continue
			var d: Vector2 = b.town_pos - pa
			var along := d.dot(lxt)
			var across := absf(d.dot(fa))
			if across > 1.0:
				continue
			var gap: float = absf(along) - (a.w + b.w) * 0.5
			if gap < 3.5:
				if along < 0.0:
					ends[0] = false
				else:
					ends[1] = false
					if gap > 0.05:
						a["deck_bridge"] = gap        # this boardwalk extends over the gap to its +x neighbour
		a["end_steps"] = ends
	# touching boardwalks share one floor level (the highest of the run) so they join without ledges
	var run_of := {}
	for i in specs.size():
		run_of[i] = i
	for i in specs.size():
		for j in range(i + 1, specs.size()):
			var a2: Dictionary = specs[i]
			var b2: Dictionary = specs[j]
			var dd: Vector2 = b2.town_pos - a2.town_pos
			if absf(dd.dot(a2.town_face)) > 1.0:
				continue
			if dd.length() - (a2.w + b2.w) * 0.5 < 3.5:
				var ri: int = _root(run_of, i)
				var rj: int = _root(run_of, j)
				run_of[rj] = ri
	var top := {}
	for i in specs.size():
		var r: int = _root(run_of, i)
		top[r] = maxf(top.get(r, -INF), specs[i].xf.origin.y)
	for i in specs.size():
		var x: Transform3D = specs[i].xf
		x.origin.y = top[_root(run_of, i)]
		specs[i].xf = x

static func _root(m: Dictionary, i: int) -> int:
	while m[i] != i:
		i = m[i]
	return i

func pick_paint() -> Color:
	return BuildingGen.PAINTS[rng.randi() % BuildingGen.PAINTS.size()]

## Connect every worldgen road ending at this settlement to the street network; returns entry points.
func road_connectors(main_a: Vector2, main_b: Vector2, inner := 0.72) -> Array:
	var entries := []
	var R := float(t.r) * inner
	for r in _roads:
		var pts: PackedVector2Array = r.pts
		var entry := Vector2.INF
		for i in pts.size():
			if pts[i].length() > R:
				entry = pts[i]
				break
		if entry == Vector2.INF:
			continue
		var ab := main_b - main_a
		var tt := clampf((entry - main_a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var join := main_a + ab * tt
		if entry.distance_to(join) > 6.0:
			street(entry, join, 9.0)
		entries.append({"entry": entry, "join": join, "other": r.other})
	return entries

## Where does the main street (x axis, z = 0) cross the river? Returns [s_start, s_end] or [].
func river_crossing(s0: float, s1: float) -> Array:
	var inside := false
	var a := 0.0
	var b := 0.0
	var s := s0
	while s <= s1:
		var wet := not river_clear(Vector2(s, 0.0), 1.5)
		if wet and not inside:
			a = s
			inside = true
		if inside:
			b = s
			if not wet and s - b > 0.0:
				break
		if inside and not wet:
			break
		s += 1.0
	return [a, b] if inside else []

## A wooden road bridge along the main street from s0 to s1 (town space x axis).
func bridge(s0: float, s1: float, width := 7.0) -> void:
	var y := maxf(gh(Vector2(s0, 0.0)), gh(Vector2(s1, 0.0))) + 0.25
	var spec := {"style": "bridge", "type": "bridge", "w": width, "d": s1 - s0, "length": s1 - s0, "floor_y": y,
		"ground_ref": false}
	# local +z along town +x: front faces town -x
	add(spec, Vector2(s0, 0.0), Vector2(-1, 0), 0.0, false)

func street_kit(items: Array) -> void:
	var spec := {"style": "street_kit", "type": "street", "w": 1.0, "d": 1.0, "items": items, "floor_y": frame.origin.y}
	_n += 1
	spec["id"] = "%s/%02d_street" % [t.id, _n]
	spec["town"] = t.id
	spec["xf"] = frame
	spec["weather"] = weather
	spec["town_pos"] = Vector2.ZERO
	spec["town_face"] = Vector2(0, -1)
	plan.specs.append(spec)

## Lamp posts, hitching rails and troughs along both sides of a street segment between s0 and s1 at |z| = off.
func dress_main_street(s0: float, s1: float, off: float, lots: Array) -> void:
	var items := []
	var s := s0 + 6.0
	var side := 1.0
	while s < s1 - 4.0:
		var p := Vector2(s, side * (off + 0.4))
		if river_clear(p, 3.0) and street_dist(p) > -MAIN_W * 0.5 - 1.0:
			items.append({"k": "lamp", "x": p.x, "z": p.y})
		s += 24.0
		side = -side
	# telegraph line along the north edge of the street
	var ps := s0 + 3.0
	while ps < s1:
		var pp := Vector2(ps, -(off + 3.6))
		if river_clear(pp, 3.0):
			items.append({"k": "pole", "x": pp.x, "z": pp.y, "yaw": 0.0})
		ps += 38.0
	for spec in lots:
		var typ: String = spec.get("type", "")
		var p: Vector2 = spec.town_pos
		var f: Vector2 = spec.town_face
		var curb: Vector2 = p + f * (spec.get("porch", 2.8) + 1.4)
		if typ in ["saloon", "hotel", "store", "livery", "sheriff", "cantina", "restaurant", "smithy"]:
			var sx := Vector2(-f.y, f.x)
			items.append({"k": "hitch", "x": curb.x + sx.x * 1.5, "z": curb.y + sx.y * 1.5, "len": 3.0})
			if typ in ["saloon", "livery", "store"]:
				items.append({"k": "trough", "x": curb.x - sx.x * 2.6, "z": curb.y - sx.y * 2.6})
		elif rng.randf() < 0.3:
			var pb: Vector2 = p + f * 1.0 + Vector2(-f.y, f.x) * (spec.w * 0.35)
			items.append({"k": "barrels" if rng.randf() < 0.5 else "crates", "x": pb.x, "z": pb.y})
	street_kit(items)

## A few wagons drawn up along the street in front of stores and the livery.
func _parked_wagons(lots: Array, hw: float, n: int) -> void:
	var placed := 0
	for spec in lots:
		if placed >= n:
			break
		if not str(spec.get("type", "")) in ["store", "livery", "hotel", "smithy", "restaurant"]:
			continue
		var p: Vector2 = spec.town_pos
		var f: Vector2 = spec.town_face
		var q := Vector2(p.x + rng.randf_range(-2.0, 2.0), -signf(f.y) * (hw - 3.2)) if absf(f.y) > 0.5 else p + f * 6.0
		q.y = (hw - 3.2) * (-1.0 if p.y < 0.0 else 1.0)
		var w := {"style": "wagon", "type": "wagon", "w": 1.8, "d": 3.6, "covered": rng.randf() < 0.35, "raise": 0.0,
			"paint": [Color(0.4, 0.45, 0.32), Color(0.5, 0.25, 0.18), Color(0.35, 0.38, 0.45)][placed % 3]}
		if add(w, q, Vector2(1, 0) if rng.randf() < 0.5 else Vector2(-1, 0), 0.0, true, 0.3, -100.0):
			placed += 1

func houses_along(a: Vector2, b: Vector2, both := true, setback := 9.0, kinds := ["house"], spacing := Vector2(15.0, 22.0)) -> Array:
	var dir := (b - a).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var L := a.distance_to(b)
	var placed := []
	for sgn in ([1.0, -1.0] if both else [1.0]):
		var s := rng.randf_range(2.0, 8.0)
		while s < L - 6.0:
			var kind: String = kinds[rng.randi() % kinds.size()]
			var spec := house_spec(kind)
			var p: Vector2 = a + dir * s + nrm * sgn * setback
			if add(spec, p, -nrm * sgn, spec.get("porch", 0.0), true, 2.0):
				placed.append(spec)
				# outhouse / shed behind
				if rng.randf() < 0.6:
					var back: Vector2 = p + nrm * sgn * (spec.d + 5.0) + dir * rng.randf_range(-3.0, 3.0)
					add({"style": "outhouse", "type": "outhouse", "w": 1.2, "d": 1.3, "raise": 0.0}, back, -nrm * sgn, 0.0, true, 0.5)
				s += spec.w + rng.randf_range(spacing.x, spacing.y) * 0.5
			else:
				s += 4.0
	return placed

func house_spec(kind: String) -> Dictionary:
	match kind:
		"cabin":
			return {"style": "cabin", "type": "cabin", "interior": "cabin", "w": rng.randf_range(5.0, 6.5), "d": rng.randf_range(4.0, 5.0),
				"roof": "roof_planks" if rng.randf() < 0.6 else "shingles", "raise": 0.25, "porch": 0.0 if rng.randf() < 0.5 else 1.6, "furnished": true}
		"adobe_house":
			return {"style": "adobe", "type": "adobe_house", "interior": "house", "w": rng.randf_range(6.0, 9.0), "d": rng.randf_range(5.0, 7.0),
				"wall": "adobe" if rng.randf() < 0.7 else "plaster", "paint": Color(1.0, 0.92, 0.82).lerp(Color(0.85, 0.7, 0.55), rng.randf()),
				"raise": 0.12, "porch": 0.0 if rng.randf() < 0.4 else 2.2, "furnished": true}
		"tent":
			return {"style": "tent", "type": "tent", "interior": "tent", "w": rng.randf_range(3.0, 4.0), "d": rng.randf_range(4.0, 5.0), "raise": 0.0}
		_:
			var painted := rng.randf() < 0.75
			return {"style": "house", "type": "house", "interior": "house", "w": rng.randf_range(6.0, 8.5), "d": rng.randf_range(7.0, 9.0),
				"wall": "paint" if painted else "siding", "paint": pick_paint(), "raise": 0.5, "porch": 2.0 if rng.randf() < 0.7 else 0.0,
				"roof": "shingles" if rng.randf() < 0.75 else "roof_planks", "furnished": true}

# ------------------------------------------------------------------------------------------------ Bitter Spring

func _bitter_spring() -> void:
	weather = 0.35
	var hw := MAIN_W * 0.5
	var smin := -175.0
	var smax := 200.0
	var cross := river_crossing(-60.0, 160.0)
	var west_end := smax
	var east_start := smax
	if not cross.is_empty():
		west_end = cross[0] - 6.0
		east_start = cross[1] + 6.0
	street(Vector2(smin - 20.0, 0.0), Vector2(smax, 0.0), MAIN_W)
	var side_s := [-98.0, -22.0]
	for ss in side_s:
		street(Vector2(ss, -hw), Vector2(ss, -95.0), SIDE_W)
		street(Vector2(ss, hw), Vector2(ss, 62.0), SIDE_W)
	if not cross.is_empty():
		bridge(cross[0] - 5.0, cross[1] + 5.0, 7.5)
	var north := [
		{"style": "two_storey", "type": "hotel", "name": "Sable Hotel", "sign": "SABLE HOTEL", "sign2": "ROOMS  BATHS  MEALS", "w": 14.0, "d": 18.0, "wall": "paint", "paint": Color(0.95, 0.9, 0.78), "trim": Color(0.25, 0.32, 0.26), "furnished": true, "role": "hotelier", "hours": [0.0, 24.0]},
		{"style": "two_storey", "type": "saloon", "name": "Brass Rail Saloon", "sign": "BRASS RAIL SALOON", "sign2": "BILLIARDS  CIGARS  FINE WHISKEY", "w": 13.0, "d": 20.0, "wall": "siding", "paint": Color(0.9, 0.82, 0.7), "trim": Color(0.55, 0.18, 0.14), "furnished": true, "role": "bartender", "hours": [10.0, 26.0]},
		{"style": "false_front", "type": "barber", "name": "Barber", "sign": "BARBER\nSHAVES  BATHS", "w": 6.5, "d": 14.0, "wall": "paint", "paint": Color(0.92, 0.92, 0.9), "trim": Color(0.55, 0.18, 0.14), "furnished": true, "role": "barber", "sign2": "BATHS 25c"},
		{"style": "false_front", "type": "store", "name": "Hollis General Merchandise", "sign": "J. HOLLIS\nGENERAL MERCHANDISE", "w": 11.0, "d": 18.0, "wall": "paint", "paint": Color(0.86, 0.74, 0.5), "trim": Color(0.25, 0.22, 0.18), "furnished": true, "role": "storekeeper", "top": "stepped"},
		{"style": "brick", "type": "bank", "name": "Bitter Spring Savings Bank", "sign": "BITTER SPRING SAVINGS BANK", "w": 10.0, "d": 14.0, "storeys": 2, "furnished": true, "role": "banker", "hours": [9.0, 15.0]},
		{"style": "false_front", "type": "doctor", "name": "Dr. Marlowe", "sign": "DR. E. MARLOWE\nPHYSICIAN & SURGEON", "w": 7.5, "d": 14.0, "wall": "paint", "paint": Color(0.7, 0.75, 0.78), "furnished": true, "role": "doctor"},
		{"style": "false_front", "type": "gunsmith", "name": "Voss Gunsmith", "sign": "A. VOSS\nGUNSMITH", "w": 8.0, "d": 15.0, "wall": "siding", "furnished": true, "role": "gunsmith", "top": "pediment"},
		{"style": "false_front", "type": "undertaker", "name": "Pruitt Undertaker", "sign": "O. PRUITT\nUNDERTAKER", "w": 7.0, "d": 14.0, "wall": "dark_planks", "furnished": true, "role": "undertaker"},
		{"style": "false_front", "type": "post", "name": "Post Office", "sign": "POST OFFICE\nWESTERN TELEGRAPH", "w": 8.0, "d": 12.0, "wall": "paint", "paint": Color(0.9, 0.88, 0.82), "furnished": true, "role": "postmaster"},
	]
	var south := [
		{"style": "false_front", "type": "sheriff", "name": "Sheriff's Office", "sign": "SHERIFF\nCOUNTY JAIL", "w": 10.0, "d": 15.0, "wall": "siding", "paint": Color(0.85, 0.8, 0.72), "furnished": true, "role": "sheriff", "hours": [0.0, 24.0], "top": "flat"},
		{"style": "false_front", "type": "restaurant", "name": "Cafe", "sign": "LUCY'S CAFE\nMEALS AT ALL HOURS", "w": 9.0, "d": 14.0, "wall": "paint", "paint": Color(0.95, 0.88, 0.7), "furnished": true, "role": "cook", "hours": [6.0, 21.0]},
		{"style": "false_front", "type": "store", "interior": "store", "name": "Millinery", "sign": "MILLINERY\nDRY GOODS", "w": 7.5, "d": 13.0, "wall": "paint", "paint": Color(0.75, 0.82, 0.74), "furnished": true, "role": "storekeeper"},
		{"style": "brick", "type": "land_office", "interior": "post", "name": "Meridian & Western Land Co.", "sign": "MERIDIAN & WESTERN LAND CO.", "w": 9.5, "d": 13.0, "storeys": 2, "furnished": true, "role": "clerk", "paint": Color(0.95, 0.85, 0.8)},
		{"style": "false_front", "type": "butcher", "name": "Meat Market", "sign": "MEAT MARKET", "w": 7.0, "d": 12.0, "wall": "paint", "paint": Color(0.62, 0.25, 0.18), "furnished": true, "role": "butcher"},
		{"style": "false_front", "type": "newspaper", "interior": "post", "name": "Sable River Courier", "sign": "SABLE RIVER\nCOURIER", "w": 8.0, "d": 13.0, "wall": "siding", "furnished": true, "role": "editor"},
		{"style": "smithy", "type": "smithy", "name": "Blacksmith", "sign": "T. BOONE  BLACKSMITH", "w": 9.0, "d": 9.0, "porch": 0.0, "raise": 0.05, "role": "blacksmith", "furnished": true},
		{"style": "barn", "type": "livery", "interior": "livery", "name": "McCrae Livery", "sign": "McCRAE LIVERY & FEED", "w": 13.0, "d": 18.0, "porch": 0.0, "raise": 0.05, "paint": Color(0.62, 0.25, 0.18), "wall": "paint", "role": "stablehand", "furnished": true},
	]
	var lots_n := row(north, Vector2(0.0, -(hw + 2.8)), Vector2(1, 0), Vector2(0, 1), smin + 30.0, west_end, 2.8, Vector2(0.0, 1.8), 4)
	var lots_s := row(south, Vector2(0.0, hw + 2.8), Vector2(1, 0), Vector2(0, -1), smin + 30.0, west_end, 2.8, Vector2(0.0, 1.8), 4)
	join_boardwalks(lots_n)
	join_boardwalks(lots_s)
	# corral next to the livery
	for spec in lots_s:
		if spec.type == "livery":
			var p: Vector2 = spec.town_pos
			add({"style": "corral", "type": "corral", "w": 18.0, "d": 16.0, "raise": 0.0}, p + Vector2(spec.w * 0.5 + 11.0, 4.0), Vector2(0, -1), 0.0, true, 0.5)
	# church closing the west end of the street, school beside it
	add({"style": "church", "type": "church", "name": "Church", "sign": "FIRST CHURCH", "w": 9.0, "d": 16.0, "porch": 3.6, "furnished": true, "role": "preacher", "raise": 0.5},
		Vector2(smin - 6.0, 0.0), Vector2(1, 0), 3.6, true, 1.0, -100.0)
	add({"style": "school", "type": "school", "name": "School", "sign": "SCHOOL", "w": 7.5, "d": 10.0, "porch": 1.6, "furnished": true, "role": "teacher", "wall": "paint", "paint": Color(0.62, 0.25, 0.18), "trim": Color(0.95, 0.94, 0.9), "raise": 0.5},
		Vector2(smin + 8.0, 34.0), Vector2(0, -1), 1.6, true, 1.0)
	# railroad depot, water tower and stock pens along the rail
	_depot("BITTER SPRING", 22.0)
	# water tank and windmill behind the north block (town water), houses along the side streets
	add({"style": "windmill", "type": "windmill", "w": 3.0, "d": 3.0, "raise": 0.0, "h": 10.0}, Vector2(-60.0, -52.0), Vector2(0, 1), 0.0, true, 1.0)
	for ss in side_s:
		houses_along(Vector2(ss, -hw - 30.0), Vector2(ss, -95.0), true, 10.0)
		houses_along(Vector2(ss, hw + 30.0), Vector2(ss, 62.0), true, 10.0)
	# east of the river: stockyard, cabins, a feed barn
	if not cross.is_empty():
		var e0: float = east_start + 6.0
		houses_along(Vector2(e0, -hw - 6.0), Vector2(e0 + 90.0, -hw - 6.0), false, 6.0, ["house", "cabin"])
		add({"style": "barn", "type": "barn", "interior": "livery", "w": 12.0, "d": 16.0, "raise": 0.05, "wall": "planks_v", "furnished": true}, Vector2(e0 + 40.0, hw + 12.0), Vector2(0, -1), 0.0, true, 2.0)
		add({"style": "corral", "type": "corral", "w": 24.0, "d": 20.0, "raise": 0.0}, Vector2(e0 + 70.0, hw + 8.0), Vector2(0, -1), 0.0, true, 1.0)
	var entries := road_connectors(Vector2(smin - 20.0, 0.0), Vector2(smax, 0.0))
	_sign_posts(entries)
	dress_main_street(smin + 20.0, west_end, hw, lots_n + lots_s)
	_parked_wagons(lots_n + lots_s, hw, 3)
	_fill_backlots(0.55, ["house", "house", "cabin"])

## Depot beside the rail at its closest approach to the town, with platform, water tower and a street to it.
## Station track along the rail inside the settlement (and a little beyond).
func _track() -> void:
	var rail = world.features.get("rail", null)
	if rail == null:
		return
	var R := float(t.r) + 60.0
	var pts := []
	for p in rail.points:
		if Vector2(p[0] - t.x, p[1] - t.z).length() < R:
			pts.append(p)
	if pts.size() < 2:
		return
	var spec := {"style": "track", "type": "track", "w": 1.0, "d": 1.0, "points": pts, "ground_ref": false}
	if not plan.has("paint_lines"):
		plan["paint_lines"] = []
	var step := 6
	var i0 := 0
	while i0 < pts.size() - 1:
		var i1 := mini(i0 + step, pts.size() - 1)
		plan.paint_lines.append({"a": to_town(pts[i0][0], pts[i0][1]), "b": to_town(pts[i1][0], pts[i1][1]), "w": 4.5})
		i0 = i1
	_n += 1
	spec["id"] = "%s/%02d_track" % [t.id, _n]
	spec["town"] = t.id
	spec["xf"] = frame
	spec["weather"] = weather
	spec["town_pos"] = Vector2.ZERO
	spec["town_face"] = Vector2(0, -1)
	plan.specs.append(spec)

func _depot(name: String, along_offset := 0.0, with_tower := true) -> void:
	if _rail.size() < 2:
		return
	_track()
	var best := INF
	var bi := 0
	for i in _rail.size() - 1:
		var d := _seg_dist(Vector2.ZERO, _rail[i], _rail[i + 1])
		if d < best:
			best = d
			bi = i
	if best > float(t.r) * 0.95:
		return
	var a: Vector2 = _rail[bi]
	var b: Vector2 = _rail[mini(bi + 1, _rail.size() - 1)]
	var dir := (b - a).normalized()
	var ab := b - a
	var tt := clampf((-a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var near := a + ab * tt + dir * along_offset
	var nrm := Vector2(-dir.y, dir.x)
	if nrm.dot(-near) < 0.0:
		nrm = -nrm                     # towards the town centre
	var front := near + nrm * 8.2      # depot front wall (platform 4.5 m, track clearance)
	var ok := add({"style": "depot", "type": "depot", "name": name + " depot", "sign": name, "w": 18.0, "d": 7.0, "porch": 4.5,
		"wall": "paint", "paint": Color(0.88, 0.8, 0.6), "trim": Color(0.42, 0.25, 0.16), "furnished": true, "role": "station_agent", "raise": 0.65},
		front, -nrm, 4.5, true, 0.5, 0.5, 3.0)
	if not ok:
		for k in [12.0, -12.0, 24.0, -24.0, 36.0]:
			if add({"style": "depot", "type": "depot", "name": name + " depot", "sign": name, "w": 18.0, "d": 7.0, "porch": 4.5,
					"wall": "paint", "paint": Color(0.88, 0.8, 0.6), "trim": Color(0.42, 0.25, 0.16), "furnished": true, "role": "station_agent", "raise": 0.65},
					front + dir * k, -nrm, 4.5, true, 0.5, 0.5, 3.0):
				front += dir * k
				ok = true
				break
	if ok:
		var join := Vector2(front.x, 0.0)
		street(front + nrm * 8.0, join, 9.0)
		street(front + nrm * 4.0 - dir * 14.0, front + nrm * 4.0 + dir * 14.0, 8.0)
	if with_tower:
		var tw := near + dir * 34.0 + nrm * 5.0
		if not add({"style": "water_tower", "type": "water_tower", "w": 7.0, "d": 7.0, "radius": 2.9, "raise": 0.0, "sign": name.split(" ")[0]},
				tw, -nrm, 0.0, true, 0.5, 0.5, 3.0):
			add({"style": "water_tower", "type": "water_tower", "w": 7.0, "d": 7.0, "radius": 2.9, "raise": 0.0},
				near - dir * 40.0 + nrm * 5.0, -nrm, 0.0, true, 0.5, 0.5, 3.0)
	add({"style": "corral", "type": "stock_pen", "w": 20.0, "d": 14.0, "raise": 0.0, "trough": true}, near - dir * 30.0 + nrm * 16.0, -nrm, 0.0, true, 0.5, 0.5, 5.0)

func _sign_posts(entries: Array) -> void:
	var items := []
	for e in entries:
		var p: Vector2 = e.join + (e.entry - e.join).normalized() * 9.0
		var txt := []
		var other = world.town(str(e.other))
		if other.is_empty():
			other = world.poi(str(e.other))
		if not other.is_empty():
			var km := Vector2(other.x - t.x, other.z - t.z).length() / 1609.0
			txt.append("%s  %d MI" % [str(other.name).to_upper().split(",")[0], maxi(1, roundi(km))])
		if txt.size() > 0:
			items.append({"k": "sign_post", "x": p.x + 5.0, "z": p.y + 5.0, "text": txt})
	if items.size() > 0:
		street_kit(items)

## Sprinkle extra houses/cabins/sheds into free land around the core so the town thins out naturally.
func _fill_backlots(density: float, kinds: Array) -> void:
	var R := float(t.r)
	var n := int(R * R * 0.00018 * density)
	for i in n:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf_range(0.25, 0.9)) * R
		var p := Vector2(cos(a), sin(a)) * r
		if street_dist(p) < 6.0:
			continue
		var spec := house_spec(kinds[rng.randi() % kinds.size()])
		var face := Vector2(0, -1) if p.y > 0.0 else Vector2(0, 1)
		if rng.randf() < 0.3:
			face = Vector2(-1, 0) if p.x > 0.0 else Vector2(1, 0)
		if add(spec, p, face, spec.get("porch", 0.0), true, 3.0) and rng.randf() < 0.5:
			add({"style": "shed", "type": "shed", "w": 3.0, "d": 3.0, "raise": 0.1}, p - face * (spec.d + 4.0) + Vector2(rng.randf_range(-3, 3), 0), face, 0.0, true, 0.5)

# ------------------------------------------------------------------------------------------------ Coldwater

func _coldwater() -> void:
	weather = 0.62
	var hw := 7.5
	var smin := -85.0
	var smax := 80.0
	street(Vector2(smin - 15.0, 0.0), Vector2(smax + 20.0, 0.0), hw * 2.0)
	street(Vector2(-10.0, hw), Vector2(-10.0, 70.0), 9.0)
	var north := [
		{"style": "false_front", "type": "saloon", "interior": "saloon", "name": "Silver Dollar", "sign": "SILVER DOLLAR\nSALOON", "w": 10.0, "d": 16.0, "wall": "planks_raw", "furnished": true, "role": "bartender", "hours": [11.0, 27.0], "awning": "shed"},
		{"style": "tent", "type": "tent_store", "interior": "store", "name": "Tent store", "sign": "PICKS  POWDER  BOOTS", "w": 6.0, "d": 9.0, "wall_h": 1.8, "ridge_h": 3.6, "floor": true, "raise": 0.3, "furnished": true, "porch": 0.0},
		{"style": "false_front", "type": "assay", "interior": "assay", "name": "Assay Office", "sign": "ASSAY OFFICE", "w": 7.0, "d": 11.0, "wall": "siding", "furnished": true, "role": "assayer", "awning": ""},
		{"style": "false_front", "type": "store", "name": "Kestrel Supply", "sign": "KESTREL\nMINING SUPPLY", "w": 9.0, "d": 15.0, "wall": "planks_raw", "furnished": true, "role": "storekeeper"},
		{"style": "tent", "type": "tent", "w": 4.0, "d": 5.0, "raise": 0.0, "porch": 0.0},
		{"style": "false_front", "type": "gunsmith", "name": "Guns & Ammunition", "sign": "GUNS\nAMMUNITION", "w": 6.5, "d": 12.0, "wall": "planks_raw", "furnished": true, "role": "gunsmith", "awning": ""},
	]
	var south := [
		{"style": "two_storey", "type": "hotel", "interior": "boarding", "name": "Miners' Rest", "sign": "MINERS' REST\nBOARD & LODGING", "w": 12.0, "d": 16.0, "wall": "siding", "furnished": true, "role": "hotelier", "hours": [0.0, 24.0]},
		{"style": "false_front", "type": "restaurant", "name": "Eats", "sign": "HOT MEALS", "w": 7.0, "d": 12.0, "wall": "planks_raw", "furnished": true, "role": "cook", "awning": ""},
		{"style": "tent", "type": "tent", "w": 3.6, "d": 4.6, "raise": 0.0, "porch": 0.0},
		{"style": "false_front", "type": "sheriff", "name": "Deputy", "sign": "DEPUTY MARSHAL", "w": 7.0, "d": 13.0, "wall": "siding", "furnished": true, "role": "sheriff", "hours": [0.0, 24.0]},
		{"style": "tent", "type": "tent", "w": 3.4, "d": 4.4, "raise": 0.0, "porch": 0.0},
		{"style": "barn", "type": "livery", "interior": "livery", "name": "Livery", "sign": "LIVERY", "w": 10.0, "d": 14.0, "porch": 0.0, "raise": 0.05, "wall": "planks_raw", "role": "stablehand", "furnished": true, "roof": "roof_planks"},
	]
	var ln := row(north, Vector2(0.0, -(hw + 2.6)), Vector2(1, 0), Vector2(0, 1), smin, smax, 2.6, Vector2(0.5, 4.0), 3)
	var ls := row(south, Vector2(0.0, hw + 2.6), Vector2(1, 0), Vector2(0, -1), smin, smax, 2.6, Vector2(0.5, 4.0), 3)
	join_boardwalks(ln)
	join_boardwalks(ls)
	# the mine: head-frame with hoist house up at the edge of camp
	var mine := Vector2(smax + 45.0, -45.0)
	for k in 8:
		if add({"style": "headframe", "type": "headframe", "w": 6.0, "d": 6.0, "h": 13.0, "raise": 0.0}, mine, Vector2(0, 1), 0.0, true, 2.0):
			add({"style": "shed", "type": "hoist_house", "w": 7.0, "d": 6.0, "h": 3.2, "wall": "corrugated", "roof": "corrugated", "raise": 0.1},
				mine + Vector2(0, 12.0), Vector2(0, -1), 0.0, true, 0.5)
			street(mine + Vector2(0, 4.0), Vector2(mine.x - 30.0, 0.0), 6.0)
			break
		mine = Vector2(mine.x - 12.0, mine.y + 6.0 * (1 if k % 2 == 0 else -1))
	# tent rows and cabins on the slopes
	houses_along(Vector2(-10.0, hw + 26.0), Vector2(-10.0, 70.0), true, 7.0, ["tent", "cabin", "tent"])
	for i in 14:
		var p := Vector2(rng.randf_range(-120.0, 110.0), rng.randf_range(-110.0, 110.0))
		if absf(p.y) < 30.0 or street_dist(p) < 4.0:
			continue
		var kind: String = ["tent", "tent", "cabin", "cabin", "shed"][rng.randi() % 5]
		var spec := house_spec(kind) if kind != "shed" else {"style": "shed", "type": "shed", "w": 3.0, "d": 3.0, "raise": 0.1}
		add(spec, p, Vector2(0, -signf(p.y)), spec.get("porch", 0.0), true, 2.5)
	add({"style": "woodpile", "type": "woodpile", "w": 3.0, "d": 1.0, "raise": 0.0}, Vector2(-30.0, -32.0), Vector2(0, 1), 0.0, true, 0.5)
	var entries := road_connectors(Vector2(smin - 15.0, 0.0), Vector2(smax + 20.0, 0.0))
	_sign_posts(entries)
	dress_main_street(smin, smax, hw, ln + ls)

# ------------------------------------------------------------------------------------------------ Mesquite Wells

func _mesquite_wells() -> void:
	weather = 0.5
	var hw := 9.0
	street(Vector2(-150.0, 0.0), Vector2(150.0, 0.0), hw * 2.0)
	# the plaza: a wide open square around the well
	street(Vector2(-22.0, -10.0), Vector2(22.0, -10.0), 26.0)
	add({"style": "well", "type": "well", "w": 2.0, "d": 2.0, "raise": 0.0}, Vector2(0.0, -10.0), Vector2(0, 1), 0.0, false)
	var adobe := func(type: String, name: String, sign: String, w: float, d: float, interior: String, role := ""):
		return {"style": "adobe", "type": type, "interior": interior, "name": name, "sign": sign, "w": w, "d": d,
			"wall": "adobe" if rng.randf() < 0.6 else "plaster", "paint": Color(1.0, 0.92, 0.8).lerp(Color(0.85, 0.68, 0.5), rng.randf()),
			"porch": 2.4, "raise": 0.15, "furnished": true, "role": role}
	var north := [
		adobe.call("cantina", "Cantina", "CANTINA LA PALOMA", 11.0, 10.0, "cantina", "bartender"),
		adobe.call("store", "Mercantile", "MERCANTIL", 10.0, 9.0, "store", "storekeeper"),
		adobe.call("adobe_house", "", "", 7.0, 6.0, "house"),
		adobe.call("doctor", "Doctor", "MEDICO", 7.0, 7.0, "doctor", "doctor"),
		adobe.call("adobe_house", "", "", 8.0, 6.0, "house"),
	]
	var south := [
		adobe.call("sheriff", "Marshal", "MARSHAL", 8.0, 8.0, "sheriff", "sheriff"),
		{"style": "false_front", "type": "hotel", "interior": "store", "name": "Stage Station", "sign": "STAGE & EXPRESS", "w": 9.0, "d": 12.0, "wall": "planks_brown", "furnished": true, "role": "agent", "porch": 2.8},
		adobe.call("adobe_house", "", "", 7.5, 6.0, "house"),
		adobe.call("barber", "Barberia", "BARBERIA", 6.5, 7.0, "barber", "barber"),
		adobe.call("adobe_house", "", "", 8.0, 6.5, "house"),
	]
	var ln := row(north, Vector2(0.0, -(hw + 2.4 + 16.0)), Vector2(1, 0), Vector2(0, 1), -120.0, 120.0, 2.4, Vector2(1.0, 6.0), 2)
	var ls := row(south, Vector2(0.0, hw + 2.4), Vector2(1, 0), Vector2(0, -1), -120.0, 120.0, 2.4, Vector2(1.0, 6.0), 2)
	# adobe chapel facing the plaza
	add({"style": "church", "type": "church", "name": "Chapel", "wall": "plaster", "paint": Color(0.97, 0.94, 0.88), "w": 8.0, "d": 14.0, "porch": 3.6, "furnished": true, "role": "preacher", "raise": 0.3, "sign": "SAN ISIDRO"},
		Vector2(-60.0, -45.0), Vector2(0, 1), 3.6, true, 1.0)
	_depot("MESQUITE WELLS", 0.0, true)
	add({"style": "windmill", "type": "windmill", "w": 3.0, "d": 3.0, "raise": 0.0, "h": 9.0}, Vector2(40.0, 40.0), Vector2(0, -1), 0.0, true, 1.0)
	add({"style": "corral", "type": "corral", "w": 22.0, "d": 18.0, "raise": 0.0, "split_rail": false}, Vector2(80.0, 30.0), Vector2(0, -1), 0.0, true, 1.0)
	for i in 10:
		var p := Vector2(rng.randf_range(-140.0, 140.0), rng.randf_range(-120.0, 120.0))
		if street_dist(p) < 6.0:
			continue
		var spec := house_spec("adobe_house")
		add(spec, p, Vector2(0, -signf(p.y)), spec.get("porch", 0.0), true, 3.0)
	var entries := road_connectors(Vector2(-150.0, 0.0), Vector2(150.0, 0.0))
	_sign_posts(entries)
	dress_main_street(-110.0, 110.0, hw, ln + ls)

# ------------------------------------------------------------------------------------------------ Port Linden

func _port_linden() -> void:
	weather = 0.25
	var hw := 11.0
	var smin := -190.0
	var smax := 190.0
	street(Vector2(smin, 0.0), Vector2(smax, 0.0), hw * 2.0)
	for ss in [-110.0, -30.0, 50.0, 125.0]:
		street(Vector2(ss, -hw), Vector2(ss, -150.0), SIDE_W)
		street(Vector2(ss, hw), Vector2(ss, 150.0), SIDE_W)
	var brick := func(type: String, name: String, sign: String, w: float, d: float, storeys: int, interior: String, role := "", sign2 := ""):
		var s := {"style": "brick", "type": type, "interior": interior, "name": name, "sign": sign, "w": w, "d": d, "storeys": storeys,
			"furnished": true, "role": role, "paint": Color(1.0, 0.95, 0.9).lerp(Color(0.85, 0.7, 0.62), rng.randf())}
		if sign2 != "":
			s["sign2"] = sign2
		return s
	var west := [
		brick.call("hotel", "Linden House", "LINDEN HOUSE HOTEL", 16.0, 20.0, 3, "hotel", "hotelier", "LINDEN HOUSE"),
		brick.call("bank", "Lakeshore Bank", "LAKESHORE NATIONAL BANK", 11.0, 15.0, 2, "bank", "banker"),
		brick.call("newspaper", "Linden Gazette", "THE LINDEN GAZETTE", 9.0, 14.0, 2, "post", "editor"),
		brick.call("store", "Dry Goods", "HALVERSEN & SONS DRY GOODS", 12.0, 18.0, 2, "store", "storekeeper"),
		brick.call("office", "Railroad Office", "MERIDIAN & WESTERN RAILROAD", 12.0, 15.0, 3, "post", "clerk", "M & W R.R."),
		{"style": "two_storey", "type": "saloon", "name": "Anchor Saloon", "sign": "THE ANCHOR", "sign2": "OYSTERS  BEER  BILLIARDS", "w": 12.0, "d": 18.0, "wall": "paint", "paint": Color(0.3, 0.42, 0.36), "furnished": true, "role": "bartender", "hours": [10.0, 26.0]},
		brick.call("gunsmith", "Gun Shop", "SPORTING GOODS  FIREARMS", 9.0, 14.0, 2, "gunsmith", "gunsmith"),
		brick.call("doctor", "Physician", "DR. A. KEMP  PHYSICIAN", 8.0, 13.0, 2, "doctor", "doctor"),
	]
	var east := [
		brick.call("store", "Chandlery", "SHIP CHANDLERY", 11.0, 16.0, 2, "store", "storekeeper"),
		brick.call("sheriff", "City Marshal", "CITY MARSHAL", 10.0, 14.0, 2, "sheriff", "sheriff"),
		{"style": "false_front", "type": "barber", "name": "Barber", "sign": "TONSORIAL PARLOR", "w": 7.0, "d": 13.0, "wall": "paint", "paint": Color(0.92, 0.92, 0.9), "furnished": true, "role": "barber"},
		brick.call("post", "Post Office", "U.S. POST OFFICE", 10.0, 14.0, 2, "post", "postmaster"),
		{"style": "false_front", "type": "restaurant", "name": "Chop House", "sign": "LAKESIDE CHOP HOUSE", "w": 10.0, "d": 15.0, "wall": "paint", "paint": Color(0.95, 0.9, 0.78), "furnished": true, "role": "cook"},
		brick.call("warehouse", "Warehouse", "LINDEN FREIGHT & STORAGE", 16.0, 22.0, 2, "warehouse", "clerk"),
		{"style": "false_front", "type": "undertaker", "name": "Undertaker", "sign": "UNDERTAKER", "w": 7.0, "d": 13.0, "wall": "dark_planks", "furnished": true, "role": "undertaker"},
		brick.call("store", "Hardware", "HARDWARE  STOVES  TINWARE", 11.0, 16.0, 2, "store", "storekeeper"),
	]
	var lw := row(west, Vector2(0.0, -(hw + 3.0)), Vector2(1, 0), Vector2(0, 1), smin + 10.0, smax - 10.0, 3.0, Vector2(0.0, 1.0), 4)
	var le := row(east, Vector2(0.0, hw + 3.0), Vector2(1, 0), Vector2(0, -1), smin + 10.0, smax - 10.0, 3.0, Vector2(0.0, 1.0), 4)
	join_boardwalks(lw)
	join_boardwalks(le)
	add({"style": "church", "type": "church", "name": "Church", "sign": "ST. ANDREW'S", "w": 10.0, "d": 18.0, "porch": 3.6, "furnished": true, "role": "preacher", "raise": 0.5, "wall": "paint", "paint": Color(0.96, 0.95, 0.92)},
		Vector2(smax + 8.0, 0.0), Vector2(-1, 0), 3.6, true, 1.0, -100.0)
	add({"style": "school", "type": "school", "name": "School", "sign": "PUBLIC SCHOOL", "w": 8.0, "d": 11.0, "porch": 1.6, "furnished": true, "role": "teacher", "raise": 0.5, "wall": "paint", "paint": Color(0.92, 0.88, 0.75)},
		Vector2(-110.0 + 15.0, -60.0), Vector2(1, 0), 1.6, true, 1.0)
	_depot("PORT LINDEN", 0.0, true)
	for ss in [-110.0, -30.0, 50.0, 125.0]:
		houses_along(Vector2(ss, -hw - 30.0), Vector2(ss, -150.0), true, 10.0)
		houses_along(Vector2(ss, hw + 30.0), Vector2(ss, 150.0), true, 10.0)
	_waterfront()
	var entries := road_connectors(Vector2(smin, 0.0), Vector2(smax, 0.0))
	_sign_posts(entries)
	dress_main_street(smin + 10.0, smax - 10.0, hw, lw + le)

## Pier on Lake Agnes below the bluff east of town, with a boathouse and a stair down the bluff.
func _waterfront() -> void:
	# march east (world +x) from the centre to the first lake cell
	var shore := Vector3.INF
	for i in 300:
		var wx: float = t.x + i * 2.0
		if world.height(wx, t.z) < world.lake_level - 0.3:
			shore = Vector3(wx, world.lake_level, t.z)
			break
	if shore == Vector3.INF:
		return
	var p := to_town(shore.x - 6.0, shore.z)
	var east := to_town(t.x + 100.0, t.z) - to_town(t.x, t.z)
	east = east.normalized()
	var spec := {"style": "pier", "type": "pier", "w": 4.0, "d": 60.0, "length": 60.0, "floor_y": world.lake_level + 1.6, "ground_ref": false}
	add(spec, p, -east, 0.0, false)
	# stair from the bluff top down to the pier head
	var top_x := 0.0
	for i in 200:
		var wx: float = t.x + 150.0 + i * 2.0
		if world.height(wx, t.z) < float(t.y) - 0.6:
			top_x = wx - 4.0
			break
	if top_x > 0.0 and shore.x - top_x > 10.0:
		var path := []
		var n := int((shore.x - 6.0 - top_x) / 4.0)
		for i in n + 1:
			path.append([lerpf(top_x, shore.x - 6.0, float(i) / n), t.z + 2.5])
		var st := {"style": "bluff_stair", "type": "stair", "w": 2.2, "d": 1.0, "points": path, "ground_ref": false}
		_n += 1
		st["id"] = "%s/%02d_stair" % [t.id, _n]
		st["town"] = t.id
		st["xf"] = frame
		st["weather"] = weather
		st["town_pos"] = to_town(top_x, t.z)
		st["town_face"] = Vector2(0, -1)
		plan.specs.append(st)
		street(to_town(top_x, t.z + 2.5), to_town(top_x - 60.0, t.z + 2.5), 6.0)
	add({"style": "shed", "type": "boathouse", "w": 7.0, "d": 6.0, "h": 3.0, "wall": "planks_v", "roof": "corrugated", "raise": 0.1},
		p - east * 4.0 + Vector2(-east.y, east.x) * 10.0, east, 0.0, true, 0.5)

# ------------------------------------------------------------------------------------------------ points of interest

func _camp() -> void:
	weather = 0.45
	add({"style": "campfire", "type": "campfire", "w": 2.0, "d": 2.0, "raise": 0.0, "seats": 6}, Vector2.ZERO, Vector2(0, -1), 0.0, false)
	var tents := [Vector2(-9.0, -6.0), Vector2(-3.0, -11.0), Vector2(5.0, -10.5), Vector2(10.5, -4.0), Vector2(-11.0, 4.0)]
	for i in tents.size():
		var p: Vector2 = tents[i]
		add({"style": "tent", "type": "tent", "interior": "tent", "w": rng.randf_range(3.2, 4.2), "d": rng.randf_range(4.2, 5.2), "raise": 0.0,
			"paint": Color(0.93, 0.9, 0.82).lerp(Color(0.78, 0.72, 0.6), rng.randf())}, p, -p.normalized(), 0.0, true, 0.5)
	add({"style": "wagon", "type": "wagon", "w": 1.8, "d": 3.6, "covered": true, "raise": 0.0}, Vector2(8.0, 7.0), Vector2(1, -0.4), 0.0, true, 0.3)
	add({"style": "wagon", "type": "chuck_wagon", "w": 1.8, "d": 3.6, "covered": false, "raise": 0.0, "paint": Color(0.35, 0.42, 0.3)}, Vector2(-4.0, 9.0), Vector2(-1, 0.2), 0.0, true, 0.3)
	add({"style": "woodpile", "type": "woodpile", "w": 2.6, "d": 1.0, "raise": 0.0}, Vector2(1.0, 13.0), Vector2(0, -1), 0.0, true, 0.3)
	add({"style": "corral", "type": "picket_line", "w": 14.0, "d": 8.0, "raise": 0.0, "split_rail": true, "trough": true}, Vector2(18.0, 10.0), Vector2(-1, 0), 0.0, true, 0.5)
	street_kit([{"k": "crates", "x": 3.5, "z": 5.0}, {"k": "barrels", "x": -6.5, "z": 6.0}, {"k": "lamp", "x": 2.0, "z": -4.0, "h": 2.6},
		{"k": "bench", "x": -2.0, "z": 5.5}])

func _ranch() -> void:
	weather = 0.4
	add({"style": "house", "type": "ranch_house", "interior": "house", "name": "Halvorsen Ranch", "w": 11.0, "d": 9.0, "wall": "paint", "paint": Color(0.95, 0.93, 0.88), "trim": Color(0.25, 0.32, 0.26), "porch": 2.4, "raise": 0.6, "furnished": true, "roof_axis": "x"},
		Vector2(0.0, -18.0), Vector2(0, 1), 2.4, true, 1.0)
	add({"style": "barn", "type": "barn", "interior": "livery", "w": 13.0, "d": 18.0, "raise": 0.05, "wall": "paint", "paint": Color(0.6, 0.22, 0.16), "trim": Color(0.95, 0.94, 0.9), "furnished": true},
		Vector2(24.0, 6.0), Vector2(-1, 0), 0.0, true, 1.0)
	add({"style": "corral", "type": "corral", "w": 26.0, "d": 22.0, "raise": 0.0}, Vector2(-14.0, 16.0), Vector2(0, -1), 0.0, true, 1.0)
	add({"style": "cabin", "type": "bunkhouse", "interior": "boarding", "w": 9.0, "d": 5.5, "raise": 0.25, "porch": 1.8, "furnished": true}, Vector2(-26.0, -8.0), Vector2(1, 0), 1.8, true, 1.0)
	add({"style": "windmill", "type": "windmill", "w": 3.0, "d": 3.0, "raise": 0.0, "h": 9.5}, Vector2(8.0, -2.0), Vector2(0, 1), 0.0, true, 0.5)
	add({"style": "outhouse", "type": "outhouse", "w": 1.2, "d": 1.3, "raise": 0.0}, Vector2(12.0, -30.0), Vector2(0, 1), 0.0, true, 0.5)
	add({"style": "shed", "type": "shed", "w": 4.0, "d": 3.5, "raise": 0.1}, Vector2(-8.0, -32.0), Vector2(0, 1), 0.0, true, 0.5)
	add({"style": "woodpile", "type": "woodpile", "w": 3.0, "d": 1.0, "raise": 0.0}, Vector2(9.0, -28.0), Vector2(0, 1), 0.0, true, 0.3)
	add({"style": "wagon", "type": "wagon", "w": 1.8, "d": 3.6, "covered": false, "raise": 0.0}, Vector2(14.0, -12.0), Vector2(0.3, 1), 0.0, true, 0.3)
	street(Vector2(0.0, -12.0), Vector2(0.0, 40.0), 6.0)

func _homestead() -> void:
	weather = 0.5
	var big := rng.randf() < 0.5
	if big:
		add(house_spec("house"), Vector2(0.0, -6.0), Vector2(0, 1), 2.0, true, 1.0)
	else:
		var c := house_spec("cabin")
		c["porch"] = 1.6
		add(c, Vector2(0.0, -6.0), Vector2(0, 1), 1.6, true, 1.0)
	add({"style": "barn", "type": "barn", "interior": "livery", "w": 9.0, "d": 12.0, "raise": 0.05, "wall": "planks_v", "furnished": true, "h": 3.8}, Vector2(15.0, 6.0), Vector2(-1, 0), 0.0, true, 1.0)
	add({"style": "corral", "type": "corral", "w": 14.0, "d": 12.0, "raise": 0.0, "split_rail": true}, Vector2(-10.0, 10.0), Vector2(0, -1), 0.0, true, 1.0)
	add({"style": "outhouse", "type": "outhouse", "w": 1.2, "d": 1.3, "raise": 0.0}, Vector2(-8.0, -16.0), Vector2(0, 1), 0.0, true, 0.5)
	add({"style": "woodpile", "type": "woodpile", "w": 2.4, "d": 1.0, "raise": 0.0}, Vector2(6.0, -14.0), Vector2(0, 1), 0.0, true, 0.3)
	if str(t.id) == "windmill_flats" or rng.randf() < 0.5:
		add({"style": "windmill", "type": "windmill", "w": 3.0, "d": 3.0, "raise": 0.0, "h": 9.0}, Vector2(4.0, 16.0), Vector2(0, -1), 0.0, true, 0.5)

func _logging() -> void:
	weather = 0.55
	add({"style": "cabin", "type": "bunkhouse", "interior": "boarding", "w": 12.0, "d": 6.0, "raise": 0.3, "porch": 1.8, "furnished": true}, Vector2(-12.0, -18.0), Vector2(0, 1), 1.8, true, 1.0)
	add({"style": "cabin", "type": "cookhouse", "interior": "restaurant", "w": 8.0, "d": 6.5, "raise": 0.3, "porch": 0.0, "furnished": true}, Vector2(8.0, -20.0), Vector2(0, 1), 0.0, true, 1.0)
	add({"style": "sawmill", "type": "sawmill", "w": 10.0, "d": 8.0, "raise": 0.0}, Vector2(18.0, 12.0), Vector2(-1, 0), 0.0, true, 1.0)
	for i in 3:
		add({"style": "logpile", "type": "logpile", "w": 4.5, "d": 7.0, "raise": 0.0}, Vector2(-14.0 + i * 7.0, 14.0), Vector2(0, -1), 0.0, true, 0.5)
	for i in 3:
		add(house_spec("tent"), Vector2(-28.0, -4.0 + i * 7.0), Vector2(1, 0), 0.0, true, 0.5)
	add({"style": "wagon", "type": "wagon", "w": 1.8, "d": 3.6, "covered": false, "raise": 0.0}, Vector2(0.0, 30.0), Vector2(0, -1), 0.0, true, 0.3)
	add({"style": "campfire", "type": "campfire", "w": 2.0, "d": 2.0, "raise": 0.0, "seats": 4}, Vector2(-2.0, -4.0), Vector2(0, -1), 0.0, true, 0.5)
	add({"style": "woodpile", "type": "woodpile", "w": 3.0, "d": 1.0, "raise": 0.0}, Vector2(2.0, -30.0), Vector2(0, 1), 0.0, true, 0.3)

func _ruin() -> void:
	weather = 0.8
	add({"style": "mission_ruin", "type": "mission_ruin", "name": "San Lazaro", "w": 11.0, "d": 26.0, "raise": 0.1, "ground_ref": true}, Vector2(0.0, -12.0), Vector2(0, -1), 0.0, false)
	add({"style": "well", "type": "well", "w": 2.0, "d": 2.0, "raise": 0.0}, Vector2(-16.0, -26.0), Vector2(0, 1), 0.0, true, 0.5)
	street_kit([])

func _trading_post() -> void:
	weather = 0.45
	add({"style": "cabin", "type": "trading_post", "interior": "store", "name": "Greer's Trading Post", "w": 11.0, "d": 8.0, "raise": 0.35, "porch": 2.4, "furnished": true, "role": "storekeeper", "roof": "shingles", "sign": "GREER'S TRADING POST"},
		Vector2(0.0, -6.0), Vector2(0, 1), 2.4, true, 1.0)
	add({"style": "corral", "type": "corral", "w": 16.0, "d": 12.0, "raise": 0.0, "split_rail": true}, Vector2(16.0, 8.0), Vector2(0, -1), 0.0, true, 1.0)
	add({"style": "shed", "type": "shed", "w": 4.0, "d": 3.5, "raise": 0.1}, Vector2(-12.0, -10.0), Vector2(1, 0), 0.0, true, 0.5)
	add({"style": "wagon", "type": "wagon", "w": 1.8, "d": 3.6, "covered": true, "raise": 0.0}, Vector2(-8.0, 8.0), Vector2(1, 0.2), 0.0, true, 0.3)
	street_kit([{"k": "hitch", "x": -2.5, "z": 0.0, "len": 3.0}, {"k": "trough", "x": 3.0, "z": 0.2}, {"k": "barrels", "x": 5.6, "z": -3.6},
		{"k": "crates", "x": -5.4, "z": -3.4}])

func _trapper() -> void:
	weather = 0.65
	var c := house_spec("cabin")
	c["w"] = 5.0
	c["d"] = 4.2
	add(c, Vector2(0.0, -2.0), Vector2(0, 1), 0.0, true, 0.5)
	add({"style": "shed", "type": "lean_to", "w": 3.0, "d": 2.5, "raise": 0.0, "wall": "log", "roof": "roof_planks"}, Vector2(6.0, -1.0), Vector2(0, 1), 0.0, true, 0.3)
	add({"style": "woodpile", "type": "woodpile", "w": 2.4, "d": 1.0, "raise": 0.0}, Vector2(-5.5, 1.5), Vector2(0, 1), 0.0, true, 0.3)
