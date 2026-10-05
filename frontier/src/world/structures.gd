class_name SettlementKit
extends BuildingInteriors
## Non-building structures of the kit: railroad water tower, windmill + tank, mining head-frame and ore bin,
## river bridge, lake pier, wagons, corrals, campfire, well, wood/log piles, sawmill, mission ruin, and the street
## furniture pass (lamps, troughs, hitching rails, barrels, benches). Same local-frame conventions as buildings.

# ------------------------------------------------------------------------------------------------ water tower

func _s_water_tower() -> void:
	var r: float = spec.get("radius", 2.8)
	var leg_h: float = spec.get("leg_h", 6.0)
	var th := 4.4
	var half := r * 0.85
	paint(Color(0.85, 0.8, 0.72))
	var tops := []
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var base := Vector3(c.x * (half + 0.5), ground_local(c.x * (half + 0.5), c.y * (half + 0.5)) - 0.3, c.y * (half + 0.5))
		var top := Vector3(c.x * half, leg_h, c.y * half)
		ext.beam("planks_brown", base, top, 0.32, 0.32, Vector3(0, 0, 1))
		ext.box("stone", base + Vector3(-0.35, 0.0, -0.35), base + Vector3(0.35, 0.6, 0.35), MeshKit.F_SIDES | MeshKit.F_PY)
		var mx := (base.x + top.x) * 0.5
		var mz := (base.z + top.z) * 0.5
		solid(Vector3(mx - 0.3, base.y, mz - 0.3), Vector3(mx + 0.3, leg_h, mz + 0.3))
		tops.append([base, top])
	# girts and X braces between legs
	for i in 4:
		var a: Array = tops[i]
		var b: Array = tops[(i + 1) % 4]
		for f in [0.33, 0.66]:
			var pa: Vector3 = a[0].lerp(a[1], f)
			var pb: Vector3 = b[0].lerp(b[1], f)
			ext.beam("planks_brown", pa, pb, 0.12, 0.18)
		ext.beam("planks_brown", a[0].lerp(a[1], 0.05), b[0].lerp(b[1], 0.62), 0.08, 0.14)
		ext.beam("planks_brown", b[0].lerp(b[1], 0.05), a[0].lerp(a[1], 0.62), 0.08, 0.14)
	# deck, tank (vertical staves), hoops, conical roof
	ext.box("planks_brown", Vector3(-half - 0.6, leg_h - 0.25, -half - 0.6), Vector3(half + 0.6, leg_h, half + 0.6))
	paint(Color(0.75, 0.7, 0.62))
	ext.cyl("planks_v", Vector3(0, leg_h, 0), Vector3(0, leg_h + th, 0), r, 18, true)
	ext.tint = Color(1, 1, 1, 0.3)
	for k in 5:
		var hy := leg_h + 0.3 + k * (th - 0.6) / 4.0
		ext.cyl("iron", Vector3(0, hy, 0), Vector3(0, hy + 0.06, 0), r + 0.025, 18, false)
	paint(Color(0.8, 0.75, 0.7))
	ext.cyl("shingles", Vector3(0, leg_h + th, 0), Vector3(0, leg_h + th + 1.4, 0), r + 0.25, 18, true, 0.15)
	# spout towards the track (-z) and a ladder
	paint(Color(0.85, 0.8, 0.72))
	ext.beam("planks_brown", Vector3(0, leg_h + 0.6, -r), Vector3(0, leg_h - 1.0, -r - 2.6), 0.28, 0.28, Vector3(1, 0, 0))
	ext.tint = Color(1, 1, 1, 0.3)
	ext.cyl("iron", Vector3(0, leg_h - 1.0, -r - 2.6), Vector3(0, leg_h - 1.5, -r - 2.9), 0.16, 8, true)
	ext.cyl("iron", Vector3(0.3, leg_h + th, -r * 0.7), Vector3(0.3, leg_h - 0.8, -r - 2.4), 0.012, 4, false)
	paint(Color(0.85, 0.8, 0.72))
	var lx := half + 0.5
	for sx: float in [-0.25, 0.25]:
		ext.beam("planks_brown", Vector3(lx, ground_local(lx, sx), sx), Vector3(lx - 0.6, leg_h + th, sx), 0.06, 0.08)
	for k in int((leg_h + th) / 0.35):
		var f := k * 0.35 / (leg_h + th)
		ext.beam("planks_brown", Vector3(lx - 0.6 * f, ground_local(lx, 0) + k * 0.35, -0.25), Vector3(lx - 0.6 * f, ground_local(lx, 0) + k * 0.35, 0.25), 0.04)
	solid(Vector3(-r, leg_h - 0.25, -r), Vector3(r, leg_h + th, r))
	if spec.get("sign", "") != "":
		text(ext, spec.sign, Vector3(0, leg_h + th * 0.55, -r - 0.03), Vector3(-1, 0, 0), Vector3(0, 0, -1), 0.6, r * 1.4, Color(0.92, 0.9, 0.84), "OldStandard-Bold")
	far.tint = Color(0.42, 0.35, 0.28, 1)
	far.cyl("far", Vector3(0, leg_h, 0), Vector3(0, leg_h + th, 0), r, 8, true)
	far.cyl("far", Vector3(0, leg_h + th, 0), Vector3(0, leg_h + th + 1.4, 0), r + 0.2, 8, false, 0.1)
	far_box(-half, -half, half, half, 0.0, leg_h, "planks_brown")
	spot("water_tower", Vector3(0, 0.0, -r - 3.0), Vector3(0, 0, 1))

# ------------------------------------------------------------------------------------------------ windmill + tank

