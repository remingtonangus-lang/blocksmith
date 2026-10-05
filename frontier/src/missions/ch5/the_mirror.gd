extends Mission
## Chapter 5, mission 1 — The Mirror. Fenn brings word to Willow Bend: Thursday's westbound express carries the
## syndicate payroll and Pell's own ledger. The Outfit argues over doing it the way Tom's train was done. The rules
## Ruth sets (the ledger only, nobody fires first — or everything in the safe) decide whether Hap comes to hold the
## horses or stays to keep the camp. Joseph rides with her along the line to scout Kessler's Tank.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const C5 = preload("res://src/missions/ch5/ch5.gd")

func _init() -> void:
	id = "c5_plan"
	title = "The Mirror"
	chapter = 5
	requires = ["c4_strike"]

func run(d) -> Variant:
	d.set_time(19.4)
	d.set_weather("fair")
	d.set_snow(0.0)
	var camp := Mission.place("caddell_camp")
	await C3.start_at(d, C2.near(camp, -6.0, 5.0), camp, false)
	var fenn := C2.spawn_friend(d, C2.near(camp, 2.5, -2.0), {"role": "townsfolk", "faction": "civilian", "name": "Augustus Fenn", "seed": 2101})
	var hap := C2.spawn_friend(d, C2.near(camp, 2.0, 1.0), {"role": "drover", "faction": "outfit", "name": "Hap Lindqvist", "seed": 7})
	var del := C2.spawn_friend(d, C2.near(camp, -1.5, 2.2), {"role": "gambler", "faction": "outfit", "name": "Del Arceneaux", "seed": 2201})
	var doc := C2.spawn_friend(d, C2.near(camp, -2.2, -0.5), {"role": "townsfolk", "faction": "outfit", "name": "Cornelius Abernathy", "seed": 3204})
	var billy := C2.spawn_friend(d, C2.near(camp, 0.5, -2.2), {"role": "child", "faction": "outfit", "name": "Billy Pruitt", "seed": 14})
	var joseph := C2.spawn_friend(d, C2.near(camp, 3.0, -1.0), {"role": "hunter", "faction": "outfit", "name": "Joseph Kehoe", "seed": 4101})
	for h in [fenn, hap, del, doc, billy, joseph]:
		d.npc_hold(h, camp)
	await d.goto(C2.near(camp, -2.0, 2.0), 3.0, "Sit down at the fire with the Outfit")
	if d.aborted(): return false
	d.cine_begin()
	await d.say("c5_plan_01", fenn)
	await d.say("c5_plan_02", del)
	await d.say("c5_plan_03", hap)
	await d.say("c5_plan_04", Game.player)
	await d.say("c5_plan_05", joseph)
	await d.say("c5_plan_06", doc)
	await d.say("c5_plan_07", billy)
	var rules: int = await d.choose("The Outfit is waiting on you. Tom's train was robbed for its safe, with a messenger in the door.",
		["The ledger only. Nobody fires first, nobody touches the messenger.", "Everything in the safe. Pell stole it first."])
	C3.set_flag("train_rules", "ledger" if rules == 0 else "all")
	C3.set_flag("hap_comes", rules == 0)
	if rules == 0:
		await d.say("c5_plan_08", Game.player)
		await d.say("c5_plan_09", hap)
		await d.say("c5_plan_10", del)
		if Game.state:
			Game.state.change_standing(2.0, "set rules for the train")
	else:
		await d.say("c5_plan_11", Game.player)
		await d.say("c5_plan_12", hap)
		await d.say("c5_plan_13", del)
		await d.say("c5_plan_14", joseph)
		if Game.state:
			Game.state.change_standing(-3.0, "planned to take the payroll")
	d.cine_end()
	d.checkpoint("plan")
	# scout the water stop with Joseph
	var train = C5.make_train(d, false)
	var tank: Vector3 = train.at(C5.TANK_S)
	var side: Vector3 = train.tangent(C5.TANK_S).cross(Vector3.UP).normalized()
	C5.water_tower(d, tank + side * 4.5)
	var rider = C3.rider(d, joseph.global_position, {"role": "hunter", "faction": "outfit", "name": "Joseph Kehoe", "seed": 4102}, "appaloosa")
	joseph.queue_free()
	await d.mount_up("Mount up and ride with Joseph")
	d.set_time(9.5)
	var near_tank := C3.dry(tank + side * 12.0)
	await d.ride_with(rider, "Ride the line with Joseph to Kessler's Tank", near_tank, 12.0)
	if d.aborted(): return false
	d.checkpoint("tank")
	d.cine_begin()
	await d.say("c5_plan_15", rider.man)
	await d.say("c5_plan_16", Game.player)
	await d.say("c5_plan_17", rider.man)
	d.cine_end()
	var pole := C3.dry(train.at(C5.POLE_S) + side * 5.0)
	await d.interact(pole, "Tie a rag on the third telegraph pole past the tank")
	if d.aborted(): return false
	await d.say("c5_plan_18", Game.player)
	d.dismount_player()
	var b2 := C2.spawn_friend(d, C2.near(Game.player.global_position, 3.0, 2.0), {"role": "child", "faction": "outfit", "name": "Billy Pruitt", "seed": 14})
	d.npc_hold(b2, Game.player.global_position)
	await d.say("c5_plan_19", b2)
	await d.say("c5_plan_20", Game.player)
	return true
