class_name TownSchedule
extends RefCounted
## Who lives in a town and what they do at each hour. Pure data + functions (no nodes):
##   cast(index, kind) -> [resident]   a stable cast from the town's buildings: one worker per job building
##                                     (bartender, storekeepers, sheriff + night deputy, barber, doctor, blacksmith,
##                                     tellers...), residents with homes and habits, a gambler, drunks, children.
##   block(resident, hour, weekday, index) -> {key, kind, bid, types}   the current block of the day:
##       work      at the job building's work spots during its hours (shops open/close; Sunday closed)
##       home      walk home and go inside (night; lit windows come from the settlement lights)
##       errands   visit open shops as a customer (counter, bank, ticket window, barber chair) between loitering
##       loiter    street life: lean on a wall by a door, sit on a porch, stand at a hitch rail, chat
##       bar / tables / cards / piano   saloon life in the evening
##       eat       cafe tables at noon;  church  Sunday service;  school / play  children
##       patrol    the sheriff's walk along the main street;  stagger  drunks outside the saloon late at night
## The resident record is a Dictionary so population.gd can keep it across despawns (memory, claims, counters).

const SUNDAY := 6

# building role -> job: gameplay role (Human), look tag (CharacterFactory), work spot types, voice, armed
const JOBS := {
	"bartender": {"role": "bartender", "look": "townsman", "types": ["bartender"]},
	"storekeeper": {"role": "shopkeeper", "look": "townsman", "types": ["shopkeeper", "shopkeeper", "work"]},
	"gunsmith": {"role": "shopkeeper", "look": "townsman", "types": ["shopkeeper", "work"]},
	"butcher": {"role": "shopkeeper", "look": "worker", "types": ["shopkeeper", "work"]},
	"banker": {"role": "townsfolk", "look": "gentleman", "types": ["banker_desk"], "extra": "teller"},
	"teller": {"role": "townsfolk", "look": "townsman", "types": ["teller"]},
	"sheriff": {"role": "lawman", "look": "lawman", "types": ["sheriff_desk"], "extra": "deputy"},
	"deputy": {"role": "lawman", "look": "lawman", "types": ["sheriff_desk", "chair"]},
	"barber": {"role": "townsfolk", "look": "townsman", "types": ["barber"]},
	"doctor": {"role": "townsfolk", "look": "gentleman", "types": ["doctor_desk", "work"]},
	"undertaker": {"role": "townsfolk", "look": "elder", "types": ["work"]},
	"postmaster": {"role": "shopkeeper", "look": "townsman", "types": ["clerk", "telegrapher"]},
	"clerk": {"role": "townsfolk", "look": "gentleman", "types": ["clerk", "telegrapher"]},
	"editor": {"role": "townsfolk", "look": "townsman", "types": ["telegrapher", "clerk"]},
	"blacksmith": {"role": "worker", "look": "worker", "types": ["work"]},
	"stablehand": {"role": "worker", "look": "cowhand", "types": ["work", "stall"]},
	"preacher": {"role": "townsfolk", "look": "elder", "types": ["preacher"]},
	"teacher": {"role": "townsfolk", "look": "townswoman", "types": ["teacher"]},
	"station_agent": {"role": "townsfolk", "look": "townsman", "types": ["ticket_agent", "work"]},
	"hotelier": {"role": "shopkeeper", "look": "gentleman", "types": ["clerk"]},
	"cook": {"role": "townsfolk", "look": "matron", "types": ["cook"]},
}
const GENERIC_JOB := {"role": "worker", "look": "worker", "types": ["work", "clerk", "shopkeeper", "bartender", "cook"]}

# residents without a job building, by settlement kind (children only where there is a school)
const RESIDENTS := {"rail_town": 15, "port_town": 18, "mining_camp": 9, "desert_stop": 7}
const CHILDREN := {"rail_town": 3, "port_town": 4, "mining_camp": 0, "desert_stop": 1}
const RESIDENT_KINDS := [
	["townsman", "townsfolk", "townsman", "m"], ["townsman", "townsfolk", "townsman", "m"],
	["townswoman", "woman", "townswoman", "f"], ["lady", "woman", "lady", "f"], ["townswoman", "woman", "townswoman", "f"],
	["drinker", "townsfolk", "worker", "m"], ["drinker", "rancher", "rancher", "m"], ["drinker", "cowhand", "cowhand", "m"],
	["elder", "elder", "elder", "m"], ["matron", "woman", "matron", "f"], ["gambler", "gambler", "gentleman", "m"],
	["drunk", "drunk", "worker", "m"], ["townsman", "townsfolk", "gentleman", "m"], ["drinker", "worker", "worker", "m"],
	["drunk", "drunk", "drifter", "m"], ["townswoman", "woman", "ranchwoman", "f"], ["drinker", "rancher", "rancher", "m"],
	["townsman", "townsfolk", "townsman", "m"]]
