extends Mission
## Chapter 3, mission 5 — The Dry Fork. Night ride with Del to Cutter Shale's line camp; creep past the sentry (or
## be seen), break the camp, and Cutter gives up — and gives up who fired at Harlan's Siding. The choice: take him
## to Sheriff Mabry (lead the prisoner across country; his men try to cut him loose; Mabry is turned enough to hold
## him; Standing up) or end it here (Standing down; his crew chases Ruth off the Fork). Home to Willow Bend, where the
## Outfit answers what she did, and the first rain in four months comes in.

const C3 = preload("res://src/missions/ch3/ch3.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")

const P = preload("res://src/missions/places.gd")

func _init() -> void:
	id = "c3_fork"
	title = "The Dry Fork"
	chapter = 3
	requires = ["c3_rights"]

func run(d) -> Variant:
	d.set_time(23.2)
	d.set_weather("clear")
	var camp := C3.dry(Vector3(-2048.0, 0, -300.0))
	var start := C3.dry(camp + Vector3(320.0, 0, 40.0))
	await C3.start_at(d, start, camp, true)
	var del = C3.rider(d, start + Vector3(4, 0, 4), {"role": "gambler", "faction": "outfit", "name": "Del Arceneaux", "seed": 2201,
		"weapon": "lockhart_sa", "skill": 0.65, "health": 160.0}, "morgan")
	del.ride_with(Game.player, Vector3(4, 0, 3))
	await d.say("c3_fork_04", Game.player)
	d.checkpoint("ride")
	var approach := C3.dry(camp + Vector3(85.0, 0, 12.0))
	await d.goto(approach, 10.0, "Ride up the Dry Fork to Cutter's line camp", true)
	if d.aborted(): return false
	del.halt()
	d.cine_begin()
	await d.say("c3_fork_01", del.man)
	await d.say("c3_fork_02", Game.player)
	await d.say("c3_fork_03", del.man)
	d.cine_end()
	d.dismount_player()
	del.get_down()
	d.npc_hold(del.man, camp)
	var sentry := C2.spawn_friend(d, C2.near(camp, 26.0, -6.0), {"role": "gunman", "faction": "syndicate", "name": "Line Camp Sentry",
		"seed": 3501, "weapon": "merriman_lever", "skill": 0.35, "aggressive": false})
	var crew: Array = d.spawn_group(C2.near(camp, -2.0, 2.0), 4, {"role": "gunman", "faction": "syndicate", "name": "Shale Rider",
		"seed": 3510, "weapon": "lockhart_sa", "skill": 0.4, "aggressive": false}, 3.0)
	var cutter = C2.one(crew)
	if cutter:
		cutter.display_name = "Cutter Shale"
	d.npc_hold(sentry, C2.near(camp, 120.0, -60.0))
	for h in crew:
		d.npc_hold(h, camp)
	d.checkpoint("approach")
	if Game.hud and not d.autopilot:
		Game.hud.notice("Crouch (C / B) and come at the soddy out of the sentry's sight", 5.0)
	var quiet: bool = await d.sneak_to(C2.near(camp, 6.0, 4.0), 3.0, "Creep up on the soddy", [sentry])
	if d.aborted(): return false
	C3.set_flag("fork_quiet", quiet)
	var men: Array = crew.slice(1)
	if quiet:
		await d.say("c3_fork_06", Game.player)
		if sentry:
			men.append(sentry)
	else:
		await d.say("c3_fork_05", sentry)
		men.append(sentry)
	await d.say("c3_fork_07", cutter)
	if cutter:
		cutter.brain.bravery = 0.0
	d.npc_release(del.man)
	C2.hostile(d, men + [cutter])
	await d.wait_dead(men, "Break Cutter's camp")
	if d.aborted(): return false
	if cutter == null or not is_instance_valid(cutter) or not cutter.alive:
		# he died in the fight: the choice was made for her
		C3.set_flag("cutter_fate", "dead")
	else:
		cutter.brain.aggressive = false
		cutter.brain.target = null
		cutter.brain.state = cutter.brain.State.SURRENDER
		cutter.faction = "syndicate"     # a prisoner now: nobody on Ruth's side shoots him
		d.npc_hold(cutter, Game.player.global_position)
		cutter.intent.crouch = true
	if del.man == null or not del.man.alive:
		d.fail("Del was killed")
		return false
	d.checkpoint("cutter_down")
	var fate := "dead"
	if cutter and is_instance_valid(cutter) and cutter.alive:
		d.npc_hold(del.man, cutter.global_position)
		d.cine_begin()
		await d.say("c3_fork_08", cutter)
		await d.say("c3_fork_09", Game.player)
		await d.say("c3_fork_10", cutter)
		var pick: int = await d.choose("Cutter Shale on his knees in the dirt of his own camp.", ["Take him in to Sheriff Mabry.", "End it here."])
		if pick == 0:
			fate = "jailed"
			await d.say("c3_fork_11", Game.player)
			await d.say("c3_fork_12", cutter)
			await d.say("c3_fork_13", del.man)
			d.cine_end()
		else:
			await d.say("c3_fork_14", Game.player)
			d.cine_end()
			cutter.faction = "bandit"
			cutter.brain.state = cutter.brain.State.SURRENDER
			cutter.damageable.apply_hit({"amount": 999.0, "zone": "head", "attacker": Game.player})
			Game.noise.emit(cutter.global_position, 80.0, Game.player)
			await d.say("c3_fork_15", del.man)
	C3.set_flag("cutter_fate", fate)
	d.checkpoint("after_cutter")
	var shb := P.building("bitter_spring", "sheriff")
	var office := P.door_out(shb, Mission.place("bitter_spring", -20.0, 14.0))
	if fate == "jailed":
		if Game.state:
			Game.state.good_deed("bring_alive")
		cutter.damageable.max_health = 5000.0
		cutter.damageable.health = 5000.0
		cutter.intent.crouch = false
		await d.mount_up("Mount up. Cutter walks.")
		del.ride_with(Game.player, Vector3(-4, 0, 3))
		del.man.set_physics_process(false)
		del._seat()
		var mid := C3.dry(camp.lerp(office, 0.45))
		await d.lead(cutter, "Take Cutter to Sheriff Mabry in Bitter Spring", mid, 8.0, ["c3_fork_16"])
		if d.aborted(): return false
		var gang: Array = d.spawn_group(C2.near(mid, 40.0, -30.0), 4, {"role": "gunman", "faction": "syndicate", "name": "Shale Rider",
			"seed": 3520, "weapon": "merriman_lever", "skill": 0.4, "aggressive": false}, 6.0)
		if gang.size() > 0:
			gang[0].display_name = "Harl Dunphy"
		d.npc_hold(cutter, C2.one(gang).global_position if C2.one(gang) else mid)
		await d.say("c3_fork_17", C2.one(gang))
		await d.say("c3_fork_18", cutter)
		C2.hostile(d, gang)
		d.checkpoint("rescue_fight")
		await d.wait_dead(gang, "Don't let them cut Cutter loose")
		if d.aborted(): return false
		await d.lead(cutter, "Take Cutter to Sheriff Mabry in Bitter Spring", office, 6.0)
		if d.aborted(): return false
		var desk := P.spot(shb, "sheriff_desk")
		var mabry: Human = d.spawn_at(P.at(desk, C2.near(office, 2.0, 0.0)), {"role": "lawman", "faction": "law", "name": "Sheriff Mabry", "seed": 503,
			"weapon": "lockhart_sa"}, office)
		P.open_doors(shb, office)
		d.dismount_player()
		d._teleport_player(P.door_in(shb, office))
		d._put_on_ground(cutter, P.at(P.spot(shb, "cell_bunk"), C2.near(office, 2.5, 2.0)))
		d.npc_hold(mabry, Game.player.global_position)
		d.npc_hold(cutter, mabry.global_position if mabry else office)
		d.dismount_player()
		d.cine_begin()
		await d.say("c3_fork_19", mabry)
		await d.say("c3_fork_20", Game.player)
		await d.say("c3_fork_21", mabry)
		await d.say("c3_fork_22", mabry)
		d.cine_end()
		C3.set_flag("mabry_turned", true)
		if cutter and is_instance_valid(cutter):
			cutter.queue_free()
	else:
		var chasers: Array = d.spawn_group(C2.near(camp, -70.0, -40.0), 3, {"role": "gunman", "faction": "syndicate", "name": "Shale Rider",
			"seed": 3530, "weapon": "merriman_lever", "skill": 0.4, "aggressive": false}, 6.0)
		await d.say("c3_fork_23", del.man)
		C2.hostile(d, chasers)
		await d.mount_up("Get on your horse")
		del.ride_with(Game.player, Vector3(-4, 0, 3))
		del._seat()
		d.checkpoint("chase")
		await d.escape(camp, 220.0, "Ride off the Fork", 50.0)
		if d.aborted(): return false
	# home
	var home := Mission.place("caddell_camp")
	await d.goto(home, 12.0, "Ride home to Willow Bend", true)
	if d.aborted(): return false
	d.set_time(6.2)
	d.set_weather("overcast")
	d.dismount_player()
	var hap := C2.spawn_friend(d, C2.near(home, 2.0, 1.0), {"role": "drover", "faction": "outfit", "name": "Hap Lindqvist", "seed": 7})
	var doc := C2.spawn_friend(d, C2.near(home, -2.0, 1.5), {"role": "townsfolk", "faction": "outfit", "name": "Cornelius Abernathy", "seed": 3204})
	var billy := C2.spawn_friend(d, C2.near(home, 0.5, -2.2), {"role": "child", "faction": "outfit", "name": "Billy Pruitt", "seed": 14})
	for h in [hap, doc, billy]:
		d.npc_hold(h, home)
	var killed := fate == "dead"
	d.cine_begin()
	await d.say("c3_fork_24" if killed else "c3_fork_25", hap)
	await d.say("c3_fork_26" if killed else "c3_fork_27", doc)
	if killed:
		await d.say("c3_fork_28", billy)
		await d.say("c3_fork_29", Game.player)
	else:
		await d.say("c3_fork_30", billy)
		await d.say("c3_fork_31", Game.player)
	await d.say("c3_fork_32", Game.player)
	d.set_weather("rain")
	await d.say("c3_fork_33", hap)
	d.cine_end()
	C3.set_flag("ch3_done", true)
	return true
