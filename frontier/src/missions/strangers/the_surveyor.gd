extends Mission
## Stranger — The Lost Surveyor (eerie, political). Boot tracks wander in circles across the Ocotillo Breaks; at the
## end of them is Linus Aldridge of the Meridian & Western, robbed of his camp by "range detectives". Creep into the
## slot canyon for his transit and field book, and read his stakes: not a railroad but the syndicate's secret water
## line to the deep wells. Give the book to Fenn, or take the railroad's thirty dollars for its return.
## Flag: field_book_to_fenn (camp talk and Fenn's paper remember it).

const ST = preload("res://src/missions/strangers/st.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")

func _init() -> void:
	id = "s_surveyor"
	title = "The Lost Surveyor"
	chapter = 3
	stranger = true
	region = "Ocotillo Breaks"
	requires = ["c3_drive"]
	start_pos = Mission.road_point("mesquite_wells", "san_lazaro", 0.3)

func run(d) -> Variant:
	d.set_time(11.0)
	d.set_weather("clear")
	var start := C3.road("mesquite_wells", "san_lazaro", 0.3, "san_lazaro")
	var lost := C3.dry(start + Vector3(-140.0, 0, 110.0))
	var canyon := C3.dry(C3.road("mesquite_wells", "san_lazaro", 0.38, "san_lazaro") + Vector3(120.0, 0, 80.0))
	await C3.start_at(d, start, lost, false)
	await d.say("s_survey_01", Game.player)
	d.checkpoint("tracks")
	await ST.trail(d, start, lost, 4, "Follow the wandering boot tracks")
	if d.aborted(): return false
	var linus := ST.person(d, C2.near(lost, 2.0, 1.5), {"role": "townsfolk", "name": "Linus Aldridge", "seed": 9901})
	if linus:
		linus.intent.crouch = true
	d.cine_begin()
	await d.say("s_survey_02", linus)
	await d.say("s_survey_03", Game.player)
	if linus:
		linus.intent.crouch = false
	await d.say("s_survey_04", linus)
	await d.say("s_survey_14", linus)
	await d.say("s_survey_15", Game.player)
	await d.say("s_survey_05", linus)
	d.cine_end()
	if Game.state and int(Game.state.inventory.get("canteen", 0)) > 0:
		Game.state.use_item("canteen")
	d.checkpoint("canyon")
	var dets: Array = ST.gang(d, C2.near(canyon, -10.0, 6.0), 3, "Range Detective", 9902, "merriman_lever", 7.0)
	for g in dets:
		d.npc_hold(g, C2.near(canyon, -60.0, 30.0))
	if Game.hud and not d.autopilot:
		Game.hud.notice("Crouch (C / B) and come at the tripod out of the detectives' sight", 5.0)
	var quiet: bool = await d.sneak_to(canyon, 3.0, "Creep into the slot canyon to Aldridge's camp", dets)
	if d.aborted(): return false
	ST.set_flag("surveyor_quiet", quiet)
	if not quiet:
		await d.say("s_survey_12", C2.one(dets))
		C2.hostile(d, dets)
		await d.wait_dead(dets, "Drive off the range detectives")
		if d.aborted(): return false
	else:
		for g in dets:
			if g and is_instance_valid(g):
				g.queue_free()
	await d.interact(canyon + Vector3(1.0, 0, 0.5), "Take the transit and the field book")
	if d.aborted(): return false
	await d.say("s_survey_06", Game.player)
	d.checkpoint("book")
	d._put_on_ground(linus, C2.near(canyon, 3.0, 2.0))
	d.npc_hold(linus, Game.player.global_position)
	d.cine_begin()
	await d.say("s_survey_13", linus)
	await d.say("s_survey_07", linus)
	var pick: int = await d.choose("A field book of stakes for a water line no map admits to.",
		["Take the field book to Fenn.", "Return it to the railroad for him."])
	ST.set_flag("field_book_to_fenn", pick == 0)
	if pick == 0:
		await d.say("s_survey_08", Game.player)
		await d.say("s_survey_09", linus)
		ST.standing(1.0, "carried the syndicate's water line to the press")
	else:
		await d.say("s_survey_10", Game.player)
		await d.say("s_survey_11", linus)
		ST.earn(30.0)
	await d.say("s_survey_16", linus)
	d.cine_end()
	ST.deed("help_stranger")
	return true