const CHILD_LOOKS := ["npc_015", "npc_025", "npc_006", "npc_031", "npc_007", "npc_002", "npc_027"]

# customer spots per building type (errands)
const CUSTOMER := {"store": ["shop_counter"], "trading_post": ["shop_counter"], "tent_store": ["shop_counter"],
	"gunsmith": ["shop_counter"], "butcher": ["shop_counter"], "post": ["shop_counter"], "land_office": ["shop_counter"],
	"newspaper": ["shop_counter"], "bank": ["bank_customer", "bench"], "hotel": ["desk_customer", "chair"],
	"depot": ["ticket_customer", "bench", "platform"], "barber": ["barber_chair", "chair"], "doctor": ["patient", "bench"],
	"sheriff": ["chair"], "assay": ["shop_counter"], "restaurant": ["chair"]}
const CLOSED_SUNDAY := ["store", "gunsmith", "butcher", "barber", "bank", "land_office", "newspaper", "post",
	"undertaker", "smithy", "assay", "trading_post", "tent_store"]

const MALE := ["Abel", "Amos", "Asa", "Caleb", "Cyrus", "Elias", "Ezra", "Gideon", "Hiram", "Isaac", "Jonas", "Lemuel",
	"Matthias", "Obed", "Perley", "Rufus", "Silas", "Virgil", "Walt", "Zeb", "Mateo", "Ignacio", "Wen", "Henrik",
	"Tomas", "Seamus", "Amon", "Bartholomew", "Clement", "Erastus", "Hezekiah", "Jubal", "Lucius", "Orrin"]
const FEMALE := ["Bertha", "Clara", "Delia", "Edna", "Etta", "Flora", "Hattie", "Ida", "Josie", "Lottie", "Mabel",
	"Minnie", "Nell", "Ora", "Sadie", "Tillie", "Rosa", "Lupe", "Greta", "Bridget", "Adelaide", "Cora", "Effie",
	"Louisa", "Maud", "Pearl", "Viola"]
const LAST := ["Abbott", "Barlow", "Birch", "Coker", "Dabney", "Ellery", "Fenwick", "Garrity", "Hollis", "Ingram",
	"Judd", "Kessler", "Larkin", "Moody", "Nance", "Oakes", "Pruett", "Quill", "Rasmussen", "Sayer", "Tolliver",
	"Upham", "Vickers", "Whitlock", "Yates", "Zeller", "Ybarra", "Ochoa", "Lindgren", "Murphy", "Doyle", "Chen"]

static func name_for(r: RandomNumberGenerator, female: bool) -> String:
	var first: Array = FEMALE if female else MALE
	return "%s %s" % [first[r.randi() % first.size()], LAST[r.randi() % LAST.size()]]

## Build the stable cast of a town from its building index (population._index). Deterministic per town id.
static func cast(idx: Dictionary, kind: String) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash(str(idx.tid)) * 7 + 3
	var out: Array = []
	var homes: Array = idx.homes
	var hi := 0
	var jobs: Array = idx.jobs
	for j in jobs:
		var job: String = j.job
		var spec: Dictionary = JOBS.get(job, GENERIC_JOB)
		out.append(_resident(r, idx, out.size(), "worker", job, spec, j.bid, homes, hi))
		hi += 1
		if spec.has("extra"):
			var ex: String = spec.extra
			out.append(_resident(r, idx, out.size(), "worker", ex, JOBS[ex], j.bid, homes, hi))
			hi += 1
	var n: int = RESIDENTS.get(kind, 0)
	for i in n:
		var rk: Array = RESIDENT_KINDS[i % RESIDENT_KINDS.size()]
		var res := _resident(r, idx, out.size(), str(rk[0]), "", {"role": rk[1], "look": rk[2], "types": []}, "", homes, hi)
		res["female"] = rk[3] == "f"
		res["name"] = name_for(r, res.female)
		out.append(res)
		hi += 1
	if idx.get("school", "") != "":
		for i in int(CHILDREN.get(kind, 0)):
			var c := _resident(r, idx, out.size(), "child", "", {"role": "townsfolk", "look": "", "types": []}, "", homes, hi)
			c["look_id"] = CHILD_LOOKS[(hash(str(idx.tid)) + i) % CHILD_LOOKS.size()]
			c["scale"] = 0.74
			c["female"] = c.look_id in ["npc_025", "npc_031", "npc_027"]
			c["name"] = name_for(r, c.female).get_slice(" ", 0) + " " + str(out[hi % maxi(out.size(), 1)].name).get_slice(" ", 1)
			out.append(c)
			hi += 1
	return out

