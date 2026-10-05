extends Mission
## Stranger — The Horseless Carriage (comic). Erasmus Pettigrew's steam Locomobile, Mark Four, runs away down the
## Greer's Post road with nobody aboard; Ruth rides it down, jumps on and hauls the brake. He offers her a share in
## the Pettigrew Motor Company for twenty dollars. Flag: invested_pettigrew (camp talk remembers it).

const ST = preload("res://src/missions/strangers/st.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const TRAIN = preload("res://src/missions/ch5/train.gd")

func _init() -> void:
	id = "s_carriage"
	title = "The Horseless Carriage"
	chapter = 1
	stranger = true
	region = "Sable Valley"
	requires = ["c1_inquiries"]
	start_pos = C3.road("bitter_spring", "greer_post", 0.3, "greer_post")

func _road_points() -> Array:
	for r in Game.world.features.roads:
		if (r.a == "bitter_spring" and r.b == "greer_post"):
			return r.points
		if (r.b == "bitter_spring" and r.a == "greer_post"):
			var pts: Array = r.points.duplicate()
			pts.reverse()
			return pts
	return []

func run(d) -> Variant:
	d.set_time(14.5)
	d.set_weather("clear")
	var start := C3.road("bitter_spring", "greer_post", 0.3, "greer_post")
	var ahead := C3.road("bitter_spring", "greer_post", 0.42, "greer_post")
	await C3.start_at(d, start, ahead, false)
	var pett := ST.person(d, start + Vector3(3.0, 0, 2.0), {"role": "townsfolk", "name": "Erasmus Pettigrew", "seed": 9101})
	# the Locomobile: a one-car "train" running the road
	var car = TRAIN.new()
	car.car_specs = [{"kind": "carriage", "len": 3.6, "w": 1.7, "h": 2.3}]
	car.accel = 0.6
	Game.main.add_child(car)
	car.setup(_road_points(), false, true)
	d.track(car)
	var s0: float = car.nearest_s(start)
	car.place_at(s0 - 30.0, 0.0)
	car.target_speed = 0.0
	d.cine_begin()
	await d.say("s_car_01", pett)
	await d.say("s_car_02", Game.player)
	car.place_at(s0 + 8.0, 7.5)
	car.target_speed = 8.5
	await d.say("s_car_03", pett)
	await d.say("s_car_04", pett)
	d.cine_end()
	d.checkpoint("runaway")
	await d.mount_up("Get on your horse and ride it down")
	if d.aborted(): return false
	var limit: float = minf(car.length() - 15.0, s0 + 1400.0)
	await d.board_train(car, 0, "Ride alongside the Locomobile and jump aboard", limit)
	if d.aborted(): return false
	d.say_async("s_car_05", Game.player)
	d.set_objective("Haul the brake lever")
	await d.ride_until_stopped(car, 0)
	if d.aborted(): return false
	await d.say("s_car_06", null)
	d.checkpoint("stopped")
	d._put_on_ground(pett, Game.player.global_position + Vector3(3.0, 0, 1.5))
	d.npc_hold(pett, Game.player.global_position)
	var rufus := ST.person(d, Game.player.global_position + Vector3(-3.0, 0, 3.0), {"role": "worker", "name": "Rufus", "seed": 9102})
	d.cine_begin()
	await d.say("s_car_07", pett)
	await d.say("s_car_08", Game.player)
	await d.say("s_car_09", pett)
	await d.say("s_car_10", pett)
	var pick: int = await d.choose("Twenty dollars for a share in the Pettigrew Motor Company.",
		["Buy a share. Twenty dollars.", "Keep your money and your eyebrows."])
	ST.set_flag("invested_pettigrew", pick == 0)
	if pick == 0:
		ST.pay(20.0)
		await d.say("s_car_11", Game.player)
		await d.say("s_car_12", pett)
	else:
		await d.say("s_car_13", Game.player)
		await d.say("s_car_14", pett)
	await d.say("s_car_15", pett)
	await d.say("s_car_16", rufus)
	await d.say("s_car_17", pett)
	await d.say("s_car_18", rufus)
	d.cine_end()
	ST.deed("help_stranger")
	return true
