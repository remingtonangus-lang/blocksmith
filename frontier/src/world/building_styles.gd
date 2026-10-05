class_name BuildingStyles
extends BuildingGen
## Exterior styles of the 1899 kit (see building_gen.gd for the frame conventions). Each style builds the shell
## (floor, foundation, walls with real openings, roof, porch/boardwalk, steps, signs, far-LOD shell) and declares
## rooms; furnish() (interiors.gd) fills them.

## Entry point: build one structure from a layout spec. sinks: {ext, inn, far, props, oprops}.
func build(s: Dictionary, sinks: Dictionary) -> Dictionary:
	begin(s, sinks)
	var style: String = s.get("style", "false_front")
	if has_method("_s_" + style):
		call("_s_" + style)
	else:
		push_warning("settlements: unknown style " + style)
	if rec.enterable or s.has("interior"):
		furnish()
	return rec

## Overridden in interiors.gd.
func furnish() -> void:
	pass

# ------------------------------------------------------------------------------------------------ shell helpers

## The four walls of a rectangle as frames: front (z0, faces -z), right (x1), back (z1), left (x0).
func frames4(x0: float, z0: float, x1: float, z1: float, t := T_WALL) -> Dictionary:
	return {"front": frame(Vector2(x1, z0), Vector2(x0, z0), t), "right": frame(Vector2(x1, z1), Vector2(x1, z0), t),
		"back": frame(Vector2(x0, z1), Vector2(x1, z1), t), "left": frame(Vector2(x0, z0), Vector2(x0, z1), t)}

## Build a side from items: [{k: "door"|"window"|"open"|"blank", c: s-centre, w, v0, v1, style, shutters, double, transom, dstyle}].
func side(f: Dictionary, y0: float, y1: float, items: Array, mo: String, mi: String, coll := true) -> void:
	var ops := []
	for it in items:
		var hw: float = it.w * 0.5
		var k: String = it.get("k", "window")
		if k == "blank":
			continue
		ops.append({"s0": it.c - hw, "s1": it.c + hw, "v0": it.get("v0", 0.0), "v1": it.v1, "kind": k})
	wall(f, y0, y1, ops, mo, mi, "", coll)
	for it in items:
		var k: String = it.get("k", "window")
		if k == "window":
			window(f, it.c - it.w * 0.5, it.c + it.w * 0.5, it.v0, it.v1, it.get("style", "double_hung"), it.get("shutters", false))
		elif k == "door":
			door(f, it.c, it.w, it.v1 - it.get("v0", 0.0) - (0.52 if it.get("transom", false) else 0.0), it.get("dstyle", "panel"),
				it.get("double", false), it.get("transom", false), it.get("v0", 0.0))

## Evenly spaced windows along a side of length L, keeping clear of [skip0, skip1] (s range).
func win_row(L: float, v0: float, v1: float, n: int, ww := 0.8, style := "double_hung", shutters := false, margin := 0.9) -> Array:
	var out := []
	if n <= 0 or L < ww + margin * 2.0:
		return out
	for i in n:
		var c := lerpf(margin + ww * 0.5, L - margin - ww * 0.5, (i + 0.5) / n) if n > 1 else L * 0.5
		if n > 1:
			c = margin + ww * 0.5 + (L - 2.0 * margin - ww) * float(i) / (n - 1)
		out.append({"k": "window", "c": c, "w": ww, "v0": v0, "v1": v1, "style": style, "shutters": shutters})
	return out

func _wins_for(L: float, density := 2.6) -> int:
	return clampi(int(L / density), 1, 6)

# ------------------------------------------------------------------------------------------------ false-front store

func _s_false_front() -> void:
	var H: float = spec.get("h", STOREY)
	var pd: float = spec.get("porch", 2.8)
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var pitch := 20.0
	var ridge := H + w * 0.5 * tan(deg_to_rad(pitch))
	var Hf: float = maxf(spec.get("front_h", H + 1.9), ridge + 0.45)
	var fr := frames4(x0, 0.0, x1, d)
	floor_slab(x0, 0.0, x1, d, 0.0)
	skirt(x0, 0.0, x1, d)
	var narrow := w < 6.6
	var items := []
	var dc := w * 0.5 if not narrow else w * 0.68
	var dw := 1.5 if not narrow else 1.0
	items.append({"k": "door", "c": dc, "w": dw, "v1": 2.3 + 0.52, "double": not narrow, "transom": true,
		"dstyle": "glazed"})
	if narrow:
		items.append({"k": "window", "c": w * 0.28, "w": w * 0.38, "v0": 0.6, "v1": 2.65, "style": "display"})
	else:
		var ww := (w - dw) * 0.5 - 0.9
		items.append({"k": "window", "c": 0.45 + ww * 0.5, "w": ww, "v0": 0.6, "v1": 2.65, "style": "display"})
		items.append({"k": "window", "c": w - 0.45 - ww * 0.5, "w": ww, "v0": 0.6, "v1": 2.65, "style": "display"})
	side(fr.front, 0.0, H, items, mat_wall, mat_in)
	# kick panels under display windows
	paint(col_trim)
	for it in items:
		if it.k == "window":
			_fbox(fr.front, "boards_v", it.c - it.w * 0.5, it.c + it.w * 0.5, 0.05, 0.55, 0.0, 0.03)
	paint(col_wall)
	var sidewin: bool = spec.get("side_windows", true)
	var nwin := _wins_for(d - 2.0, 3.2) if sidewin else 0
	side(fr.left, 0.0, H, win_row(d, 0.9, 2.3, nwin), mat_wall, mat_in)
	side(fr.right, 0.0, H, win_row(d, 0.9, 2.3, nwin), mat_wall, mat_in)
	side(fr.back, 0.0, H, [{"k": "door", "c": w * 0.7, "w": 0.95, "v1": DOOR_H, "dstyle": "plank"},
		{"k": "window", "c": w * 0.28, "w": 0.75, "v0": 1.0, "v1": 2.2, "style": "small"}], mat_wall, mat_in)
	ceiling(x0, 0.0, x1, d, H - 0.02, "planks_v")
	# roof hidden behind the false front, gable at the back
	gable_roof(x0, 0.0, x1, d, H, pitch, "z", 0.3, "", "", "planks_v", false, true)
	# the false front itself (above the porch roof up to Hf), back side raw boards with braces
	var top_shape: String = spec.get("top", rand_pick(["flat", "stepped", "pediment", "flat", "curved"]))
	_false_front_top(fr.front, H, Hf, top_shape)
	corner_boards(x0, 0.0, x1, d, -0.05, H)
	# boardwalk with awning
	var awn: String = spec.get("awning", "shed")
	boardwalk(x0, x1, pd, awn, 3.3, 3.0, [0.0 if not narrow else x1 - dc], spec.get("end_steps", true))
	# sign on the false front above the awning
	var sign_txt: String = spec.get("sign", "")
	if sign_txt != "":
		sign_board(fr.front, w * 0.5, (3.45 + Hf) * 0.5 + 0.1, minf(w - 0.6, 8.0), minf(Hf - 3.8, 1.3), sign_txt, spec.get("sign_style", -1), spec.get("font", "Rye"), 0.03)
	if spec.has("sign2"):
		hanging_sign(x0 + 0.6, -pd * 0.55, 2.55, 1.3, 0.45, spec.sign2)
	if spec.get("porch_lamp", true):
		lantern_mesh(Vector3((w * 0.5 - dc) + dw * 0.5 + 0.45, 2.55, -0.25))
		light(Vector3(0.0, 2.6, -0.6), "porch", 7.0, 0.9)
	# far shell
	far_box(x0, 0.0, x1, d, -0.6, H, mat_wall, col_wall)
	far_gable(x0, 0.0, x1, d, H, ridge, "z", mat_roof)
	far_box(x0, -0.05, x1, 0.15, H, Hf, mat_wall, col_wall)
	far_box(x0, -pd, x1, 0.0, 3.0, 3.3, "roof_planks")
	# rooms
	var back := clampf(d * 0.25, 2.5, 4.0)
	room("main", x0 + T_WALL, T_WALL, x1 - T_WALL, d - back, 0.0)
	room("back", x0 + T_WALL, d - back + T_WALL, x1 - T_WALL, d - T_WALL, 0.0)
	inner_partition_x(d - back, x0 + T_WALL, x1 - T_WALL, 0.0, H - 0.02, w * 0.25, 0.95)