static func _resident(r: RandomNumberGenerator, idx: Dictionary, slot: int, kind: String, job: String, spec: Dictionary,
		work: String, homes: Array, hi: int) -> Dictionary:
	var female: bool = str(spec.get("look", "")) in ["townswoman", "lady", "matron", "ranchwoman"]
	var res := {"key": "%s:%d" % [idx.tid, slot], "town": idx.tid, "slot": slot, "kind": kind, "job": job,
		"role": spec.get("role", "townsfolk"), "look": spec.get("look", ""), "types": spec.get("types", []),
		"work": work, "home": homes[hi % homes.size()] if not homes.is_empty() else "", "seed": r.randi(),
		"female": female, "name": name_for(r, female), "evening": r.randf(), "early": r.randf_range(-0.4, 0.3),
		"shift": "night" if job == "deputy" else "day", "faction": "law" if spec.get("role", "") == "lawman" else "civilian",
		"weapon": "lockhart_sa" if spec.get("role", "") in ["lawman", "rancher", "gambler"] else ""}
	return res

static func in_hours(h: float, hours: Array) -> bool:
	var o := float(hours[0])
	var c := float(hours[1])
	if c - o >= 24.0:
		return true
	return (h >= o and h < c) or (h + 24.0 >= o and h + 24.0 < c)

static func _b(kind: String, bid := "", types: Array = []) -> Dictionary:
	return {"key": kind + "|" + bid, "kind": kind, "bid": bid, "types": types}

## Hash of the resident and an hour slot: a stable coin per hour for habits.
static func _coin(res: Dictionary, h: float, salt: int) -> float:
	return float(posmod(hash(int(res.seed) * 131 + int(floor(h)) * 17 + salt), 1000)) / 1000.0

## The block of the day for a resident. `idx` gives the buildings (saloon, church, school, restaurant, work hours).
static func block(res: Dictionary, h: float, wday: int, idx: Dictionary) -> Dictionary:
	var sunday := wday == SUNDAY
	var saloon: String = idx.get("saloon", "")
	var church: String = idx.get("church", "")
	var cafe: String = idx.get("restaurant", "")
	var kind: String = res.kind
	if kind == "worker":
		var wb: Dictionary = idx.buildings.get(res.work, {})
		var hours: Array = wb.get("hours", [8.0, 18.0])
		var job: String = res.job
		if job in ["sheriff", "deputy"]:
			var on := (h >= 7.0 and h < 19.0) if res.shift == "day" else (h >= 19.0 or h < 7.0)
			if on:
				return _b("patrol", res.work) if int(h) % 3 == 1 else _b("work", res.work, res.types)
			if res.shift == "day" and h >= 19.0 and h < 21.5 and saloon != "":
				return _b("tables", saloon)
			return _b("home", res.home)
		if job == "teacher":
			hours = [8.0, 14.5] if not sunday and wday != 5 else [0.0, 0.0]
		elif job == "preacher":
			if sunday and h >= 8.5 and h < 12.0:
				return _b("work", res.work, ["preacher"])
			hours = [9.0, 17.0]
			if h >= 9.0 and h < 17.0:
				return _b("work", res.work, ["bench", "preacher"]) if _coin(res, h, 5) < 0.5 else _b("loiter")
		elif sunday and str(wb.get("type", "")) in CLOSED_SUNDAY:
			hours = [0.0, 0.0]
		elif sunday and str(wb.get("type", "")) == "saloon":
			hours = [12.0, float(hours[1])]
		var start := float(hours[0]) + float(res.early)
		if float(hours[1]) - float(hours[0]) >= 24.0:
			hours = [6.0, 22.0]          # hotel clerk etc.: a long day shift
			start = 6.0 + float(res.early)
		if in_hours(h - float(res.early), hours) or (h >= start and h < float(hours[0])):
			# the cook and bartender eat on the job; others take a noon hour at the cafe sometimes
			if h >= 12.0 and h < 13.0 and cafe != "" and job not in ["cook", "bartender", "hotelier"] and _coin(res, h, 9) < 0.35:
				return _b("eat", cafe)
			return _b("work", res.work, res.types)
		if sunday and church != "" and h >= 9.0 and h < 11.5 and _coin(res, 0.0, 3) < 0.8:
			return _b("church", church)
		return _evening(res, h, saloon, cafe, idx)
	if sunday and church != "" and h >= 9.0 and h < 11.5 and kind != "drunk" and kind != "gambler":
		return _b("church", church)
	match kind:
		"child":
			if h >= 8.0 and h < 14.0 and not sunday and wday != 5 and idx.get("school", "") != "":
				return _b("school", idx.school)
			if h >= 7.5 and h < 18.5:
				return _b("play", idx.get("school", ""))
			return _b("home", res.home)
		"drunk":
			if h < 2.0 or h >= 21.5:
				return _b("stagger", saloon)
			if h >= 11.0 and saloon != "":
				return _b("bar", saloon) if _coin(res, h, 1) < 0.75 else _b("tables", saloon)
			return _b("home", res.home)
		"gambler":
			if (h < 3.0 or h >= 14.0) and saloon != "":
				return _b("cards", saloon)
			if h >= 12.0 and h < 14.0:
				return _b("eat", cafe) if cafe != "" else _b("loiter")
			return _b("home", res.home)
	# townsfolk, women, elders, drinkers
	var female: bool = res.female
	if h < 7.0 + float(res.early) or h >= 23.0:
		return _b("home", res.home)
	if h < 8.5:
		return _b("porch", res.home) if _coin(res, h, 2) < 0.5 else _b("loiter")
	if h >= 12.0 and h < 13.0 and cafe != "" and _coin(res, h, 4) < 0.6:
		return _b("eat", cafe)
	if h < 17.5:
		if kind == "drinker" and h >= 14.0 and saloon != "" and _coin(res, h, 6) < 0.4:
			return _b("bar", saloon)
		return _b("errands") if _coin(res, h, 7) < 0.55 else _b("loiter")
	return _evening(res, h, saloon, cafe, idx, female)

