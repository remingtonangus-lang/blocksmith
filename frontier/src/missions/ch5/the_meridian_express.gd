extends Mission
## Chapter 5, mission 2 — The Meridian Express. Kessler's Tank, Thursday afternoon: the westbound express slows for
## water and climbs away. Gallop alongside the express car and jump for it (fail if it reaches Bitter Spring);
## Del stops the engine. Wells and Merriweather guards, then the messenger in the door of the car — the mirror of
## Harlan's Siding: talk him down or shoot him. The ledger (and the payroll, if those were the rules). Pell's men ride
## out of the caboose: they knew. If Hap came to hold the horses, he's hit. Ride for Halvorsen's.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const C5 = preload("res://src/missions/ch5/ch5.gd")

func _init() -> void:
	id = "c5_train"
	title = "The Meridian Express"
	chapter = 5
	requires = ["c5_plan"]

func run(d) -> Variant:
	d.set_time(15.2)
	d.set_weather("clear")
	var train = C5.make_train(d)
	train.lay_track(C5.START_S - 50.0, C5.LIMIT_S + 60.0)
	var tank: Vector3 = train.at(C5.TANK_S)
	var side: Vector3 = train.tangent(C5.TANK_S).cross(Vector3.UP).normalized()
	C5.water_tower(d, tank + side * 4.5)
	train.target_speed = 0.0
	train.place_at(C5.START_S - 250.0, 0.0)
	var wait := C5.wait_spot(train)
	await C3.start_at(d, wait, tank, true)
	var del = C3.rider(d, wait + Vector3(5, 0, 3), {"role": "gambler", "faction": "outfit", "name": "Del Arceneaux", "seed": 2201,
		"weapon": "lockhart_sa", "skill": 0.65, "health": 200.0}, "morgan")
	del.ride_with(Game.player, Vector3(5, 0, 4))
	var joseph = C3.rider(d, wait + Vector3(-5, 0, 3), {"role": "hunter", "faction": "outfit", "name": "Joseph Kehoe", "seed": 4102,
		"weapon": "bowden_bolt", "skill": 0.7, "health": 200.0}, "appaloosa")
	joseph.ride_with(Game.player, Vector3(-5, 0, 4))
	var hap: Human = null
	if C3.flag("hap_comes"):
		hap = C2.spawn_friend(d, C3.dry(wait + side * 10.0), {"role": "drover", "faction": "outfit", "name": "Hap Lindqvist", "seed": 7})
		d.npc_hold(hap, tank)
	d.cine_begin()
	await d.say("c5_train_01", joseph.man)
	await d.say("c5_train_02", del.man)
	d.cine_end()
	d.checkpoint("waiting")
	# here she comes: down the grade, slow for water, then away
	train.place_at(C5.START_S, 9.0)
	train.target_speed = 11.5
	if not d.autopilot:
		var t := 0.0
		while train.s < C5.POLE_S - 40.0 and t < 90.0 and not d.aborted():
			await d.get_tree().physics_frame
			t += d.get_physics_process_delta_time()
	await d.say("c5_train_03", null)
	var express: int = train.car_index("express")
	await d.board_train(train, express, "Ride alongside the express car and jump for it", C5.LIMIT_S)
	if d.aborted(): return false
	await d.say("c5_train_04", Game.player)
	await d.ride_until_stopped(train, express)
	if d.aborted(): return false
	d.checkpoint("stopped")
	var car: Vector3 = train.car_center(express)
	var cside: Vector3 = train.tangent(train.s - float(train.cars[express].offset)).cross(Vector3.UP).normalized()
	del.teleport(train.car_center(0) + cside * 4.0)
	del.halt()
	joseph.teleport(car + cside * 7.0 + Vector3(4, 0, 0))
	joseph.halt()
	await d.say("c5_train_05", del.man)
	var guards: Array = d.spawn_group(C3.dry(car - cside * 4.0), 3, {"role": "lawman", "faction": "syndicate", "name": "Express Guard",
		"seed": 5110, "weapon": "harlan_carbine", "skill": 0.4, "aggressive": false}, 3.0)
	await d.say("c5_train_06", C2.one(guards))
	joseph.get_down()
	d.npc_release(joseph.man)
	C2.hostile(d, guards)
	await d.wait_dead(guards, "Take the express car")
	if d.aborted(): return false
	d.checkpoint("messenger")
	var harmon: Human = d.spawn_at(car + cside * 1.8, {"role": "townsfolk", "faction": "civilian", "name": "Will Harmon", "seed": 5120,
		"weapon": "harlan_carbine"}, Game.player.global_position)
	d.cine_begin()
	await d.say("c5_train_24", Game.player)
	await d.say("c5_train_07", harmon)
	await d.say("c5_train_08", Game.player)
	await d.say("c5_train_09", harmon)
	var mirror: int = await d.choose("A messenger in the door of the car, his shotgun half up. Harlan's Siding, eighteen months on.",
		["Lower your gun and tell him who you are.", "Shoot him before he shoots you."])
	if mirror == 0:
		await d.say("c5_train_10", Game.player)
		await d.say("c5_train_11", harmon)
		d.cine_end()
		C3.set_flag("messenger_killed", false)
		if Game.state:
			Game.state.change_standing(5.0, "spared the express messenger")
		d.npc_walk_to(harmon, harmon.global_position + cside * 40.0)
	else:
		d.cine_end()
		harmon.damageable.apply_hit({"amount": 999.0, "zone": "chest", "attacker": Game.player})
		Game.noise.emit(harmon.global_position, 80.0, Game.player)
		d.cine_begin()
		await d.say("c5_train_12", del.man)
		await d.say("c5_train_13", Game.player)
		d.cine_end()
		C3.set_flag("messenger_killed", true)
		if Game.state:
			Game.state.change_standing(-8.0, "shot the express messenger")
	await d.interact(car + cside * 1.6, "Open the express safe")
	if d.aborted(): return false
	var billy: Human = d.spawn_at(car + cside * 2.4 + Vector3(1, 0, 0), {"role": "child", "faction": "outfit", "name": "Billy Pruitt", "seed": 14}, car)
	await d.say("c5_train_14", billy)
	if C3.flag("train_rules", "ledger") == "ledger":
		await d.say("c5_train_15", Game.player)
		C3.set_flag("payroll_taken", false)
	else:
		await d.say("c5_train_16", del.man)
		C3.set_flag("payroll_taken", true)
	C3.set_flag("has_ledger", true)
	d.checkpoint("posse")
	var posse: Array = d.spawn_group(C3.dry(train.car_center(train.cars.size() - 1) - cside * 8.0), 5, {"role": "gunman", "faction": "syndicate",
		"name": "Ashby's Rider", "seed": 5130, "weapon": "merriman_lever", "skill": 0.4, "aggressive": false}, 5.0)
	if posse.size() > 0:
		posse[0].display_name = "Captain Ward Ashby"
	await d.say("c5_train_17", joseph.man)
	await d.say("c5_train_18", C2.one(posse))
	C2.hostile(d, posse)
	if hap and hap.alive:
		await d.say("c5_train_19", hap)
		await d.say("c5_train_20", Game.player)
		C3.set_flag("hap_wounded", true)
		hap.brain.state = hap.brain.State.COWER
	await d.say("c5_train_21", joseph.man)
	await d.mount_up("Get on your horse")
	await d.escape(car, 220.0, "Ride for Halvorsen's", 70.0)
	if d.aborted(): return false
	for p in posse:
		if is_instance_valid(p) and p.alive:
			p.queue_free()
	d.npc_hold(del.man, Game.player.global_position)
	await d.say("c5_train_22", del.man)
	await d.say("c5_train_23", Game.player)
	return true
