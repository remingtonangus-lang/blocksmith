extends Node
## Wildlife ecology around the player: herds and solitary animals spawn out of sight (150-330 m) in biomes and
## hours that suit them, despawn far away, and keep a stable budget. Predators hunt prey on their own; kills and
## chases are logged for the ecology oracle.

const SPAWN_MIN := 150.0
const SPAWN_MAX := 330.0
const DESPAWN := 460.0
const BUDGET := 26
const BIRD_FLOCKS := 4           # flocks / single raptors around the player (src/actors/bird.gd)

var animals: Array = []
var birds: Array = []
var _t := 2.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 1899 * 7
	Game.set("wildlife", self)

var _queue: Array = []     # [species, pos, seed, group array] spawned a couple per frame (no hitches)

func _process(dt: float) -> void:
	for i in mini(2, _queue.size()):
		var e: Array = _queue.pop_front()
		Game.terrain.ensure_tile(e[1])
		var a := Animal.spawn(Game.main, e[1], e[0], e[2])
		var group: Array = e[3]
		group.append(a)
		animals.append(a)
		a.herd = group
		a.leader = group[0]
	_t -= dt
	if _t > 0.0 or Game.player == null or Game.world == null:
		return
	_t = 1.5
	var pp: Vector3 = Game.player.global_position
	animals = animals.filter(func(a): return is_instance_valid(a))
	for a in animals:
		if a.global_position.distance_to(pp) > DESPAWN or (not a.alive and a.global_position.distance_to(pp) > 120.0):
			a.queue_free()
	_birds_update(pp)
	if animals.size() + _queue.size() >= BUDGET:
		return
	_spawn_group(pp)

## Birds: keep a few flocks (turkeys and grouse by biome, crows anywhere, crows on town hitch rails) and one
## hawk soaring within view.
func _birds_update(pp: Vector3) -> void:
	birds = birds.filter(func(b): return is_instance_valid(b))
	for b in birds:
		if b.global_position.distance_to(pp) > DESPAWN + 100.0 or (not b.alive and b.global_position.distance_to(pp) > 120.0):
			b.queue_free()
	var flocks := {}
	var hawk := false
	for b in birds:
		if is_instance_valid(b):
			flocks[b.flock] = true
			hawk = hawk or b.species == "red_tailed_hawk"
	if not hawk:
		var a := rng.randf() * TAU
		var hp := pp + Vector3(cos(a), 0, sin(a)) * rng.randf_range(80.0, 200.0)
		if Game.world.in_bounds(hp.x, hp.z, 50.0):
			birds.append(Bird.spawn(Game.main, hp, "red_tailed_hawk", rng.randi()))
		return
	if flocks.size() >= BIRD_FLOCKS:
		return
	var w: WorldData = Game.world
	for attempt in 6:
		var ang := rng.randf() * TAU
		var p := pp + Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(120.0, 260.0)
		if not w.in_bounds(p.x, p.z, 50.0) or w.is_water(p.x, p.z) or (1.0 - w.normal(p.x, p.z).y) > 0.35:
			continue
		var biome := w.ctrl(p.x, p.z).b
		var cands := ["crow"]
		for sp in ["turkey", "sage_grouse"]:
			if biome >= Bird.SPECIES[sp].biomes[0] and biome <= Bird.SPECIES[sp].biomes[1]:
				cands.append(sp)
		var sp: String = cands[rng.randi() % cands.size()]
		var n := rng.randi_range(Bird.SPECIES[sp].flock[0], Bird.SPECIES[sp].flock[1])
		var group := []
		for i in n:
			var q := p + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
			q.y = w.height(q.x, q.z)
			var b := Bird.spawn(Game.main, q, sp, rng.randi())
			group.append(b)
			b.flock = group
			b.home = p
			birds.append(b)
		Game.log_event("wildlife_spawn", {"species": sp, "n": n, "at": [p.x, p.z]})
		return

func _spawn_group(pp: Vector3) -> void:
	var w: WorldData = Game.world
	for attempt in 6:
		var ang := rng.randf() * TAU
		var d := rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var p := pp + Vector3(cos(ang) * d, 0, sin(ang) * d)
		if not w.in_bounds(p.x, p.z, 50.0) or w.is_water(p.x, p.z) or (1.0 - w.normal(p.x, p.z).y) > 0.4:
			continue
		var near := w.nearest_settlement(p.x, p.z)
		if not near.is_empty() and Vector2(near.x - p.x, near.z - p.z).length() < float(near.r) + 120.0:
			continue
		var biome := w.ctrl(p.x, p.z).b
		var cands := []
		for sp in Animal.SPECIES.keys():
			var s: Dictionary = Animal.SPECIES[sp]
			if biome >= s.biomes[0] and biome <= s.biomes[1]:
				cands.append(sp)
		if cands.is_empty():
			continue
		var sp: String = cands[rng.randi() % cands.size()]
		var spec: Dictionary = Animal.SPECIES[sp]
		var n := rng.randi_range(spec.herd[0], spec.herd[1])
		var group := []
		for i in n:
			var q := p + Vector3(rng.randf_range(-7, 7), 0, rng.randf_range(-7, 7))
			q.y = w.height(q.x, q.z) + 0.3
			_queue.append([sp, q, rng.randi(), group])
		Game.log_event("wildlife_spawn", {"species": sp, "n": n, "at": [p.x, p.z]})
		return
