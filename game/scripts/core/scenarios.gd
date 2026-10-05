extends Node
## --scenario NAME[,NAME...]: scripted play through the real game loop (headless is fine), each with an oracle.
##   ride      stand on the rear deck of an AI crawler driving its road for 20 s: the player must stay aboard
##   drive     enter a crawler, hold forward for 12 s: it must travel > 60 m and stay upright
##   fly       enter the gunship, climb 6 s then fly forward 8 s: altitude and distance must grow
##   dropship  board a dropship: it must deliver the passenger near the landing zone within 240 s
##   battle    run the front for 60 s: both sides must fire and take casualties, nobody stuck under ground
##   weapons   on foot: the carbine fires at its rate with view climb; a rocket launches and explodes on the ground
##   destroy   shell a tower until it falls: it must fracture into falling rigid pieces and lose its collision
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
	_leave_vehicle()
	_next()


## Out of any vehicle, even one that refuses (a gunship in flight): each scenario starts on foot.
func _leave_vehicle() -> void:
	var p: Player = G.player
	if p == null or p.vehicle == null:
		return
	var v: Node = p.vehicle
	if v.has_method("exit"):
		v.exit(p)
	if p.vehicle == null:
		return
	for prop in ["pilot", "driver"]:
		if prop in v:
			v.set(prop, null)
	if "cam" in v and v.get("cam") != null:
		(v.get("cam") as Node).queue_free()
		v.set("cam", null)
	var q: Vector3 = (v as Node3D).global_position
	p.exit_vehicle(Vector3(q.x, G.world.surface_at(q.x, q.z) + 0.1, q.z))


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
	if OS.get_environment("RIDE_TRACE") != "" and int(t * 2.0) != int((t - _delta) * 2.0):
		var e := c.global_transform.basis.get_euler()
		if t > 13.9 and t < 14.8:
			var q := PhysicsShapeQueryParameters3D.new()
			var sp := SphereShape3D.new()
			sp.radius = 5.0
			q.shape = sp
			q.transform = Transform3D(Basis.IDENTITY, c.global_position + Vector3(0, 1, 0))
			q.exclude = [c.get_rid(), p.get_rid()]
			for h in c.get_world_3d().direct_space_state.intersect_shape(q, 8):
				var col: Object = h["collider"]
				print("    touching %s" % [col.get_path() if col is Node else col])
		print("  ride t %.1f pos %s local %s roll %.1f pitch %.1f yaw rate %.2f speed %.1f on floor %s" % [t, c.global_position, local, rad_to_deg(e.z), rad_to_deg(e.x), c.angular_velocity.y, c.linear_velocity.length(), p.is_on_floor()])
	if t > 1.0 and (absf(local.x) > 1.8 or local.z < -1.5 or local.z > 5.2 or local.y < 2.0):
		_done(false, "fell off the deck at %.1f s (local %s, crawler moved %.0f m)" % [t, local, c.global_position.distance_to(data["start"])])
		return
	if t > 1.5 and not data.has("landed"):
		data["landed"] = local
	if t > 20.0:
		var moved := c.global_position.distance_to(data["start"])
		var drift := Vector2(local.x - data["landed"].x, local.z - data["landed"].z).length()
		_done(moved > 40.0 and drift < 0.5, "rode %.0f m, drifted %.2f m on the deck (ended at %s)" % [moved, drift, local])


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
		# Horizontal distance only, and on the ground: a crawler falling through the world once passed this.
		var a: Vector3 = data["start"]
		var b := c.global_position
		var moved := Vector2(b.x - a.x, b.z - a.z).length()
		var up := c.global_transform.basis.y.dot(Vector3.UP)
		var above := b.y - G.world.ground_at(b.x, b.z)
		_done(moved > 60.0 and moved < 400.0 and up > 0.8 and absf(above) < 5.0, "travelled %.0f m in 12 s, up %.2f, %.1f m above ground" % [moved, up, above])


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


