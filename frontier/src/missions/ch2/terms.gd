extends Mission
## Chapter 2, mission 5 — Terms. Pell's first move: Ruth's bounty poster is pasted on the Lantern's door (Linden
## County, $200; $250 if she took the bait money), drawn from her old Exhibition bills. Pell is waiting in Fenn's
## office with an offer: the deeds for the complaint. Give them (bounty withdrawn, Fenn's story dies, Standing
## down) or keep them (the price stands, Fenn prints, Standing up). Bounty men are already reading the poster
## across the street: out the back unseen, or fight. Home to Willow Bend, where the Outfit has seen the picture.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const COUNTY := "Linden County"

const P = preload("res://src/missions/places.gd")

func _init() -> void:
	id = "c2_terms"
	title = "Terms"
	chapter = 2
	requires = ["c2_exchange"]

func run(d) -> Variant:
	d.set_time(7.3)
	d.set_weather("clear")
	var office_fb := C2.spot("port_linden", -60.0, -20.0)
	var nb := P.building("port_linden", "newspaper")
	var office := P.inside(nb, 0.55, office_fb)
	var front := P.door_out(nb, C2.near(office_fb, -1.5, 1.0))
	d.place_player(C2.near(front, -40.0, 18.0), 0.0)
	await d.say("c2_terms_01", Game.player)
	await d.interact(front, "Read the notice on the Lantern's door")
	if d.aborted(): return false
	var price := 250.0 if C2.flag("took_satchel") else 200.0
	await d.paper("WANTED", ["!RUTH CADDELL", "alias \"Miss Ruthie, the Ozark Wonder\"",
		"For the robbery of the Linden Exchange Bank, Port Linden, on the night of Thursday last.",
		"A woman of thirty-four years, lean, a scar through the left eyebrow. Rides a bay mare. Shoots exceedingly well.",
		"!$%d REWARD" % int(price),
		"Apply to the Sheriff of Linden County, or to L. Pell, Esq., attorney for the complainants."], "poster", "Tear it down")
	d.post_bounty(COUNTY, price, 1, "Pell's complaint: the Exchange")
	C2.set_flag("ruth_poster", price)
	await d.say("c2_terms_02", Game.player)
	d.checkpoint("poster")
	var fenn: Human = d.spawn_at(P.at(P.spot(nb, "clerk"), C2.near(office, 2.0, -1.0)), {"role": "townsfolk", "faction": "civilian", "name": "Augustus Fenn", "seed": 2101}, office)
	var pell: Human = d.spawn_at(P.inside(nb, 0.7, C2.near(office, 3.2, 1.2), 1.2), {"role": "townsfolk", "faction": "civilian", "name": "Lucius Pell", "seed": 2501}, office)
	await d.goto(P.door_in(nb, C2.near(office, 1.0, 0.0)), 2.5, "Go inside the Lantern")
	if d.aborted(): return false
	d.cine_begin()
	await d.say("c2_terms_03", fenn)
	await d.say("c2_terms_04", pell)
	await d.say("c2_terms_05" if C2.flag("ruth_in_print") else "c2_terms_06", pell)
	await d.say("c2_terms_07", Game.player)
	await d.say("c2_terms_08", pell)
	await d.say("c2_terms_09", Game.player)
	await d.say("c2_terms_10", pell)
	await d.say("c2_terms_11", pell)
	await d.say("c2_terms_12", Game.player)
	await d.say("c2_terms_13", pell)
	var deal: int = await d.choose("Pell holds out a soft, clean hand for the deeds.", ["Give him the deeds.", "Keep them. Let Fenn print."])
	if deal == 0:
		await d.say("c2_terms_14", Game.player)
		await d.say("c2_terms_15", pell)
		await d.say("c2_terms_16", fenn)
		d.clear_bounty(COUNTY, price)
		if Game.state:
			Game.state.change_standing(-3.0, "gave Pell the deeds")
	else:
		await d.say("c2_terms_17", Game.player)
		await d.say("c2_terms_18", pell)
		await d.say("c2_terms_19", fenn)
		if Game.state:
			Game.state.change_standing(4.0, "kept the deeds for the Lantern")
	C2.set_flag("deeds_kept", deal == 1)
	C2.set_flag("has_deeds", deal == 1)
	d.cine_end()
	if pell:
		P.open_doors(nb, office)
		d.npc_walk_to(pell, C2.near(front, 40.0, -30.0))
	# bounty men across the street, reading the poster with their lips
	var street := C2.near(front, -30.0, 14.0)
	var hunters: Array = d.spawn_group(street, 2, {"role": "gunman", "faction": "syndicate", "name": "Bounty Man", "seed": 2510,
		"weapon": "merriman_lever", "skill": 0.45, "aggressive": false}, 2.0)
	if hunters.size() > 0:
		hunters[0].display_name = "Saul Breck"
	for h in hunters:
		d.npc_hold(h, office)
	d.cine_begin()
	await d.say("c2_terms_20", fenn)
	await d.say("c2_terms_21", Game.player)
	await d.say("c2_terms_22", fenn)
	d.cine_end()
	d.checkpoint("back_door")
	var stable := C2.near(office, 34.0, 26.0)
	var unseen: bool = await d.sneak_to(stable, 4.0, "Slip out the back to your horse", hunters)
	if d.aborted(): return false
	C2.set_flag("left_linden_quiet", unseen)
	if not unseen:
		await d.say("c2_terms_23", C2.one(hunters))
		if deal == 0:
			await d.say("c2_terms_24", C2.one(hunters))
		C2.hostile(d, hunters)
		await d.wait_dead(hunters, "Deal with the bounty men")
		if d.aborted(): return false
	d.checkpoint("ride_home")
	var camp := Mission.place("caddell_camp")
	await d.goto(camp, 12.0, "Ride home to Willow Bend")
	if d.aborted(): return false
	d.set_time(19.2)
	var hap := C2.spawn_friend(d, C2.near(camp, 2.0, 1.0), {"role": "drover", "faction": "outfit", "name": "Hap Lindqvist", "seed": 7})
	var del := C2.spawn_friend(d, C2.near(camp, -1.5, 2.2), {"role": "gambler", "faction": "outfit", "name": "Del Arceneaux", "seed": 2201})
	var billy := C2.spawn_friend(d, C2.near(camp, 0.5, -2.0), {"role": "child", "faction": "outfit", "name": "Billy Pruitt", "seed": 14})
	for h in [hap, del, billy]:
		d.npc_hold(h, camp)
	d.cine_begin()
	await d.say("c2_terms_25", hap)
	await d.say("c2_terms_26", Game.player)
	await d.say("c2_terms_27", hap)
	await d.say("c2_terms_34" if deal == 0 else "c2_terms_28", del)
	await d.say("c2_terms_29" if C2.flag("billy_trusted") else "c2_terms_30", billy)
	await d.say("c2_terms_31", Game.player)
	await d.say("c2_terms_32", Game.player)
	await d.say("c2_terms_33", hap)
	d.cine_end()
	C2.set_flag("ch2_done", true)
	return true
