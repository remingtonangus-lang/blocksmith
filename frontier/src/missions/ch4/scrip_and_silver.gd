extends Mission
## Chapter 4, mission 5 — Scrip and Silver. Night in Coldwater: Ashby's guards come down with torches to burn the
## strike kitchen; hold them off it with the miners and Joseph (defend). Garrity, cornered in the company office:
## make him sign the miners' terms at gunpoint (the strike is won tonight and void in any court; Standing down) or
## hand him and his own letter to the territorial mine inspector (slow, lawful, theirs; Standing up). Joseph joins
## the Outfit; home to Willow Bend in the snow.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const C4 = preload("res://src/missions/ch4/ch4.gd")

const P = preload("res://src/missions/places.gd")

func _init() -> void:
	id = "c4_strike"
	title = "Scrip and Silver"
	chapter = 4
	requires = ["c4_asa"]

func run(d) -> Variant:
	d.set_time(21.2)
	d.set_weather("overcast")
	d.set_snow(0.5)
	var kitchen := C4.kitchen()
	await C3.start_at(d, C2.near(kitchen, -4.0, 3.0), kitchen, false)
	var nora := C2.spawn_friend(d, C2.near(kitchen, 1.5, 0.0), {"role": "lady", "faction": "civilian", "name": "Nora Kilbride", "seed": 4102})
	var dai := C2.spawn_friend(d, C2.near(kitchen, -1.5, 1.0), {"role": "worker", "faction": "outfit", "name": "Dai Pritchard", "seed": 4103,
		"weapon": "harlan_carbine", "skill": 0.4})
	var joseph := C2.spawn_friend(d, C2.near(kitchen, -3.0, -2.0), {"role": "hunter", "faction": "outfit", "name": "Joseph Kehoe", "seed": 4101,
		"weapon": "bowden_bolt", "skill": 0.7, "health": 160.0})
	var miners: Array = d.spawn_group(C2.near(kitchen, 2.0, 4.0), 2, {"role": "worker", "faction": "outfit", "name": "Miner", "seed": 4510,
		"weapon": "lockhart_sa", "skill": 0.3}, 2.0)
	for h in [nora, dai, joseph] + miners:
		d.npc_hold(h, Game.player.global_position)
	d.cine_begin()
	await d.say("c4_strike_01", nora)
	await d.say("c4_strike_02", dai)
	await d.say("c4_strike_03", Game.player)
	d.cine_end()
	d.checkpoint("kitchen")
	var guards: Array = d.spawn_group(C2.near(kitchen, -60.0, 30.0), 6, {"role": "gunman", "faction": "syndicate", "name": "Company Guard",
		"seed": 4520, "weapon": "harlan_carbine", "skill": 0.35, "aggressive": false}, 6.0)
	if guards.size() > 0:
		guards[0].display_name = "Captain Ward Ashby"
	await d.say("c4_strike_04", C2.one(guards))
	await d.say("c4_strike_05", nora)
	# torch-bearers walk at the kitchen while the rest shoot
	var torches: Array = guards.slice(0, 2)
	for t in torches:
		d.npc_walk_to(t, kitchen, Human.JOG)
		t.faction = "bandit"
	C2.hostile(d, guards.slice(2))
	for h in [dai, joseph] + miners:
		d.npc_release(h)
	if nora:
		d.npc_release(nora)
		nora.brain.state = nora.brain.State.COWER
	var held: bool = await d.defend(kitchen, 5.0, guards, "Keep the torches off the kitchen", 7.0)
	if d.aborted(): return false
	C3.set_flag("kitchen_burned", not held)
	d.checkpoint("garrity")
	for h in [nora, joseph]:
		if h and h.alive:
			d.npc_hold(h, Game.player.global_position)
	await d.say("c4_strike_06" if held else "c4_strike_07", nora)
	var office := C4.office()
	var garrity: Human = d.spawn_at(C4.office_in(), {"role": "townsfolk", "faction": "civilian", "name": "Silas Garrity", "seed": 4140}, office)
	P.open_doors(P.building("coldwater", "assay"), office)
	await d.goto(office, 3.0, "Find Garrity at the company office")
	if d.aborted(): return false
	await d.goto(C4.office_in(), 2.2, "Go in after Garrity")
	if d.aborted(): return false
	d.npc_hold(garrity, Game.player.global_position)
	d.cine_begin()
	await d.say("c4_strike_08", garrity)
	await d.say("c4_strike_09", Game.player)
	await d.say("c4_strike_10", garrity)
	var how: int = await d.choose("Garrity, the miners' terms on his desk, and Asa's letter in your coat.",
		["Make him sign the terms. Now.", "Hand him and his letter to the territorial inspector."])
	if how == 0:
		await d.say("c4_strike_11", Game.player)
		await d.say("c4_strike_12", garrity)
		if dai and dai.alive:
			d._put_on_ground(dai, office)
			d.npc_hold(dai, garrity.global_position if garrity else office)
		await d.say("c4_strike_13", dai)
		C3.set_flag("strike_terms", "signed")
		if Game.state:
			Game.state.change_standing(-1.0, "made Garrity sign at gunpoint")
	else:
		await d.say("c4_strike_14", Game.player)
		var insp := C2.spawn_friend(d, C2.near(office, -3.0, 2.0), {"role": "lawman", "faction": "law", "name": "Inspector Hale", "seed": 4530})
		await d.say("c4_strike_15", insp)
		await d.say("c4_strike_16", garrity)
		await d.say("c4_strike_17", nora)
		C3.set_flag("strike_terms", "inspector")
		if Game.state:
			Game.state.change_standing(3.0, "gave Garrity to the mine inspector")
	await d.say("c4_strike_18", joseph)
	await d.say("c4_strike_19", Game.player)
	await d.say("c4_strike_20", joseph)
	d.cine_end()
	C3.set_flag("joseph_joined", true)
	d.checkpoint("home")
	var home := Mission.place("caddell_camp")
	await d.mount_up("Mount up")
	await d.goto(home, 12.0, "Ride home to Willow Bend", true)
	if d.aborted(): return false
	d.set_time(19.0)
	d.set_snow(0.2)
	d.dismount_player()
	var hap := C2.spawn_friend(d, C2.near(home, 2.0, 1.0), {"role": "drover", "faction": "outfit", "name": "Hap Lindqvist", "seed": 7})
	var del := C2.spawn_friend(d, C2.near(home, -1.5, 2.2), {"role": "gambler", "faction": "outfit", "name": "Del Arceneaux", "seed": 2201})
	var doc := C2.spawn_friend(d, C2.near(home, -2.2, -0.5), {"role": "townsfolk", "faction": "outfit", "name": "Cornelius Abernathy", "seed": 3204})
	var billy := C2.spawn_friend(d, C2.near(home, 0.5, -2.2), {"role": "child", "faction": "outfit", "name": "Billy Pruitt", "seed": 14})
	var jo := C2.spawn_friend(d, C2.near(home, 3.0, -1.0), {"role": "hunter", "faction": "outfit", "name": "Joseph Kehoe", "seed": 4101})
	for h in [hap, del, doc, billy, jo]:
		d.npc_hold(h, home)
	d.cine_begin()
	await d.say("c4_strike_21", hap)
	await d.say("c4_strike_22", del)
	await d.say("c4_strike_23", doc)
	await d.say("c4_strike_24", billy)
	await d.say("c4_strike_25", jo)
	await d.say("c4_strike_26", Game.player)
	await d.say("c4_strike_27", jo)
	d.cine_end()
	C3.set_flag("ch4_done", true)
	return true
