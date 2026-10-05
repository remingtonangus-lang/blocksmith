extends Node
## Ambient population: keeps towns, camps and roads alive around the player.
##
## Towns (once the settlement is built): a stable cast per town from TownSchedule.cast — a worker for every job
## building (bartender, storekeepers, sheriff + night deputy, barber, doctor, blacksmith, tellers, cook...), residents
## with homes and habits, a gambler, drunks and children. Each resident runs a TownRoutine (src/ai/routine.gd) on
## the settlement's interaction spots: shops open and close, the saloon fills at night, people walk home and go
## indoors (despawned until the schedule brings them out again). Residents spawn within SPAWN_R of Ruth — straight
## onto the spot their hour puts them on when she arrives, out of their front door when she is already nearby —
## and despawn beyond DESPAWN_R. This node owns the spot claims, the town index (buildings by role, street spots,
## patrol route, school yard), shared bark pacing, per-resident memory of Ruth, crowds and the town metrics.
##
## POIs (ranches, homesteads, logging camps) keep simple residents that wander near home; roads get travellers.

const SPAWN_R := 260.0
const DESPAWN_R := 360.0
const MAX_NEAR := 64
const SPAWNS_PER_TICK := 6

const POI_SIZE := {"camp": 0, "ranch": 6, "homestead": 3, "logging": 8, "ruin": 2, "trading_post": 3, "cabin": 1}
const POI_ROLES := ["townsfolk", "townsfolk", "worker", "rancher", "worker", "woman"]
const TOWN_FALLBACK := {"rail_town": 28, "port_town": 34, "mining_camp": 18, "desert_stop": 16}
const HOMES := ["house", "cabin", "tent", "shack", "adobe", "hotel"]

var residents := {}          # resident key -> Human (spawned)
var casts := {}              # town id -> [resident record]
var index := {}              # town id -> town index (see _index)
var memory := {}             # resident key -> {greeted: game hour, threatened: game hour}
var indoors := {}            # resident key -> true while they are home behind their door
var metrics := {"trips": 0, "reached": 0, "failed": 0, "skipped": 0, "home": 0, "chats": 0, "doors": 0,
	"stuck": 0, "samples": 0, "on_schedule": 0.0, "npc_seconds": 0.0, "greetings": 0, "fled_inside": 0,
	"reports": 0, "crowd": 0, "nudges": 0, "spawned": 0}
var spectacles: Array = []   # [{pos, until, kind}]
var _t := 0.0
var _sample_t := 5.0
var _traveller_t := 20.0
var travellers: Array = []
var _bark_until := 0.0
var _seen_town := {}         # town id -> true once Ruth has been near (first fill places people on spots)

var _pending_spectacles: Array = []
var _last_gunfire := -100.0

func _ready() -> void:
	Game.population = self
	Game.noise.connect(func(_p: Vector3, radius: float, _s: Node): if radius >= 100.0: _last_gunfire = Time.get_ticks_msec() * 0.001)

## A body fell in town: once the shooting has stopped for a while, people come out and gather round.
func queue_spectacle(pos: Vector3) -> void:
	_pending_spectacles.append(pos)

func _process(dt: float) -> void:
	_t -= dt
	_sample_t -= dt
	if Game.player == null or Game.world == null:
		return
	if _sample_t <= 0.0:
		_sample_t = 5.0
		_sample()
	if _t > 0.0:
		return
	_t = 0.5
	if not _pending_spectacles.is_empty() and Time.get_ticks_msec() * 0.001 - _last_gunfire > 10.0:
		for sp in _pending_spectacles:
			spectacle(sp, 50.0, "body")
		_pending_spectacles.clear()
	_tick(false)
	_yield_to_story()
	_travellers(0.5, Game.player.global_position)

