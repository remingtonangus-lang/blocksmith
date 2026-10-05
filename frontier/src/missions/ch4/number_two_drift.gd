extends Mission
## Chapter 4, mission 2 — Number Two Drift. Thursday noon at the Kestrel mine mouth: Dai and three miners went
## into number two for their tools, and the company's man Lute Hensley lights the powder. Dig them out against the
## failing air (timed jobs at the rubble — all four saved if she's quick), or ride Hensley down before he reaches
## the company office (pursuit on horseback: proof of who paid him; Tommy Rees dies under the timber). Garrity
## offers the funeral in scrip; Asa Shale has gone over the Kestrel Pass with a letter for Eben.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const C4 = preload("res://src/missions/ch4/ch4.gd")

func _init() -> void:
	id = "c4_mine"
	title = "Number Two Drift"
	chapter = 4
	requires = ["c4_coldwater"]

func run(d) -> Variant:
	d.set_time(11.6)
	d.set_weather("overcast")
	d.set_snow(0.4)
	var yard := C4.at(C4.MINE_YARD)
	var adit := C4.at(C4.ADIT)
	C4.portal(d, adit, yard)
	await C3.start_at(d, C2.near(yard, -20.0, 18.0), adit, false)
	var joseph := C2.spawn_friend(d, C2.near(yard, -16.0, 14.0), {"role": "hunter", "faction": "outfit", "name": "Joseph Kehoe", "seed": 4101,
		"weapon": "bowden_bolt", "skill": 0.7})
	var nora := C2.spawn_friend(d, C2.near(yard, 6.0, 8.0), {"role": "lady", "faction": "civilian", "name": "Nora Kilbride", "seed": 4102})
	d.npc_hold(joseph, adit)
	d.npc_hold(nora, adit)
	await d.say("c4_mine_01", Game.player)
	await d.goto(C2.near(yard, -4.0, 2.0), 5.0, "Get to the Kestrel mine before noon")
	if d.aborted(): return false
	var hensley = C3.rider(d, C2.near(adit, 8.0, 10.0), {"role": "gunman", "faction": "syndicate", "name": "Lute Hensley", "seed": 4201,
		"weapon": "lockhart_sa", "aggressive": false}, "mustang")
	d.cine_begin()
	await d.say("c4_mine_02", joseph)
	await d.say("c4_mine_03", Game.player)
	await d.say("c4_mine_04", hensley.man)
	d.cine_end()
	C4.blast(d, adit)
	await d.say("c4_mine_05", joseph)
	await d.say("c4_mine_06", nora)
	await d.say("c4_mine_07", joseph)
	d.checkpoint("blast")
	var dig_points := [C2.near(adit, -1.5, 3.0), C2.near(adit, 1.5, 3.2), C2.near(adit, -0.6, 5.0), C2.near(adit, 1.0, 6.2)]
	C4.rubble(d, dig_points)
	var how: int = await d.choose("Four men under the rubble. Hensley spurring his bay for the company office.",
		["Dig them out.", "Ride Hensley down. Joseph and Nora dig."])
	var saved := 0
	if how == 0:
		await d.say("c4_mine_08", Game.player)
		await d.say("c4_mine_10", null)
		var town_office := C4.town(64.0, 34.0)
		hensley.ride_to(town_office)
		var done: int = await d.timed_tasks(dig_points, "Dig them out before the air goes bad", 75.0, "Heave timber")
		if d.aborted(): return false
		saved = 4 if done >= 4 else 3
		C3.set_flag("fuse_proof", false)
	else:
		await d.say("c4_mine_09", Game.player)
		await d.mount_up("Get on your horse")
		var office := C4.town(64.0, 34.0)
		var caught: bool = await d.pursue(hensley, office, "Ride down Hensley", 70.0, 7.0)
		if d.aborted(): return false
		C3.set_flag("fuse_proof", caught)
		if caught and hensley.man and hensley.man.alive:
			hensley.get_down()
			d.npc_hold(hensley.man, Game.player.global_position)
			hensley.man.brain.state = hensley.man.brain.State.SURRENDER
			d.dismount_player()
			d.cine_begin()
			await d.say("c4_mine_13", hensley.man)
			await d.say("c4_mine_14", Game.player)
			await d.say("c4_mine_15", hensley.man)
			d.cine_end()
		await d.goto(C2.near(yard, -2.0, 4.0), 8.0, "Get back to the mine", false)
		if d.aborted(): return false
		saved = 3
	C3.set_flag("miners_saved", saved)
	d.checkpoint("aftermath")
	d.dismount_player()
	var dai := C2.spawn_friend(d, C2.near(adit, 2.0, 9.0), {"role": "worker", "faction": "civilian", "name": "Dai Pritchard", "seed": 4103})
	d.npc_hold(dai, Game.player.global_position)
	d.npc_hold(joseph, Game.player.global_position)
	d.npc_hold(nora, Game.player.global_position)
	d.cine_begin()
	if saved >= 4:
		await d.say("c4_mine_11", dai)
		await d.say("c4_mine_12", nora)
		if Game.state:
			Game.state.change_standing(3.0, "dug the miners out of number two")
	else:
		await d.say("c4_mine_16", joseph)
		await d.say("c4_mine_17", nora)
		if how == 1:
			await d.say("c4_mine_18", Game.player)
		await d.say("c4_mine_19", joseph)
	var garrity := C2.spawn_friend(d, C2.near(yard, -6.0, 6.0), {"role": "townsfolk", "faction": "civilian", "name": "Silas Garrity", "seed": 4140})
	d.npc_hold(garrity, adit)
	await d.say("c4_mine_20", garrity)
	await d.say("c4_mine_21", dai)
	await d.say("c4_mine_22", joseph)
	await d.say("c4_mine_23", Game.player)
	await d.say("c4_mine_24", joseph)
	await d.say("c4_mine_25", Game.player)
	await d.say("c4_mine_26", joseph)
	d.cine_end()
	return true
