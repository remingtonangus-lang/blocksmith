class_name TreeBuilder
## Procedural trees: spruce (whorls of needle cards), broadleaf (limbs + a shell of leaf-cluster cards),
## birch (slender white trunk, airy crown) and a bush. Each mesh has a bark surface and a leaf surface.
## Vertex COLOR: r = flex (0 at the base .. 1 at branch tips, for wind), g = phase, b = ambient occlusion.
## Leaf normals are blended toward the crown's radial direction so the canopy shades as a volume.
## The leaf atlas (four 512 px tiles) and bark textures are painted procedurally and cached.

enum { SPRUCE, BROADLEAF, BIRCH, BUSH }
const SPECIES := 4
const ATLAS := 1024
const TILE := 512
const VERSION := 5


# --------------------------------------------------------------------------------------------- meshes

static func build(species: int, seed: int, lod: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + species * 31 + lod * 3
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	match species:
		SPRUCE: _spruce(rng, bark, leaves, lod)
		BROADLEAF: _broadleaf(rng, bark, leaves, lod, false)
		BIRCH: _broadleaf(rng, bark, leaves, lod, true)
		BUSH: _bush(rng, leaves, lod)
	var mesh := ArrayMesh.new()
	if species != BUSH:
		bark.generate_tangents()
		bark.commit(mesh)
	leaves.commit(mesh)
	return mesh


static func height_of(species: int) -> float:
	return [24.0, 16.0, 15.0, 1.8][species]


static func _cyl(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides: int, flex_a: float, flex_b: float, v0: float, phase: float) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var w := axis.cross(u).normalized()
	var length := a.distance_to(b)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := u * cos(a0) + w * sin(a0)
		var d1 := u * cos(a1) + w * sin(a1)
		var pa0 := a + d0 * ra
		var pa1 := a + d1 * ra
		var pb0 := b + d0 * rb
		var pb1 := b + d1 * rb
		var u0 := float(i) / sides
		var u1 := float(i + 1) / sides
		var va := v0
		var vb := v0 + length / 2.0
		for q in [[pa0, d0, u0, va, flex_a], [pb0, d0, u0, vb, flex_b], [pa1, d1, u1, va, flex_a],
				[pa1, d1, u1, va, flex_a], [pb0, d0, u0, vb, flex_b], [pb1, d1, u1, vb, flex_b]]:
			st.set_color(Color(q[4], phase, 1.0))
			st.set_normal(q[1])
			st.set_uv(Vector2(q[2], q[3]))
			st.add_vertex(q[0])


## A leaf card: centre c, spanning `right` (half width) and `up` (half height), atlas tile, normal blend target.
static func _card(st: SurfaceTool, c: Vector3, right: Vector3, up: Vector3, tile: int, radial: Vector3, flex: float, phase: float, ao: float, flip: bool = false) -> void:
	var tx := float(tile % 2) * 0.5
	var ty := float(tile / 2) * 0.5
	var n := right.cross(up).normalized()
	if n.dot(radial) < 0.0:
		n = -n
	var nn := (n * 0.35 + radial.normalized() * 0.65).normalized()
	var corners := [c - right - up, c + right - up, c + right + up, c - right + up]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	if flip:
		uvs = [Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)]
	var flexes := [flex * 0.7, flex * 0.7, flex, flex]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color(flexes[k], phase, ao))
		st.set_normal(nn)
		st.set_uv(Vector2(tx, ty) + uvs[k] * 0.5)
		st.add_vertex(corners[k])


