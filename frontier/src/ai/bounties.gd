extends Node3D
## Sheriff's bounty board, beside the door of each county seat's sheriff's office (placed through the settlements
## spots API by main; turn-ins happen at the sheriff's desk spot inside). The posters name a fixed roster of original
## outlaws, two per county, each with a crime, a description, a reward and a lair: a hideout (a fixed place away
## from the roads) or a roaming camp that moves day by day along three sites. Accept a poster and the lair goes on
## the map; near it the outlaw and his gang are in camp around a fire. Break the gang and the outlaw gives up:
## tie him and carry him across the saddle to a sheriff for 1.5x the reward (and Standing), or settle it there and
## bring his gun belt as proof for the plain reward. Resolved outlaws are remembered (flags outlaw_<id>), written
## into the journal, gossiped about and printed in the papers. The board also takes fines: anyone with a bounty on
## Ruth can pay it off here.

const P = preload("res://src/missions/places.gd")
const CAMPFIRE_COL := Color(1.0, 0.55, 0.2)

## The roster. lair: "hideout" (one site) or "roaming" (three sites; today's is day % 3). Sites are offsets from a
## world place (town or POI id), nudged onto dry ground.
const OUTLAWS := [
	{"id": "hatcher", "name": "Cole Hatcher", "county": "bitter_spring", "crime": "horse theft and the killing of a freight agent",
		"looks": "Tall, red-bearded, missing the top of his left ear.", "reward": 60.0, "gang": 3, "lair": "hideout",
		"sites": [["caddell_camp", -520.0, 380.0]], "where": "an old line shack in the Sable bottoms", "loot": "treasure_map_1"},
	{"id": "penn", "name": "Ezra Penn", "county": "bitter_spring", "crime": "robbing church collections and shooting a deacon",
		"looks": "Preaches in a clerical collar he has no right to. Soft voice, hard hands.", "reward": 50.0, "gang": 2, "lair": "roaming",
		"sites": [["windmill_flats", 420.0, -360.0], ["halvorsen_ranch", -380.0, 300.0], ["bitter_spring", 600.0, 520.0]], "where": "a revival tent that moves every few days"},
	{"id": "marlow", "name": "Judith Marlow", "county": "port_linden", "crime": "stage robbery on the Linden road",
		"looks": "Called Jinx. Rides a white-faced bay. Laughs while she works.", "reward": 75.0, "gang": 2, "lair": "roaming",
		"sites": [["greer_post", 500.0, 420.0], ["port_linden", -700.0, 380.0], ["dunmore_homestead", -460.0, 520.0]], "where": "camps along the Linden road, never two nights running"},
	{"id": "fontaine", "name": "Delia Fontaine", "county": "port_linden", "crime": "swindling widows and poisoning a banker",
		"looks": "Handsome, well spoken, fond of lavender water.", "reward": 80.0, "gang": 2, "lair": "hideout",
		"sites": [["dunmore_homestead", 380.0, 300.0]], "where": "an abandoned farmhouse beyond Dunmore"},
	{"id": "crow", "name": "Absalom Crow", "county": "coldwater", "crime": "dynamiting the Kestrel payroll wagon",
		"looks": "Small, burn-scarred hands, smells of blasting powder.", "reward": 120.0, "gang": 4, "lair": "hideout",
		"sites": [["coldwater", 520.0, -420.0]], "where": "a played-out adit above Coldwater"},
	{"id": "mccready", "name": "Rory McCready", "county": "coldwater", "crime": "claim jumping and murder on the Kestrel",
		"looks": "Called Scotch. Big as a door, sings when he drinks.", "reward": 100.0, "gang": 3, "lair": "roaming",
		"sites": [["trapper_cabin_n", 420.0, 380.0], ["coldwater", -520.0, 460.0], ["trapper_cabin_n", -380.0, -420.0]], "where": "hunting camps on the Kestrel slopes"},
	{"id": "pardee", "name": "Wade Pardee", "county": "mesquite_wells", "crime": "rustling Ybarra and Halvorsen cattle",
		"looks": "Rides with his brother Ivo. Both bow-legged, both mean.", "reward": 90.0, "gang": 3, "lair": "roaming",
		"sites": [["mesquite_wells", 560.0, -420.0], ["windmill_flats", -600.0, 420.0], ["san_lazaro", 480.0, -500.0]], "where": "rustlers' camps in the Breaks"},
	{"id": "rusk", "name": "Tobiah Rusk", "county": "mesquite_wells", "crime": "killing a deputy at Mesquite Wells",
		"looks": "Pale eyes, a silver conch on his hatband, quick.", "reward": 140.0, "gang": 4, "lair": "hideout",
		"sites": [["san_lazaro", -420.0, 360.0]], "where": "a dry wash below the San Lazaro mission"},
]

