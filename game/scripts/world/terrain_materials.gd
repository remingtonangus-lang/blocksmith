class_name TerrainMaterials
## Procedural, tileable ground materials painted at load (cached in user://): 512^2 albedo+roughness and
## normal+height layers in two Texture2DArrays. Layers: 0 grass, 1 meadow, 2 forest floor, 3 rock, 4 sand,
## 5 snow, 6 Capital paving, 7 road.

const RES := 512
const LAYERS := 8
const VERSION := 3


static func build(seed: int) -> Array:
	var path := "user://terrain_mats_v%d_s%d.res" % [VERSION, seed]
	var alb: Array[Image] = []
	var nrm: Array[Image] = []
	if ResourceLoader.exists(path):
		var cached: Resource = load(path)
		if cached is TerrainMatCache:
			alb = cached.albedo
			nrm = cached.normal
	if alb.size() != LAYERS:
		alb.clear(); nrm.clear()
		alb.resize(LAYERS); nrm.resize(LAYERS)
		var out := []
		out.resize(LAYERS)
		var task := WorkerThreadPool.add_group_task(func(i: int): out[i] = _paint(i, seed), LAYERS, -1, true, "terrain materials")
		WorkerThreadPool.wait_for_group_task_completion(task)
		for i in LAYERS:
			alb[i] = out[i][0]
			nrm[i] = out[i][1]
		var c := TerrainMatCache.new()
		c.albedo = alb
		c.normal = nrm
		ResourceSaver.save(c, path, ResourceSaver.FLAG_COMPRESS)
	var a := Texture2DArray.new()
	a.create_from_images(alb)
	var b := Texture2DArray.new()
	b.create_from_images(nrm)
	return [a, b]


static func _noise(seed: int, freq: float, oct: int, kind: int = FastNoiseLite.TYPE_SIMPLEX_SMOOTH, cell_ret: int = -1) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = kind
	n.frequency = freq
	n.fractal_octaves = oct
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if oct > 1 else FastNoiseLite.FRACTAL_NONE
	if cell_ret >= 0:
		n.cellular_return_type = cell_ret
		n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	var img := n.get_seamless_image(RES, RES, false, false, 0.1, true)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