func _s_windmill() -> void:
	var h: float = spec.get("h", 9.0)
	var g := ground_min(-1.3, -1.3, 1.3, 1.3)
	paint(Color(0.8, 0.78, 0.74))
	var legs := []
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var a := Vector3(c.x * 1.3, g - 0.2, c.y * 1.3)
		var b := Vector3(c.x * 0.3, h, c.y * 0.3)
		ext.beam("planks_brown", a, b, 0.12, 0.12)
		legs.append([a, b])
	for k in 6:
		var f := (k + 1) / 7.0
		for i in 4:
			var pa: Vector3 = legs[i][0].lerp(legs[i][1], f)
			var pb: Vector3 = legs[(i + 1) % 4][0].lerp(legs[(i + 1) % 4][1], f)
			ext.beam("planks_brown", pa, pb, 0.05, 0.08)
			var pc: Vector3 = legs[(i + 1) % 4][0].lerp(legs[(i + 1) % 4][1], (k + 2) / 7.0)
			ext.beam("planks_brown", pa, pc, 0.03, 0.05)
	ext.box("planks_brown", Vector3(-0.5, h, -0.5), Vector3(0.5, h + 0.12, 0.5))
	solid(Vector3(-1.3, g, -1.3), Vector3(1.3, h, 1.3))
	# wheel + tail as a separate spinning mesh
	var wk := MeshKit.new()
	wk.xf = Transform3D.IDENTITY
	wk.seed = ext.seed
	wk.tint = Color(0.85, 0.82, 0.78, 0.4)
	var R := 1.7
	for i in 18:
		var a := TAU * i / 18.0
		var dirv := Vector3(cos(a), sin(a), 0)
		var tang := Vector3(-sin(a), cos(a), 0)
		var p0 := dirv * 0.45
		var p1 := dirv * R
		wk.quad("planks_raw", p0 - tang * 0.06, p1 - tang * 0.13, p1 + tang * 0.13 + Vector3(0, 0, -0.08), p0 + tang * 0.06 + Vector3(0, 0, -0.04))
		wk.quad("planks_raw", p0 + tang * 0.06 + Vector3(0, 0, -0.04), p1 + tang * 0.13 + Vector3(0, 0, -0.08), p1 - tang * 0.13, p0 - tang * 0.06)
	wk.tint = Color(1, 1, 1, 0.3)
	wk.cyl("iron", Vector3(0, 0, 0.05), Vector3(0, 0, -0.15), 0.18, 8, true)
	for rr: float in [0.45, R * 0.75, R]:
		for i in 18:
			var a0 := TAU * i / 18.0
			var a1 := TAU * (i + 1) / 18.0
			wk.beam("iron", Vector3(cos(a0), sin(a0), 0) * rr, Vector3(cos(a1), sin(a1), 0) * rr, 0.02)
	var hub := Vector3(0, h + 0.55, -0.75)
	if not rec.has("spinners"):
		rec["spinners"] = []
	rec.spinners.append({"kit": wk, "xf": xf * Transform3D(Basis.IDENTITY, hub), "axis": Vector3(0, 0, 1), "speed": 1.6})
	# head, tail vane, pump rod
	ext.tint = Color(1, 1, 1, 0.3)
	ext.box("iron", Vector3(-0.15, h + 0.12, -0.75), Vector3(0.15, h + 0.75, 0.4))
	ext.beam("iron", Vector3(0, h + 0.5, 0.3), Vector3(0, h + 0.6, 2.4), 0.05)
	paint(Color(0.9, 0.88, 0.84))
	ext.box("paint", Vector3(-0.02, h + 0.2, 1.6), Vector3(0.02, h + 1.1, 2.6))
	ext.tint = Color(1, 1, 1, 0.3)
	ext.cyl("iron", Vector3(0, g, 0), Vector3(0, h, 0), 0.03, 5, false)
	paint(col_wall)
	# tank and trough beside the tower
	paint(Color(0.85, 0.82, 0.78))
	var tg := ground_local(2.8, 0.0)
	ext.cyl("planks_v", Vector3(2.8, tg - 0.1, 0.0), Vector3(2.8, tg + 1.3, 0.0), 1.5, 16, false)
	ext.tint = Color(1, 1, 1, 0.3)
	ext.cyl("iron", Vector3(2.8, tg + 0.3, 0.0), Vector3(2.8, tg + 0.36, 0.0), 1.52, 16, false)
	ext.cyl("iron", Vector3(2.8, tg + 1.0, 0.0), Vector3(2.8, tg + 1.06, 0.0), 1.52, 16, false)
	ext.tint = Color(1, 1, 1, 0)
	ext.cyl("water", Vector3(2.8, tg + 1.1, 0.0), Vector3(2.8, tg + 1.12, 0.0), 1.45, 16, true)
	solid(Vector3(1.3, tg, -1.5), Vector3(4.3, tg + 1.3, 1.5))
	trough(2.8, 2.2, 2.2)
	far.tint = Color(0.5, 0.48, 0.45, 1)
	far.box("far", Vector3(-0.6, 0.0, -0.6), Vector3(0.6, h, 0.6), MeshKit.F_SIDES)
	far.cyl("far", Vector3(0, h + 0.55, -0.8), Vector3(0, h + 0.55, -0.9), 1.7, 8, true)

# ------------------------------------------------------------------------------------------------ mining head-frame

func _s_headframe() -> void:
	var h: float = spec.get("h", 13.0)
	var g := ground_local(0.0, 0.0)
	paint(Color(0.8, 0.72, 0.6))
	# collar around the shaft
	ext.box("planks_brown", Vector3(-1.6, g - 0.1, -1.6), Vector3(1.6, g + 0.35, 1.6), MeshKit.F_SIDES | MeshKit.F_PY)
	ext.tint = Color(0.02, 0.02, 0.02, 0)
	ext.box("cloth", Vector3(-1.1, g + 0.35, -1.1), Vector3(1.1, g + 0.36, 1.1), MeshKit.F_PY)
	paint(Color(0.8, 0.72, 0.6))
	solid(Vector3(-1.6, g - 0.1, -1.6), Vector3(1.6, g + 1.2, 1.6))
	# two tall leg pairs leaning together, backstays to the hoist house (+z)
	for sx: float in [-1.0, 1.0]:
		ext.beam("planks_brown", Vector3(sx * 1.4, g, -1.4), Vector3(sx * 0.7, h, -0.3), 0.3, 0.3)
		ext.beam("planks_brown", Vector3(sx * 1.4, g, 1.4), Vector3(sx * 0.7, h, 0.3), 0.3, 0.3)
		ext.beam("planks_brown", Vector3(sx * 1.6, ground_local(sx * 1.6, 9.0), 9.0), Vector3(sx * 0.7, h - 0.4, 0.0), 0.28, 0.28)
		for k in 4:
			var f := (k + 1) / 5.0
			var a := Vector3(sx * 1.4, g, -1.4).lerp(Vector3(sx * 0.7, h, -0.3), f)
			var b := Vector3(sx * 1.4, g, 1.4).lerp(Vector3(sx * 0.7, h, 0.3), f)
			ext.beam("planks_brown", a, b, 0.1, 0.16)
			solid(a - Vector3(0.15, 0.15, 0.15), a + Vector3(0.15, 0.15, 0.15))
		solid(Vector3(sx * 1.4 - 0.2, g, -1.6), Vector3(sx * 1.4 + 0.2, g + 3.0, 1.6))
	for k in 5:
		var f := (k + 1) / 6.0
		var y := g + (h - g) * f
		var xw := lerpf(1.4, 0.7, f)
		ext.beam("planks_brown", Vector3(-xw, y, -lerpf(1.4, 0.3, f)), Vector3(xw, y, -lerpf(1.4, 0.3, f)), 0.12, 0.18)
		ext.beam("planks_brown", Vector3(-xw, y, lerpf(1.4, 0.3, f)), Vector3(xw, y, lerpf(1.4, 0.3, f)), 0.12, 0.18)
	ext.box("planks_brown", Vector3(-1.0, h, -0.6), Vector3(1.0, h + 0.3, 0.6))
	# sheave wheel
	ext.tint = Color(1, 1, 1, 0.3)
	ext.cyl("iron", Vector3(-0.08, h + 1.1, 0), Vector3(0.08, h + 1.1, 0), 1.0, 20, true)
	ext.cyl("iron", Vector3(-0.2, h + 1.1, 0), Vector3(0.2, h + 1.1, 0), 0.12, 8, true)
	ext.beam("iron", Vector3(0, h + 1.1, -0.95), Vector3(0, g + 0.4, -0.95), 0.03)
	ext.beam("iron", Vector3(0, h + 1.1, 0.95), Vector3(0, ground_local(0, 9.0) + 2.0, 9.0), 0.03)
	paint(col_wall)
	# ore bin with chute
	paint(Color(0.8, 0.72, 0.6))
	var bz := -5.0
	var bg := ground_local(-3.0, bz)
	for c: Vector2 in [Vector2(-4.2, bz - 1.2), Vector2(-1.8, bz - 1.2), Vector2(-1.8, bz + 1.2), Vector2(-4.2, bz + 1.2)]:
		ext.box("planks_brown", Vector3(c.x - 0.12, bg - 0.2, c.y - 0.12), Vector3(c.x + 0.12, bg + 3.2, c.y + 0.12), MeshKit.F_SIDES)
	ext.box("planks_raw", Vector3(-4.3, bg + 3.0, bz - 1.3), Vector3(-1.7, bg + 5.2, bz + 1.3))
	ext.beam("planks_raw", Vector3(-3.0, bg + 3.1, bz - 1.2), Vector3(-3.0, bg + 2.2, bz - 2.6), 0.6, 0.08, Vector3(0, 1, 0))
	solid(Vector3(-4.3, bg, bz - 1.3), Vector3(-1.7, bg + 5.2, bz + 1.3))
	# tailings pile
	ext.tint = Color(0.62, 0.56, 0.5, 0.6)
	ext.cyl("stone", Vector3(6.0, ground_local(6.0, -6.0) - 0.5, -6.0), Vector3(6.0, ground_local(6.0, -6.0) + 2.2, -6.0), 5.0, 12, true, 0.8)
	paint(col_wall)
	far.tint = Color(0.45, 0.38, 0.3, 1)
	far.box("far", Vector3(-1.0, g, -1.0), Vector3(1.0, h + 1.5, 1.0), MeshKit.F_SIDES)
	far.box("far", Vector3(-4.3, bg, bz - 1.3), Vector3(-1.7, bg + 5.2, bz + 1.3), MeshKit.F_ALL)
	spot("work", Vector3(0, g + 0.35, -2.2), Vector3(0, 0, 1), {"work": "mine"})
	spot("work", Vector3(-3.0, bg, bz - 2.2), Vector3(0, 0, 1), {"work": "ore"})

