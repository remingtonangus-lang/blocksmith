class_name RoadMesh
extends Node3D
## Wagon roads as terrain-hugging ribbons over the road layer of the terrain: two wheel ruts with a hoof-churned
## crown between them, softened verges, puddles in the ruts after rain. Built from the worldgen road polylines,
## resampled every 3 m, chunked by 256 m tiles for culling and faded out with distance (the terrain's own road layer
## carries the road beyond that).

const STEP := 3.0
const HALF_W := 4.6        # covers the terrain road layer (mask fades out at 4.5 m)
const ACROSS := 9                  # vertices across the road
const TILE := 256.0
const VIS_END := 380.0

var material: ShaderMaterial

func build(world: WorldData, terrain_mat: ShaderMaterial) -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/road.gdshader")
	if terrain_mat:
		material.set_shader_parameter("tex_ah", terrain_mat.get_shader_parameter("tex_ah"))
		material.set_shader_parameter("tex_nr", terrain_mat.get_shader_parameter("tex_nr"))
	material.set_shader_parameter("fade_end", VIS_END)
	# geometry on a worker thread (heightmap sampling for ~100k vertices); meshes are made on the main thread
	var roads: Array = world.features.get("roads", []).duplicate(true)
	WorkerThreadPool.add_task(func():
		var tiles := _build_arrays(world, roads)
		_add_meshes.call_deferred(tiles), false, "road ribbons")

func _build_arrays(world: WorldData, roads: Array) -> Dictionary:
	var tiles := {}                # Vector2i -> [verts, uvs, colours]
	var along_total := 0.0
	for r in roads:
		var pts := PackedVector2Array()
		for p in r.points:
			pts.append(Vector2(p[0], p[1]))
		var samples := _resample(pts, STEP)
		if samples.size() < 2:
			continue
		var prev_l: Array = []
		for i in samples.size():
			var c: Vector2 = samples[i]
			var t: Vector2 = (samples[mini(i + 1, samples.size() - 1)] - samples[maxi(i - 1, 0)]).normalized()
			var side := Vector2(-t.y, t.x)
			var ring: Array = []
			if i > 0:
				along_total += STEP
			for k in ACROSS:
				var u := float(k) / float(ACROSS - 1)
				var q := c + side * (u * 2.0 - 1.0) * HALF_W
				var h := world.height(q.x, q.y)
				var wet := 1.0 if world.is_water(q.x, q.y) else 0.0
				ring.append([Vector3(q.x, h + 0.02, q.y), u, wet, side, along_total])   # pos, u, wet, side, along
			var tk := Vector2i(floori(c.x / TILE), floori(c.y / TILE))
			if not prev_l.is_empty():
				if not tiles.has(tk):
					tiles[tk] = [[], [], []]   # plain arrays: packed arrays read out of an Array are copies
				_quad_strip(tiles[tk], prev_l, ring)
			prev_l = ring
	return tiles

func _add_meshes(tiles: Dictionary) -> void:
	for tk in tiles.keys():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		var v := PackedVector3Array(tiles[tk][0])
		var n := PackedVector3Array()
		n.resize(v.size())
		n.fill(Vector3.UP)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array(tiles[tk][1])
		arr[Mesh.ARRAY_COLOR] = PackedColorArray(tiles[tk][2])
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = VIS_END + TILE * 0.7
		mi.name = "Road_%d_%d" % [tk.x, tk.y]
		add_child(mi)
	print("roads: %d ribbon tiles" % tiles.size())

func _quad_strip(t: Array, a: Array, b: Array) -> void:
	for k in ACROSS - 1:
		for e in [a[k], b[k], b[k + 1], a[k], b[k + 1], a[k + 1]]:
			t[0].append(e[0])
			t[1].append(Vector2(e[1], e[4]))
			t[2].append(Color(e[2], e[3].x * 0.5 + 0.5, e[3].y * 0.5 + 0.5))

static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2:
		return out
	out.append(pts[0])
	var carry := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		var d := step - carry
		while d <= seg:
			out.append(a.lerp(b, d / seg))
			d += step
		carry = seg - (d - step)
	return out