static func _spruce(rng: RandomNumberGenerator, bark: SurfaceTool, leaves: SurfaceTool, lod: int) -> void:
	var H := rng.randf_range(20.0, 28.0)
	var r0 := H * 0.02
	var bend := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
	var segs := 5 if lod == 0 else 2
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var p0 := Vector3(0, H * t0 * 0.97, 0) + bend * t0 * t0
		var p1 := Vector3(0, H * t1 * 0.97, 0) + bend * t1 * t1
		_cyl(bark, p0 + Vector3(0, -0.3 if i == 0 else 0.0, 0), p1, r0 * (1.0 - t0 * 0.9), r0 * (1.0 - t1 * 0.9), 7 if lod == 0 else 5, t0 * 0.3, t1 * 0.3, H * t0, 0.0)
	var start := H * rng.randf_range(0.12, 0.2)
	var spacing := 0.62 if lod == 0 else 1.25
	var h := start
	var whorl := 0
	while h < H * 0.96:
		var t := (h - start) / (H - start)
		var L := (H - h) * 0.31 + 0.35
		var n := 6 if lod == 0 else 4
		var rot := whorl * 2.39996
		var centre := Vector3(0, h, 0) + bend * pow(h / H, 2.0)
		for b in n:
			var a := rot + TAU * b / n + rng.randf_range(-0.2, 0.2)
			var dir := Vector3(cos(a), 0.0, sin(a))
			var droop := lerpf(-0.28, 0.05, t) + rng.randf_range(-0.08, 0.08)
			var along := (dir + Vector3(0, droop, 0)).normalized()
			var side := Vector3.UP.cross(dir).normalized()
			var mid := centre + along * L * 0.5
			var flex := 0.35 + 0.65 * clampf(L / 6.0, 0.0, 1.0)
			var radial := (dir * 0.8 + Vector3(0, 0.6, 0)).normalized()
			var ao := lerpf(0.55, 1.0, t)
			# Two crossed cards per branch: flat spray and a tilted one for volume.
			_card(leaves, mid, along * L * 0.55, side * L * 0.28, 0, radial, flex, a, ao)
			var tilt := (side * 0.5 + Vector3.UP * 0.86).normalized() * L * 0.22
			_card(leaves, mid + Vector3(0, 0.05, 0), along * L * 0.55, tilt, 0, radial, flex, a + 1.0, ao, true)
		h += spacing * rng.randf_range(0.85, 1.15)
		whorl += 1
	# Leader at the top.
	var top := Vector3(0, H * 0.97, 0) + bend
	_card(leaves, top + Vector3(0, -0.6, 0), Vector3(0, 0.9, 0), Vector3(0.35, 0, 0), 0, Vector3.UP, 0.6, 0.3, 1.0)
	_card(leaves, top + Vector3(0, -0.6, 0), Vector3(0, 0.9, 0), Vector3(0, 0, 0.35), 0, Vector3.UP, 0.6, 0.9, 1.0)