## Facade above the main wall: plain, stepped, pediment or curved (stepped approximation) top + cornice.
func _false_front_top(f: Dictionary, H: float, Hf: float, shape: String) -> void:
	var t := 0.12
	var L: float = f.L
	var face_key := mat_wall
	var tops := []        # [s0, s1, top]
	match shape:
		"stepped":
			tops = [[0.0, L * 0.2, Hf - 0.5], [L * 0.2, L * 0.8, Hf], [L * 0.8, L, Hf - 0.5]]
		"pediment":
			tops = [[0.0, L, Hf - 0.35]]
		"curved":
			var n := 7
			for i in n:
				var a := float(i) / n
				var b := float(i + 1) / n
				var m := (a + b) * 0.5
				tops.append([L * a, L * b, Hf - 0.6 + 0.6 * sin(m * PI)])
		_:
			tops = [[0.0, L, Hf]]
	for tp in tops:
		var s0: float = tp[0]
		var s1: float = tp[1]
		var top: float = tp[2]
		ext.face(face_key, fp(f, s0, H), f.dir * (s1 - s0), Vector3.UP * (top - H))
		ext.face("planks_raw", fp(f, s1, H, -t), -f.dir * (s1 - s0), Vector3.UP * (top - H))
		paint(col_trim)
		_fbox(f, "paint", s0 - (0.08 if s0 == 0.0 else 0.0), s1 + (0.08 if s1 >= L - 0.01 else 0.0), top - 0.08, top + 0.05, -t, 0.18)
		_fbox(f, "paint", s0, s1, top - 0.32, top - 0.08, 0.0, 0.06)
		paint(col_wall)
	if shape == "pediment":
		var base := Hf - 0.35
		var peak := Hf + 0.55
		ext.tri(face_key, fp(f, 0.15 * L, base), fp(f, 0.85 * L, base), fp(f, 0.5 * L, peak))
		ext.tri("planks_raw", fp(f, 0.85 * L, base, -t), fp(f, 0.15 * L, base, -t), fp(f, 0.5 * L, peak, -t))
		paint(col_trim)
		ext.beam("paint", fp(f, 0.13 * L, base + 0.02, 0.05), fp(f, 0.5 * L, peak + 0.04, 0.05), 0.12, 0.1, f.out)
		ext.beam("paint", fp(f, 0.5 * L, peak + 0.04, 0.05), fp(f, 0.87 * L, base + 0.02, 0.05), 0.12, 0.1, f.out)
		paint(col_wall)
	# side edges and braces behind
	paint(col_trim)
	_fbox(f, "paint", -0.02, 0.1, H, Hf - (0.5 if shape == "stepped" else 0.0), 0.0, 0.04)
	_fbox(f, "paint", L - 0.1, L + 0.02, H, Hf - (0.5 if shape == "stepped" else 0.0), 0.0, 0.04)
	# brackets under the cornice
	var nb := int(L / 0.9)
	var main_top: float = Hf if shape != "curved" and shape != "pediment" else Hf - 0.35
	for i in nb:
		var s := 0.45 + i * (L - 0.9) / maxf(nb - 1, 1)
		_fbox(f, "paint", s - 0.05, s + 0.05, main_top - 0.42, main_top - 0.32, 0.0, 0.14)
	paint(col_wall)
	for s in [L * 0.25, L * 0.75]:
		ext.beam("planks_raw", fp(f, s, Hf - 0.4, -t - 0.05), fp(f, s, H - 0.1, -t - 1.4), 0.08, 0.12, f.dir)
	solid_obb(fp(f, L * 0.5, (H + Hf) * 0.5, -t * 0.5), Vector3(L, Hf - H, t), fbasis(f))

## Interior partition wall across x at z with a doorway (centre dx, width dw), finished both sides.
func inner_partition_x(z: float, x0: float, x1: float, y0: float, y1: float, dx: float, dw: float, key := "") -> void:
	if key == "":
		key = mat_in
	var t := 0.1
	var ops := [{"s0": dx - dw * 0.5 - x0, "s1": dx + dw * 0.5 - x0, "v0": y0, "v1": y0 + DOOR_H, "kind": "door"}]
	for r: Rect2 in _rects(x1 - x0, y0, y1, ops):
		var a := Vector3(x0 + r.position.x, r.position.y, z)
		inn.face(key, a + Vector3(r.size.x, 0, 0), Vector3(-r.size.x, 0, 0), Vector3(0, r.size.y, 0))
		inn.face(key, a + Vector3(0, 0, t), Vector3(r.size.x, 0, 0), Vector3(0, r.size.y, 0))
		solid(Vector3(x0 + r.position.x, r.position.y, z), Vector3(x0 + r.position.x + r.size.x, r.position.y + r.size.y, z + t))
	# doorway casing
	paint(col_trim, inn)
	inn.box("paint", Vector3(dx - dw * 0.5 - 0.08, y0, z - 0.02), Vector3(dx - dw * 0.5, y0 + DOOR_H + 0.08, z + t + 0.02))
	inn.box("paint", Vector3(dx + dw * 0.5, y0, z - 0.02), Vector3(dx + dw * 0.5 + 0.08, y0 + DOOR_H + 0.08, z + t + 0.02))
	inn.box("paint", Vector3(dx - dw * 0.5 - 0.08, y0 + DOOR_H, z - 0.02), Vector3(dx + dw * 0.5 + 0.08, y0 + DOOR_H + 0.1, z + t + 0.02))
	paint(col_wall, inn)

## Interior partition along z at x.
func inner_partition_z(x: float, z0: float, z1: float, y0: float, y1: float, dz: float, dw: float, key := "") -> void:
	if key == "":
		key = mat_in
	var t := 0.1
	var ops := []
	if dw > 0.0:
		ops.append({"s0": dz - dw * 0.5 - z0, "s1": dz + dw * 0.5 - z0, "v0": y0, "v1": y0 + DOOR_H, "kind": "door"})
	for r: Rect2 in _rects(z1 - z0, y0, y1, ops):
		var za := z0 + r.position.x
		var zb := za + r.size.x
		inn.face(key, Vector3(x, r.position.y, za), Vector3(0, 0, r.size.x), Vector3(0, r.size.y, 0))
		inn.face(key, Vector3(x + t, r.position.y, zb), Vector3(0, 0, -r.size.x), Vector3(0, r.size.y, 0))
		solid(Vector3(x, r.position.y, za), Vector3(x + t, r.position.y + r.size.y, zb))
	if dw > 0.0:
		paint(col_trim, inn)
		inn.box("paint", Vector3(x - 0.02, y0, dz - dw * 0.5 - 0.08), Vector3(x + t + 0.02, y0 + DOOR_H + 0.08, dz - dw * 0.5))
		inn.box("paint", Vector3(x - 0.02, y0, dz + dw * 0.5), Vector3(x + t + 0.02, y0 + DOOR_H + 0.08, dz + dw * 0.5 + 0.08))
		inn.box("paint", Vector3(x - 0.02, y0 + DOOR_H, dz - dw * 0.5 - 0.08), Vector3(x + t + 0.02, y0 + DOOR_H + 0.1, dz + dw * 0.5 + 0.08))
		paint(col_wall, inn)

func stair_run(hgt: float) -> float:
	return ceil(hgt / 0.19) * 0.27

## Straight interior staircase rising along +z from (x, y0, z0) to y1; returns the run length.
func stair(xc: float, z0: float, y0: float, y1: float, width := 1.0, dir := 1.0) -> float:
	var rise := 0.19
	var n := int(ceil((y1 - y0) / rise))
	rise = (y1 - y0) / n
	var run := 0.27
	paint(Color(0.9, 0.85, 0.8), inn)
	for i in n:
		var za := z0 + dir * run * i
		var zb := za + dir * run
		inn.box("dark_planks", Vector3(xc - width * 0.5, y0, minf(za, zb)), Vector3(xc + width * 0.5, y0 + rise * (i + 1), maxf(za, zb)),
			MeshKit.F_ALL & ~MeshKit.F_NY)
	# stringer/handrail
	paint(col_trim, inn)
	var zend := z0 + dir * run * n
	inn.beam("fine_wood", Vector3(xc + width * 0.5 + 0.04, y0 + 0.95, z0), Vector3(xc + width * 0.5 + 0.04, y1 + 0.95, zend), 0.06, 0.06)
	inn.box("fine_wood", Vector3(xc + width * 0.5 + 0.01, y0, z0 - 0.04 * dir), Vector3(xc + width * 0.5 + 0.08, y0 + 1.05, z0 + 0.04 * dir))
	paint(col_wall, inn)
	ramp(Vector3(xc, y0, z0), Vector3(xc, y1, zend), width)
	return run * n

## Upper floor slab with a rectangular stairwell hole.
func floor_with_hole(x0: float, z0: float, x1: float, z1: float, y: float, hx0: float, hz0: float, hx1: float, hz1: float, key := "floor") -> void:
	floor_slab(x0, z0, hx0, z1, y, key, 0.25)
	floor_slab(hx1, z0, x1, z1, y, key, 0.25)
	floor_slab(hx0, z0, hx1, hz0, y, key, 0.25)
	floor_slab(hx0, hz1, hx1, z1, y, key, 0.25)
	# ceiling of the storey below
	for r in [[x0, z0, hx0, z1], [hx1, z0, x1, z1], [hx0, z0, hx1, hz0], [hx0, hz1, hx1, z1]]:
		ceiling(r[0], r[1], r[2], r[3], y - 0.25, "planks_v")
	# railing around the stairwell (three sides)
	paint(col_trim, inn)
	inn.box("fine_wood", Vector3(hx0 - 0.04, y + 0.9, hz0 - 0.04), Vector3(hx0 + 0.04, y + 0.98, hz1))
	inn.box("fine_wood", Vector3(hx0 - 0.04, y, hz1 - 0.04), Vector3(hx1, y + 0.98, hz1 + 0.04))
	for i in int((hz1 - hz0) / 0.25):
		var zz := hz0 + 0.12 + i * 0.25
		inn.box("fine_wood", Vector3(hx0 - 0.02, y, zz - 0.02), Vector3(hx0 + 0.02, y + 0.9, zz + 0.02), MeshKit.F_SIDES)
	solid(Vector3(hx0 - 0.05, y, hz0 + 1.0), Vector3(hx0 + 0.05, y + 1.0, hz1))
	solid(Vector3(hx0, y, hz1 - 0.05), Vector3(hx1, y + 1.0, hz1 + 0.05))
	paint(col_wall, inn)

# ------------------------------------------------------------------------------------------------ two-storey (saloon, hotel)

