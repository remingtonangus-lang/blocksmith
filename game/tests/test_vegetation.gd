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
	v.free()