# ------------------------------------------------------------------------------------------------ bridge and pier

## Bridge: spans local z 0..L, deck at y = 0 (xf at the start, deck height), width w.
func _s_bridge() -> void:
	var L: float = spec.get("length", 40.0)
	var hw := w * 0.5
	paint(Color(0.85, 0.8, 0.72))
	ext.box("planks_brown", Vector3(-hw, -0.12, 0.0), Vector3(hw, 0.0, L), MeshKit.F_PY | MeshKit.F_NX | MeshKit.F_PX)
	ext.face("planks_v", Vector3(-hw, -0.12, L), Vector3(w, 0, 0), Vector3(0, 0, -L))
	solid(Vector3(-hw, -0.4, 0.0), Vector3(hw, 0.0, L))
	for sx: float in [-hw + 0.3, -hw * 0.33, hw * 0.33, hw - 0.3]:
		ext.box("planks_brown", Vector3(sx - 0.12, -0.5, 0.0), Vector3(sx + 0.12, -0.12, L), MeshKit.F_SIDES | MeshKit.F_NY)
	# trestle bents
	var nb := maxi(1, int(L / 6.0))
	for i in range(1, nb):
		var bz := L * i / nb
		var gl := minf(ground_local(-hw, bz), ground_local(hw, bz))
		for sx: float in [-hw + 0.25, -hw * 0.4, hw * 0.4, hw - 0.25]:
			ext.box("planks_brown", Vector3(sx - 0.15, gl - 0.6, bz - 0.15), Vector3(sx + 0.15, -0.5, bz + 0.15), MeshKit.F_SIDES)
		ext.box("planks_brown", Vector3(-hw - 0.2, -0.75, bz - 0.18), Vector3(hw + 0.2, -0.5, bz + 0.18))
		if -0.5 - gl > 1.5:
			ext.beam("planks_brown", Vector3(-hw + 0.25, gl + 0.3, bz), Vector3(hw - 0.25, -0.8, bz), 0.08, 0.16, Vector3(0, 0, 1))
			ext.beam("planks_brown", Vector3(hw - 0.25, gl + 0.3, bz), Vector3(-hw + 0.25, -0.8, bz), 0.08, 0.16, Vector3(0, 0, 1))
	# abutments
	paint(Color(0.9, 0.86, 0.8))
	for zz: float in [0.0, L]:
		var gz := ground_local(0.0, zz + (2.0 if zz == 0.0 else -2.0))
		ext.box("stone", Vector3(-hw - 0.4, gz - 1.0, zz - 1.0), Vector3(hw + 0.4, -0.12, zz + 1.0), MeshKit.F_SIDES)
	# railings
	paint(Color(0.85, 0.8, 0.72))
	for sx: float in [-hw - 0.05, hw + 0.05]:
		var n := int(L / 2.0)
		for i in n + 1:
			var pz := L * i / n
			ext.box("planks_brown", Vector3(sx - 0.07, 0.0, pz - 0.07), Vector3(sx + 0.07, 1.1, pz + 0.07), MeshKit.F_SIDES | MeshKit.F_PY)
		ext.box("planks_brown", Vector3(sx - 0.06, 1.0, 0.0), Vector3(sx + 0.06, 1.12, L))
		ext.box("planks_brown", Vector3(sx - 0.04, 0.5, 0.0), Vector3(sx + 0.04, 0.6, L))
		solid(Vector3(sx - 0.07, 0.0, 0.0), Vector3(sx + 0.07, 1.12, L))
	far_box(-hw, 0.0, hw, L, -0.5, 1.1, "planks_brown")
	rec.walkable = true

## Pier into the lake: local z 0..L, deck height y = 0 (xf origin), piles down to the bed.
func _s_pier() -> void:
	var L: float = spec.get("length", 50.0)
	var hw := w * 0.5
	paint(Color(0.82, 0.78, 0.7))
	ext.box("planks_brown", Vector3(-hw, -0.12, 0.0), Vector3(hw, 0.0, L), MeshKit.F_PY | MeshKit.F_NX | MeshKit.F_PX | MeshKit.F_PZ)
	solid(Vector3(-hw, -0.4, 0.0), Vector3(hw, 0.0, L))
	for sx: float in [-hw + 0.3, hw - 0.3]:
		ext.box("planks_brown", Vector3(sx - 0.12, -0.45, 0.0), Vector3(sx + 0.12, -0.12, L), MeshKit.F_SIDES | MeshKit.F_NY)
	var n := int(L / 3.5)
	for i in n + 1:
		var pz := L * i / n
		var gl := ground_local(0.0, pz) - 0.5
		for sx: float in [-hw - 0.1, hw + 0.1]:
			ext.cyl("log", Vector3(sx, gl, pz), Vector3(sx, 0.35, pz), 0.17, 7, true)
		ext.box("planks_brown", Vector3(-hw - 0.2, -0.6, pz - 0.12), Vector3(hw + 0.2, -0.35, pz + 0.12))
		if i % 3 == 1:
			ext.tint = Color(1, 1, 1, 0.4)
			ext.cyl("iron", Vector3(hw - 0.35, 0.0, pz), Vector3(hw - 0.35, 0.45, pz), 0.12, 8, true)
			paint(Color(0.82, 0.78, 0.7))
	# T-head
	ext.box("planks_brown", Vector3(-hw - 6.0, -0.12, L - 4.0), Vector3(hw + 6.0, 0.0, L), MeshKit.F_PY | MeshKit.F_NX | MeshKit.F_PX | MeshKit.F_PZ | MeshKit.F_NZ)
	solid(Vector3(-hw - 6.0, -0.4, L - 4.0), Vector3(hw + 6.0, 0.0, L))
	for sx: float in [-hw - 5.8, hw + 5.8]:
		ext.cyl("log", Vector3(sx, ground_local(sx, L - 2.0) - 0.5, L - 2.0), Vector3(sx, 0.4, L - 2.0), 0.2, 7, true)
	crates_pile_out(hw + 3.0, L - 2.0)
	spot("pier_end", Vector3(0, 0, L - 0.8), Vector3(0, 0, 1))
	spot("fishing", Vector3(hw + 4.5, 0, L - 0.6), Vector3(0, 0, 1), {"sit_height": 0.0})
	far_box(-hw, 0.0, hw, L, -0.5, 0.0, "planks_brown")
	rec.walkable = true