func _s_two_storey() -> void:
	var H1: float = spec.get("h", STOREY)
	var H2 := UPPER
	var Ht := H1 + H2
	var pd: float = spec.get("porch", 3.0)
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var fr := frames4(x0, 0.0, x1, d)
	floor_slab(x0, 0.0, x1, d, 0.0)
	skirt(x0, 0.0, x1, d)
	var saloon: bool = spec.get("type", "") == "saloon"
	# ground floor front
	var g_items := []
	if saloon:
		g_items.append({"k": "door", "c": w * 0.5, "w": 1.5, "v1": 2.4, "dstyle": "batwing", "double": true})
		var ww := minf((w - 1.5) * 0.5 - 1.2, 2.4)
		g_items.append({"k": "window", "c": w * 0.5 - 0.75 - 0.7 - ww * 0.5, "w": ww, "v0": 0.7, "v1": 2.7, "style": "tall"})
		g_items.append({"k": "window", "c": w * 0.5 + 0.75 + 0.7 + ww * 0.5, "w": ww, "v0": 0.7, "v1": 2.7, "style": "tall"})
	else:
		g_items.append({"k": "door", "c": w * 0.5, "w": 1.5, "v1": 2.35 + 0.52, "dstyle": "glazed", "double": true, "transom": true})
		g_items += _flank_windows(w, 1.5, 0.75, 0.8, 2.6, 2, "tall")
	side(fr.front, 0.0, H1, g_items, mat_wall, mat_in)
	# upper floor front: balcony door in the middle and windows
	var u_items := [{"k": "door", "c": w * 0.5, "w": 0.95, "v0": H1, "v1": H1 + DOOR_H + 0.1, "dstyle": "glazed"}]
	u_items += _flank_windows(w, 0.95, H1 + 0.8, 0.85, H1 + 2.4, 2 if w > 9.0 else 1, "double_hung", true)
	side(fr.front, H1, Ht, u_items, mat_wall, mat_in)
	var nside := _wins_for(d - 2.0, 3.0)
	side(fr.left, 0.0, H1, win_row(d, 0.9, 2.5, nside, 0.85, "tall"), mat_wall, mat_in)
	side(fr.right, 0.0, H1, win_row(d, 0.9, 2.5, nside, 0.85, "tall"), mat_wall, mat_in)
	side(fr.left, H1, Ht, win_row(d, H1 + 0.8, H1 + 2.4, nside, 0.8, "double_hung", true), mat_wall, mat_in)
	side(fr.right, H1, Ht, win_row(d, H1 + 0.8, H1 + 2.4, nside, 0.8, "double_hung", true), mat_wall, mat_in)
	side(fr.back, 0.0, H1, [{"k": "door", "c": w * 0.75, "w": 0.95, "v1": DOOR_H, "dstyle": "plank"},
		{"k": "window", "c": w * 0.3, "w": 0.8, "v0": 1.0, "v1": 2.3}], mat_wall, mat_in)
	side(fr.back, H1, Ht, win_row(w, H1 + 0.8, H1 + 2.4, 2, 0.8), mat_wall, mat_in)
	corner_boards(x0, 0.0, x1, d, -0.05, Ht)
	paint(col_trim)
	ext.box("paint", Vector3(x0 - 0.03, H1 - 0.12, -0.05), Vector3(x1 + 0.03, H1 + 0.1, d + 0.05), MeshKit.F_SIDES)   # belt course
	paint(col_wall)
	# upper floor with stairwell along the right wall, roof
	var sw := 1.1
	var stair_x := x1 - T_WALL - sw * 0.5 - 0.05
	var run := stair_run(H1)
	var hz0 := d - 1.2 - run
	stair(stair_x, hz0, 0.0, H1, sw)
	floor_with_hole(x0 + T_WALL, T_WALL, x1 - T_WALL, d - T_WALL, H1, stair_x - sw * 0.5 - 0.02, hz0, x1 - T_WALL, d - 1.2)
	ceiling(x0 + T_WALL, T_WALL, x1 - T_WALL, d - T_WALL, Ht - 0.05, "planks_v")
	shed_roof(x0, 0.0, x1, d, Ht + 0.5, Ht + 0.05, 0.15, "roof_planks")
	# parapet false front
	var Hp := Ht + 1.0
	var top_shape: String = spec.get("top", rand_pick(["flat", "pediment", "stepped"]))
	_false_front_top(fr.front, Ht, Hp, top_shape)
	# porch below, balcony above
	var posts := boardwalk(x0, x1, pd, "", 3.3, H1 - 0.1, [0.0], spec.get("end_steps", true))
	paint(col_trim)
	for px in posts:
		ext.box("paint", Vector3(px - 0.08, 0.0, -pd + 0.06), Vector3(px + 0.08, H1 + 2.7, -pd + 0.22), MeshKit.F_SIDES)
		solid(Vector3(px - 0.08, 0.0, -pd + 0.06), Vector3(px + 0.08, H1, -pd + 0.22))
	paint(col_wall)
	ext.box("planks_brown", Vector3(x0, H1 - 0.06, -pd), Vector3(x1, H1, 0.0), MeshKit.F_PY | MeshKit.F_NZ | MeshKit.F_PX | MeshKit.F_NX)
	ext.face("planks_v", Vector3(x0, H1 - 0.25, -pd), Vector3(x1 - x0, 0, 0), Vector3(0, 0, pd))   # porch ceiling
	paint(col_trim)
	ext.box("paint", Vector3(x0, H1 - 0.3, -pd), Vector3(x1, H1 - 0.06, -pd + 0.06))
	paint(col_wall)
	solid(Vector3(x0, H1 - 0.3, -pd), Vector3(x1, H1, 0.0))
	porch_rail(x0 + 0.05, x1 - 0.05, -pd + 0.14, H1, [])
	paint(Color(0.9, 0.88, 0.85))
	shed_roof(x0, -pd, x1, 0.0, H1 + 2.95, H1 + 2.7, 0.2, "corrugated" if rng.randf() < 0.4 else mat_roof, false)
	paint(col_wall)
	spot("balcony", Vector3(w * 0.25, H1, -pd + 0.6), Vector3(0, 0, -1))
	spot("balcony", Vector3(-w * 0.25, H1, -pd + 0.6), Vector3(0, 0, -1))
	# signs: big name on the parapet and painted on the balcony fascia
	var sign_txt: String = spec.get("sign", "")
	if sign_txt != "":
		sign_board(fr.front, w * 0.5, Ht + 0.5, w - 0.8, 0.85, sign_txt, spec.get("sign_style", -1), spec.get("font", "Rye"), 0.03)
	if spec.has("sign2"):
		text(ext, spec.sign2, Vector3(0.0, H1 - 0.18, -pd - 0.005), Vector3(-1, 0, 0), Vector3(0, 0, -1), 0.16, w * 0.7,
			Color(0.95, 0.88, 0.6), "OldStandard-Bold")
	lantern_mesh(Vector3(-0.9, 2.5, -0.3))
	lantern_mesh(Vector3(0.9, 2.5, -0.3))
	light(Vector3(0.0, 2.6, -0.7), "porch", 8.0, 1.1, Color(1.0, 0.66, 0.34), true)
	far_box(x0, 0.0, x1, d, -0.6, Ht, mat_wall, col_wall)
	far_box(x0, -0.05, x1, 0.15, Ht, Hp, mat_wall, col_wall)
	far_box(x0, -pd, x1, 0.0, H1 - 0.3, H1, "planks_brown")
	room("main", x0 + T_WALL, T_WALL, x1 - T_WALL, d - T_WALL, 0.0)
	room("upper", x0 + T_WALL, T_WALL, x1 - T_WALL, d - T_WALL, H1)

func _flank_windows(L: float, dw: float, v0: float, ww: float, v1: float, n: int, style: String, shutters := false) -> Array:
	var out := []
	var side_len := (L - dw) * 0.5 - 0.5
	for sgn: float in [-1.0, 1.0]:
		for i in n:
			var c: float = L * 0.5 + sgn * (dw * 0.5 + 0.5 + side_len * (i + 0.5) / n)
			out.append({"k": "window", "c": c, "w": ww, "v0": v0, "v1": v1, "style": style, "shutters": shutters})
	return out

# ------------------------------------------------------------------------------------------------ brick block (bank, Port Linden)

