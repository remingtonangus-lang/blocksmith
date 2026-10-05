class_name WorldState
extends Node
## The persistent open-world state: Standing (honour), money, satchel inventory, law (crimes, witnesses, bounty per
## county, wanted level and lawmen response), time, story progress, and save/load (user://saves/*.json).
## Systems report events here (crime, kill, help, theft); NPC reactions, prices and dialogue read from here.

signal standing_changed(value: float, delta: float, reason: String)
signal wanted_changed(level: int, county: String)
signal money_changed(value: float)
signal loaded                       # after load_game: systems re-read their state from flags

const COUNTIES := {"bitter_spring": "Sable County", "coldwater": "Kestrel County", "mesquite_wells": "Ocotillo County",
	"port_linden": "Linden County"}

## Crime table: base bounty $, Standing change, whether it needs a witness to count with the law.
const CRIMES := {
	"murder": {"bounty": 50.0, "standing": -12.0, "witness": true},
	"murder_lawman": {"bounty": 120.0, "standing": -20.0, "witness": true},
	"assault": {"bounty": 10.0, "standing": -2.0, "witness": true},
	"brandish": {"bounty": 0.0, "standing": -0.5, "witness": true},
	"theft": {"bounty": 15.0, "standing": -3.0, "witness": true},
	"horse_theft": {"bounty": 35.0, "standing": -5.0, "witness": true},
	"robbery": {"bounty": 60.0, "standing": -8.0, "witness": true},
	"stage_robbery": {"bounty": 110.0, "standing": -10.0, "witness": true},
	"train_robbery": {"bounty": 180.0, "standing": -14.0, "witness": true},
	"trespass": {"bounty": 5.0, "standing": -0.5, "witness": true},
	"animal_cruelty": {"bounty": 0.0, "standing": -2.0, "witness": false},
}
const GOOD := {"help_stranger": 4.0, "spare_enemy": 3.0, "donation": 2.0, "return_property": 3.0, "bring_alive": 5.0,
	"greet": 0.1, "pay_bounty": 1.0}

var standing := 0.0                 # -100 outlaw .. +100 honourable
var money := 14.5
var inventory := {"tonic_health": 2, "tonic_nerve": 1, "jerky": 4, "coffee": 1, "pelt_rabbit": 0}
var bounties := {}                  # county -> dollars
var wanted := 0                     # 0 none, 1 seen/reported, 2 lawmen hunting, 3 dead or alive (marshals)
var wanted_county := ""
var wanted_t := 0.0                 # seconds left before the heat cools if unseen
var crimes_log: Array = []
var kills := {"civilian": 0, "law": 0, "outlaw": 0, "animal": 0}
var stats := {"distance_on_foot": 0.0, "distance_horse": 0.0, "headshots": 0, "missions": 0}
var flags := {}                     # story flags (spared_asa, hap_alive, ...)

func _ready() -> void:
	Game.set("state", self)

func _process(dt: float) -> void:
	if wanted > 0:
		wanted_t -= dt
		if wanted_t <= 0.0:
			# escaped the search: wanted level drops, bounty stays on the books
			wanted = maxi(wanted - 1, 0)
			wanted_t = 60.0 if wanted > 0 else 0.0
			wanted_changed.emit(wanted, wanted_county)
			if wanted == 0 and Game.hud:
				Game.hud.notice("The law has lost your trail", 4.0)

func standing_label() -> String:
	if standing > 60.0: return "Honourable"
	if standing > 20.0: return "Respected"
	if standing > -20.0: return "Unknown quantity"
	if standing > -60.0: return "Disreputable"
	return "Outlaw"

func change_standing(delta: float, reason: String) -> void:
	# diminishing returns at the extremes so one act can't flip a reputation
	var scale := 1.0 - absf(standing) / 140.0 if signf(delta) == signf(standing) else 1.0
	var d := delta * scale
	standing = clampf(standing + d, -100.0, 100.0)
	Game.log_event("standing", {"delta": snappedf(d, 0.01), "reason": reason, "value": snappedf(standing, 0.1)})
	standing_changed.emit(standing, d, reason)