static func _broadleaf(rng: RandomNumberGenerator, bark: SurfaceTool, leaves: SurfaceTool, lod: int, birch: bool) -> void:
	var H := rng.randf_range(14.0, 19.0) if not birch else rng.randf_range(13.0, 17.0)
	var r0 := H * (0.03 if not birch else 0.017)
	var split := H * (0.38 if not birch else 0.55)
	var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)) * (1.6 if birch else 1.0)
	var trunk_top := Vector3(0, split, 0) + lean * 0.4
	_cyl(bark, Vector3(0, -0.4, 0), trunk_top, r0 * 1.25, r0 * 0.85, 8 if lod == 0 else 5, 0.0, 0.08, 0.0, 0.0)
	var crown_c := Vector3(0, H * (0.62 if not birch else 0.66), 0) + lean
	var crown_r := Vector3(H * 0.36, H * 0.3, H * 0.36) if not birch else Vector3(H * 0.22, H * 0.32, H * 0.22)
	var limbs := 4 if not birch else 3
	var tips: Array[Vector3] = []
	for i in limbs:
		var a := TAU * i / limbs + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(a), 0, sin(a))
		var tip := crown_c + out * crown_r.x * rng.randf_range(0.45, 0.7) + Vector3(0, crown_r.y * rng.randf_range(0.1, 0.6), 0)
		var mid := trunk_top.lerp(tip, 0.5) + Vector3(0, 0.6, 0)
		_cyl(bark, trunk_top, mid, r0 * 0.8, r0 * 0.5, 6 if lod == 0 else 4, 0.08, 0.4, split, a)
		_cyl(bark, mid, tip, r0 * 0.5, r0 * 0.15, 5 if lod == 0 else 3, 0.4, 0.8, split + 3.0, a)
		tips.append(tip)
	_cyl(bark, trunk_top, crown_c + Vector3(0, crown_r.y * 0.7, 0), r0 * 0.7, r0 * 0.1, 5, 0.1, 0.8, split, 0.0)
	# The crown is a cluster of lobes (one per limb tip, one on top, a few fillers) so the silhouette is lumpy.
	var lobes: Array = []
	for tp in tips:
		lobes.append([tp + Vector3(0, crown_r.y * 0.15, 0), crown_r.x * rng.randf_range(0.42, 0.55)])
	lobes.append([crown_c + Vector3(0, crown_r.y * 0.55, 0), crown_r.x * rng.randf_range(0.45, 0.6)])
	for i in 3:
		var a := rng.randf() * TAU
		lobes.append([crown_c + Vector3(cos(a) * crown_r.x * 0.5, rng.randf_range(-0.2, 0.4) * crown_r.y, sin(a) * crown_r.z * 0.5), crown_r.x * rng.randf_range(0.35, 0.5)])
	var n := (150 if not birch else 120) if lod == 0 else (50 if not birch else 40)
	var tile := 1 if not birch else 2
	var sz_min := 1.0 if not birch else 0.75
	var sz_max := 1.6 if not birch else 1.15
	if lod > 0:
		sz_min *= 1.5
		sz_max *= 1.5
	for i in n:
		var lobe: Array = lobes[i % lobes.size()]
		var lc: Vector3 = lobe[0]
		var lr: float = lobe[1]
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var r := rng.randf_range(0.55, 1.0)
		var p := lc + d * lr * r * Vector3(1.0, 0.8, 1.0) * (Vector3(1.0, 1.4, 1.0) if birch else Vector3.ONE)
		var radial := (p - crown_c).normalized().lerp(d, 0.5).normalized()
		var s := rng.randf_range(sz_min, sz_max)
		var right := radial.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized())
		if right.length() < 0.1:
			right = Vector3.RIGHT
		right = right.normalized() * s
		var up := right.cross(radial).normalized() * s
		if birch:
			up = (up + Vector3(0, -s * 0.6, 0)).normalized() * s * 1.1
		var hgt := clampf((p.y - (crown_c.y - crown_r.y)) / (crown_r.y * 2.0), 0.0, 1.0)
		var ao := lerpf(0.45, 1.0, hgt) * lerpf(0.65, 1.0, r)
		_card(leaves, p, right, up, tile, radial, 0.7 + r * 0.3, rng.randf() * TAU, ao, rng.randf() < 0.5)


static func _bush(rng: RandomNumberGenerator, leaves: SurfaceTool, lod: int) -> void:
	var R := rng.randf_range(0.9, 1.5)
	var c := Vector3(0, R * 0.55, 0)
	var n := 26 if lod == 0 else 12
	for i in n:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-1, 1)).normalized()
		var p := c + d * R * rng.randf_range(0.3, 0.9)
		var s := rng.randf_range(0.55, 0.85) * R
		var right := d.cross(Vector3(rng.randf_range(-1, 1), 0.3, rng.randf_range(-1, 1)).normalized())
		if right.length() < 0.1:
			right = Vector3.RIGHT
		right = right.normalized() * s
		var up := right.cross(d).normalized() * s
		_card(leaves, p, right, up, 3, d, 0.3 + d.y * 0.3, rng.randf() * TAU, lerpf(0.55, 1.0, (p.y) / (R * 1.3)))


# ------------------------------------------------------------------------------------------- textures

static func leaf_atlas() -> Image:
	var path := "user://leaf_atlas_v%d.png" % VERSION
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img and img.get_width() == ATLAS:
			img.generate_mipmaps()
			return img
	var data := PackedByteArray()
	data.resize(ATLAS * ATLAS * 4)
	var tiles := []
	tiles.resize(4)
	var task := WorkerThreadPool.add_group_task(func(i: int): tiles[i] = _paint_tile(i), 4, -1, true, "leaf atlas")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for t in 4:
		var src: PackedByteArray = tiles[t]
		var ox := (t % 2) * TILE
		var oy := (t / 2) * TILE
		for y in TILE:
			var so := y * TILE * 4
			var dof := ((oy + y) * ATLAS + ox) * 4
			for k in TILE * 4:
				data[dof + k] = src[so + k]
	var out := Image.create_from_data(ATLAS, ATLAS, false, Image.FORMAT_RGBA8, data)
	out.save_png(path)
	out.generate_mipmaps()
	return out


