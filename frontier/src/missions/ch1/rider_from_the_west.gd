extends Mission
## Chapter 1, mission 1 — Rider from the West. Golden hour on the river road; Ruth and her horse come into
## Bitter Spring; a newsboy hawks the syndicate's land offer; stable the horse.

func _init() -> void:
	id = "c1_rider"
	title = "Rider from the West"
	chapter = 1

func run(d) -> Variant:
	d.set_time(17.1)
	d.set_weather("fair")
	var start := Mission.road_point("bitter_spring", "mesquite_wells", 0.22)
	var ahead := Mission.road_point("bitter_spring", "mesquite_wells", 0.15)
	d.place_player(start, atan2(-(ahead.x - start.x), -(ahead.z - start.z)))
	await d.wait(1.5)
	await d.say("c1_rider_01", Game.player)
	await d.say("c1_rider_02", Game.player)
	d.checkpoint("road")
	var edge := Mission.place("bitter_spring", -150.0, 30.0)
	await d.goto(edge, 40.0, "Ride into Bitter Spring", false)
	if d.aborted(): return false
	var newsboy_pos := Mission.place("bitter_spring", -40.0, 6.0)
	var boys: Array = d.spawn_group(newsboy_pos, 1, {"role": "newsboy", "faction": "civilian", "name": "Newsboy", "seed": 410})
	await d.goto(newsboy_pos, 12.0, "Ride down the main street")
	if d.aborted(): return false
	await d.say("c1_rider_03", boys[0] if boys.size() > 0 else null)
	await d.say("c1_rider_04", Game.player)
	d.checkpoint("town")
	var stable := Mission.place("bitter_spring", 60.0, -30.0)
	var hands: Array = d.spawn_group(stable, 1, {"role": "stablehand", "faction": "civilian", "name": "Stablehand", "seed": 420}, 1.0)
	await d.interact(stable, "Stable your horse")
	if d.aborted(): return false
	await d.say("c1_rider_05", hands[0] if hands.size() > 0 else null)
	await d.say("c1_rider_06", Game.player)
	return true
