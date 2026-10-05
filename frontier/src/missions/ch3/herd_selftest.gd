extends SceneTree
## Plays the chapter 3 herd without the game: a scripted rider pushes 24 head along the real trail through the
## Breaks (does driving from behind move them toward the goal?), turns a stray back, then rides the leaders' flank
## in a stampede (can it be turned in time?). Prints HERDTEST PASS/FAIL.
##   godot --headless --path frontier --script res://src/missions/ch3/herd_selftest.gd

var _w: WorldData

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var w := WorldData.new()
	if not w.load_all():
		print("HERDTEST FAIL (no world data)")
		quit(1)
		return
	_w = w
	root.get_node("Game").set("world", w)
	var lines := []
	var ok := true
	var a := _road(w, "windmill_flats", "mesquite_wells", 0.6)
	var goal := _road(w, "windmill_flats", "mesquite_wells", 0.67)
	var herd = load("res://src/missions/ch3/herd.gd").new()
	root.add_child(herd)
	herd.setup(a, 24, 1899)
	var rider := Node3D.new()
	root.add_child(rider)
	herd.pushers.append(rider)
	herd.goal = goal
	var dir := Vector3(goal.x - a.x, 0, goal.z - a.z).normalized()
	rider.global_position = a - dir * 30.0
	var start_d := _flat(herd.center(), goal)
	# 1) drive: the rider keeps 14 m behind the bunch, weaving a little
	var t := 0.0
	var stray_made := false
	var stray_back := false
	var stray = null
	while t < 240.0:
		await physics_frame
		t += 1.0 / 60.0
		var cen: Vector3 = herd.center()
		if _flat(cen, goal) < 16.0:
			break
		if not stray_made and t > 20.0:
			stray = herd.make_stray()
			stray_made = true
		var sts: Array = herd.strays()
		if not sts.is_empty():
			# ride round the stray: get on its far side from the herd
			var s: Vector3 = sts[0].global_position
			var out := (s - cen)
			out.y = 0
			rider.global_position = _step(rider.global_position, s + out.normalized() * 8.0, 9.0)
		else:
			if stray_made and not stray_back and stray != null and not stray.lost:
				stray_back = true
			var to_goal := Vector3(goal.x - cen.x, 0, goal.z - cen.z).normalized()
			var want: Vector3 = cen - to_goal * 16.0 + to_goal.cross(Vector3.UP) * sin(t * 0.4) * 6.0
			rider.global_position = _step(rider.global_position, want, 6.0)
	var end_d := _flat(herd.center(), goal)
	var drove: bool = end_d < 16.0
	lines.append("  %s  drive: %.0f m -> %.0f m from the goal in %.0f s, %d head" % ["ok  " if drove else "FAIL", start_d, end_d, t, herd.head()])
	lines.append("  %s  stray turned back to the herd" % ("ok  " if stray_back else "FAIL"))
	ok = ok and drove and stray_back and herd.head() >= 20
	# 2) stampede: ride for the leaders' flank at a gallop
	herd.stampede(dir.rotated(Vector3.UP, 0.8))
	rider.global_position = herd.center() - herd.stampede_dir * 30.0
	t = 0.0
	var turned := false
	while t < 40.0:
		await physics_frame
		t += 1.0 / 60.0
		var lead: Node3D = herd.leader()
		if lead == null:
			break
		var side: Vector3 = herd.stampede_dir.cross(Vector3.UP).normalized()
		rider.global_position = _step(rider.global_position, lead.global_position + side * 6.0 + herd.stampede_dir * 2.0, 12.8)
		if herd.mill_t > 5.0:
			turned = true
			break
	herd.calm()
	lines.append("  %s  stampede turned by riding the leaders' flank in %.1f s" % ["ok  " if turned else "FAIL", t])
	ok = ok and turned
	# 3) a rider who only chases the drag doesn't stop a stampede
	herd.stampede(dir.rotated(Vector3.UP, -0.8))
	t = 0.0
	var max_mill := 0.0
	while t < 20.0:
		await physics_frame
		t += 1.0 / 60.0
		rider.global_position = _step(rider.global_position, herd.center() - herd.stampede_dir * 25.0, 12.8)
		max_mill = maxf(max_mill, herd.mill_t)
	herd.calm()
	var trailing_ok := max_mill < 5.0
	lines.append("  %s  chasing the drag doesn't turn them (max mill %.1f s)" % ["ok  " if trailing_ok else "FAIL", max_mill])
	ok = ok and trailing_ok
	for l in lines:
		print(l)
	print("HERDTEST %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

func _road(w: WorldData, a: String, b: String, f: float) -> Vector3:
	for r in w.features.roads:
		if r.a == a and r.b == b:
			var pts: Array = r.points
			var i := clampi(int(f * (pts.size() - 1)), 0, pts.size() - 1)
			return Vector3(pts[i][0], pts[i][2], pts[i][1])
	return Vector3.ZERO

func _flat(p: Vector3, q: Vector3) -> float:
	return Vector2(p.x - q.x, p.z - q.z).length()

## Move toward a point at a horse's speed (m/s), on the ground.
func _step(from: Vector3, to: Vector3, speed: float) -> Vector3:
	var d := Vector3(to.x - from.x, 0, to.z - from.z)
	var s := speed / 60.0
	var p := from + (d.normalized() * s if d.length() > s else d)
	p.y = _w.height(p.x, p.z)
	return p
