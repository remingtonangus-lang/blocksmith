extends Mission
## Chapter 4, mission 4 — The Youngest. Dusk, storm, the line shack under the ridge: Asa Shale's two men shoot
## from the window while the cold works on Ruth; break them and Asa, nineteen and leg-shot, gives up Garrity's letter
## and the truth about Harlan's Siding. Spare him (sent west under another name; flag "spared_asa" for chapter 6;
## Standing up) or kill him (Standing down; Joseph's silence). Joseph will ride with her "as far as Eben".

const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const C4 = preload("res://src/missions/ch4/ch4.gd")

func _init() -> void:
	id = "c4_asa"
	title = "The Youngest"
	chapter = 4
	requires = ["c4_pass"]

func run(d) -> Variant:
	d.set_time(18.3)
	d.set_weather("storm")
	d.set_snow(0.6)
	var shack := C4.at(C4.LINE_SHACK)
	C4.shack(d, shack)
	var start := C4.at(shack + Vector3(-110.0, 0, 30.0))
	await C3.start_at(d, start, shack, false)
	var joseph := C2.spawn_friend(d, C2.near(start, 3.0, 2.0), {"role": "hunter", "faction": "outfit", "name": "Joseph Kehoe", "seed": 4101,
		"weapon": "bowden_bolt", "skill": 0.7, "health": 160.0})
	d.npc_hold(joseph, shack)
	d.cold_begin(1.2)
	await d.say("c4_asa_01", Game.player)
	d.checkpoint("approach")
	await d.goto(C2.near(shack, -40.0, 12.0), 5.0, "Close in on the line shack")
	if d.aborted(): return false
	var men: Array = d.spawn_group(C2.near(shack, 1.5, 2.6), 2, {"role": "gunman", "faction": "syndicate", "name": "Shale Rider",
		"seed": 4410, "weapon": "merriman_lever", "skill": 0.45, "aggressive": false}, 1.0)
	var asa := C2.spawn_friend(d, C2.near(shack, -1.0, 2.4), {"role": "gunman", "faction": "syndicate", "name": "Asa Shale", "seed": 4130,
		"weapon": "lockhart_sa", "skill": 0.25, "aggressive": false})
	for h in men + [asa]:
		d.npc_hold(h, Game.player.global_position)
	joseph.global_position = C2.near(Game.player.global_position, 3.0, 2.0)
	d.cine_begin()
	await d.say("c4_asa_02", joseph)
	await d.say("c4_asa_25", Game.player)
	await d.say("c4_asa_03", asa)
	await d.say("c4_asa_04", Game.player)
	await d.say("c4_asa_05", asa)
	await d.say("c4_asa_06", joseph)
	d.cine_end()
	d.npc_release(joseph)
	if asa:
		asa.brain.bravery = 0.0
		asa.damageable.max_health = 400.0
		asa.damageable.health = 400.0
	C2.hostile(d, men + [asa])
	d.checkpoint("shack_fight")
	await d.wait_dead(men, "Break the line shack")
	if d.aborted(): return false
	if asa == null or not is_instance_valid(asa) or not asa.alive:
		C3.set_flag("spared_asa", false)
		C3.set_flag("asa_killed", true)
		d.cold_end()
		return true
	asa.faction = "syndicate"
	asa.brain.aggressive = false
	asa.brain.target = null
	asa.brain.state = asa.brain.State.SURRENDER
	d.npc_hold(asa, Game.player.global_position)
	asa.intent.crouch = true
	d.npc_hold(joseph, asa.global_position)
	d.cold_end()
	d.checkpoint("asa_down")
	d.cine_begin()
	await d.say("c4_asa_07", asa)
	await d.say("c4_asa_08", Game.player)
	await d.say("c4_asa_09", asa)
	await d.say("c4_asa_10", joseph)
	await d.say("c4_asa_11", Game.player)
	await d.say("c4_asa_12", asa)
	C3.set_flag("has_garrity_letter", true)
	var spare: int = await d.choose("Asa Shale, nineteen, leg-shot in the snow. He held the horses.",
		["Let him go west under another name.", "Finish it."])
	if spare == 0:
		await d.say("c4_asa_13", Game.player)
		await d.say("c4_asa_14", asa)
		await d.say("c4_asa_15", Game.player)
		await d.say("c4_asa_22", asa)
		await d.say("c4_asa_18", joseph)
		d.cine_end()
		C3.set_flag("spared_asa", true)
		C3.set_flag("asa_killed", false)
		if Game.state:
			Game.state.good_deed("spare_enemy")
			Game.state.change_standing(3.0, "spared Asa Shale")
		d.npc_walk_to(asa, C2.near(shack, -300.0, 200.0), Human.WALK)
	else:
		await d.say("c4_asa_16", Game.player)
		d.cine_end()
		asa.faction = "bandit"
		asa.damageable.apply_hit({"amount": 999.0, "zone": "chest", "attacker": Game.player})
		Game.noise.emit(asa.global_position, 60.0, Game.player)
		d.cine_begin()
		await d.say("c4_asa_17", joseph)
		await d.say("c4_asa_23", Game.player)
		await d.say("c4_asa_24", joseph)
		C3.set_flag("spared_asa", false)
		C3.set_flag("asa_killed", true)
	await d.say("c4_asa_19", joseph)
	await d.say("c4_asa_20", Game.player)
	await d.say("c4_asa_21", joseph)
	d.cine_end()
	return true
