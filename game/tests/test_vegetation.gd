extends RefCounted
## Tree placement: deterministic, avoids water and steep ground, and is fast enough to stream (timed).


func run(t) -> void:
	var g := WorldGen.new(1337)
	g.generate(true)
	G.gen = g
	var v: Node = load("res://scripts/world/vegetation.gd").new()
	v.gen = g
	var f: Vector3 = g.sites["forest"]
	var c := Vector2i(floori(f.x / 128.0), floori(f.z / 128.0))
	var t0 := Time.get_ticks_usec()
	var n := 0
	for i in 36:
		n += v.cell_trees(c + Vector2i(i % 6 - 3, i / 6 - 3), true).size()
	var far_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("    36 far tree cells (one impostor cell): %d trees, %.0f ms" % [n, far_ms])
	t0 = Time.get_ticks_usec()
	var near: Array = v.cell_trees(c, false)
	print("    1 near tree cell: %d trees, %.1f ms" % [near.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	t.check(near.size() > 40, "the forest site has a forest (%d trees in 128 m)" % near.size())
	var again: Array = v.cell_trees(c, false)
	t.check(again.size() == near.size(), "placement is deterministic")
	var wet := 0
	for tr in near:
		var p: Vector3 = (tr[2] as Transform3D).origin
		if g.water_at(p.x, p.z) > -100.0:
			wet += 1
	t.check(wet == 0, "no trees in water")
	# Trunks: every tree (not bushes) lands in the bucket under it, and avoid() pushes a walker out of the bark.
	var b: Dictionary = v._trunk_buckets(near)
	v.trunks[c] = b
	var missed := 0
	var trunks_n := 0
	var inside := 0
	for tr in near:
		if tr[0] == TreeBuilder.BUSH:
			continue
		trunks_n += 1
		var o: Vector3 = (tr[2] as Transform3D).origin
		var bk := Vector2i(floori(o.x / 8.0), floori(o.z / 8.0))
		if not b.has(bk):
			missed += 1
			continue
		var q: Vector3 = v.avoid(o + Vector3(0.05, 0.0, 0.02), 0.35)
		var r: float = float(v.TRUNK_R[tr[0]]) * (tr[2] as Transform3D).basis.get_scale().x
		if Vector2(q.x - o.x, q.z - o.z).length() < r + 0.3:
			inside += 1
	t.check(missed == 0, "every trunk is bucketed (%d of %d missed)" % [missed, trunks_n])
	t.check(inside == 0, "avoid() pushes a walker out of every trunk (%d left inside)" % inside)
	var t1 := Time.get_ticks_usec()
	for k in 20000:
		v.avoid(Vector3(c.x * 128.0 + fposmod(k * 1.37, 128.0), 0.0, c.y * 128.0 + fposmod(k * 0.71, 128.0)), 0.35)
	var us := (Time.get_ticks_usec() - t1) / 20000.0
	print("    avoid(): %.2f us per call in the forest" % us)
	t.check(us < 20.0, "avoid() is cheap enough for every walking soldier (%.2f us)" % us)
	v.free()