func _tick(fill: bool) -> void:
	var pp: Vector3 = Game.player.global_position
	var near := 0
	for k in residents.keys():
		var h = residents[k]
		if not is_instance_valid(h):
			residents.erase(k)
			continue
		if h.global_position.distance_to(pp) > DESPAWN_R:
			_despawn(k, h)
		else:
			near += 1
	var budget := 999 if fill else SPAWNS_PER_TICK
	var st = Game.main.settlements if Game.main else null
	for t in Game.world.features.towns:
		var tc := Vector3(t.x, 0, t.z)
		if Vector2(tc.x - pp.x, tc.z - pp.z).length() > SPAWN_R + float(t.r):
			if _seen_town.has(t.id) and Vector2(tc.x - pp.x, tc.z - pp.z).length() > DESPAWN_R + float(t.r) + 100.0:
				_seen_town.erase(t.id)
			continue
		if st != null and st.has_method("get_town") and not st.get_town(t.id).is_empty():
			if st.get_town(t.id).state != "built":
				continue
			if not index.has(t.id):
				index[t.id] = _index(t.id)
				casts[t.id] = TownSchedule.cast(index[t.id], str(t.kind))
				for r in casts[t.id]:
					index[t.id].look_ids[r.key] = _pick_look(t.id, r)
			var first: bool = not _seen_town.has(t.id)
			for r in casts[t.id]:
				if residents.has(r.key) or near >= MAX_NEAR or budget <= 0:
					continue
				if _spawn_town_resident(r, first or fill):
					near += 1
					budget -= 1
			_seen_town[t.id] = true
		else:
			near += _spawn_simple(t, int(TOWN_FALLBACK.get(t.kind, 16)), near, pp)
	for p in Game.world.features.pois:
		var pc := Vector3(p.x, 0, p.z)
		if Vector2(pc.x - pp.x, pc.z - pp.z).length() > SPAWN_R + float(p.r):
			continue
		near += _spawn_simple(p, int(POI_SIZE.get(p.kind, 2)), near, pp)

## Story scenes (src/missions/places.gd) put their own actors on the same spots (the bartender of the Gilded Spur,
## a card table, the sheriff's desk): a resident holding a spot a story actor stands on moves on, and the spot
## stays the story's while that actor is there.
func _yield_to_story() -> void:
	var others: Array = []
	for h in get_tree().get_nodes_in_group("humans"):
		if h.alive and not h.has_meta("resident") and not h.has_meta("home_town") and h.role != "traveller" and h.global_position.distance_to(Game.player.global_position) < 200.0:
			others.append(h)
	if others.is_empty():
		return
	for k in residents:
		var r: Human = residents[k]
		if not is_instance_valid(r):
			continue
		var rt = r.brain.get("routine")
		if rt == null or rt.spot.is_empty():
			continue
		var o: Vector3 = rt.spot.transform.origin
		for h in others:
			if h.global_position.distance_to(o) < 0.8:
				rt.interrupt()
				rt.spot = {}
				var sp: Dictionary = _spot_at(r.get_meta("home_town", ""), o)
				if not sp.is_empty():
					sp["by"] = h.get_instance_id()
				if r.global_position.distance_to(o) < 1.0:
					r.global_position = o + (r.global_position - h.global_position).normalized() * 0.9
				break

## The settlement unloaded its detail (Ruth is far away): drop the index (spot records go with it); the cast is
## rebuilt identically from the plan when the town is built again.
func forget_town(tid: String) -> void:
	for k in residents.keys():
		if str(k).begins_with(tid + ":") and is_instance_valid(residents[k]):
			_despawn(k, residents[k])
	index.erase(tid)
	casts.erase(tid)

