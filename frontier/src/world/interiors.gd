class_name BuildingInteriors
extends BuildingStyles
## Furnishing: every enterable building gets a fitting interior — counters, bars, shelves full of goods, beds,
## stoves, cells, pews — built procedurally into the `inn` kit plus Poly Haven CC0 props via MultiMesh lists,
## warm interior lights and interaction spots for town life (bartender, bar patrons, shopkeeper, chairs with sit
## heights, beds, work spots, cell bunks...). Prop yaw: 0 = the model's front faces local +z.

const GOODS := [Color(0.55, 0.12, 0.08), Color(0.8, 0.68, 0.38), Color(0.12, 0.2, 0.42), Color(0.18, 0.32, 0.16),
	Color(0.75, 0.45, 0.12), Color(0.85, 0.82, 0.72), Color(0.38, 0.22, 0.12), Color(0.6, 0.15, 0.25), Color(0.1, 0.1, 0.1)]
const BOTTLES := [Color(0.12, 0.22, 0.12), Color(0.3, 0.18, 0.08), Color(0.1, 0.12, 0.1), Color(0.55, 0.42, 0.2), Color(0.75, 0.8, 0.78)]

func furnish() -> void:
	var t: String = spec.get("interior", spec.get("type", ""))
	if has_method("_f_" + t):
		call("_f_" + t)
	elif rec.rooms.size() > 0:
		_f_generic()
	_room_lights()
	_probe()

## One interior reflection probe per furnished building: box-projected room reflections (bar mirror, floors,
## bottles) and an interior ambient instead of open-sky light.
func _probe() -> void:
	if not furnished or rec.rooms.is_empty() or spec.get("style", "") in ["tent", "smithy", "barn", "outhouse", "shed"]:
		return
	var lo := Vector3(INF, 0.0, INF)
	var hi := Vector3(-INF, 0.0, -INF)
	for r in rec.rooms:
		var rc: Rect2 = r.rect
		lo = Vector3(minf(lo.x, rc.position.x), 0.0, minf(lo.z, rc.position.y))
		hi = Vector3(maxf(hi.x, rc.end.x), maxf(hi.y, r.y + 3.4), maxf(hi.z, rc.end.y))
	if hi.x <= lo.x:
		return
	rec["probe"] = {"center": (lo + hi) * 0.5, "size": hi - lo + Vector3(0.2, 0.2, 0.2)}

func R(name: String) -> Dictionary:
	for r in rec.rooms:
		if r.name == name:
			return r
	return rec.rooms[0] if rec.rooms.size() > 0 else {"rect": Rect2(-1, 1, 2, 2), "y": 0.0}

func _room_lights() -> void:
	for r in rec.rooms:
		var rc: Rect2 = r.rect
		var h := 2.6 if r.y > 0.0 or spec.get("style", "") in ["house", "cabin", "adobe"] else 3.0
		if spec.get("style", "") == "tent":
			h = 1.9
		var area := rc.size.x * rc.size.y
		if area < 2.0:
			continue
		var c := Vector3(rc.position.x + rc.size.x * 0.5, r.y + h, rc.position.y + rc.size.y * 0.5)
		light(c, "interior", clampf(sqrt(area) * 1.6, 5.0, 14.0), 1.1 if area > 30.0 else 0.8)

# ------------------------------------------------------------------------------------------------ furniture pieces

func counter(x0: float, z0: float, x1: float, z1: float, h := 1.05, front := "fine_wood", top := "fine_wood") -> void:
	if front == "dark_planks":
		front = "fine_wood"
	paint(Color(0.62, 0.45, 0.32), inn)
	inn.box(front, Vector3(x0, 0.08, z0), Vector3(x1, h - 0.05, z1), MeshKit.F_SIDES)
	inn.box(front, Vector3(x0 + 0.04, 0.0, z0 + 0.04), Vector3(x1 - 0.04, 0.1, z1 - 0.04), MeshKit.F_SIDES)
	inn.box(top, Vector3(x0 - 0.05, h - 0.05, z0 - 0.05), Vector3(x1 + 0.05, h, z1 + 0.05))
	# raised panels on the long faces
	var long_x := (x1 - x0) > (z1 - z0)
	var L := (x1 - x0) if long_x else (z1 - z0)
	var n := maxi(1, int(L / 0.9))
	for i in n:
		var a := (i + 0.12) / n
		var b := (i + 0.88) / n
		if long_x:
			inn.box(front, Vector3(lerpf(x0, x1, a), 0.25, z0 - 0.015), Vector3(lerpf(x0, x1, b), h - 0.2, z0), MeshKit.F_NZ)
			inn.box(front, Vector3(lerpf(x0, x1, a), 0.25, z1), Vector3(lerpf(x0, x1, b), h - 0.2, z1 + 0.015), MeshKit.F_PZ)
		else:
			inn.box(front, Vector3(x0 - 0.015, 0.25, lerpf(z0, z1, a)), Vector3(x0, h - 0.2, lerpf(z0, z1, b)), MeshKit.F_NX)
			inn.box(front, Vector3(x1, 0.25, lerpf(z0, z1, a)), Vector3(x1 + 0.015, h - 0.2, lerpf(z0, z1, b)), MeshKit.F_PX)
	paint(col_wall, inn)
	solid(Vector3(x0, 0.0, z0), Vector3(x1, h, z1))

## Shelving against a wall: x0..x1 along x at z (depth towards +z if dir > 0) or along z when along_z.
func shelves(a0: float, a1: float, wall: float, depth: float, h: float, n: int, along_z := false, dir := 1.0, goods := true, y0 := 0.0) -> void:
	paint(Color(0.55, 0.4, 0.3), inn)
	var key := "fine_wood"
	var b0 := wall
	var b1 := wall + depth * dir
	var lo := minf(b0, b1)
	var hi := maxf(b0, b1)
	var pts := []
	for i in n + 1:
		pts.append(y0 + 0.1 + (h - 0.2) * float(i) / n)
	for y in pts:
		if along_z:
			inn.box(key, Vector3(lo, y, a0), Vector3(hi, y + 0.03, a1))
		else:
			inn.box(key, Vector3(a0, y, lo), Vector3(a1, y + 0.03, hi))
	var nu := maxi(2, int((a1 - a0) / 1.2) + 1)
	for i in nu:
		var a := lerpf(a0, a1 - 0.04, float(i) / (nu - 1))
		if along_z:
			inn.box(key, Vector3(lo, y0, a), Vector3(hi, y0 + h, a + 0.04))
		else:
			inn.box(key, Vector3(a, y0, lo), Vector3(a + 0.04, y0 + h, hi))
	if along_z:
		solid(Vector3(lo, y0, a0), Vector3(hi, y0 + h, a1))
	else:
		solid(Vector3(a0, y0, lo), Vector3(a1, y0 + h, hi))
	if not goods:
		paint(col_wall, inn)
		return
	# goods: tins, boxes, jars, bolts of cloth
	for k in pts.size() - 1:
		var y: float = pts[k] + 0.03
		var top: float = pts[k + 1]
		var a := a0 + 0.08
		while a < a1 - 0.12:
			var kind := rng.randi() % 5
			var gw := rng.randf_range(0.08, 0.3)
			var gh := minf(rng.randf_range(0.1, 0.32), top - y - 0.04)
			var gd := depth * rng.randf_range(0.5, 0.85)
			var c: Color = GOODS[rng.randi() % GOODS.size()]
			if rng.randf() < 0.18:
				a += gw
				continue
			var mid := (lo + hi) * 0.5
			if kind == 0:
				# a row of labelled tins (one box: label band + tin ends)
				var cnt := int(gw / 0.08) + 1
				gw = cnt * 0.08
				var th := minf(0.12, gh)
				inn.tint = Color(c.r, c.g, c.b, 0.1)
				if along_z:
					inn.box("cloth", Vector3(mid - 0.035, y, a), Vector3(mid + 0.035, y + th, a + gw), MeshKit.F_ALL & ~MeshKit.F_NY)
				else:
					inn.box("cloth", Vector3(a, y, mid - 0.035), Vector3(a + gw, y + th, mid + 0.035), MeshKit.F_ALL & ~MeshKit.F_NY)
			elif kind == 1:
				inn.tint = Color(BOTTLES[rng.randi() % BOTTLES.size()], 1.0)
				var cnt2 := int(gw / 0.09) + 1
				for j in cnt2:
					var pa2 := a + 0.045 + j * 0.09
					var p2 := Vector3(mid, y, pa2) if along_z else Vector3(pa2, y, mid)
					inn.cyl("bottle", p2, p2 + Vector3(0, minf(0.16, gh), 0), 0.04, 5, false)
				gw = cnt2 * 0.09
			else:
				inn.tint = Color(c.r, c.g, c.b, 0.2)
				if along_z:
					inn.box("cloth", Vector3(mid - gd * 0.5, y, a), Vector3(mid + gd * 0.5, y + gh, a + gw), MeshKit.F_ALL & ~MeshKit.F_NY)
				else:
					inn.box("cloth", Vector3(a, y, mid - gd * 0.5), Vector3(a + gw, y + gh, mid + gd * 0.5), MeshKit.F_ALL & ~MeshKit.F_NY)
			a += gw + rng.randf_range(0.01, 0.06)
	paint(col_wall, inn)

## Glass-topped display case (store, gunsmith): stained wood base, glass lid with goods visible inside.
func display_case(x0: float, z0: float, x1: float, z1: float, h := 0.95) -> void:
	paint(Color(0.55, 0.38, 0.26), inn)
	inn.box("fine_wood", Vector3(x0, 0.0, z0), Vector3(x1, h - 0.3, z1))
	for c: Vector2 in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]:
		inn.box("fine_wood", Vector3(c.x - 0.03, h - 0.3, c.y - 0.03), Vector3(c.x + 0.03, h, c.y + 0.03))
	inn.box("fine_wood", Vector3(x0 - 0.02, h, z0 - 0.02), Vector3(x1 + 0.02, h + 0.03, z1 + 0.02), MeshKit.F_SIDES)
	var zz := z0 + 0.12
	while zz < z1 - 0.15:
		inn.tint = Color(GOODS[rng.randi() % GOODS.size()], 0.1)
		inn.box("cloth", Vector3(x0 + 0.1, h - 0.3, zz), Vector3(x1 - 0.1, h - 0.25, zz + rng.randf_range(0.08, 0.2)), MeshKit.F_PY | MeshKit.F_SIDES)
		zz += rng.randf_range(0.15, 0.3)
	inn.tint = Color(1.0, 0.5, 1.0, 1.0)
	inn.box("glass", Vector3(x0, h - 0.3, z0), Vector3(x1, h, z1), MeshKit.F_PY | MeshKit.F_SIDES)
	paint(col_wall, inn)
	solid(Vector3(x0, 0.0, z0), Vector3(x1, h, z1))

