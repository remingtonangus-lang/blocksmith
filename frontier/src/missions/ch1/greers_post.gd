extends Mission
## Chapter 1, mission 4 — Greer's Post. Buy the Shales' whereabouts from Tobias Greer; ride into the ambush he sold
## you; one survivor (spare him: Standing up, he carries the message to Cutter Shale).

const P = preload("res://src/missions/places.gd")

func _init() -> void:
	id = "c1_greer"
	title = "Greer's Post"
	chapter = 1
	requires = ["c1_inquiries"]

func run(d) -> Variant:
	d.set_time(10.0)
	var post := Mission.place("greer_post")
	await d.goto(post, 10.0, "Ride to Greer's trading post")
	if d.aborted(): return false
	var gb := P.building("greer_post", "trading_post")
	var keeper := P.spot(gb, "shopkeeper")
	var g: Array = [d.spawn_at(P.at(keeper, post + Vector3(3.0, 0, 0)), {"role": "shopkeeper", "faction": "civilian", "name": "Tobias Greer", "seed": 601}, P.look(keeper, post))]
	await d.interact(P.at(P.spot(gb, "shop_counter"), post + Vector3(3.0, 0, 0)), "Talk to Greer")
	if d.aborted(): return false
	d.cine_begin()
	var gr = g[0] if g.size() > 0 else null
	for id in ["c1_greer_01", "c1_greer_02", "c1_greer_03", "c1_greer_04", "c1_greer_05"]:
		await d.say(id, Game.player if id in ["c1_greer_02", "c1_greer_04"] else gr)
	d.cine_end()
	if Game.state:
		Game.state.add_money(-5.0)
	d.checkpoint("bought")
	var road := Mission.road_point("bitter_spring", "greer_post", 0.5)
	await d.goto(road, 25.0, "Head back toward Bitter Spring")
	if d.aborted(): return false
	var riders: Array = d.spawn_group(road + Vector3(30.0, 0, -18.0), 4, {"role": "gunman", "faction": "shale", "name": "Shale Rider", "seed": 610, "weapon": "merriman_lever", "skill": 0.4}, 8.0)
	await d.say("c1_greer_06", riders[0] if riders.size() > 0 else null)
	await d.say("c1_greer_07", Game.player)
	# the youngest breaks and surrenders when his friends fall
	var kid: Human = riders[-1] if riders.size() > 0 else null
	if kid:
		kid.brain.bravery = 0.0
	await d.wait_dead(riders.slice(0, riders.size() - 1), "Survive the ambush")
	if d.aborted(): return false
	if kid and is_instance_valid(kid) and kid.alive:
		kid.brain.state = kid.brain.State.SURRENDER
		await d.say("c1_greer_08", kid)
		await d.say("c1_greer_09", Game.player)
		if Game.state:
			Game.state.good_deed("spare_enemy")
			Game.state.flags["spared_greer_kid"] = true
		kid.brain.state = kid.brain.State.FLEE
	return true
