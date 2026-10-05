extends Mission
## Chapter 3, mission 2 — A Leg to Set. At Mesquite Wells, Shale's riders have broken the Ybarra girl's leg. The
## only doctor is Cornelius Abernathy, drunk in Fausto's cantina and owing a mule skinner eleven dollars: pay, or
## make Barlow stand aside (a fight). Lead the staggering doctor to the house; his hands shake — one drink or none
## (the steadiness of the setting, Doc's arc, later lines). Ruth holds the child still (steady_hand minigame).
## Doc joins the Outfit.

const C3 = preload("res://src/missions/ch3/ch3.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")

func _init() -> void:
	id = "c3_doc"
	title = "A Leg to Set"
	chapter = 3
	requires = ["c3_ranch"]

func run(d) -> Variant:
	d.set_time(15.2)
	d.set_weather("clear")
	var town := Mission.place("mesquite_wells")
	var well := C3.road("windmill_flats", "mesquite_wells", 0.93, "mesquite_wells")
	var start := C3.road("windmill_flats", "mesquite_wells", 0.8, "mesquite_wells")
	await C3.start_at(d, start, well, true)
	await d.say("c3_doc_01", Game.player)
	d.checkpoint("arrive")
	var house := C2.near(well, 6.0, -8.0)
	await d.goto(house, 10.0, "Ride into Mesquite Wells", true)
	if d.aborted(): return false
	d.dismount_player()
	var rosa := C2.spawn_friend(d, C2.near(house, 1.5, 0.5), {"role": "lady", "faction": "civilian", "name": "Rosa Ybarra", "seed": 3201})
	var mateo := C2.spawn_friend(d, C2.near(house, -1.5, 1.0), {"role": "rancher", "faction": "civilian", "name": "Mateo Ybarra", "seed": 3202})
	var ines := C2.spawn_friend(d, C2.near(house, 0.5, 2.6), {"role": "child", "faction": "civilian", "name": "Inés Ybarra", "seed": 3203})
	d.npc_hold(rosa, Game.player.global_position)
	d.npc_hold(mateo, Game.player.global_position)
	d.npc_hold(ines, house)
	d.cine_begin()
	await d.say("c3_doc_02", rosa)
	await d.say("c3_doc_03", Game.player)
	await d.say("c3_doc_04", rosa)
	await d.say("c3_doc_05", mateo)
	await d.say("c3_doc_06", ines)
	await d.say("c3_doc_07", rosa)
	await d.say("c3_doc_08", Game.player)
	d.cine_end()
	d.checkpoint("ybarra")
	var cantina := C3.dry(C2.near(town, 30.0, -12.0))
	var doc := C2.spawn_friend(d, C2.near(cantina, -1.2, 0.6), {"role": "townsfolk", "faction": "civilian", "name": "Cornelius Abernathy", "seed": 3204})
	var fausto := C2.spawn_friend(d, C2.near(cantina, 2.0, -1.5), {"role": "bartender", "faction": "civilian", "name": "Fausto Medina", "seed": 3205})
	var skinners: Array = d.spawn_group(C2.near(cantina, 1.2, 1.6), 2, {"role": "worker", "faction": "syndicate", "name": "Mule Skinner",
		"seed": 3210, "weapon": "lockhart_sa", "skill": 0.3, "aggressive": false}, 1.0)
	if skinners.size() > 0:
		skinners[0].display_name = "Royce Barlow"
	for h in [doc, fausto] + skinners:
		d.npc_hold(h, cantina)
	await d.interact(cantina, "Go into Fausto's cantina")
	if d.aborted(): return false
	var barlow = C2.one(skinners)
	d.cine_begin()
	await d.say("c3_doc_09", fausto)
	await d.say("c3_doc_10", doc)
	await d.say("c3_doc_11", Game.player)
	await d.say("c3_doc_12", doc)
	await d.say("c3_doc_13", barlow)
	var tab: int = await d.choose("Royce Barlow, mule skinner, is between you and the door.",
		["Pay Barlow his eleven dollars.", "Tell Barlow to stand aside."])
	if tab == 0:
		await d.say("c3_doc_14", Game.player)
		await d.say("c3_doc_15", barlow)
		if Game.state:
			Game.state.add_money(-minf(11.0, float(Game.state.money)))
		d.cine_end()
	else:
		await d.say("c3_doc_16", Game.player)
		await d.say("c3_doc_17", barlow)
		d.cine_end()
		if doc:
			d.npc_release(doc)
			doc.brain.state = doc.brain.State.COWER
		C2.hostile(d, skinners)
		d.checkpoint("cantina_fight")
		await d.wait_dead(skinners, "Deal with the mule skinners")
		if d.aborted(): return false
	C3.set_flag("paid_doc_tab", tab == 0)
	if doc == null or not doc.alive:
		d.fail("The doctor was killed")
		return false
	d.checkpoint("lead_doc")
	await d.lead(doc, "Get the doctor to the Ybarra house", C2.near(house, 0.0, 1.5), 4.0, ["c3_doc_18", "c3_doc_19", "c3_doc_20"])
	if d.aborted(): return false
	d.npc_hold(doc, ines.global_position if ines else house)
	d.cine_begin()
	await d.say("c3_doc_21", doc)
	await d.say("c3_doc_22", doc)
	var drink: int = await d.choose("Doc's hands are shaking. There's a bottle on the Ybarras' shelf.", ["Give him one drink.", "No. Do it sober."])
	if drink == 0:
		await d.say("c3_doc_23", Game.player)
		await d.say("c3_doc_24", doc)
	else:
		await d.say("c3_doc_25", Game.player)
		await d.say("c3_doc_26", doc)
		await d.say("c3_doc_27", Game.player)
		if Game.state:
			Game.state.change_standing(1.0, "kept Doc off the bottle")
	C3.set_flag("doc_sober", drink == 1)
	d.cine_end()
	var held: Dictionary = await d.minigame("steady_hand", {"title": "Hold her still", "seconds": 8.0,
		"band": 0.26 if drink == 0 else 0.2, "tremor": 0.2 if drink == 0 else 0.55})
	if d.aborted(): return false
	var clean: bool = held.get("ok", true)
	C3.set_flag("ines_leg_clean", clean)
	d.checkpoint("leg_set")
	d.cine_begin()
	await d.say("c3_doc_28" if clean else "c3_doc_29", doc)
	await d.say("c3_doc_30", rosa)
	await d.say("c3_doc_31", doc)
	await d.say("c3_doc_32", Game.player)
	await d.say("c3_doc_33", doc)
	await d.say("c3_doc_34", Game.player)
	await d.say("c3_doc_35", doc)
	await d.say("c3_doc_36", mateo)
	await d.say("c3_doc_37", Game.player)
	await d.say("c3_doc_38", rosa)
	d.cine_end()
	C3.set_flag("doc_joined", true)
	if Game.state:
		Game.state.good_deed("help_stranger")
	return true