## Pedestal desk with drawer fronts and brass pulls (sheriff, bank, doctor, editor).
func desk(cx: float, cz: float, yaw := 0.0, y := 0.0) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var c := Vector3(cx, y, cz)
	paint(Color(0.5, 0.34, 0.22), inn)
	inn.obox("fine_wood", c + b * Vector3(0, 0.75, 0), Vector3(1.5, 0.04, 0.75), b)
	for sx: float in [-0.52, 0.52]:
		inn.obox("fine_wood", c + b * Vector3(sx, 0.365, 0), Vector3(0.42, 0.73, 0.7), b)
		for k in 3:
			inn.obox("fine_wood", c + b * Vector3(sx, 0.15 + k * 0.22, 0.355), Vector3(0.36, 0.18, 0.015), b)
			inn.tint = Color(1, 1, 1, 0.1)
			inn.obox("brass", c + b * Vector3(sx, 0.15 + k * 0.22, 0.37), Vector3(0.08, 0.02, 0.02), b)
			paint(Color(0.5, 0.34, 0.22), inn)
	paint(col_wall, inn)
	var lo := c + b * Vector3(-0.75, 0, -0.38)
	var hi := c + b * Vector3(0.75, 0.77, 0.38)
	solid(Vector3(minf(lo.x, hi.x), y, minf(lo.z, hi.z)), Vector3(maxf(lo.x, hi.x), y + 0.77, maxf(lo.z, hi.z)))

func table_chairs(cx: float, cz: float, y := 0.0, round_table := true, n := 4, game := false, chair := "painted_wooden_chair_01@stain") -> void:
	if round_table:
		prop("round_wooden_table_01", Vector3(cx, y, cz), rng.randf() * 90.0, 0.75)
		solid(Vector3(cx - 0.45, y, cz - 0.45), Vector3(cx + 0.45, y + 0.76, cz + 0.45))
	else:
		prop("WoodenTable_03", Vector3(cx, y, cz), 0.0, 1.0)
		solid(Vector3(cx - 0.66, y, cz - 0.28), Vector3(cx + 0.66, y + 0.8, cz + 0.28))
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.25, 0.25)
		var r := 0.85 if round_table else 0.75
		var p := Vector3(cx + sin(a) * r, y, cz + cos(a) * r)
		var face := Vector3(cx - p.x, 0.0, cz - p.z)
		prop(chair, p, rad_to_deg(atan2(face.x, face.z)) + rng.randf_range(-12, 12))
		spot("chair", p, face, {"sit_height": 0.46, "table": Vector3(cx, y, cz), "cards": game})
	if game:
		inn.tint = Color(0.15, 0.32, 0.18, 0.1)
		inn.cyl("cloth", Vector3(cx, y + 0.76, cz), Vector3(cx, y + 0.765, cz), 0.5, 14, true)
		paint(col_wall, inn)

func bed(x: float, z: float, y := 0.0, yaw := 0.0) -> void:
	prop("old_bed_frame", Vector3(x, y, z), yaw)
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var c := Vector3(x, y, z)
	# mattress, blanket and pillow inside the frame
	inn.tint = Color(0.9, 0.88, 0.82, 0.1)
	inn.obox("cloth", c + b * Vector3(0, 0.5, 0.05), Vector3(0.8, 0.14, 1.85), b)
	var bl: Color = rand_pick([Color(0.55, 0.15, 0.12), Color(0.25, 0.3, 0.45), Color(0.45, 0.4, 0.3), Color(0.3, 0.38, 0.28)])
	inn.tint = Color(bl.r, bl.g, bl.b, 0.1)
	inn.obox("cloth", c + b * Vector3(0, 0.585, 0.3), Vector3(0.86, 0.04, 1.3), b)
	inn.tint = Color(0.95, 0.94, 0.9, 0.1)
	inn.obox("cloth", c + b * Vector3(0, 0.62, -0.72), Vector3(0.6, 0.1, 0.3), b)
	paint(col_wall, inn)
	var lo := c + b * Vector3(-0.45, 0, -1.0)
	var hi := c + b * Vector3(0.45, 0.6, 1.0)
	solid(Vector3(minf(lo.x, hi.x), y, minf(lo.z, hi.z)), Vector3(maxf(lo.x, hi.x), y + 0.6, maxf(lo.z, hi.z)))
	spot("bed", c + b * Vector3(0, 0.0, 0.0), b * Vector3(0, 0, 1), {"lie_height": 0.62, "head": c + b * Vector3(0, 0.62, -0.75)})

func stove(x: float, z: float, y := 0.0, top_y := 3.0) -> void:
	inn.tint = Color(1, 1, 1, 0.2)
	inn.box("iron", Vector3(x - 0.35, y + 0.2, z - 0.28), Vector3(x + 0.35, y + 0.75, z + 0.28))
	for c: Vector2 in [Vector2(-0.3, -0.23), Vector2(0.3, -0.23), Vector2(0.3, 0.23), Vector2(-0.3, 0.23)]:
		inn.box("iron", Vector3(x + c.x - 0.03, y, z + c.y - 0.03), Vector3(x + c.x + 0.03, y + 0.2, z + c.y + 0.03), MeshKit.F_SIDES)
	inn.cyl("iron", Vector3(x, y + 0.75, z + 0.1), Vector3(x, top_y, z + 0.1), 0.08, 8, false)
	paint(col_wall, inn)
	solid(Vector3(x - 0.35, y, z - 0.28), Vector3(x + 0.35, y + 0.75, z + 0.28))
	light(Vector3(x, y + 0.5, z - 0.4), "stove", 3.0, 0.35, Color(1.0, 0.45, 0.15))

func rug(x0: float, z0: float, x1: float, z1: float, y := 0.0) -> void:
	paint(rand_pick([Color(0.9, 0.5, 0.4), Color(0.6, 0.7, 0.9), Color(0.9, 0.8, 0.6)]), inn)
	inn.box("carpet", Vector3(x0, y, z0), Vector3(x1, y + 0.012, z1), MeshKit.F_PY)
	paint(col_wall, inn)

func picture(x: float, y: float, z: float, yaw: float) -> void:
	prop("hanging_picture_frame_01", Vector3(x, y, z), yaw)

func piano(x: float, z: float, yaw: float, y := 0.0) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var c := Vector3(x, y, z)
	paint(Color(0.55, 0.4, 0.32), inn)
	inn.obox("fine_wood", c + b * Vector3(0, 0.65, 0), Vector3(1.5, 1.3, 0.55), b)
	inn.obox("fine_wood", c + b * Vector3(0, 0.72, 0.38), Vector3(1.4, 0.06, 0.25), b)
	inn.tint = Color(0.95, 0.93, 0.88, 0.0)
	inn.obox("cloth", c + b * Vector3(0, 0.755, 0.36), Vector3(1.22, 0.015, 0.16), b)
	inn.tint = Color(0.05, 0.05, 0.05, 0.0)
	for i in 21:
		inn.obox("cloth", c + b * Vector3(-0.58 + i * 0.058, 0.768, 0.33), Vector3(0.02, 0.012, 0.09), b)
	paint(col_wall, inn)
	prop("wooden_stool_01", c + b * Vector3(0, 0, 0.85), yaw)
	solid(c + b * Vector3(-0.75, 0, -0.3) * Vector3(1, 1, 1) + Vector3(0, 0, 0), c + b * Vector3(0.75, 1.3, 0.3))
	spot("piano", c + b * Vector3(0, 0, 0.85), b * Vector3(0, 0, -1), {"sit_height": 0.44})

func bars_wall(a: Vector3, b: Vector3, h := 2.4, spacing := 0.13) -> void:
	inn.tint = Color(1, 1, 1, 0.2)
	var L := a.distance_to(b)
	var n := int(L / spacing)
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		inn.box("iron", p + Vector3(-0.012, 0, -0.012), p + Vector3(0.012, h, 0.012), MeshKit.F_SIDES)
	inn.beam("iron", a + Vector3(0, h - 0.05, 0), b + Vector3(0, h - 0.05, 0), 0.06, 0.05)
	inn.beam("iron", a + Vector3(0, 1.1, 0), b + Vector3(0, 1.1, 0), 0.05, 0.03)
	inn.beam("iron", a + Vector3(0, 0.05, 0), b + Vector3(0, 0.05, 0), 0.06, 0.05)
	paint(col_wall, inn)
	var lo := Vector3(minf(a.x, b.x) - 0.03, 0.0, minf(a.z, b.z) - 0.03)
	var hi := Vector3(maxf(a.x, b.x) + 0.03, h, maxf(a.z, b.z) + 0.03)
	solid(lo, hi)

func bench(x0: float, x1: float, z: float, y := 0.0, back := true, along_z := false) -> void:
	paint(Color(0.75, 0.65, 0.55), inn)
	if along_z:
		inn.box("fine_wood", Vector3(z - 0.22, y + 0.42, x0), Vector3(z + 0.22, y + 0.46, x1))
		inn.box("fine_wood", Vector3(z - 0.2, y, x0 + 0.1), Vector3(z + 0.2, y + 0.42, x0 + 0.15))
		inn.box("fine_wood", Vector3(z - 0.2, y, x1 - 0.15), Vector3(z + 0.2, y + 0.42, x1 - 0.1))
		if back:
			inn.box("fine_wood", Vector3(z + 0.2, y + 0.46, x0), Vector3(z + 0.24, y + 0.95, x1))
		solid(Vector3(z - 0.22, y, x0), Vector3(z + 0.22, y + 0.46, x1))
	else:
		inn.box("fine_wood", Vector3(x0, y + 0.42, z - 0.22), Vector3(x1, y + 0.46, z + 0.22))
		inn.box("fine_wood", Vector3(x0 + 0.1, y, z - 0.2), Vector3(x0 + 0.15, y + 0.42, z + 0.2))
		inn.box("fine_wood", Vector3(x1 - 0.15, y, z - 0.2), Vector3(x1 - 0.1, y + 0.42, z + 0.2))
		if back:
			inn.box("fine_wood", Vector3(x0, y + 0.46, z + 0.2), Vector3(x1, y + 0.95, z + 0.24))
		solid(Vector3(x0, y, z - 0.22), Vector3(x1, y + 0.46, z + 0.22))
	paint(col_wall, inn)
	var n := int((x1 - x0) / 0.65)
	for i in n:
		var a := x0 + 0.35 + i * 0.65
		if along_z:
			spot("bench", Vector3(z, y, a), Vector3(-1, 0, 0), {"sit_height": 0.45})
		else:
			spot("bench", Vector3(a, y, z), Vector3(0, 0, -1), {"sit_height": 0.45})

