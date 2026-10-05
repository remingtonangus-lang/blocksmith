extends Mission
## Chapter 2, mission 3 — Thornwood. Hask's books point at the Thornwood logging camp. Billy Pruitt, who ran from it,
## attaches himself uninvited and leads Ruth in through the timber; they overhear the syndicate's paymaster tell the
## foreman that Thursday's silver at the Exchange is bait Pell has "arranged to be surprised" by. Billy is spotted:
## pay his "debt" (money, Standing) and fight the paymaster's guards, or refuse and fight the foreman's men.

const C2 = preload("res://src/missions/ch2/ch2.gd")

func _init() -> void:
	id = "c2_thornwood"
	title = "Thornwood"
	chapter = 2
	requires = ["c2_cards"]

func run(d) -> Variant:
	d.set_time(13.6)
	d.set_weather("overcast")
	var start := Mission.road_point("dunmore_homestead", "thornwood_logging", 0.25)
	var ahead := Mission.road_point("dunmore_homestead", "thornwood_logging", 0.3)
	if start != Vector3.ZERO:
		d.place_player(start, atan2(-(ahead.x - start.x), -(ahead.z - start.z)))
	await d.wait(1.0)
	await d.say("c2_thorn_01", Game.player)
	d.checkpoint("road")
	var camp := Mission.place("thornwood_logging")
	var turn := Mission.road_point("dunmore_homestead", "thornwood_logging", 0.7)
	if turn == Vector3.ZERO:
		turn = C2.near(camp, -160.0, 90.0)
	await d.goto(turn, 14.0, "Ride toward the Thornwood logging camp")
	if d.aborted(): return false
	var billy := C2.spawn_friend(d, C2.near(Game.player.global_position, -6.0, 5.0), {"role": "child", "faction": "outfit",
		"name": "Billy Pruitt", "seed": 14, "health": 140.0})
	d.npc_hold(billy, Game.player.global_position)
	d.cine_begin()
	await d.say("c2_thorn_02", billy)
	await d.say("c2_thorn_03", Game.player)
	await d.say("c2_thorn_04", billy)
	await d.say("c2_thorn_05", Game.player)
	await d.say("c2_thorn_06", billy)
	var keep: int = await d.choose("Billy has already decided. The question is whether you have.",
		["Go home, Billy.", "Stay behind me. When I say run, you run."])
	if keep == 0:
		await d.say("c2_thorn_07", Game.player)
		await d.say("c2_thorn_08", billy)
	else:
		await d.say("c2_thorn_09", Game.player)
		await d.say("c2_thorn_10", billy)
	C2.set_flag("billy_trusted", keep == 1)
	d.cine_end()
	# the back way in, through the timber above the camp
	var back := C2.near(camp, -45.0, -30.0)
	if billy == null:
		d.fail("Billy is gone")
		return false
	await d.follow(billy, "Follow Billy through the timber", back, 5.0, ["c2_thorn_11", "c2_thorn_12", "c2_thorn_13"])
	if d.aborted(): return false
	d.checkpoint("above_camp")
	var shack := C2.near(camp, -18.0, -10.0)
	var tolliver := C2.spawn_friend(d, shack, {"role": "worker", "faction": "syndicate", "name": "Lew Tolliver", "seed": 2301,
		"weapon": "lockhart_sa", "skill": 0.4, "aggressive": false})
	var cobb := C2.spawn_friend(d, C2.near(shack, 1.8, 0.6), {"role": "townsfolk", "faction": "civilian", "name": "Ansel Cobb", "seed": 2302})
	var loggers: Array = d.spawn_group(C2.near(camp, -8.0, -4.0), 3, {"role": "worker", "faction": "syndicate", "name": "Logger",
		"seed": 2310, "weapon": "lockhart_sa", "skill": 0.3, "aggressive": false}, 4.0)
	var guards: Array = d.spawn_group(C2.near(shack, 6.0, 4.0), 2, {"role": "gunman", "faction": "syndicate", "name": "Cobb's Guard",
		"seed": 2320, "weapon": "merriman_lever", "skill": 0.45, "aggressive": false}, 2.0)
	d.npc_hold(tolliver, shack + Vector3(1.8, 0, 0.6))
	d.npc_hold(cobb, shack)
	for g in loggers + guards:
		d.npc_hold(g, shack)
	d.npc_hold(billy, shack)
	await d.say("c2_thorn_14", billy)
	await d.goto(C2.near(shack, -14.0, -12.0), 4.0, "Creep close enough to hear (crouch)")
	if d.aborted(): return false
	d.cine_begin()
	await d.say("c2_thorn_15", tolliver)
	await d.say("c2_thorn_16", cobb)
	await d.say("c2_thorn_17", tolliver)
	await d.say("c2_thorn_18", cobb)
	await d.say("c2_thorn_19", Game.player)
	C2.set_flag("heard_thursday", true)
	await d.say("c2_thorn_20", tolliver)
	var pay: int = await d.choose("Tolliver and his men, axes and pistols between them. Billy is behind you, very still.",
		["Pay what the boy owes.", "The boy owes you nothing."])
	var fight: Array = []
	if pay == 0:
		var have := C2.money()
		if have >= 22.0:
			await d.say("c2_thorn_21", Game.player)
			if Game.state:
				Game.state.add_money(-22.0)
		else:
			await d.say("c2_thorn_33", Game.player)
			if Game.state:
				Game.state.add_money(-have)
		await d.say("c2_thorn_22", tolliver)
		await d.say("c2_thorn_23", billy)
		if Game.state:
			Game.state.good_deed("help_stranger")
		C2.set_flag("paid_billy", true)
		await d.say("c2_thorn_24", cobb)
		fight = guards
	else:
		await d.say("c2_thorn_25", Game.player)
		await d.say("c2_thorn_26", tolliver)
		C2.set_flag("paid_billy", false)
		fight = [tolliver] + loggers
	d.cine_end()
	if cobb:
		d.npc_release(cobb)
		cobb.brain.target = Game.player
		cobb.brain.target_last_seen = Game.player.global_position
		cobb.brain.state = cobb.brain.State.FLEE
	d.npc_release(billy)
	if billy:
		billy.brain.state = billy.brain.State.COWER
	if fight.has(tolliver) and tolliver:
		tolliver.brain.bravery = 0.0      # a foreman, not a gunman: he gives up when his men fall
	C2.hostile(d, fight)
	d.checkpoint("camp_fight")
	await d.wait_dead(fight.filter(func(h): return h != tolliver), "Get Billy out of Thornwood")
	if d.aborted(): return false
	if tolliver and is_instance_valid(tolliver) and tolliver.alive and fight.has(tolliver):
		tolliver.brain.state = tolliver.brain.State.SURRENDER
	if billy == null or not billy.alive:
		d.fail("Billy was killed")
		return false
	d.npc_hold(billy, Game.player.global_position)
	d.cine_begin()
	await d.say("c2_thorn_27" if pay == 0 else "c2_thorn_28", billy)
	await d.say("c2_thorn_29", Game.player)
	await d.say("c2_thorn_30", billy)
	await d.say("c2_thorn_31", Game.player)
	await d.say("c2_thorn_32", billy)
	d.cine_end()
	C2.set_flag("billy_rides", true)
	return true