# ---------------------------------------------------------------------------------------------- weapons

func _setup_weapons() -> void:
	var p: Player = G.player
	# Its own spot (earlier scenarios leave the player anywhere): the spawn apron, facing open ground.
	_leave_vehicle()
	var sp: Vector3 = G.world.site("spawn")
	G.terrain.collision_now(sp)
	p.global_position = Vector3(sp.x, G.world.surface_at(sp.x, sp.z) + 0.05, sp.z)
	p.velocity = Vector3.ZERO
	p.rotation.y = deg_to_rad(-70.0)
	p.pitch = 0.0
	var w: Weapons = p.weapons
	data["w"] = w
	data["ammo0"] = w.ammo[0]
	data["pitch0"] = p.pitch
	data["phase"] = 0
	data["shots_seen"] = 0
	data["max_pitch"] = p.pitch
	w._select(0)
	w.cooldown = 0.0
	Input.action_press("fire")


func _tick_weapons(_delta: float) -> void:
	var p: Player = G.player
	var w: Weapons = data["w"]
	data["max_pitch"] = maxf(data["max_pitch"], p.pitch)
	if data["phase"] == 0 and t > 1.5:
		Input.action_release("fire")
		data["fired"] = int(data["ammo0"]) - int(w.ammo[0])
		data["climb"] = rad_to_deg(float(data["max_pitch"]) - float(data["pitch0"]))
		# Rocket into the ground 25 m ahead.
		p.pitch = deg_to_rad(-6.0)
		w._select(3)
		w.cooldown = 0.0
		data["phase"] = 1
		data["r0"] = G.fx.rockets_fired
	elif data["phase"] == 1 and t > 2.0:
		Input.action_press("fire")
		data["phase"] = 2
	elif data["phase"] == 2 and t > 2.1:
		Input.action_release("fire")
		data["rocket_ammo"] = w.ammo[3]
		data["rockets_live"] = G.fx.rockets_fired - int(data["r0"])
		data["phase"] = 3
	elif data["phase"] == 3 and (t > 8.0 or (t > 2.5 and not _player_rocket_flying())):
		# Rocket counts are global (gunships and soldiers fire them too): the launcher's own ammo says it fired.
		var fired: int = data["fired"]
		var gone := not _player_rocket_flying()
		var ok: bool = fired >= 12 and fired <= 22 and float(data["climb"]) > 3.0 and int(data["rocket_ammo"]) == 0 and int(data["rockets_live"]) >= 1 and gone
		_done(ok, "carbine fired %d rounds in 1.5 s, view climbed %.1f deg; launcher empty %s, its rocket exploded %s" % [fired, data["climb"], int(data["rocket_ammo"]) == 0, gone])


func _player_rocket_flying() -> bool:
	var rid := G.player.get_rid()
	for r in G.fx.rockets:
		if (r[5] as Array).has(rid):
			return true
	return false


# ---------------------------------------------------------------------------------------------- destroy

func _setup_destroy() -> void:
	var city: CapitalCity = G.world.city_list[0]
	var best: Dictionary = {}
	for b in city.buildings:
		var h: float = b["h"]
		if b["alive"] and h > 45.0 and h < 90.0 and (b["pos"] as Vector3).distance_to(city.center) > 300.0:
			best = b
			break
	data["b"] = best
	data["city"] = city
	var bp: Vector3 = best["pos"]
	var p: Player = G.player
	p.global_position = bp + Vector3(0, 0, 220)
	G.terrain.collision_now(bp)
	data["shots"] = 0
	data["dead_t"] = -1.0
	var old := {}
	for d in (G.combat.destruction as Destruction).debris:
		old[d[0]] = true
	data["old"] = old
	data["shot_t"] = 0.0
	print("  destroy: building %d h %.0f at %s, hp %.0f" % [best["id"], best["h"], bp, 600.0 + float(best["h"]) * 25.0])


