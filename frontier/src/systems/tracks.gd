class_name Tracks
extends Node3D
## Tracks and blood trails: a pool of ground decals. Animals near the player leave prints along their path
## (cloven hooves for deer, elk, pronghorn and bison; paws for canids and the cougar; plantigrade prints for
## bears and raccoons; the jackrabbit's bound; three-toed bird prints). A wounded animal leaves blood drops
## along its path, denser for worse wounds, and a pool where it dies. The textures are painted at start-up; old
## marks fade and the pool is recycled.
## API: Tracks.print_at(pos, heading, kind, size), Tracks.blood_at(pos, amount), Tracks.count(kind).

const MAX_MARKS := 320
const FADE_TIME := 600.0           # seconds of game time until a print is gone

static var inst: Tracks = null
var _pool: Array[Decal] = []
var _age: Array[float] = []
var _kind: Array[String] = []
var _next := 0
var _tex := {}
var counts := {}                   # kind -> marks laid (oracle / tests)

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

func _process(dt: float) -> void:
	# fade marks with age (a few per frame)
	for k in 12:
		var i := (_next + k * 27) % _pool.size()
		if _age[i] == INF:
			continue
		_age[i] += dt * 12.0
		var a := clampf(1.0 - _age[i] / FADE_TIME, 0.0, 1.0)
		_pool[i].albedo_mix = a * 0.92
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
	d.size = size
	d.global_transform = Transform3D(Basis(Vector3.UP, heading), pos + Vector3(0, 0.1, 0))
	d.albedo_mix = 0.92
	d.visible = true
	counts[kind] = int(counts.get(kind, 0)) + 1

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
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a * (0.85 + 0.15 * rng.randf())))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
