extends Node
## Evidence shots for the blind critic rounds: one frame per system, taken from inside the running game with the
## HUD/menus as a player sees them. --features DIR [--only a,b]. Each scenario sets itself up, settles streaming,
## renders, saves DIR/<name>.png and cleans up after itself.

const LIST := ["town_hud", "face_closeup", "gunfight_nerve", "riding", "wildlife", "camp_night", "dialogue",
	"map", "journal", "shop", "poker", "satchel", "weapon_wheel"]
## With --vr_sim the run takes the VR view instead: head camera, HUD/menu sheets, hands, guns (src/tests/vr_shots.gd).
const VR_LIST := ["vr_hud", "vr_menu", "vr_hands", "vr_gun_aim", "vr_fire", "vr_two_hand", "vr_reload", "vr_nerve", "vr_riding",
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