static func _paint(layer: int, seed: int) -> Array:
	var s := seed * 101 + layer * 7
	var fine := _noise(s, 0.09, 4)
	var mid := _noise(s + 1, 0.022, 4)
	var big := _noise(s + 2, 0.006, 3)
	var cells := _noise(s + 3, 0.02, 1, FastNoiseLite.TYPE_CELLULAR, FastNoiseLite.RETURN_DISTANCE2_SUB)
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var col := PackedByteArray()
	col.resize(RES * RES * 4)
	var hgt := PackedFloat32Array()
	hgt.resize(RES * RES)
	for y in RES:
		for x in RES:
			var i := y * RES + x
			var f := fine[i] / 255.0
			var m := mid[i] / 255.0
			var b := big[i] / 255.0
			var c := cells[i] / 255.0
			var rgb := Vector3()
			var rough := 0.9
			var h := 0.0
			match layer:
				0:  # grass: dense blades, darker clumps, sun-dried tips
					var blade := absf(sin((x * 0.9 + f * 14.0) * 1.3) * cos((y * 0.35 + m * 9.0)))
					rgb = Vector3(0.16, 0.26, 0.075).lerp(Vector3(0.27, 0.36, 0.11), m)
					rgb = rgb.lerp(Vector3(0.36, 0.38, 0.17), clampf((f - 0.62) * 2.5, 0.0, 1.0))
					rgb *= 0.75 + blade * 0.35 + (b - 0.5) * 0.2
					h = f * 0.6 + blade * 0.4
				1:  # meadow: lighter, drier, flowers
					rgb = Vector3(0.30, 0.33, 0.13).lerp(Vector3(0.44, 0.41, 0.20), m)
					rgb *= 0.8 + f * 0.35
					h = f
					var r := G.hash2(x, y, s)
					if r > 0.9965:
						rgb = [Vector3(0.95, 0.93, 0.85), Vector3(0.92, 0.78, 0.2), Vector3(0.55, 0.35, 0.75)][int(r * 1e5) % 3]
						h = 1.0
				2:  # forest floor: needles, leaf litter, moss
					rgb = Vector3(0.17, 0.12, 0.075).lerp(Vector3(0.29, 0.20, 0.12), f)
					rgb = rgb.lerp(Vector3(0.15, 0.22, 0.08), clampf((m - 0.55) * 3.0, 0.0, 1.0))
					var twig := clampf(1.0 - absf(sin(x * 0.21 + y * 0.67 + f * 12.0)) * 6.0, 0.0, 1.0) * float(G.hash2(x / 9, y / 9, s) > 0.7)
					rgb = rgb.lerp(Vector3(0.36, 0.27, 0.17), twig)
					h = f * 0.7 + twig * 0.3
				3:  # rock: cracked cells, strata, lichen
					var crack := clampf(c * 3.0, 0.0, 1.0)
					var strata := sin(y * 0.07 + m * 7.0) * 0.5 + 0.5
					rgb = Vector3(0.36, 0.35, 0.33).lerp(Vector3(0.52, 0.50, 0.47), f * 0.6 + strata * 0.4)
					rgb *= 0.55 + crack * 0.45
					rgb = rgb.lerp(Vector3(0.40, 0.42, 0.30), clampf((b - 0.6) * 2.0, 0.0, 0.6))
					rough = 0.78 - f * 0.1
					h = crack * 0.6 + f * 0.3 + strata * 0.1
				4:  # sand: grains and ripples
					var rip := sin(x * 0.12 + m * 9.0) * 0.5 + 0.5
					rgb = Vector3(0.66, 0.60, 0.47).lerp(Vector3(0.78, 0.71, 0.56), f * 0.6 + rip * 0.4)
					rgb *= 0.92 + (G.hash2(x, y, s + 9) - 0.5) * 0.12
					rough = 0.95
					h = rip * 0.6 + f * 0.4
				5:  # snow: soft drifts
					rgb = Vector3(0.86, 0.89, 0.94).lerp(Vector3(0.97, 0.98, 1.0), m * 0.7 + f * 0.3)
					rough = 0.55 + f * 0.2
					h = m * 0.8 + f * 0.2
				6:  # Capital paving: large white stone slabs with fine grey joints
					var tx := x % 64
					var ty := (y + (32 if (x / 64) % 2 == 1 else 0)) % 64
					var joint := float(tx < 2 or ty < 2)
					var tint := G.hash2(x / 64, (y + (32 if (x / 64) % 2 == 1 else 0)) / 64, s)
					rgb = Vector3(0.80, 0.81, 0.80).lerp(Vector3(0.90, 0.90, 0.88), tint) * (0.94 + f * 0.08)
					rgb = rgb.lerp(Vector3(0.42, 0.44, 0.45), joint)
					rough = 0.55 + f * 0.15 + joint * 0.3
					h = 1.0 - joint * 0.8 - f * 0.05
				7:  # road: asphalt with aggregate
					rgb = Vector3(0.085, 0.088, 0.094) * (0.8 + f * 0.4 + (b - 0.5) * 0.3)
					if G.hash2(x, y, s + 3) > 0.985:
						rgb = Vector3(0.3, 0.3, 0.3)
					rough = 0.88
					h = f * 0.5
			var o := i * 4
			col[o] = clampi(int(rgb.x * 255.0), 0, 255)
			col[o + 1] = clampi(int(rgb.y * 255.0), 0, 255)
			col[o + 2] = clampi(int(rgb.z * 255.0), 0, 255)
			col[o + 3] = clampi(int(rough * 255.0), 0, 255)
			hgt[i] = h
	var nrm := PackedByteArray()
	nrm.resize(RES * RES * 4)
	var strength: float = [2.0, 1.5, 2.5, 4.0, 1.5, 1.0, 3.0, 1.5][layer]
	for y in RES:
		var y0 := ((y - 1 + RES) % RES) * RES
		var y1 := ((y + 1) % RES) * RES
		for x in RES:
			var x0 := (x - 1 + RES) % RES
			var x1 := (x + 1) % RES
			var dx := (hgt[y * RES + x1] - hgt[y * RES + x0]) * strength
			var dy := (hgt[y1 + x] - hgt[y0 + x]) * strength
			var v := Vector3(-dx, -dy, 1.0).normalized()
			var o := (y * RES + x) * 4
			nrm[o] = int((v.x * 0.5 + 0.5) * 255.0)
			nrm[o + 1] = int((v.y * 0.5 + 0.5) * 255.0)
			nrm[o + 2] = int((v.z * 0.5 + 0.5) * 255.0)
			nrm[o + 3] = int(clampf(hgt[y * RES + x], 0.0, 1.0) * 255.0)
	var a := Image.create_from_data(RES, RES, false, Image.FORMAT_RGBA8, col)
	a.generate_mipmaps()
	var b2 := Image.create_from_data(RES, RES, false, Image.FORMAT_RGBA8, nrm)
	b2.generate_mipmaps()
	return [a, b2]
