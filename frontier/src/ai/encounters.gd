extends Node
## Random encounters along the roads: every few minutes of travel, if the player is on or near a road and away from
## towns, one of the encounter types may stage itself ahead of her (out of sight), play out through the mission
## director's verbs, and resolve by what she does. Outcomes touch Standing, money, items and the law.
## Eighteen kinds: the first six are small favours and trades; the rest are scenes with a choice or a fight
## (ambush, a hanging, a runaway wagon, a lost child, a duel, a snake-oil seller, bounty hunters when Ruth has a
## price on her head, a stranded traveller who robs her, a drunk with a pistol, a barn fire, a circuit preacher, a
## stage hold-up). Bots: `--bot encounters` stages every kind under autopilot; --choices picks the branches.

const TYPES := ["wagon", "robbery", "prisoner", "snakebite", "hunter", "grave",
	"ambush", "hanging", "runaway", "lost_child", "duel", "snake_oil", "bounty_hunters", "stranded", "drunk", "fire",
	"preacher", "stage"]
## Relative odds. bounty_hunters only rolls while Ruth has a bounty; the robbing traveller is rare on purpose.
const WEIGHTS := {"stranded": 0.25, "duel": 0.6, "hanging": 0.7, "fire": 0.7, "bounty_hunters": 2.0}
const COOLDOWN := 150.0
const TRAIN = preload("res://src/missions/ch5/train.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")

var _t := 90.0
var active := ""
var nodes: Array = []
var rng := RandomNumberGenerator.new()
var history := []
var props: Array = []      # wagons, fires: freed when the encounter ends
var outcome := ""          # how the last one ended (bots read it from the log)

func _ready() -> void:
	rng.seed = 1899 * 13
	Game.set("encounters", self)
	if Game.missions:
		Game.missions._load_dialogue("res://design/dialogue/encounters.json")

func _process(dt: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_process_impl(dt)
	Game.prof("encounters.gd _process", _pt0)

func _process_impl(dt: float) -> void:
	if Game.player == null or Game.missions == null or Game.missions.active != null or active != "":
		return
	_t -= dt * (1.0 + clampf(float(Game.player.get("speed")), 0.0, 10.0) / 4.0)
	if _t > 0.0:
		return
	_t = COOLDOWN * rng.randf_range(0.7, 1.3)
	var pp: Vector3 = Game.player.global_position
	var near := Game.world.nearest_settlement(pp.x, pp.z)
	if not near.is_empty() and Vector2(near.x - pp.x, near.z - pp.z).length() < float(near.r) + 250.0:
		return
	start(pick_kind())

## Weighted roll over the kinds that make sense right now.
func pick_kind() -> String:
	var pool := []
	var total := 0.0
	for k in TYPES:
		if k == "bounty_hunters" and _bounty() <= 0.0:
			continue
		var w: float = WEIGHTS.get(k, 1.0)
		if history.size() > 0 and history.back() == k:
			w *= 0.2
		pool.append([k, w])
		total += w
	var r := rng.randf() * total
	for e in pool:
		r -= float(e[1])
		if r <= 0.0:
			return e[0]
	return pool.back()[0]

## Stage an encounter ahead of the player on the nearest road (or at a given point for tests).
func start(kind: String, at := Vector3.INF) -> void:
	var p := at
	if p == Vector3.INF:
		var pp: Vector3 = Game.player.global_position
		var fwd := Vector3(-sin(Game.player.facing), 0, -cos(Game.player.facing))
		var id := Game.roads.nearest(pp + fwd * 110.0) if Game.roads else -1
		p = Game.roads.pts[id] if id >= 0 else pp + fwd * 110.0
	p.y = Game.world.height(p.x, p.z)
	active = kind
	outcome = ""
	history.append(kind)
	Game.log_event("encounter", {"kind": kind, "at": [p.x, p.z]})
	await call("_" + kind, p)
	var md = Game.missions
	for n in nodes:
		if is_instance_valid(n) and n is Human:
			md.npc_release(n)
			if n.alive and n.brain:
				n.brain.state = n.brain.State.ROUTINE
	nodes.clear()
	for n in props:
		if is_instance_valid(n):
			n.queue_free()
	props.clear()
	if md.active == null:
		md._abort = false          # a fight lost or a softlock inside an encounter must not poison the next mission
		md.set_objective("")
	Game.log_event("encounter_end", {"kind": kind, "outcome": outcome})
	active = ""

func _spawn(p: Vector3, opts: Dictionary) -> Human:
	Game.terrain.ensure_tile(p)
	var h := Human.spawn(Game.main, p + Vector3(0, 0.3, 0), opts)
	nodes.append(h)
	return h

func _wait_near(p: Vector3, r: float, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if Game.player.global_position.distance_to(p) < r or Game.missions.autopilot:
			return true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return false

func _wagon(p: Vector3) -> void:
	var w := _spawn(p + Vector3(2, 0, 0), {"seed": rng.randi(), "role": "wagoner", "faction": "civilian", "name": "Wagoner"})
	w.brain.state = w.brain.State.IDLE
	if not await _wait_near(p, 12.0, 120.0):
		return
	await Game.missions.say("enc_wagon_01", w)
	await Game.missions.interact(p + Vector3(1, 0, 1), "Help lift the wagon")
	await Game.missions.say("enc_wagon_02", Game.player)
	await Game.missions.say("enc_wagon_03", w)
	Game.state.good_deed("help_stranger")
	Game.state.add_item("coffee")

func _robbery(p: Vector3) -> void:
	var gang: Array = []
	for i in rng.randi_range(2, 3):
		gang.append(_spawn(p + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)),
			{"seed": rng.randi(), "role": "gunman", "faction": "bandit", "name": "Road Agent", "weapon": "lockhart_sa", "skill": 0.35}))
	for g in gang:
		g.brain.group = gang
		g.brain.aggressive = false
	if not await _wait_near(p, 18.0, 120.0):
		return
	await Game.missions.say("enc_robbery_01", gang[0])
	await Game.missions.say("enc_robbery_02", Game.player)
	for g in gang:
		g.brain.aggressive = true
		g.brain.share_target(Game.player)
	await Game.missions.wait_dead(gang, "Road agents")