func _s_brick() -> void:
	var storeys: int = spec.get("storeys", 2)
	var H1: float = spec.get("h", 4.0)
	var Hs := 3.4
	var Ht := H1 + Hs * (storeys - 1)
	var t := 0.3
	var x0 := -w * 0.5
	var x1 := w * 0.5
	mat_wall = spec.get("wall", "brick")
	col_wall = spec.get("paint", Color(1.0, 0.95, 0.92).lerp(Color(0.9, 0.75, 0.68), rng.randf()))
	paint(col_wall)
	var fr := frames4(x0, 0.0, x1, d, t)
	floor_slab(x0, 0.0, x1, d, 0.0, "floor")
	skirt(x0, 0.0, x1, d, 0.0, "stone")
	var pd: float = spec.get("porch", 3.0)
	var bank: bool = spec.get("type", "") == "bank"
	var g_items := []
	if bank:
		g_items.append({"k": "door", "c": w * 0.5, "w": 1.6, "v1": 2.6 + 0.52, "dstyle": "glazed", "double": true, "transom": true})
		g_items += _flank_windows(w, 1.6, 0.9, 1.1, 3.1, 1 if w < 10 else 2, "tall")
	else:
		g_items.append({"k": "door", "c": w * 0.5, "w": 1.5, "v1": 2.5 + 0.52, "dstyle": "glazed", "double": true, "transom": true})
		var ww := (w - 1.5) * 0.5 - 1.2
		g_items.append({"k": "window", "c": 0.6 + ww * 0.5, "w": ww, "v0": 0.55, "v1": 3.0, "style": "display"})
		g_items.append({"k": "window", "c": w - 0.6 - ww * 0.5, "w": ww, "v0": 0.55, "v1": 3.0, "style": "display"})
	side(fr.front, 0.0, H1, g_items, mat_wall, mat_in)
	var nf := clampi(int(w / 2.2), 2, 5)
	for s_i in range(1, storeys):
		var y0 := H1 + Hs * (s_i - 1)
		var items := win_row(w, y0 + 0.75, y0 + 2.55, nf, 0.9, "tall", false, 0.9)
		side(fr.front, y0, y0 + Hs, items, mat_wall, mat_in)
		for it in items:
			paint(Color(0.95, 0.92, 0.85))
			_fbox(fr.front, "stone", it.c - 0.6, it.c + 0.6, it.v1 + 0.02, it.v1 + 0.3, 0.0, 0.06)    # lintel
			_fbox(fr.front, "stone", it.c - 0.55, it.c + 0.55, it.v0 - 0.12, it.v0 - 0.02, 0.0, 0.08)  # sill
			paint(col_wall)
	var nside := _wins_for(d - 2.0, 3.2)
	var sidewin: bool = spec.get("side_windows", true)
	for s_i in storeys:
		var y0 := 0.0 if s_i == 0 else H1 + Hs * (s_i - 1)
		var y1 := H1 if s_i == 0 else y0 + Hs
		var wins := win_row(d, y0 + 0.9, y0 + 2.6, nside if sidewin else 0, 0.85, "tall")
		side(fr.left, y0, y1, wins, mat_wall, mat_in)
		side(fr.right, y0, y1, wins, mat_wall, mat_in)
		var bitems := win_row(w, y0 + 0.9, y0 + 2.6, 2, 0.85, "tall")
		if s_i == 0:
			bitems = [{"k": "door", "c": w * 0.8, "w": 0.95, "v1": DOOR_H, "dstyle": "plank"},
				{"k": "window", "c": w * 0.35, "w": 0.85, "v0": 1.0, "v1": 2.5, "style": "tall"}]
		side(fr.back, y0, y1, bitems, mat_wall, mat_in)
	# storefront: cast-iron pilasters and a sign band
	paint(Color(1, 1, 1, 0))
	for xx in [x0 + 0.05, x1 - 0.05] + ([] if bank else [-0.95, 0.95]):
		ext.box("iron", Vector3(xx - 0.12, 0.0, -0.1), Vector3(xx + 0.12, H1, 0.02), MeshKit.F_SIDES)
		ext.box("iron", Vector3(xx - 0.17, H1 - 0.25, -0.15), Vector3(xx + 0.17, H1 - 0.05, 0.02))
	paint(Color(0.95, 0.92, 0.85))
	ext.box("stone", Vector3(x0 - 0.05, H1 - 0.05, -0.18), Vector3(x1 + 0.05, H1 + 0.6, 0.0), MeshKit.F_SIDES | MeshKit.F_PY | MeshKit.F_NY)
	# cornice: corbelled brick steps + stone cap; parapet
	var Hp := Ht + 0.9
	paint(col_wall)
	ext.box("brick", Vector3(x0, Ht, -0.02), Vector3(x1, Hp, t), MeshKit.F_NZ | MeshKit.F_PY | MeshKit.F_NX | MeshKit.F_PX)
	for k in 3:
		ext.box("brick", Vector3(x0 - 0.02, Ht + 0.15 + k * 0.12, -0.08 - k * 0.07), Vector3(x1 + 0.02, Ht + 0.27 + k * 0.12, 0.0),
			MeshKit.F_NZ | MeshKit.F_PY | MeshKit.F_NY | MeshKit.F_NX | MeshKit.F_PX)
	paint(Color(0.92, 0.9, 0.84))
	ext.box("stone", Vector3(x0 - 0.06, Hp, -0.3), Vector3(x1 + 0.06, Hp + 0.12, t + 0.02))
	for xx in [x0, x1]:
		ext.box("brick", Vector3(xx - 0.02, Ht, 0.0), Vector3(xx + 0.02, Hp, d), MeshKit.F_PY)
	paint(col_wall)
	ext.box("brick", Vector3(x0, Ht, d - t), Vector3(x1, Ht + 0.5, d), MeshKit.F_PZ | MeshKit.F_PY)
	for xx in [[x0, x0 + t], [x1 - t, x1]]:
		ext.box("brick", Vector3(xx[0], Ht, 0.0), Vector3(xx[1], Ht + 0.5, d), MeshKit.F_PX | MeshKit.F_NX | MeshKit.F_PY)
	# floors and roof
	for s_i in range(1, storeys):
		var y := H1 + Hs * (s_i - 1)
		var sx := x1 - t - 0.6
		var hgt := H1 if s_i == 1 else Hs
		var run := stair_run(hgt)
		floor_with_hole(x0 + t, t, x1 - t, d - t, y, sx - 0.55, d - 1.0 - run, x1 - t, d - 1.0)
		stair(sx, d - 1.0 - run, y - hgt, y, 1.0)
	ceiling(x0 + t, t, x1 - t, d - t, Ht - 0.05, "planks_v")
	flat_roof(x0, 0.0, x1, d, Ht)
	# sign band text (painted gold on the stone band)
	var sign_txt: String = spec.get("sign", "")
	if sign_txt != "":
		text(ext, sign_txt.split("\n")[0], Vector3(0.0, H1 + 0.27, -0.185), Vector3(-1, 0, 0), Vector3(0, 0, -1), 0.36, w - 0.8,
			Color(0.25, 0.2, 0.15) if bank else Color(0.2, 0.17, 0.12), "OldStandard-Bold")
	if spec.has("sign2"):
		sign_board(fr.front, w * 0.5, Ht + 0.45, w * 0.6, 0.55, spec.sign2, 3, "Rye", 0.02)
	# sidewalk (boardwalk in front, no roof for banks; awning for shops)
	boardwalk(x0, x1, pd, "" if bank else "shed", 3.6, 3.3, [0.0], spec.get("end_steps", true), "corrugated")
	lantern_mesh(Vector3(-1.1, 2.5, -0.35))
	light(Vector3(0.0, 2.6, -0.8), "porch", 7.0, 0.9)
	far_box(x0, 0.0, x1, d, -0.6, Hp, "brick")
	room("main", x0 + t, t, x1 - t, d - t, 0.0)
	for s_i in range(1, storeys):
		room("upper%d" % s_i, x0 + t, t, x1 - t, d - t, H1 + Hs * (s_i - 1))

# ------------------------------------------------------------------------------------------------ house

func _s_house() -> void:
	var H: float = spec.get("h", 2.9)
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var fy: float = spec.get("raise", 0.5)    # floor above the ground in front
	var pd: float = spec.get("porch", 2.0)
	var axis: String = spec.get("roof_axis", "x" if w >= d * 0.9 else "z")
	var pitch: float = spec.get("pitch", 35.0)
	var fr := frames4(x0, 0.0, x1, d)
	floor_slab(x0, 0.0, x1, d, 0.0)
	skirt(x0, 0.0, x1, d, 0.0, "stone" if rng.randf() < 0.4 else "planks_v")
	var shut: bool = spec.get("shutters", rng.randf() < 0.6)
	var dc := w * 0.5 if w > 6.5 else w * 0.35
	var items := [{"k": "door", "c": dc, "w": 0.95, "v1": DOOR_H, "dstyle": "panel"}]
	if w > 6.5:
		items.append({"k": "window", "c": w * 0.2, "w": 0.85, "v0": 0.85, "v1": 2.25, "shutters": shut})
		items.append({"k": "window", "c": w * 0.8, "w": 0.85, "v0": 0.85, "v1": 2.25, "shutters": shut})
	else:
		items.append({"k": "window", "c": w * 0.72, "w": 0.85, "v0": 0.85, "v1": 2.25, "shutters": shut})
	side(fr.front, 0.0, H, items, mat_wall, mat_in)
	side(fr.left, 0.0, H, win_row(d, 0.85, 2.25, 2 if d > 6.5 else 1, 0.8, "double_hung", shut), mat_wall, mat_in)
	side(fr.right, 0.0, H, win_row(d, 0.85, 2.25, 2 if d > 6.5 else 1, 0.8, "double_hung", shut), mat_wall, mat_in)
	side(fr.back, 0.0, H, [{"k": "door", "c": w * 0.7, "w": 0.9, "v1": DOOR_H, "dstyle": "plank"},
		{"k": "window", "c": w * 0.3, "w": 0.8, "v0": 0.9, "v1": 2.2}], mat_wall, mat_in)
	ceiling(x0, 0.0, x1, d, H - 0.02, "planks_v")
	corner_boards(x0, 0.0, x1, d, -0.05, H)
	var ridge := gable_roof(x0, 0.0, x1, d, H, pitch, axis, 0.4, "", "", "planks_v")
	if axis == "x":
		chimney(x0 + 0.5, d * 0.5, H - 0.5, ridge + 0.7)
	else:
		chimney(w * 0.0, d - 1.2, H - 0.5, ridge + 0.5)
	if pd > 0.0:
		var px0 := x0 if spec.get("porch_full", true) else (w * 0.5 - dc) - 1.4
		var px1 := x1 if spec.get("porch_full", true) else (w * 0.5 - dc) + 1.4
		boardwalk(px0, px1, pd, "shed", H - 0.1, H - 0.45, [(w * 0.5 - dc)], false, "", true)
		if rng.randf() < 0.6:
			prop("Rockingchair_01", Vector3((w * 0.5 - dc) + 1.4, 0.0, -pd * 0.5), 180.0 + rng.randf_range(-20, 20), 1.0, true)
			spot("porch_sit", Vector3((w * 0.5 - dc) + 1.4, 0.0, -pd * 0.5), Vector3(0, 0, -1), {"sit_height": 0.45})
	else:
		steps((w * 0.5 - dc), 0.0, 0.0, 1.2)
	lantern_mesh(Vector3((w * 0.5 - dc) + 0.7, 1.9, -0.2))
	light(Vector3((w * 0.5 - dc), 2.0, -0.6), "porch", 6.0, 0.6)
	far_box(x0, 0.0, x1, d, -0.6, H, mat_wall, col_wall)
	far_gable(x0, 0.0, x1, d, H, ridge, axis, mat_roof)
	var split := d * 0.55
	room("front", x0 + T_WALL, T_WALL, x1 - T_WALL, split, 0.0)
	room("back", x0 + T_WALL, split + 0.1, x1 - T_WALL, d - T_WALL, 0.0)
	inner_partition_x(split, x0 + T_WALL, x1 - T_WALL, 0.0, H - 0.02, (w * 0.5 - dc), 0.9)