var town_id := ""
var posters: Array = []        # roster entries (dictionaries with name, crime, reward, pos, gang, id...) on this board
var active: Dictionary = {}
var stage := ""                # "", "travel", "fight", "carry", "proof"
var rng := RandomNumberGenerator.new()

func setup(tid: String) -> void:
	town_id = tid
	rng.seed = hash(tid) + 77
	add_to_group("interactable")
	refresh()

static func county_name(tid: String) -> String:
	return str(WorldState.COUNTIES.get(tid, "Sable County"))

static func outlaw(id: String) -> Dictionary:
	for o in OUTLAWS:
		if o.id == id:
			return o
	return {}

static func resolved(id: String) -> bool:
	return Game.state != null and Game.state.flags.has("outlaw_" + id)

## Where an outlaw is today (hideout, or today's roaming camp).
static func lair_pos(o: Dictionary, day := -1) -> Vector3:
	var d: int = day if day >= 0 else (int(Game.sky.day) if Game.sky else 0)
	var sites: Array = o.sites
	var s: Array = sites[d % sites.size()] if o.lair == "roaming" else sites[0]
	var base := Mission.place(str(s[0]))
	var p := Vector3(base.x + float(s[1]), 0, base.z + float(s[2]))
	var w = Game.world
	if w.is_water(p.x, p.z) or (1.0 - w.normal(p.x, p.z).y) > 0.35:
		var found := false
		for r in [20.0, 40.0, 80.0, 140.0]:
			for k in 8:
				var q := p + Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0)) * float(r)
				if not w.is_water(q.x, q.z) and (1.0 - w.normal(q.x, q.z).y) <= 0.35:
					p = q
					found = true
					break
			if found:
				break
	p.y = w.height(p.x, p.z)
	return p

## The board shows its county's outlaws first, then neighbours', up to three unresolved posters.
func refresh() -> void:
	posters.clear()
	var mine := OUTLAWS.filter(func(o): return o.county == town_id and not resolved(o.id))
	var others := OUTLAWS.filter(func(o): return o.county != town_id and not resolved(o.id))
	for o in mine + others:
		if posters.size() >= 3:
			break
		var e: Dictionary = o.duplicate()
		e["pos"] = lair_pos(o)
		posters.append(e)

## The sheriff's desk inside the office (the deputy at the board takes turn-ins; the sheriff sits here).
func desk() -> Vector3:
	var b := P.building(town_id, "sheriff")
	return P.at(P.spot(b, "sheriff_desk"), global_position)

# ------------------------------------------------------------------ the board
func _fines() -> float:
	var t := 0.0
	if Game.state:
		for k in Game.state.bounties:
			t += float(Game.state.bounties[k])
	return t

func interact_prompt() -> String:
	if not active.is_empty():
		if stage in ["carry", "proof"]:
			return "Turn in %s to the sheriff" % active.name
		return "Bounty: %s (in progress)" % active.name
	if _fines() > 0.0:
		return "Read the bounty board (fines and bounties: $%d)" % int(_fines())
	return "Read the bounty board" if not posters.is_empty() else ""

## Pay every bounty and fine on Ruth, in any county (misdemeanour fines included). Returns false if she can't.
func pay_fines() -> bool:
	var st = Game.state
	var owed := _fines()
	if st == null or owed <= 0.0 or st.money < owed:
		return false
	for k in st.bounties.keys():
		if float(st.bounties[k]) > 0.0:
			st.pay_bounty(k)
	st.wanted = 0
	st.wanted_t = 0.0
	st.wanted_changed.emit(0, "")
	Game.log_event("fines_paid", {"amount": owed, "town": town_id})
	Game.say("Paid $%.2f to the county. Your name's clean here, for now." % owed, 4.0)
	return true

