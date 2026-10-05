extends Mission
## Companion — Hymns for the Crew (Hap). Hap never said the words over the three men of his crew the syndicate shot
## last summer. Ride out with him to the draw past the Halvorsen road: the syndicate has strung wire across the graves
## and left riders to mind it. Cut the wire (a fight) or let Hap sing to them through the fence while the riders
## listen. Flag hap_crew = "wire" / "sang" (Hap's camp lines change).

const ST = preload("res://src/missions/strangers/st.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")

func _init() -> void:
	id = "p_hap"
	title = "Hymns for the Crew"
	chapter = 2
	stranger = true
	companion = "hap"
	region = "Corrigan Plains"
	requires = ["c2_terms"]
	start_pos = Mission.place("caddell_camp", 3.0, 4.0)

func flags_ok() -> bool:
	return Game.state != null and Game.state.flags.get("hap_alive", true) != false

func run(d) -> Variant:
	d.set_time(16.8)
	d.set_weather("clear")
	var camp := C3.dry(Mission.place("caddell_camp", 3.0, 4.0))
	var draw := C3.dry(C3.road("bitter_spring", "halvorsen_ranch", 0.55, "halvorsen_ranch") + Vector3(90.0, 0, -70.0))
	await C3.start_at(d, C2.near(camp, -3.0, 2.0), camp, false)
	var hap := ST.person(d, camp, {"role": "drover", "faction": "outfit", "name": "Hap Lindqvist", "seed": 7})
	d.cine_begin()
	await d.say("p_hap_01", hap)
	await d.say("p_hap_02", Game.player)
	await d.say("p_hap_03", hap)
	d.cine_end()
	d.checkpoint("ride")
	if hap:
		hap.queue_free()
	var rider = C3.rider(d, C2.near(camp, 4.0, 3.0), {"role": "drover", "faction": "outfit", "name": "Hap Lindqvist", "seed": 7,
		"weapon": "harlan_carbine", "skill": 0.4, "health": 160.0}, "mustang")
	await d.mount_up("Mount up and ride out with Hap")
	if d.aborted(): return false
	rider.ride_with(Game.player, Vector3(4, 0, 3))
	await d.goto(C2.near(draw, -20.0, -14.0), 12.0, "Ride with Hap to the draw where his crew lies", true)
	if d.aborted(): return false
	rider.halt()
	d.dismount_player()
	rider.get_down()
	var h = rider.man
	d.npc_hold(h, draw)
	var guards: Array = ST.gang(d, C2.near(draw, 8.0, 6.0), 3, "Range Rider", 9601, "merriman_lever", 3.0)
	d.checkpoint("wire")
	d.cine_begin()
	await d.say("p_hap_04", h)
	await d.say("p_hap_05", C2.one(guards))
	await d.say("p_hap_06", h)
	await d.say("p_hap_07", C2.one(guards))
	var pick: int = await d.choose("Three graves behind syndicate wire, and three riders paid to mind it.",
		["Cut the wire.", "Let Hap sing to them through the fence."])
	ST.set_flag("hap_crew", "wire" if pick == 0 else "sang")
	if pick == 0:
		await d.say("p_hap_08", Game.player)
		d.cine_end()
		d.npc_release(h)
		C2.hostile(d, guards)
		await d.wait_dead(guards, "Clear the riders off Hap's crew")
		if d.aborted(): return false
		await d.interact(draw, "Cut the wire")
		if d.aborted(): return false
		d.npc_hold(h, draw)
		await d.say("p_hap_09", h)
		ST.standing(-0.5, "cut syndicate wire")
	else:
		await d.say("p_hap_10", Game.player)
		await d.say("p_hap_11", h)
		await d.say("p_hap_12", C2.one(guards))
		d.cine_end()
		await d.wait(4.0)
		ST.standing(1.0, "let a man mourn in peace")
	d.cine_begin()
	await d.say("p_hap_13", h)
	await d.say("p_hap_14", h)
	await d.say("p_hap_15", Game.player)
	d.cine_end()
	return true