func _prisoner(p: Vector3) -> void:
	var dep := _spawn(p, {"seed": rng.randi(), "role": "lawman", "faction": "law", "name": "Deputy", "weapon": "harlan_carbine"})
	var pri := _spawn(p + Vector3(1.5, 0, 0.5), {"seed": rng.randi(), "role": "prisoner", "faction": "civilian", "name": "Prisoner"})
	pri.brain.state = pri.brain.State.SURRENDER
	if not await _wait_near(p, 12.0, 120.0):
		return
	await Game.missions.say("enc_prisoner_01", pri)
	await Game.missions.say("enc_prisoner_02", dep)
	await Game.missions.say("enc_prisoner_03", Game.player)
	# freeing him means drawing on the deputy: that path is the player's choice (crime system judges it)

func _snakebite(p: Vector3) -> void:
	var v := _spawn(p, {"seed": rng.randi(), "role": "prospector", "faction": "civilian", "name": "Prospector", "health": 30.0})
	v.brain.state = v.brain.State.COWER
	if not await _wait_near(p, 10.0, 120.0):
		return
	await Game.missions.say("enc_snake_01", v)
	if int(Game.state.inventory.get("tonic_health", 0)) > 0:
		await Game.missions.interact(p, "Give him a tonic")
		Game.state.inventory["tonic_health"] -= 1
		await Game.missions.say("enc_snake_02", Game.player)
		await Game.missions.say("enc_snake_03", v)
		Game.state.good_deed("help_stranger")
		Game.state.flags["snakebite_tip"] = true

func _hunter(p: Vector3) -> void:
	var h := _spawn(p, {"seed": rng.randi(), "role": "hunter", "faction": "civilian", "name": "Meat Hunter", "weapon": "bowden_bolt"})
	if not await _wait_near(p, 10.0, 120.0):
		return
	await Game.missions.say("enc_hunter_01", h)
	if Game.state.money >= 0.5:
		Game.state.add_money(-0.5)
		Game.state.add_item("meat_mule_deer")