func crates_pile_out(x: float, z: float) -> void:
	for i in 4:
		var pick: String = rand_pick(["wooden_crate_01", "wooden_crate_02", "barrel_03", "wooden_military_crate"])
		prop(pick, Vector3(x + rng.randf_range(-1.0, 1.0), ground_local(x, z) + 0.0, z + rng.randf_range(-0.8, 0.8)), rng.randf() * 360.0, 1.0, true)
	solid(Vector3(x - 1.2, ground_local(x, z), z - 1.0), Vector3(x + 1.2, ground_local(x, z) + 0.6, z + 1.0))

# ------------------------------------------------------------------------------------------------ wagon

func _wheel(k: MeshKit, c: Vector3, r: float, spokes := 12) -> void:
	k.tint = Color(0.75, 0.6, 0.45, 0.4)
	for i in 16:
		var a0 := TAU * i / 16.0
		var a1 := TAU * (i + 1) / 16.0
		k.beam("planks_brown", c + Vector3(0, cos(a0), sin(a0)) * r, c + Vector3(0, cos(a1), sin(a1)) * r, 0.07, 0.08, Vector3(1, 0, 0))
	for i in spokes:
		var a := TAU * i / spokes
		k.beam("planks_brown", c, c + Vector3(0, cos(a), sin(a)) * (r - 0.03), 0.035, 0.035)
	k.tint = Color(1, 1, 1, 0.3)
	k.cyl("iron", c + Vector3(-0.1, 0, 0), c + Vector3(0.1, 0, 0), 0.09, 8, true)

func _s_wagon() -> void:
	var covered: bool = spec.get("covered", true)
	var g := ground_local(0.0, 0.0)
	var k := ext
	var wr := 0.62
	var fr_ := 0.5
	for sx: float in [-0.72, 0.72]:
		_wheel(k, Vector3(sx, g + wr, 1.0), wr)
		_wheel(k, Vector3(sx, g + fr_, -1.1), fr_)
	paint(spec.get("paint", Color(0.55, 0.3, 0.2)))
	var by := g + 0.75
	ext.box("planks_brown", Vector3(-0.6, by, -1.6), Vector3(0.6, by + 0.08, 1.5))
	ext.box("paint", Vector3(-0.62, by, -1.6), Vector3(-0.58, by + 0.55, 1.5))
	ext.box("paint", Vector3(0.58, by, -1.6), Vector3(0.62, by + 0.55, 1.5))
	ext.box("paint", Vector3(-0.6, by, -1.62), Vector3(0.6, by + 0.55, -1.58))
	ext.box("paint", Vector3(-0.6, by, 1.48), Vector3(0.6, by + 0.45, 1.52))
	ext.beam("planks_brown", Vector3(0, g + 0.55, -1.2), Vector3(0, g + 0.35, -3.6), 0.08, 0.1)
	ext.tint = Color(1, 1, 1, 0.3)
	ext.cyl("iron", Vector3(-0.8, g + wr, 1.0), Vector3(0.8, g + wr, 1.0), 0.04, 6, false)
	ext.cyl("iron", Vector3(-0.8, g + fr_, -1.1), Vector3(0.8, g + fr_, -1.1), 0.04, 6, false)
	paint(col_wall)
	ext.box("planks_brown", Vector3(-0.55, by + 0.55, -1.55), Vector3(0.55, by + 0.6, -1.1))   # seat
	if covered:
		paint(Color(0.93, 0.9, 0.82))
		var arcs := 7
		for i in arcs:
			var a0 := PI * i / arcs
			var a1 := PI * (i + 1) / arcs
			var p0 := Vector3(-cos(a0) * 0.7, by + 0.55 + sin(a0) * 1.0, 0)
			var p1 := Vector3(-cos(a1) * 0.7, by + 0.55 + sin(a1) * 1.0, 0)
			_canvas_quad(p1 + Vector3(0, 0, -1.3), p0 + Vector3(0, 0, -1.3), p0 + Vector3(0, 0, 1.4), p1 + Vector3(0, 0, 1.4))
		paint(col_wall)
	else:
		crates_in_wagon(by + 0.08)
	solid(Vector3(-0.75, g, -1.6), Vector3(0.75, by + (1.6 if covered else 0.6), 1.5))
	far.tint = Color(0.8, 0.76, 0.68, 1) if covered else Color(0.4, 0.3, 0.22, 1)
	far.box("far", Vector3(-0.7, g + 0.4, -1.6), Vector3(0.7, by + (1.5 if covered else 0.5), 1.5))
	spot("wagon_seat", Vector3(0, by + 0.6, -1.3), Vector3(0, 0, -1), {"sit_height": 0.0})

func crates_in_wagon(y: float) -> void:
	prop("wooden_crate_02", Vector3(0.0, y, 0.5), 0.0, 1.0, true)
	prop("barrel_03", Vector3(-0.25, y, -0.8), 0.0, 0.8, true)
	prop("wooden_crate_01", Vector3(0.2, y, -0.4), 90.0, 1.0, true)

# ------------------------------------------------------------------------------------------------ corral

## Post-and-rail corral: rectangle w x d starting at the front edge z=0, gate gap in the front centre.
func _s_corral() -> void:
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var split: bool = spec.get("split_rail", false)
	paint(Color(0.85, 0.8, 0.72))
	var pts := [Vector2(x0, 0.0), Vector2(x1, 0.0), Vector2(x1, d), Vector2(x0, d)]
	for e in 4:
		var a: Vector2 = pts[e]
		var b: Vector2 = pts[(e + 1) % 4]
		var L := a.distance_to(b)
		var n := maxi(1, int(ceil(L / 2.4)))
		for i in n:
			var pa := a.lerp(b, float(i) / n)
			var pb := a.lerp(b, float(i + 1) / n)
			if e == 0 and absf((pa.x + pb.x) * 0.5) < 2.0:
				continue      # gate gap
			var ga := ground_local(pa.x, pa.y)
			var gb := ground_local(pb.x, pb.y)
			ext.box("planks_brown", Vector3(pa.x - 0.08, ga - 0.3, pa.y - 0.08), Vector3(pa.x + 0.08, ga + 1.45, pa.y + 0.08), MeshKit.F_SIDES | MeshKit.F_PY)
			for ry: float in [0.45, 0.9, 1.35]:
				if split:
					ext.cyl("log", Vector3(pa.x, ga + ry, pa.y), Vector3(pb.x, gb + ry, pb.y), 0.06, 5, false)
				else:
					ext.beam("planks_raw", Vector3(pa.x, ga + ry, pa.y), Vector3(pb.x, gb + ry, pb.y), 0.05, 0.16)
			var c := Vector3((pa.x + pb.x) * 0.5, (ga + gb) * 0.5 + 0.75, (pa.y + pb.y) * 0.5)
			var dir := Vector3(pb.x - pa.x, gb - ga, pb.y - pa.y)
			solid_obb(c, Vector3(dir.length(), 1.5, 0.15), Basis(Vector3.UP, atan2(-(pb.y - pa.y), pb.x - pa.x)))
	ext.box("planks_brown", Vector3(1.9, ground_local(1.9, 0.0) - 0.3, -0.1), Vector3(2.1, ground_local(1.9, 0.0) + 1.6, 0.1), MeshKit.F_SIDES | MeshKit.F_PY)
	ext.box("planks_brown", Vector3(-2.1, ground_local(-1.9, 0.0) - 0.3, -0.1), Vector3(-1.9, ground_local(-1.9, 0.0) + 1.6, 0.1), MeshKit.F_SIDES | MeshKit.F_PY)
	# gate swung open
	var gg := ground_local(2.0, 0.0)
	for ry: float in [0.4, 0.8, 1.2]:
		ext.box("planks_raw", Vector3(2.0, gg + ry, -0.05 - 0.0), Vector3(2.06, gg + ry + 0.14, -3.6))
	ext.beam("planks_raw", Vector3(2.03, gg + 0.4, -0.1), Vector3(2.03, gg + 1.34, -3.5), 0.05, 0.12, Vector3(1, 0, 0))
	if spec.get("trough", true):
		trough(x1 - 2.0, d - 1.2, 2.0)
	far.tint = Color(0.42, 0.36, 0.28, 1)
	for e in 4:
		var a2: Vector2 = pts[e]
		var b2: Vector2 = pts[(e + 1) % 4]
		var ga2 := ground_local(a2.x, a2.y)
		far.quad("far", Vector3(a2.x, ga2, a2.y), Vector3(b2.x, ga2, b2.y), Vector3(b2.x, ga2 + 1.4, b2.y), Vector3(a2.x, ga2 + 1.4, a2.y))
		far.quad("far", Vector3(b2.x, ga2, b2.y), Vector3(a2.x, ga2, a2.y), Vector3(a2.x, ga2 + 1.4, a2.y), Vector3(b2.x, ga2 + 1.4, b2.y))
	spot("corral", Vector3(0, ground_local(0, d * 0.5), d * 0.5), Vector3(0, 0, -1), {"animal": "horse"})