func _tick_destroy(_delta: float) -> void:
	var b: Dictionary = data["b"]
	var bp: Vector3 = b["pos"]
	var de: Destruction = G.combat.destruction
	if b["alive"]:
		if t - float(data["shot_t"]) > 0.4:
			data["shot_t"] = t
			data["shots"] += 1
			var top := bp + Vector3(randf_range(-4, 4), float(b["h"]) * randf_range(0.3, 0.9) + 60.0, randf_range(-4, 4))
			G.combat.shell(top, Vector3.DOWN, 300.0, 2.0, 1, [])
		if t > 20.0:
			_done(false, "still standing after %d shells (hp %.0f)" % [data["shots"], b.get("hp", -1.0)])
		return
	if float(data["dead_t"]) < 0.0:
		data["dead_t"] = t
		var top_y := -1e9
		var top: RigidBody3D = null
		var old: Dictionary = data["old"]
		var mine := 0
		for d in de.debris:
			if not is_instance_valid(d[0]) or old.has(d[0]):
				continue
			var rb: RigidBody3D = d[0]
			mine += 1
			if rb.global_position.y > top_y:
				top_y = rb.global_position.y
				top = rb
		data["top"] = top
		data["top_y"] = top_y
		data["n"] = mine
		print("  destroy: collapsed after %d shells, %d pieces, top piece at %.0f m" % [data["shots"], mine, top_y - bp.y])
		return
	if t - float(data["dead_t"]) > 8.0:
		var top: Variant = data["top"]
		var drop := float(data["top_y"]) - (top as RigidBody3D).global_position.y if is_instance_valid(top) else 0.0
		var bad := 0
		for d in de.debris:
			if not is_instance_valid(d[0]):
				continue
			var rb: RigidBody3D = d[0]
			var q := rb.global_position
			if is_nan(q.x) or is_nan(q.y) or q.y < G.world.ground_at(q.x, q.z) - 6.0:
				bad += 1
		var body_gone: bool = not b.has("body") or not is_instance_valid(b["body"])
		var ok: bool = int(data["n"]) >= 8 and drop > 10.0 and bad == 0 and body_gone
		_done(ok, "%d pieces, top piece fell %.0f m in 8 s, %d lost/NaN, collision removed %s" % [data["n"], drop, bad, body_gone])


# ------------------------------------------------------------------------------------------------ stand

## Teleport the player to sites around the map: each time they must stand on the ground after 3 s.
func _setup_stand() -> void:
	data["sites"] = ["fort_lumen", "citadel", "front", "forest", "radar", "harbor", "spawn"]
	data["i"] = -1
	data["bad"] = []
	data["t0"] = 0.0
	_stand_next()


func _stand_next() -> void:
	data["i"] += 1
	if data["i"] >= (data["sites"] as Array).size():
		return
	var nm: String = data["sites"][data["i"]]
	var s: Vector3 = G.world.site(nm) + Vector3(60, 0, 90)
	var p: Player = G.player
	p.global_position = Vector3(s.x, G.world.surface_at(s.x, s.z) + 0.05, s.z)
	p.velocity = Vector3.ZERO
	G.terrain.collision_now(p.global_position)
	data["t0"] = t


func _tick_stand(_delta: float) -> void:
	var sites: Array = data["sites"]
	if data["i"] >= sites.size():
		var bad: Array = data["bad"]
		_done(bad.is_empty(), "%d sites, fell or stuck at: %s" % [sites.size(), ", ".join(bad)])
		return
	if t - float(data["t0"]) > 3.0:
		var p: Player = G.player
		var q := p.global_position
		var g0: float = G.world.ground_at(q.x, q.z)
		var g: float = G.world.surface_at(q.x, q.z, maxf(q.y + 1.0 - g0, 1.0))
		print("  stand %s: y %.2f surface %.2f" % [sites[data["i"]], q.y, g])
		if absf(q.y - g) > 1.0:
			(data["bad"] as Array).append("%s (%.1f m off)" % [sites[data["i"]], q.y - g])
		_stand_next()
