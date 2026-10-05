extends Node
## --scenario NAME[,NAME...]: scripted play through the real game loop (headless is fine), each with an oracle.
##   ride      stand on the rear deck of an AI crawler driving its road for 20 s: the player must stay aboard
##   drive     enter a crawler, hold forward for 12 s: it must travel > 60 m and stay upright
##   fly       enter the gunship, climb 6 s then fly forward 8 s: altitude and distance must grow
##   dropship  board a dropship: it must deliver the passenger near the landing zone within 240 s
##   battle    run the front for 60 s: both sides must fire and take casualties, nobody stuck under ground
##   weapons   on foot: the carbine fires at its rate with view climb; a rocket launches and explodes on the ground
##   destroy   shell a tower until it falls: it must fracture into falling rigid pieces and lose its collision
##   parked    the spawn's empty crawlers must not move between 5 s and 35 s (they crept 0.4 m per 30 s)
##   forest_drive  drive a crawler 12 s along the densest heading in the forest: it must fell trees, not stop
##             (it stopped dead against the first trunk: 5 m)
##   trees     walk into a broadleaf trunk in the forest for 3 s: the player must stop at its bark; a soldier
##             placed inside a trunk is pushed out
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
	if t > 400.0:
		_done(false, "watchdog: still running after 400 s")
		return
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
	v._prune()
	var h: Helicopter = null
	for k in v.helis:
		if not k.ai:
			h = k
	if h == null:
		data["h"] = null
		return
	data["h"] = h
	G.terrain.collision_now(h.global_position)
	data["start"] = h.global_position
	h.enter(G.player)
	Input.action_press("ascend")


func _tick_fly(_delta: float) -> void:
	if data["h"] == null or not is_instance_valid(data["h"]):
		_done(false, "the player's gunship is gone (destroyed before the scenario)")
		return
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
	G.player.invulnerable = true      # the front and the harbour are under fire; this checks the ground
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
		G.player.invulnerable = false
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


# ------------------------------------------------------------------------------------------ forest drive

## Drive a crawler straight into dense forest for 12 s. Trunks became solid; a crawler should push through
## (felling trees), not stop dead at the first one.
func _setup_forest_drive() -> void:
	_leave_vehicle()
	var veg: Node = G.world.vegetation
	var f: Vector3 = G.world.site("forest")
	var c := Vector2i(floori(f.x / 128.0), floori(f.z / 128.0))
	var trees: Array = veg.cell_trees(c)
	# A clear start (no trunk within 6 m).
	var start := Vector3.ZERO
	var found := false
	for k in 200:
		var p := Vector3(c.x * 128.0 + 20.0 + (k % 10) * 9.0, 0.0, c.y * 128.0 + 20.0 + (k / 10) * 4.5)
		var clear := true
		for tr in trees:
			var o: Vector3 = (tr[2] as Transform3D).origin
			if tr[0] != TreeBuilder.BUSH and Vector2(o.x - p.x, o.z - p.z).length() < 6.0:
				clear = false
				break
		if clear and G.gen.slope_at(p.x, p.z) < 0.2:
			start = p
			found = true
			break
	if not found:
		_done(false, "no clear start in the forest cell")
		return
	# Heading: of eight, the one with the most trunks within 2.5 m of the next 120 m (the first try ran through a
	# clearing: one trunk in 249 m).
	var best_dir := Vector3.RIGHT
	var best_n := -1
	var near_trees: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			near_trees.append_array(veg.cell_trees(c + Vector2i(dx, dz)))
	for h in 8:
		var d := Vector3(cos(h * TAU / 8.0), 0.0, sin(h * TAU / 8.0))
		var n := 0
		for tr in near_trees:
			if tr[0] == TreeBuilder.BUSH:
				continue
			var o: Vector3 = (tr[2] as Transform3D).origin
			var rel := Vector3(o.x - start.x, 0.0, o.z - start.z)
			var along := rel.dot(d)
			if along > 6.0 and along < 120.0 and (rel - d * along).length() < 2.5:
				n += 1
		if n > best_n:
			best_n = n
			best_dir = d
	var ahead := best_n
	data["dir"] = best_dir
	var cr: Crawler = G.vehicles.crawlers[0]
	G.world.focus(start)
	G.terrain.collision_now(start)
	start.y = G.world.surface_at(start.x, start.z) + 1.6
	cr.global_transform = Transform3D(Basis(Vector3.UP, atan2(-best_dir.x, -best_dir.z)), start)
	cr.linear_velocity = Vector3.ZERO
	cr.angular_velocity = Vector3.ZERO
	cr.enter(G.player)
	data["c"] = cr
	data["start"] = start
	data["ahead"] = ahead
	data["phase"] = 0
	data["felled0"] = int(veg.get("felled")) if veg.get("felled") != null else 0