func crates_pile(x: float, z: float, y := 0.0, n := 4) -> void:
	for i in n:
		var pick: String = rand_pick(["wooden_crate_01", "wooden_crate_02", "barrel_03", "wooden_military_crate", "wine_barrel_01"])
		var p := Vector3(x + rng.randf_range(-0.8, 0.8), y, z + rng.randf_range(-0.6, 0.6))
		prop(pick, p, rng.randf() * 360.0)
	solid(Vector3(x - 0.9, y, z - 0.7), Vector3(x + 0.9, y + 0.6, z + 0.7))

func sacks(x: float, z: float, y := 0.0, n := 4) -> void:
	for i in n:
		inn.tint = Color(0.82, 0.74, 0.58, 0.3)
		var p := Vector3(x + (i % 2) * 0.55 - 0.27, y + 0.18 + (i / 2) * 0.32, z + rng.randf_range(-0.05, 0.05))
		inn.obox("canvas", p, Vector3(0.48, 0.32, 0.7), Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)))
	paint(col_wall, inn)

func hay(x: float, z: float, y := 0.0, n := 3, k: MeshKit = null) -> void:
	if k == null:
		k = inn
	k.tint = Color(1.15, 1.0, 0.65, 0.2)
	for i in n:
		var p := Vector3(x + (i % 3) * 0.95, y + 0.25 + (i / 3) * 0.5, z + rng.randf_range(-0.05, 0.05))
		k.obox("thatch", p, Vector3(0.9, 0.5, 0.48), Basis(Vector3.UP, rng.randf_range(-0.1, 0.1)))
	paint(col_wall, k)
	solid(Vector3(x - 0.45, y, z - 0.3), Vector3(x + (mini(n, 3) - 1) * 0.95 + 0.45, y + 0.5 * ceil(n / 3.0), z + 0.3))

func wanted_board(x: float, y: float, z: float, yaw: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var c := Vector3(x, y, z)
	paint(Color(0.55, 0.42, 0.3), inn)
	inn.obox("planks_brown", c, Vector3(1.4, 1.0, 0.03), b)
	var names := ["WANTED", "REWARD", "WANTED", "NOTICE"]
	for i in 4:
		var o := Vector3(-0.45 + (i % 2) * 0.62, 0.22 - (i / 2) * 0.47, 0.02)
		inn.tint = Color(0.9, 0.85, 0.7, 0.4)
		inn.obox("cloth", c + b * o, Vector3(0.38, 0.4, 0.005), b)
		var tc := c + b * (o + Vector3(0, 0.12, 0.004))
		text(inn, names[i], tc, b * Vector3(1, 0, 0), b * Vector3(0, 0, 1), 0.06, 0.32, Color(0.12, 0.1, 0.08), "OldStandard-Bold")
		inn.tint = Color(0.35, 0.3, 0.25, 0.4)
		inn.obox("cloth", c + b * (o + Vector3(0, -0.04, 0.004)), Vector3(0.16, 0.16, 0.002), b)
	paint(col_wall, inn)

func gun_rack(x: float, y: float, z: float, yaw: float, n := 5) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var c := Vector3(x, y, z)
	paint(Color(0.6, 0.45, 0.3), inn)
	inn.obox("fine_wood", c + b * Vector3(0, 0.1, 0.05), Vector3(n * 0.18 + 0.2, 0.06, 0.12), b)
	inn.obox("fine_wood", c + b * Vector3(0, 1.0, 0.05), Vector3(n * 0.18 + 0.2, 0.06, 0.1), b)
	for i in n:
		var ox := -n * 0.09 + 0.09 + i * 0.18
		inn.tint = Color(0.5, 0.33, 0.2, 0.2)
		inn.obox("fine_wood", c + b * Vector3(ox, 0.35, 0.06), Vector3(0.045, 0.5, 0.06), b)
		inn.tint = Color(1, 1, 1, 0.2)
		inn.obox("iron", c + b * Vector3(ox, 0.92, 0.06), Vector3(0.022, 0.75, 0.022), b)
	paint(col_wall, inn)

func coffin(x: float, z: float, y: float, yaw: float, open := false) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var c := Vector3(x, y, z)
	paint(Color(0.7, 0.55, 0.42), inn)
	var pts := [Vector2(-0.22, -0.95), Vector2(0.22, -0.95), Vector2(0.32, -0.45), Vector2(0.2, 0.95), Vector2(-0.2, 0.95), Vector2(-0.32, -0.45)]
	var hgt := 0.42
	for i in pts.size():
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % pts.size()]
		var a0 := c + b * Vector3(p0.x, 0, p0.y)
		var a1 := c + b * Vector3(p1.x, 0, p1.y)
		inn.quad("fine_wood", a1, a0, a0 + Vector3(0, hgt, 0), a1 + Vector3(0, hgt, 0))
	if not open:
		for i in range(1, pts.size() - 1):
			inn.tri("fine_wood", c + b * Vector3(pts[0].x, hgt, pts[0].y), c + b * Vector3(pts[i + 1].x, hgt, pts[i + 1].y), c + b * Vector3(pts[i].x, hgt, pts[i].y))
	paint(col_wall, inn)

# ------------------------------------------------------------------------------------------------ rooms by type

func _f_saloon() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	# bar along the left wall, back bar with mirror and bottles
	var bx := x0 + 1.95
	var bz0 := z0 + 2.2
	var bz1 := minf(z1 - 1.5, bz0 + 7.5)
	counter(bx - 0.3, bz0, bx + 0.3, bz1, 1.1, "dark_planks", "fine_wood")
	paint(Color(1, 1, 1, 0.1), inn)
	inn.box("brass", Vector3(bx + 0.42, 0.15, bz0), Vector3(bx + 0.46, 0.19, bz1))        # foot rail
	shelves(bz0, bz1, x0, 0.4, 1.0, 1, true, 1.0, false, 0.0)
	paint(Color(0.85, 0.72, 0.6), inn)
	inn.box("dark_planks", Vector3(x0, 1.0, bz0), Vector3(x0 + 0.42, 1.05, bz1))
	inn.box("mirror", Vector3(x0 + 0.01, 1.3, bz0 + 0.6), Vector3(x0 + 0.03, 2.4, bz1 - 0.6), MeshKit.F_PX)
	inn.box("fine_wood", Vector3(x0, 1.2, bz0 + 0.45), Vector3(x0 + 0.06, 2.55, bz0 + 0.6))
	inn.box("fine_wood", Vector3(x0, 1.2, bz1 - 0.6), Vector3(x0 + 0.06, 2.55, bz1 - 0.45))
	inn.box("fine_wood", Vector3(x0, 2.4, bz0 + 0.45), Vector3(x0 + 0.1, 2.6, bz1 - 0.45))
	paint(col_wall, inn)
	# bottles on the back bar
	var zz := bz0 + 0.15
	while zz < bz1 - 0.15:
		inn.tint = Color(BOTTLES[rng.randi() % BOTTLES.size()], 1.0)
		var hh := rng.randf_range(0.24, 0.32)
		inn.cyl("bottle", Vector3(x0 + 0.2, 1.05, zz), Vector3(x0 + 0.2, 1.05 + hh, zz), 0.04, 6, true)
		inn.cyl("bottle", Vector3(x0 + 0.2, 1.05 + hh, zz), Vector3(x0 + 0.2, 1.05 + hh + 0.09, zz), 0.014, 5, true)
		zz += rng.randf_range(0.09, 0.2)
	paint(col_wall, inn)
	prop("wine_barrel_01", Vector3(x0 + 0.45, 0.0, bz1 + 0.6), 90.0)
	prop("barrel_03", Vector3(x0 + 0.4, 0.0, bz0 - 0.5), 0.0)
	prop("jug_01", Vector3(bx, 1.1, bz0 + 1.2), 30.0)
	prop("vintage_oil_lamp", Vector3(bx, 1.1, (bz0 + bz1) * 0.5), 0.0)
	for i in 5:
		var pz := lerpf(bz0 + 0.6, bz1 - 0.6, i / 4.0)
		spot("bar_patron", Vector3(bx + 0.75, 0.0, pz), Vector3(-1, 0, 0), {"lean": true})
		prop("wooden_stool_01", Vector3(bx + 0.62, 0.0, pz), 0.0, 1.6)
	spot("bartender", Vector3(x0 + 0.85, 0.0, (bz0 + bz1) * 0.5), Vector3(1, 0, 0), {"work": "bar"})
	spot("bartender", Vector3(x0 + 0.85, 0.0, bz0 + 1.0), Vector3(1, 0, 0), {"work": "bar"})
	# tables (one card table with green baize), piano in the back corner
	var tx0 := bx + 2.2
	var tx1 := x1 - 1.6
	var rows := clampi(int((z1 - z0 - 6.0) / 3.2), 1, 3)
	var cols := clampi(int((tx1 - tx0) / 3.0) + 1, 1, 3)
	for i in rows:
		for j in cols:
			var tz := z0 + 3.0 + i * 3.2 + rng.randf_range(-0.3, 0.3)
			var tx := lerpf(tx0, tx1, float(j) / maxf(cols - 1, 1)) if cols > 1 else (tx0 + tx1) * 0.5
			tx += rng.randf_range(-0.3, 0.3)
			if tz > z1 - 3.4 and tx > x1 - 3.5:
				continue
			table_chairs(tx, tz, 0.0, true, 3 + (i + j) % 2, i == 0 and j == cols - 1)
	# spittoons along the foot rail
	for i in 3:
		prop("pot_enamel_01@dark", Vector3(bx + 0.55, 0.0, lerpf(bz0 + 1.0, bz1 - 1.0, i / 2.0)), rng.randf() * 360.0, 0.9)
	piano(x1 - 1.0, z1 - 0.6, 180.0)
	prop("lantern_chandelier_01", Vector3((x0 + x1) * 0.5 + 0.6, 3.5, (z0 + z1) * 0.45), 0.0)
	prop("bull_head", Vector3(x1 - 0.05, 2.4, (z0 + z1) * 0.5), -90.0)
	picture(x1 - 0.03, 2.0, z0 + 2.0, -90.0)
	picture(x1 - 0.03, 2.0, z1 - 3.0, -90.0)
	prop("vintage_grandfather_clock_01", Vector3(x0 + 0.4, 0.0, z1 - 0.5), 90.0)
	light(Vector3((x0 + x1) * 0.5 + 0.6, 3.0, (z0 + z1) * 0.45), "interior", 9.0, 1.4)
	light(Vector3(bx - 0.6, 2.6, (bz0 + bz1) * 0.5), "interior", 6.0, 0.9)
	spot("stand", Vector3((x0 + x1) * 0.5, 0.0, z0 + 1.5), Vector3(0, 0, 1))
	_upper_rooms(true)

