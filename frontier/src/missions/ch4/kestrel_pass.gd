extends Mission
## Chapter 4, mission 3 — The Kestrel Pass. Joseph takes Ruth straight up the face to get ahead of Asa: climb hold
## by hold in a snowstorm with the cold eating at her (warmth drains above the snow line and in the storm; a herder's
## shack fire halfway). At the pass Asa's men open fire under a hanging cornice and bring the slope down: run for the
## rocks before the slide (buried = retry). Joseph is half-buried: dig him out (Standing, his trust) or go after
## Asa while the tracks last.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const C4 = preload("res://src/missions/ch4/ch4.gd")

func _init() -> void:
	id = "c4_pass"
	title = "The Kestrel Pass"
	chapter = 4
	requires = ["c4_mine"]

func run(d) -> Variant:
	d.set_time(14.8)
	d.set_weather("storm")
	d.set_snow(0.55)
	var foot := C4.at(C4.FACE_FOOT)
	var top := C4.at(C4.PASS)
	await C3.start_at(d, C2.near(foot, -8.0, 6.0), top, false)
	var joseph := C2.spawn_friend(d, C2.near(foot, -4.0, 4.0), {"role": "hunter", "faction": "outfit", "name": "Joseph Kehoe", "seed": 4101,
		"weapon": "bowden_bolt", "skill": 0.7})
	d.npc_hold(joseph, top)
	d.cine_begin()
	await d.say("c4_pass_01", joseph)
	await d.say("c4_pass_02", Game.player)
	await d.say("c4_pass_03", joseph)
	d.cine_end()
	d.cold_begin(1.5)
	d.checkpoint("face")
	var mid := C4.at(foot.lerp(top, 0.5))
	var shack := C2.near(mid, 6.0, 0.0)
	var fire: Node3D = d.warm_spot(shack)
	await d.climb(C4.holds(foot, mid, 4), "Climb the face")
	if d.aborted(): return false
	d.npc_hold(joseph, shack)
	joseph.global_position = C2.near(shack, 2.0, 1.5)
	await d.say("c4_pass_04", joseph)
	await d.goto(fire.global_position, 3.0, "Get to the herder's shack fire")
	if d.aborted(): return false
	d.cine_begin()
	await d.say("c4_pass_24", joseph)
	await d.say("c4_pass_05", Game.player)
	await d.say("c4_pass_25", Game.player)
	d.cine_end()
	d.checkpoint("shack")
	await d.climb(C4.holds(mid, top, 4), "Climb to the pass")
	if d.aborted(): return false
	joseph.global_position = C2.near(top, -3.0, 4.0)
	d.npc_hold(joseph, top + Vector3(200, 0, 0))
	d.checkpoint("pass_top")
	await d.say("c4_pass_06", joseph)
	var string: Array = d.spawn_group(C2.near(top, 90.0, 40.0), 3, {"role": "gunman", "faction": "syndicate", "name": "Shale Rider",
		"seed": 4310, "weapon": "merriman_lever", "skill": 0.3, "aggressive": false}, 6.0)
	if string.size() > 0:
		string[0].display_name = "Asa Shale"
	for s in string:
		d.npc_hold(s, top)
	await d.say("c4_pass_07", C2.one(string))
	Game.noise.emit(top, 200.0, C2.one(string))
	await d.say("c4_pass_08", joseph)
	await d.say("c4_pass_09", joseph)
	# the cornice lets go above the pass: the slide comes down from the north; the rocks are to the west
	var safe := C4.at(top + Vector3(-48.0, 0, 6.0))
	await d.avalanche(top + Vector3(0, 0, -170.0), Vector3(0, 0, 1), safe, 11.0, "Run for the rocks")
	if d.aborted(): return false
	for s in string:
		if is_instance_valid(s):
			s.queue_free()
	d.checkpoint("after_slide")
	joseph.global_position = C2.near(top, 0.0, 22.0)
	d.npc_hold(joseph, safe)
	joseph.brain.state = joseph.brain.State.COWER
	joseph.intent.crouch = true
	d.warm_spot(C2.near(safe, 3.0, 2.0))
	await d.say("c4_pass_10", Game.player)
	await d.goto(joseph.global_position, 3.0, "Find Joseph in the slide")
	if d.aborted(): return false
	d.cine_begin()
	await d.say("c4_pass_11", joseph)
	await d.say("c4_pass_12", Game.player)
	await d.say("c4_pass_13", joseph)
	var dig: int = await d.choose("Joseph, buried to the chest, telling you to go. Asa's tracks filling with snow.",
		["Dig Joseph out first.", "Go after Asa while the trail's warm."])
	C3.set_flag("left_joseph", dig == 1)
	if dig == 0:
		d.cine_end()
		var holes := [C2.near(joseph.global_position, 1.2, 0.0), C2.near(joseph.global_position, -1.2, 0.5)]
		await d.timed_tasks(holes, "Dig Joseph out", 60.0, "Dig")
		if d.aborted(): return false
		d.cine_begin()
		await d.say("c4_pass_14", joseph)
		await d.say("c4_pass_15", Game.player)
		await d.say("c4_pass_16", joseph)
		await d.say("c4_pass_17", joseph)
		if Game.state:
			Game.state.change_standing(2.0, "dug Joseph out of the slide")
	else:
		await d.say("c4_pass_20", Game.player)
		await d.say("c4_pass_21", joseph)
		await d.say("c4_pass_22", Game.player)
		await d.say("c4_pass_23", joseph)
		if Game.state:
			Game.state.change_standing(-1.0, "left Joseph in the snow")
	await d.say("c4_pass_18", Game.player)
	await d.say("c4_pass_19", joseph)
	d.cine_end()
	d.cold_end()
	return true
