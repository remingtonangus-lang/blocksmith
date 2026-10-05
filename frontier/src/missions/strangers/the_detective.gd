extends Mission
## Stranger — The Detective (moral, a turn). Hollis Crane of the Halloran National Detective Agency is hunted by
## railroad bulls and asks Ruth to get him past them to the ford below the marsh. She creeps him by (or shoots her way
## through), and at the ford he hands her to the bounty hunters he's riding with: he was the bait. After the fight he
## tells her what he is. Turn him in to Mabry, or send him back to Chicago owing her a favour. Flag: protected_crane.

const ST = preload("res://src/missions/strangers/st.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")

func _init() -> void:
	id = "s_detective"
	title = "The Detective"
	chapter = 2
	stranger = true
	region = "Lake Sable shore"
	requires = ["c2_terms"]
	start_pos = Mission.road_point("bitter_spring", "port_linden", 0.62)

func run(d) -> Variant:
	d.set_time(10.5)
	d.set_weather("overcast")
	var start := C3.road("bitter_spring", "port_linden", 0.62, "port_linden")
	var bridge := C3.road("bitter_spring", "port_linden", 0.7, "port_linden")
	var ford := C3.dry(C3.road("bitter_spring", "port_linden", 0.78, "port_linden") + Vector3(30.0, 0, -35.0))
	await C3.start_at(d, start, bridge, false)
	var crane := ST.person(d, C2.near(start, 3.0, 2.0), {"role": "townsfolk", "name": "Hollis Crane", "seed": 9601})
	d.cine_begin()
	await d.say("s_det_01", crane)
	await d.say("s_det_02", Game.player)
	await d.say("s_det_03", crane)
	await d.say("s_det_04", crane)
	await d.say("s_det_05", Game.player)
	d.cine_end()
	var bulls: Array = ST.gang(d, bridge, 3, "Railroad Bull", 9602, "harlan_carbine", 6.0)
	for b in bulls:
		d.npc_hold(b, start)
	d.checkpoint("bulls")
	if Game.hud and not d.autopilot:
		Game.hud.notice("Crouch (C / B) and keep to the reeds, out of the bulls' sight", 5.0)
	d.npc_walk_to(crane, C2.near(ford, -4.0, 3.0))
	var quiet: bool = await d.sneak_to(ford, 5.0, "Get Crane past the railroad bulls to the ford", bulls)
	if d.aborted(): return false
	ST.set_flag("crane_quiet", quiet)
	if not quiet:
		C2.hostile(d, bulls)
		await d.wait_dead(bulls, "The railroad bulls have seen you")
		if d.aborted(): return false
	d.checkpoint("ford")
	d._put_on_ground(crane, C2.near(ford, 3.0, 2.0))
	var hunters: Array = ST.gang(d, C2.near(ford, -14.0, 10.0), 3, "Bounty Hunter", 9603, "merriman_lever", 4.0)
	var moss = C2.one(hunters)
	if moss:
		moss.display_name = "Ansel Moss"
	d.npc_hold(crane, C2.near(ford, -14.0, 10.0))
	d.cine_begin()
	await d.say("s_det_06", crane)
	await d.say("s_det_07", moss)
	await d.say("s_det_08", Game.player)
	d.cine_end()
	if crane:
		d.npc_release(crane)
		crane.brain.state = crane.brain.State.COWER
	C2.hostile(d, hunters)
	d.say_async("s_det_15", moss)
	await d.wait_dead(hunters, "Crane's friends want their two hundred dollars")
	if d.aborted(): return false
	if crane == null or not is_instance_valid(crane) or not crane.alive:
		ST.set_flag("protected_crane", false)
		return true
	d.checkpoint("crane")
	d.npc_hold(crane, Game.player.global_position)
	crane.brain.state = crane.brain.State.SURRENDER
	d.cine_begin()
	await d.say("s_det_09", crane)
	await d.say("s_det_10", crane)
	var pick: int = await d.choose("Hollis Crane, detective once, bait today, on his knees in the ford.",
		["Turn him over to Sheriff Mabry.", "Let him go back to Chicago, owing you."])
	ST.set_flag("protected_crane", pick == 1)
	if pick == 0:
		await d.say("s_det_11", Game.player)
		await d.say("s_det_12", crane)
		ST.deed("bring_alive")
	else:
		await d.say("s_det_13", Game.player)
		await d.say("s_det_14", crane)
		ST.deed("spare_enemy")
		ST.earn(10.0)
	d.cine_end()
	return true