func _tick_forest_drive(_delta: float) -> void:
	var cr: Crawler = data["c"]
	if cr.cam:
		cr.cam.yaw = cr.global_rotation.y
	if data["phase"] == 0 and t > 2.0:
		Input.action_press("move_forward")
		data["phase"] = 1
		data["t1"] = t
	elif data["phase"] == 1 and t <= 14.0 and OS.get_environment("FD_TRACE") == "1" and int(t * 2.0) != int((t - _delta) * 2.0):
		cr.contact_monitor = true
		cr.max_contacts_reported = 8
		print("  fd t %.1f pos %s v %.1f m/s contacts %s" % [t, cr.global_position, cr.linear_velocity.length(),
			cr.get_colliding_bodies().map(func(n): return n.name)])
	elif data["phase"] == 1 and t > 14.0:
		Input.action_release("move_forward")
		var a: Vector3 = data["start"]
		var b := cr.global_position
		var moved := Vector2(b.x - a.x, b.z - a.z).length()
		var up := cr.global_transform.basis.y.dot(Vector3.UP)
		var veg: Node = G.world.vegetation
		var felled := (int(veg.get("felled")) if veg.get("felled") != null else 0) - int(data["felled0"])
		# Trunks the drive line actually crossed (every cell along it, as generated): felled + still standing.
		var on_path := 0
		var standing := 0
		var seg := Vector2(b.x - a.x, b.z - a.z)
		var cells := {}
		for k2 in 40:
			var q := a.lerp(b, k2 / 39.0)
			cells[Vector2i(floori(q.x / 128.0), floori(q.z / 128.0))] = true
		for ck in cells:
			for tr in veg.cell_trees(ck):
				if tr[0] == TreeBuilder.BUSH:
					continue
				var o: Vector3 = (tr[2] as Transform3D).origin
				var rel := Vector2(o.x - a.x, o.z - a.z)
				var u := clampf(rel.dot(seg) / seg.length_squared(), 0.0, 1.0)
				if (rel - seg * u).length() < 2.5:
					on_path += 1
					var tk := Vector2i(roundi(o.x * 10.0), roundi(o.z * 10.0))
					if not (veg.get("_felled") as Dictionary).has(tk):
						standing += 1
		data["ahead"] = "%d on the path, %d of them not felled" % [on_path, standing]
		# Open ground covers 116 m in 12 s (drive); through forest it must keep going: half of that, upright.
		_done(moved > 55.0 and up > 0.8, "travelled %.0f m in 12 s into forest (trunks within 2.5 m of the line: %s), felled %d trees, up %.2f" % [moved, data["ahead"], felled, up])


# ----------------------------------------------------------------------------------------------- parked

## Empty vehicles must stay where they were parked (the vehicles_spawn shot found the spawn crawlers gone).
func _setup_parked() -> void:
	_leave_vehicle()
	var sp: Vector3 = G.world.site("spawn")
	var list: Array = []
	for c in G.vehicles.crawlers:
		if c.driver == null and not c.has_meta("patrol") and (c as Node3D).global_position.distance_to(sp) < 80.0:
			list.append([c, (c as Node3D).global_position])
	data["list"] = list
	# The player stands nearby (the collision window and trunk bodies follow the player).
	var p: Player = G.player
	p.global_position = Vector3(sp.x - 6.0, G.world.surface_at(sp.x - 6.0, sp.z + 30.0) + 0.05, sp.z + 30.0)
	p.velocity = Vector3.ZERO
	G.terrain.collision_now(p.global_position)
	if list.is_empty():
		_done(false, "no parked crawler near the spawn")


func _tick_parked(_delta: float) -> void:
	# From 5 s (after the drop onto the ground at spawn) to 35 s.
	if t < 5.0:
		return
	if not data.has("t5"):
		data["t5"] = true
		for e in data["list"]:
			if is_instance_valid(e[0]):
				e[1] = (e[0] as Node3D).global_position
		return
	if t < 35.0:
		return
	var worst := 0.0
	var msg: Array = []
	for e in data["list"]:
		var c: Node3D = e[0]
		if not is_instance_valid(c):
			msg.append("destroyed")
			worst = 1e9
			continue
		var d := c.global_position.distance_to(e[1])
		worst = maxf(worst, d)
		msg.append("%.2f m (up %.2f)" % [d, c.global_transform.basis.y.y])
	_done(worst < 0.05, "%d spawn crawlers moved %s in 30 s" % [(data["list"] as Array).size(), ", ".join(msg)])


