extends Mission
## Chapter 2, mission 2 — A Gentleman's Game. The back table at the Corinthian: Pell's clerk Lyle Hask, old Josiah
## Merrow, the cardsharp Del Arceneaux and a house dealer, Abel Stroud, who stacks the deck for Hask. Five-card draw
## (src/minigames/poker.gd); Ruth can catch the cold deck at the table ("Call the deal") or name the tell after.
## Taking Del's advice highlights the tells. Stroud and his floorman draw; Del fights at Ruth's side and joins the
## Outfit. Choice: give every player back his stake (Standing) or take the table money.

const C2 = preload("res://src/missions/ch2/ch2.gd")

const P = preload("res://src/missions/places.gd")

func _init() -> void:
	id = "c2_cards"
	title = "A Gentleman's Game"
	chapter = 2
	requires = ["c2_lantern"]

func run(d) -> Variant:
	d.set_time(21.2)
	var saloon_fb := C2.spot("port_linden", -38.0, 12.0)
	var sb := P.building("port_linden", "saloon")
	var saloon := P.inside(sb, 0.5, saloon_fb)
	await d.goto(P.door_out(sb, saloon_fb), 4.0, "Go to the Corinthian saloon")
	if d.aborted(): return false
	await d.say("c2_cards_01", Game.player)
	var chairs := P.table_chairs(sb, 4)
	var table := P.inside(sb, 0.6, C2.near(saloon_fb, -3.0, 2.0))
	if chairs.size() > 0 and chairs[0].has("table"):
		table = chairs[0].table
	var seat := func(i: int, fb: Vector3) -> Vector3:
		return chairs[i].transform.origin if i < chairs.size() else fb
	var del: Human = d.spawn_at(seat.call(0, C2.near(table, 1.6, 0.4)), {"role": "gambler", "faction": "outfit", "name": "Del Arceneaux",
		"seed": 2201, "weapon": "lockhart_sa", "skill": 0.65, "health": 160.0}, table)
	var stroud: Human = d.spawn_at(seat.call(1, C2.near(table, 0.0, -1.4)), {"role": "gambler", "faction": "syndicate", "name": "Abel Stroud",
		"seed": 2202, "weapon": "lockhart_sa", "skill": 0.5, "aggressive": false}, table)
	var hask: Human = d.spawn_at(seat.call(2, C2.near(table, -1.5, 0.3)), {"role": "townsfolk", "faction": "civilian", "name": "Lyle Hask", "seed": 2203}, table)
	var merrow: Human = d.spawn_at(seat.call(3, C2.near(table, 0.2, 1.6)), {"role": "townsfolk", "faction": "civilian", "name": "Josiah Merrow", "seed": 2204}, table)
	var bt := P.spot(sb, "bartender")
	var floyd: Human = d.spawn_at(P.at(bt, C2.near(saloon_fb, 3.0, -3.0)), {"role": "bartender", "faction": "syndicate", "name": "Floyd Gentry",
		"seed": 2205, "weapon": "harlan_carbine", "skill": 0.4, "aggressive": false}, P.look(bt, table))
	for h in [del, stroud, hask, merrow]:
		d.npc_hold(h, table)
	d.npc_hold(floyd, table)
	await d.interact(table, "Take a seat at the back table")
	if d.aborted(): return false
	d.cine_begin()
	await d.say("c2_cards_02", del)
	await d.say("c2_cards_03", Game.player)
	await d.say("c2_cards_04", del)
	await d.say("c2_cards_05", del)
	await d.say("c2_cards_06", del)
	var listen: int = await d.choose("The cardsharp seems to want an ally. Or a mark.", ["Why tell me?", "I'll mind my own cards."])
	if listen == 0:
		await d.say("c2_cards_07", Game.player)
		await d.say("c2_cards_08", del)
	else:
		await d.say("c2_cards_09", Game.player)
		await d.say("c2_cards_10", del)
	C2.set_flag("del_hint", listen == 0)
	await d.say("c2_cards_11", stroud)
	await d.say("c2_cards_12", merrow)
	d.cine_end()
	d.checkpoint("table")
	if C2.money() < 5.0 and Game.hud:
		Game.hud.notice("Fenn's five dollars will cover your stake", 4.0)
	var res: Dictionary = await d.minigame("poker", {
		"players": [{"name": "Del Arceneaux", "style": "bluffer", "stack": 14.0},
			{"name": "Lyle Hask", "style": "plant", "stack": 25.0},
			{"name": "Josiah Merrow", "style": "tight", "stack": 18.0}],
		"buyin": 10.0, "stake": 5.0, "hands": 8, "seed": 1899 + 22, "rig_hands": [3, 6], "plant": 2, "mark": 0,
		"dealer": "Abel Stroud", "hint": listen == 0, "can_leave": true})
	if d.aborted(): return false
	var caught: bool = res.get("caught", false)
	d.checkpoint("cards_done")
	d.cine_begin()
	if caught:
		await d.say("c2_cards_13", Game.player)
		await d.say("c2_cards_14", stroud)
		await d.say("c2_cards_15", del)
	else:
		var tell: int = await d.choose("Something in Stroud's dealing sat wrong with you.",
			["He squares the deck twice before Hask's big hands.", "He deals too fast to follow.", "Let it go."])
		if tell == 0:
			caught = true
			await d.say("c2_cards_16", Game.player)
			await d.say("c2_cards_14", stroud)
			await d.say("c2_cards_15", del)
		elif tell == 1:
			await d.say("c2_cards_17", Game.player)
			await d.say("c2_cards_18", stroud)
			await d.say("c2_cards_19", del)
		else:
			await d.say("c2_cards_20", del)
	C2.set_flag("cheat_caught", caught)
	if Game.state:
		if caught:
			Game.state.change_standing(2.0, "exposed a crooked dealer")
		elif not caught and res.get("false_accusations", 0) == 0:
			Game.state.change_standing(-1.0, "let a cheat run")
	await d.say("c2_cards_21", stroud)
	d.cine_end()
	# Stroud and his floorman draw; Del answers; Hask and Merrow get under the table
	for h in [hask, merrow]:
		if h:
			d.npc_release(h)
			h.brain.state = h.brain.State.COWER
	d.npc_release(del)
	var house: Array = [stroud, floyd].filter(func(h): return h != null)
	C2.hostile(d, house)
	d.checkpoint("house_fight")
	await d.wait_dead(house, "Survive the house")
	if d.aborted(): return false
	if del == null or not del.alive:
		d.fail("Del was killed")
		return false
	d.npc_hold(del, Game.player.global_position)
	if hask:
		d.npc_hold(hask, Game.player.global_position)
	d.cine_begin()
	await d.say("c2_cards_22", hask)
	await d.say("c2_cards_23", Game.player)
	await d.say("c2_cards_24", hask)
	await d.say("c2_cards_25", del)
	var pot: int = await d.choose("The money's still on the felt. Every stake from a crooked night.",
		["Give every player back his stake.", "Take the table money."])
	if pot == 0:
		await d.say("c2_cards_26", Game.player)
		await d.say("c2_cards_27", merrow)
		if Game.state:
			Game.state.good_deed("return_property")
		C2.set_flag("returned_stakes", true)
	else:
		await d.say("c2_cards_28", Game.player)
		await d.say("c2_cards_29", del)
		if Game.state:
			Game.state.add_money(12.0)
			Game.state.change_standing(-3.0, "kept a crooked pot")
		C2.set_flag("returned_stakes", false)
	await d.say("c2_cards_30", del)
	await d.say("c2_cards_31", Game.player)
	await d.say("c2_cards_32", del)
	await d.say("c2_cards_33", Game.player)
	await d.say("c2_cards_34", del)
	await d.say("c2_cards_35", Game.player)
	d.cine_end()
	if hask:
		d.npc_release(hask)
		hask.brain.target = Game.player
		hask.brain.target_last_seen = Game.player.global_position
		hask.brain.state = hask.brain.State.FLEE
	C2.set_flag("del_joined", true)
	return true
