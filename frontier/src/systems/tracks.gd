class_name Tracks
extends Node3D
## Tracks and blood trails: a pool of ground decals. Animals near the player leave prints along their path
## (cloven hooves for deer, elk, pronghorn and bison; paws for canids and the cougar; plantigrade prints for
## bears and raccoons; the jackrabbit's bound; three-toed bird prints). A wounded animal leaves blood drops
## along its path, denser for worse wounds, and a pool where it dies. The textures are painted at start-up; old
## marks fade and the pool is recycled. Prints are pressed in: a normal map (from the print's depth mask) shades
## the walls of each hoof or paw; in mud (wet bottoms, roads after rain) they are darker, sharper and deeper, on
## dry sand and hardpan fainter.
## API: Tracks.print_at(pos, heading, kind, size), Tracks.blood_at(pos, amount), Tracks.count(kind).

const MAX_MARKS := 320
const FADE_TIME := 600.0           # seconds of game time until a print is gone

static var inst: Tracks = null
var _pool: Array[Decal] = []
var _age: Array[float] = []
var _kind: Array[String] = []
var _mix: Array[float] = []        # albedo_mix at laying (mud: more)
var _next := 0
var _tex := {}
var _nrm := {}
var counts := {}                   # kind -> marks laid (oracle / tests)
var last_mud := 0.0                # mud factor of the last mark (tests)

static func ensure() -> Tracks:
	if inst == null or not is_instance_valid(inst):
		inst = Tracks.new()
		inst.name = "Tracks"
		var parent: Node = Game.main if Game.main else Engine.get_main_loop().root
		parent.add_child(inst)
	return inst

func _ready() -> void:
	var n := MAX_MARKS if Game.quality_name != "quest" else 80
	for kind in ["cloven", "paw", "plantigrade", "rabbit", "bird", "blood", "pool"]:
		_tex[kind] = _paint(kind)
	for i in n:
		var d := Decal.new()
		d.visible = false
		d.cull_mask = 1
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		add_child(d)
		_pool.append(d)
		_age.append(INF)
		_kind.append("")
		_mix.append(0.92)

func _process(dt: float) -> void:
	# fade marks with age (a few per frame)
	for k in 12:
		var i := (_next + k * 27) % _pool.size()
		if _age[i] == INF:
			continue
		_age[i] += dt * 12.0
		var a := clampf(1.0 - _age[i] / FADE_TIME, 0.0, 1.0)
		_pool[i].albedo_mix = a * _mix[i]
		if a <= 0.0:
			_pool[i].visible = false
			_age[i] = INF

static func print_at(pos: Vector3, heading: float, kind: String, size: float) -> void:
	ensure()._place(pos, heading, kind, Vector3(size * 0.6, 0.3, size))

static func blood_at(pos: Vector3, amount: float, pool := false) -> void:
	var s := clampf(0.06 + amount * 0.12, 0.06, 0.35) if not pool else clampf(0.4 + amount * 0.5, 0.4, 1.4)
	ensure()._place(pos, randf() * TAU, "pool" if pool else "blood", Vector3(s, 0.4, s))

static func count(kind: String) -> int:
	return int(inst.counts.get(kind, 0)) if inst != null and is_instance_valid(inst) else 0

func _place(pos: Vector3, heading: float, kind: String, size: Vector3) -> void:
	var d := _pool[_next]
	_age[_next] = 0.0
	_kind[_next] = kind
	_next = (_next + 1) % _pool.size()
	d.texture_albedo = _tex[kind]
	d.texture_normal = _nrm.get(kind)
	d.size = size
	d.global_transform = Transform3D(Basis(Vector3.UP, heading), pos + Vector3(0, 0.1, 0))
	var m := mud_at(pos) if not kind in ["blood", "pool"] else 0.0
	var dry := dry_at(pos) if m < 0.1 and not kind in ["blood", "pool"] else 0.0
	var mix := lerpf(0.92, 1.0, m) * (1.0 - 0.35 * dry)
	var shade := 1.0 - 0.5 * m
	d.modulate = Color(shade, shade * 0.97, shade * 0.95)
	d.normal_fade = 0.0
	_mix[(_next - 1 + _pool.size()) % _pool.size()] = mix
	d.albedo_mix = mix
	last_mud = m
	d.visible = true
	counts[kind] = int(counts.get(kind, 0)) + 1

## 0..1 how muddy the ground is here: wet bottoms (moisture), roads and grass after rain (sky.wet).
static var mud_override := -1.0     # tests: force the mud factor