# ------------------------------------------------------------------------------------------------ log cabin

func _s_cabin() -> void:
	var H: float = spec.get("h", 2.5)
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var t := 0.26
	mat_wall = "log"
	mat_in = "log"
	paint(Color(0.95, 0.9, 0.85))
	var fr := frames4(x0, 0.0, x1, d, t)
	floor_slab(x0, 0.0, x1, d, 0.0, "planks_brown")
	skirt(x0, 0.0, x1, d, 0.0, "stone")
	side(fr.front, 0.0, H, [{"k": "door", "c": w * 0.4, "w": 0.9, "v1": 1.95, "dstyle": "plank"},
		{"k": "window", "c": w * 0.78, "w": 0.6, "v0": 0.95, "v1": 1.75, "style": "small"}], "log", "log")
	side(fr.left, 0.0, H, win_row(d, 0.95, 1.75, 1, 0.6, "small"), "log", "log")
	side(fr.right, 0.0, H, [], "log", "log")
	side(fr.back, 0.0, H, [], "log", "log")
	# log ends crossing at the corners (alternating courses)
	for c: Vector2 in [Vector2(x0, 0.0), Vector2(x1, 0.0), Vector2(x1, d), Vector2(x0, d)]:
		var sx := signf(c.x)
		var sz := -1.0 if c.y < 0.1 else 1.0
		var k := 0
		var y := 0.15
		while y < H:
			if k % 2 == 0:
				ext.cyl("log", Vector3(c.x - sx * 0.1, y, c.y + sz * 0.02), Vector3(c.x + sx * 0.32, y, c.y + sz * 0.02), 0.14, 6, true)
			else:
				ext.cyl("log", Vector3(c.x + sx * 0.02, y, c.y - sz * 0.1), Vector3(c.x + sx * 0.02, y, c.y + sz * 0.32), 0.14, 6, true)
			y += 0.28
			k += 1
	ceiling(x0, 0.0, x1, d, H - 0.02, "planks_v")
	var ridge := gable_roof(x0 - 0.1, -0.1, x1 + 0.1, d + 0.1, H, 32.0, "x", 0.45, spec.get("roof", "roof_planks"), "log", "log")
	chimney(x1 + 0.25, d * 0.5, -0.4, ridge + 0.5, "stone")
	if spec.get("porch", 0.0) > 0.0:
		boardwalk(x0, x1, spec.porch, "shed", H - 0.05, H - 0.4, [w * 0.1], false, "roof_planks")
	else:
		steps(w * 0.1, 0.0, 0.0, 1.0)
	far_box(x0, 0.0, x1, d, -0.4, H, "log")
	far_gable(x0, 0.0, x1, d, H, ridge, "x", "roof_planks")
	room("main", x0 + t, t, x1 - t, d - t, 0.0)

# ------------------------------------------------------------------------------------------------ church

func _s_church() -> void:
	var H := 4.8
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var tw := 3.4
	col_wall = spec.get("paint", Color(0.96, 0.95, 0.92))
	mat_wall = spec.get("wall", "paint")
	mat_in = "plaster"
	paint(col_wall)
	var fr := frames4(x0, 0.0, x1, d)
	floor_slab(x0, 0.0, x1, d, 0.0)
	skirt(x0, 0.0, x1, d, 0.0, "stone")
	side(fr.front, 0.0, H, [{"k": "window", "c": w * 0.18, "w": 0.7, "v0": 1.4, "v1": 3.6, "style": "tall"},
		{"k": "open", "c": w * 0.5, "w": 1.6, "v0": 0.0, "v1": 2.7},
		{"k": "window", "c": w * 0.82, "w": 0.7, "v0": 1.4, "v1": 3.6, "style": "tall"}], mat_wall, mat_in)
	var nw := clampi(int(d / 3.5), 2, 5)
	side(fr.left, 0.0, H, win_row(d, 1.1, 3.8, nw, 0.9, "tall", false, 1.6), mat_wall, mat_in)
	side(fr.right, 0.0, H, win_row(d, 1.1, 3.8, nw, 0.9, "tall", false, 1.6), mat_wall, mat_in)
	side(fr.back, 0.0, H, [{"k": "door", "c": w * 0.8, "w": 0.9, "v1": DOOR_H, "dstyle": "plank"}], mat_wall, mat_in)
	var ridge := gable_roof(x0, 0.0, x1, d, H, 45.0, "z", 0.45, "shingles", "", "plaster")
	ext.face("planks_v", Vector3(x0, H - 0.02, 0.0), Vector3(w, 0, 0), Vector3(0, 0, d))
	corner_boards(x0, 0.0, x1, d, -0.05, H)
	# tower in front
	var tz0 := -tw
	var tf := frames4(-tw * 0.5, tz0, tw * 0.5, 0.0)
	var Ht := 9.6
	floor_slab(-tw * 0.5, tz0, tw * 0.5, 0.0, 0.0)
	skirt(-tw * 0.5, tz0, tw * 0.5, 0.0, 0.0, "stone")
	side(tf.front, 0.0, Ht, [{"k": "door", "c": tw * 0.5, "w": 1.6, "v1": 2.7, "dstyle": "panel", "double": true},
		{"k": "window", "c": tw * 0.5, "w": 0.6, "v0": 5.0, "v1": 6.6, "style": "tall"}], mat_wall, mat_in)
	side(tf.left, 0.0, Ht, [{"k": "window", "c": tw * 0.5, "w": 0.5, "v0": 5.2, "v1": 6.5, "style": "tall"}], mat_wall, mat_in)
	side(tf.right, 0.0, Ht, [{"k": "window", "c": tw * 0.5, "w": 0.5, "v0": 5.2, "v1": 6.5, "style": "tall"}], mat_wall, mat_in)
	corner_boards(-tw * 0.5, tz0, tw * 0.5, 0.0, -0.05, Ht)
	# belfry: open stage with corner posts and rails, then the spire
	var by := Ht
	ext.box("planks_brown", Vector3(-tw * 0.5 - 0.1, by, tz0 - 0.1), Vector3(tw * 0.5 + 0.1, by + 0.15, 0.1))
	paint(col_trim)
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var px := c.x * (tw * 0.5 - 0.15)
		var pz := tz0 * 0.5 + c.y * (tw * 0.5 - 0.15)
		ext.box("paint", Vector3(px - 0.15, by, pz - 0.15), Vector3(px + 0.15, by + 2.6, pz + 0.15), MeshKit.F_SIDES)
	porch_rail(-tw * 0.5 + 0.3, tw * 0.5 - 0.3, tz0 + 0.15, by + 0.15, [], 0.8)
	porch_rail(-tw * 0.5 + 0.3, tw * 0.5 - 0.3, -0.15, by + 0.15, [], 0.8)
	paint(col_wall)
	ext.box("paint", Vector3(-tw * 0.5 - 0.15, by + 2.6, tz0 - 0.15), Vector3(tw * 0.5 + 0.15, by + 2.9, 0.15))
	ext.tint = Color(1, 1, 1, 0)
	ext.cyl("brass", Vector3(0, by + 1.3, tz0 * 0.5), Vector3(0, by + 2.2, tz0 * 0.5), 0.45, 10, true, 0.22)
	paint(col_wall)
	var sy := by + 2.9
	var ap := Vector3(0, sy + 6.0, tz0 * 0.5)
	var c0 := Vector3(-tw * 0.5 - 0.1, sy, tz0 - 0.1)
	var c1 := Vector3(tw * 0.5 + 0.1, sy, tz0 - 0.1)
	var c2 := Vector3(tw * 0.5 + 0.1, sy, 0.1)
	var c3 := Vector3(-tw * 0.5 - 0.1, sy, 0.1)
	ext.tri("shingles", c1, c0, ap)
	ext.tri("shingles", c2, c1, ap)
	ext.tri("shingles", c3, c2, ap)
	ext.tri("shingles", c0, c3, ap)
	ext.tint = Color(1, 1, 1, 0)
	ext.box("iron", ap + Vector3(-0.03, 0, -0.03), ap + Vector3(0.03, 1.2, 0.03))
	ext.box("iron", ap + Vector3(-0.35, 0.75, -0.03), ap + Vector3(0.35, 0.82, 0.03))
	paint(col_wall)
	ceiling(-tw * 0.5, tz0, tw * 0.5, 0.0, 3.2, "planks_v")
	steps(0.0, tz0, 0.0, 2.4)
	if spec.get("sign", "") != "":
		sign_board(tf.front, tw * 0.5, 3.6, tw - 0.4, 0.5, spec.sign, 1, "OldStandard-Bold", 0.03)
	far_box(x0, 0.0, x1, d, -0.6, H, "paint")
	far_gable(x0, 0.0, x1, d, H, ridge, "z", "shingles")
	far_box(-tw * 0.5, tz0, tw * 0.5, 0.0, -0.6, sy, "paint")
	far.tint = Color(0.3, 0.28, 0.25, 1)
	far.tri("far", c1, c0, ap)
	far.tri("far", c2, c1, ap)
	far.tri("far", c3, c2, ap)
	far.tri("far", c0, c3, ap)
	room("nave", x0 + T_WALL, T_WALL, x1 - T_WALL, d - T_WALL, 0.0)
	room("tower", -tw * 0.5 + T_WALL, tz0 + T_WALL, tw * 0.5 - T_WALL, 0.0, 0.0)

