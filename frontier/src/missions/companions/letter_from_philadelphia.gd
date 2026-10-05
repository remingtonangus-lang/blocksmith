extends Mission
## Companion — The Letter from Philadelphia (Doc). The widow of the patient Doc killed fourteen years ago has written
## to forgive him. Before he can decide what that means, a wagon goes over on a teamster at Mesquite Wells: ride him
## there against the clock (late, and the man loses a leg), hold the man still while Doc works (steady_hand), and
## then tell Doc what to do with the letter. Flag doc_letter = "answered" / "burned".

const ST = preload("res://src/missions/strangers/st.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")

func _init() -> void:
	id = "p_doc"
	title = "The Letter from Philadelphia"
	chapter = 3
	stranger = true
	companion = "doc"
	region = "Mesquite Wells"
	requires = ["c3_drive"]
	needs_flags = {"doc_joined": true}
	start_pos = Mission.place("caddell_camp", -1.6, -2.8)

func run(d) -> Variant:
	d.set_time(10.0)
	d.set_weather("clear")
	var camp := C3.dry(Mission.place("caddell_camp", -1.6, -2.8))
	await C3.start_at(d, C2.near(camp, 3.0, 2.0), camp, false)
	var doc := ST.person(d, camp, {"role": "townsfolk", "faction": "outfit", "name": "Cornelius Abernathy", "seed": 3204})
	var rosa := ST.person(d, C2.near(camp, 6.0, -4.0), {"role": "lady", "name": "Rosa Ybarra", "seed": 3201})
	d.cine_begin()
	await d.say("p_doc_01", doc)
	await d.say("p_doc_02", doc)
	await d.say("p_doc_03", rosa)
	await d.say("p_doc_04", doc)
	d.cine_end()
	d.checkpoint("ride")
	await d.mount_up("Get on your horse — Doc rides double")
	if d.aborted(): return false
	var wells := C3.dry(Mission.place("mesquite_wells", -14.0, 10.0))
	var dist := Vector2(wells.x - camp.x, wells.z - camp.z).length()
	var in_time: bool = await d.timed_goto(wells, 12.0, "Ride Doc to the wells before the teamster bleeds out", dist / 11.0 + 30.0, true)
	if d.aborted(): return false
	d.dismount_player()
	d._put_on_ground(doc, C2.near(wells, 1.5, 1.0))
	var man := ST.person(d, C2.near(wells, 0.5, 2.0), {"role": "worker", "name": "Injured Teamster", "seed": 9801})
	if man:
		man.intent.crouch = true
	d.npc_hold(doc, man.global_position if man else wells)
	d.checkpoint("surgery")
	d.cine_begin()
	await d.say("p_doc_05", doc)
	await d.say("p_doc_06", man)
	await d.say("p_doc_07", doc)
	d.cine_end()
	var held: Dictionary = await d.minigame("steady_hand", {"title": "Hold him still", "seconds": 8.0, "band": 0.24, "tremor": 0.25})
	if d.aborted(): return false
	var saved: bool = in_time and held.get("ok", true)
	ST.set_flag("doc_teamster_legs", 2 if saved else 1)
	d.cine_begin()
	if saved:
		await d.say("p_doc_09", doc)
		await d.say("p_doc_10", Game.player)
		ST.deed("help_stranger")
	else:
		await d.say("p_doc_08", doc)
	await d.say("p_doc_11", doc)
	var pick: int = await d.choose("A letter of forgiveness from Philadelphia, fourteen years late, in a doctor's steady hand.",
		["Tell him to answer it.", "Tell him to burn it."])
	ST.set_flag("doc_letter", "answered" if pick == 0 else "burned")
	if pick == 0:
		await d.say("p_doc_12", Game.player)
		await d.say("p_doc_13", doc)
	else:
		await d.say("p_doc_14", Game.player)
		await d.say("p_doc_15", doc)
	d.cine_end()
	return true
