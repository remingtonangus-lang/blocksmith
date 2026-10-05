extends Mission
## Chapter 5, mission 3 — What We Owe. Hap's fate and the Outfit's split. If Hap held the horses he's on Ingrid's
## kitchen table with a ball under his ribs: hold him still while Doc works (steady_hand) — he lives, or he doesn't.
## If he stayed to keep the camp, the posse found Willow Bend first. Then the argument over the ledger and the money:
## Fenn gets the book and the payroll goes back (Standing; Del may go), or the Outfit keeps it all (Joseph goes).
## A messenger shot in the door of his car costs Joseph regardless. Standing then locks the ending.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const P = preload("res://src/missions/places.gd")

func _init() -> void:
	id = "c5_owe"
	title = "What We Owe"
	chapter = 5
	requires = ["c5_train"]

func run(d) -> Variant:
	d.set_time(20.5)
	d.set_weather("fair")
	var hap_alive := false
	var talk_at := Vector3.ZERO
	if C3.flag("hap_wounded"):
		var rb := P.building("halvorsen_ranch", "ranch_house")
		var ranch := Mission.place("halvorsen_ranch")
		var kitchen := P.inside(rb, 0.5, C2.near(ranch, -2.0, 0.0))
		await C3.start_at(d, C2.near(ranch, -16.0, 10.0), ranch, false)
		P.open_doors(rb, kitchen)
		var hap: Human = d.spawn_at(kitchen, {"role": "drover", "faction": "outfit", "name": "Hap Lindqvist", "seed": 7}, kitchen + Vector3(0, 0, 2))
		hap.intent.crouch = true
		var doc: Human = d.spawn_at(P.inside(rb, 0.5, C2.near(ranch, -1.0, 1.0), 1.0), {"role": "townsfolk", "faction": "outfit",
			"name": "Cornelius Abernathy", "seed": 3204}, kitchen)
		var ingrid: Human = d.spawn_at(P.inside(rb, 0.7, C2.near(ranch, -3.0, 1.5), -1.0), {"role": "rancher", "faction": "civilian",
			"name": "Ingrid Halvorsen", "seed": 3101}, kitchen)
		await d.goto(P.door_in(rb, kitchen), 2.5, "Get Hap to Ingrid's kitchen table")
		if d.aborted(): return false
		d.cine_begin()
		await d.say("c5_owe_01", doc)
		await d.say("c5_owe_02", ingrid)
		d.cine_end()
		d.checkpoint("table")
		var held: Dictionary = await d.minigame("steady_hand", {"title": "Hold Hap still", "seconds": 9.0, "band": 0.22, "tremor": 0.35})
		if d.aborted(): return false
		hap_alive = held.get("ok", true)
		d.cine_begin()
		if hap_alive:
			await d.say("c5_owe_03", doc)
			await d.say("c5_owe_04", hap)
		else:
			await d.say("c5_owe_06", hap)
			await d.say("c5_owe_05", doc)
		await d.say("c5_owe_24", ingrid)
		d.cine_end()
		talk_at = P.door_out(rb, ranch)
	else:
		var camp := Mission.place("caddell_camp")
		await C3.start_at(d, C2.near(camp, -60.0, 40.0), camp, true)
		await d.goto(C2.near(camp, -8.0, 6.0), 8.0, "Ride home to Willow Bend", true)
		if d.aborted(): return false
		d.dismount_player()
		for k in 3:
			d.warm_spot(C2.near(camp, -3.0 + k * 3.0, 2.0 + k))
		var billy: Human = C2.spawn_friend(d, C2.near(camp, -6.0, 4.0), {"role": "child", "faction": "outfit", "name": "Billy Pruitt", "seed": 14})
		var joseph: Human = C2.spawn_friend(d, C2.near(camp, -4.0, 6.0), {"role": "hunter", "faction": "outfit", "name": "Joseph Kehoe", "seed": 4101})
		var dl: Human = C2.spawn_friend(d, C2.near(camp, -7.0, 7.0), {"role": "gambler", "faction": "outfit", "name": "Del Arceneaux", "seed": 2201})
		for h in [billy, joseph, dl]:
			d.npc_hold(h, camp)
		d.cine_begin()
		await d.say("c5_owe_07", billy)
		await d.say("c5_owe_08", joseph)
		await d.say("c5_owe_09", Game.player)
		await d.say("c5_owe_10", dl)
		d.cine_end()
		d.checkpoint("burial")
		await d.interact(C2.near(camp, 8.0, -6.0), "Bury Hap under the cottonwoods")
		if d.aborted(): return false
		await d.say("c5_owe_11", billy)
		await d.say("c5_owe_12", Game.player)
		hap_alive = false
		talk_at = C2.near(camp, -4.0, 4.0)
	C3.set_flag("hap_alive", hap_alive)
	d.checkpoint("the_split")
	var dl2: Human = C2.spawn_friend(d, C2.near(talk_at, 2.0, 1.5), {"role": "gambler", "faction": "outfit", "name": "Del Arceneaux", "seed": 2201})
	var jo: Human = C2.spawn_friend(d, C2.near(talk_at, -2.0, 1.5), {"role": "hunter", "faction": "outfit", "name": "Joseph Kehoe", "seed": 4101})
	var doc2: Human = C2.spawn_friend(d, C2.near(talk_at, 0.5, 3.0), {"role": "townsfolk", "faction": "outfit", "name": "Cornelius Abernathy", "seed": 3204})
	for h in [dl2, jo, doc2]:
		d.npc_hold(h, Game.player.global_position)
	var joseph_gone: bool = C3.flag("messenger_killed")
	d.cine_begin()
	if joseph_gone:
		await d.say("c5_owe_23", jo)
	await d.say("c5_owe_13", dl2)
	if not joseph_gone:
		await d.say("c5_owe_14", jo)
	var split: int = await d.choose("The ledger and the money on the table. The Outfit watching you.",
		["The ledger goes to Fenn. The payroll goes back to the people Pell took it from.", "We keep it all. We've paid for it."])
	if split == 0:
		await d.say("c5_owe_15", Game.player)
		if C3.flag("payroll_taken"):
			await d.say("c5_owe_16", dl2)
			C3.set_flag("del_left", true)
		if not joseph_gone:
			await d.say("c5_owe_17", jo)
		C3.set_flag("ledger_to_fenn", true)
		if Game.state:
			Game.state.change_standing(6.0, "gave the ledger to Fenn and the payroll back")
	else:
		await d.say("c5_owe_18", Game.player)
		if not joseph_gone:
			await d.say("c5_owe_19", jo)
		joseph_gone = true
		await d.say("c5_owe_20", dl2)
		await d.say("c5_owe_21", doc2)
		C3.set_flag("ledger_to_fenn", false)
		if Game.state:
			if C3.flag("payroll_taken"):
				Game.state.add_money(400.0)
			Game.state.change_standing(-6.0, "kept the stolen payroll")
	C3.set_flag("joseph_left", joseph_gone)
	await d.say("c5_owe_22", Game.player)
	d.cine_end()
	var branch: String = d.lock_ending()
	C3.set_flag("ch5_done", true)
	Game.log_event("ch5_end", {"branch": branch, "hap_alive": hap_alive, "joseph_left": joseph_gone,
		"del_left": C3.flag("del_left", false)})
	return true