# ------------------------------------------------------------------------------------------------ school

func _s_school() -> void:
	var H := 3.4
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var fr := frames4(x0, 0.0, x1, d)
	floor_slab(x0, 0.0, x1, d, 0.0)
	skirt(x0, 0.0, x1, d, 0.0, "stone")
	side(fr.front, 0.0, H, [{"k": "door", "c": w * 0.5, "w": 1.0, "v1": DOOR_H + 0.1, "dstyle": "panel"}], mat_wall, mat_in)
	side(fr.left, 0.0, H, win_row(d, 0.9, 2.7, 3, 0.9, "tall"), mat_wall, mat_in)
	side(fr.right, 0.0, H, win_row(d, 0.9, 2.7, 3, 0.9, "tall"), mat_wall, mat_in)
	side(fr.back, 0.0, H, [], mat_wall, mat_in)
	var ridge := gable_roof(x0, 0.0, x1, d, H, 35.0, "z", 0.4, "", "", "plaster")
	ceiling(x0, 0.0, x1, d, H - 0.02, "planks_v")
	corner_boards(x0, 0.0, x1, d, -0.05, H)
	# little belfry on the front of the ridge
	var by := ridge - 0.3
	paint(col_trim)
	for c: Vector2 in [Vector2(-0.5, 0.6), Vector2(0.5, 0.6), Vector2(0.5, 1.6), Vector2(-0.5, 1.6)]:
		ext.box("paint", Vector3(c.x - 0.06, by, c.y - 0.06), Vector3(c.x + 0.06, by + 1.4, c.y + 0.06), MeshKit.F_SIDES)
	paint(col_wall)
	ext.box(mat_wall, Vector3(-0.6, by - 0.4, 0.5), Vector3(0.6, by + 0.2, 1.7), MeshKit.F_SIDES)
	gable_roof(-0.6, 0.5, 0.6, 1.7, by + 1.4, 40.0, "z", 0.15, "shingles", mat_wall)
	ext.tint = Color(1, 1, 1, 0)
	ext.cyl("brass", Vector3(0, by + 0.5, 1.1), Vector3(0, by + 1.1, 1.1), 0.28, 8, true, 0.12)
	paint(col_wall)
	boardwalk(-1.3, 1.3, 1.6, "shed", 2.8, 2.5, [0.0], false)
	chimney(0.0, d - 0.6, H - 0.5, ridge + 0.4)
	if spec.get("sign", "") != "":
		sign_board(fr.front, w * 0.5, H + 0.6, 2.2, 0.45, spec.sign, 1, "OldStandard-Bold", 0.03)
	far_box(x0, 0.0, x1, d, -0.6, H, mat_wall, col_wall)
	far_gable(x0, 0.0, x1, d, H, ridge, "z", mat_roof)
	room("class", x0 + T_WALL, T_WALL, x1 - T_WALL, d - T_WALL, 0.0)

# ------------------------------------------------------------------------------------------------ barn / livery stable

func _s_barn() -> void:
	var H: float = spec.get("h", 4.4)
	var x0 := -w * 0.5
	var x1 := w * 0.5
	mat_wall = spec.get("wall", "planks_v")
	var fr := frames4(x0, 0.0, x1, d)
	# dirt floor (no slab): just a low sill; collision floor not needed (terrain)
	var dw := 3.4
	side(fr.front, 0.0, H, [{"k": "open", "c": w * 0.5, "w": dw, "v0": 0.0, "v1": 3.7}], mat_wall, mat_wall)
	side(fr.back, 0.0, H, [{"k": "open", "c": w * 0.5, "w": 2.6, "v0": 0.0, "v1": 3.2}], mat_wall, mat_wall)
	side(fr.left, 0.0, H, win_row(d, 1.8, 2.5, 3, 0.7, "small"), mat_wall, mat_wall)
	side(fr.right, 0.0, H, win_row(d, 1.8, 2.5, 3, 0.7, "small"), mat_wall, mat_wall)
	skirt(x0, 0.0, x1, d, 0.0, "planks_v")
	# sliding doors (slid open, hanging from a track)
	paint(col_trim)
	ext.box("paint", Vector3(x0 + 0.2, 3.75, -0.12), Vector3(x1 - 0.2, 3.85, -0.04))
	paint(col_wall)
	for sgn: float in [-1.0, 1.0]:
		var cx: float = sgn * (dw * 0.5 + dw * 0.25 + 0.05)
		ext.box(mat_wall, Vector3(cx - dw * 0.25, 0.05, -0.12), Vector3(cx + dw * 0.25, 3.7, -0.06))
		paint(col_trim)
		ext.beam("paint", Vector3(cx - dw * 0.25 + 0.1, 0.2, -0.13), Vector3(cx + dw * 0.25 - 0.1, 3.5, -0.13), 0.12, 0.02, Vector3(0, 0, -1))
		ext.beam("paint", Vector3(cx + dw * 0.25 - 0.1, 0.2, -0.13), Vector3(cx - dw * 0.25 + 0.1, 3.5, -0.13), 0.12, 0.02, Vector3(0, 0, -1))
		paint(col_wall)
		solid(Vector3(cx - dw * 0.25, 0.05, -0.12), Vector3(cx + dw * 0.25, 3.7, -0.06))
	var ridge := gable_roof(x0, 0.0, x1, d, H, 40.0, "z", 0.5, spec.get("roof", "shingles"), mat_wall, mat_wall)
	# hayloft door + hay hood
	paint(col_trim)
	ext.box("paint", Vector3(-0.8, H + 0.3, -0.05), Vector3(0.8, H + 1.9, 0.0))
	paint(col_wall)
	ext.box(mat_roof, Vector3(-0.5, ridge - 0.2, -1.4), Vector3(0.5, ridge + 0.1, 0.0))
	ext.tint = Color(1, 1, 1, 0)
	ext.cyl("iron", Vector3(0, ridge - 0.25, -1.2), Vector3(0, ridge - 1.2, -1.2), 0.012, 4, false)
	paint(col_wall)
	# loft floor over the back half
	floor_slab(x0 + 0.15, d * 0.45, x1 - 0.15, d - 0.15, H - 0.1, "planks_brown", 0.2)
	ext.face("planks_v", Vector3(x0 + 0.15, H - 0.3, d * 0.45), Vector3(w - 0.3, 0, 0), Vector3(0, 0, d * 0.55 - 0.15))
	if spec.get("sign", "") != "":
		sign_board(fr.front, w * 0.5, H - 0.2, minf(w - 1.0, 7.0), 0.55, spec.sign, spec.get("sign_style", -1), "Rye", 0.03)
	far_box(x0, 0.0, x1, d, -0.4, H, mat_wall)
	far_gable(x0, 0.0, x1, d, H, ridge, "z", mat_roof)
	room("stable", x0 + T_WALL, T_WALL, x1 - T_WALL, d - T_WALL, 0.0)
	rec.enterable = true
	spot("door_out", Vector3(0, 0, -1.2), Vector3(0, 0, 1))
	spot("door_in", Vector3(0, 0, 1.2), Vector3(0, 0, -1))

# ------------------------------------------------------------------------------------------------ blacksmith (open-front shop)

func _s_smithy() -> void:
	var H := 3.8
	var x0 := -w * 0.5
	var x1 := w * 0.5
	mat_wall = spec.get("wall", "planks_raw")
	var fr := frames4(x0, 0.0, x1, d)
	side(fr.left, 0.0, H - 0.6, win_row(d, 1.2, 2.2, 1, 0.8, "small"), mat_wall, mat_wall)
	side(fr.right, 0.0, H - 0.6, [], mat_wall, mat_wall)
	side(fr.back, 0.0, H - 0.6, [], mat_wall, mat_wall)
	# side walls rise with the roof slope
	ext.tri(mat_wall, Vector3(x0, H - 0.6, d), Vector3(x0, H, 0.0), Vector3(x0, H - 0.6, 0.0))
	ext.tri(mat_wall, Vector3(x1, H - 0.6, 0.0), Vector3(x1, H, 0.0), Vector3(x1, H - 0.6, d))
	paint(Color(0.75, 0.7, 0.62))
	for px in [x0 + 0.1, 0.0, x1 - 0.1]:
		ext.box("planks_brown", Vector3(px - 0.1, 0.0, -0.1), Vector3(px + 0.1, H, 0.1), MeshKit.F_SIDES)
		solid(Vector3(px - 0.1, 0.0, -0.1), Vector3(px + 0.1, H, 0.1))
	ext.box("planks_brown", Vector3(x0, H - 0.3, -0.12), Vector3(x1, H, 0.12))
	paint(col_wall)
	shed_roof(x0, 0.0, x1, d, H, H - 0.6, 0.4, spec.get("roof", "corrugated"))
	if spec.get("sign", "") != "":
		text(ext, spec.sign, Vector3(0, H - 0.15, -0.125), Vector3(-1, 0, 0), Vector3(0, 0, -1), 0.24, w - 1.0, Color(0.92, 0.88, 0.75), "Rye")
	far_box(x0, 0.0, x1, d, -0.4, H - 0.6, mat_wall)
	far_box(x0, 0.0, x1, d, H - 0.6, H - 0.4, "corrugated")
	room("shop", x0 + T_WALL, 0.2, x1 - T_WALL, d - T_WALL, 0.0)
	rec.enterable = true
	rec.interior_floor = "ground"