func good_deed(kind: String) -> void:
	change_standing(GOOD.get(kind, 1.0), kind)

## A crime happened at pos. Witnesses within sight who survive (and reach the law) make it count.
func crime(kind: String, pos: Vector3, victim: Node = null) -> void:
	var c: Dictionary = CRIMES.get(kind, {"bounty": 5.0, "standing": -1.0, "witness": true})
	change_standing(c.standing, kind)
	crimes_log.append({"kind": kind, "pos": [pos.x, pos.z], "t": Time.get_unix_time_from_system()})
	var witnesses := _witnesses(pos, victim)
	Game.log_event("crime", {"kind": kind, "witnesses": witnesses.size()})
	if c.witness and witnesses.is_empty():
		return
	var county := county_at(pos)
	bounties[county] = float(bounties.get(county, 0.0)) + float(c.bounty)
	var level := 1
	if kind in ["murder", "murder_lawman", "robbery", "horse_theft", "stage_robbery", "train_robbery"]:
		level = 2
	if kind == "murder_lawman" or float(bounties[county]) > 200.0:
		level = 3
	if level > wanted:
		wanted = level
		wanted_county = county
		wanted_changed.emit(wanted, county)
		if Game.hud:
			Game.hud.notice(["", "Crime reported", "Wanted in %s" % county, "Wanted dead or alive — %s" % county][level], 5.0)
	wanted_t = [0.0, 45.0, 120.0, 240.0][wanted]
	for w in witnesses:
		if w.brain and w.brain.has_method("on_witness"):
			w.brain.on_witness(kind, pos)

func _witnesses(pos: Vector3, victim: Node) -> Array:
	var out := []
	for h in get_tree().get_nodes_in_group("humans"):
		if h == victim or not h.alive:
			continue
		if h.global_position.distance_to(pos) > 45.0:
			continue
		var eye: Vector3 = h.global_position + Vector3(0, 1.6, 0)
		var q := PhysicsRayQueryParameters3D.create(eye, pos + Vector3(0, 1.2, 0), 1)
		if h.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			out.append(h)
	return out

func county_at(pos: Vector3) -> String:
	var near := Game.world.nearest_settlement(pos.x, pos.z)
	var best := ""
	var bd := INF
	for tid in COUNTIES.keys():
		var t := Game.world.town(tid)
		var d := Vector2(t.x - pos.x, t.z - pos.z).length()
		if d < bd:
			bd = d
			best = COUNTIES[tid]
	return best if best != "" else str(near.get("name", "Sable County"))

func pay_bounty(county: String) -> bool:
	var b: float = bounties.get(county, 0.0)
	if b <= 0.0 or money < b:
		return false
	add_money(-b)
	bounties[county] = 0.0
	if wanted_county == county:
		wanted = 0
		wanted_changed.emit(0, county)
	good_deed("pay_bounty")
	return true

func add_money(d: float) -> void:
	money = maxf(money + d, 0.0)
	money_changed.emit(money)

func add_item(id: String, n := 1) -> void:
	inventory[id] = int(inventory.get(id, 0)) + n

func use_item(id: String) -> bool:
	if int(inventory.get(id, 0)) <= 0:
		return false
	inventory[id] -= 1
	match id:
		"tonic_health":
			if Game.player and Game.player.damageable:
				Game.player.damageable.heal(60.0)
		"tonic_nerve":
			if Game.player and Game.player.nerve:
				Game.player.nerve.reward(100.0)
				Game.player.nerve.restore_core(100.0)
		"jerky":
			if Game.player and Game.player.damageable:
				Game.player.damageable.heal(15.0)
		"coffee":
			if Game.player:
				Game.player.stamina = Game.player.STAMINA_MAX
				if Game.player.nerve:
					Game.player.nerve.restore_core(30.0)
		"cooked_meat":
			if Game.player and Game.player.damageable:
				Game.player.damageable.heal(35.0)
				Game.player.stamina = Game.player.STAMINA_MAX
				if Game.player.nerve:
					Game.player.nerve.restore_core(40.0)
		"gun_oil":
			if Game.player and Game.player.gun:
				Game.player.gun.clean_all()
	return true

