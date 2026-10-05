extends RefCounted
## Weapon care and ammunition oracle (headless): condition wears per shot; a fouled gun throws wider, reloads slower
## and jams; gun oil (satchel) restores it; Express rounds load on the next reload and hit harder; shotgun slugs make
## one heavy projectile; condition and ammo choice survive a save/load.

static func run(runner: Node) -> Dictionary:
	var res := {"bot": "armory", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "checks": {}}
	var tree := runner.get_tree()
	var p = Game.player
	var g: GunHandler = p.gun
	var st = Game.state
	var was_pos: Vector3 = p.global_position
	p.global_position = Vector3(0, 3500.0, 0)     # shots go into empty sky
	await tree.physics_frame
	g.select(0)
	var id := g.weapon_id()
	g.drawn = true
	g.clean_all()
	var clean_spread: float = g.effective_def().aim_spread
	# 1. wear per shot
	for i in 6:
		g.cooldown = 0.0
		g.clip[id] = 6
		g.fire(p.global_position, Vector3.UP, true)
	var c6 := g.cond(id)
	res.checks["cond_after_6"] = snappedf(c6, 0.001)
	if c6 >= 1.0:
		_fail(res, "six shots left the gun spotless")
	# 2. fouled: wider, jams
	g.condition[id] = 0.05
	var foul_spread: float = g.effective_def().aim_spread
	res.checks["spread_clean_vs_fouled"] = [snappedf(clean_spread, 0.01), snappedf(foul_spread, 0.01)]
	if foul_spread <= clean_spread * 1.3:
		_fail(res, "a fouled gun is not less accurate (%.2f vs %.2f)" % [foul_spread, clean_spread])
	var j0 := g.jams
	for i in 120:
		g.cooldown = 0.0
		g.clip[id] = 6
		g.condition[id] = 0.05
		g.fire(p.global_position, Vector3.UP, true)
	res.checks["jams_in_120"] = g.jams - j0
	if g.jams - j0 < 3:
		_fail(res, "a fouled gun never jams (%d in 120)" % (g.jams - j0))
	# 3. gun oil
	st.add_item("gun_oil")
	if not st.use_item("gun_oil") or g.cond(id) < 0.999:
		_fail(res, "gun oil did not clean the gun (%.2f)" % g.cond(id))
	# 4. Express rounds: next reload loads them, more damage
	var base: String = g.def().ammo
	var std_dmg: float = g.effective_def().damage
	g.ammo[base + "_express"] = 12
	var nxt := g.cycle_ammo()
	g.clip[id] = 0
	g.reloading = false
	g.start_reload()
	for i in 600:
		await tree.process_frame
		if not g.reloading:
			break
	res.checks["loaded"] = g.loaded_variant(id)
	var exp_dmg: float = g.effective_def().damage
	res.checks["damage_std_vs_express"] = [snappedf(std_dmg, 0.1), snappedf(exp_dmg, 0.1)]
	if nxt != base + "_express" or g.loaded_variant(id) != base + "_express" or exp_dmg <= std_dmg:
		_fail(res, "Express rounds did not load or hit harder (%s, %s, %.1f vs %.1f)" % [nxt, g.loaded_variant(id), exp_dmg, std_dmg])
	# 5. slugs
	if not g.weapons.has("calder_double"):
		g.weapons.append("calder_double")
	g.select(g.weapons.find("calder_double"))
	g.ammo["shotgun_slug"] = 8
	g.loaded["calder_double"] = "shotgun_slug"
	var sd := g.effective_def()
	res.checks["slug"] = {"pellets": sd.pellets, "damage": snappedf(float(sd.damage), 0.1), "range": snappedf(float(sd.range), 0.1)}
	if int(sd.pellets) != 1 or float(sd.damage) < 50.0:
		_fail(res, "slugs are not one heavy projectile (%s)" % str(res.checks.slug))
	g.select(0)
	# 6. save / load keeps condition and ammo choice
	g.condition[id] = 0.42
	if st.save_game("armory_test"):
		g.condition[id] = 1.0
		g.ammo_sel = {}
		st.load_game("armory_test")
		var ok_c := absf(float(g.condition.get(id, 1.0)) - 0.42) < 0.01
		var ok_s := str(g.ammo_sel.get(base, "")) == base + "_express"
		res.checks["save_load"] = ok_c and ok_s
		if not (ok_c and ok_s):
			_fail(res, "save/load lost gun state (condition %s, selection %s)" % [str(g.condition.get(id)), str(g.ammo_sel)])
	g.clean_all()
	g.loaded = {}
	g.ammo_sel = {}
	p.global_position = was_pos
	await tree.physics_frame
	print("  armory: %s" % str(res.checks))
	return res

static func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)
	print("  armory FAIL: " + why)
