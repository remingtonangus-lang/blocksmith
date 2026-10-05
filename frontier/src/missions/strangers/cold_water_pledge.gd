extends Mission
## Stranger — The Cold Water Pledge (moral, bittersweet). Hannah Bright of the temperance league has a hatchet and
## the Silver Dollar in Coldwater in her sights. The saloon is Jack Bright's: the husband who walked out eleven years
## ago. Hand her a hatchet (his bouncer objects; the barrels go in the mud) or make her put it down and say what she
## came to say. Flag: smashed_barrels (Doc, of all people, has to hear about it).

const ST = preload("res://src/missions/strangers/st.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const C4 = preload("res://src/missions/ch4/ch4.gd")
const P = preload("res://src/missions/places.gd")

func _init() -> void:
	id = "s_pledge"
	title = "The Cold Water Pledge"
	chapter = 4
	stranger = true
	region = "Coldwater"
	requires = ["c4_coldwater"]
	start_pos = C2.spot("coldwater", 22.0, -16.0)

func _saloon() -> Dictionary:
	var b := P.building("coldwater", "saloon")
	if b.is_empty():
		b = P.building("coldwater", "hotel")
	return b

func run(d) -> Variant:
	d.set_time(19.5)
	d.set_weather("overcast")
	d.set_snow(0.2)
	var street := C2.spot("coldwater", 22.0, -16.0)
	var sb := _saloon()
	var door := P.door_out(sb, C4.town(30.0, -4.0))
	await C3.start_at(d, C2.near(street, -3.0, 2.0), street, false)
	var hannah := ST.person(d, street, {"role": "lady", "name": "Hannah Bright", "seed": 9801})
	d.cine_begin()
	await d.say("s_pledge_01", hannah)
	await d.say("s_pledge_02", Game.player)
	await d.say("s_pledge_03", hannah)
	await d.say("s_pledge_04", hannah)
	d.cine_end()
	d.npc_walk_to(hannah, C2.near(door, 1.5, 1.0))
	d.say_async("s_pledge_15", hannah)
	await d.goto(door, 3.5, "Walk Hannah to the Silver Dollar")
	if d.aborted(): return false
	d.checkpoint("saloon")
	P.open_doors(sb, door)
	var bar := P.at(P.spot(sb, "bartender"), P.inside(sb, 0.6, C2.near(door, 4.0, 3.0)))
	var floor_pt := P.inside(sb, 0.35, C2.near(door, 2.0, 2.0))
	d._teleport_player(floor_pt)
	d._put_on_ground(hannah, floor_pt + Vector3(1.0, 0, 0.6))
	var jack := ST.person(d, bar, {"role": "bartender", "name": "Jack Bright", "seed": 9802}, floor_pt)
	var house: Array = ST.gang(d, P.inside(sb, 0.5, C2.near(door, 3.0, 4.0), 2.0), 2, "Silver Dollar Bouncer", 9803, "lockhart_sa", 1.5)
	var bouncer = C2.one(house)
	d.npc_hold(hannah, jack.global_position if jack else bar)
	d.cine_begin()
	await d.say("s_pledge_05", jack)
	await d.say("s_pledge_06", hannah)
	await d.say("s_pledge_07", bouncer)
	await d.say("s_pledge_08", jack)
	var pick: int = await d.choose("Hannah Bright with a hatchet, Jack Bright behind his bar, eleven years between them.",
		["Hand me a hatchet, Mrs. Bright.", "Put the hatchet down. Say what you came to say."])
	var smashed := pick == 0
	ST.set_flag("smashed_barrels", smashed)
	if smashed:
		await d.say("s_pledge_09", Game.player)
		d.cine_end()
		if jack:
			d.npc_release(jack)
			jack.brain.state = jack.brain.State.COWER
		if hannah:
			d.npc_release(hannah)
			hannah.brain.state = hannah.brain.State.COWER
		C2.hostile(d, house)
		await d.wait_dead(house, "The bouncers object")
		if d.aborted(): return false
		d.checkpoint("barrels")
		for i in 3:
			var bp := P.inside(sb, 0.75, C2.near(door, 5.0 + i, 4.0), -1.5 + 1.5 * i)
			await d.interact(bp, "Stave in the whiskey barrel (%d/3)" % (i + 1))
			if d.aborted(): return false
			Game.noise.emit(bp, 25.0, Game.player)
		d.npc_hold(hannah, Game.player.global_position)
		d.npc_hold(jack, Game.player.global_position)
		d.cine_begin()
		await d.say("s_pledge_10", hannah)
		await d.say("s_pledge_11", jack)
		d.cine_end()
	else:
		await d.say("s_pledge_12", Game.player)
		await d.say("s_pledge_13", hannah)
		await d.say("s_pledge_14", jack)
		await d.say("s_pledge_16", jack)
		d.cine_end()
		ST.deed("help_stranger")
	return true