func _grave(p: Vector3) -> void:
	var w := _spawn(p, {"seed": rng.randi(), "role": "lady", "faction": "civilian", "name": "Mourner"})
	w.brain.state = w.brain.State.IDLE
	if not await _wait_near(p, 10.0, 120.0):
		return
	await Game.missions.say("enc_grave_01", w)
	await Game.missions.interact(p + Vector3(1.5, 0, 0), "Dig the grave")
	await Game.missions.say("enc_grave_02", Game.player)
	Game.state.good_deed("help_stranger")

# ------------------------------------------------------------------ helpers for the scene encounters
func _bounty() -> float:
	var st = Game.state
	if st == null:
		return 0.0
	var t := 0.0
	for k in st.bounties:
		t += float(st.bounties[k])
	return t

func _worst_county() -> String:
	var st = Game.state
	var best := ""
	var amt := 0.0
	for k in st.bounties:
		if float(st.bounties[k]) > amt:
			amt = float(st.bounties[k])
			best = k
	return best

func _at(p: Vector3, dx: float, dz: float) -> Vector3:
	return C2.near(p, dx, dz)

func _say(id: String, who: Node3D) -> void:
	await Game.missions.say(id, who)

func _hold(group: Array, look: Vector3) -> void:
	for h in group:
		if h and is_instance_valid(h):
			Game.missions.npc_hold(h, look)

func _gang(p: Vector3, n: int, name: String, weapon := "lockhart_sa", spread := 4.0) -> Array:
	var g: Array = []
	for i in n:
		var h := _spawn(_at(p, rng.randf_range(-spread, spread), rng.randf_range(-spread, spread)),
			{"seed": rng.randi(), "role": "gunman", "faction": "bandit", "name": name, "weapon": weapon, "skill": 0.35})
		h.brain.aggressive = false
		g.append(h)
	for h in g:
		h.brain.group = g
	return g

## Turn a group loose on Ruth and wait for the fight to end. True if she came out of it.
func _fight(group: Array, text: String) -> bool:
	var md = Game.missions
	C2.hostile(md, group)
	await md.wait_dead(group, text)
	return not md.aborted()

func _standing(delta: float, why: String) -> void:
	if Game.state:
		Game.state.change_standing(delta, why)

func _deed(kind: String) -> void:
	if Game.state:
		Game.state.good_deed(kind)

func _ruth() -> Node3D:
	return Game.player

# ------------------------------------------------------------------ 7. ambush in the rocks
func _ambush(p: Vector3) -> void:
	var lair := _at(p, 26.0, -18.0)
	var gang := _gang(lair, 3, "Road Agent", "merriman_lever", 5.0)
	for g in gang:
		g.intent.crouch = true
	_hold(gang, p)
	if not await _wait_near(p, 30.0, 150.0):
		return
	Game.missions.say_async("enc_ambush_01", gang[0])
	await _say("enc_ambush_02", _ruth())
	if await _fight(gang, "Ambush — get to cover and fight"):
		outcome = "fought_off"
		await _say("enc_ambush_03", _ruth())
		_standing(0.5, "drove off an ambush")
		Game.state.add_money(float(rng.randi_range(2, 7)))

# ------------------------------------------------------------------ 8. a hanging to stop
func _hanging(p: Vector3) -> void:
	var limb := _at(p, 14.0, 8.0)
	var men := _gang(limb, 3, "Vigilante", "harlan_carbine", 2.5)
	men[0].display_name = "Vigilance Captain"
	var man := _spawn(limb, {"seed": rng.randi(), "role": "prisoner", "faction": "civilian", "name": "Condemned Man"})
	man.brain.state = man.brain.State.SURRENDER
	_hold(men, limb)
	_hold([man], p)
	if not await _wait_near(limb, 20.0, 150.0):
		return
	await _say("enc_hang_01", man)
	await _say("enc_hang_02", men[0])
	var pick: int = await Game.missions.choose("A rope over a cottonwood limb, three men with rifles, and one who swears he never touched their stock.",
		["Cut him down.", "Ride on. It's not your rope."])
	if pick == 0:
		await _say("enc_hang_03", _ruth())
		if Game.state.standing >= 30.0:
			# her name carries: they back down and promise him a trial
			await _say("enc_hang_04", men[0])
			outcome = "talked_down"
		else:
			await _say("enc_hang_05", men[0])
			if not await _fight(men, "Stop the hanging"):
				return
			outcome = "fought"
		Game.missions.npc_hold(man, _ruth().global_position)
		await _say("enc_hang_06", man)
		_deed("help_stranger")
	else:
		await _say("enc_hang_07", _ruth())
		_standing(-2.0, "rode past a lynching")
		outcome = "rode_on"

