extends Mission
## Chapter 4, mission 1 — Coldwater. First snow in the Kestrel Range. Ruth rides up to the silver camp after Asa
## Shale and meets Joseph Kehoe reading Fenn's paper at the livery (he knows what she did to Cutter). The strike
## kitchen: Ashby's company guards break up the meeting — stand with the miners openly (a fight, Standing up) or keep
## out of sight on Joseph's advice and follow Asa unseen to the company office, overhearing Thursday's powder plot.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const C4 = preload("res://src/missions/ch4/ch4.gd")

func _init() -> void:
	id = "c4_coldwater"
	title = "Coldwater"
	chapter = 4
	requires = ["c3_fork"]

func run(d) -> Variant:
	d.set_time(9.0)
	d.set_weather("overcast")
	d.set_snow(0.35)
	var start := C3.road("bitter_spring", "coldwater", 0.9, "coldwater")
	var livery := C4.town(-30.0, 12.0)
	await C3.start_at(d, start, livery, true)
	await d.say("c4_cold_01", Game.player)
	d.checkpoint("road")
	await d.goto(livery, 10.0, "Ride up into Coldwater", true)
	if d.aborted(): return false
	d.dismount_player()
	var joseph := C2.spawn_friend(d, C2.near(livery, 2.0, 1.0), {"role": "hunter", "faction": "civilian", "name": "Joseph Kehoe", "seed": 4101})
	d.npc_hold(joseph, Game.player.global_position)
	d.cine_begin()
	await d.say("c4_cold_02" if C3.flag("cutter_fate", "") == "jailed" else "c4_cold_03", joseph)
	await d.say("c4_cold_04", Game.player)
	await d.say("c4_cold_05", joseph)
	if C3.flag("deeds_kept"):
		await d.say("c4_cold_06", joseph)
	await d.say("c4_cold_07", Game.player)
	await d.say("c4_cold_08", joseph)
	await d.say("c4_cold_09", Game.player)
	await d.say("c4_cold_10", joseph)
	d.cine_end()
	d.checkpoint("joseph")
	var kitchen := C4.kitchen()
	var nora := C2.spawn_friend(d, C2.near(kitchen, 1.5, 0.0), {"role": "lady", "faction": "civilian", "name": "Nora Kilbride", "seed": 4102})
	var dai := C2.spawn_friend(d, C2.near(kitchen, -1.5, 1.0), {"role": "worker", "faction": "civilian", "name": "Dai Pritchard", "seed": 4103})
	var miners: Array = d.spawn_group(C2.near(kitchen, 0.0, 5.0), 4, {"role": "worker", "faction": "civilian", "name": "Miner", "seed": 4110}, 3.0)
	for h in [nora, dai] + miners:
		d.npc_hold(h, kitchen)
	d.npc_walk_to(joseph, C2.near(kitchen, -4.0, -3.0))
	await d.goto(C2.near(kitchen, -3.0, -2.0), 4.0, "Go to the miners' meeting at the strike kitchen")
	if d.aborted(): return false
	d.npc_hold(joseph, kitchen)
	var guards: Array = d.spawn_group(C2.near(kitchen, -14.0, 8.0), 4, {"role": "gunman", "faction": "syndicate", "name": "Company Guard",
		"seed": 4120, "weapon": "harlan_carbine", "skill": 0.4, "aggressive": false}, 2.0)
	var ashby = C2.one(guards)
	if ashby:
		ashby.display_name = "Captain Ward Ashby"
	var asa := C2.spawn_friend(d, C2.near(kitchen, -18.0, 10.0), {"role": "gunman", "faction": "syndicate", "name": "Asa Shale", "seed": 4130,
		"weapon": "lockhart_sa", "aggressive": false})
	for g in guards + [asa]:
		d.npc_hold(g, kitchen)
	d.cine_begin()
	await d.say("c4_cold_11", nora)
	await d.say("c4_cold_12", dai)
	await d.say("c4_cold_13", ashby)
	var stand: int = await d.choose("Ashby's guards, carbines at port arms. The miners have shovels and soup.",
		["Stand with the miners in the open.", "Keep out of sight, as Joseph says, and watch Ashby's men."])
	C3.set_flag("stood_with_miners", stand == 0)
	if stand == 0:
		await d.say("c4_cold_14", Game.player)
		await d.say("c4_cold_15", ashby)
		d.cine_end()
		for h in [nora] + miners:
			d.npc_release(h)
			h.brain.state = h.brain.State.COWER
		if ashby:
			d.npc_release(ashby)
			ashby.brain.target = Game.player
			ashby.brain.target_last_seen = Game.player.global_position
			ashby.brain.state = ashby.brain.State.FLEE
		if asa:
			asa.queue_free()
		var fight: Array = guards.slice(1)
		C2.hostile(d, fight)
		d.checkpoint("street_fight")
		await d.wait_dead(fight, "Stand off Ashby's guards")
		if d.aborted(): return false
		if Game.state:
			Game.state.change_standing(3.0, "stood with the Coldwater miners")
		for h in [nora, dai]:
			d.npc_hold(h, Game.player.global_position)
		d.cine_begin()
		await d.say("c4_cold_21", nora)
		await d.say("c4_cold_22", Game.player)
		await d.say("c4_cold_23", dai)
		d.cine_end()
		C3.set_flag("knows_powder_plot", false)
	else:
		await d.say("c4_cold_16", joseph)
		await d.say("c4_cold_17", Game.player)
		d.cine_end()
		# the meeting breaks up; the boy walks Ashby's message up to the company office
		for h in miners:
			d.npc_walk_to(h, C2.near(kitchen, 40.0, 30.0))
		var office := C4.office()
		var garrity := C2.spawn_friend(d, C2.near(office, 1.5, 0.0), {"role": "townsfolk", "faction": "civilian", "name": "Silas Garrity", "seed": 4140})
		d.npc_hold(garrity, office)
		d.npc_walk_to(asa, C2.near(office, -1.5, 0.5))
		var unseen: bool = await d.sneak_to(C2.near(office, -6.0, -4.0), 3.0, "Follow Asa to the company office unseen", [asa])
		if d.aborted(): return false
		if unseen:
			d.npc_hold(asa, garrity.global_position if garrity else office)
			d.npc_hold(garrity, asa.global_position if asa else office)
			d.cine_begin()
			await d.say("c4_cold_18", garrity)
			await d.say("c4_cold_19", asa)
			await d.say("c4_cold_20", garrity)
			d.cine_end()
			C3.set_flag("knows_powder_plot", true)
		else:
			if asa:
				d.npc_release(asa)
				asa.brain.target = Game.player
				asa.brain.target_last_seen = Game.player.global_position
				asa.brain.state = asa.brain.State.FLEE
			await d.goto(C2.near(kitchen, 2.0, -2.0), 4.0, "Go back to Nora's kitchen")
			if d.aborted(): return false
			d.cine_begin()
			await d.say("c4_cold_21", nora)
			await d.say("c4_cold_22", Game.player)
			await d.say("c4_cold_23", dai)
			d.cine_end()
			C3.set_flag("knows_powder_plot", false)
	d.checkpoint("evening")
	d.set_time(18.4)
	d.npc_hold(joseph, Game.player.global_position)
	d.npc_hold(nora, Game.player.global_position)
	d.cine_begin()
	await d.say("c4_cold_24", joseph)
	await d.say("c4_cold_25", Game.player)
	await d.say("c4_cold_26", joseph)
	await d.say("c4_cold_27", nora)
	d.cine_end()
	return true