# ------------------------------------------------------------------------------------------------ railroad depot

func _s_depot() -> void:
	var H := 3.7
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var fr := frames4(x0, 0.0, x1, d)
	floor_slab(x0, 0.0, x1, d, 0.0)
	skirt(x0, 0.0, x1, d, 0.0, "stone")
	var items := [{"k": "door", "c": w * 0.62, "w": 1.0, "v1": 2.3 + 0.52, "dstyle": "glazed", "transom": true},
		{"k": "window", "c": w * 0.5, "w": 0.9, "v0": 0.85, "v1": 2.6, "style": "tall"},
		{"k": "window", "c": w * 0.38, "w": 0.9, "v0": 0.85, "v1": 2.6, "style": "tall"},
		{"k": "door", "c": w * 0.12, "w": 2.2, "v1": 2.6, "dstyle": "plank"},
		{"k": "window", "c": w * 0.75, "w": 0.9, "v0": 0.85, "v1": 2.6, "style": "tall"},
		{"k": "window", "c": w * 0.88, "w": 0.9, "v0": 0.85, "v1": 2.6, "style": "tall"}]
	side(fr.front, 0.0, H, items, mat_wall, mat_in)
	side(fr.back, 0.0, H, [{"k": "door", "c": w * 0.4, "w": 1.0, "v1": DOOR_H + 0.1, "dstyle": "panel"}] + win_row(w, 0.9, 2.6, 4, 0.9, "tall", false, 3.0), mat_wall, mat_in)
	side(fr.left, 0.0, H, win_row(d, 0.9, 2.6, 1, 0.9, "tall"), mat_wall, mat_in)
	side(fr.right, 0.0, H, win_row(d, 0.9, 2.6, 1, 0.9, "tall"), mat_wall, mat_in)
	corner_boards(x0, 0.0, x1, d, -0.05, H)
	# board-and-batten lower band
	paint(col_trim)
	ext.box("paint", Vector3(x0 - 0.02, 1.0, -0.03), Vector3(x1 + 0.02, 1.08, d + 0.03), MeshKit.F_SIDES)
	paint(col_wall)
	ceiling(x0, 0.0, x1, d, H - 0.02, "planks_v")
	var ridge := gable_roof(x0, 0.0, x1, d, H, 28.0, "x", 2.2, spec.get("roof", "shingles"), "", "planks_v")
	# eave brackets
	paint(col_trim)
	for i in int(w / 2.0) + 1:
		var bx := x0 + 0.3 + i * (w - 0.6) / int(w / 2.0)
		for zz in [[0.0, -1.0], [d, 1.0]]:
			ext.beam("paint", Vector3(bx, H - 1.1, zz[0]), Vector3(bx, H - 0.05, zz[0] + zz[1] * 1.4), 0.1, 0.1, Vector3(1, 0, 0))
	paint(col_wall)
	# platform along the track side
	var pdp: float = spec.get("porch", 4.5)
	ext.box("planks_brown", Vector3(x0 - 6.0, -0.06, -pdp), Vector3(x1 + 6.0, 0.0, 0.0), MeshKit.F_PY | MeshKit.F_NZ | MeshKit.F_PX | MeshKit.F_NX)
	solid(Vector3(x0 - 6.0, -0.4, -pdp), Vector3(x1 + 6.0, 0.0, 0.0))
	var g := ground_min(x0 - 6.0, -pdp, x1 + 6.0, -pdp + 0.3)
	ext.box("planks_v", Vector3(x0 - 6.0, g - 0.3, -pdp + 0.02), Vector3(x1 + 6.0, -0.06, -pdp + 0.06), MeshKit.F_NZ)
	steps_x(x0 - 6.0, -pdp * 0.5, 0.0, pdp - 0.4, -1.0)
	steps_x(x1 + 6.0, -pdp * 0.5, 0.0, pdp - 0.4, 1.0)
	# station name boards on both gable ends and over the platform
	var town_name: String = spec.get("sign", "")
	if town_name != "":
		sign_board(fr.left, d * 0.5, H + 0.7, d * 0.7, 0.6, town_name, 1, "OldStandard-Bold", 0.02)
		sign_board(fr.right, d * 0.5, H + 0.7, d * 0.7, 0.6, town_name, 1, "OldStandard-Bold", 0.02)
		sign_board(fr.front, w * 0.5, H - 0.45, 4.2, 0.5, town_name, 1, "OldStandard-Bold", 0.03)
	for i in 3:
		var lx := x0 + w * (0.2 + 0.3 * i)
		lantern_mesh(Vector3(lx, 2.8, -1.4))
		light(Vector3(lx, 2.9, -1.4), "porch", 8.0, 0.9)
	spot("platform", Vector3(-w * 0.2, 0.0, -pdp + 1.0), Vector3(0, 0, -1))
	spot("platform", Vector3(w * 0.25, 0.0, -pdp + 1.0), Vector3(0, 0, -1))
	far_box(x0, 0.0, x1, d, -0.6, H, mat_wall, col_wall)
	far_gable(x0, 0.0, x1, d, H, ridge, "x", mat_roof)
	room("waiting", x0 + w * 0.3, T_WALL, x1 - T_WALL, d - T_WALL, 0.0)
	room("freight", x0 + T_WALL, T_WALL, x0 + w * 0.3, d - T_WALL, 0.0)
	inner_partition_z(x0 + w * 0.3, T_WALL, d - T_WALL, 0.0, H - 0.02, d * 0.5, 1.0)

# ------------------------------------------------------------------------------------------------ adobe

func _s_adobe() -> void:
	var H: float = spec.get("h", 3.1)
	var t := 0.5
	var x0 := -w * 0.5
	var x1 := w * 0.5
	mat_wall = spec.get("wall", "adobe")
	mat_in = "plaster"
	var fr := frames4(x0, 0.0, x1, d, t)
	floor_slab(x0, 0.0, x1, d, 0.0, "planks_brown")
	var dc := w * 0.5 if w > 7.0 else w * 0.35
	var items := [{"k": "door", "c": dc, "w": 1.0, "v1": 2.05, "dstyle": "plank"}]
	if w > 7.0:
		items.append({"k": "window", "c": w * 0.2, "w": 0.7, "v0": 1.0, "v1": 1.9, "style": "adobe"})
		items.append({"k": "window", "c": w * 0.8, "w": 0.7, "v0": 1.0, "v1": 1.9, "style": "adobe"})
	else:
		items.append({"k": "window", "c": w * 0.75, "w": 0.7, "v0": 1.0, "v1": 1.9, "style": "adobe"})
	side(fr.front, 0.0, H, items, mat_wall, mat_in)
	side(fr.left, 0.0, H, win_row(d, 1.0, 1.8, 1, 0.6, "adobe"), mat_wall, mat_in)
	side(fr.right, 0.0, H, win_row(d, 1.0, 1.8, 1, 0.6, "adobe"), mat_wall, mat_in)
	side(fr.back, 0.0, H, [{"k": "door", "c": w * 0.7, "w": 0.9, "v1": 1.95, "dstyle": "plank"}], mat_wall, mat_in)
	# parapet and roof
	var Hp := H + 0.45
	for e in [[x0, 0.0, x1, t], [x0, d - t, x1, d], [x0, 0.0, x0 + t, d], [x1 - t, 0.0, x1, d]]:
		ext.box(mat_wall, Vector3(e[0], H, e[1]), Vector3(e[2], Hp, e[3]), MeshKit.F_ALL & ~MeshKit.F_NY)
	flat_roof(x0 + t, t, x1 - t, d - t, H - 0.25, "roof_planks")
	ext.face("roof_planks", Vector3(x0 + t, H - 0.3, t), Vector3(w - t * 2.0, 0, 0), Vector3(0, 0, d - t * 2.0))
	# vigas through the front and back walls
	paint(Color(0.85, 0.78, 0.68))
	var nv := int(w / 0.9)
	for i in nv:
		var vx := x0 + 0.45 + i * (w - 0.9) / maxf(nv - 1, 1)
		ext.cyl("log", Vector3(vx, H - 0.38, -0.5), Vector3(vx, H - 0.38, 0.2), 0.1, 6, true)
		ext.cyl("log", Vector3(vx, H - 0.38, d - 0.2), Vector3(vx, H - 0.38, d + 0.45), 0.1, 6, true)
		inn.cyl("log", Vector3(vx, H - 0.38, t), Vector3(vx, H - 0.38, d - t), 0.1, 6, false)
	# canales (roof spouts)
	ext.box("dark_planks", Vector3(x0 + 0.8, H - 0.05, -0.6), Vector3(x0 + 1.0, H + 0.08, 0.0))
	ext.box("dark_planks", Vector3(x1 - 1.0, H - 0.05, -0.6), Vector3(x1 - 0.8, H + 0.08, 0.0))
	paint(col_wall)
	# portal (porch) with posts and corbels
	if spec.get("porch", 2.4) > 0.0:
		var pd: float = spec.get("porch", 2.4)
		ext.box("stone", Vector3(x0, -0.3, -pd), Vector3(x1, 0.0, 0.0), MeshKit.F_PY | MeshKit.F_NZ | MeshKit.F_NX | MeshKit.F_PX)
		solid(Vector3(x0, -0.4, -pd), Vector3(x1, 0.0, 0.0))
		paint(Color(0.85, 0.78, 0.68))
		var np := maxi(2, int(w / 2.6) + 1)
		for i in np:
			var px := lerpf(x0 + 0.2, x1 - 0.2, float(i) / (np - 1))
			ext.box("planks_brown", Vector3(px - 0.1, 0.0, -pd + 0.1), Vector3(px + 0.1, 2.55, -pd + 0.3), MeshKit.F_SIDES)
			ext.box("planks_brown", Vector3(px - 0.35, 2.55, -pd + 0.08), Vector3(px + 0.35, 2.7, -pd + 0.32))
			solid(Vector3(px - 0.1, 0.0, -pd + 0.1), Vector3(px + 0.1, 2.55, -pd + 0.3))
		ext.box("planks_brown", Vector3(x0, 2.7, -pd + 0.06), Vector3(x1, 2.9, -pd + 0.34))
		ext.box("roof_planks", Vector3(x0 - 0.1, 2.9, -pd - 0.1), Vector3(x1 + 0.1, 3.0, 0.0))
		for i in int(w / 0.6):
			var lx := x0 + 0.3 + i * 0.6
			ext.cyl("log", Vector3(lx, 2.85, -pd), Vector3(lx, 2.85, 0.0), 0.05, 5, false)
		paint(col_wall)
	if spec.get("sign", "") != "":
		var ff: Dictionary = fr.front
		text(ext, spec.sign, fp(ff, w * 0.5, H - 0.05, 0.005), ff.dir, ff.out, 0.3, w * 0.75, Color(0.35, 0.18, 0.1), "Sancreek-Regular")
	far_box(x0, 0.0, x1, d, -0.3, Hp, mat_wall, col_wall)
	room("main", x0 + t, t, x1 - t, d - t, 0.0)