## Screenshots: end the current visit of a share of the strollers (errands, loiterers, porch sitters) now.
func stir(share: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in residents:
		var h: Human = residents[k]
		var rt = h.brain.get("routine") if is_instance_valid(h) else null
		if rt != null and rt.phase == "at" and rt.block.get("kind", "") in ["errands", "loiter", "porch", "patrol"] and rng.randf() < share:
			rt.t = rt.dwell

func walking() -> int:
	var n := 0
	for k in residents:
		var h: Human = residents[k]
		var rt = h.brain.get("routine") if is_instance_valid(h) else null
		if rt != null and rt.phase == "walk":
			n += 1
	return n

func _spot_at(tid: String, o: Vector3) -> Dictionary:
	var st = Game.main.settlements
	for sp in st.spots(tid):
		if (sp.transform.origin as Vector3).distance_to(o) < 0.05:
			return sp
	return {}

## Screenshot/bot hook: spawn everyone due in nearby towns now, on their spots.
func fill_now() -> void:
	if Game.player != null and Game.world != null:
		_tick(true)

func _despawn(key: String, h: Human) -> void:
	metrics.stuck += h.stuck_events
	metrics.doors += h.doors_used
	if h.brain and h.brain.get("routine") != null:
		h.brain.routine.interrupt()
	h.queue_free()
	residents.erase(key)

# ------------------------------------------------------------------ town residents

func _spawn_town_resident(r: Dictionary, place: bool) -> bool:
	var idx: Dictionary = index[r.town]
	var b := block_for(r)
	if b.kind == "home":
		indoors[r.key] = true
		return false
	if b.kind in ["play", "stagger", "patrol"] and not nav_ready(r.town):
		return false                     # these walk between navmesh points: wait for the town's navmesh
	var pp: Vector3 = Game.player.global_position
	var hs := home_spot(r)
	var from_home: bool = indoors.has(r.key) and not place and not hs.is_empty() and \
		hs.transform.origin.distance_to(pp) < 140.0
	var pos: Vector3 = hs.transform.origin if from_home else idx.center
	var opts := {"seed": int(r.seed), "role": r.role, "faction": r.faction, "name": r.name, "weapon": r.weapon,
		"look": r.look}
	var lid: String = idx.look_ids.get(r.key, "")
	if lid != "":
		opts["look_id"] = lid
	if r.has("scale"):
		opts["scale"] = r.scale
	if Game.terrain:
		Game.terrain.ensure_tile(pos)
	var h := Human.spawn(Game.main, pos + Vector3(0, 0.05, 0), opts)
	h.set_meta("home_town", r.town)
	h.set_meta("resident", r.key)
	h.set_town_mode()
	if r.kind == "child":
		h.set_meta("child", true)
	var rt := TownRoutine.new(h, r, self)
	h.brain.routine = rt
	h.brain.home = idx.center
	residents[r.key] = h
	indoors.erase(r.key)
	metrics.spawned += 1
	if not from_home:
		if not rt.place_now():
			var jr := RandomNumberGenerator.new()
			jr.seed = int(r.seed)
			var c: Vector3 = idx.center + Vector3(jr.randf_range(-6.0, 6.0), 0.0, jr.randf_range(-6.0, 6.0))
			var p := snap(c)
			h.global_position = (p if p != Vector3.INF else c) + Vector3(0, 0.1, 0)
	return true

## The block of the day for a resident right now.
func block_for(r: Dictionary) -> Dictionary:
	var h: float = Game.sky.hours if Game.sky else 10.0
	var day: int = Game.sky.day if Game.sky else 0
	return TownSchedule.block(r, h, posmod(day, 7), index.get(r.town, {}))

func _pick_look(tid: String, r: Dictionary) -> String:
	if r.has("look_id"):
		return r.look_id
	var used: Dictionary = index[tid].used_looks
	var cap := int(Game.args.get("looks", 0))
	if cap > 0 and used.size() >= cap:
		# low-memory runs: reuse the looks already cast (clothing colours still vary per seed)
		var have: Array = used.keys().filter(func(id): return r.look == "" or Array(CharacterFactory.ids(r.look)).has(id))
		if have.is_empty():
			have = used.keys().filter(func(id): return Array(CharacterFactory.ids("female" if r.female else "male")).has(id))
		if have.is_empty():
			have = used.keys()
		return have[posmod(int(r.seed), have.size())]
	var pools: Array = [CharacterFactory.ids(r.look)] if r.look != "" else []
	var sexed := "townswoman" if r.female else "townsman"
	pools.append(CharacterFactory.ids(sexed))
	pools.append(CharacterFactory.ids("female" if r.female else "male"))
	for pool in pools:
		var ids: Array = Array(pool)
		ids.sort_custom(func(a, b): return hash(a + str(r.seed)) < hash(b + str(r.seed)))
		for id in ids:
			if not used.has(id) and id not in TownSchedule.CHILD_LOOKS:
				used[id] = true
				return id
	# everyone has been cast once: reuse a look of the right kind (materials vary per seed)
	var any: Array = Array(CharacterFactory.ids(r.look if r.look != "" else sexed))
	return any[posmod(int(r.seed), any.size())] if not any.is_empty() else ""

## Town index: buildings by type, jobs, homes, synthetic street spots, patrol route, yard, saloon front.
func _index(tid: String) -> Dictionary:
	var st = Game.main.settlements
	var t: Dictionary = st.get_town(tid)
	var idx := {"tid": tid, "buildings": {}, "by_type": {}, "jobs": [], "homes": [], "street": [], "patrol": [],
		"patrol_raw": [], "yard_raw": Vector3.INF, "front_raw": Vector3.INF, "yard": Vector3.INF, "front": Vector3.INF,
		"center": t.center, "saloon": "", "church": "", "school": "", "restaurant": "", "sheriff": "",
		"look_ids": {}, "used_looks": {}, "snapped": false}
	var work_types := {}
	for j in TownSchedule.JOBS.values():
		for ty in j.types:
			work_types[ty] = true
	for bid in t.buildings:
		var b: Dictionary = st.get_building(bid)
		idx.buildings[bid] = b
		var ty: String = b.type
		if not idx.by_type.has(ty):
			idx.by_type[ty] = []
		idx.by_type[ty].append(bid)
		for key in ["saloon", "church", "school", "restaurant", "sheriff"]:
			if ty == key and idx[key] == "":
				idx[key] = bid
		if str(b.get("role", "")) != "":
			var has_work := false
			for s in b.spots:
				if work_types.has(s.type):
					has_work = true
					break
			if has_work:
				idx.jobs.append({"job": b.role, "bid": bid})
		if ty in HOMES and ty != "hotel":
			for s in b.spots:
				if s.type == "door_in":
					idx.homes.append(bid)
					break
	if idx.homes.is_empty():
		for ty in ["hotel", "tent", "saloon"]:
			for bid in idx.by_type.get(ty, []):
				idx.homes.append(bid)
	# street spots: lean on the wall beside shop doors, porch seats, hitch rails, troughs, outdoor benches
	for bid in t.buildings:
		var b: Dictionary = idx.buildings[bid]
		var ty: String = b.type
		for s in b.spots:
			var sty: String = s.type
			if sty == "door_out" and not ty in ["house", "outhouse", "cabin", "shed", "tent", "church", "school"]:
				var xf: Transform3D = s.transform
				var back := Basis(Vector3.UP, PI) * xf.basis
				for side in [-1.0, 1.0]:
					var p: Vector3 = xf.origin + xf.basis.x * side * 1.55 - xf.basis.z * 0.45
					idx.street.append({"type": "lean_wall", "transform": Transform3D(back, p), "building": bid,
						"town": tid, "synthetic": true})
			elif sty in ["porch_sit", "hitch", "trough", "well", "pump"]:
				idx.street.append(s)
			elif sty == "bench" and ty in ["depot", "street"]:
				idx.street.append(s)
	# yard in front of the school, the saloon front, a patrol route along the main street
	for key in ["school", "saloon"]:
		var bid2: String = idx[key]
		if bid2 == "":
			continue
		for s in idx.buildings[bid2].spots:
			if s.type == "door_out":
				var xf2: Transform3D = s.transform
				idx["yard_raw" if key == "school" else "front_raw"] = xf2.origin + xf2.basis.z * (9.0 if key == "school" else 5.0)
				break
	var main_st := {}
	for sg in t.streets:
		if main_st.is_empty() or (sg.a as Vector2).distance_to(sg.b) * float(sg.w) > (main_st.a as Vector2).distance_to(main_st.b) * float(main_st.w):
			main_st = sg
	if not main_st.is_empty():
		var a: Vector2 = main_st.a
		var bb: Vector2 = main_st.b
		var L := a.distance_to(bb)
		var dir := (bb - a) / maxf(L, 0.01)
		var nrm := Vector2(-dir.y, dir.x)
		var n := maxi(int(L / 22.0), 2)
		var frame: Transform3D = t.frame
		for i in n + 1:
			var side := 1.0 if i % 2 == 0 else -1.0
			var q := a + dir * (L * float(i) / n) + nrm * side * (float(main_st.w) * 0.5 - 1.2)
			var w := frame * Vector3(q.x, 0.0, q.y)
			w.y = Game.world.height(w.x, w.z)
			idx.patrol_raw.append(w)
		var back_pts: Array = idx.patrol_raw.duplicate()
		back_pts.reverse()
		idx.patrol_raw.append_array(back_pts.slice(1, back_pts.size() - 1))
	return idx

func _ensure_snapped(idx: Dictionary) -> void:
	if idx.snapped or not nav_ready(idx.tid):
		return
	idx.snapped = true
	for p in idx.patrol_raw:
		var s := snap(p)
		if s != Vector3.INF and Vector2(s.x - p.x, s.z - p.z).length() < 3.0:
			idx.patrol.append(s)
	if idx.yard_raw != Vector3.INF:
		idx.yard = snap(idx.yard_raw)
	if idx.front_raw != Vector3.INF:
		idx.front = snap(idx.front_raw)
	# lean spots must stand on walkable ground (boardwalk), not in an alley gap or inside a porch post
	var keep: Array = []
	for s in idx.street:
		if s.get("synthetic", false):
			var o: Vector3 = s.transform.origin
			var q := snap(o)
			if q == Vector3.INF or Vector2(q.x - o.x, q.z - o.z).length() > 0.25 or absf(q.y - o.y) > 0.5:
				continue
		keep.append(s)
	idx.street = keep

# ------------------------------------------------------------------ API for routines

func nav_ready(tid: String) -> bool:
	var st = Game.main.settlements if Game.main else null
	return st != null and st.navigation_ready(tid)

func btype(bid: String) -> String:
	var st = Game.main.settlements
	return str(st.get_building(bid).get("type", ""))

func _free(s: Dictionary) -> bool:
	if not s.has("by"):
		return true
	var o = instance_from_id(int(s.by))
	return o == null or not is_instance_valid(o) or not o.alive

## Claim a free ground-floor spot of one of `types` in building `bid`. `need`: "" | "table" | "cards".
func claim(rt: TownRoutine, bid: String, types: Array, need := "") -> Dictionary:
	var idx: Dictionary = index.get(rt.res.town, {})
	var b: Dictionary = idx.get("buildings", {}).get(bid, {})
	if b.is_empty() or types.is_empty():
		return {}
	var order: Array = types.duplicate()
	var first: String = order[rt.rng.randi() % order.size()]
	order.erase(first)
	order.push_front(first)
	var fy: float = b.floor_y
	for ty in order:
		var cands: Array = []
		for s in b.spots:
			if s.type != ty or not _free(s) or s.get("bad", false):
				continue
			if (s.transform.origin.y - fy) > 1.2:
				continue                       # upstairs: not on the ground-floor navmesh routes we trust
			if need == "table" and not s.has("table"):
				continue
			if need == "cards" and not s.get("cards", false):
				continue
			cands.append(s)
		if not cands.is_empty():
			var s2: Dictionary = cands[rt.rng.randi() % cands.size()]
			s2["by"] = rt.body.get_instance_id()
			return s2
	return {}

func claim_street(rt: TownRoutine) -> Dictionary:
	var idx: Dictionary = index.get(rt.res.town, {})
	if idx.is_empty():
		return {}
	_ensure_snapped(idx)
	var cands: Array = []
	var bp := rt.body.global_position
	for s in idx.street:
		if _free(s) and s.transform.origin.distance_to(bp) < 140.0:
			cands.append(s)
	if cands.is_empty():
		return {}
	var s2: Dictionary = cands[rt.rng.randi() % cands.size()]
	s2["by"] = rt.body.get_instance_id()
	return s2

func release(s: Dictionary, body: Node) -> void:
	if s.has("by") and int(s.by) == body.get_instance_id():
		s.erase("by")

func home_spot(r: Dictionary) -> Dictionary:
	var idx: Dictionary = index.get(r.town, {})
	var b: Dictionary = idx.get("buildings", {}).get(r.home, {})
	if b.is_empty():
		return {}
	for s in b.spots:
		if s.type == "door_in":
			return s
	for s in b.spots:
		if s.type == "door_out":
			return s
	return {}

func went_home(rt: TownRoutine) -> void:
	metrics.home += 1
	var key: String = rt.res.key
	indoors[key] = true
	if residents.has(key):
		_despawn(key, residents[key])

## A shop open now for an errand (store, bank, barber, post, depot ticket window...), nearer ones preferred.
func open_shop(r: Dictionary, rng: RandomNumberGenerator) -> String:
	var idx: Dictionary = index.get(r.town, {})
	var h: float = Game.sky.hours if Game.sky else 10.0
	var sunday: bool = Game.sky != null and posmod(Game.sky.day, 7) == TownSchedule.SUNDAY
	var cands: Array = []
	for bid in idx.get("buildings", {}):
		var b: Dictionary = idx.buildings[bid]
		var ty: String = b.type
		if not TownSchedule.CUSTOMER.has(ty) or ty == "restaurant" or ty == "sheriff":
			continue
		if sunday and ty in TownSchedule.CLOSED_SUNDAY:
			continue
		if not TownSchedule.in_hours(h, b.get("hours", [8.0, 18.0])):
			continue
		cands.append(bid)
	if cands.is_empty():
		return ""
	return cands[rng.randi() % cands.size()]

func yard(tid: String) -> Vector3:
	var idx: Dictionary = index.get(tid, {})
	_ensure_snapped(idx)
	return idx.get("yard", Vector3.INF)

func saloon_front(tid: String) -> Vector3:
	var idx: Dictionary = index.get(tid, {})
	_ensure_snapped(idx)
	return idx.get("front", Vector3.INF)

func patrol_points(tid: String) -> Array:
	var idx: Dictionary = index.get(tid, {})
	_ensure_snapped(idx)
	return idx.get("patrol", [])

func snap(p: Vector3) -> Vector3:
	var m := get_viewport().find_world_3d().navigation_map if get_viewport() else RID()
	if not m.is_valid() or NavigationServer3D.map_get_iteration_id(m) == 0:
		return Vector3.INF
	return NavigationServer3D.map_get_closest_point(m, p + Vector3(0, 0.8, 0))

## True when `body` is at least `min_dist` from Ruth and outside the camera's view.
func unseen(body: Node3D, min_dist: float) -> bool:
	return unseen_point(body.global_position, min_dist)

func unseen_point(p: Vector3, min_dist: float) -> bool:
	if Game.player == null:
		return true
	if p.distance_to(Game.player.global_position) < min_dist:
		return false
	var cam: Camera3D = Game.camera
	if cam == null or not is_instance_valid(cam):
		return true
	var to := p - cam.global_position
	if to.length() > 260.0:
		return true
	return (-cam.global_transform.basis.z).dot(to.normalized()) < 0.45

func near_walker(body: Human, r: float) -> Human:
	for k in residents:
		var o: Human = residents[k]
		if o == body or not is_instance_valid(o) or not o.alive:
			continue
		var rt = o.brain.get("routine")
		if rt == null or rt.phase != "walk" or rt.chat_cool > 0.0 or o.brain.state != o.brain.State.ROUTINE:
			continue
		if not rt.block.get("kind", "") in ["errands", "loiter", "porch"]:
			continue
		if o.global_position.distance_to(body.global_position) < r:
			return o
	return null

## Someone standing idle on the street (wall lean, hitch rail) within 60 m, nobody visiting them yet.
func idler_to_join(body: Human) -> Human:
	var best: Human = null
	var bd := 60.0
	for k in residents:
		var o: Human = residents[k]
		if o == body or not is_instance_valid(o) or not o.alive:
			continue
		var rt = o.brain.get("routine")
		if rt == null or rt.phase != "at" or rt.seated or rt.spot.is_empty() or rt.partner != null:
			continue
		if not str(rt.spot.get("type", "")) in ["lean_wall", "hitch", "trough"] or rt.dwell - rt.t < 30.0:
			continue
		var d := o.global_position.distance_to(body.global_position)
		if d < bd:
			bd = d
			best = o
	return best

func neighbour(body: Human, r: float) -> Human:
	for k in residents:
		var o: Human = residents[k]
		if o != body and is_instance_valid(o) and o.alive and o.global_position.distance_to(body.global_position) < r:
			return o
	return null

func stat(name: String, n: int) -> void:
	metrics[name] = metrics.get(name, 0) + n

## Shared bark pacing: one voice at a time in a town, only when Ruth can hear it.
func can_bark(pos: Vector3, gap := 3.5) -> bool:
	var now := Time.get_ticks_msec() * 0.001
	if now < _bark_until or Game.player == null or Game.audio == null:
		return false
	if pos.distance_to(Game.player.global_position) > 28.0:
		return false
	_bark_until = now + gap
	return true

func remember(key: String, what: String) -> void:
	if key == "":
		return
	if not memory.has(key):
		memory[key] = {}
	memory[key][what] = _game_hours()

## Game hours since `what` happened to this resident (INF if never).
func since(key: String, what: String) -> float:
	var m: Dictionary = memory.get(key, {})
	return _game_hours() - float(m[what]) if m.has(what) else INF

func _game_hours() -> float:
	return (Game.sky.day * 24.0 + Game.sky.hours) if Game.sky else Time.get_ticks_msec() / 120000.0

## A spectacle (a body in the street, a fight): civilians nearby gather round at a few metres and watch.
func spectacle(pos: Vector3, seconds := 40.0, kind := "body") -> void:
	spectacles.append({"pos": pos, "until": Time.get_ticks_msec() * 0.001 + seconds, "kind": kind})
	for k in residents:
		var h: Human = residents[k]
		if is_instance_valid(h) and h.alive and h.global_position.distance_to(pos) < 40.0 and h.brain.has_method("watch"):
			h.brain.watch(pos, seconds)

# ------------------------------------------------------------------ metrics

func _sample() -> void:
	if Game.args.has("town_debug"):
		var parts: PackedStringArray = []
		for k in residents:
			var hh: Human = residents[k]
			var rr = hh.brain.get("routine") if is_instance_valid(hh) else null
			if rr != null:
				parts.append("%s %s:%s/%s %.0f/%.0f %s" % [k.get_slice(":", 1), rr.res.kind, rr.block.get("kind", "-"), rr.phase,
					rr.t, rr.dwell if rr.phase == "at" else rr.walk_limit, hh.brain.debug_state])
		print("town_debug h=%.2f nav=%s: %s" % [Game.sky.hours if Game.sky else -1.0, str(nav_ready("bitter_spring")), " | ".join(parts)])
	var n := 0
	var ok := 0.0
	for k in residents:
		var h: Human = residents[k]
		if not is_instance_valid(h) or not h.alive:
			continue
		var rt = h.brain.get("routine")
		if rt == null:
			continue
		n += 1
		var good := 0.0
		if h.brain.state == h.brain.State.ROUTINE:
			if rt.phase in ["at", "chat", "leave"]:
				good = 1.0
			elif rt.phase == "walk" and rt.t < rt.walk_limit:
				good = 1.0
			elif rt.phase == "plan" and rt.t < 6.0:
				good = 1.0
		else:
			good = 1.0          # reacting (fleeing, watching, reporting) counts as doing the right thing
		ok += good
	for tid in casts:
		for r in casts[tid]:
			if indoors.has(r.key) and not residents.has(r.key) and block_for(r).kind == "home":
				n += 1
				ok += 1.0
	if n > 0:
		metrics.samples += 1
		metrics.on_schedule += ok / n
	metrics.npc_seconds += residents.size() * 5.0

## Summary for the town bot: {residents, on_schedule %, reached %, doors, stuck, ...}
func town_metrics() -> Dictionary:
	var doors: int = metrics.doors
	var stuck: int = metrics.stuck
	for k in residents:
		var h = residents[k]
		if is_instance_valid(h):
			doors += h.doors_used
			stuck += h.stuck_events
	var walked: int = int(metrics.trips) - int(metrics.skipped)
	return {"residents": residents.size(), "cast": casts.values().reduce(func(a, c): return a + c.size(), 0),
		"on_schedule": 100.0 * metrics.on_schedule / maxf(metrics.samples, 1.0),
		"reached": 100.0 * float(metrics.reached) / maxf(float(metrics.reached + metrics.failed), 1.0),
		"trips": walked, "arrived": metrics.reached, "failed": metrics.failed, "skipped": metrics.skipped,
		"home": metrics.home, "doors": doors, "stuck": stuck, "chats": metrics.chats,
		"npc_minutes": metrics.npc_seconds / 60.0, "greetings": metrics.greetings, "fled_inside": metrics.fled_inside,
		"reports": metrics.reports, "crowd": metrics.crowd, "nudges": metrics.nudges}

# ------------------------------------------------------------------ POIs and travellers

func _spawn_simple(t: Dictionary, n: int, near: int, pp: Vector3) -> int:
	var made := 0
	for slot in n:
		var key := "%s:%d" % [t.id, slot]
		if residents.has(key) or near + made >= MAX_NEAR:
			continue
		var r := RandomNumberGenerator.new()
		r.seed = hash(t.id) * 31 + slot
		var home := _home_point(t, r)
		if home == Vector3.INF or pp.distance_to(home) > SPAWN_R:
			continue
		var role: String = POI_ROLES[r.randi() % POI_ROLES.size()]
		var female := role == "woman"
		Game.terrain.ensure_tile(home)
		var h := Human.spawn(Game.main, home + Vector3(0, 0.3, 0), {"seed": r.randi(), "role": role,
			"faction": "civilian", "name": TownSchedule.name_for(r, female),
			"weapon": "lockhart_sa" if role == "rancher" else ""})
		h.set_meta("home_town", t.id)
		residents[key] = h
		made += 1
	return made

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
		var h := Human.spawn(Game.main, p + Vector3(0, 0.3, 0), {"seed": Game.rng.randi(), "role": "traveller",
			"faction": "civilian", "name": TownSchedule.name_for(Game.rng, false)})
		var j := clampi(i + (40 if Game.rng.randf() < 0.5 else -40), 0, pts.size() - 1)
		h.brain.home = Vector3(pts[j][0], pts[j][2], pts[j][1])
		h.intent.move_to = h.brain.home
		travellers.append(h)
		break

static func _name(r: RandomNumberGenerator) -> String:
	return TownSchedule.name_for(r, r.randf() < 0.4)