# ------------------------------------------------------------------------------------------------ camp pieces

func _s_campfire() -> void:
	var g := ground_local(0.0, 0.0)
	prop("stone_fire_pit", Vector3(0, g + 0.15, 0), 0.0, 1.0, true)
	paint(Color(0.6, 0.5, 0.4))
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		ext.cyl("log", Vector3(cos(a) * 0.35, g + 0.08, sin(a) * 0.35), Vector3(-cos(a) * 0.1, g + 0.32, -sin(a) * 0.1), 0.06, 6, true)
	ext.tint = Color(1, 1, 1, 0)
	ext.cyl("fire", Vector3(0, g + 0.1, 0), Vector3(0, g + 0.55, 0), 0.28, 7, false, 0.02)
	ext.cyl("fire", Vector3(0.05, g + 0.1, 0.05), Vector3(0.05, g + 0.4, 0.05), 0.18, 6, false, 0.02)
	paint(Color(0.85, 0.8, 0.72))
	# cooking tripod with a pot
	for i in 3:
		var a2 := TAU * i / 3.0
		ext.beam("planks_raw", Vector3(cos(a2) * 0.9, g, sin(a2) * 0.9), Vector3(0, g + 1.5, 0), 0.04)
	ext.tint = Color(1, 1, 1, 0.3)
	ext.beam("iron", Vector3(0, g + 1.5, 0), Vector3(0, g + 0.85, 0), 0.008)
	prop("pot_enamel_01", Vector3(0, g + 0.68, 0), 0.0, 1.2, true)
	# log seats around the fire
	paint(Color(0.85, 0.8, 0.72))
	var seats: int = spec.get("seats", 5)
	for i in seats:
		var a3 := TAU * i / seats + 0.6
		var p := Vector3(cos(a3) * 2.4, 0, sin(a3) * 2.4)
		p.y = ground_local(p.x, p.z)
		var tang := Vector3(-sin(a3), 0, cos(a3))
		ext.cyl("log", p - tang * 0.75 + Vector3(0, 0.2, 0), p + tang * 0.75 + Vector3(0, 0.2, 0), 0.2, 8, true)
		solid(p - Vector3(0.4, 0, 0.4), p + Vector3(0.4, 0.4, 0.4))
		spot("campfire_seat", p, -p.normalized() * Vector3(1, 0, 1), {"sit_height": 0.4})
	light(Vector3(0, g + 0.8, 0), "fire", 9.0, 2.0, Color(1.0, 0.5, 0.2), true)
	rec["always_lit"] = true
	spot("campfire", Vector3(0, g, 1.2), Vector3(0, 0, -1), {"work": "cook"})

func _s_well() -> void:
	var g := ground_local(0.0, 0.0)
	paint(Color(0.9, 0.85, 0.8))
	ext.cyl("stone", Vector3(0, g - 0.3, 0), Vector3(0, g + 0.8, 0), 0.9, 14, false)
	ext.cyl("stone", Vector3(0, g + 0.8, 0), Vector3(0, g + 0.88, 0), 0.95, 14, true)
	ext.tint = Color(1, 1, 1, 0)
	ext.cyl("water", Vector3(0, g + 0.2, 0), Vector3(0, g + 0.21, 0), 0.72, 12, true)
	paint(Color(0.8, 0.72, 0.62))
	for sx: float in [-0.85, 0.85]:
		ext.box("planks_brown", Vector3(sx - 0.07, g + 0.8, -0.07), Vector3(sx + 0.07, g + 2.3, 0.07), MeshKit.F_SIDES)
	ext.cyl("log", Vector3(-0.85, g + 1.6, 0), Vector3(0.85, g + 1.6, 0), 0.08, 7, true)
	gable_roof(-1.0, -0.7, 1.0, 0.7, g + 2.2, 35.0, "x", 0.2, "shingles", "planks_v", "", false, false)
	prop("wooden_bucket_01", Vector3(0.6, g + 0.88, 0.3), 0.0, 1.0, true)
	solid(Vector3(-0.95, g, -0.95), Vector3(0.95, g + 0.88, 0.95))
	spot("well", Vector3(0, g, -1.3), Vector3(0, 0, 1), {"work": "water"})
	far.tint = Color(0.6, 0.56, 0.5, 1)
	far.cyl("far", Vector3(0, g, 0), Vector3(0, g + 0.9, 0), 0.9, 8, true)

func _s_woodpile() -> void:
	var g := ground_local(0.0, 0.0)
	paint(Color(0.85, 0.75, 0.6))
	for row in 4:
		for i in int(w / 0.22):
			var px := -w * 0.5 + 0.11 + i * 0.22 + (0.11 if row % 2 == 1 else 0.0)
			if px > w * 0.5 - 0.1:
				continue
			ext.cyl("log", Vector3(px, g + 0.11 + row * 0.19, -0.4), Vector3(px, g + 0.11 + row * 0.19, 0.4), 0.1, 6, true)
	solid(Vector3(-w * 0.5, g, -0.4), Vector3(w * 0.5, g + 0.8, 0.4))
	paint(Color(0.8, 0.7, 0.6))
	ext.cyl("log", Vector3(w * 0.5 + 0.8, g, 0.2), Vector3(w * 0.5 + 0.8, g + 0.45, 0.2), 0.3, 9, true)
	prop("hatchet", Vector3(w * 0.5 + 0.8, g + 0.45, 0.2), 30.0, 1.4, true)
	spot("work", Vector3(w * 0.5 + 0.8, g, -0.5), Vector3(0, 0, 1), {"work": "chop"})

func _s_logpile() -> void:
	var g := ground_local(0.0, 0.0)
	paint(Color(0.85, 0.8, 0.72))
	var n := int(w / 0.6)
	for row in 3:
		for i in n - row:
			var px := -w * 0.5 + 0.3 + i * 0.6 + row * 0.3
			ext.cyl("log", Vector3(px, g + 0.3 + row * 0.52, -d * 0.5), Vector3(px, g + 0.3 + row * 0.52, d * 0.5), 0.29, 8, true)
	solid(Vector3(-w * 0.5, g, -d * 0.5), Vector3(w * 0.5, g + 1.5, d * 0.5))
	far.tint = Color(0.45, 0.36, 0.26, 1)
	far.box("far", Vector3(-w * 0.5, g, -d * 0.5), Vector3(w * 0.5, g + 1.4, d * 0.5))

