extends Node
## Ambient population: keeps towns, camps and roads alive around the player. Towns get residents with stable
## identities (seed per town + slot, so the same people live there every visit) that spawn within SPAWN_R of the
## player and despawn beyond DESPAWN_R; roads get occasional travellers. If the settlement system exposes
## interaction spots (settlements.get_town(id).spots), residents get routines; otherwise they wander near home.

const SPAWN_R := 260.0
const DESPAWN_R := 360.0
const MAX_NEAR := 36

var residents := {}          # "town:slot" -> Human
var _t := 0.0
var _traveller_t := 20.0
var travellers: Array = []

const TOWN_SIZE := {"rail_town": 28, "port_town": 34, "mining_camp": 18, "desert_stop": 16}
const POI_SIZE := {"camp": 0, "ranch": 6, "homestead": 3, "logging": 8, "ruin": 2, "trading_post": 3, "cabin": 1}
const ROLES := ["townsfolk", "townsfolk", "townsfolk", "worker", "shopkeeper", "rancher", "drunk", "lady", "child",
	"preacher", "gambler", "lawman"]

func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0 or Game.player == null or Game.world == null:
		return
	_t = 0.5
	var pp: Vector3 = Game.player.global_position
	var near := 0
	for k in residents.keys():
		var h = residents[k]
		if not is_instance_valid(h):
			residents.erase(k)
			continue
		if h.global_position.distance_to(pp) > DESPAWN_R:
			h.queue_free()
			residents.erase(k)
		else:
			near += 1
	for list in [Game.world.features.towns, Game.world.features.pois]:
		for t in list:
			var tc := Vector3(t.x, 0, t.z)
			if Vector2(tc.x - pp.x, tc.z - pp.z).length() > SPAWN_R + float(t.r):
				continue
			var n: int = TOWN_SIZE.get(t.kind, POI_SIZE.get(t.kind, 2))
			for slot in n:
				var key := "%s:%d" % [t.id, slot]
				if residents.has(key) or near >= MAX_NEAR:
					continue
				var h := _spawn_resident(t, slot)
				if h != null:
					residents[key] = h
					near += 1
	_travellers(dt * 0.0 + 0.5, pp)

func _spawn_resident(t: Dictionary, slot: int) -> Human:
	var r := RandomNumberGenerator.new()
	r.seed = hash(t.id) * 31 + slot
	var home := _home_point(t, r)
	if home == Vector3.INF:
		return null
	if Game.player.global_position.distance_to(home) > SPAWN_R:
		return null
	var role: String = ROLES[r.randi() % ROLES.size()]
	var faction := "law" if role == "lawman" else "civilian"
	var weapon := "lockhart_sa" if role in ["lawman", "rancher", "gambler"] else ""
	Game.terrain.ensure_tile(home)
	var h := Human.spawn(Game.main, home + Vector3(0, 0.3, 0), {"seed": r.randi(), "role": role, "faction": faction,
		"name": _name(r), "weapon": weapon})
	h.set_meta("home_town", t.id)
	if Game.main.settlements and Game.main.settlements.has_method("get_town"):
		var info = Game.main.settlements.get_town(t.id)
		if info is Dictionary and info.has("spots") and h.brain.has_method("set_spots"):
			h.brain.set_spots(info.spots)
	return h

func _home_point(t: Dictionary, r: RandomNumberGenerator) -> Vector3:
	for attempt in 12:
		var a := r.randf() * TAU
		var d := r.randf_range(4.0, float(t.r) * 0.85)
		var p := Vector3(t.x + cos(a) * d, 0, t.z + sin(a) * d)
		if Game.world.is_water(p.x, p.z):
			continue
		p.y = Game.world.height(p.x, p.z)
		return p
	return Vector3.INF

func _travellers(dt: float, pp: Vector3) -> void:
	travellers = travellers.filter(func(h): return is_instance_valid(h))
	for h in travellers:
		if h.global_position.distance_to(pp) > DESPAWN_R:
			h.queue_free()
	_traveller_t -= dt
	if _traveller_t > 0.0 or travellers.size() >= 3:
		return
	_traveller_t = Game.rng.randf_range(25.0, 60.0)
	# pick a road point 120-220 m from the player, walking along the road
	var roads: Array = Game.world.features.roads
	for attempt in 8:
		var rd: Dictionary = roads[Game.rng.randi() % roads.size()]
		var pts: Array = rd.points
		var i := Game.rng.randi() % pts.size()
		var p := Vector3(pts[i][0], pts[i][2], pts[i][1])
		var d := p.distance_to(pp)
		if d < 120.0 or d > 220.0:
			continue
		Game.terrain.ensure_tile(p)
		var h := Human.spawn(Game.main, p + Vector3(0, 0.3, 0), {"seed": Game.rng.randi(), "role": "traveller", "faction": "civilian", "name": _name(Game.rng)})
		var j := clampi(i + (40 if Game.rng.randf() < 0.5 else -40), 0, pts.size() - 1)
		h.brain.home = Vector3(pts[j][0], pts[j][2], pts[j][1])
		h.intent.move_to = h.brain.home
		travellers.append(h)
		break

const FIRST := ["Abel", "Amos", "Asa", "Bertha", "Caleb", "Clara", "Cyrus", "Delia", "Edna", "Elias", "Etta", "Ezra",
	"Flora", "Gideon", "Hattie", "Hiram", "Ida", "Isaac", "Jonas", "Josie", "Lemuel", "Lottie", "Mabel", "Matthias",
	"Minnie", "Nell", "Obed", "Ora", "Perley", "Rufus", "Sadie", "Silas", "Tillie", "Virgil", "Walt", "Zeb", "Mateo",
	"Rosa", "Ignacio", "Lupe", "Wen", "Henrik", "Greta", "Tomas", "Bridget", "Seamus"]
const LAST := ["Abbott", "Barlow", "Birch", "Coker", "Dabney", "Ellery", "Fenwick", "Garrity", "Hollis", "Ingram",
	"Judd", "Kessler", "Larkin", "Moody", "Nance", "Oakes", "Pruett", "Quill", "Rasmussen", "Sayer", "Tolliver",
	"Upham", "Vickers", "Whitlock", "Yates", "Zeller", "Ybarra", "Ochoa", "Lindgren", "Murphy", "Doyle", "Chen"]

static func _name(r: RandomNumberGenerator) -> String:
	return "%s %s" % [FIRST[r.randi() % FIRST.size()], LAST[r.randi() % LAST.size()]]
