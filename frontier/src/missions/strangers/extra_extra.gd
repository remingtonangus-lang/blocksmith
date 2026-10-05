extends Mission
## Stranger — Extra, Extra (comic, warm). Pip Callahan sells the Lantern outside the press and owes Mick Rourke
## for a hundred rained-on papers by sundown. Ride a bundle to the stage stop at Greer's Post before four o'clock (a
## timed ride: late pays half), then face Rourke: pay the boy's debt, or tell Rourke it's forgiven and back it up.
## Flag: paid_pip_debt (Billy is jealous of him either way).

const ST = preload("res://src/missions/strangers/st.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const P = preload("res://src/missions/places.gd")

func _init() -> void:
	id = "s_newsboy"
	title = "Extra, Extra"
	chapter = 2
	stranger = true
	region = "Port Linden"
	requires = ["c2_lantern"]
	start_pos = C2.spot("port_linden", -18.0, 26.0)

func run(d) -> Variant:
	d.set_time(14.6)
	d.set_weather("clear")
	var press := P.door_out(P.building("port_linden", "newspaper"), C2.spot("port_linden", -18.0, 26.0))
	await C3.start_at(d, C2.near(press, -3.0, 2.0), press, false)
	var pip := ST.person(d, C2.near(press, 1.5, 1.5), {"role": "child", "name": "Pip Callahan", "seed": 9701})
	d.cine_begin()
	await d.say("s_news_01", pip)
	await d.say("s_news_02", Game.player)
	await d.say("s_news_03", pip)
	await d.say("s_news_04", pip)
	d.cine_end()
	d.checkpoint("ride")
	d.say_async("s_news_15", pip)
	await d.mount_up("Get on your horse — the bundle's tied behind the saddle")
	if d.aborted(): return false
	var stop := C3.dry(Mission.place("greer_post", 12.0, -8.0))
	var dist := Vector2(stop.x - press.x, stop.z - press.z).length()
	var in_time: bool = await d.timed_goto(stop, 10.0, "Ride the bundle to the stage stop at Greer's Post before four", dist / 10.5 + 25.0, true)
	if d.aborted(): return false
	ST.set_flag("pip_bundle_in_time", in_time)
	var agent := ST.person(d, C2.near(stop, 3.0, 1.0), {"role": "shopkeeper", "name": "Station Agent", "seed": 9702})
	if in_time:
		await d.say("s_news_05", agent)
		ST.earn(2.0)
	else:
		await d.say("s_news_06", agent)
		ST.earn(1.0)
	d.checkpoint("rourke")
	await d.goto(C2.near(press, -6.0, 4.0), 12.0, "Ride back to Pip at the press", true)
	if d.aborted(): return false
	d.dismount_player()
	d._put_on_ground(pip, C2.near(press, 1.5, 1.5))
	var toughs: Array = ST.gang(d, C2.near(press, 6.0, -5.0), 3, "Rourke's Tough", 9703, "lockhart_sa", 2.5)
	var rourke = C2.one(toughs)
	if rourke:
		rourke.display_name = "Mick Rourke"
	d.npc_hold(pip, Game.player.global_position)
	d.cine_begin()
	await d.say("s_news_07", rourke)
	var pick: int = await d.choose("Mick Rourke wants six dollars off a boy of eleven by sundown.",
		["Pay the boy's debt yourself.", "Tell Rourke the debt's forgiven."])
	ST.set_flag("paid_pip_debt", pick == 0)
	if pick == 0:
		await d.say("s_news_08", Game.player)
		ST.pay(6.0)
		await d.say("s_news_09", rourke)
		d.cine_end()
		for t in toughs:
			if t and is_instance_valid(t):
				d.npc_walk_to(t, C2.near(press, 60.0, -40.0))
	else:
		await d.say("s_news_10", Game.player)
		await d.say("s_news_11", rourke)
		d.cine_end()
		if pip:
			d.npc_release(pip)
			pip.brain.state = pip.brain.State.COWER
		C2.hostile(d, toughs)
		await d.wait_dead(toughs, "Rourke and his toughs")
		if d.aborted(): return false
		ST.standing(-0.5, "a street fight in Port Linden")
		await d.say("s_news_16", Game.player)
	d.npc_hold(pip, Game.player.global_position)
	d.cine_begin()
	await d.say("s_news_12", pip)
	await d.say("s_news_13", Game.player)
	await d.say("s_news_14", pip)
	d.cine_end()
	ST.deed("help_stranger")
	return true