# ------------------------------------------------------------------ 9. runaway wagon
## The wagon runs the nearest road (the train kit's "wagon" car: bed, bow top, a team of two). Ride level with it
## and jump to the seat to haul the team in; too slow and it goes over.
func _road_from(p: Vector3, metres: float) -> Array:
	var best: Array = []
	var bd := 1e9
	var bi := 0
	for r in Game.world.features.roads:
		var pts: Array = r.points
		for i in pts.size():
			var dd := Vector2(float(pts[i][0]) - p.x, float(pts[i][1]) - p.z).length()
			if dd < bd:
				bd = dd
				best = pts
				bi = i
	if best.is_empty() or bd > 60.0:
		return []
	# run the way with more road left
	var fwd := best.size() - 1 - bi > bi
	var out := []
	var acc := 0.0
	var i := bi
	while i >= 0 and i < best.size() and acc < metres:
		out.append(best[i])
		if out.size() > 1:
			var a: Array = out[out.size() - 2]
			acc += Vector2(float(best[i][0]) - float(a[0]), float(best[i][1]) - float(a[1])).length()
		i += 1 if fwd else -1
	return out if acc > 200.0 else []

func _runaway(p: Vector3) -> void:
	var md = Game.missions
	var rail := _road_from(p, 900.0)
	var woman := _spawn(_at(p, 0.0, 0.0), {"seed": rng.randi(), "role": "lady", "faction": "civilian", "name": "Farm Wife"})
	woman.visible = false
	woman.set_physics_process(false)
	if rail.is_empty():
		woman.queue_free()
		return
	var w = TRAIN.new()
	w.car_specs = [{"kind": "wagon", "len": 4.2, "w": 1.8, "h": 2.6}]
	w.accel = 1.4
	Game.main.add_child(w)
	w.setup(rail, false, true)
	props.append(w)
	w.place_at(20.0, 9.0)
	w.target_speed = 9.5
	await _say("enc_runaway_01", null)
	if not await _wait_near(w.car_center(0), 120.0, 60.0):
		return
	var caught := false
	if md.autopilot:
		caught = md.auto_choice(2) == 0
	else:
		md.set_objective("Ride alongside the runaway wagon and jump for the seat")
		var close_t := 0.0
		while w.s < w.length() - 20.0:
			var c: Vector3 = w.car_center(0)
			if _ruth().global_position.distance_to(c) < 5.0:
				close_t += get_physics_process_delta_time()
				if Game.hud:
					Game.hud.prompt("[E]  Jump for the seat")
				if Input.is_action_just_pressed("interact") or close_t > 2.5:
					caught = true
					break
			else:
				close_t = 0.0
			await get_tree().physics_frame
		md.set_objective("")
	if caught:
		md.dismount_player()
		await md.ride_until_stopped(w, 0)
		woman.visible = true
		woman.set_physics_process(true)
		md._put_on_ground(woman, _ruth().global_position + Vector3(2.0, 0, 1.0))
		md.npc_hold(woman, _ruth().global_position)
		await _say("enc_runaway_02", _ruth())
		await _say("enc_runaway_03", woman)
		_deed("help_stranger")
		Game.state.add_money(3.0)
		outcome = "caught"
	else:
		w.brake()
		w.speed = 0.0
		var c2: Vector3 = w.car_center(0)
		if not Game.headless and w.cars.size() > 0:
			w.cars[0].node.rotation.z = 1.4       # over on its side
		woman.visible = true
		woman.set_physics_process(true)
		md._put_on_ground(woman, c2 + Vector3(3.0, 0, 2.0))
		woman.intent.crouch = true
		await _say("enc_runaway_04", woman)
		outcome = "overturned"

