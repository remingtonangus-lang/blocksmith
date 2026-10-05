extends RefCounted
## Shared helpers for the chapter 2 missions (Paper and Iron): dry-land placement around a town (Port Linden sits
## on the lake shore), story flags, and turning a held group of people into a fight.

## Mission.place with the offset swung round the town centre until it lands on dry ground.
static func spot(id: String, dx: float, dz: float) -> Vector3:
	var c := Mission.place(id)
	var off := Vector2(dx, dz)
	for k in 12:
		var o := off.rotated(TAU * k / 12.0)
		var p := Vector3(c.x + o.x, 0, c.z + o.y)
		if not Game.world.is_water(p.x, p.z) and not Game.world.is_water(p.x + 4.0, p.z) and not Game.world.is_water(p.x - 4.0, p.z):
			p.y = Game.world.height(p.x, p.z)
			return p
	var q := Vector3(c.x + dx * 0.3, 0, c.z + dz * 0.3)
	q.y = Game.world.height(q.x, q.z)
	return q

## A point at a fixed offset from another, nudged off water.
static func near(base: Vector3, dx: float, dz: float) -> Vector3:
	var off := Vector2(dx, dz)
	for k in 8:
		var o := off.rotated(TAU * k / 8.0)
		var p := Vector3(base.x + o.x, 0, base.z + o.y)
		if not Game.world.is_water(p.x, p.z):
			p.y = Game.world.height(p.x, p.z)
			return p
	return base

static func one(group: Array):
	return group[0] if group.size() > 0 and is_instance_valid(group[0]) else null

static func flag(key: String, default = false):
	return Game.state.flags.get(key, default) if Game.state else default

static func set_flag(key: String, value) -> void:
	if Game.state:
		Game.state.flags[key] = value

static func money() -> float:
	return float(Game.state.money) if Game.state else 0.0

## Release held people and send them at Ruth (and her friends): they become bandits for the brain's purposes.
static func hostile(d, group: Array) -> void:
	for h in group:
		if h == null or not is_instance_valid(h) or not h.alive:
			continue
		d.npc_release(h)
		h.faction = "bandit"
		h.brain.aggressive = true
		h.brain.share_target(Game.player)

## Friends who stand still for a scene and then fight on Ruth's side.
static func spawn_friend(d, pos: Vector3, opts: Dictionary) -> Human:
	var g: Array = d.spawn_group(pos, 1, opts, 0.3)
	return g[0] if g.size() > 0 else null

static func dead_count(group: Array) -> int:
	var n := 0
	for h in group:
		if h != null and is_instance_valid(h) and not h.alive:
			n += 1
	return n
