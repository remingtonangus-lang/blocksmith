extends Mission
## Chapter 1, mission 5 — A Fire at Willow Bend. Night raid on the camp; defend Hap; a runaway boy (Billy) appears
## and saves the horses; Ruth decides to stay.

func _init() -> void:
	id = "c1_fire"
	title = "A Fire at Willow Bend"
	chapter = 1
	requires = ["c1_greer"]

func run(d) -> Variant:
	d.set_time(22.8)
	var camp := Mission.place("caddell_camp")
	await d.goto(camp, 10.0, "Return to camp at Willow Bend")
	if d.aborted(): return false
	var hap: Array = d.spawn_group(camp + Vector3(2.0, 0, 1.0), 1, {"role": "drover", "faction": "outfit", "name": "Hap Lindqvist", "seed": 7, "weapon": "harlan_carbine", "skill": 0.4}, 0.3)
	d.cine_begin()
	var h = hap[0] if hap.size() > 0 else null
	await d.say("c1_fire_01", h)
	await d.say("c1_fire_02", Game.player)
	await d.say("c1_fire_03", h)
	d.cine_end()
	var raiders: Array = d.spawn_group(camp + Vector3(-35.0, 0, -25.0), 5, {"role": "gunman", "faction": "shale", "name": "Raider", "seed": 700, "weapon": "lockhart_sa", "skill": 0.35}, 10.0)
	for r in raiders:
		r.brain.aggressive = true
	d.checkpoint("raid")
	await d.wait(2.0)
	var billy: Array = d.spawn_group(camp + Vector3(12.0, 0, 18.0), 1, {"role": "child", "faction": "civilian", "name": "Billy Pruitt", "seed": 14}, 0.3)
	await d.say("c1_fire_04", billy[0] if billy.size() > 0 else null)
	await d.say("c1_fire_05", Game.player)
	await d.say("c1_fire_06", billy[0] if billy.size() > 0 else null)
	await d.say("c1_fire_07", Game.player)
	await d.wait_dead(raiders, "Defend the camp")
	if d.aborted(): return false
	if h != null and is_instance_valid(h) and not h.alive:
		d.fail("Hap was killed")
		return false
	d.cine_begin()
	await d.say("c1_fire_08", h)
	await d.say("c1_fire_09", Game.player)
	await d.say("c1_fire_10", Game.player)
	d.cine_end()
	if Game.state:
		Game.state.flags["billy_joined"] = true
	return true