static func _evening(res: Dictionary, h: float, saloon: String, cafe: String, _idx: Dictionary, female := false) -> Dictionary:
	var e: float = res.evening
	if female or res.kind in ["elder", "matron", "townswoman", "lady"]:
		if h < 19.0:
			return _b("porch", res.home) if e < 0.5 else _b("loiter")
		if h < 20.5 and cafe != "" and e > 0.7:
			return _b("eat", cafe)
		return _b("home", res.home)
	if h < 18.5:
		return _b("loiter") if e < 0.6 else _b("porch", res.home)
	if saloon != "" and e < 0.65 and h < 23.5:
		return _b("bar", saloon) if _coin(res, h, 8) < 0.45 else _b("tables", saloon)
	if h < 21.0:
		return _b("porch", res.home)
	return _b("home", res.home)

## Activity clip for a spot type ("" = plain standing idle). Seated spots return "sit_idle".
static func activity_for(spot: Dictionary, block_kind: String, r: RandomNumberGenerator) -> String:
	var t: String = spot.get("type", "")
	if spot.has("sit_height") and t != "bath":
		return "sit_idle"
	match t:
		"bar_patron":
			return ["drink", "drink", "drink_smoke", "idle_wait"][r.randi() % 4]
		"lean_wall":
			return "lean_wall"
		"bartender", "shopkeeper", "clerk", "teller", "ticket_agent", "cook", "barber":
			return ["idle_wait", "idle_shift", "idle_wait"][r.randi() % 3]
		"shop_counter", "bank_customer", "desk_customer", "ticket_customer", "patient":
			return ["talk_1", "talk_2", "idle_wait"][r.randi() % 3]
		"preacher", "teacher":
			return "talk_2"
		"work", "stall", "trough", "hitch", "corral":
			return ["idle_shift", "idle_wait"][r.randi() % 2]
	if block_kind == "stagger":
		return "idle_shift"
	return ["idle_wait", "idle_shift"][r.randi() % 2]

## One-shot gestures that fit a spot while dwelling (picked at random every so often).
static func gestures_for(spot: Dictionary) -> Array:
	var t: String = spot.get("type", "")
	if spot.has("sit_height"):
		return []
	match t:
		"bartender", "shopkeeper", "work", "stall", "cook":
			return ["pick_up", "shrug"]
		"bar_patron":
			return ["drink"]
		"shop_counter", "bank_customer", "desk_customer", "ticket_customer", "clerk", "teller", "ticket_agent":
			return ["shrug", "talk_directions"]
		"preacher", "teacher":
			return ["talk_directions", "shrug"]
	return ["shrug"]
