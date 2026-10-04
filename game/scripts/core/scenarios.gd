extends Node
## --scenario NAME[,NAME...]: scripted play through the real game loop (headless is fine), each with an oracle.
##   ride      stand on the rear deck of an AI crawler driving its road for 20 s: the player must stay aboard
##   drive     enter a crawler, hold forward for 12 s: it must travel > 60 m and stay upright
##   fly       enter the gunship, climb 6 s then fly forward 8 s: altitude and distance must grow
##   dropship  board a dropship: it must deliver the passenger near the landing zone within 240 s
##   battle    run the front for 60 s: both sides must fire and take casualties, nobody stuck under ground
## Prints "scenario NAME: PASS/FAIL ..." and quits with the number of failures.

var queue: Array = []
var current := ""
var t := 0.0
var data := {}
var failures := 0
var results: Array = []


func start(names: Array) -> void:
	queue = names
	_next()


func _next() -> void:
	if queue.is_empty():
		for r in results:
			print(r)
		G.log_line("scenarios done: %d failed" % failures)
		G.write_json(G.log_dir() + "/scenarios.json", {"results": results, "failures": failures})
		get_tree().quit(failures)
		return
	current = queue.pop_front()
	t = 0.0
	data = {}
	call("_setup_" + current)


func _done(ok: bool, msg: String) -> void:
	var line := "scenario %s: %s %s" % [current, "PASS" if ok else "FAIL", msg]
	results.append(line)
	print(line)
	if not ok:
		failures += 1
	_release()
	var p: Player = G.player
	if p and p.vehicle and p.vehicle.has_method("exit"):
		p.vehicle.exit(p)
	_next()


func _release() -> void:
	for a in ["move_forward", "ascend", "fire", "interact", "brake", "boost"]:
		Input.action_release(a)


func _process(delta: float) -> void:
	if current == "":
		return
	t += delta
	call("_tick_" + current, delta)


# ------------------------------------------------------------------------------------------------- ride

func _setup_ride() -> void:
	var v: Vehicles = G.vehicles
	var c: Crawler = null
	for k in v.crawlers:
		if k.has_meta("patrol"):
			c = k
	data["c"] = c
	var p: Player = G.player
	G.terrain.collision_now(c.global_position)
	p.global_position = c.global_transform * Vector3(0, 3.1, 3.0)
	p.velocity = c.linear_velocity
	data["start"] = c.global_position


func _tick_ride(_delta: float) -> void:
	var c: Crawler = data["c"]
	var p: Player = G.player
	var local := c.global_transform.affine_inverse() * p.global_position
	if t > 1.0 and (absf(local.x) > 1.8 or local.z < -1.5 or local.z > 5.2 or local.y < 2.0):
		_done(false, "fell off the deck at %.1f s (local %s, crawler moved %.0f m)" % [t, local, c.global_position.distance_to(data["start"])])
		return
	if t > 20.0:
		var moved := c.global_position.distance_to(data["start"])
		_done(moved > 40.0, "rode %.0f m, ended at deck position %s" % [moved, local])


# ------------------------------------------------------------------------------------------------ drive

func _setup_drive() -> void:
	var v: Vehicles = G.vehicles
	var c: Crawler = v.crawlers[0]
	data["c"] = c
	data["start"] = c.global_position
	c.enter(G.player)
	Input.action_press("move_forward")


func _tick_drive(_delta: float) -> void:
	var c: Crawler = data["c"]
	if int(t * 2.0) != int((t - _delta) * 2.0):
		print("  drive t %.1f pos %s vel %s (%.1f m/s) grounded %d" % [t, c.global_position, c.linear_velocity, c.linear_velocity.length(), c._grounded])
	if c.cam:
		c.cam.yaw = c.global_rotation.y
	if t > 12.0:
		var moved := c.global_position.distance_to(data["start"])
		var up := c.global_transform.basis.y.dot(Vector3.UP)
		_done(moved > 60.0 and up > 0.8, "travelled %.0f m in 12 s, up %.2f" % [moved, up])


# -------------------------------------------------------------------------------------------------- fly

func _setup_fly() -> void:
	var v: Vehicles = G.vehicles
	var h: Helicopter = null
	for k in v.helis:
		if not k.ai:
			h = k
	data["h"] = h
	G.terrain.collision_now(h.global_position)
	data["start"] = h.global_position
	h.enter(G.player)
	Input.action_press("ascend")


func _tick_fly(_delta: float) -> void:
	var h: Helicopter = data["h"]
	if int(t * 2.0) != int((t - _delta) * 2.0):
		print("  fly t %.1f pos %s vel %s heading %.2f" % [t, h.global_position, h.linear_velocity, h._heading])
	if t > 6.0 and not data.has("climbed"):
		data["climbed"] = h.global_position.y - data["start"].y
		data["mid"] = h.global_position
		Input.action_release("ascend")
		Input.action_press("move_forward")
		h.cam.yaw = PI            # south, away from the citadel's towers
	if t > 14.0:
		var fwd: float = (h.global_position - (data["mid"] as Vector3)).length()
		_done(data["climbed"] > 25.0 and fwd > 150.0, "climbed %.0f m in 6 s, flew %.0f m in 8 s" % [data["climbed"], fwd])


# --------------------------------------------------------------------------------------------- dropship

func _setup_dropship() -> void:
	var d: Dropship = G.vehicles.dropships[0]
	d.state = Dropship.PARKED
	d.global_position = d.home
	d.wait = 0.0
	data["d"] = d
	d._board(G.player)


func _tick_dropship(_delta: float) -> void:
	var d: Dropship = data["d"]
	var p: Player = G.player
	if p.vehicle == null and t > 5.0:
		var dist := p.global_position.distance_to(d.lz)
		_done(dist < 80.0, "delivered after %.0f s, %.0f m from the landing zone" % [t, dist])
	elif t > 240.0:
		_done(false, "still aboard after 240 s (state %d)" % d.state)


# ----------------------------------------------------------------------------------------------- battle

func _setup_battle() -> void:
	G.battle.bench_battle()
	data["k0"] = G.battle.army.kills.duplicate()


func _tick_battle(_delta: float) -> void:
	if t > 60.0:
		var army: Army = G.battle.army
		var k: Array = army.kills
		var under := 0
		for i in army.n:
			if army.state[i] != Army.S_DEAD and army.state[i] != 255:
				if army.pos[i].y < G.world.ground_at(army.pos[i].x, army.pos[i].z) - 1.0:
					under += 1
		var ok: bool = k[0] > data["k0"][0] and k[1] > data["k0"][1] and under == 0
		_done(ok, "kills Capital %d Cinder %d, alive %d / %d, under ground %d" % [k[0], k[1], army.count_alive(0), army.count_alive(1), under])
