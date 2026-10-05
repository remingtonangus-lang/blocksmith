extends Mission
## Chapter 3, mission 4 — Water Rights. Cutter Shale — a name on Tom's list — rides into the Ybarra yard with a
## forged Water Board order. Draw on him with children in the yard (a fight, he escapes; Standing down) or let him
## ride (Standing up; Rosa's reproach). At night his men come with a carcass and coal oil for the well: hold them
## off it (defend). Whether the well stays clean is remembered. Mateo tells Ruth about the Dry Fork line camp.

const C3 = preload("res://src/missions/ch3/ch3.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")

func _init() -> void:
	id = "c3_rights"
	title = "Water Rights"
	chapter = 3
	requires = ["c3_drive"]

func run(d) -> Variant:
	d.set_time(16.4)
	d.set_weather("clear")
	var well := C3.road("windmill_flats", "mesquite_wells", 0.93, "mesquite_wells")
	var east := C3.road("windmill_flats", "mesquite_wells", 0.86, "mesquite_wells")
	await C3.start_at(d, C2.near(well, -6.0, 4.0), east, false)
	var mateo := C2.spawn_friend(d, C2.near(well, 2.0, 1.0), {"role": "rancher", "faction": "outfit", "name": "Mateo Ybarra", "seed": 3202,
		"weapon": "harlan_carbine", "skill": 0.4})
	var rosa := C2.spawn_friend(d, C2.near(well, 3.5, 3.0), {"role": "lady", "faction": "civilian", "name": "Rosa Ybarra", "seed": 3201})
	var doc := C2.spawn_friend(d, C2.near(well, -2.0, 2.5), {"role": "townsfolk", "faction": "outfit", "name": "Cornelius Abernathy", "seed": 3204,
		"weapon": "lockhart_sa", "skill": 0.3})
	var ines := C2.spawn_friend(d, C2.near(well, 4.5, 5.0), {"role": "child", "faction": "civilian", "name": "Inés Ybarra", "seed": 3203})
	for h in [mateo, rosa, doc, ines]:
		d.npc_hold(h, east)
	await d.say("c3_rights_01", Game.player)
	var riders: Array = d.spawn_group(C2.near(well, -16.0, -14.0), 6, {"role": "gunman", "faction": "syndicate", "name": "Shale Rider",
		"seed": 3410, "weapon": "merriman_lever", "skill": 0.4, "aggressive": false}, 4.0)
	var cutter = C2.one(riders)
	if cutter:
		cutter.display_name = "Cutter Shale"
	for r in riders:
		d.npc_hold(r, well)
	await d.goto(C2.near(well, -8.0, -6.0), 4.0, "Meet the riders at the gate")
	if d.aborted(): return false
	d.checkpoint("riders")
	d.cine_begin()
	await d.say("c3_rights_02", cutter)
	await d.say("c3_rights_03", Game.player)
	await d.say("c3_rights_04", cutter)
	await d.say("c3_rights_05", cutter)
	await d.say("c3_rights_06", mateo)
	await d.say("c3_rights_07", cutter)
	await d.say("c3_rights_08", doc)
	await d.say("c3_rights_09", cutter)
	var draw: int = await d.choose("Cutter Shale — a name on Tom's list — close enough to touch. Children in the yard.",
		["Draw on him here.", "Let him ride. Not with the children watching."])
	C3.set_flag("drew_on_cutter", draw == 0)
	if draw == 0:
		await d.say("c3_rights_10", Game.player)
		await d.say("c3_rights_11", cutter)
		d.cine_end()
		for h in [rosa, ines]:
			if h:
				d.npc_release(h)
				h.brain.state = h.brain.State.COWER
		d.npc_release(mateo)
		d.npc_release(doc)
		# Cutter wheels away; his men cover him
		if cutter:
			d.npc_release(cutter)
			cutter.brain.target = Game.player
			cutter.brain.target_last_seen = Game.player.global_position
			cutter.brain.state = cutter.brain.State.FLEE
		var cover: Array = riders.slice(1)
		C2.hostile(d, cover)
		await d.say("c3_rights_27", cutter)
		d.checkpoint("yard_fight")
		await d.wait_dead(cover, "Drive Cutter's men out of the yard")
		if d.aborted(): return false
		if cutter and is_instance_valid(cutter):
			cutter.queue_free()
		if Game.state:
			Game.state.change_standing(-2.0, "started a gunfight in a family's yard")
	else:
		await d.say("c3_rights_12", Game.player)
		await d.say("c3_rights_13", cutter)
		await d.say("c3_rights_14", rosa)
		await d.say("c3_rights_15", Game.player)
		d.cine_end()
		for r in riders:
			if is_instance_valid(r):
				r.queue_free()
		if Game.state:
			Game.state.change_standing(3.0, "kept the shooting away from the children")
	await d.say("c3_rights_28", ines)
	await d.say("c3_rights_29", Game.player)
	# night: they come for the well
	d.set_time(22.3)
	d.set_weather("clear")
	for h in [mateo, doc]:
		if h and h.alive:
			d.npc_hold(h, east)
	d.checkpoint("night")
	await d.say("c3_rights_16", doc)
	await d.say("c3_rights_17", mateo)
	await d.say("c3_rights_18", Game.player)
	var raiders: Array = d.spawn_group(C2.near(well, -55.0, -30.0), 5, {"role": "gunman", "faction": "syndicate", "name": "Shale Rider",
		"seed": 3420, "weapon": "lockhart_sa", "skill": 0.35, "aggressive": false}, 6.0)
	for r in raiders:
		d.npc_walk_to(r, well, Human.JOG)
	d.npc_release(mateo)
	d.npc_release(doc)
	# they walk the carcass in while the others shoot
	var carriers: Array = raiders.slice(0, 2)
	var shooters: Array = raiders.slice(2)
	for c in carriers:
		c.faction = "bandit"          # outlaws for the law's purposes, though they never draw
	C2.hostile(d, shooters)
	var held: bool = await d.defend(well, 6.0, raiders, "Keep them away from the well", 7.0)
	if d.aborted(): return false
	if mateo == null or not mateo.alive:
		d.fail("Mateo was killed")
		return false
	C3.set_flag("well_fouled", not held)
	d.checkpoint("after_raid")
	for h in [mateo, doc, rosa]:
		if h and h.alive:
			d.npc_hold(h, Game.player.global_position)
	d.cine_begin()
	if held:
		await d.say("c3_rights_19", rosa)
		await d.say("c3_rights_20", Game.player)
	else:
		await d.say("c3_rights_21", mateo)
		await d.say("c3_rights_22", Game.player)
		if Game.state:
			Game.state.change_standing(-1.0, "the Ybarra well was fouled")
	await d.say("c3_rights_23", doc)
	await d.say("c3_rights_24", Game.player)
	await d.say("c3_rights_25", rosa)
	await d.say("c3_rights_26", doc)
	d.cine_end()
	return true