func _s_sawmill() -> void:
	var H := 4.2
	var x0 := -w * 0.5
	var x1 := w * 0.5
	paint(Color(0.82, 0.76, 0.68))
	var g := ground_min(x0, 0.0, x1, d)
	for i in 4:
		for j in 2:
			var px := lerpf(x0 + 0.2, x1 - 0.2, i / 3.0)
			var pz := 0.2 if j == 0 else d - 0.2
			ext.box("planks_brown", Vector3(px - 0.12, g - 0.2, pz - 0.12), Vector3(px + 0.12, H, pz + 0.12), MeshKit.F_SIDES)
			solid(Vector3(px - 0.12, g, pz - 0.12), Vector3(px + 0.12, H, pz + 0.12))
	gable_roof(x0, 0.0, x1, d, H, 25.0, "x", 0.6, "corrugated", "planks_raw", "", true, true)
	# carriage rails, the saw, a log on the carriage, sawdust
	ext.box("planks_brown", Vector3(x0 - 4.0, g, d * 0.5 - 0.6), Vector3(x1 + 4.0, g + 0.4, d * 0.5 - 0.4))
	ext.box("planks_brown", Vector3(x0 - 4.0, g, d * 0.5 + 0.4), Vector3(x1 + 4.0, g + 0.4, d * 0.5 + 0.6))
	ext.cyl("log", Vector3(x0 + 1.0, g + 0.75, d * 0.5), Vector3(x1 - 1.0, g + 0.75, d * 0.5), 0.35, 8, true)
	ext.tint = Color(1, 1, 1, 0.2)
	ext.cyl("iron", Vector3(0.0, g + 0.9, d * 0.5 - 1.0), Vector3(0.0, g + 0.9, d * 0.5 - 0.98), 0.9, 20, true)
	ext.tint = Color(0.85, 0.72, 0.52, 0.2)
	ext.cyl("thatch", Vector3(x1 + 2.0, g - 0.2, d + 2.0), Vector3(x1 + 2.0, g + 1.2, d + 2.0), 2.0, 10, true, 0.2)
	paint(col_wall)
	solid(Vector3(x0 - 4.0, g, d * 0.5 - 0.6), Vector3(x1 + 4.0, g + 0.4, d * 0.5 + 0.6))
	spot("work", Vector3(0.0, g, d * 0.5 - 1.6), Vector3(0, 0, 1), {"work": "saw"})
	far.tint = Color(0.42, 0.42, 0.4, 1)
	far.box("far", Vector3(x0, H, 0.0), Vector3(x1, H + 1.0, d))

# ------------------------------------------------------------------------------------------------ mission ruin

func _s_mission_ruin() -> void:
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var t := 0.8
	mat_wall = "stone"
	paint(Color(1.0, 0.86, 0.72))
	# espadana: the tall stepped facade with bell openings
	var ff := frame(Vector2(x1, 0.0), Vector2(x0, 0.0), t)
	var fh := 9.0
	var items := [{"k": "open", "c": w * 0.5, "w": 2.2, "v0": 0.0, "v1": 3.6}]
	wall(ff, 0.0, 6.5, [{"s0": w * 0.5 - 1.1, "s1": w * 0.5 + 1.1, "v0": 0.0, "v1": 3.6, "kind": "open"},
		{"s0": w * 0.5 - 0.5, "s1": w * 0.5 + 0.5, "v0": 4.6, "v1": 5.6, "kind": "window"}], "stone", "stone")
	# stepped gable top with two bell openings
	var steps_ := [[w * 0.15, w * 0.85, 6.5, 7.5], [w * 0.3, w * 0.7, 7.5, fh]]
	for st in steps_:
		var ops := []
		if st[2] > 7.0:
			ops = [{"s0": w * 0.5 - 0.9, "s1": w * 0.5 - 0.25, "v0": 7.8, "v1": 8.6, "kind": "open"},
				{"s0": w * 0.5 + 0.25, "s1": w * 0.5 + 0.9, "v0": 7.8, "v1": 8.6, "kind": "open"}]
		var f2 := frame(Vector2(x1 - st[0], 0.0), Vector2(x1 - st[1], 0.0), t)
		wall(f2, st[2], st[3], [] if ops.is_empty() else [{"s0": ops[0].s0 - st[0], "s1": ops[0].s1 - st[0], "v0": 7.8, "v1": 8.6, "kind": "open"},
			{"s0": ops[1].s0 - st[0], "s1": ops[1].s1 - st[0], "v0": 7.8, "v1": 8.6, "kind": "open"}], "stone", "stone")
		ext.box("stone", fp(f2, 0.0, st[3], -t), fp(f2, f2.L, st[3] + 0.15, 0.0), MeshKit.F_PY)
	ext.box("stone", Vector3(x0, 6.5, -0.0), Vector3(x0 + w * 0.15, 6.65, t), MeshKit.F_PY)
	ext.box("stone", Vector3(x1 - w * 0.15, 6.5, 0.0), Vector3(x1, 6.65, t), MeshKit.F_PY)
	ext.tint = Color(1, 1, 1, 0.5)
	ext.cyl("brass", Vector3(w * 0.5 - 0.575 - w * 0.5 + 0.0, 8.0, t * 0.5), Vector3(-0.575, 8.5, t * 0.5), 0.25, 8, true, 0.12)
	paint(Color(1.0, 0.86, 0.72))
	# side walls, ruined: falling heights along their length
	for sx: float in [x0, x1]:
		var segs := 8
		for i in segs:
			var za := t + (d - t) * i / segs
			var zb := t + (d - t) * (i + 1) / segs
			var hgt := maxf(0.6, 5.5 - absf(sin(i * 1.7 + sx)) * 3.5 - (i * 0.35))
			if i == 3:
				hgt = 0.4
			var xa: float = sx if sx < 0 else sx - t
			ext.box("stone", Vector3(xa, -0.3, za), Vector3(xa + t, hgt, zb))
			solid(Vector3(xa, 0.0, za), Vector3(xa + t, hgt, zb))
	# back wall stump, rubble, fallen vigas, a wooden cross
	ext.box("stone", Vector3(x0, -0.3, d - t), Vector3(x1, 1.4, d))
	solid(Vector3(x0, 0.0, d - t), Vector3(x1, 1.4, d))
	for i in 9:
		var p := Vector3(rng.randf_range(x0 + 1.0, x1 - 1.0), 0.0, rng.randf_range(2.0, d - 2.0))
		p.y = ground_local(p.x, p.z)
		ext.obox("stone", p + Vector3(0, 0.15, 0), Vector3(rng.randf_range(0.4, 1.2), rng.randf_range(0.25, 0.6), rng.randf_range(0.4, 1.0)),
			Basis(Vector3(rng.randf(), 1, rng.randf()).normalized(), rng.randf_range(-0.4, 0.4)))
	paint(Color(0.75, 0.68, 0.6))
	for i in 3:
		var p2 := Vector3(rng.randf_range(x0 + 1.5, x1 - 1.5), 0.0, rng.randf_range(3.0, d - 3.0))
		p2.y = ground_local(p2.x, p2.z)
		var a := rng.randf() * TAU
		ext.cyl("log", p2 + Vector3(cos(a) * 2.5, 0.2 + i * 0.3, sin(a) * 2.5), p2 + Vector3(-cos(a) * 2.5, 1.4, -sin(a) * 2.5), 0.13, 6, true)
	ext.box("planks_brown", Vector3(-0.07, 0.0, d - 2.0), Vector3(0.07, 2.4, d - 1.86))
	ext.box("planks_brown", Vector3(-0.6, 1.7, d - 2.0), Vector3(0.6, 1.84, d - 1.86))
	solid_obb(fp(ff, w * 0.25, 3.25, -t * 0.5), Vector3(w * 0.5 - 1.1, 6.5, t), fbasis(ff))
	far.tint = Color(0.7, 0.55, 0.42, 1)
	far.box("far", Vector3(x0, 0.0, 0.0), Vector3(x1, 6.5, t), MeshKit.F_ALL)
	far.box("far", Vector3(x0 + w * 0.3, 6.5, 0.0), Vector3(x1 - w * 0.3, fh, t), MeshKit.F_ALL)
	far.box("far", Vector3(x0, 0.0, t), Vector3(x0 + t, 3.5, d), MeshKit.F_ALL)
	far.box("far", Vector3(x1 - t, 0.0, t), Vector3(x1, 3.5, d), MeshKit.F_ALL)
	room("nave", x0 + t, t, x1 - t, d - t, 0.0)
	spot("stand", Vector3(0, ground_local(0, d * 0.5), d * 0.5), Vector3(0, 0, -1))

