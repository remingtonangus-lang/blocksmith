extends Mission
## Chapter 6, mission 2 — Long Light. The last ride for Eben Shale: dusk at the San Lazaro mission ruin, his men
## in the walls, Eben with his Bible in the roofless chapel (and Asa, if Ruth spared him, trying to stop his
## brother). Hear him out or draw now; how it ends was settled by the road she took (the ending branch locked at the
## end of chapter 5): high — she shoots the gun from his hand and takes him in alive; middle — the duel kills him;
## low — she executes him and Ashby offers her his men.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const C6 = preload("res://src/missions/ch6/ch6.gd")

func _init() -> void:
	id = "c6_eben"
	title = "Long Light"
	chapter = 6
	requires = ["c6_warrants"]

func run(d) -> Variant:
	d.set_time(18.6)
	d.set_weather("clear")
	var ruin := Mission.place("san_lazaro")
	var start := C3.road("mesquite_wells", "san_lazaro", 0.93, "san_lazaro")
	await C3.start_at(d, start, ruin, true)
	await d.say("c6_eben_01", Game.player)
	d.checkpoint("ride")
	await d.goto(C2.near(ruin, -40.0, 20.0), 10.0, "Ride to the San Lazaro mission", true)
	if d.aborted(): return false
	d.dismount_player()
	var men: Array = d.spawn_group(C2.near(ruin, -8.0, 6.0), 5, {"role": "gunman", "faction": "syndicate", "name": "Shale Rider",
		"seed": 6210, "weapon": "merriman_lever", "skill": 0.45, "aggressive": false}, 10.0)
	var eben: Human = C2.spawn_friend(d, C2.near(ruin, 4.0, -4.0), {"role": "gunman", "faction": "syndicate", "name": "Eben Shale",
		"seed": 6201, "weapon": "lockhart_sa", "skill": 0.7, "aggressive": false, "health": 3000.0})
	for m in men:
		d.npc_hold(m, Game.player.global_position)
	d.npc_hold(eben, Game.player.global_position)
	var crew: Dictionary = C6.spawn_outfit(d, C2.near(ruin, -44.0, 24.0), true)
	C2.hostile(d, men)
	for id in crew.keys():
		d.npc_release(crew[id])
	d.checkpoint("walls")
	await d.wait_dead(men, "Clear Eben's men from the walls")
	if d.aborted(): return false
	d.checkpoint("chapel")
	await d.goto(C2.near(eben.global_position, -4.0, 2.0), 3.0, "Go into the chapel")
	if d.aborted(): return false
	var asa: Human = null
	if C3.flag("spared_asa", false):
		asa = C2.spawn_friend(d, C2.near(eben.global_position, 3.0, 2.5), {"role": "gunman", "faction": "civilian", "name": "Asa Shale", "seed": 4130})
		d.npc_hold(asa, eben.global_position)
	d.npc_hold(eben, Game.player.global_position)
	d.cine_begin()
	await d.say("c6_eben_02", eben)
	await d.say("c6_eben_03", eben)
	await d.say("c6_eben_04", Game.player)
	await d.say("c6_eben_05", eben)
	if asa:
		await d.say("c6_eben_06", asa)
		await d.say("c6_eben_07", eben)
	var hear: int = await d.choose("Eben Shale, Bible in one hand, the other near his gun. The last name.", ["Hear him out.", "Draw now."])
	C3.set_flag("heard_eben", hear == 0)
	if hear == 0:
		await d.say("c6_eben_08", eben)
		await d.say("c6_eben_09", Game.player)
	else:
		await d.say("c6_eben_10", Game.player)
	d.cine_end()
	var branch: String = C6.branch()
	Game.noise.emit(eben.global_position, 80.0, Game.player)
	match branch:
		"high":
			eben.brain.state = eben.brain.State.SURRENDER
			d.cine_begin()
			await d.say("c6_eben_11", eben)
			await d.say("c6_eben_12", Game.player)
			if asa:
				await d.say("c6_eben_19", asa)
			d.cine_end()
			C3.set_flag("eben_fate", "jailed")
			if Game.state:
				Game.state.good_deed("bring_alive")
		"middle":
			eben.damageable.max_health = 100.0
			eben.faction = "bandit"
			eben.brain.aggressive = true
			eben.damageable.apply_hit({"amount": 999.0, "zone": "chest", "attacker": Game.player})
			d.cine_begin()
			await d.say("c6_eben_13", eben)
			await d.say("c6_eben_14", Game.player)
			if asa:
				await d.say("c6_eben_20", asa)
			d.cine_end()
			C3.set_flag("eben_fate", "dead")
		_:
			eben.brain.state = eben.brain.State.SURRENDER
			d.cine_begin()
			await d.say("c6_eben_15", eben)
			await d.say("c6_eben_16", Game.player)
			d.cine_end()
			eben.damageable.max_health = 100.0
			eben.faction = "bandit"
			eben.damageable.apply_hit({"amount": 999.0, "zone": "head", "attacker": Game.player})
			var ashby: Human = C2.spawn_friend(d, C2.near(ruin, -6.0, 10.0), {"role": "gunman", "faction": "syndicate", "name": "Captain Ward Ashby", "seed": 6230})
			d.npc_hold(ashby, Game.player.global_position)
			d.cine_begin()
			if asa:
				await d.say("c6_eben_21", asa)
			await d.say("c6_eben_17", ashby)
			await d.say("c6_eben_18", Game.player)
			d.cine_end()
			C3.set_flag("eben_fate", "executed")
			C3.set_flag("ruth_chief", true)
	if eben and is_instance_valid(eben) and eben.alive and branch == "high":
		eben.queue_free()
	return true
