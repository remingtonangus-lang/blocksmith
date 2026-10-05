extends RefCounted
## World generation: determinism, layout (sea edges, mountains, flat Capital plain), rivers flow downhill.


func run(t) -> void:
	var g := WorldGen.new(1337)
	var t0 := Time.get_ticks_msec()
	g.generate(false)
	print("    worldgen %d ms" % (Time.get_ticks_msec() - t0))
	t.check(g.heights.size() == WorldGen.N * WorldGen.N, "height grid size")
	var bad := 0
	var hi := -1e9
	var lo := 1e9
	for i in range(0, g.heights.size(), 97):
		var h := g.heights[i]
		if is_nan(h) or is_inf(h):
			bad += 1
		hi = maxf(hi, h)
		lo = minf(lo, h)
	t.check(bad == 0, "no NaN heights")
	print("    height range %.0f .. %.0f" % [lo, hi])
	t.check(hi > 1400.0, "mountains reach above the snow line (%.0f)" % hi)
	t.check(lo < -100.0, "deep sea exists (%.0f)" % lo)
	for c in [Vector2(-7900, -7900), Vector2(7900, 7900), Vector2(-7900, 7900), Vector2(7900, -7900)]:
		t.check(g.height_at(c.x, c.y) < 0.0, "world corner %s is sea" % c)
	var cap: Vector3 = g.sites["capital"]
	t.near(cap.y, 22.0, 3.0, "Capital plain is flattened")
	var spread := 0.0
	for k in 16:
		var a := TAU * k / 16.0
		spread = maxf(spread, absf(g.height_at(cap.x + cos(a) * 900.0, cap.z + sin(a) * 900.0) - 22.0))
	t.check(spread < 6.0, "Capital plain flat within 900 m (max dev %.1f)" % spread)
	for r in g.rivers:
		var pts: PackedVector3Array = r["pts"]
		var up := 0
		for i in range(1, pts.size()):
			if pts[i].y > pts[i - 1].y + 0.001:
				up += 1
		t.check(up == 0, "river surface never flows uphill")
		var mid := pts[pts.size() / 3]
		t.check(g.water_at(mid.x, mid.z) > -100.0, "river has water at its upper third")
		t.check(g.height_at(mid.x, mid.z) < mid.y, "river bed below its surface")
		# No floating water: the surface sits on its channel (a 230 m sheet once hung over the main river's source).
		# On cascades the ground under a point already belongs to the next, lower step: allow one step's drop.
		var worst := 0.0
		for i in pts.size() - 1:
			var p := pts[i]
			if p.y > 0.5:
				worst = maxf(worst, p.y - g.height_at(p.x, p.z) - (p.y - pts[i + 1].y))
		t.check(worst < 9.0, "river surface stays on its channel (max %.1f m above the ground beyond the local drop)" % worst)
	# No road is buried by another one carved later over the same corridor (Front Track sat 18 m under Red Track's).
	var buried := 0.0
	for r in g.roads:
		for p in (r["pts"] as PackedVector3Array):
			buried = minf(buried, p.y - g.height_at(p.x, p.z))
	t.check(buried > -1.5, "roads stay on the ground (lowest %.1f m)" % buried)
	# Determinism: a second generator with the same seed agrees.
	var g2 := WorldGen.new(1337)
	t.near(g2.base_height(1234.5, -987.25), g.base_height(1234.5, -987.25), 0.0001, "base height deterministic")
	# The cache round-trips.
	g._save_cache()
	var g3 := WorldGen.new(1337)
	t.check(g3._load_cache(), "cache loads")
	t.near(g3.height_at(333.0, 777.0), g.height_at(333.0, 777.0), 0.0001, "cache matches")