func interact(_who: Node) -> void:
	if not active.is_empty():
		if stage in ["carry", "proof"]:
			_turn_in()
		return
	refresh()
	var menus = Game.get("menus")
	if menus == null:
		if not posters.is_empty():
			accept(0)
		return
	var p: PanelContainer = menus._paper_panel(Vector2(900, 620))
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UITheme.label("WANTED", 64, "poster", UITheme.OXBLOOD, false))
	v.add_child(UITheme.label("%s — by order of the sheriff" % county_name(town_id), 22, "italic", UITheme.INK_SOFT, false))
	for i in posters.size():
		var b: Dictionary = posters[i]
		var idx := i
		v.add_child(HSeparator.new())
		var btn: Button = menus._button("%s — $%d dead or alive" % [b.name, int(b.reward)], func():
			accept(idx)
			menus.back())
		btn.add_theme_font_override("font", UITheme.font("serif_bold"))
		btn.add_theme_font_size_override("font_size", 28)
		v.add_child(btn)
		v.add_child(UITheme.label("For %s. %s Known to keep to %s." % [b.crime, b.looks, b.where], 20, "body", UITheme.INK, false))
	if _fines() > 0.0:
		v.add_child(HSeparator.new())
		v.add_child(menus._button("Pay your fines and bounties ($%.2f)" % _fines(), func():
			if not pay_fines():
				Game.say("You can't cover it.", 2.5)
			menus.back()))
	v.add_child(menus._button("Leave", menus.back))
	menus._push(p)

func accept(i: int) -> void:
	if i < 0 or i >= posters.size():
		return
	active = posters.pop_at(i)
	stage = "travel"
	Game.log_event("bounty_accept", {"name": active.name, "reward": active.reward, "id": active.get("id", "")})
	if Game.get("menus"):
		Game.menus.set_waypoint(active.pos)
	Game.say("Bounty accepted: %s, $%d. %s, marked on your map." % [active.name, int(active.reward), str(active.get("where", "Last seen")).capitalize()], 5.0)
	_hunt.call_deferred()