# ------------------------------------------------------------------------------------------------ bluff stair

## A long timber stair that follows steep ground (Port Linden's bluff down to the lake): treads every 0.18 m of
## drop, filled down to the ground, handrails on posts. spec.points: world [x, z] path from top to bottom.
func _s_bluff_stair() -> void:
	var pts: Array = spec.get("points", [])
	if pts.size() < 2:
		return
	var inv := xf.affine_inverse()
	var hw: float = spec.get("w", 2.0) * 0.5
	var loc := []
	for p in pts:
		var q := inv * Vector3(p[0], 0.0, p[1])
		loc.append(Vector2(q.x, q.z))
	paint(Color(0.82, 0.76, 0.68))
	var y := ground_local(loc[0].x, loc[0].y) + 0.05
	var tread_start := 0.0
	var dist := 0.0
	var posts := []
	var post_acc := 0.0
	for i in loc.size() - 1:
		var a: Vector2 = loc[i]
		var b: Vector2 = loc[i + 1]
		var L := a.distance_to(b)
		var dirv := (b - a) / maxf(L, 0.001)
		var side := Vector2(-dirv.y, dirv.x)
		var tt := 0.0
		while tt < L:
			var p := a + dirv * tt
			var g := ground_local(p.x, p.y)
			if g < y - 0.18 or tt + 0.1 >= L and i == loc.size() - 2:
				# close the current tread at p and step down
				var p0 := a + dirv * (tread_start - dist) if tread_start >= dist else a
				_tread(p0, p, side, hw, y, minf(g, ground_local(p0.x, p0.y)))
				y -= 0.18
				y = maxf(y, g + 0.05)
				tread_start = dist + tt
			post_acc += 0.1
			if post_acc >= 2.4:
				post_acc = 0.0
				posts.append([p, side, y])
			tt += 0.1
		dist += L
	# handrails
	for sgn: float in [-1.0, 1.0]:
		for k in posts.size():
			var pp: Vector2 = posts[k][0] + posts[k][1] * hw * sgn
			var py: float = posts[k][2]
			ext.box("planks_brown", Vector3(pp.x - 0.05, py - 0.1, pp.y - 0.05), Vector3(pp.x + 0.05, py + 1.0, pp.y + 0.05), MeshKit.F_SIDES | MeshKit.F_PY)
			if k > 0:
				var qq: Vector2 = posts[k - 1][0] + posts[k - 1][1] * hw * sgn
				var qy: float = posts[k - 1][2]
				ext.beam("planks_brown", Vector3(qq.x, qy + 0.95, qq.y), Vector3(pp.x, py + 0.95, pp.y), 0.06, 0.08)
	paint(col_wall)
	rec.walkable = true

func _tread(p0: Vector2, p1: Vector2, side: Vector2, hw: float, y: float, g: float) -> void:
	if p0.distance_to(p1) < 0.05:
		return
	var c := [p0 - side * hw, p1 - side * hw, p1 + side * hw, p0 + side * hw]
	var lo := g - 0.3
	var pts := [Vector3(c[0].x, lo, c[0].y), Vector3(c[1].x, lo, c[1].y), Vector3(c[2].x, lo, c[2].y), Vector3(c[3].x, lo, c[3].y),
		Vector3(c[0].x, y, c[0].y), Vector3(c[1].x, y, c[1].y), Vector3(c[2].x, y, c[2].y), Vector3(c[3].x, y, c[3].y)]
	# hexa wants x-z- ordering; build faces directly so the tread works for any direction
	ext.quad("planks_brown", pts[4], pts[7], pts[6], pts[5])
	ext.quad("planks_brown", pts[0], pts[4], pts[5], pts[1])
	ext.quad("planks_brown", pts[2], pts[6], pts[7], pts[3])
	ext.quad("planks_v", pts[1], pts[5], pts[6], pts[2])
	ext.quad("planks_v", pts[3], pts[7], pts[4], pts[0])
	var mid := (p0 + p1) * 0.5
	var ax := Vector3(p1.x - p0.x, 0.0, p1.y - p0.y)
	solid_obb(Vector3(mid.x, y - 0.15, mid.y), Vector3(hw * 2.0, 0.3, ax.length()), Basis.looking_at(ax.normalized(), Vector3.UP))

# ------------------------------------------------------------------------------------------------ railroad track

## Station track along the rail line through a settlement: ballast bed, ties every 0.6 m, two rails at standard
## gauge on the graded rail profile. spec.points: world [x, z, y] samples.
func _s_track() -> void:
	var pts: Array = spec.get("points", [])
	if pts.size() < 2:
		return
	var inv := xf.affine_inverse()
	var loc := []
	for p in pts:
		loc.append(inv * Vector3(p[0], p[2], p[1]))
	var gauge := 1.435
	var carry := 0.0
	for i in loc.size() - 1:
		var a: Vector3 = loc[i]
		var b: Vector3 = loc[i + 1]
		var ab := b - a
		var L := ab.length()
		if L < 0.01:
			continue
		var dirv := ab / L
		var side := Vector3(-dirv.z, 0.0, dirv.x).normalized()
		paint(Color(0.62, 0.56, 0.5))
		ext.tint = Color(0.62, 0.58, 0.54, 0.5)
		# ballast: a trapezoid prism under the ties
		var hb := 1.9
		var ht := 1.45
		var c0 := [a - side * hb + Vector3(0, -0.25, 0), b - side * hb + Vector3(0, -0.25, 0), b + side * hb + Vector3(0, -0.25, 0), a + side * hb + Vector3(0, -0.25, 0),
			a - side * ht + Vector3(0, 0.12, 0), b - side * ht + Vector3(0, 0.12, 0), b + side * ht + Vector3(0, 0.12, 0), a + side * ht + Vector3(0, 0.12, 0)]
		ext.quad("stone", c0[4], c0[7], c0[6], c0[5])
		ext.quad("stone", c0[0], c0[4], c0[5], c0[1])
		ext.quad("stone", c0[2], c0[6], c0[7], c0[3])
		# ties
		ext.tint = Color(0.55, 0.45, 0.38, 0.6)
		var tdist := 0.6 - carry
		while tdist < L:
			var tc := a + dirv * tdist
			ext.obox("dark_planks", tc + Vector3(0, 0.2, 0), Vector3(2.6, 0.16, 0.22), Basis(side, Vector3.UP, side.cross(Vector3.UP)), MeshKit.F_ALL & ~MeshKit.F_NY)
			tdist += 0.6
		carry = L - (tdist - 0.6)
		# rails
		ext.tint = Color(1, 1, 1, 0.6)
		for sg in [-0.5, 0.5]:
			var off: Vector3 = side * gauge * sg
			ext.beam("iron", a + off + Vector3(0, 0.34, 0), b + off + Vector3(0, 0.34, 0), 0.07, 0.13)
	paint(col_wall)

# ------------------------------------------------------------------------------------------------ street furniture

