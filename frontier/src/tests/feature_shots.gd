extends Node
## Evidence shots for the blind critic rounds: one frame per system, taken from inside the running game with the
## HUD/menus as a player sees them. --features DIR [--only a,b]. Each scenario sets itself up, settles streaming,
## renders, saves DIR/<name>.png and cleans up after itself.

const LIST := ["town_hud", "face_closeup", "gunfight_nerve", "riding", "wildlife", "camp_night", "dialogue",
	"map", "journal", "shop", "poker", "satchel", "weapon_wheel", "mission_talk", "results_card",
	"fistfight", "cover_fight", "lasso", "holdup", "horse_closeup"]
## With --vr_sim the run takes the VR view instead: head camera, HUD/menu sheets, hands, guns (src/tests/vr_shots.gd).
const VR_LIST := ["vr_hud", "vr_menu", "vr_comfort", "vr_hands", "vr_body", "vr_gun_aim", "vr_fire", "vr_two_hand", "vr_reload",
	"vr_bolt", "vr_pump", "vr_nerve", "vr_riding",
	"vr_door"]

var main: Node
var _spawned: Array = []
var _vrs: VRShots

func run(m: Node) -> void:
	main = m
	var dir := str(Game.args["features"])
	DirAccess.make_dir_recursive_absolute(dir)
	var only := str(Game.args.get("only", ""))
	if Game.player == null:
		main._spawn_player()
		for i in 3:
			await get_tree().process_frame
	_vrs = VRShots.new(self)
	for name in (VR_LIST if Game.is_vr else LIST):
		if only != "" and not only.split(",").has(name):
			continue
		var t0 := Time.get_ticks_msec()
		await call("_" + name)
		await _capture(dir.path_join(name + ".png"))
		_cleanup()
		print("feature shot: %s (%d ms)  draws %d objects %d prims %d [%s, %s]" % [name, Time.get_ticks_msec() - t0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), RenderingServer.get_current_rendering_method(), Game.quality_name])
	get_tree().quit(0)

# ------------------------------------------------------------------ helpers
func _place(x: float, z: float, yaw_deg: float, hour: float, weather := "fair") -> Vector3:
	var p := Vector3(x, Game.world.height(x, z) + 0.2, z)
	Game.terrain.ensure_collision_at(p)
	var pl = Game.player
	pl.global_position = p
	pl.velocity = Vector3.ZERO
	pl.cam_yaw = deg_to_rad(-yaw_deg)
	pl.facing = deg_to_rad(-yaw_deg)
	pl.cam_pitch = deg_to_rad(-6.0)
	main.sky.set_time(hour)
	main.sky.set_weather(SkySystem.Weather.get(weather.to_upper(), SkySystem.Weather.FAIR), true)
	main.sky.paused = true
	main.sky.cam_attr.auto_exposure_speed = 30.0
	# --fixed_exposure X: software Vulkan (llvmpipe) mis-meters auto exposure on the player camera and washes the
	# frame out; evidence shots from the cloud box use a fixed exposure instead
	if Game.args.has("fixed_exposure"):
		main.sky.cam_attr.auto_exposure_enabled = false
		var night := hour < 5.5 or hour > 19.8
		var dusk := not night and (hour < 7.0 or hour > 18.3)
		main.sky.cam_attr.exposure_multiplier = Game.arg_f("fixed_exposure", 1.0) * (3.5 if night else (1.6 if dusk else 1.0))
	return p

func _town(id: String) -> Vector3:
	var t: Dictionary = Game.world.town(id)
	return Vector3(t.x, 0, t.z)

func _ahead(p: Vector3, yaw_deg: float, d: float, side := 0.0) -> Vector3:
	var f := Vector3(sin(deg_to_rad(yaw_deg)), 0, -cos(deg_to_rad(yaw_deg)))
	var r := Vector3(-f.z, 0, f.x)
	var q := p + f * d + r * side
	q.y = Game.world.height(q.x, q.z) + 0.3
	return q

func _human(pos: Vector3, opts: Dictionary) -> Human:
	Game.terrain.ensure_collision_at(pos)
	var h := Human.spawn(main, pos, opts)
	_spawned.append(h)
	return h

