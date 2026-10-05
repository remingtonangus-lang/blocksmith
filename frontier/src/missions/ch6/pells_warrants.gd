extends Mission
## Chapter 6, mission 1 — Pell's Warrants. Pell's counterstroke: Eben rides at dawn on Willow Bend with Pell's
## warrants and Ashby's men. If Ruth spared Asa in the snow, the boy comes back first to warn her (the raid is
## smaller and the Outfit is ready). Stand and hold the camp (defend) or scatter the Outfit and draw the riders off
## (a horseback getaway). Eben names the place: San Lazaro.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const C6 = preload("res://src/missions/ch6/ch6.gd")

func _init() -> void:
	id = "c6_warrants"
	title = "Pell's Warrants"
	chapter = 6
	requires = ["c5_owe"]

func run(d) -> Variant:
	d.set_time(5.4)
	d.set_weather("fog")
	var camp := Mission.place("caddell_camp")
	await C3.start_at(d, C2.near(camp, -4.0, 3.0), camp, false)
	var crew: Dictionary = C6.spawn_outfit(d, camp, true)
	var warned := false
	if C3.flag("spared_asa", false):
		var asa: Human = C2.spawn_friend(d, C2.near(camp, -40.0, 25.0), {"role": "gunman", "faction": "civilian", "name": "Asa Shale", "seed": 4130})
		d.npc_hold(asa, camp)
		await d.goto(C2.near(asa.global_position, 3.0, 0.0), 4.0, "A rider in the fog. Go and see")
		if d.aborted(): return false
		d.cine_begin()
		await d.say("c6_war_01", asa)
		await d.say("c6_war_02", Game.player)
		await d.say("c6_war_03", asa)
		await d.say("c6_war_04", Game.player)
		await d.say("c6_war_05", asa)
		d.cine_end()
		C3.set_flag("asa_warned", true)
		warned = true
		asa.queue_free()
	d.checkpoint("dawn")
	var n := 4 if warned else 7
	var riders: Array = d.spawn_group(C2.near(camp, -70.0, -50.0), n, {"role": "gunman", "faction": "syndicate", "name": "Ashby's Rider",
		"seed": 6110, "weapon": "merriman_lever", "skill": 0.4 if warned else 0.5, "aggressive": false}, 8.0)
	var billy = crew.get("billy")
	await d.say("c6_war_06", billy)
	await d.say("c6_war_07", Game.player)
	var how: int = await d.choose("Pell's riders coming out of the fog with a sheriff's star in front.",
		["Stand and hold the camp.", "Scatter the Outfit and draw them off."])
	C3.set_flag("camp_stand", how == 0)
	if how == 0:
		await d.say("c6_war_08", Game.player)
		for id in crew.keys():
			d.npc_release(crew[id])
		for r in riders:
			d.npc_walk_to(r, camp, Human.JOG)
		C2.hostile(d, riders)
		var held: bool = await d.defend(camp, 6.0, riders, "Hold the camp", 8.0)
		if d.aborted(): return false
		C3.set_flag("camp_held", held)
		if not held:
			await d.say("c6_war_14", Game.player)
	else:
		await d.say("c6_war_09", Game.player)
		for id in crew.keys():
			if is_instance_valid(crew[id]):
				crew[id].queue_free()
		await d.say("c6_war_10", billy if is_instance_valid(billy) else null)
		await d.say("c6_war_11", Game.player)
		C2.hostile(d, riders)
		await d.mount_up("Get on your horse and draw them off")
		await d.escape(camp, 260.0, "Draw the riders away from the Outfit", 60.0)
		if d.aborted(): return false
	d.checkpoint("invitation")
	await d.say("c6_war_12", null)
	var doc = crew.get("doc")
	await d.say("c6_war_13", doc if is_instance_valid(doc) else null)
	for r in riders:
		if is_instance_valid(r):
			r.queue_free()
	return true
