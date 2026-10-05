extends Mission
## Chapter 3, mission 2 — A Leg to Set. At Mesquite Wells, Shale's riders have broken the Ybarra girl's leg. The
## only doctor is Cornelius Abernathy, drunk in Fausto's cantina and owing a mule skinner eleven dollars: pay, or
## make Barlow stand aside (a fight). Lead the staggering doctor to the house; his hands shake — one drink or none
## (the steadiness of the setting, Doc's arc, later lines). Ruth holds the child still (steady_hand minigame).
## Doc joins the Outfit.

const C3 = preload("res://src/missions/ch3/ch3.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")

const P = preload("res://src/missions/places.gd")

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
	var hb := P.building("mesquite_wells", "house")
	var house_in := P.inside(hb, 0.55, C2.near(well, 6.0, -6.0))
	var house := P.door_out(hb, C2.near(well, 6.0, -8.0))
	await d.goto(house, 10.0, "Ride into Mesquite Wells", true)
	if d.aborted(): return false
	d.dismount_player()
	var rosa := C2.spawn_friend(d, C2.near(house, 1.5, 0.5), {"role": "lady", "faction": "civilian", "name": "Rosa Ybarra", "seed": 3201})
	var mateo := C2.spawn_friend(d, C2.near(house, -1.5, 1.0), {"role": "rancher", "faction": "civilian", "name": "Mateo Ybarra", "seed": 3202})
	var ines: Human = d.spawn_at(house_in, {"role": "child", "faction": "civilian", "name": "Inés Ybarra", "seed": 3203}, house)
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
	var cb := P.building("mesquite_wells", "cantina")
	var cantina_fb := C3.dry(C2.near(town, 30.0, -12.0))
	var cantina := P.inside(cb, 0.5, cantina_fb)
	var bt := P.spot(cb, "bartender")
	var doc: Human = d.spawn_at(P.at(P.spot(cb, "bar_patron", 0), C2.near(cantina, -1.2, 0.6)), {"role": "townsfolk", "faction": "civilian", "name": "Cornelius Abernathy", "seed": 3204}, P.at(bt, cantina))
	var fausto: Human = d.spawn_at(P.at(bt, C2.near(cantina, 2.0, -1.5)), {"role": "bartender", "faction": "civilian", "name": "Fausto Medina", "seed": 3205}, P.look(bt, cantina))
	var skinners: Array = []
	for i in 2:
		skinners.append(d.spawn_at(P.at(P.spot(cb, "bar_patron", 2 + i), C2.near(cantina, 1.2 + i, 1.6)), {"role": "worker", "faction": "syndicate",
			"name": "Mule Skinner", "seed": 3210 + i, "weapon": "lockhart_sa", "skill": 0.3, "aggressive": false}, cantina))
	if skinners.size() > 0:
		skinners[0].display_name = "Royce Barlow"
	for h in [doc, fausto] + skinners:
		d.npc_hold(h, cantina)
	await d.goto(P.door_in(cb, cantina), 2.5, "Go into Fausto's cantina")
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
	P.open_doors(cb, cantina)
	P.open_doors(hb, house)
	await d.lead(doc, "Get the doctor to the Ybarra house", house_in, 3.0, ["c3_doc_18", "c3_doc_19", "c3_doc_20"])
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