# ------------------------------------------------------------------ 10. a lost child
func _lost_child(p: Vector3) -> void:
	var md = Game.missions
	var kid := _spawn(_at(p, 4.0, 3.0), {"seed": rng.randi(), "role": "child", "faction": "civilian", "name": "Lost Girl"})
	md.npc_hold(kid, p)
	if not await _wait_near(kid.global_position, 12.0, 150.0):
		return
	await _say("enc_child_01", kid)
	await _say("enc_child_02", _ruth())
	var home := _at(p, -150.0, 110.0)
	var mother := _spawn(home, {"seed": rng.randi(), "role": "lady", "faction": "civilian", "name": "Homesteader's Wife"})
	md.npc_hold(mother, p)
	md.npc_release(kid)
	await md.lead(kid, "Walk the girl home to the homestead", home, 8.0, ["enc_child_03"])
	if md.aborted():
		return
	md.npc_hold(mother, _ruth().global_position)
	await _say("enc_child_04", mother)
	_deed("help_stranger")
	Game.state.add_item("jerky", 2)
	outcome = "home"

# ------------------------------------------------------------------ 11. a duel challenge
func _duel(p: Vector3) -> void:
	var md = Game.missions
	var kid := _spawn(_at(p, 6.0, -4.0), {"seed": rng.randi(), "role": "gunman", "faction": "civilian", "name": "Lew Tolliver",
		"weapon": "lockhart_sa", "skill": 0.55})
	kid.brain.aggressive = false
	md.npc_hold(kid, p)
	if not await _wait_near(kid.global_position, 14.0, 150.0):
		return
	await _say("enc_duel_01" if Game.state.standing >= 0.0 else "enc_duel_02", kid)
	var pick: int = await md.choose("A boy of nineteen with a new gun belt wants to know if the stories are true.",
		["Step off twenty paces.", "Talk him out of it."])
	if pick == 0:
		await _say("enc_duel_03", _ruth())
		if await _fight([kid], "Twenty paces. Draw when he does"):
			await _say("enc_duel_04", _ruth())
			_standing(-1.0, "killed a boy in a street duel")
			outcome = "shot"
	else:
		await _say("enc_duel_05", _ruth())
		await _say("enc_duel_06", kid)
		_deed("spare_enemy")
		md.npc_walk_to(kid, _at(p, 120.0, -80.0))
		outcome = "talked"

# ------------------------------------------------------------------ 12. a snake-oil seller
func _snake_oil(p: Vector3) -> void:
	var md = Game.missions
	var man := _spawn(_at(p, 5.0, 2.0), {"seed": rng.randi(), "role": "gambler", "faction": "civilian", "name": "Elixir Seller"})
	md.npc_hold(man, p)
	if not await _wait_near(man.global_position, 12.0, 150.0):
		return
	await _say("enc_oil_01", man)
	var pick: int = await md.choose("Two dollars a bottle for Professor Whitlow's Mountain Balsam.",
		["Buy a bottle.", "Tell him what's in it, loud enough for the road."])
	if pick == 0:
		Game.state.add_money(-minf(2.0, Game.state.money))
		Game.state.add_item("tonic_nerve")
		await _say("enc_oil_02", man)
		await _say("enc_oil_03", _ruth())
		outcome = "bought"
	else:
		await _say("enc_oil_04", _ruth())
		await _say("enc_oil_05", man)
		_standing(1.0, "named a quack for what he was")
		md.npc_walk_to(man, _at(p, -100.0, 60.0))
		outcome = "exposed"