## Upper floor of a two-storey building: corridor along the stairwell side and rooms with beds.
func _upper_rooms(saloon := false) -> void:
	var u := R("upper")
	if u.y <= 0.0:
		return
	var rc: Rect2 = u.rect
	var y: float = u.y
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	var cor_x := x1 - 1.4           # corridor next to the stairwell
	var n := maxi(2, int((z1 - z0 - 1.0) / 3.2))
	var H2 := UPPER
	inner_partition_z(cor_x - 0.1, z0 + 1.2, z1, y, y + H2 - 0.05, -1.0, 0.0)
	var rl := (z1 - (z0 + 1.2)) / n
	for i in n:
		var ra := z0 + 1.2 + rl * i
		var rb := ra + rl
		if i > 0:
			_partition_x_simple(ra, x0, cor_x - 0.1, y, y + H2 - 0.05)
		# doorway into the corridor
		_cut_door_z(cor_x - 0.1, ra + rl * 0.5, y)
		bed(x0 + 0.6, (ra + rb) * 0.5, y, 90.0)
		prop("ClassicNightstand_01", Vector3(x0 + 0.35, y, rb - 0.45), 90.0)
		prop("vintage_oil_lamp", Vector3(x0 + 0.35, y + 0.7, rb - 0.45), 0.0, 0.6)
		if rng.randf() < 0.6:
			prop("painted_wooden_chair_01", Vector3(cor_x - 0.9, y, ra + 0.5), -120.0)
		room("room%d" % i, x0, ra, cor_x - 0.1, rb, y)
	# front room over the balcony door
	rug(x0 + 0.5, z0 + 0.2, cor_x - 0.6, z0 + 1.0, y)
	spot("balcony_door", Vector3(0.0, y, z0 + 0.6), Vector3(0, 0, -1))
	light(Vector3(cor_x + 0.7, y + 2.6, (z0 + z1) * 0.5), "interior", 8.0, 0.7)

func _partition_x_simple(z: float, x0: float, x1: float, y0: float, y1: float) -> void:
	inn.face(mat_in, Vector3(x1, y0, z), Vector3(x0 - x1, 0, 0), Vector3(0, y1 - y0, 0))
	inn.face(mat_in, Vector3(x0, y0, z + 0.1), Vector3(x1 - x0, 0, 0), Vector3(0, y1 - y0, 0))
	solid(Vector3(x0, y0, z), Vector3(x1, y1, z + 0.1))

## The corridor wall is built solid by inner_partition_z(dw = 0); doorways are re-cut as gaps in its collision and
## drawn as dark openings with casings (cheap: rooms behind are visible through the opening anyway).
func _cut_door_z(x: float, zc: float, y: float) -> void:
	paint(col_trim, inn)
	inn.box("paint", Vector3(x - 0.03, y, zc - 0.5), Vector3(x + 0.13, y + DOOR_H + 0.1, zc - 0.42))
	inn.box("paint", Vector3(x - 0.03, y, zc + 0.42), Vector3(x + 0.13, y + DOOR_H + 0.1, zc + 0.5))
	inn.box("paint", Vector3(x - 0.03, y + DOOR_H, zc - 0.5), Vector3(x + 0.13, y + DOOR_H + 0.1, zc + 0.5))
	inn.box("dark_planks", Vector3(x - 0.02, y, zc - 0.42), Vector3(x + 0.12, y + DOOR_H, zc + 0.42), MeshKit.F_PX | MeshKit.F_NX)
	paint(col_wall, inn)

func _f_hotel() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	# front desk on the left, key board behind, lobby chairs, dining tables at the back
	counter(x0 + 1.4, z0 + 2.5, x0 + 1.95, z0 + 5.5, 1.05, "fine_wood", "fine_wood")
	paint(Color(0.6, 0.45, 0.3), inn)
	inn.box("fine_wood", Vector3(x0, 1.3, z0 + 3.0), Vector3(x0 + 0.05, 2.1, z0 + 5.0), MeshKit.F_PX)
	inn.tint = Color(1, 1, 1, 0.1)
	for i in 12:
		inn.box("brass", Vector3(x0 + 0.05, 1.45 + (i / 6) * 0.35, z0 + 3.15 + (i % 6) * 0.3), Vector3(x0 + 0.08, 1.55 + (i / 6) * 0.35, z0 + 3.2 + (i % 6) * 0.3))
	paint(col_wall, inn)
	prop("CashRegister_01", Vector3(x0 + 1.67, 1.05, z0 + 3.0), 90.0, 0.8)
	prop("mantel_clock_01", Vector3(x0 + 1.67, 1.05, z0 + 5.0), 90.0)
	spot("clerk", Vector3(x0 + 0.7, 0.0, z0 + 4.0), Vector3(1, 0, 0), {"work": "desk"})
	spot("desk_customer", Vector3(x0 + 2.6, 0.0, z0 + 4.0), Vector3(-1, 0, 0))
	prop("vintage_grandfather_clock_01", Vector3(x1 - 2.0, 0.0, z0 + 0.4), 0.0)
	rug(x0 + 2.4, z0 + 1.2, x1 - 1.6, z0 + 5.5)
	for i in 3:
		var p := Vector3(x1 - 2.2 - i * 1.1, 0.0, z0 + 1.6 + (i % 2) * 0.5)
		prop("Rockingchair_01", p, 160.0 + i * 20.0)
		spot("chair", p, Vector3(0, 0, 1), {"sit_height": 0.45})
	prop("WoodenTable_02", Vector3(x1 - 2.7, 0.0, z0 + 2.5), 0.0)
	picture(x1 - 0.03, 1.9, z0 + 3.0, -90.0)
	picture(x0 + 0.03, 1.9, z1 - 2.0, 90.0)
	for i in 2:
		table_chairs(x0 + 3.0 + i * 2.6, z1 - 2.0, 0.0, true, 4)
	stove(x0 + 0.6, z1 - 0.8, 0.0, STOREY - 0.1)
	_upper_rooms()

func _f_store() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	# shelving floor-to-ceiling on both side walls; counter along the right; goods on the floor
	shelves(z0 + 1.2, z1 - 0.3, x0, 0.45, 2.7, 5, true, 1.0)
	shelves(z0 + 3.6, z1 - 0.3, x1, 0.45, 2.7, 5, true, -1.0)
	counter(x1 - 1.6, z0 + 1.8, x1 - 1.0, z1 - 1.0, 0.95)
	prop("CashRegister_01", Vector3(x1 - 1.3, 0.95, z0 + 2.6), -90.0, 0.85)
	prop("wicker_basket_01", Vector3(x1 - 1.3, 0.95, z0 + 3.6), 20.0)
	prop("jug_01", Vector3(x1 - 1.3, 0.95, z1 - 1.6), 0.0)
	# behind the till, where the counter leaves a full-width aisle to the wall (walkable for the clerk)
	spot("shopkeeper", Vector3(x1 - 0.5, 0.0, z0 + 2.6), Vector3(-1, 0, 0), {"work": "counter"})
	spot("shop_counter", Vector3(x1 - 2.1, 0.0, z0 + 2.6), Vector3(1, 0, 0))
	spot("shop_counter", Vector3(x1 - 2.1, 0.0, (z0 + z1) * 0.5), Vector3(1, 0, 0))
	var cx := (x0 + x1) * 0.5 - 0.6
	display_case(cx - 0.4, z0 + 2.8, cx + 0.4, z0 + 5.4)
	prop("barrel_03", Vector3(x0 + 0.9, 0.0, z0 + 0.6), 0.0)
	prop("barrel_03", Vector3(x0 + 1.6, 0.0, z0 + 0.6), 40.0)
	sacks(cx, z1 - 1.0, 0.0, 4)
	prop("rusted_spade_01", Vector3(x0 + 0.5, 0.55, z0 + 0.9), 80.0)
	prop("wooden_axe", Vector3(x0 + 0.55, 0.22, z0 + 1.0), 90.0)
	prop("wooden_bucket_01", Vector3(cx + 0.9, 0.0, z0 + 1.0), 0.0)
	prop("wooden_bucket_02", Vector3(cx + 1.1, 0.0, z0 + 1.6), 0.0)
	prop("pot_enamel_01", Vector3(x1 - 1.3, 0.95, z1 - 2.2), 0.0)
	prop("wooden_ladder", Vector3(x0 + 0.75, 0.0, z1 - 2.0), 90.0, 1.4)
	stove((x0 + x1) * 0.5 + 0.5, z1 - 2.6, 0.0, STOREY - 0.05)
	prop("folding_wooden_stool", Vector3((x0 + x1) * 0.5 + 1.2, 0.0, z1 - 1.9), 200.0)
	prop("painted_wooden_chair_01", Vector3((x0 + x1) * 0.5 - 0.3, 0.0, z1 - 1.9), 160.0)
	spot("chair", Vector3((x0 + x1) * 0.5 - 0.3, 0.0, z1 - 1.9), Vector3(0.3, 0, -1), {"sit_height": 0.46})
	spot("chair", Vector3((x0 + x1) * 0.5 + 1.2, 0.0, z1 - 1.9), Vector3(-0.3, 0, -1), {"sit_height": 0.44})
	prop("wooden_lantern_01", Vector3(cx, STOREY - 1.0, (z0 + z1) * 0.5), 0.0)
	_f_backroom()

func _f_backroom() -> void:
	var b := R("back")
	if b.rect.size.x <= 0.0 or b.name != "back":
		return
	var rc: Rect2 = b.rect
	crates_pile(rc.position.x + 1.2, rc.position.y + 0.9, 0.0, 4)
	prop("wooden_barrels_01", Vector3(rc.end.x - 1.5, 0.0, rc.position.y + rc.size.y * 0.5), 0.0, 0.45)
	spot("work", Vector3(rc.position.x + rc.size.x * 0.5, 0.0, rc.position.y + rc.size.y * 0.5), Vector3(-1, 0, 0), {"work": "stock"})