static func mud_at(pos: Vector3) -> float:
	if mud_override >= 0.0:
		return mud_override
	var w: WorldData = Game.world
	if w == null or not w.ok:
		return 0.0
	var c := w.ctrl(pos.x, pos.z)
	var wet := float(Game.sky.get("wet")) if Game.sky != null else 0.0
	var m := clampf((c.g - 0.65) / 0.25, 0.0, 1.0)
	if c.r > 0.45:
		m = maxf(m, clampf((wet - 0.3) / 0.4, 0.0, 1.0))
	m = maxf(m, clampf((wet - 0.5) / 0.4, 0.0, 1.0) * clampf((c.g - 0.3) / 0.4, 0.0, 1.0))
	var gh := w.height(pos.x, pos.z)
	for o in [Vector2.ZERO, Vector2(3.5, 0), Vector2(-3.5, 0), Vector2(0, 3.5), Vector2(0, -3.5)]:
		if w.water_level(pos.x + o.x, pos.z + o.y) > gh - 0.6:
			m = maxf(m, 0.8)                                      # lake shore and river banks
			break
	return m

## 0..1 dry hardpan / sand (desert, low moisture): prints show less.
static func dry_at(pos: Vector3) -> float:
	var w: WorldData = Game.world
	if w == null or not w.ok:
		return 0.0
	var c := w.ctrl(pos.x, pos.z)
	return clampf((0.3 - c.b) / 0.2, 0.0, 1.0) * clampf((0.4 - c.g) / 0.3, 0.0, 1.0)

## Normal map of a pressed-in print: the depth mask as a height field (h = -mask), its gradient tilts the
## normals so the print's walls catch the light on one side and fall into shade on the other.
func _paint_normal(mask: PackedFloat32Array, n: int, depth: float) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var hl := mask[y * n + maxi(x - 1, 0)]
			var hr := mask[y * n + mini(x + 1, n - 1)]
			var hu := mask[maxi(y - 1, 0) * n + x]
			var hd := mask[mini(y + 1, n - 1) * n + x]
			# h = -mask: dh/dx = -(hr - hl) / 2 ; normal = (-dh/dx, dh/dy, 1) with image y down (OpenGL convention)
			var nx := (hr - hl) * 0.5 * depth
			var ny := -(hd - hu) * 0.5 * depth
			var nv := Vector3(nx, ny, 1.0).normalized()
			img.set_pixel(x, y, Color(nv.x * 0.5 + 0.5, nv.y * 0.5 + 0.5, nv.z * 0.5 + 0.5, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Paint a print / blood texture (alpha mask, darkened earth or blood colour), 64x64.
func _paint(kind: String) -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var col := Color(0.07, 0.055, 0.04) if not kind in ["blood", "pool"] else Color(0.32, 0.03, 0.03)
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	var blobs := []                # [cx, cy, rx, ry] in 0..1 (y = forward)
	match kind:
		"cloven":
			blobs = [[0.36, 0.55, 0.13, 0.32], [0.64, 0.55, 0.13, 0.32], [0.3, 0.12, 0.06, 0.06], [0.7, 0.12, 0.06, 0.06]]
		"paw":
			blobs = [[0.5, 0.35, 0.2, 0.17], [0.26, 0.62, 0.08, 0.1], [0.42, 0.75, 0.08, 0.1], [0.58, 0.75, 0.08, 0.1], [0.74, 0.62, 0.08, 0.1]]
		"plantigrade":
			blobs = [[0.5, 0.38, 0.26, 0.3], [0.2, 0.78, 0.07, 0.08], [0.36, 0.86, 0.07, 0.08], [0.52, 0.88, 0.07, 0.08], [0.68, 0.85, 0.07, 0.08], [0.82, 0.76, 0.07, 0.08]]
		"rabbit":
			blobs = [[0.3, 0.55, 0.1, 0.38], [0.7, 0.55, 0.1, 0.38]]
		"bird":
			blobs = []
		"blood":
			for k in 7:
				blobs.append([0.5 + rng.randf_range(-0.3, 0.3), 0.5 + rng.randf_range(-0.3, 0.3), rng.randf_range(0.04, 0.14), 0.0])
		"pool":
			blobs = [[0.5, 0.5, 0.36, 0.0], [0.38, 0.42, 0.22, 0.0], [0.62, 0.6, 0.2, 0.0]]
	var mask := PackedFloat32Array()
	mask.resize(n * n)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n
			var v := 1.0 - (y + 0.5) / n
			var a := 0.0
			for b in blobs:
				var ry: float = b[3] if b[3] > 0.0 else b[2]
				var dd := pow((u - b[0]) / b[2], 2.0) + pow((v - b[1]) / ry, 2.0)
				a = maxf(a, clampf((1.0 - dd) * 3.0, 0.0, 1.0))
			if kind == "bird":
				# three forward toes and a hind toe from the centre
				for ang in [-0.5, 0.0, 0.5, PI]:
					var dx := sin(ang)
					var dy := cos(ang)
					var t := clampf((u - 0.5) * dx + (v - 0.4) * dy, 0.0, 0.42 if ang != PI else 0.2)
					var px := 0.5 + dx * t
					var py := 0.4 + dy * t
					var dd2 := Vector2(u - px, v - py).length()
					a = maxf(a, clampf((0.045 - dd2) * 40.0, 0.0, 1.0))
			mask[y * n + x] = a
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a * (0.85 + 0.15 * rng.randf())))
	if not kind in ["blood", "pool"]:
		_nrm[kind] = _paint_normal(mask, n, 2.2)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