func _settle(frames := 30) -> void:
	# --settle_scale 0.2 on software renderers (seconds per frame): streaming is settled explicitly below anyway
	frames = maxi(3, int(round(frames * Game.arg_f("settle_scale", 1.0))))
	await get_tree().process_frame
	if main.scatter != null:
		main.scatter.settle_now()
	if main.vegetation != null and main.vegetation.has_method("settle_now"):
		main.vegetation.settle_now()
	for i in frames:
		await get_tree().process_frame

func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

func _cleanup() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	if Game.get("menus"):
		Game.menus.close_all()
	var pl = Game.player
	var wheel = pl.get_node_or_null("WeaponWheel")
	if wheel and wheel.open:
		wheel._close(false)
	pl.bot_driven = false
	pl.intent.aim = false
	pl.intent.fire = false
	pl.intent.melee = false
	pl.intent.lasso = false
	if pl.get("lasso") != null:
		pl.lasso.release()
	if pl.get("cover") != null and pl.cover.active:
		pl.cover.leave()
	pl.set_process(true)
	pl.set_physics_process(true)
	if pl.get("on_horse") != null and Horse.player_horse:
		Horse.player_horse.dismount()
	if Game.missions and Game.missions.cine:
		Game.missions.cine_end()

	if _vrs != null:
		_vrs.reset()

# ------------------------------------------------------------------ scenarios
func _town_hud() -> void:
	var c := _town("bitter_spring")
	var p := _place(c.x, c.z + 12.0, 110.0, 10.0)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in 7:
		var q := _ahead(p, 110.0, r.randf_range(6.0, 22.0), r.randf_range(-6.0, 6.0))
		var h := _human(q, {"seed": 300 + i, "role": ["townsfolk", "rancher", "worker", "lawman", "woman", "gambler", "townsfolk"][i], "faction": "law" if i == 3 else "civilian", "name": "Townsfolk"})
		h.intent.move_to = _ahead(q, 110.0 + r.randf_range(-90.0, 90.0), r.randf_range(4.0, 12.0))
		h.intent.speed = Human.WALK
	await _settle(90)

func _face_closeup() -> void:
	var c := _town("bitter_spring")
	var p := _place(c.x + 6.0, c.z + 18.0, 200.0, 16.0)
	var h := _human(_ahead(p, 200.0, 4.0), {"seed": 911, "role": "rancher", "faction": "civilian", "name": "Rancher"})
	await _settle(20)
	var pl = Game.player
	pl.set_process(false)
	pl.set_physics_process(false)
	var cam: Camera3D = Game.camera
	var head: Vector3 = h.visual.head_position() if h.visual.has_method("head_position") else h.global_position + Vector3(0, 1.65, 0)
	var fwd: Vector3 = -h.visual.global_basis.z
	cam.global_position = head + fwd * 1.1 + Vector3(0.25, 0.05, 0.0)
	cam.look_at(head, Vector3.UP)
	cam.fov = 35.0
	if h.visual.has_method("look_at_node"):
		h.visual.look_at_node(cam)
	if h.visual.has_method("set_expression"):
		h.visual.set_expression("smile", 0.35)
	await _settle(30)

func _gunfight_nerve() -> void:
	var p := _place(500.0, 1500.0, 60.0, 15.0)
	var foes: Array = []
	for i in 3:
		var h := _human(_ahead(p, 60.0, 18.0 + i * 4.0, -6.0 + i * 6.0), {"seed": 500 + i, "role": "gunman", "faction": "bandit", "name": "Road Agent", "weapon": "merriman_lever"})
		h.brain.aggressive = true
		h.brain.target = Game.player
		foes.append(h)
	for h in foes:
		h.brain.group = foes
	var pl = Game.player
	pl.bot_driven = true
	pl.intent.aim = true
	await _settle(60)
	if pl.nerve and pl.nerve.can_activate():
		pl.nerve.activate()
		var ray: Dictionary = pl.aim_ray()
		pl.nerve.mark(ray.origin, (foes[0].global_position + Vector3(0, 1.5, 0) - ray.origin).normalized())
	for i in 20:
		await get_tree().process_frame
	Game.camera.fov = 62.0

