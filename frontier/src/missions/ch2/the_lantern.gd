extends Mission
## Chapter 2, mission 1 — The Lantern. Ruth rides into Port Linden after Eben Shale and walks in on two hired men
## breaking Augustus Fenn's press. Talk them out (Standing) or draw; Fenn walks her past the syndicate's land office
## and the Exchange bank, names Lucius Pell, and asks whether he may print her name (remembered by Pell in "Terms").

const C2 = preload("res://src/missions/ch2/ch2.gd")

const P = preload("res://src/missions/places.gd")

func _init() -> void:
	id = "c2_lantern"
	title = "The Lantern"
	chapter = 2
	requires = ["c1_fire"]

func run(d) -> Variant:
	d.set_time(9.4)
	d.set_weather("fair")
	var start := Mission.road_point("bitter_spring", "port_linden", 0.86)
	var ahead := Mission.road_point("bitter_spring", "port_linden", 0.93)
	if start != Vector3.ZERO:
		d.place_player(start, atan2(-(ahead.x - start.x), -(ahead.z - start.z)))
	await d.wait(1.0)
	await d.say("c2_lan_01", Game.player)
	d.checkpoint("road")
	var office_fb := C2.spot("port_linden", -60.0, -20.0)
	var nb := P.building("port_linden", "newspaper")
	var office := P.inside(nb, 0.55, office_fb)
	await d.goto(P.door_out(nb, office_fb + Vector3(-14.0, 0, 6.0)), 8.0, "Ride into Port Linden and find the Lantern office")
	if d.aborted(): return false
	var fenn: Human = d.spawn_at(P.at(P.spot(nb, "clerk"), C2.near(office, 2.5, -1.5)), {"role": "townsfolk", "faction": "civilian",
		"name": "Augustus Fenn", "seed": 2101}, office)
	var toughs: Array = []
	for i in 2:
		toughs.append(d.spawn_at(P.inside(nb, 0.45 + 0.15 * i, C2.near(office, -2.0 + i * 1.5, 1.5), -1.0 + i * 2.0), {"role": "gunman",
			"faction": "syndicate", "name": "Hired Man", "seed": 2110 + i, "weapon": "lockhart_sa", "skill": 0.3, "aggressive": false}, office))
	if toughs.size() > 1:
		toughs[0].display_name = "Carl Ebbing"
		toughs[1].display_name = "Wade Snell"
	if fenn:
		d.npc_hold(fenn, office + Vector3(-2.0, 0, 1.5))
	for t in toughs:
		d.npc_hold(t, office + Vector3(2.5, 0, -1.5))
	await d.say("c2_lan_02", Game.player)
	await d.goto(P.door_in(nb, office), 2.5, "See what the noise is at the Lantern")
	if d.aborted(): return false
	var carl = C2.one(toughs)
	var wade = toughs[1] if toughs.size() > 1 else carl
	d.cine_begin()
	await d.say("c2_lan_03", carl)
	await d.say("c2_lan_04", wade)
	await d.say("c2_lan_05", fenn)
	await d.say("c2_lan_06", Game.player)
	await d.say("c2_lan_07", carl)
	var pick: int = await d.choose("Two men with hammers. One has a pistol in his belt and keeps touching it.",
		["Talk them out the door.", "Draw on them."])
	if pick == 0:
		await d.say("c2_lan_08", Game.player)
		await d.say("c2_lan_09", wade)
		await d.say("c2_lan_10", carl)
		d.cine_end()
		for t in toughs:
			d.npc_release(t)
			t.brain.target = Game.player
			t.brain.target_last_seen = Game.player.global_position
			t.brain.state = t.brain.State.FLEE
		if Game.state:
			Game.state.good_deed("help_stranger")
		C2.set_flag("lantern_talked", true)
		await d.wait(2.0)
	else:
		await d.say("c2_lan_11", Game.player)
		await d.say("c2_lan_12", carl)
		d.cine_end()
		C2.hostile(d, toughs)
		d.checkpoint("press_fight")
		await d.wait_dead(toughs, "Stop the men breaking Fenn's press")
		if d.aborted(): return false
		C2.set_flag("lantern_talked", false)
	if fenn == null or not fenn.alive:
		d.fail("Fenn was killed")
		return false
	d.checkpoint("fenn")
	d.cine_begin()
	await d.say("c2_lan_13", fenn)
	await d.say("c2_lan_14", Game.player)
	await d.say("c2_lan_15", fenn)
	await d.say("c2_lan_16", Game.player)
	await d.say("c2_lan_17", fenn)
	d.cine_end()
	var overlook := P.door_out(P.building("port_linden", "bank"), C2.spot("port_linden", -12.0, 34.0))
	P.open_doors(nb, office)
	await d.follow(fenn, "Walk with Fenn", overlook, 5.0, ["c2_lan_18", "c2_lan_19", "c2_lan_20", "c2_lan_21", "c2_lan_22", "c2_lan_23"])
	if d.aborted(): return false
	d.checkpoint("overlook")
	d.npc_hold(fenn, Game.player.global_position)
	d.cine_begin()
	await d.say("c2_lan_24", fenn)
	await d.say("c2_lan_25", Game.player)
	await d.say("c2_lan_26", fenn)
	var name_pick: int = await d.choose("Fenn wants to put your name in the Lantern.",
		["Print it. Let them know who's asking.", "Keep my name out of it."])
	if name_pick == 0:
		await d.say("c2_lan_27", Game.player)
		await d.say("c2_lan_28", fenn)
		C2.set_flag("ruth_in_print", true)
	else:
		await d.say("c2_lan_29", Game.player)
		await d.say("c2_lan_30", fenn)
		C2.set_flag("ruth_in_print", false)
	await d.say("c2_lan_31", fenn)
	await d.say("c2_lan_32", Game.player)
	d.cine_end()
	return true
