extends Mission
## Chapter 2, mission 4 — The Exchange. Del's plan: Thursday night, the Linden Exchange Bank's back door. Sneak past
## the old watchman (tie him up quietly, or be seen and lose time). The vault is empty except for a box of forged
## quitclaim deeds — one signed by Arliss Doane two days after his funeral — and a satchel of bait money (take it:
## money, Standing down, a bigger price on Ruth's head later). Linden County deputies were waiting: timed escape.

const C2 = preload("res://src/missions/ch2/ch2.gd")

func _init() -> void:
	id = "c2_exchange"
	title = "The Exchange"
	chapter = 2
	requires = ["c2_thornwood"]

func run(d) -> Variant:
	d.set_time(1.2)
	d.set_weather("fog")
	var bank := C2.spot("port_linden", -12.0, 34.0)
	var alley := C2.near(bank, -32.0, 22.0)
	d.place_player(C2.near(alley, -40.0, 10.0), 0.0)
	await d.goto(alley, 5.0, "Meet Del in the alley behind the Exchange")
	if d.aborted(): return false
	var del := C2.spawn_friend(d, C2.near(alley, 1.5, 1.0), {"role": "gambler", "faction": "outfit", "name": "Del Arceneaux",
		"seed": 2201, "weapon": "lockhart_sa", "skill": 0.65, "health": 160.0})
	d.npc_hold(del, Game.player.global_position)
	d.cine_begin()
	await d.say("c2_bank_01", del)
	await d.say("c2_bank_02", Game.player)
	await d.say("c2_bank_03", del)
	await d.say("c2_bank_04", Game.player)
	await d.say("c2_bank_05", del)
	await d.say("c2_bank_06", Game.player)
	d.cine_end()
	d.checkpoint("alley")
	# the watchman sits by the back door looking down the lane, away from the alley; a deputy keeps the corner
	var door := C2.near(bank, -6.0, 6.0)
	var dodd := C2.spawn_friend(d, C2.near(door, 1.2, -1.0), {"role": "townsfolk", "faction": "civilian", "name": "Ephraim Dodd", "seed": 2401})
	var corner: Array = d.spawn_group(C2.near(bank, 14.0, -10.0), 1, {"role": "lawman", "faction": "law", "name": "Linden County Deputy",
		"seed": 2402, "weapon": "harlan_carbine", "skill": 0.4}, 0.5)
	var away := door + (door - alley).normalized() * 20.0
	d.npc_hold(dodd, away)
	for c in corner:
		d.npc_hold(c, C2.near(bank, 30.0, -10.0))
	if Game.hud and not d.autopilot:
		Game.hud.notice("Crouch (C / B) and keep out of the watchman's sight", 5.0)
	var quiet: bool = await d.sneak_to(C2.near(door, -1.0, 1.2), 2.2, "Reach the back door unseen", [dodd] + corner)
	if d.aborted(): return false
	var seconds := 55.0
	d.npc_hold(dodd, Game.player.global_position)
	if quiet:
		await d.interact(dodd.global_position if dodd else door, "Tie up the watchman")
		if d.aborted(): return false
		d.cine_begin()
		await d.say("c2_bank_07", dodd)
		await d.say("c2_bank_08", Game.player)
		d.cine_end()
		if Game.state:
			Game.state.change_standing(1.0, "spared the night watchman")
	else:
		d.cine_begin()
		await d.say("c2_bank_09", dodd)
		await d.say("c2_bank_10", del)
		d.cine_end()
		seconds = 35.0
	C2.set_flag("bank_quiet", quiet)
	d.checkpoint("inside")
	var vault := C2.near(bank, -1.5, 1.0)
	d.npc_walk_to(del, vault)
	await d.interact(vault, "Open the vault")
	if d.aborted(): return false
	if del:
		d.npc_hold(del, Game.player.global_position)
	d.cine_begin()
	await d.say("c2_bank_11", del)
	await d.say("c2_bank_12", Game.player)
	await d.say("c2_bank_13", Game.player)
	await d.say("c2_bank_14", del)
	var take: int = await d.choose("Fifty dollars in a satchel, left where you'd trip over it.", ["Take the satchel too.", "Take only the deeds."])
	if take == 0:
		await d.say("c2_bank_15", Game.player)
		await d.say("c2_bank_16", del)
		if Game.state:
			Game.state.add_money(50.0)
			Game.state.change_standing(-5.0, "took the bank's bait money")
	else:
		await d.say("c2_bank_17", Game.player)
		await d.say("c2_bank_18", del)
		if Game.state:
			Game.state.change_standing(2.0, "left the bait money")
	C2.set_flag("took_satchel", take == 0)
	C2.set_flag("has_deeds", true)
	d.cine_end()
	# the deputies were waiting
	var deputies: Array = d.spawn_group(C2.near(bank, 22.0, -18.0), 4, {"role": "lawman", "faction": "law", "name": "Linden County Deputy",
		"seed": 2410, "weapon": "lockhart_sa", "skill": 0.35}, 6.0)
	deputies.append_array(corner)
	for c in corner:
		d.npc_release(c)
	await d.say("c2_bank_19", C2.one(deputies))
	await d.say("c2_bank_20", del)
	for dep in deputies:
		dep.brain.aggressive = true
		dep.brain.share_target(Game.player)
	d.npc_release(del)
	d.npc_release(dodd)
	if dodd:
		dodd.brain.state = dodd.brain.State.COWER
	d.checkpoint("escape")
	await d.escape(bank, 120.0, "Get clear of the Exchange", seconds)
	if d.aborted(): return false
	var killed := C2.dead_count(deputies)
	if killed > 0 and Game.state:
		Game.state.change_standing(-3.0 * killed, "killed Linden County deputies")
	C2.set_flag("deputies_killed", killed)
	for dep in deputies:
		if is_instance_valid(dep) and dep.alive:
			dep.brain.aggressive = false
			dep.brain.target = null
			dep.brain.state = dep.brain.State.ROUTINE
	# Del finds her at the edge of town, out of breath
	if del == null or not del.alive:
		d.fail("Del was killed")
		return false
	d.npc_hold(del, Game.player.global_position)
	d._put_on_ground(del, C2.near(Game.player.global_position, 3.0, 2.0))
	d.cine_begin()
	await d.say("c2_bank_21", del)
	if killed > 0:
		await d.say("c2_bank_25", Game.player)
	await d.say("c2_bank_22", Game.player)
	await d.say("c2_bank_23", del)
	await d.say("c2_bank_24", Game.player)
	d.cine_end()
	return true