# ------------------------------------------------------------------ 13. bounty hunters (only with a price on her)
func _bounty_hunters(p: Vector3) -> void:
	var md = Game.missions
	var owed := _bounty()
	var county := _worst_county()
	var gang := _gang(_at(p, 10.0, -6.0), 3, "Bounty Hunter", "merriman_lever", 3.0)
	gang[0].display_name = "Abner Coyle"
	_hold(gang, p)
	if not await _wait_near(gang[0].global_position, 25.0, 150.0):
		return
	await _say("enc_bh_01", gang[0])
	var can_pay: bool = owed > 0.0 and Game.state.money >= owed
	var pick: int = await md.choose("Three men with a poster of you and a pair of irons. The bounty stands at $%d." % int(owed),
		["Pay it off. ($%d)" % int(owed) if can_pay else "Try to talk them round.", "Tell them to come and collect."])
	if pick == 0 and can_pay:
		await _say("enc_bh_02", _ruth())
		Game.state.pay_bounty(county)
		await _say("enc_bh_03", gang[0])
		for g in gang:
			md.npc_walk_to(g, _at(p, 140.0, 40.0))
		outcome = "paid"
		return
	if pick == 0:
		await _say("enc_bh_04", _ruth())
		await _say("enc_bh_05", gang[0])
	else:
		await _say("enc_bh_06", _ruth())
	if await _fight(gang, "The bounty hunters"):
		outcome = "fought"

# ------------------------------------------------------------------ 14. the stranded traveller (rare): he robs you
func _stranded(p: Vector3) -> void:
	var md = Game.missions
	var man := _spawn(_at(p, 4.0, 3.0), {"seed": rng.randi(), "role": "traveller", "faction": "civilian", "name": "Stranded Traveller",
		"weapon": "lockhart_sa", "skill": 0.4})
	man.brain.aggressive = false
	md.npc_hold(man, p)
	if not await _wait_near(man.global_position, 10.0, 150.0):
		return
	await _say("enc_strand_01", man)
	await md.interact(man.global_position + Vector3(0.8, 0, 0.8), "Give him water")
	if md.aborted():
		return
	_standing(1.0, "gave a stranger water")
	await _say("enc_strand_02", man)
	var pick: int = await md.choose("The man you just gave your canteen to has a pistol in your ribs.",
		["Hand over the purse.", "Draw on him."])
	if pick == 0:
		var take := minf(10.0, Game.state.money)
		Game.state.add_money(-take)
		await _say("enc_strand_03", _ruth())
		Game.state.flags["robbed_by_traveller"] = true
		md.npc_walk_to(man, _at(p, -160.0, -90.0), Human.SPRINT)
		outcome = "robbed"
	else:
		if await _fight([man], "He's drawn on you"):
			await _say("enc_strand_04", _ruth())
			outcome = "fought"

# ------------------------------------------------------------------ 15. a drunk with a pistol
func _drunk(p: Vector3) -> void:
	var md = Game.missions
	var man := _spawn(_at(p, 6.0, 4.0), {"seed": rng.randi(), "role": "drunk", "faction": "civilian", "name": "Drunk Drover",
		"weapon": "lockhart_sa", "skill": 0.1})
	man.brain.aggressive = false
	md.npc_hold(man, p)
	if not await _wait_near(man.global_position, 14.0, 150.0):
		return
	Game.noise.emit(man.global_position, 60.0, man)
	await _say("enc_drunk_01", man)
	var pick: int = await md.choose("A drover on a three-day drunk, shooting at bottles a few yards from the road.",
		["Take one pull with him.", "Take the pistol off him before he kills somebody."])
	if pick == 0:
		await _say("enc_drunk_02", _ruth())
		await _say("enc_drunk_03", man)
		outcome = "drank"
	else:
		await _say("enc_drunk_04", _ruth())
		await _say("enc_drunk_05", man)
		_standing(1.0, "disarmed a drunk on the road")
		outcome = "disarmed"

