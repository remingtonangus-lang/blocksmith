extends Mission
## Stranger — The Widow's Herd (sad). Clementine Voss lost eight head the morning she buried her husband. They
## didn't wander: Walt's partner Lyman Gage drove them off to sell before the syndicate takes the place. Ruth finds
## his camp on the plain; she can walk him back to face the widow (he stays on to work it off) or settle it with a
## gun. Either way the cattle are driven home. Flag: spared_partner (camp talk remembers it).

const ST = preload("res://src/missions/strangers/st.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")

func _init() -> void:
	id = "s_herd"
	title = "The Widow's Herd"
	chapter = 3
	stranger = true
	region = "Corrigan Plains"
	requires = ["c3_ranch"]
	start_pos = Mission.place("windmill_flats", 14.0, -10.0)

func run(d) -> Variant:
	d.set_time(8.5)
	d.set_weather("clear")
	var home := C3.dry(Mission.place("windmill_flats", 14.0, -10.0))
	var camp := C3.road("halvorsen_ranch", "windmill_flats", 0.35, "windmill_flats")
	camp = C3.dry(camp + Vector3(90.0, 0, 60.0))
	await C3.start_at(d, home + Vector3(-3.0, 0, 2.0), home, false)
	var clem := ST.person(d, home, {"role": "lady", "name": "Clementine Voss", "seed": 9201})
	d.cine_begin()
	await d.say("s_herd_01", clem)
	await d.say("s_herd_02", Game.player)
	await d.say("s_herd_03", clem)
	await d.say("s_herd_04", Game.player)
	await d.say("s_herd_05", clem)
	d.cine_end()
	d.checkpoint("trail")
	await d.mount_up("Get on your horse")
	if d.aborted(): return false
	await ST.trail(d, home, camp, 3, "Follow the cattle tracks north")
	if d.aborted(): return false
	var herd = C3.herd(d, C2.near(camp, 12.0, 6.0), 8, 9202)
	var gage := ST.person(d, camp, {"role": "drover", "name": "Lyman Gage", "seed": 9203, "weapon": "lockhart_sa", "skill": 0.4})
	var hands: Array = ST.gang(d, C2.near(camp, -6.0, 5.0), 2, "Gage's Hired Man", 9204)
	await d.goto(C2.near(camp, -10.0, -8.0), 10.0, "Ride into Gage's camp", true)
	if d.aborted(): return false
	d.checkpoint("gage")
	d.cine_begin()
	await d.say("s_herd_06", gage)
	await d.say("s_herd_07", Game.player)
	await d.say("s_herd_08", gage)
	await d.say("s_herd_09", gage)
	var pick: int = await d.choose("Lyman Gage, with Walt Voss's cattle and no paper for them.",
		["Walk him back to face her.", "Settle it here."])
	var spared := pick == 0
	ST.set_flag("spared_partner", spared)
	if spared:
		await d.say("s_herd_10", Game.player)
		d.cine_end()
		for h in hands:
			if h and is_instance_valid(h):
				d.npc_walk_to(h, C2.near(camp, -80.0, 120.0), Human.SPRINT)
	else:
		await d.say("s_herd_11", Game.player)
		d.cine_end()
		C2.hostile(d, [gage] + hands)
		await d.wait_dead([gage] + hands, "Gage and his hired men")
		if d.aborted(): return false
	d.checkpoint("drive")
	if spared and gage and is_instance_valid(gage):
		d.npc_walk_to(gage, home + Vector3(2.0, 0, 3.0))
	var head: int = await d.drive(herd, home, 25.0, "Drive Walt's cattle home", 1, 5)
	if d.aborted(): return false
	Game.log_event("herd_home", {"head": head})
	d.dismount_player()
	d.npc_hold(clem, Game.player.global_position)
	d.cine_begin()
	await d.say("s_herd_12", clem)
	if spared:
		if gage and is_instance_valid(gage):
			d._put_on_ground(gage, home + Vector3(2.0, 0, 3.0))
			d.npc_hold(gage, clem.global_position if clem else home)
		await d.say("s_herd_13", clem)
		await d.say("s_herd_14", gage)
		await d.say("s_herd_15", clem)
		ST.deed("spare_enemy")
	else:
		await d.say("s_herd_16", clem)
		await d.say("s_herd_17", Game.player)
	await d.say("s_herd_18", clem)
	d.cine_end()
	ST.deed("return_property")
	return true