# ------------------------------------------------------------------------------------------------ trees

## Trees had no collision: the player walked through trunks. Walk at a lone broadleaf in the forest.
func _setup_trees() -> void:
	_leave_vehicle()
	G.player.invulnerable = true
	var veg: Node = G.world.vegetation
	var f: Vector3 = G.world.site("forest")
	var c := Vector2i(floori(f.x / 128.0), floori(f.z / 128.0))
	var trees: Array = veg.cell_trees(c)
	var pick: Array = []
	for tr in trees:
		if tr[0] != TreeBuilder.BROADLEAF:
			continue
		var o: Vector3 = (tr[2] as Transform3D).origin
		# Open ground in front (no other trunk within 6 m) and gentle slope, so only this trunk is in the way.
		var crowded := false
		for u in trees:
			var q: Vector3 = (u[2] as Transform3D).origin
			if u != tr and u[0] != TreeBuilder.BUSH and Vector2(q.x - o.x, q.z - o.z).length() < 6.0:
				crowded = true
				break
		if not crowded and G.gen.slope_at(o.x, o.z) < 0.25:
			pick = tr
			break
	if pick.is_empty():
		_done(false, "no lone broadleaf in the forest cell")
		return
	var o: Vector3 = (pick[2] as Transform3D).origin
	var start := Vector3(o.x + 4.0, 0.0, o.z)
	var p: Player = G.player
	G.world.focus(start)
	G.terrain.collision_now(start)
	p.global_position = Vector3(start.x, G.world.surface_at(start.x, start.z) + 0.05, start.z)
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(4.0, 0.0)      # facing -x, at the trunk
	p.pitch = 0.0
	data["o"] = o
	var radii: Array = (veg.get_script() as Script).get_script_constant_map()["TRUNK_R"]
	data["r"] = float(radii[TreeBuilder.BROADLEAF]) * (pick[2] as Transform3D).basis.get_scale().x
	data["min_x"] = 1e9
	data["phase"] = 0


func _tick_trees(_delta: float) -> void:
	var p: Player = G.player
	var o: Vector3 = data["o"]
	if data["phase"] == 0 and t > 1.0:
		p.rotation.y = atan2(4.0, 0.0)
		Input.action_press("move_forward")
		data["phase"] = 1
	elif data["phase"] == 1:
		data["min_x"] = minf(data["min_x"], p.global_position.x - o.x)
		if t > 4.0:
			Input.action_release("move_forward")
			var r: float = data["r"]
			var veg: Node = G.world.vegetation
			var inside: Vector3 = veg.avoid(o + Vector3(0.1, 0.0, 0.05), 0.35)
			var out_d := Vector2(inside.x - o.x, inside.z - o.z).length()
			var gap: float = data["min_x"]
			# The capsule (0.35 m) must stop at the bark: centre at least r + 0.2 from the trunk axis, on our side.
			var ok := gap > r + 0.2 and out_d >= r + 0.34
			G.player.invulnerable = false
			_done(ok, "trunk radius %.2f m: closest approach %.2f m from its axis (needs > r + 0.2; without trunk collision the player walked through), soldier pushed out to %.2f m" % [r, gap, out_d])


# ------------------------------------------------------------------------------------------------- menu

## The pause menu: Esc / Menu opens it and pauses the game, a preset change applies, B / Esc closes it.
func _setup_menu() -> void:
	var ev := InputEventAction.new()
	ev.action = "pause"
	ev.pressed = true
	Input.parse_input_event(ev)
	data["phase"] = 0
	data["preset0"] = Settings.preset


func _tick_menu(_delta: float) -> void:
	var m: PauseMenu = G.main.get_node_or_null("PauseMenu")
	if m == null:
		_done(false, "no pause menu in normal play")
		return
	if data["phase"] == 0 and t > 0.3:
		data["opened"] = m.open and get_tree().paused
		Settings.set_preset("Low")
		data["phase"] = 1
	elif data["phase"] == 1 and t > 0.6:
		data["low"] = Settings.q["shadow_dist"] == Settings.PRESETS["Low"]["shadow_dist"]
		Settings.set_preset(String(data["preset0"]))
		var ev := InputEventAction.new()
		ev.action = "ui_cancel"
		ev.pressed = true
		Input.parse_input_event(ev)
		data["phase"] = 2
	elif data["phase"] == 2 and t > 0.9:
		var closed := not m.open and not get_tree().paused
		_done(bool(data["opened"]) and bool(data["low"]) and closed, "opened and paused %s, preset applied %s, closed and resumed %s" % [data["opened"], data["low"], closed])