# ------------------------------------------------------------------ the hunt
func _camp_fire(p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "OutlawCamp"
	Game.main.add_child(n)
	n.global_position = p
	if not Game.headless:
		var light := OmniLight3D.new()
		light.light_color = CAMPFIRE_COL
		light.light_energy = 2.0
		light.omni_range = 9.0
		light.position = Vector3(0, 0.8, 0)
		n.add_child(light)
		var f := CPUParticles3D.new()
		f.amount = 30
		f.lifetime = 0.9
		f.direction = Vector3.UP
		f.spread = 15.0
		f.gravity = Vector3(0, 2.0, 0)
		f.initial_velocity_min = 0.6
		f.initial_velocity_max = 1.6
		var qm := QuadMesh.new()
		qm.size = Vector2(0.3, 0.3)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_color = CAMPFIRE_COL
		qm.material = m
		f.mesh = qm
		n.add_child(f)
		for k in 2:
			var tent := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(2.2, 1.6, 2.6)
			tent.mesh = pm
			var tm := StandardMaterial3D.new()
			tm.albedo_color = Color(0.72, 0.66, 0.54)
			tent.material_override = tm
			tent.position = Vector3(-4.0 + 8.0 * k, 0.8, 3.0)
			n.add_child(tent)
	return n

func _hunt() -> void:
	var b := active
	var md = Game.missions
	var lair: Vector3 = b.pos
	while Game.player.global_position.distance_to(lair) > 140.0 and not md.autopilot:
		await get_tree().create_timer(1.0).timeout
		if active.is_empty():
			return
	stage = "fight"
	var fire := _camp_fire(lair)
	var group: Array = md.spawn_group(lair, 1 + int(b.gang), {"role": "gunman", "faction": "bandit", "name": "%s's Rider" % str(b.name).split(" ")[-1],
		"weapon": "merriman_lever", "skill": 0.45, "seed": hash(str(b.get("id", b.name)))}, 9.0)
	var target: Human = group[0]
	target.display_name = b.name
	target.brain.bravery = 0.15
	var gang: Array = group.slice(1)
	for h in group:
		h.brain.aggressive = true
	md.set_objective("Break %s's gang" % b.name)
	# the fight: until the gang is down; the outlaw gives up once he's alone (or dies in it)
	var t := 0.0
	while true:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if md.autopilot and t > 0.5:
			for h in gang:
				if is_instance_valid(h) and h.alive:
					h.damageable.apply_hit({"amount": 999.0, "zone": "chest", "attacker": Game.player})
		var left: Array = gang.filter(func(h): return is_instance_valid(h) and h.alive and h.brain.state != h.brain.State.SURRENDER)
		if not target.alive:
			break
		if left.is_empty() or target.brain.state == target.brain.State.SURRENDER:
			target.brain.aggressive = false
			target.brain.target = null
			target.brain.state = target.brain.State.SURRENDER
			break
		if Game.player.damageable and not Game.player.damageable.alive:
			_abandon(group, fire)
			return
	# loot in the camp (Cole Hatcher carries the first treasure map)
	var loot := str(b.get("loot", ""))
	if loot != "" and Game.state and int(Game.state.inventory.get(loot, 0)) <= 0:
		await md.interact(lair + Vector3(1.2, 0, 1.2), "Search the camp")
		Game.state.add_item(loot)
		if Game.hud:
			Game.hud.notice("A hand-drawn map, folded small, in the outlaw's saddlebag", 4.0)
		Game.log_event("bounty_loot", {"item": loot})
	var alive: bool = target.alive
	if alive:
		target.faction = "civilian"
		var pick: int = await md.choose("%s on his knees by his own fire, hands up." % b.name,
			["Tie him and take him in alive.", "Settle it here."])
		if pick == 1:
			target.damageable.apply_hit({"amount": 999.0, "zone": "head", "attacker": null})
			if Game.state:
				Game.state.change_standing(-4.0, "executed a surrendered outlaw")
			alive = false
	if alive:
		await md.interact(target.global_position, "Tie up %s" % b.name)
		stage = "carry"
		active["prisoner"] = target
		Game.log_event("bounty_tied", {"name": b.name})
		_carry(target)
	else:
		if target and is_instance_valid(target):
			await md.interact(target.global_position, "Take %s's gun belt as proof" % b.name)
		stage = "proof"
		if Game.state:
			Game.state.add_item("proof_%s" % str(b.get("id", "outlaw")))
	active["fire"] = fire
	active["group"] = group
	if Game.get("menus"):
		Game.menus.set_waypoint(global_position)
	md.set_objective("Take %s to the sheriff in %s%s" % [b.name, str(town_id).replace("_", " ").capitalize(), " — he's tied across your saddle" if alive else ""])
	if md.autopilot:
		md._teleport_player(global_position + Vector3(1.0, 0, 1.0))
		await get_tree().physics_frame
		_turn_in()

## A tied prisoner rides across the horse behind Ruth (or walks at her heel when she's afoot).
func _carry(h: Human) -> void:
	h.set_physics_process(false)
	h.brain.set_physics_process(false)
	while not active.is_empty() and stage == "carry" and is_instance_valid(h):
		var p = Game.player
		var horse = p.get("on_horse")
		if horse != null and horse is Node3D:
			var hz: Node3D = horse
			var back := Vector3(sin(hz.rotation.y), 0, cos(hz.rotation.y))
			h.global_position = hz.global_position + back * 0.7 + Vector3(0, 1.15, 0)
			if h.visual:
				h.visual.rotation = Vector3(0, hz.rotation.y + PI * 0.5, PI * 0.5)
		else:
			var fwd := Vector3(-sin(p.facing), 0, -cos(p.facing))
			var q: Vector3 = p.global_position - fwd * 1.6
			q.y = Game.world.height(q.x, q.z)
			h.global_position = h.global_position.lerp(q, 0.15)
			if h.visual:
				h.visual.rotation = Vector3(0, p.facing, 0)
		await get_tree().physics_frame

func _turn_in() -> void:
	if active.is_empty():
		return
	var b := active
	var alive := stage == "carry"
	if not alive and Game.state:
		Game.state.inventory["proof_%s" % str(b.get("id", "outlaw"))] = maxi(int(Game.state.inventory.get("proof_%s" % str(b.get("id", "outlaw")), 0)) - 1, 0)
	_pay(b, alive)
	for k in ["prisoner", "fire"]:
		var n = b.get(k)
		if n != null and is_instance_valid(n):
			n.queue_free()
	# the camp is broken: its people (dead or fled) go with it
	for h in b.get("group", []):
		if h != null and is_instance_valid(h):
			h.queue_free()
	if Game.state:
		Game.state.flags["outlaw_%s" % str(b.get("id", b.name))] = "alive" if alive else "dead"
	Game.missions.set_objective("")
	active = {}
	stage = ""
	refresh()

func _abandon(group: Array, fire: Node3D) -> void:
	for h in group:
		if is_instance_valid(h):
			h.queue_free()
	if is_instance_valid(fire):
		fire.queue_free()
	posters.append(active)
	active = {}
	stage = ""
	Game.missions.set_objective("")

func _pay(b: Dictionary, alive: bool) -> void:
	var amount: float = b.reward * (1.5 if alive else 1.0)
	Game.state.add_money(amount)
	if alive:
		Game.state.good_deed("bring_alive")
	Game.log_event("bounty_paid", {"name": b.name, "alive": alive, "amount": amount, "id": b.get("id", "")})
	if Game.has_meta("news"):
		Game.get_meta("news").record("bounty", {"name": b.name, "alive": alive, "amount": amount, "town": town_id, "id": b.get("id", "")})
	Game.say("Bounty on %s collected: $%d%s" % [b.name, int(amount), " (alive)" if alive else ""], 5.0)
	if Game.get("menus"):
		Game.menus.clear_waypoint()