func _riding() -> void:
	var c := _town("bitter_spring")
	var p := _place(c.x + 60.0, c.z + 80.0, 30.0, 17.2)
	var hz: Horse = Horse.player_horse
	if hz:
		hz.global_position = p + Vector3(1.5, 0, 0)
		await _settle(5)
		hz.mount(Game.player)
	await _settle(40)

func _wildlife() -> void:
	var p := _place(900.0, 1700.0, 80.0, 8.5)
	for i in 6:
		var sp := "mule_deer" if i < 4 else "pronghorn"
		var a := Animal.spawn(main, _ahead(p, 80.0, 9.0 + i * 1.8, -4.5 + i * 1.8), sp, 40 + i)
		_spawned.append(a)
	await _settle(60)

func _camp_night() -> void:
	var cp: Dictionary = Game.world.poi("caddell_camp")
	var p := _place(cp.x + 6.0, cp.z + 6.0, 225.0, 21.5, "clear")
	await _settle(60)

func _dialogue() -> void:
	var cp: Dictionary = Game.world.poi("caddell_camp")
	var p := _place(cp.x, cp.z + 4.0, 0.0, 18.2)
	var hap := _human(_ahead(p, 0.0, 2.2), {"seed": 1, "role": "drover", "faction": "civilian", "name": "Hap Lindqvist"})
	await _settle(20)
	var md = Game.missions
	md.cine_begin()
	md.say("c1_drv_10" if md.dialogue.has("c1_drv_10") else md.dialogue.keys()[10], hap)
	await _settle(40)

## A stranger's talk mid-scene through the conversation camera: two-shot, then a cut to over Ruth's shoulder onto
## Silas Wren (letterbox, shallow focus on Forward+, the pair facing each other).
func _mission_talk() -> void:
	var cp: Dictionary = Game.world.poi("trapper_cabin_n")
	var p := _place(cp.x + 8.0, cp.z + 9.0, 0.0, 17.6)
	var wren := _human(_ahead(p, 0.0, 2.4, 0.4), {"seed": 9501, "role": "prospector", "faction": "civilian", "name": "Silas Wren"})
	await _settle(20)
	var md = Game.missions
	md.cine_begin()
	var line_a: String = "s_comet_01" if md.dialogue.has("s_comet_01") else md.dialogue.keys()[0]
	md.say_async(line_a, wren)
	await _settle(30)
	md.say_async("s_comet_02" if md.dialogue.has("s_comet_02") else line_a, Game.player)
	await _settle(30)
	md.say_async("s_comet_03" if md.dialogue.has("s_comet_03") else line_a, wren)
	await _settle(45)

## The results card at the end of a main mission: time, accuracy, head shots, the optional objectives and a medal.
func _results_card() -> void:
	var c := _town("bitter_spring")
	_place(c.x, c.z + 30.0, 180.0, 17.0)
	await _settle(15)
	var pres = Game.get_meta("presentation") if Game.has_meta("presentation") else null
	if pres == null:
		return
	var r: Dictionary = pres.rate("c3_fork", {"time": 431.0, "shots": 23, "hits": 15, "headshots": 4, "damage": 38.0, "civilians": 0},
		{"fork_quiet": true, "cutter_fate": "jailed"})
	r["title"] = "The Dry Fork"
	var cl := CanvasLayer.new()
	cl.layer = 14
	add_child(cl)
	cl.add_child(pres.results_panel(r))
	_spawned.append(cl)
	await _settle(10)

func _map() -> void:
	_place(_town("bitter_spring").x, _town("bitter_spring").z, 0.0, 12.0)
	if Game.get("menus"):
		Game.menus.set_waypoint(_town("port_linden"))
		Game.menus.open_map()
	await _settle(20)

func _journal() -> void:
	var md = Game.missions
	if md and md.completed.is_empty():
		for path in MissionDirector.MISSIONS.slice(0, 12):
			var m = load(path).new()
			md.completed.append(m.id)          # a journal with a few chapters written in it
	if Game.get("menus"):
		Game.menus.open_journal()
	await _settle(15)