func _f_gunsmith() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	# glass-topped counter across the shop, rifles racked behind, workbench at the back
	counter(x0 + 0.6, z0 + 3.4, x1 - 1.3, z0 + 4.0, 0.95, "fine_wood", "fine_wood")
	inn.tint = Color(1.0, 0.5, 1.0, 1.0)
	inn.box("glass", Vector3(x0 + 0.7, 0.96, z0 + 3.45), Vector3(x1 - 1.4, 1.2, z0 + 3.95), MeshKit.F_PY | MeshKit.F_NZ)
	paint(col_wall, inn)
	for i in 3:
		gun_rack(x0 + 1.1 + i * 1.3, 0.9, z1 - 0.02, 180.0, 5)
	gun_rack(x1 - 0.02, 0.9, z0 + 6.0, -90.0, 6)
	counter(x0 + 0.2, z1 - 2.3, x0 + 2.4, z1 - 1.7, 0.9, "dark_planks", "dark_planks")
	prop("vintage_binocular", Vector3(x0 + 1.0, 0.9, z1 - 2.0), 30.0)
	prop("wooden_military_crate", Vector3(x1 - 1.0, 0.0, z1 - 0.8), 90.0)
	prop("wooden_military_crate", Vector3(x1 - 1.0, 0.46, z1 - 0.8), 80.0)
	prop("wooden_crate_01", Vector3(x0 + 0.8, 0.0, z0 + 0.6), 10.0)
	prop("pocket_watch", Vector3(x0 + 1.5, 0.96, z0 + 3.7), 0.0)
	spot("shopkeeper", Vector3((x0 + x1) * 0.5, 0.0, z0 + 4.6), Vector3(0, 0, -1), {"work": "counter"})
	spot("shop_counter", Vector3((x0 + x1) * 0.5, 0.0, z0 + 2.7), Vector3(0, 0, 1))
	spot("work", Vector3(x0 + 1.3, 0.0, z1 - 1.3), Vector3(0, 0, -1), {"work": "bench"})
	prop("painted_wooden_chair_01", Vector3(x0 + 1.3, 0.0, z1 - 1.2), 180.0)
	_f_backroom()

func _f_sheriff() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	# office at the front: desk, chairs, rack, wanted posters; two cells across the back
	var cz := z1 - 2.6
	desk(x0 + 2.2, z0 + 2.4, 180.0)
	prop("painted_wooden_chair_01@stain", Vector3(x0 + 2.2, 0.0, z0 + 3.2), 180.0)
	spot("sheriff_desk", Vector3(x0 + 2.2, 0.0, z0 + 3.2), Vector3(0, 0, -1), {"sit_height": 0.46, "work": "desk"})
	prop("painted_wooden_chair_01@stain", Vector3(x0 + 2.2, 0.0, z0 + 1.5), 0.0)
	spot("chair", Vector3(x0 + 2.2, 0.0, z0 + 1.5), Vector3(0, 0, 1), {"sit_height": 0.46})
	prop("vintage_oil_lamp", Vector3(x0 + 1.8, 0.77, z0 + 2.4), 0.0, 0.7)
	gun_rack(x1 - 0.02, 0.9, z0 + 2.5, -90.0, 6)
	wanted_board(x0 + 0.03, 1.6, z0 + 1.6, 90.0)
	prop("painted_wooden_cabinet", Vector3(x1 - 0.45, 0.0, z0 + 4.5), -90.0, 0.9)
	stove(x1 - 1.2, cz - 0.8, 0.0, STOREY - 0.05)
	prop("Rockingchair_01", Vector3(x1 - 2.2, 0.0, cz - 1.2), 120.0)
	# cells: bar front with a gap (cell door left ajar), cots
	var mid := (x0 + x1) * 0.5
	bars_wall(Vector3(x0, 0.0, cz), Vector3(mid - 1.0, 0.0, cz), 2.5)
	bars_wall(Vector3(mid - 0.2, 0.0, cz), Vector3(mid + 0.2, 0.0, cz), 2.5)
	bars_wall(Vector3(mid + 1.0, 0.0, cz), Vector3(x1, 0.0, cz), 2.5)
	bars_wall(Vector3(mid, 0.0, cz), Vector3(mid, 0.0, z1), 2.5)
	for sgn: float in [-1.0, 1.0]:
		var bx: float = mid + sgn * (x1 - x0) * 0.25
		inn.tint = Color(0.7, 0.65, 0.55, 0.3)
		inn.box("planks_brown", Vector3(bx - 1.0, 0.4, z1 - 0.75), Vector3(bx + 1.0, 0.46, z1 - 0.05))
		inn.box("iron", Vector3(bx - 0.95, 0.0, z1 - 0.7), Vector3(bx - 0.9, 0.4, z1 - 0.65))
		inn.box("iron", Vector3(bx + 0.9, 0.0, z1 - 0.7), Vector3(bx + 0.95, 0.4, z1 - 0.65))
		inn.tint = Color(0.55, 0.5, 0.4, 0.3)
		inn.box("cloth", Vector3(bx - 0.95, 0.46, z1 - 0.72), Vector3(bx + 0.8, 0.5, z1 - 0.08))
		paint(col_wall, inn)
		solid(Vector3(bx - 1.0, 0.0, z1 - 0.75), Vector3(bx + 1.0, 0.46, z1 - 0.05))
		spot("cell_bunk", Vector3(bx, 0.0, z1 - 1.2), Vector3(0, 0, 1), {"sit_height": 0.46, "cell": 0 if sgn < 0 else 1})
		prop("wooden_bucket_01", Vector3(bx + 0.9, 0.0, cz + 0.5), 0.0)
	room("cells", x0, cz, x1, z1, 0.0)
	light(Vector3(mid, 2.8, (cz + z1) * 0.5), "interior", 5.0, 0.4)

func _f_bank() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	var cz := z0 + 4.2
	counter(x0, cz, x1 - 1.3, cz + 0.7, 1.1, "fine_wood", "fine_wood")
	# teller grilles (brass bars) on the counter
	inn.tint = Color(1, 1, 1, 0.1)
	var n := int((x1 - 1.3 - x0) / 0.12)
	for i in n:
		var bx := x0 + 0.06 + i * 0.12
		if i % 14 in [5, 6, 7, 8]:
			continue
		inn.box("brass", Vector3(bx - 0.008, 1.1, cz + 0.33), Vector3(bx + 0.008, 2.0, cz + 0.37), MeshKit.F_SIDES)
	inn.box("brass", Vector3(x0, 1.98, cz + 0.3), Vector3(x1 - 1.3, 2.04, cz + 0.4))
	paint(col_wall, inn)
	solid(Vector3(x0, 1.1, cz + 0.3), Vector3(x1 - 1.3, 2.04, cz + 0.4))
	for i in 2:
		var tx := x0 + 1.2 + i * 2.6
		spot("teller", Vector3(tx, 0.0, cz + 1.3), Vector3(0, 0, -1), {"work": "teller"})
		spot("bank_customer", Vector3(tx, 0.0, cz - 0.6), Vector3(0, 0, 1))
		prop("CashRegister_01", Vector3(tx, 1.1, cz + 0.45), 180.0, 0.7)
	# vault at the back
	var vx := (x0 + x1) * 0.5
	inn.tint = Color(1, 1, 1, 0.2)
	inn.box("iron", Vector3(vx - 1.3, 0.0, z1 - 1.6), Vector3(vx + 1.3, 2.5, z1), MeshKit.F_NZ | MeshKit.F_PX | MeshKit.F_NX | MeshKit.F_PY)
	inn.cyl("iron", Vector3(vx, 1.15, z1 - 1.6), Vector3(vx, 1.15, z1 - 1.75), 0.85, 16, true)
	inn.cyl("brass", Vector3(vx, 1.15, z1 - 1.75), Vector3(vx, 1.15, z1 - 1.85), 0.18, 10, true)
	for k in 4:
		var a := TAU * k / 4.0
		inn.beam("brass", Vector3(vx, 1.15, z1 - 1.8), Vector3(vx + cos(a) * 0.4, 1.15 + sin(a) * 0.4, z1 - 1.8), 0.03)
	paint(col_wall, inn)
	solid(Vector3(vx - 1.3, 0.0, z1 - 1.6), Vector3(vx + 1.3, 2.5, z1))
	text(inn, "SAFE DEPOSIT", Vector3(vx, 2.25, z1 - 1.61), Vector3(-1, 0, 0), Vector3(0, 0, -1), 0.1, 1.6, Color(0.85, 0.7, 0.35), "OldStandard-Bold")
	desk(x0 + 1.8, z1 - 2.4, 180.0)
	prop("painted_wooden_chair_01@stain", Vector3(x0 + 1.8, 0.0, z1 - 1.6), 180.0)
	spot("banker_desk", Vector3(x0 + 1.8, 0.0, z1 - 1.6), Vector3(0, 0, -1), {"sit_height": 0.46, "work": "desk"})
	prop("vintage_grandfather_clock_01", Vector3(x1 - 0.5, 0.0, z0 + 0.5), -90.0)
	bench(x0 + 0.5, x0 + 2.5, z0 + 0.5, 0.0, true)
	rug(x0 + 0.6, z0 + 1.2, x1 - 0.6, cz - 0.4)
	picture(x1 - 0.03, 1.9, z0 + 2.5, -90.0)

func _f_doctor() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	bench(x0 + 0.4, x0 + 2.4, z0 + 0.5, 0.0, true)
	desk(x1 - 1.5, z0 + 2.2, 90.0)
	prop("painted_wooden_chair_01@stain", Vector3(x1 - 0.6, 0.0, z0 + 2.2), -90.0)
	spot("doctor_desk", Vector3(x1 - 0.6, 0.0, z0 + 2.2), Vector3(-1, 0, 0), {"sit_height": 0.46, "work": "desk"})
	# examination table
	paint(Color(0.7, 0.6, 0.5), inn)
	inn.box("fine_wood", Vector3(x0 + 0.6, 0.0, z1 - 2.6), Vector3(x0 + 1.3, 0.8, z1 - 0.8))
	inn.tint = Color(0.9, 0.9, 0.86, 0.1)
	inn.box("cloth", Vector3(x0 + 0.62, 0.8, z1 - 2.58), Vector3(x0 + 1.28, 0.86, z1 - 0.82))
	paint(col_wall, inn)
	solid(Vector3(x0 + 0.6, 0.0, z1 - 2.6), Vector3(x0 + 1.3, 0.86, z1 - 0.8))
	spot("patient", Vector3(x0 + 0.95, 0.0, z1 - 1.7), Vector3(1, 0, 0), {"lie_height": 0.86})
	spot("work", Vector3(x0 + 1.8, 0.0, z1 - 1.7), Vector3(-1, 0, 0), {"work": "treat"})
	shelves(z1 - 3.0, z1 - 0.3, x1, 0.4, 2.0, 4, true, -1.0)
	prop("painted_wooden_cabinet", Vector3((x0 + x1) * 0.5, 0.0, z1 - 0.35), 180.0, 0.9)
	prop("wooden_bowl_01", Vector3((x0 + x1) * 0.5, 1.06, z1 - 0.35), 0.0)
	prop("jug_01", Vector3((x0 + x1) * 0.5 + 0.3, 1.06, z1 - 0.35), 40.0)
	bed(x0 + 0.65, (z0 + z1) * 0.5 - 0.3, 0.0, 90.0)
	picture(x0 + 0.03, 1.8, z0 + 2.0, 90.0)
	_f_backroom()

