extends Mission
## Companion — Two Rivers (Joseph). A cavalry captain Joseph scouted for in 1890 wants him to find a Lakota family
## that left the agency for the winter hunting ground. Joseph goes, because better him than the captain's other
## scouts: track them up the north fork, find them cold and hungry, give them meat. Then the captain: Ruth lies to
## him for Joseph, or lets Joseph refuse him to his face — whether the fight is his. Flag joseph_trail = "false" /
## "refused" (Joseph's camp lines change).

const ST = preload("res://src/missions/strangers/st.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const C4 = preload("res://src/missions/ch4/ch4.gd")

func _init() -> void:
	id = "p_joseph"
	title = "Two Rivers"
	chapter = 4
	stranger = true
	companion = "joseph"
	region = "Kestrel Range"
	requires = ["c4_strike"]
	needs_flags = {"joseph_joined": true}
	start_pos = C4.town(-30.0, 12.0)

func flags_ok() -> bool:
	return super.flags_ok() and Game.state.flags.get("joseph_left", false) != true

func run(d) -> Variant:
	d.set_time(9.5)
	d.set_weather("overcast")
	d.set_snow(0.3)
	var livery := C4.town(-30.0, 12.0)
	await C3.start_at(d, C2.near(livery, -3.0, 2.0), livery, false)
	var joseph := ST.person(d, livery, {"role": "hunter", "faction": "outfit", "name": "Joseph Kehoe", "seed": 4101, "weapon": "bowden_bolt"})
	var thorne := ST.person(d, C2.near(livery, 4.0, -2.0), {"role": "lawman", "faction": "law", "name": "Captain Thorne", "seed": 9951})
	d.cine_begin()
	await d.say("p_joseph_01", joseph)
	await d.say("p_joseph_02", thorne)
	await d.say("p_joseph_03", joseph)
	await d.say("p_joseph_04", joseph)
	d.cine_end()
	d.checkpoint("tracks")
	var camp := C3.dry(Mission.place("trapper_cabin_n", 160.0, -140.0))
	var start := C3.dry(livery.lerp(camp, 0.55))
	await d.mount_up("Ride north with Joseph")
	if d.aborted(): return false
	await d.goto(start, 14.0, "Ride up toward the north fork", true)
	if d.aborted(): return false
	d.dismount_player()
	d._put_on_ground(joseph, C2.near(start, 2.0, 2.0))
	await d.say("p_joseph_05", joseph)
	d.npc_walk_to(joseph, C2.near(camp, -4.0, 3.0))
	await ST.trail(d, start, camp, 4, "Follow the travois tracks up the north fork")
	if d.aborted(): return false
	var elder := ST.person(d, camp, {"role": "elder", "name": "Old Man", "seed": 9952})
	var mother := ST.person(d, C2.near(camp, 2.0, 1.5), {"role": "woman", "name": "Young Mother", "seed": 9953})
	var kid := ST.person(d, C2.near(camp, 2.6, 2.4), {"role": "child", "name": "Boy", "seed": 9954})
	d._put_on_ground(joseph, C2.near(camp, -3.0, 2.0))
	d.npc_hold(joseph, camp)
	d.checkpoint("family")
	d.cine_begin()
	await d.say("p_joseph_06", elder)
	await d.say("p_joseph_07", mother)
	await d.say("p_joseph_08", joseph)
	d.cine_end()
	if Game.state and int(Game.state.inventory.get("jerky", 0)) > 0:
		Game.state.use_item("jerky")
	ST.deed("help_stranger")
	# back down to the captain
	await d.goto(C2.near(livery, 6.0, -4.0), 12.0, "Ride back down to Captain Thorne", false)
	if d.aborted(): return false
	d._put_on_ground(thorne, C2.near(livery, 4.0, -2.0))
	d._put_on_ground(joseph, C2.near(livery, 7.0, -2.0))
	d.npc_hold(thorne, Game.player.global_position)
	d.npc_hold(joseph, thorne.global_position if thorne else livery)
	for h in [elder, mother, kid]:
		if h and is_instance_valid(h):
			h.queue_free()
	d.cine_begin()
	var pick: int = await d.choose("Captain Thorne waiting at the livery for an answer, and Joseph saying nothing at all.",
		["Lie to the captain for him.", "Let Joseph answer the captain himself."])
	ST.set_flag("joseph_trail", "false" if pick == 0 else "refused")
	if pick == 0:
		await d.say("p_joseph_09", Game.player)
		await d.say("p_joseph_10", thorne)
	else:
		await d.say("p_joseph_11", Game.player)
		await d.say("p_joseph_12", joseph)
		await d.say("p_joseph_13", thorne)
		await d.say("p_joseph_14", joseph)
		await d.say("p_joseph_15", joseph)
	d.cine_end()
	return true