func _shop() -> void:
	var shops := get_tree().get_nodes_in_group("interactable").filter(func(n): return n.has_method("sell_all") and n.kind == "gunsmith")
	if shops.size() > 0:
		_place(shops[0].global_position.x + 2.0, shops[0].global_position.z, 270.0, 13.0)
		await _settle(10)
		shops[0].open_ui()
	await _settle(15)

func _poker() -> void:
	var c := _town("port_linden")
	_place(c.x, c.z, 0.0, 21.0)
	var pk = load("res://src/minigames/poker.gd").new()
	_spawned.append(pk)
	add_child(pk)
	Game.state.add_money(10.0)
	pk.play({"force_ui": true, "pace": 1.0, "buyin": 5.0, "dealer": "The dealer", "players": [
		{"name": "Del Arceneaux", "style": "bluffer", "stack": 20.0}, {"name": "Hask", "style": "tight", "stack": 18.0},
		{"name": "Merrow", "style": "loose", "stack": 15.0}]})
	await _settle(150)

func _satchel() -> void:
	Game.state.add_item("pelt_mule_deer_q3")
	Game.state.add_item("fish_rainbow_trout", 2)
	Satchel.open()
	await _settle(15)

func _weapon_wheel() -> void:
	var c := _town("bitter_spring")
	_place(c.x + 30.0, c.z + 40.0, 60.0, 15.0)
	await _settle(10)
	var wheel = Game.player.get_node_or_null("WeaponWheel")
	if wheel:
		wheel._open()
		wheel._aim = Vector2(120, -60)
		wheel._pick()
		wheel._ctl.queue_redraw()
	await _settle(10)

## A street fistfight in Bitter Spring, side-on, Ruth's cross landing while townsfolk gather to watch.
func _fistfight() -> void:
	var c := _town("bitter_spring")
	var p := _place(c.x, c.z + 14.0, 110.0, 12.5)
	var pl = Game.player
	pl.bot_driven = true
	pl.gun.drawn = false
	var to := _ahead(p, 110.0, 1.15)
	var h := _human(to, {"seed": 515, "role": "rancher", "faction": "civilian", "name": "Brawler", "bravery": 0.95})
	h.facing = deg_to_rad(-110.0) + PI
	var r := RandomNumberGenerator.new()
	r.seed = 21
	for i in 5:                                   # onlookers in a loose ring, facing the fight
		var a := r.randf_range(-1.0, 1.0) + (PI if i % 2 == 0 else 0.0)
		var q := (p + to) * 0.5 + Vector3(cos(a), 0, sin(a)) * r.randf_range(4.5, 7.0)
		q.y = Game.world.height(q.x, q.z) + 0.3
		var o := _human(q, {"seed": 340 + i, "role": ["townsfolk", "worker", "woman", "gambler", "townsfolk"][i], "faction": "civilian", "name": "Onlooker"})
		var d: Vector3 = (p + to) * 0.5 - q
		o.facing = atan2(-d.x, -d.z)
		if o.brain.has_method("watch"):
			o.brain.watch((p + to) * 0.5, 60.0)
	await _settle(40)
	pl.facing = deg_to_rad(-110.0)
	pl.cam_yaw = pl.facing + deg_to_rad(75.0)     # side-on
	pl.cam_pitch = deg_to_rad(-4.0)
	pl.intent.melee = true
	for i in 9:                                   # mid-swing
		await get_tree().process_frame