func _f_barber() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	# two chairs facing the mirror on the left wall, counter with bowls, waiting bench
	inn.tint = Color(1, 1, 1, 0.1)
	inn.box("mirror", Vector3(x0 + 0.01, 1.2, z0 + 1.6), Vector3(x0 + 0.03, 2.1, z0 + 5.4), MeshKit.F_PX)
	paint(col_wall, inn)
	counter(x0, z0 + 1.6, x0 + 0.5, z0 + 5.4, 0.9, "fine_wood", "fine_wood")
	for i in 2:
		var cz := z0 + 2.4 + i * 2.0
		prop("BarberShopChair_01", Vector3(x0 + 1.5, 0.0, cz), -90.0)
		solid(Vector3(x0 + 1.15, 0.0, cz - 0.35), Vector3(x0 + 1.85, 1.0, cz + 0.35))
		spot("barber_chair", Vector3(x0 + 1.5, 0.0, cz), Vector3(-1, 0, 0), {"sit_height": 0.6})
		spot("barber", Vector3(x0 + 2.3, 0.0, cz + 0.3), Vector3(-1, 0, 0), {"work": "shave"})
		prop("wooden_bowl_01", Vector3(x0 + 0.25, 0.9, cz), 0.0)
		prop("jug_01", Vector3(x0 + 0.25, 0.9, cz + 0.45), 0.0)
	bench(x1 - 0.5, x1 - 0.1, z0 + 1.0, 0.0, true, true)
	for i in 3:
		var p := Vector3(x1 - 0.5, 0.0, z0 + 1.6 + i * 0.75)
		prop("painted_wooden_chair_01", p, -90.0)
		spot("chair", p, Vector3(-1, 0, 0), {"sit_height": 0.46})
	picture(x1 - 0.03, 1.8, z0 + 4.5, -90.0)
	# bath in the back room
	var b := R("back")
	if b.name == "back":
		var br: Rect2 = b.rect
		paint(Color(0.9, 0.9, 0.88), inn)
		inn.box("iron", Vector3(br.position.x + 0.4, 0.0, br.position.y + 0.4), Vector3(br.position.x + 2.1, 0.6, br.position.y + 1.2), MeshKit.F_SIDES)
		inn.tint = Color(1, 1, 1, 0)
		inn.box("water", Vector3(br.position.x + 0.45, 0.4, br.position.y + 0.45), Vector3(br.position.x + 2.05, 0.45, br.position.y + 1.15), MeshKit.F_PY)
		paint(col_wall, inn)
		solid(Vector3(br.position.x + 0.4, 0.0, br.position.y + 0.4), Vector3(br.position.x + 2.1, 0.6, br.position.y + 1.2))
		spot("bath", Vector3(br.position.x + 1.25, 0.0, br.position.y + 0.8), Vector3(1, 0, 0), {"sit_height": 0.2})
		prop("wooden_bucket_01", Vector3(br.position.x + 2.5, 0.0, br.position.y + 0.6), 0.0)
		stove(br.end.x - 0.6, br.position.y + 0.6, 0.0, STOREY - 0.05)

func _f_undertaker() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	for i in 3:
		var cz := z0 + 1.6 + i * 1.0
		paint(Color(0.6, 0.5, 0.4), inn)
		inn.box("dark_planks", Vector3(x0 + 0.3, 0.0, cz - 0.25), Vector3(x0 + 0.5, 0.5, cz + 0.25))
		coffin(x0 + 1.4, cz, 0.0, 90.0, i == 1)
	coffin(x1 - 0.6, z1 - 1.6, 0.0, 0.0, false)
	solid(Vector3(x0 + 0.3, 0.0, z0 + 1.2), Vector3(x0 + 2.5, 0.5, z0 + 3.8))
	counter(x1 - 2.6, z0 + 2.0, x1 - 0.4, z0 + 2.6, 0.9, "dark_planks", "dark_planks")
	prop("hatchet", Vector3(x1 - 1.5, 0.9, z0 + 2.3), 60.0)
	prop("rusted_spade_01", Vector3(x1 - 0.2, 0.55, z1 - 0.4), 0.0)
	spot("work", Vector3(x1 - 1.5, 0.0, z0 + 3.0), Vector3(0, 0, -1), {"work": "carpentry"})
	prop("painted_wooden_chair_01", Vector3(x1 - 1.0, 0.0, z0 + 0.8), 200.0)
	picture(x0 + 0.03, 1.8, z1 - 1.5, 90.0)
	_f_backroom()

func _f_post() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	var cz := z0 + 3.2
	counter(x0, cz, x1 - 1.2, cz + 0.6, 1.05, "fine_wood", "fine_wood")
	# pigeonholes behind the counter
	paint(Color(0.7, 0.55, 0.4), inn)
	var pw := x1 - 1.6 - x0
	inn.box("fine_wood", Vector3(x0 + 0.2, 0.9, z1 - 0.35), Vector3(x0 + 0.2 + pw, 2.4, z1 - 0.05))
	inn.tint = Color(0.15, 0.12, 0.1, 0.1)
	for r in 5:
		for c in int(pw / 0.25):
			inn.box("cloth", Vector3(x0 + 0.24 + c * 0.25, 0.95 + r * 0.29, z1 - 0.36), Vector3(x0 + 0.42 + c * 0.25, 1.18 + r * 0.29, z1 - 0.355), MeshKit.F_NZ)
	paint(col_wall, inn)
	solid(Vector3(x0 + 0.2, 0.0, z1 - 0.35), Vector3(x0 + 0.2 + pw, 2.4, z1 - 0.05))
	prop("painted_wooden_table", Vector3(x1 - 1.8, 0.0, z1 - 1.4), 90.0, 0.55)
	inn.tint = Color(1, 1, 1, 0.2)
	inn.box("brass", Vector3(x1 - 1.85, 0.56, z1 - 1.5), Vector3(x1 - 1.7, 0.6, z1 - 1.3))
	paint(col_wall, inn)
	spot("telegrapher", Vector3(x1 - 1.0, 0.0, z1 - 1.4), Vector3(-1, 0, 0), {"sit_height": 0.46, "work": "telegraph"})
	prop("painted_wooden_chair_01", Vector3(x1 - 1.0, 0.0, z1 - 1.4), -90.0)
	spot("clerk", Vector3((x0 + x1) * 0.5 - 0.6, 0.0, cz + 1.1), Vector3(0, 0, -1), {"work": "counter"})
	spot("shop_counter", Vector3((x0 + x1) * 0.5 - 0.6, 0.0, cz - 0.6), Vector3(0, 0, 1))
	wanted_board(x0 + 0.03, 1.6, z0 + 1.5, 90.0)
	bench(x1 - 0.5, x1 - 0.1, z0 + 0.6, 0.0, true, true)
	prop("vintage_suitcase", Vector3(x0 + 1.0, 0.0, z0 + 0.4), 10.0)

func _f_restaurant() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	counter(x0 + 0.2, z1 - 2.0, x1 - 1.5, z1 - 1.4, 1.0, "dark_planks", "fine_wood")
	spot("cook", Vector3((x0 + x1) * 0.5, 0.0, z1 - 0.8), Vector3(0, 0, -1), {"work": "cook"})
	stove(x1 - 0.8, z1 - 0.6, 0.0, STOREY - 0.05)
	prop("pot_enamel_01", Vector3(x1 - 0.8, 0.75, z1 - 0.6), 0.0)
	var n := maxi(1, int((z1 - 2.6 - z0) / 2.2))
	for i in n:
		table_chairs(x0 + 1.4, z0 + 1.5 + i * 2.2, 0.0, false, 4)
		if x1 - x0 > 5.0:
			table_chairs(x1 - 1.6, z0 + 1.5 + i * 2.2, 0.0, true, 3)
	picture(x0 + 0.03, 1.9, z0 + 2.0, 90.0)

func _f_butcher() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	counter(x0 + 0.4, z0 + 3.0, x1 - 0.4, z0 + 3.7, 0.95, "paint", "fine_wood")
	spot("shopkeeper", Vector3((x0 + x1) * 0.5, 0.0, z0 + 4.3), Vector3(0, 0, -1), {"work": "counter"})
	spot("shop_counter", Vector3((x0 + x1) * 0.5, 0.0, z0 + 2.4), Vector3(0, 0, 1))
	# hanging cuts on a rail and a chopping block
	inn.tint = Color(1, 1, 1, 0.2)
	inn.box("iron", Vector3(x0 + 0.3, 2.45, z1 - 0.6), Vector3(x1 - 0.3, 2.5, z1 - 0.55))
	for i in int((x1 - x0 - 0.8) / 0.5):
		var hx := x0 + 0.6 + i * 0.5
		inn.tint = Color(0.62, 0.2, 0.16, 0.2)
		inn.obox("cloth", Vector3(hx, 2.0, z1 - 0.58), Vector3(0.22, 0.6, 0.16), Basis(Vector3.UP, rng.randf()))
	paint(Color(0.8, 0.7, 0.6), inn)
	inn.cyl("log", Vector3(x0 + 1.0, 0.0, z1 - 1.8), Vector3(x0 + 1.0, 0.85, z1 - 1.8), 0.4, 10, true)
	paint(col_wall, inn)
	prop("hatchet", Vector3(x0 + 1.0, 0.85, z1 - 1.8), 30.0)
	spot("work", Vector3(x0 + 1.0, 0.0, z1 - 2.5), Vector3(0, 0, 1), {"work": "butcher"})
	prop("wooden_bucket_02", Vector3(x1 - 1.0, 0.0, z1 - 1.2), 0.0)
	_f_backroom()

func _f_church() -> void:
	var m := R("nave")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	var cx := (x0 + x1) * 0.5
	var rows := int((z1 - z0 - 4.5) / 1.0)
	for i in rows:
		var pz := z0 + 1.5 + i * 1.0
		bench(x0 + 0.3, cx - 0.7, pz, 0.0, true)
		bench(cx + 0.7, x1 - 0.3, pz, 0.0, true)
	# chancel: raised platform, altar, pulpit, cross
	paint(Color(0.75, 0.62, 0.5), inn)
	inn.box("floor", Vector3(x0, 0.0, z1 - 2.6), Vector3(x1, 0.3, z1), MeshKit.F_PY | MeshKit.F_NZ)
	solid(Vector3(x0, 0.0, z1 - 2.6), Vector3(x1, 0.3, z1))
	inn.box("fine_wood", Vector3(cx - 0.9, 0.3, z1 - 1.2), Vector3(cx + 0.9, 1.25, z1 - 0.6))
	inn.tint = Color(0.92, 0.9, 0.84, 0.0)
	inn.box("cloth", Vector3(cx - 0.95, 1.25, z1 - 1.25), Vector3(cx + 0.95, 1.28, z1 - 0.55))
	paint(Color(0.75, 0.62, 0.5), inn)
	inn.box("fine_wood", Vector3(cx + 1.8, 0.3, z1 - 2.4), Vector3(cx + 2.5, 1.45, z1 - 1.8))
	inn.box("fine_wood", Vector3(cx - 0.06, 1.8, z1 - 0.04), Vector3(cx + 0.06, 3.4, z1))
	inn.box("fine_wood", Vector3(cx - 0.45, 2.8, z1 - 0.04), Vector3(cx + 0.45, 2.92, z1))
	paint(col_wall, inn)
	solid(Vector3(cx - 0.9, 0.3, z1 - 1.2), Vector3(cx + 0.9, 1.25, z1 - 0.6))
	spot("preacher", Vector3(cx + 2.15, 0.3, z1 - 1.5), Vector3(0, 0, -1), {"work": "preach"})
	prop("vintage_oil_lamp", Vector3(cx - 0.6, 1.28, z1 - 0.9), 0.0, 0.7)
	prop("vintage_oil_lamp", Vector3(cx + 0.6, 1.28, z1 - 0.9), 0.0, 0.7)
	prop("lantern_chandelier_01", Vector3(cx, 4.4, z0 + (z1 - z0) * 0.35), 0.0)
	prop("lantern_chandelier_01", Vector3(cx, 4.4, z0 + (z1 - z0) * 0.7), 0.0)
	light(Vector3(cx, 3.6, z0 + (z1 - z0) * 0.35), "interior", 9.0, 1.0)
	light(Vector3(cx, 3.6, z0 + (z1 - z0) * 0.7), "interior", 9.0, 1.0)