## Price multiplier at shops: honourable folk get small discounts, outlaws pay more.
func price_factor() -> float:
	return clampf(1.0 - standing / 400.0, 0.85, 1.25)

# ------------------------------------------------------------------ save / load
func save_game(slot := "auto") -> bool:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var p = Game.player
	var data := {
		"version": 1, "time": Time.get_datetime_string_from_system(),
		"standing": standing, "money": money, "inventory": inventory, "bounties": bounties, "wanted": wanted,
		"wanted_county": wanted_county, "kills": kills, "stats": stats, "flags": flags,
		"missions": Game.missions.completed if Game.missions else [],
		"hours": Game.sky.hours if Game.sky else 9.0, "day": Game.sky.day if Game.sky else 0,
		"weather": Game.sky.weather if Game.sky else 1,
		"player": {"pos": [p.global_position.x, p.global_position.y, p.global_position.z], "yaw": p.facing,
			"health": p.damageable.health if p.damageable else 100.0,
			"ammo": p.gun.ammo if p.gun else {}, "clip": p.gun.clip if p.gun else {}, "weapons": p.gun.weapons if p.gun else [],
			"condition": p.gun.condition if p.gun else {}, "ammo_sel": p.gun.ammo_sel if p.gun else {},
			"loaded": p.gun.loaded if p.gun else {},
			"nerve": {"core": p.nerve.core, "rank": p.nerve.rank, "xp": p.nerve.xp} if p.nerve else {}},
	}
	var f := FileAccess.open("user://saves/%s.json" % slot, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, " "))
	Game.log_event("saved", {"slot": slot})
	return true

func load_game(slot := "auto") -> bool:
	var txt := FileAccess.get_file_as_string("user://saves/%s.json" % slot)
	if txt.is_empty():
		return false
	var d = JSON.parse_string(txt)
	if d == null:
		return false
	standing = d.standing
	money = d.money
	inventory = d.inventory
	bounties = d.bounties
	wanted = int(d.wanted)
	wanted_county = d.wanted_county
	kills = d.kills
	stats = d.stats
	flags = d.flags
	if Game.missions:
		Game.missions.completed.clear()
		for m in d.missions:
			Game.missions.completed.append(str(m))
	if Game.sky:
		Game.sky.day = int(d.day)
		Game.sky.set_time(float(d.hours))
		Game.sky.set_weather(int(d.weather), true)
	var p = Game.player
	var pp: Array = d.player.pos
	var pos := Vector3(pp[0], pp[1], pp[2])
	Game.terrain.ensure_collision_at(pos)
	p.global_position = pos + Vector3(0, 0.3, 0)
	p.facing = float(d.player.yaw)
	if p.damageable:
		p.damageable.health = float(d.player.health)
	if p.gun:
		p.gun.ammo = d.player.ammo
		p.gun.clip = d.player.clip
		var ws: Array[String] = []
		for w in d.player.weapons:
			ws.append(str(w))
		p.gun.weapons = ws
		p.gun.condition = d.player.get("condition", {})
		p.gun.ammo_sel = d.player.get("ammo_sel", {})
		p.gun.loaded = d.player.get("loaded", {})
	if p.nerve and d.player.has("nerve"):
		var nv: Dictionary = d.player.nerve
		p.nerve.core = float(nv.get("core", 100.0))
		p.nerve.rank = clampi(int(nv.get("rank", 1)), 1, 5)
		p.nerve.xp = float(nv.get("xp", 0.0))
		p.nerve.max_meter = p.nerve.RANK_METER[p.nerve.rank - 1]
	Game.log_event("loaded", {"slot": slot})
	loaded.emit()
	return true