static func _paint_tile(tile: int) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(TILE * TILE * 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + tile
	var bg: Color = [Color(0.1, 0.16, 0.07), Color(0.16, 0.24, 0.08), Color(0.24, 0.32, 0.1), Color(0.15, 0.22, 0.08)][tile]
	for i in TILE * TILE:
		buf[i * 4] = int(bg.r * 255.0); buf[i * 4 + 1] = int(bg.g * 255.0); buf[i * 4 + 2] = int(bg.b * 255.0); buf[i * 4 + 3] = 0
	match tile:
		0: # spruce spray: a stem along x with side twigs, dense short needles
			var stem_y := TILE * 0.5
			_line(buf, Vector2(8, stem_y), Vector2(TILE - 10, stem_y + 6), 3.0, Color(0.25, 0.17, 0.1))
			for twig in 9:
				var x0 := 40.0 + twig * 50.0
				var side := 1.0 if twig % 2 == 0 else -1.0
				var end := Vector2(x0 + 70.0, stem_y + side * rng.randf_range(120.0, 190.0) * (1.0 - twig / 12.0))
				_line(buf, Vector2(x0, stem_y), end, 2.0, Color(0.27, 0.19, 0.11))
				_needles(buf, rng, Vector2(x0, stem_y), end, 70)
			_needles(buf, rng, Vector2(8, stem_y), Vector2(TILE - 10, stem_y + 6), 260)
		1: # broadleaf cluster: twigs radiating, layered oval leaves with a midrib
			var c := Vector2(TILE * 0.5, TILE * 0.55)
			for i in 7:
				var a := TAU * i / 7.0 + rng.randf_range(-0.2, 0.2)
				_line(buf, c, c + Vector2(cos(a), sin(a)) * 170.0, 2.5, Color(0.28, 0.2, 0.13))
			for i in 150:
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * 200.0
				var p := c + Vector2(cos(a), sin(a)) * r
				var col := Color(0.14, 0.27, 0.07).lerp(Color(0.33, 0.45, 0.13), rng.randf())
				col = col.lerp(Color(0.42, 0.42, 0.12), 0.25 * rng.randf() * float(r > 150.0))
				_leaf(buf, p, rng.randf() * TAU, rng.randf_range(26.0, 40.0), rng.randf_range(12.0, 18.0), col)
		2: # birch: small serrated light leaves on hanging twigs
			for tw in 9:
				var top := Vector2(rng.randf_range(40, TILE - 40), rng.randf_range(10, 120))
				var bot := top + Vector2(rng.randf_range(-60, 60), rng.randf_range(260, 380))
				_line(buf, top, bot, 1.6, Color(0.3, 0.22, 0.16))
				for k in 16:
					var p := top.lerp(bot, rng.randf()) + Vector2(rng.randf_range(-28, 28), rng.randf_range(-10, 10))
					var col := Color(0.3, 0.45, 0.12).lerp(Color(0.5, 0.6, 0.2), rng.randf())
					_leaf(buf, p, PI * 0.5 + rng.randf_range(-0.8, 0.8), rng.randf_range(18.0, 26.0), rng.randf_range(12.0, 16.0), col)
		3: # bush: dense small leaves
			var c := Vector2(TILE * 0.5, TILE * 0.5)
			for i in 260:
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * 225.0
				var col := Color(0.13, 0.24, 0.07).lerp(Color(0.3, 0.42, 0.12), rng.randf())
				_leaf(buf, c + Vector2(cos(a), sin(a)) * r, rng.randf() * TAU, rng.randf_range(16.0, 26.0), rng.randf_range(8.0, 13.0), col)
	return buf


static func _plot(buf: PackedByteArray, x: int, y: int, col: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= TILE or y >= TILE:
		return
	var o := (y * TILE + x) * 4
	buf[o] = int(col.r * 255.0); buf[o + 1] = int(col.g * 255.0); buf[o + 2] = int(col.b * 255.0)
	buf[o + 3] = maxi(buf[o + 3], int(a * 255.0))


static func _line(buf: PackedByteArray, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var n := int(a.distance_to(b))
	for i in n:
		var p := a.lerp(b, float(i) / maxf(1.0, n))
		var r := int(ceil(w))
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy <= w * w:
					_plot(buf, int(p.x) + dx, int(p.y) + dy, col, 1.0)


static func _needles(buf: PackedByteArray, rng: RandomNumberGenerator, a: Vector2, b: Vector2, count: int) -> void:
	var dir := (b - a).normalized()
	var nrm := dir.orthogonal()
	for i in count:
		var t := rng.randf()
		var p := a.lerp(b, t)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var d := (nrm * side + dir * rng.randf_range(0.2, 0.9)).normalized()
		var L := rng.randf_range(18.0, 34.0) * (1.0 - t * 0.4)
		var col := Color(0.07, 0.15, 0.06).lerp(Color(0.2, 0.32, 0.13), rng.randf())
		var n := int(L)
		for k in n:
			var q := p + d * k
			_plot(buf, int(q.x), int(q.y), col, 1.0)
			_plot(buf, int(q.x) + 1, int(q.y), col, 1.0)


static func _leaf(buf: PackedByteArray, c: Vector2, ang: float, L: float, W: float, col: Color) -> void:
	var ca := cos(ang)
	var sa := sin(ang)
	var r := int(L) + 1
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var u := (dx * ca + dy * sa) / L
			var v := (-dx * sa + dy * ca) / W
			# Pointed oval: narrower toward the tip.
			var w := 1.0 - u * u
			if w <= 0.0:
				continue
			var vv := v / (sqrt(w) * (1.0 - 0.35 * maxf(u, 0.0)))
			if absf(vv) > 1.0:
				continue
			var shade := 0.82 + 0.25 * (1.0 - absf(vv)) - 0.15 * u
			var c2 := col * shade
			if absf(v) < 0.08:
				c2 = col.lerp(Color(0.55, 0.6, 0.3), 0.35)
			c2.a = 1.0
			_plot(buf, int(c.x) + dx, int(c.y) + dy, c2, 1.0)


static func bark_texture(birch: bool) -> ImageTexture:
	var w := 256
	var h := 512
	var img := Image.create(w, h, true, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 9 if birch else 3
	n.frequency = 0.05
	n.fractal_octaves = 4
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for y in h:
		for x in w:
			var fx := float(x) / w
			# Wrap horizontally (around the trunk) by sampling on a circle.
			var nx := cos(fx * TAU) * 40.0
			var nz := sin(fx * TAU) * 40.0
			var v := n.get_noise_3d(nx, y * 0.25, nz) * 0.5 + 0.5
			var streak := n.get_noise_3d(nx * 3.0, y * 0.05, nz * 3.0) * 0.5 + 0.5
			var c: Color
			if birch:
				c = Color(0.86, 0.85, 0.8) * (0.85 + v * 0.2)
				var lent := n.get_noise_3d(nx * 2.0, y * 1.6, nz * 2.0)
				if lent > 0.38:
					c = Color(0.12, 0.11, 0.1)
				elif streak > 0.72:
					c = c.lerp(Color(0.5, 0.48, 0.45), 0.5)
			else:
				c = Color(0.23, 0.17, 0.12) * (0.6 + v * 0.6)
				var groove := absf(sin(fx * TAU * 9.0 + streak * 5.0))
				c *= 0.55 + groove * 0.5
			var o := (y * w + x) * 4
			data[o] = clampi(int(c.r * 255.0), 0, 255)
			data[o + 1] = clampi(int(c.g * 255.0), 0, 255)
			data[o + 2] = clampi(int(c.b * 255.0), 0, 255)
			data[o + 3] = 255
	img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
