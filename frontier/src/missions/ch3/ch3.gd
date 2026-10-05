extends RefCounted
## Shared helpers for chapter 3 (Dry Season): the chapter 2 helpers plus horse handling, road points with a
## fallback, the trail herd and mission riders.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const HERD = preload("res://src/missions/ch3/herd.gd")
const OUTRIDER = preload("res://src/missions/ch3/outrider.gd")

static func road(a: String, b: String, f: float, fallback_id := "") -> Vector3:
	var p := Mission.road_point(a, b, f)
	if p == Vector3.ZERO:
		p = Mission.place(fallback_id if fallback_id != "" else b)
	return dry(p)

## Off water (nudged outward in a ring).
static func dry(p: Vector3) -> Vector3:
	if not Game.world.is_water(p.x, p.z):
		return Vector3(p.x, Game.world.height(p.x, p.z), p.z)
	for r in [6.0, 12.0, 24.0, 40.0]:
		for k in 8:
			var q: Vector3 = p + Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0)) * float(r)
			if not Game.world.is_water(q.x, q.z):
				return Vector3(q.x, Game.world.height(q.x, q.z), q.z)
	return p

## Point at the yaw that looks from a toward b.
static func yaw_to(a: Vector3, b: Vector3) -> float:
	return atan2(-(b.x - a.x), -(b.z - a.z))

## Start a scene with Ruth at a point and her horse beside her (mounted if asked; bots always ride).
static func start_at(d, p: Vector3, look: Vector3, mounted := false) -> void:
	var on = Game.player.get("on_horse")
	if on != null and not mounted:
		d.dismount_player()
	d.place_player(p, yaw_to(p, look))
	var horse = Horse.player_horse if is_instance_valid(Horse.player_horse) else null
	if horse != null and horse.rider == null:
		d._put_on_ground(horse, p + Vector3(2.5, 0, 1.0))
		horse.unhitch()
	if mounted:
		await d.mount_up("Mount up")

static func herd(d, center: Vector3, count: int, seed_value: int):
	var h = HERD.new()
	Game.main.add_child(h)
	h.setup(center, count, seed_value)
	d.track(h)
	return h

static func rider(d, pos: Vector3, opts: Dictionary, breed := "mustang"):
	return OUTRIDER.create(d, pos, opts, breed)

static func flag(key: String, default = false):
	return C2.flag(key, default)

static func set_flag(key: String, value) -> void:
	C2.set_flag(key, value)
