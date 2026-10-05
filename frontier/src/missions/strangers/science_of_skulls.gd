extends Mission
## Stranger — The Science of Skulls (comic, moral). Dr. Horatio Bundy reads the bumps of the head in the Mesquite
## Wells plaza, and took Ramon Ortiz's seed money to "invest" it. He offers to settle it like a gentleman, at cards,
## dealing himself. Catch the mirror ring (or see it after), then make him pay the farmer back and leave — or take
## half his purse and let him go on reading heads. Flag: took_cut (Doc has opinions).

const ST = preload("res://src/missions/strangers/st.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")

func _init() -> void:
	id = "s_skulls"
	title = "The Science of Skulls"
	chapter = 3
	stranger = true
	region = "Mesquite Wells"
	requires = ["c3_doc"]
	start_pos = Mission.place("mesquite_wells", 10.0, 18.0)

func run(d) -> Variant:
	d.set_time(17.0)
	d.set_weather("clear")
	var plaza := C3.dry(Mission.place("mesquite_wells", 10.0, 18.0))
	await C3.start_at(d, C2.near(plaza, -4.0, 2.0), plaza, false)
	var bundy := ST.person(d, plaza, {"role": "townsfolk", "name": "Dr. Horatio Bundy", "seed": 9401})
	var ortiz := ST.person(d, C2.near(plaza, 2.5, 3.0), {"role": "rancher", "name": "Ramon Ortiz", "seed": 9402})
	d.cine_begin()
	await d.say("s_skull_01", bundy)
	await d.say("s_skull_02", Game.player)
	await d.say("s_skull_03", bundy)
	await d.say("s_skull_04", ortiz)
	await d.say("s_skull_05", bundy)
	d.cine_end()
	d.checkpoint("cards")
	var res: Dictionary = await d.minigame("poker", {
		"players": [{"name": "Dr. Horatio Bundy", "style": "plant", "stack": 30.0},
			{"name": "Ramon Ortiz", "style": "tight", "stack": 6.0},
			{"name": "Teamster", "style": "loose", "stack": 12.0}],
		"buyin": 0.0, "stake": 5.0, "hands": 6, "seed": 9403, "rig_hands": [2, 4], "plant": 1, "mark": 0,
		"dealer": "Dr. Horatio Bundy", "hint": false, "can_leave": true})
	if d.aborted(): return false
	var caught: bool = res.get("caught", false)
	ST.set_flag("bundy_caught_at_table", caught)
	d.checkpoint("reckoning")
	d.cine_begin()
	if caught:
		await d.say("s_skull_06", Game.player)
		await d.say("s_skull_07", bundy)
	else:
		await d.say("s_skull_08", Game.player)
		await d.say("s_skull_09", bundy)
	await d.say("s_skull_10", ortiz)
	var pick: int = await d.choose("A phrenologist with a mirror ring and a farmer's seed money.",
		["Make him pay Mr. Ortiz back and leave town.", "Take half his purse and let him go on reading heads."])
	ST.set_flag("took_cut", pick == 1)
	if pick == 0:
		await d.say("s_skull_11", Game.player)
		await d.say("s_skull_12", bundy)
		await d.say("s_skull_13", ortiz)
		ST.deed("return_property")
		if bundy:
			d.npc_walk_to(bundy, C2.near(plaza, -90.0, 60.0))
	else:
		await d.say("s_skull_14", Game.player)
		await d.say("s_skull_15", bundy)
		await d.say("s_skull_16", ortiz)
		ST.earn(15.0)
		ST.standing(-2.0, "split a swindler's take")
	d.cine_end()
	return true