func _f_school() -> void:
	var m := R("class")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	var cols := 3
	var rows := int((z1 - z0 - 3.5) / 1.2)
	for i in rows:
		for j in cols:
			var px := lerpf(x0 + 1.0, x1 - 1.0, float(j) / (cols - 1))
			var pz := z0 + 1.2 + i * 1.2
			paint(Color(0.7, 0.6, 0.5), inn)
			inn.box("fine_wood", Vector3(px - 0.55, 0.68, pz + 0.25), Vector3(px + 0.55, 0.72, pz + 0.65))
			inn.box("iron", Vector3(px - 0.5, 0.0, pz + 0.4), Vector3(px - 0.46, 0.68, pz + 0.5))
			inn.box("iron", Vector3(px + 0.46, 0.0, pz + 0.4), Vector3(px + 0.5, 0.68, pz + 0.5))
			paint(col_wall, inn)
			bench(px - 0.55, px + 0.55, pz, 0.0, true)
			solid(Vector3(px - 0.55, 0.0, pz + 0.25), Vector3(px + 0.55, 0.72, pz + 0.65))
	# blackboard and teacher's desk
	inn.tint = Color(0.12, 0.16, 0.13, 0.0)
	inn.box("cloth", Vector3((x0 + x1) * 0.5 - 1.5, 1.0, z1 - 0.03), Vector3((x0 + x1) * 0.5 + 1.5, 2.2, z1), MeshKit.F_NZ)
	paint(col_wall, inn)
	text(inn, "1899", Vector3((x0 + x1) * 0.5 + 0.9, 1.9, z1 - 0.035), Vector3(-1, 0, 0), Vector3(0, 0, -1), 0.14, 0.6, Color(0.9, 0.9, 0.86), "OldStandard-Regular")
	prop("painted_wooden_table", Vector3((x0 + x1) * 0.5, 0.0, z1 - 1.3), 0.0, 0.6)
	solid(Vector3((x0 + x1) * 0.5 - 0.75, 0.0, z1 - 1.65), Vector3((x0 + x1) * 0.5 + 0.75, 0.6, z1 - 0.95))
	spot("teacher", Vector3((x0 + x1) * 0.5, 0.0, z1 - 0.6), Vector3(0, 0, -1), {"work": "teach"})
	stove(x0 + 0.7, z1 - 0.7, 0.0, 3.3)

func _f_livery() -> void:
	var m := R("stable")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	var n := int((z1 - z0 - 2.0) / 2.5)
	for sgn: float in [-1.0, 1.0]:
		var xw: float = x0 if sgn < 0 else x1
		var xs: float = xw + (3.0 if sgn < 0 else -3.0)
		for i in n + 1:
			var pz := z0 + 1.5 + i * 2.5
			paint(Color(0.85, 0.8, 0.72), inn)
			inn.box("planks_v", Vector3(minf(xw, xs), 0.0, pz - 0.04), Vector3(maxf(xw, xs), 1.5, pz + 0.04))
			inn.box("planks_brown", Vector3(xs - 0.07, 0.0, pz - 0.07), Vector3(xs + 0.07, 2.2, pz + 0.07))
			solid(Vector3(minf(xw, xs), 0.0, pz - 0.04), Vector3(maxf(xw, xs), 1.5, pz + 0.04))
			if i < n:
				spot("stall", Vector3((xw + xs) * 0.5, 0.0, pz + 1.25), Vector3(-sgn, 0, 0), {"animal": "horse"})
				prop("wooden_bucket_01", Vector3(xw + (0.35 if sgn < 0 else -0.35), 0.0, pz + 0.6), 0.0)
				hay(xw + (0.5 if sgn < 0 else -0.5), pz + 1.8, 0.0, 1)
	paint(col_wall, inn)
	hay(x0 + 0.9, z1 - 0.6, 0.0, 6)
	prop("wooden_ladder", Vector3(x1 - 0.5, 0.0, z1 - 1.2), -90.0, 1.8)
	prop("barrel_03", Vector3(x1 - 0.6, 0.0, z0 + 0.6), 0.0)
	prop("rusted_spade_01", Vector3(x0 + 0.25, 0.55, z0 + 0.8), 90.0)
	spot("work", Vector3(0.0, 0.0, (z0 + z1) * 0.5), Vector3(-1, 0, 0), {"work": "stable"})
	hay(x0 + 1.0, d * 0.6, 4.3, 6, inn)

func _f_smithy() -> void:
	var m := R("shop")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	# brick forge with hood and stack, glowing coals; anvil on a stump; quench tub; tool rack
	var fx := x0 + 1.2
	var fz := z1 - 1.0
	paint(Color(0.9, 0.82, 0.78), inn)
	inn.box("brick", Vector3(fx - 0.8, -0.3, fz - 0.6), Vector3(fx + 0.8, 0.8, fz + 0.6), MeshKit.F_ALL & ~MeshKit.F_NY)
	inn.box("brick", Vector3(fx - 0.6, 1.8, fz - 0.4), Vector3(fx + 0.6, 2.3, fz + 0.6), MeshKit.F_ALL)
	inn.box("brick", Vector3(fx - 0.25, 2.3, fz - 0.05), Vector3(fx + 0.25, 4.6, fz + 0.45), MeshKit.F_SIDES | MeshKit.F_PY)
	inn.tint = Color(1, 1, 1, 0)
	inn.box("fire", Vector3(fx - 0.4, 0.8, fz - 0.3), Vector3(fx + 0.4, 0.86, fz + 0.3), MeshKit.F_PY)
	paint(col_wall, inn)
	solid(Vector3(fx - 0.8, 0.0, fz - 0.6), Vector3(fx + 0.8, 0.8, fz + 0.6))
	light(Vector3(fx, 1.2, fz - 0.6), "fire", 6.0, 1.4, Color(1.0, 0.45, 0.15))
	var ax := (x0 + x1) * 0.5 + 0.3
	var az := (z0 + z1) * 0.5
	paint(Color(0.8, 0.7, 0.6), inn)
	inn.cyl("log", Vector3(ax, 0.0, az), Vector3(ax, 0.55, az), 0.3, 9, true)
	inn.tint = Color(1, 1, 1, 0.2)
	inn.box("iron", Vector3(ax - 0.12, 0.55, az - 0.1), Vector3(ax + 0.12, 0.75, az + 0.1))
	inn.box("iron", Vector3(ax - 0.35, 0.75, az - 0.12), Vector3(ax + 0.3, 0.9, az + 0.12))
	inn.cyl("iron", Vector3(ax + 0.3, 0.84, az), Vector3(ax + 0.55, 0.84, az), 0.06, 6, true, 0.01)
	paint(col_wall, inn)
	solid(Vector3(ax - 0.35, 0.0, az - 0.3), Vector3(ax + 0.55, 0.9, az + 0.3))
	spot("work", Vector3(ax - 0.8, 0.0, az), Vector3(1, 0, 0), {"work": "anvil"})
	spot("work", Vector3(fx + 1.1, 0.0, fz - 0.4), Vector3(-1, 0, 0), {"work": "forge"})
	prop("wine_barrel_01", Vector3(fx + 1.3, 0.0, fz + 0.3), 0.0, 0.8)
	gun_rack(x1 - 0.02, 1.0, z1 - 1.5, -90.0, 0)
	for i in 5:
		inn.tint = Color(1, 1, 1, 0.3)
		inn.box("iron", Vector3(x1 - 0.06, 1.2, z1 - 2.2 + i * 0.3), Vector3(x1 - 0.03, 1.9, z1 - 2.17 + i * 0.3))
	paint(col_wall, inn)
	prop("wooden_bucket_02", Vector3(x1 - 1.0, 0.0, z0 + 0.8), 0.0)
	prop("hatchet", Vector3(ax - 0.2, 0.9, az + 0.05), 0.0)

func _f_depot() -> void:
	var m := R("waiting")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	bench(x0 + 0.6, x0 + 3.2, z1 - 0.45, 0.0, true)
	bench(x0 + 3.8, x0 + 6.0, z1 - 0.45, 0.0, true)
	bench(x0 + 0.8, x0 + 3.2, (z0 + z1) * 0.5, 0.0, false)
	# ticket office in the far end (bay side): counter with grille
	counter(x1 - 2.6, z0 + 0.3, x1 - 2.1, z1 - 0.3, 1.05, "fine_wood", "fine_wood")
	inn.tint = Color(1, 1, 1, 0.1)
	for i in int((z1 - z0 - 0.6) / 0.1):
		var gz := z0 + 0.35 + i * 0.1
		if i % 12 in [4, 5, 6]:
			continue
		inn.box("brass", Vector3(x1 - 2.37, 1.05, gz - 0.006), Vector3(x1 - 2.33, 1.9, gz + 0.006), MeshKit.F_SIDES)
	paint(col_wall, inn)
	solid(Vector3(x1 - 2.4, 1.05, z0 + 0.3), Vector3(x1 - 2.3, 1.9, z1 - 0.3))
	spot("ticket_agent", Vector3(x1 - 1.4, 0.0, (z0 + z1) * 0.5), Vector3(-1, 0, 0), {"work": "tickets"})
	spot("ticket_customer", Vector3(x1 - 3.2, 0.0, (z0 + z1) * 0.5), Vector3(1, 0, 0))
	prop("painted_wooden_table", Vector3(x1 - 1.0, 0.0, z0 + 1.0), 90.0, 0.55)
	inn.tint = Color(1, 1, 1, 0.2)
	inn.box("brass", Vector3(x1 - 1.05, 0.56, z0 + 0.9), Vector3(x1 - 0.9, 0.6, z0 + 1.1))
	paint(col_wall, inn)
	prop("vintage_grandfather_clock_01", Vector3(x0 + 0.4, 0.0, z0 + 0.4), 0.0)
	stove(x0 + 4.6, (z0 + z1) * 0.5, 0.0, 3.6)
	var f := R("freight")
	var fr: Rect2 = f.rect
	crates_pile(fr.position.x + 1.2, fr.position.y + 1.2, 0.0, 5)
	prop("vintage_suitcase", Vector3(fr.position.x + 0.8, 0.0, fr.end.y - 0.5), 0.0)
	prop("vintage_suitcase", Vector3(fr.position.x + 0.8, 0.57, fr.end.y - 0.45), 8.0)
	prop("wooden_barrels_01", Vector3(fr.position.x + fr.size.x * 0.5, 0.0, fr.end.y - 1.8), 0.0, 0.45)
	spot("work", Vector3(fr.position.x + fr.size.x * 0.5, 0.0, fr.position.y + fr.size.y * 0.5), Vector3(0, 0, -1), {"work": "freight"})

