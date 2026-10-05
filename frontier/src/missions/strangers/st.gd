extends RefCounted
## Shared helpers for the Strangers side stories: the chapter 2/3 helpers plus a person who stands for a scene, a
## hunt (one animal, stalked and shot), fishing with the real fishing system (Game.fishing), and a trail of tracks.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")

static func flag(key: String, default = false):
	return C2.flag(key, default)

static func set_flag(key: String, value) -> void:
	C2.set_flag(key, value)

## A named stranger standing at a point, looking at Ruth (or `look`).
static func person(d, pos: Vector3, opts: Dictionary, look := Vector3.INF) -> Human:
	var o := opts.duplicate()
	if not o.has("faction"):
		o["faction"] = "civilian"
	var h := C2.spawn_friend(d, pos, o)
	if h:
		d.npc_hold(h, look if look != Vector3.INF else Game.player.global_position)
	return h

## A group that waits quietly until the mission turns it loose (C2.hostile).
static func gang(d, pos: Vector3, n: int, name: String, seed_value: int, weapon := "lockhart_sa", spread := 4.0) -> Array:
	var g: Array = d.spawn_group(pos, n, {"role": "gunman", "faction": "syndicate", "name": name, "seed": seed_value,
		"weapon": weapon, "skill": 0.35, "aggressive": false}, spread)
	for h in g:
		d.npc_hold(h, Game.player.global_position)
	return g

static func pay(dollars: float) -> void:
	if Game.state:
		Game.state.add_money(-minf(dollars, maxf(float(Game.state.money), 0.0)))

static func earn(dollars: float) -> void:
	if Game.state:
		Game.state.add_money(dollars)

static func standing(delta: float, why: String) -> void:
	if Game.state:
		Game.state.change_standing(delta, why)

static func deed(kind: String) -> void:
	if Game.state:
		Game.state.good_deed(kind)

## Hunt one animal: it is set on Ruth (a predator stalks her); returns when it's dead. Autopilot and retries kill it.
static func hunt(d, species: String, pos: Vector3, text: String, seed_value: int) -> void:
	if d.aborted():
		return
	var p := C3.dry(pos)
	Game.terrain.ensure_tile(p)
	var a: Animal = Animal.spawn(Game.main, p + Vector3(0, 0.4, 0), species, seed_value)
	d.track(a)
	a.threat = null
	a.prey = Game.player
	a.state = Animal.State.STALK
	d.set_objective(text)
	var t := 0.0
	while not d.aborted() and is_instance_valid(a) and a.alive:
		if (d.autopilot and t > 0.5) or d.resuming:
			a.damageable.apply_hit({"amount": 9999.0, "zone": "head", "attacker": Game.player if not d.resuming else null})
		if Game.player.damageable and not Game.player.damageable.alive:
			d.fail("Ruth died")
			return
		await d.get_tree().physics_frame
		t += d.get_physics_process_delta_time()
		if t > d.step_timeout * 2.0:
			d.fail("softlock: the %s was never brought down" % species)
			return
	Game.log_event("hunted", {"species": species})
	d.set_objective("")

## The nearest bank (dry ground with water a few metres off) within `r` of a point; INF if none.
static func bank_near(p: Vector3, r := 220.0) -> Vector3:
	var w = Game.world
	for rad in [8.0, 16.0, 30.0, 50.0, 80.0, 120.0, 170.0, r]:
		for k in 16:
			var a := TAU * k / 16.0
			var q := p + Vector3(cos(a), 0, sin(a)) * float(rad)
			if w.is_water(q.x, q.z):
				# step back toward p until dry
				var dir := (p - q)
				dir.y = 0.0
				dir = dir.normalized()
				for s in 12:
					var b := q + dir * (2.0 + s * 2.0)
					if not w.is_water(b.x, b.z):
						return Vector3(b.x, w.height(b.x, b.z), b.z)
	return Vector3.INF

## Fish a fish out of the nearest water with the real fishing system (a rod is lent if Ruth has none). Returns the
## species caught. Bots, retries and headless runs land one at once.
static func fish(d, near: Vector3, text: String) -> String:
	if d.aborted():
		return ""
	var st = Game.state
	if st and int(st.inventory.get("fishing_rod", 0)) <= 0:
		st.add_item("fishing_rod")
		if Game.hud and not d.autopilot:
			Game.hud.notice("A borrowed rod is in your satchel", 3.0)
	var bank := bank_near(near)
	var fs = Game.get("fishing")
	if d.autopilot or d.resuming or Game.headless or fs == null or bank == Vector3.INF:
		if bank != Vector3.INF:
			d._teleport_player(bank)
		if st:
			st.add_item("fish_brook_trout")
		Game.log_event("fishing_landed", {"species": "brook_trout", "lb": 1.4, "auto": true})
		return "brook_trout"
	var n0: int = fs.catches.size()
	await d.goto(bank, 4.0, "Go down to the water")
	if d.aborted():
		return ""
	d.set_objective(text + "  (B / D-pad left at the water's edge)")
	var t := 0.0
	while not d.aborted() and fs.catches.size() <= n0:
		await d.get_tree().physics_frame
		t += d.get_physics_process_delta_time()
		if t > 600.0:
			d.fail("softlock: no fish caught")
			return ""
	d.set_objective("")
	var c: Dictionary = fs.catches[fs.catches.size() - 1]
	return str(c.get("species", "trout"))

## Follow a trail: a few waypoints from a to b, each a marker, the objective naming what she reads in the ground.
static func trail(d, a: Vector3, b: Vector3, n: int, text: String) -> void:
	for i in range(1, n + 1):
		var f := float(i) / float(n)
		var side := sin(f * PI * 2.0) * 18.0
		var dir := (b - a)
		dir.y = 0.0
		var perp := dir.normalized().cross(Vector3.UP)
		var q := C3.dry(a.lerp(b, f) + perp * side * (1.0 - f))
		await d.goto(q, 5.0, text)
		if d.aborted():
			return
