extends Mission
## Chapter 1, mission 2 — The Drover. At Willow Bend two syndicate toughs are finishing off a wounded drover.
## Ruth steps in; gunfight (Nerve introduced); patch up Hap; make camp. Standing rises if she lets them draw first.

func _init() -> void:
	id = "c1_drover"
	title = "The Drover"
	chapter = 1
	requires = ["c1_rider"]

func run(d) -> Variant:
	d.set_time(18.4)
	var camp := Mission.place("caddell_camp")
	var approach := camp + Vector3(-70.0, 0.0, 40.0)
	d.place_player(approach, atan2(-(camp.x - approach.x), -(camp.z - approach.z)))
	await d.goto(camp + Vector3(-18.0, 0, 10.0), 8.0, "Investigate the voices at Willow Bend")
	if d.aborted(): return false
	var hap: Array = d.spawn_group(camp + Vector3(2.0, 0, 0), 1, {"role": "drover", "faction": "civilian", "name": "Hap Lindqvist", "seed": 7, "health": 40.0}, 0.5)
	if hap.size() > 0:
		hap[0].brain.state = hap[0].brain.State.COWER
	var toughs: Array = d.spawn_group(camp + Vector3(6.0, 0, -3.0), 2, {"role": "gunman", "faction": "syndicate", "name": "Syndicate Man", "seed": 30, "weapon": "lockhart_sa", "skill": 0.3}, 3.0)
	d.cine_begin()
	await d.say("c1_drover_01", toughs[0] if toughs.size() > 0 else null)
	await d.say("c1_drover_02", toughs[1] if toughs.size() > 1 else null)
	await d.say("c1_drover_03", Game.player)
	await d.say("c1_drover_04", toughs[0] if toughs.size() > 0 else null)
	await d.say("c1_drover_05", Game.player)
	d.cine_end()
	d.checkpoint("standoff")
	for t in toughs:
		t.brain.aggressive = true
		t.brain.share_target(Game.player)
	if Game.hud:
		Game.hud.notice("Aim (right mouse / LT), then press Nerve (Q / R3) to slow time and mark targets", 7.0)
	await d.wait_dead(toughs, "Deal with the syndicate men")
	if d.aborted(): return false
	d.checkpoint("after_fight")
	await d.interact(camp + Vector3(2.0, 0, 0), "Tend to the wounded drover")
	if d.aborted(): return false
	var h = hap[0] if hap.size() > 0 else null
	d.cine_begin()
	await d.say("c1_drover_06", h)
	await d.say("c1_drover_07", Game.player)
	await d.say("c1_drover_08", h)
	await d.say("c1_drover_09", Game.player)
	await d.say("c1_drover_10", h)
	await d.say("c1_drover_11", Game.player)
	d.cine_end()
	return true
