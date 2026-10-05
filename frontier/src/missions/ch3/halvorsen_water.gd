extends Mission
## Chapter 3, mission 1 — Halvorsen Water. Ruth rides south to warn Ingrid Halvorsen that her south section is in
## Pell's forged deeds. Cutter Shale's men are pulling down her north windmill: ride out with Ingrid, warn them off
## (two run, Standing) or draw on Kett, then fight. Ingrid's herd must walk to the Ybarra well: take her dollar a
## head (paid on delivery in "Through the Breaks") or ask for nothing (Standing, later lines).

const C3 = preload("res://src/missions/ch3/ch3.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")

func _init() -> void:
	id = "c3_ranch"
	title = "Halvorsen Water"
	chapter = 3
	requires = ["c2_terms"]

func run(d) -> Variant:
	d.set_time(10.5)
	d.set_weather("dust")
	var ranch := Mission.place("halvorsen_ranch")
	var start := C3.road("bitter_spring", "halvorsen_ranch", 0.72)
	await C3.start_at(d, start, ranch, true)
	await d.say("c3_ranch_01", Game.player)
	d.checkpoint("road")
	await d.goto(C2.near(ranch, -10.0, -6.0), 14.0, "Ride to the Halvorsen Ranch", true)
	if d.aborted(): return false
	var ingrid := C2.spawn_friend(d, C2.near(ranch, -2.0, 0.0), {"role": "rancher", "faction": "civilian", "name": "Ingrid Halvorsen", "seed": 3101})
	d.npc_hold(ingrid, Game.player.global_position)
	d.cine_begin()
	await d.say("c3_ranch_02", ingrid)
	await d.say("c3_ranch_03", Game.player)
	await d.say("c3_ranch_04", ingrid)
	await d.say("c3_ranch_05", Game.player)
	await d.say("c3_ranch_06", ingrid)
	var teo := C2.spawn_friend(d, C2.near(ranch, 6.0, 4.0), {"role": "worker", "faction": "civilian", "name": "Teodoro Baca", "seed": 3102})
	await d.say("c3_ranch_07", teo)
	await d.say("c3_ranch_08", ingrid)
	await d.say("c3_ranch_09", Game.player)
	d.cine_end()
	d.checkpoint("ranch")
	# Ingrid rides out to the north mill; Ruth escorts her
	var mill := C3.dry(C2.near(ranch, -70.0, -150.0))
	var rider = C3.rider(d, ingrid.global_position if ingrid else ranch, {"role": "rancher", "faction": "civilian",
		"name": "Ingrid Halvorsen", "seed": 3103})
	if ingrid:
		ingrid.queue_free()
	var crew: Array = d.spawn_group(C2.near(mill, 4.0, 3.0), 4, {"role": "gunman", "faction": "syndicate", "name": "Shale Hand",
		"seed": 3110, "weapon": "lockhart_sa", "skill": 0.35, "aggressive": false}, 4.0)
	if crew.size() > 0:
		crew[0].display_name = "Amos Kett"
	for h in crew:
		d.npc_hold(h, mill)
	await d.mount_up("Mount up and ride with Ingrid")
	await d.ride_with(rider, "Ride with Ingrid to the north windmill", C2.near(mill, -14.0, 10.0), 12.0)
	if d.aborted(): return false
	var kett = C2.one(crew)
	var im = rider.man
	d.cine_begin()
	await d.say("c3_ranch_10", kett)
	await d.say("c3_ranch_11", im)
	await d.say("c3_ranch_12", kett)
	await d.say("c3_ranch_13", Game.player)
	var how: int = await d.choose("Four men, a team in harness, a chain already round the tower leg.",
		["Fire one over their heads and give them the chance to leave.", "Draw on Kett and settle it."])
	var fighters: Array = crew
	if how == 0:
		await d.say("c3_ranch_14", Game.player)
		await d.say("c3_ranch_15", kett)
		# two of them take the offer
		fighters = crew.slice(0, 2)
		for h in crew.slice(2):
			d.npc_release(h)
			h.brain.target = Game.player
			h.brain.target_last_seen = Game.player.global_position
			h.brain.state = h.brain.State.FLEE
		if Game.state:
			Game.state.change_standing(2.0, "gave Shale's men the chance to leave")
	else:
		await d.say("c3_ranch_16", Game.player)
		await d.say("c3_ranch_17", kett)
	d.cine_end()
	C3.set_flag("mill_warned", how == 0)
	C2.hostile(d, fighters)
	d.checkpoint("mill_fight")
	await d.wait_dead(fighters, "Save Ingrid's windmill")
	if d.aborted(): return false
	if im == null or not im.alive:
		d.fail("Ingrid was killed")
		return false
	rider.get_down()
	d.npc_hold(im, Game.player.global_position)
	d.dismount_player()
	d.cine_begin()
	await d.say("c3_ranch_18", im)
	await d.say("c3_ranch_19", Game.player)
	await d.say("c3_ranch_20", im)
	await d.say("c3_ranch_21", im)
	await d.say("c3_ranch_22", Game.player)
	await d.say("c3_ranch_23", im)
	var pay: int = await d.choose("Ingrid offers a dollar a head delivered — most of what she has left.",
		["Take the dollar a head.", "Keep your money. Feed my people when this is over."])
	if pay == 0:
		await d.say("c3_ranch_24", Game.player)
		await d.say("c3_ranch_25", im)
	else:
		await d.say("c3_ranch_26", Game.player)
		await d.say("c3_ranch_27", im)
		if Game.state:
			Game.state.good_deed("help_stranger")
	C3.set_flag("ingrid_pays", pay == 0)
	await d.say("c3_ranch_28", im)
	await d.say("c3_ranch_29", Game.player)
	await d.say("c3_ranch_30", teo)
	await d.say("c3_ranch_31", im)
	d.cine_end()
	C3.set_flag("ingrid_ally", true)
	return true