## Telegraph pole: cedar pole, crossarm, four glass insulators. Returns the insulator tops (wire anchors).
func _pole(x: float, z: float, yaw_deg: float) -> Array:
	var g := ground_local(x, z)
	var h := 7.2
	paint(Color(0.75, 0.66, 0.56))
	ext.cyl("log", Vector3(x, g - 0.5, z), Vector3(x, g + h, z), 0.13, 7, true, 0.1)
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var ax := b * Vector3(1, 0, 0)
	ext.beam("planks_brown", Vector3(x, g + h - 0.45, z) - ax * 0.85, Vector3(x, g + h - 0.45, z) + ax * 0.85, 0.09, 0.11)
	ext.beam("planks_brown", Vector3(x, g + h - 1.1, z), Vector3(x, g + h - 0.5, z) + ax * 0.55, 0.04, 0.05)
	ext.beam("planks_brown", Vector3(x, g + h - 1.1, z), Vector3(x, g + h - 0.5, z) - ax * 0.55, 0.04, 0.05)
	solid(Vector3(x - 0.13, g, z - 0.13), Vector3(x + 0.13, g + h, z + 0.13))
	var tops := []
	ext.tint = Color(0.35, 0.55, 0.45, 1.0)
	for o: float in [-0.75, -0.3, 0.3, 0.75]:
		var p := Vector3(x, g + h - 0.39, z) + ax * o
		ext.cyl("bottle", p, p + Vector3(0, 0.1, 0), 0.035, 5, true)
		tops.append(p + Vector3(0, 0.09, 0))
	paint(col_wall)
	return tops

func _wire(a: Vector3, b: Vector3) -> void:
	ext.tint = Color(0.15, 0.15, 0.15, 0.5)
	var n := 4
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t) + Vector3(0, -0.45 * 4.0 * t * (1.0 - t), 0)
		ext.beam("iron", prev, p, 0.014, 0.014)
		prev = p

## spec.items: [{k: lamp|trough|hitch|barrels|crates|bench|sign_post|pump|pole|hay, x, z, yaw}] in this spec's frame.
## Consecutive "pole" items are strung together with sagging telegraph wires.
func _s_street_kit() -> void:
	var poles := []
	for it in spec.get("items", []):
		if it.k == "pole":
			poles.append(_pole(it.x, it.z, it.get("yaw", 0.0)))
	for i in range(1, poles.size()):
		for k in 4:
			_wire(poles[i - 1][k], poles[i][k])
	for it in spec.get("items", []):
		var x: float = it.x
		var z: float = it.z
		match it.k:
			"lamp":
				lamp_post(x, z, it.get("h", 3.3))
			"trough":
				trough(x, z, 2.2, it.get("yaw90", false))
			"hitch":
				hitching_rail(x, z, it.get("len", 3.0), true, str(it.get("fronts", "")))
			"barrels":
				var g := ground_local(x, z)
				prop("barrel_03", Vector3(x, g, z), rng.randf() * 360.0, 1.0, true)
				prop("barrel_03", Vector3(x + 0.65, g, z + 0.1), rng.randf() * 360.0, 1.0, true)
				if rng.randf() < 0.5:
					prop("wine_barrel_01", Vector3(x + 0.3, g, z + 0.65), 90.0, 1.0, true)
				solid(Vector3(x - 0.35, g, z - 0.35), Vector3(x + 1.0, g + 0.9, z + 1.0))
			"crates":
				var g2 := ground_local(x, z)
				prop("wooden_crate_02", Vector3(x, g2, z), rng.randf_range(-20, 20), 1.0, true)
				prop("wooden_crate_01", Vector3(x + 0.1, g2 + 0.46, z), rng.randf_range(-30, 30), 1.0, true)
				solid(Vector3(x - 0.3, g2, z - 0.6), Vector3(x + 0.3, g2 + 0.8, z + 0.6))
			"bench":
				var g3 := ground_local(x, z)
				paint(Color(0.8, 0.72, 0.6))
				ext.box("planks_brown", Vector3(x - 0.9, g3 + 0.42, z - 0.2), Vector3(x + 0.9, g3 + 0.47, z + 0.2))
				ext.box("planks_brown", Vector3(x - 0.8, g3, z - 0.18), Vector3(x - 0.72, g3 + 0.42, z + 0.18))
				ext.box("planks_brown", Vector3(x + 0.72, g3, z - 0.18), Vector3(x + 0.8, g3 + 0.42, z + 0.18))
				solid(Vector3(x - 0.9, g3, z - 0.2), Vector3(x + 0.9, g3 + 0.47, z + 0.2))
				spot("bench", Vector3(x - 0.4, g3, z), Vector3(0, 0, -1), {"sit_height": 0.45})
				spot("bench", Vector3(x + 0.4, g3, z), Vector3(0, 0, -1), {"sit_height": 0.45})
			"sign_post":
				var g4 := ground_local(x, z)
				paint(Color(0.8, 0.72, 0.6))
				ext.box("planks_brown", Vector3(x - 0.06, g4 - 0.3, z - 0.06), Vector3(x + 0.06, g4 + 2.4, z + 0.06), MeshKit.F_SIDES | MeshKit.F_PY)
				var lines: Array = it.get("text", [])
				for i in lines.size():
					var y := g4 + 2.1 - i * 0.32
					var right: bool = i % 2 == 0
					var ox := 0.6 if right else -0.6
					paint(Color(0.85, 0.8, 0.7))
					ext.box("planks_raw", Vector3(x + ox - 0.6, y - 0.11, z - 0.02), Vector3(x + ox + 0.6, y + 0.11, z + 0.02))
					text(ext, lines[i], Vector3(x + ox, y, z - 0.022), Vector3(-1, 0, 0), Vector3(0, 0, -1), 0.1, 1.1, Color(0.15, 0.1, 0.08), "OldStandard-Bold")
					text(ext, lines[i], Vector3(x + ox, y, z + 0.022), Vector3(1, 0, 0), Vector3(0, 0, 1), 0.1, 1.1, Color(0.15, 0.1, 0.08), "OldStandard-Bold")
				solid(Vector3(x - 0.06, g4, z - 0.06), Vector3(x + 0.06, g4 + 2.4, z + 0.06))
			"pump":
				var g5 := ground_local(x, z)
				ext.tint = Color(1, 1, 1, 0.5)
				ext.box("iron", Vector3(x - 0.1, g5, z - 0.1), Vector3(x + 0.1, g5 + 1.0, z + 0.1))
				ext.beam("iron", Vector3(x, g5 + 0.85, z), Vector3(x, g5 + 0.75, z - 0.35), 0.05)
				ext.beam("iron", Vector3(x, g5 + 1.0, z), Vector3(x, g5 + 1.25, z + 0.5), 0.035)
				paint(col_wall)
				solid(Vector3(x - 0.1, g5, z - 0.1), Vector3(x + 0.1, g5 + 1.0, z + 0.1))
				spot("pump", Vector3(x, g5, z - 0.7), Vector3(0, 0, 1), {"work": "water"})
			"hay":
				hay(x, z, ground_local(x, z), it.get("n", 3), ext)
			"woodpile":
				var saved := xf
				var saved_w := w
				w = it.get("w", 2.4)
				var shift := Transform3D(Basis.IDENTITY, Vector3(x, 0, z))
				var nb: int = rec.boxes.size()
				xf = xf * shift
				ext.xf = xf
				_s_woodpile()
				for bi in range(nb, rec.boxes.size()):
					rec.boxes[bi][0] = shift * rec.boxes[bi][0]
				xf = saved
				ext.xf = xf
				w = saved_w
	far.tint = Color(0, 0, 0, 1)