## A gunfight from cover: Ruth tucked against a Bitter Spring storefront beside its door, popping out to aim at
## two road agents in the street.
func _cover_fight() -> void:
	var c := _town("bitter_spring")
	var st = main.get("settlements")
	var door: TownDoor = st.nearest_door(Vector3(-526.4, Game.world.height(-526.4, -252.9), -252.9), 60.0) if st != null else null
	if door == null:
		door = st.nearest_door(Vector3(c.x, Game.world.height(c.x, c.z), c.z), 200.0) if st != null else null
	if door == null:
		return
	var out := -door.global_basis.z
	out.y = 0.0
	out = out.normalized()
	var along := door.global_basis.x
	along.y = 0.0
	along = along.normalized()
	var spot := door.global_transform * Vector3(door.width * 0.5 * door.hinge_sign, 0.0, 0.0) + along * (door.width + 1.4) + out * 0.7
	var yaw_out := rad_to_deg(atan2(out.x, -out.z))
	_place(spot.x, spot.z, yaw_out + 180.0, 15.5)
	var pl = Game.player
	pl.bot_driven = true
	await _settle(10)
	pl.cover.try_enter(-out)
	var foes: Array = []
	for i in 2:
		var q := spot + out * (14.0 + i * 5.0) + along * (-3.0 + i * 7.0)
		q.y = Game.world.height(q.x, q.z) + 0.3
		var h := _human(q, {"seed": 560 + i, "role": "gunman", "faction": "bandit", "name": "Road Agent", "weapon": "lockhart_sa"})
		h.brain.aggressive = true
		h.brain.target = pl
		foes.append(h)
	await _settle(40)
	var d: Vector3 = foes[0].global_position - pl.global_position
	pl.cam_yaw = atan2(-d.x, -d.z)
	pl.cam_pitch = deg_to_rad(-3.0)
	pl.gun.drawn = true
	pl.intent.aim = true
	await _settle(25)

## The lasso: a runaway caught at nine metres on open range, the rope taut as he tries to bolt.
func _lasso() -> void:
	var c := _town("bitter_spring")
	var o: Vector3 = load("res://src/tests/combat_bot.gd")._arena(Game.world, Vector3(c.x + 220.0, 0.0, c.z + 260.0))
	var p := _place(o.x, o.z, 0.0, 17.8)
	var pl = Game.player
	pl.bot_driven = true
	pl.gun.drawn = false
	var h := _human(_ahead(p, 0.0, 9.0), {"seed": 811, "role": "gunman", "faction": "bandit", "name": "Runaway", "bravery": 0.2})
	await _settle(30)
	pl.intent.lasso = true
	for i in 4:
		await get_tree().physics_frame
	h.brain.state = h.brain.State.FLEE
	for i in 50:
		h.intent.move_to = h.global_position + Vector3(0, 0, -40.0)
		h.intent.speed = Human.SPRINT
		await get_tree().physics_frame
	pl.cam_yaw = deg_to_rad(55.0)                 # three-quarter view across the rope
	pl.cam_pitch = deg_to_rad(-8.0)
	await _settle(4)

## A stagecoach held up on the Coldwater road: the coach stopped, crew and passengers out with their hands up,
## Ruth covering them with her revolver.
func _holdup() -> void:
	var hd = Game.get_meta("holdups") if Game.has_meta("holdups") else null
	if hd == null:
		return
	hd.enabled = false
	var road_p := Mission.road_point("bitter_spring", "coldwater", 0.45)
	_place(road_p.x + 6.0, road_p.z, 0.0, 16.4)
	await _settle(20)
	var v: Dictionary = hd.spawn_stage(Game.player.global_position, 45.0, 7.0)
	if v.is_empty():
		return
	var pl = Game.player
	pl.bot_driven = true
	pl.gun.drawn = true
	var wt := 0
	while wt < 900 and hd.aim_point(v).distance_to(pl.global_position) > 22.0:
		await get_tree().physics_frame
		wt += 1
	await hd.holdup(v)
	for h in v.people + v.crew.map(func(cr): return cr.h):
		if is_instance_valid(h):
			_spawned.append(h)
	await _settle(90)
	var d: Vector3 = v.stopped_at - pl.global_position
	pl.facing = atan2(-d.x, -d.z)
	pl.cam_yaw = pl.facing + deg_to_rad(18.0)
	pl.cam_pitch = deg_to_rad(-5.0)
	pl.intent.aim = true
	await _settle(25)