# ------------------------------------------------------------------ 16. a barn fire
func _fire(p: Vector3) -> void:
	var md = Game.missions
	var barn := _at(p, -30.0, 24.0)
	var man := _spawn(_at(barn, 6.0, 4.0), {"seed": rng.randi(), "role": "rancher", "faction": "civilian", "name": "Homesteader"})
	md.npc_hold(man, barn)
	var pts := []
	for i in 4:
		var a := TAU * i / 4.0
		pts.append(_at(barn, cos(a) * 5.0, sin(a) * 5.0))
	for q in pts:
		_flames(q)
	if not await _wait_near(barn, 30.0, 150.0):
		return
	await _say("enc_fire_01", man)
	var n: int = await md.timed_tasks(pts, "Throw water on the fire", 45.0, "Throw a bucket")
	var saved := n >= pts.size()
	if md.autopilot:
		saved = md.auto_choice(2) == 0
	for f in props:
		if is_instance_valid(f) and f.name == "Flames":
			f.queue_free()
	md.npc_hold(man, _ruth().global_position)
	if saved:
		await _say("enc_fire_02", man)
		_deed("help_stranger")
		outcome = "saved"
	else:
		await _say("enc_fire_03", man)
		_standing(1.0, "fought a barn fire")
		outcome = "lost"

func _flames(q: Vector3) -> void:
	if Game.headless:
		return
	var f := CPUParticles3D.new()
	f.name = "Flames"
	f.amount = 40
	f.lifetime = 1.1
	f.direction = Vector3.UP
	f.spread = 18.0
	f.gravity = Vector3(0, 2.0, 0)
	f.initial_velocity_min = 1.0
	f.initial_velocity_max = 2.6
	f.scale_amount_min = 0.5
	f.scale_amount_max = 1.4
	var qm := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1.0, 0.55, 0.15, 0.7)
	qm.material = m
	f.mesh = qm
	Game.main.add_child(f)
	f.global_position = q + Vector3(0, 0.5, 0)
	props.append(f)

# ------------------------------------------------------------------ 17. a circuit preacher
func _preacher(p: Vector3) -> void:
	var md = Game.missions
	var man := _spawn(_at(p, 5.0, -3.0), {"seed": rng.randi(), "role": "preacher", "faction": "civilian", "name": "Circuit Preacher"})
	md.npc_hold(man, p)
	if not await _wait_near(man.global_position, 12.0, 150.0):
		return
	await _say("enc_preach_01" if Game.state.standing >= 0.0 else "enc_preach_02", man)
	var pick: int = await md.choose("A circuit preacher on a mule, collecting for a church that's still mostly a plan.",
		["Give him a dollar.", "Keep riding."])
	if pick == 0:
		Game.state.add_money(-minf(1.0, Game.state.money))
		_deed("donation")
		await _say("enc_preach_03", man)
		outcome = "gave"
	else:
		await _say("enc_preach_04", _ruth())
		await _say("enc_preach_05", man)
		outcome = "passed"

# ------------------------------------------------------------------ 18. a stage hold-up
func _stage(p: Vector3) -> void:
	var md = Game.missions
	var stop := _at(p, 8.0, 0.0)
	var driver := _spawn(stop, {"seed": rng.randi(), "role": "worker", "faction": "civilian", "name": "Stage Driver"})
	var fare := _spawn(_at(stop, 1.5, 1.0), {"seed": rng.randi(), "role": "lady", "faction": "civilian", "name": "Passenger"})
	for h in [driver, fare]:
		h.brain.state = h.brain.State.SURRENDER
	var gang := _gang(_at(stop, -5.0, 3.0), 2, "Road Agent", "lockhart_sa", 2.0)
	_hold(gang, stop)
	if not await _wait_near(stop, 22.0, 150.0):
		return
	await _say("enc_stage_01", gang[0])
	var pick: int = await md.choose("Two road agents, a stage driver with his hands up and a lady passenger in tears.",
		["Draw on them.", "Ride on. Not your coach."])
	if pick == 0:
		if await _fight(gang, "Stop the hold-up"):
			md.npc_hold(driver, _ruth().global_position)
			await _say("enc_stage_02", driver)
			_deed("help_stranger")
			Game.state.add_money(5.0)
			outcome = "stopped"
	else:
		await _say("enc_stage_03", _ruth())
		_standing(-1.0, "rode past a stage robbery")
		outcome = "rode_on"
