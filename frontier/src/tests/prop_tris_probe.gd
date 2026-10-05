extends SceneTree
## godot --headless -s res://src/tests/prop_tris_probe.gd : triangle counts of the town props after TownProps
## decimation (props.gd MAX_TRIS), heaviest first.

func _init() -> void:
	var rows := []
	var total := 0
	for name in TownProps.SIZE:
		var t0 := Time.get_ticks_usec()
		var m: Mesh = TownProps.mesh(name)
		if m == null:
			continue
		var tris := 0
		for s in m.get_surface_count():
			var a: Array = m.surface_get_arrays(s)
			var idx = a[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		total += tris
		rows.append([tris, name, (Time.get_ticks_usec() - t0) / 1000])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows.slice(0, 12):
		print("%7d tris  %-28s %d ms" % r)
	print("props: %d, total %d tris" % [rows.size(), total])
	quit()