## Ruth's horse up close in golden light (coat, mane, tack).
func _horse_closeup() -> void:
	var cp: Dictionary = Game.world.poi("caddell_camp")
	var p := _place(cp.x + 14.0, cp.z - 10.0, 300.0, 17.4)
	var hz: Horse = Horse.player_horse
	if hz == null:
		return
	var at := _ahead(p, 300.0, 4.5)
	hz.global_position = at
	hz.velocity = Vector3.ZERO
	hz.rotation.y = deg_to_rad(-300.0) + PI * 0.5      # broadside to the camera
	await _settle(30)
	var pl = Game.player
	pl.set_process(false)
	pl.set_physics_process(false)
	var cam: Camera3D = Game.camera
	var side: Vector3 = hz.global_basis.x.normalized()
	cam.global_position = hz.global_position + side * 3.6 + Vector3(0, 1.55, 0) - hz.global_basis.z * 0.4
	cam.look_at(hz.global_position + Vector3(0, 1.25, 0) - hz.global_basis.z * 0.3, Vector3.UP)
	cam.fov = 40.0
	await _settle(20)

# ------------------------------------------------------------------ VR (--vr_sim; scenes in vr_shots.gd)
func _ground(x: float, z: float) -> float:
	return Game.world.height(x, z)

func _vr_target(pos: Vector3, seed: int) -> Node3D:
	var h := _human(pos + Vector3(0, 0.3, 0), {"seed": seed, "role": "gunman", "faction": "bandit", "name": "Road Agent", "weapon": "merriman_lever"})
	return h

func _vr_hud() -> void:
	await _town_hud()
	await _vrs.hud(110.0)

func _vr_menu() -> void:
	var c := _town("bitter_spring")
	_place(c.x + 30.0, c.z + 40.0, 60.0, 15.0)
	await _vrs.menu(60.0)

func _vr_hands() -> void:
	var c := _town("bitter_spring")
	_place(c.x + 30.0, c.z + 40.0, 60.0, 15.0)
	await _settle(10)
	await _vrs.hands(60.0)

func _vr_gun_aim() -> void:
	_place(500.0, 1500.0, 60.0, 15.0)
	await _settle(10)
	await _vrs.gun_aim(60.0)

func _vr_fire() -> void:
	_place(500.0, 1500.0, 60.0, 15.0)
	await _settle(10)
	await _vrs.gun_aim(60.0, true)

func _vr_two_hand() -> void:
	_place(500.0, 1500.0, 60.0, 15.0)
	await _settle(10)
	await _vrs.two_hand(60.0)

func _vr_reload() -> void:
	var c := _town("bitter_spring")
	_place(c.x + 30.0, c.z + 40.0, 60.0, 15.0)
	await _settle(10)
	await _vrs.reload(60.0)

func _vr_nerve() -> void:
	_place(500.0, 1500.0, 60.0, 15.0)
	await _settle(10)
	await _vrs.nerve(60.0)

func _vr_riding() -> void:
	await _riding()
	await _vrs.riding()

func _vr_comfort() -> void:
	var c := _town("bitter_spring")
	_place(c.x + 30.0, c.z + 40.0, 60.0, 15.0)
	await _vrs.comfort(60.0)

func _vr_body() -> void:
	var c := _town("bitter_spring")
	_place(c.x + 30.0, c.z + 40.0, 60.0, 15.0)
	await _settle(10)
	await _vrs.body(60.0)

func _vr_bolt() -> void:
	_place(500.0, 1500.0, 60.0, 15.0)
	await _settle(10)
	await _vrs.bolt_reload(60.0)

func _vr_pump() -> void:
	_place(500.0, 1500.0, 60.0, 15.0)
	await _settle(10)
	await _vrs.pump_reload(60.0)

func _vr_door() -> void:
	var c := _town("bitter_spring")
	var st = main.get("settlements")
	var door: TownDoor = st.nearest_door(Vector3(c.x, Game.world.height(c.x, c.z), c.z), 200.0) if st != null else null
	if door == null:
		return
	var front := door.global_transform * Vector3(door.width * 0.5 * door.hinge_sign, 0.0, -1.0)
	var fz := door.global_basis.z                 # face the door from its -Z side
	var yaw := rad_to_deg(atan2(fz.x, -fz.z))
	_place(front.x, front.z, yaw, 11.0)
	await _settle(20)
	await _vrs.reach(yaw, door.global_transform * Vector3(door.width * 0.85 * door.hinge_sign, 1.0, -0.05), false)