func _f_house() -> void:
	var fr := R("front")
	var rc: Rect2 = fr.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	table_chairs(x0 + (x1 - x0) * 0.35, (z0 + z1) * 0.5 + 0.3, 0.0, false, 4)
	prop("Rockingchair_01", Vector3(x1 - 0.9, 0.0, z0 + 0.9), 220.0)
	spot("chair", Vector3(x1 - 0.9, 0.0, z0 + 0.9), Vector3(-0.6, 0, 0.8), {"sit_height": 0.45})
	stove(x1 - 0.6, z1 - 0.5, 0.0, 2.85)
	prop("painted_wooden_cabinet", Vector3(x0 + 0.65, 0.0, z1 - 0.35), 180.0, 0.85)
	prop("vintage_oil_lamp", Vector3(x0 + (x1 - x0) * 0.35, 0.8, (z0 + z1) * 0.5 + 0.3), 0.0, 0.6)
	rug(x0 + 0.8, z0 + 0.6, x1 - 0.8, z1 - 0.8)
	picture(x0 + 0.03, 1.7, (z0 + z1) * 0.5, 90.0)
	var bk := R("back")
	if bk.name == "back":
		var br: Rect2 = bk.rect
		bed(br.position.x + 0.6, br.position.y + br.size.y * 0.5, 0.0, 90.0)
		prop("ClassicNightstand_01", Vector3(br.position.x + 0.35, 0.0, br.end.y - 0.35), 90.0)
		prop("vintage_suitcase", Vector3(br.end.x - 0.4, 0.0, br.end.y - 0.3), 90.0, 0.8)
		prop("wooden_bowl_01", Vector3(br.position.x + 0.35, 0.7, br.end.y - 0.3), 0.0)
		prop("painted_wooden_chair_01", Vector3(br.end.x - 0.6, 0.0, br.position.y + 0.6), 200.0)

func _f_cabin() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	if z1 - z0 > 2.6:
		bed(x0 + 0.6, z1 - 1.2, 0.0, 90.0)
	else:
		bed(x0 + 1.2, z1 - 0.6, 0.0, 0.0)
	prop("WoodenTable_03", Vector3((x0 + x1) * 0.5, 0.0, z0 + 1.0), 0.0, 0.85)
	solid(Vector3((x0 + x1) * 0.5 - 0.55, 0.0, z0 + 0.75), Vector3((x0 + x1) * 0.5 + 0.55, 0.7, z0 + 1.25))
	prop("wooden_stool_01", Vector3((x0 + x1) * 0.5, 0.0, z0 + 1.6), 0.0)
	spot("chair", Vector3((x0 + x1) * 0.5, 0.0, z0 + 1.6), Vector3(0, 0, -1), {"sit_height": 0.44})
	# hearth against the chimney wall
	paint(Color(0.9, 0.85, 0.8), inn)
	inn.box("stone", Vector3(x1 - 0.7, -0.05, (z0 + z1) * 0.5 - 0.8), Vector3(x1, 1.3, (z0 + z1) * 0.5 + 0.8), MeshKit.F_NX | MeshKit.F_PY | MeshKit.F_NZ | MeshKit.F_PZ)
	inn.tint = Color(1, 1, 1, 0)
	inn.box("fire", Vector3(x1 - 0.45, 0.05, (z0 + z1) * 0.5 - 0.35), Vector3(x1 - 0.15, 0.1, (z0 + z1) * 0.5 + 0.35), MeshKit.F_PY)
	paint(col_wall, inn)
	solid(Vector3(x1 - 0.7, 0.0, (z0 + z1) * 0.5 - 0.8), Vector3(x1, 1.3, (z0 + z1) * 0.5 + 0.8))
	light(Vector3(x1 - 1.0, 0.6, (z0 + z1) * 0.5), "fire", 4.5, 0.7, Color(1.0, 0.5, 0.2))
	prop("pot_enamel_01", Vector3(x1 - 0.35, 0.1, (z0 + z1) * 0.5), 0.0)
	prop("barrel_03", Vector3(x0 + 0.4, 0.0, z0 + 0.4), 0.0)
	prop("wooden_bucket_01", Vector3(x1 - 0.9, 0.0, z0 + 0.4), 0.0)
	shelves(x0 + 0.2, x0 + 1.4, z0, 0.3, 1.6, 2, false, 1.0, true, 0.6)
	spot("work", Vector3(x1 - 1.1, 0.0, (z0 + z1) * 0.5), Vector3(1, 0, 0), {"work": "cook"})

func _f_tent() -> void:
	var m := R("tent")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z1 := rc.end.y
	inn.tint = Color(0.55, 0.5, 0.4, 0.3)
	inn.box("cloth", Vector3(x0 + 0.1, 0.0, z1 - 2.0), Vector3(x0 + 0.85, 0.35, z1 - 0.1))
	paint(col_wall, inn)
	spot("bed", Vector3(x0 + 0.47, 0.0, z1 - 1.0), Vector3(0, 0, 1), {"lie_height": 0.35})
	if x1 - x0 > 2.6:
		inn.tint = Color(0.5, 0.45, 0.38, 0.3)
		inn.box("cloth", Vector3(x1 - 0.85, 0.0, z1 - 2.0), Vector3(x1 - 0.1, 0.35, z1 - 0.1))
		paint(col_wall, inn)
		spot("bed", Vector3(x1 - 0.47, 0.0, z1 - 1.0), Vector3(0, 0, 1), {"lie_height": 0.35})
	prop("wooden_crate_01", Vector3(0.0, ground_local(0.0, z1 - 0.4), z1 - 0.4), 0.0)
	prop("wooden_lantern_01", Vector3(0.0, ground_local(0.0, z1 - 0.4) + 0.35, z1 - 0.4), 0.0)
	prop("folding_wooden_stool", Vector3(0.3, ground_local(0.3, 1.0), 1.0), 30.0)

func _f_generic() -> void:
	var m: Dictionary = rec.rooms[0]
	var rc: Rect2 = m.rect
	if rc.size.x * rc.size.y < 6.0:
		return
	table_chairs(rc.position.x + rc.size.x * 0.5, rc.position.y + rc.size.y * 0.5, m.y, false, 2)
	crates_pile(rc.end.x - 1.0, rc.end.y - 0.9, m.y, 3)

func _f_warehouse() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	for i in 4:
		crates_pile(rc.position.x + 1.2 + (i % 2) * (rc.size.x - 2.4), rc.position.y + 1.5 + (i / 2) * (rc.size.y - 3.0), 0.0, 5)
	prop("wooden_barrels_01", Vector3(rc.position.x + rc.size.x * 0.5, 0.0, rc.position.y + rc.size.y * 0.5), 0.0, 0.6)
	sacks(rc.position.x + rc.size.x * 0.5, rc.end.y - 0.6, 0.0, 6)
	spot("work", Vector3(rc.position.x + rc.size.x * 0.5, 0.0, rc.position.y + 2.0), Vector3(0, 0, 1), {"work": "freight"})

func _f_assay() -> void:
	_f_post()
	var m := R("main")
	var rc: Rect2 = m.rect
	inn.tint = Color(1, 1, 1, 0.2)
	inn.box("iron", Vector3(rc.end.x - 1.2, 0.0, rc.end.y - 1.0), Vector3(rc.end.x - 0.2, 1.3, rc.end.y - 0.1))
	inn.box("brass", Vector3(rc.position.x + 1.0, 1.05, rc.position.y + 3.3), Vector3(rc.position.x + 1.4, 1.35, rc.position.y + 3.6))
	paint(col_wall, inn)
	solid(Vector3(rc.end.x - 1.2, 0.0, rc.end.y - 1.0), Vector3(rc.end.x - 0.2, 1.3, rc.end.y - 0.1))

func _f_cantina() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	var x0 := rc.position.x
	var x1 := rc.end.x
	var z0 := rc.position.y
	var z1 := rc.end.y
	counter(x0 + 0.3, z1 - 1.8, x1 - 1.2, z1 - 1.3, 1.05, "planks_brown", "dark_planks")
	shelves(x0 + 0.3, x1 - 1.2, z1, 0.3, 1.8, 3, false, -1.0)
	spot("bartender", Vector3((x0 + x1) * 0.5, 0.0, z1 - 0.8), Vector3(0, 0, -1), {"work": "bar"})
	for i in 3:
		spot("bar_patron", Vector3(x0 + 1.0 + i * 1.0, 0.0, z1 - 2.4), Vector3(0, 0, 1), {"lean": true})
	table_chairs(x0 + 1.5, z0 + 1.5, 0.0, true, 4)
	if x1 - x0 > 5.0:
		table_chairs(x1 - 1.5, z0 + 1.5, 0.0, true, 3, true)
	prop("wine_barrel_01", Vector3(x1 - 0.5, 0.0, z1 - 0.5), 0.0)
	prop("jug_01", Vector3(x0 + 1.0, 1.05, z1 - 1.55), 0.0)
	prop("lantern_chandelier_01", Vector3((x0 + x1) * 0.5, 2.7, (z0 + z1) * 0.5), 0.0, 0.8)

func _f_boarding() -> void:
	var m := R("main")
	var rc: Rect2 = m.rect
	var n := int((rc.size.y - 1.0) / 1.4)
	for i in n:
		bed(rc.position.x + 0.6, rc.position.y + 0.9 + i * 1.4, 0.0, 90.0)
		if rc.size.x > 4.5:
			bed(rc.end.x - 0.6, rc.position.y + 0.9 + i * 1.4, 0.0, -90.0)
	stove(rc.position.x + rc.size.x * 0.5, rc.end.y - 0.6, 0.0, 3.0)
	_upper_rooms()