# ------------------------------------------------------------------------------------------------ tents, sheds, outhouses

func _canvas_quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	ext.quad("canvas", p0, p1, p2, p3)
	ext.quad("canvas", p3, p2, p1, p0)

func _s_tent() -> void:
	var wh: float = spec.get("wall_h", 1.3)
	var rh: float = spec.get("ridge_h", 2.7)
	var x0 := -w * 0.5
	var x1 := w * 0.5
	paint(spec.get("paint", Color(0.95, 0.92, 0.84).lerp(Color(0.8, 0.74, 0.62), rng.randf())))
	# roof
	_canvas_quad(Vector3(x0 - 0.15, wh - 0.05, -0.1), Vector3(x0 - 0.15, wh - 0.05, d + 0.1), Vector3(0, rh, d + 0.1), Vector3(0, rh, -0.1))
	_canvas_quad(Vector3(x1 + 0.15, wh - 0.05, d + 0.1), Vector3(x1 + 0.15, wh - 0.05, -0.1), Vector3(0, rh, -0.1), Vector3(0, rh, d + 0.1))
	# walls
	var g := ground_min(x0, 0.0, x1, d)
	_canvas_quad(Vector3(x0, g, 0.0), Vector3(x0, g, d), Vector3(x0, wh, d), Vector3(x0, wh, 0.0))
	_canvas_quad(Vector3(x1, g, d), Vector3(x1, g, 0.0), Vector3(x1, wh, 0.0), Vector3(x1, wh, d))
	_canvas_quad(Vector3(x0, g, d), Vector3(x1, g, d), Vector3(x1, wh, d), Vector3(x0, wh, d))
	ext.tri("canvas", Vector3(x0, wh, d), Vector3(x1, wh, d), Vector3(0, rh, d))
	ext.tri("canvas", Vector3(x1, wh, d), Vector3(x0, wh, d), Vector3(0, rh, d))
	# front: two flaps tied back leave an opening
	_canvas_quad(Vector3(x1, g, 0.0), Vector3(0.45, g, 0.0), Vector3(0.1, rh - 0.1, 0.0), Vector3(x1, wh, 0.0))
	_canvas_quad(Vector3(-0.45, g, 0.0), Vector3(x0, g, 0.0), Vector3(x0, wh, 0.0), Vector3(-0.1, rh - 0.1, 0.0))
	ext.tri("canvas", Vector3(x1, wh, 0.0), Vector3(0.1, rh - 0.1, 0.0), Vector3(0, rh, 0.0))
	ext.tri("canvas", Vector3(-0.1, rh - 0.1, 0.0), Vector3(x0, wh, 0.0), Vector3(0, rh, 0.0))
	# poles, ridge, guy ropes
	paint(Color(0.8, 0.75, 0.68))
	ext.cyl("planks_raw", Vector3(0, g, -0.05), Vector3(0, rh + 0.25, -0.05), 0.04, 5, true)
	ext.cyl("planks_raw", Vector3(0, g, d + 0.05), Vector3(0, rh + 0.25, d + 0.05), 0.04, 5, true)
	ext.cyl("planks_raw", Vector3(0, rh + 0.02, -0.1), Vector3(0, rh + 0.02, d + 0.1), 0.035, 5, false)
	ext.tint = Color(0.75, 0.7, 0.58, 0.3)
	for zz: float in [0.3, d * 0.5, d - 0.3]:
		for sgn: float in [-1.0, 1.0]:
			var a := Vector3(sgn * (w * 0.5 + 0.15), wh - 0.05, zz)
			var b := Vector3(sgn * (w * 0.5 + 1.3), ground_local(sgn * (w * 0.5 + 1.3), zz) + 0.1, zz)
			ext.beam("canvas", a, b, 0.012)
			ext.box("planks_raw", b + Vector3(-0.03, -0.25, -0.03), b + Vector3(0.03, 0.12, 0.03), MeshKit.F_SIDES | MeshKit.F_PY)
	paint(col_wall)
	if spec.get("floor", false):
		floor_slab(x0 + 0.05, 0.05, x1 - 0.05, d - 0.05, 0.0, "planks_raw", 0.15)
		skirt(x0 + 0.05, 0.05, x1 - 0.05, d - 0.05, 0.0, "planks_raw")
	solid(Vector3(x0, g, 0.1), Vector3(x0 + 0.05, wh, d))
	solid(Vector3(x1 - 0.05, g, 0.1), Vector3(x1, wh, d))
	solid(Vector3(x0, g, d - 0.05), Vector3(x1, wh, d))
	if spec.get("sign", "") != "":
		sign_board(frame(Vector2(x1, 0.0), Vector2(x0, 0.0)), w * 0.5, rh - 0.6, w * 0.6, 0.4, spec.sign, spec.get("sign_style", 1), "Rye", 0.06)
	far_box(x0, 0.0, x1, d, -0.2, wh, "canvas")
	far_gable(x0, 0.0, x1, d, wh, rh, "z", "canvas")
	room("tent", x0 + 0.1, 0.3, x1 - 0.1, d - 0.1, 0.0)
	rec.enterable = true
	spot("door_out", Vector3(0, 0, -0.9), Vector3(0, 0, 1))
	spot("door_in", Vector3(0, 0, 0.8), Vector3(0, 0, -1))

func _s_outhouse() -> void:
	w = 1.2
	d = 1.3
	var H := 2.1
	var fr := frames4(-0.6, 0.0, 0.6, 1.3, 0.04)
	mat_wall = "planks_raw"
	floor_slab(-0.6, 0.0, 0.6, 1.3, 0.12, "planks_raw", 0.12)
	side(fr.front, 0.0, H, [{"k": "door", "c": 0.6, "w": 0.75, "v1": 1.85, "dstyle": "outhouse"}], mat_wall, mat_wall)
	side(fr.left, 0.0, H - 0.2, [], mat_wall, mat_wall)
	side(fr.right, 0.0, H - 0.2, [], mat_wall, mat_wall)
	side(fr.back, 0.0, H - 0.2, [], mat_wall, mat_wall)
	ext.tri(mat_wall, Vector3(-0.6, H - 0.2, 1.3), Vector3(-0.6, H, 0.0), Vector3(-0.6, H - 0.2, 0.0))
	ext.tri(mat_wall, Vector3(0.6, H - 0.2, 0.0), Vector3(0.6, H, 0.0), Vector3(0.6, H - 0.2, 1.3))
	shed_roof(-0.6, 0.0, 0.6, 1.3, H, H - 0.2, 0.12, "roof_planks")
	inn.box("planks_raw", Vector3(-0.55, 0.12, 0.7), Vector3(0.55, 0.55, 1.25))
	spot("outhouse", Vector3(0, 0.12, 0.9), Vector3(0, 0, -1), {"sit_height": 0.45})
	far_box(-0.6, 0.0, 0.6, 1.3, -0.2, H, "planks_raw")

func _s_shed() -> void:
	var H: float = spec.get("h", 2.4)
	var x0 := -w * 0.5
	var x1 := w * 0.5
	mat_wall = spec.get("wall", "planks_raw")
	var fr := frames4(x0, 0.0, x1, d, 0.05)
	side(fr.front, 0.0, H, [{"k": "door", "c": w * 0.5, "w": 1.0, "v1": 1.95, "dstyle": "plank"}], mat_wall, mat_wall)
	side(fr.left, 0.0, H - 0.4, [], mat_wall, mat_wall)
	side(fr.right, 0.0, H - 0.4, [], mat_wall, mat_wall)
	side(fr.back, 0.0, H - 0.4, [], mat_wall, mat_wall)
	ext.tri(mat_wall, Vector3(x0, H - 0.4, d), Vector3(x0, H, 0.0), Vector3(x0, H - 0.4, 0.0))
	ext.tri(mat_wall, Vector3(x1, H - 0.4, 0.0), Vector3(x1, H, 0.0), Vector3(x1, H - 0.4, d))
	floor_slab(x0, 0.0, x1, d, 0.0, "planks_raw", 0.15)
	skirt(x0, 0.0, x1, d, 0.0, "planks_raw")
	shed_roof(x0, 0.0, x1, d, H, H - 0.4, 0.25, spec.get("roof", "corrugated"))
	far_box(x0, 0.0, x1, d, -0.3, H, mat_wall)
	room("shed", x0 + 0.05, 0.05, x1 - 0.05, d - 0.05, 0.0)
