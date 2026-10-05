extends SceneTree
## Runs the chapter 5 express without the game: builds the train on the real rail, rolls it down from Port Linden
## through the Kessler's Tank slow zone, and sends a scripted rider (a galloping horse's top speed and stamina) from
## the waiting spot to the express car's side. Checks the path, the slow-down at the tank, that a galloping rider can
## get level with the car before Bitter Spring, and that the brakes stop it. Prints TRAINTEST PASS/FAIL.
##   godot --headless --path frontier --script res://src/missions/ch5/train_selftest.gd

var _w: WorldData

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var w := WorldData.new()
	if not w.load_all():
		print("TRAINTEST FAIL (no world data)")
		quit(1)
		return
	_w = w
	root.get_node("Game").set("world", w)
	var C5 = load("res://src/missions/ch5/ch5.gd")
	var t = load("res://src/missions/ch5/train.gd").new()
	root.add_child(t)
	t.setup(w.features.get("rail", {}).get("points", []), true)
	t.slow_zones = [{"s": C5.TANK_S, "r": 60.0, "v": 3.5}]
	var lines := []
	var ok := true
	var path_ok: bool = t.length() > 7000.0 and t.cars.size() == 5
	lines.append("  %s  path %.0f m along the rail, %d cars" % ["ok  " if path_ok else "FAIL", t.length(), t.cars.size()])
	ok = ok and path_ok
	t.place_at(C5.START_S, 9.0)
	t.target_speed = 11.5
	var express: int = t.car_index("express")
	var wait: Vector3 = t.at(C5.POLE_S) + t.tangent(C5.POLE_S).cross(Vector3.UP).normalized() * 55.0 - t.tangent(C5.POLE_S) * 30.0
	var rider := wait
	var stamina := 35.0          # seconds of gallop
	var tm := 0.0
	var min_speed := 99.0
	var level_t := 0.0
	var boarded_at := -1.0
	var pole_t := -1.0
	while t.s < C5.LIMIT_S and tm < 240.0:
		await physics_frame
		tm += 1.0 / 60.0
		if absf(t.s - C5.TANK_S) < 40.0:
			min_speed = minf(min_speed, t.speed)
		# the rider starts when the engine passes the rag pole
		if t.s > C5.POLE_S:
			if pole_t < 0.0:
				pole_t = tm
			var c: Vector3 = t.car_center(express)
			var fwd: Vector3 = t.tangent(t.s - float(t.cars[express].offset))
			var side := fwd.cross(Vector3.UP).normalized()
			var target := c + side * 3.5
			var spd := 12.8 if stamina > 0.0 else 6.4
			if spd > 7.0:
				stamina -= 1.0 / 60.0
			var d := Vector3(target.x - rider.x, 0, target.z - rider.z)
			rider += d.normalized() * minf(spd / 60.0, d.length())
			var rel := rider - c
			var level: bool = absf(rel.dot(fwd)) < float(t.cars[express].len) * 0.5 + 1.5 and absf(rel.dot(side)) < 5.0
			level_t = level_t + 1.0 / 60.0 if level else 0.0
			if level_t > 0.6 and boarded_at < 0.0:
				boarded_at = t.s
				break
	var slow_ok := min_speed < 4.5
	lines.append("  %s  slows to %.1f m/s for water at Kessler's Tank" % ["ok  " if slow_ok else "FAIL", min_speed])
	var board_ok := boarded_at > 0.0
	lines.append("  %s  a galloping rider gets level with the express car %s" % ["ok  " if board_ok else "FAIL",
		("%.0f m past the pole, %.0f s after it went by (limit %.0f m)" % [boarded_at - C5.POLE_S, tm - pole_t, C5.LIMIT_S - C5.POLE_S]) if board_ok else "(never)"])
	t.brake()
	var bt := 0.0
	while t.speed > 0.15 and bt < 30.0:
		await physics_frame
		bt += 1.0 / 60.0
	var brake_ok: bool = t.speed <= 0.15
	lines.append("  %s  brakes stop it in %.1f s" % ["ok  " if brake_ok else "FAIL", bt])
	ok = ok and slow_ok and board_ok and brake_ok
	for l in lines:
		print(l)
	print("TRAINTEST %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
