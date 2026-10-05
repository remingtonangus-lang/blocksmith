extends Node
## Screenshot harness. --shot out.png [--at x,z] [--up 1.7] [--yaw deg] [--pitch deg] [--fov deg] [--frames n]
## or --tour DIR (named vantage points in TOUR). Waits for streaming/shaders, saves PNGs, prints timings, quits.
## --horse D [--horse_seed S --horse_breed B --horse_yaw DEG --horse_anim A]: stand a horse D metres in front of
## the camera (side-on by default) for in-world horse shots.

const TOUR := [
	# name, x, z, height above ground, yaw (deg, 0 = north, 90 = east), pitch, hour, weather
	["bitter_spring_street", "town:bitter_spring", 0, 1.7, 110, -2, 10.0, "fair"],
	["river_valley_vista", -380, -400, 60, 140, -8, 16.5, "fair"],
	["kestrel_range", -1400, -900, 25, -30, 6, 8.0, "clear"],
	["ocotillo_mesas", -2200, 1900, 30, 200, -4, 17.6, "clear"],
	["plains_noon", 500, 1500, 2.0, 60, 0, 12.5, "fair"],
	["lake_agnes", 2700, 300, 12, 90, -3, 8.5, "fair"],
	["river_fog_morning", -300, -300, 6.0, 160, -2, 6.6, "fog"],
	["night_town", "town:bitter_spring", 0, 1.7, 290, 2, 22.5, "clear"],
	["storm_plains", 200, 900, 2.0, 30, 2, 15.0, "storm"],
	# settlements (src/world/settlements.gd): street level, boardwalk, interiors, depot, distant views, night
	["bs_main_street", -526.4, -252.9, 1.7, 108, -1, 10.5, "fair"],
	["bs_boardwalk", -479.2, -252.7, 2.05, 100, -4, 16.0, "fair"],
	["bs_saloon_interior", -481.4, -256.4, 2.1, 30, -6, 11.0, "fair"],
	["bs_store_interior", -446.1, -244.8, 2.1, 25, -8, 11.0, "fair"],
	["bs_sheriff_interior", -506.1, -234.6, 2.1, 205, -6, 11.0, "fair"],
	["bs_depot", -348.3, -110.4, 1.7, 0, 2, 9.0, "fair"],
	["bs_aerial", -600.0, -330.0, 70.0, 70, -24, 15.0, "fair"],
	["bs_from_1km", 332.0, 495.0, 180.0, -45, -10, 16.5, "clear"],
	["bs_night_street", -526.4, -252.9, 1.7, 108, -1, 21.5, "clear"],
	["bs_golden_street", -526.4, -252.9, 1.7, 108, -1, 16.8, "clear"],
	["cw_street", -1843.0, -2113.5, 1.7, 55, 0, 15.0, "fair"],
	["cw_aerial", -1880.0, -2050.0, 50.0, 45, -22, 14.0, "fair"],
	["mw_street", -2280.0, 1137.0, 1.7, 95, 0, 17.0, "clear"],
	["mw_aerial", -2100.0, 1250.0, 45.0, -35, -20, 15.0, "clear"],
	["pl_street", 2720.7, -127.3, 1.7, 172, 0, 16.0, "fair"],
	["pl_aerial", 2600.0, 200.0, 70.0, 42, -22, 15.5, "fair"],
	["pl_waterfront", 2990.0, 60.0, 8.0, 100, -12, 9.5, "fair"],
	["camp_dusk", -790.0, -760.0, 1.7, 34, -6, 19.4, "clear"],
	["ranch", 335.0, 1170.0, 2.0, -10, -3, 9.0, "fair"],
	["mission_ruin", -3031.0, 2668.0, 1.7, 180, 6, 17.5, "clear"],
	# town life (src/ai/population.gd + routine.gd): residents placed by the hour, then a few seconds of walking
	["town_morning", -516.0, -251.5, 1.7, 108, -2, 8.75, "fair"],
	["saloon_night", -481.4, -256.4, 2.1, 30, -8, 21.5, "clear"],
	["store_clerk", -444.8, -248.8, 2.1, -101, -9, 10.5, "fair"],
	["town_noon_aerial", -540.0, -290.0, 26.0, 60, -22, 12.4, "fair"],
]
const TOWN_LIFE := ["town_morning", "saloon_night", "store_clerk", "town_noon_aerial"]

var main: Node

func run(m: Node) -> void:
	main = m
	if Game.args.has("tour"):
		var dir := str(Game.args["tour"])
		DirAccess.make_dir_recursive_absolute(dir)
		var only := str(Game.args.get("only", ""))
		for s in TOUR:
			if only != "" and not only.split(",").has(s[0]):
				continue
			await _shot(dir.path_join(s[0] + ".png"), s[1], s[2], s[3], s[4], s[5], s[6], s[7])
	else:
		var at: PackedStringArray = str(Game.args.get("at", "town:bitter_spring")).split(",")
		var x = at[0] if at.size() == 1 else float(at[0])
		var z = 0.0 if at.size() == 1 else float(at[1])
		await _shot(str(Game.args["shot"]), x, z, Game.arg_f("up", 1.7), Game.arg_f("yaw", 90.0), Game.arg_f("pitch", -3.0),
			Game.arg_f("time", main.sky.hours), str(Game.args.get("weather", "")))
	get_tree().quit(0)

func _shot(path: String, x, z, up: float, yaw: float, pitch: float, hour: float, weather: String) -> void:
	var w: WorldData = Game.world
	var px: float
	var pz: float
	if typeof(x) == TYPE_STRING and str(x).begins_with("town:"):
		var t := w.town(str(x).substr(5))
		if t.is_empty():
			t = w.poi(str(x).substr(5))
		px = t.x
		pz = t.z + float(z)
	else:
		px = float(x)
		pz = float(z)
	if Game.args.has("player") and Game.player == null:
		main._spawn_player()
		for i in 3:
			await get_tree().process_frame
	if Game.player != null:
		Game.player.global_position = Vector3(px, w.height(px, pz) + 0.2, pz)
		Game.player.cam_yaw = deg_to_rad(-yaw)
		Game.player.facing = deg_to_rad(-yaw)
		Game.player.cam_pitch = deg_to_rad(pitch)
		# --aim: Ruth draws and aims (over-the-shoulder aim camera, visible gun); --weapon N picks the gun slot;
		# --fire fires once a few frames before the capture (muzzle flash + smoke)
		if Game.args.has("aim") and Game.player.get("gun") != null:
			Game.player.bot_driven = true
			Game.player.gun.select(int(Game.args.get("weapon", 0)))
			Game.player.gun.drawn = true
			Game.player.gun.cooldown = 0.0
			Game.player.intent.aim = true
			if Game.player.get("holder") != null:
				Game.player.holder.snap = true
	var cam: Camera3D = Game.camera
	var gy := w.height(px, pz)
	var wl := w.water_level(px, pz)
	cam.global_position = Vector3(px, maxf(gy, wl) + up, pz)
	cam.rotation = Vector3(deg_to_rad(pitch), deg_to_rad(-yaw), 0.0)
	if Game.args.has("fov"):
		cam.fov = Game.arg_f("fov", 62.0)
	main.sky.set_time(hour)
	if weather != "":
		main.sky.set_weather(SkySystem.Weather.get(weather.to_upper(), SkySystem.Weather.FAIR), true)
	main.sky.paused = true
	main.sky.cam_attr.auto_exposure_speed = 30.0     # converge within the few frames a shot renders
	if Game.args.has("horse"):
		_place_horse(cam)
	var t0 := Time.get_ticks_msec()
	# let streaming (tree chunks, collision, grass) settle before counting frames
	var veg = main.vegetation
	await get_tree().process_frame
	if main.scatter != null:
		main.scatter.settle_now()
	if veg != null and veg.has_method("settle_now"):
		veg.settle_now()
		var inst := 0
		for r in veg._regions.values():
			inst += r.multimesh.instance_count
		print("vegetation: %d regions, %d trees, %d near chunks, %d grass cells" % [veg._regions.size(), inst, veg._near.size(), veg._grass_cells.size()])
	var stl = main.get("settlements")
	if stl != null and stl.has_method("settle_now"):
		stl.settle_now()
	if Game.population != null and (Game.args.has("town_life") or path.get_file().get_basename() in TOWN_LIFE):
		await _town_life(cam.global_position)
	var frames := int(Game.args.get("frames", 24))
	if Game.args.has("menu") and Game.get("menus") != null:
		var mn = Game.menus
		match str(Game.args["menu"]):
			"pause": mn.open_pause()
			"map": mn.open_map()
			"journal": mn.open_journal()
			"settings": mn.open_settings()
	for i in frames:
		if Game.args.has("fire") and Game.player != null and i == maxi(frames - 2, 0):
			Game.player.intent.fire = true
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	var ft := (Time.get_ticks_msec() - t0) / float(frames + 1)
	print("render: %d draw calls, %d objects, %dk primitives (%s)" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000, path.get_file()])
	print("shot: %s at (%.0f, %.0f, %.0f) yaw %.0f pitch %.0f %.1fh %s  ~%.1f ms/frame" % [path, px, cam.global_position.y, pz, yaw, pitch, hour, weather, ft])
	if Game.args.has("dc_breakdown"):
		await _dc_breakdown()

## --dc_breakdown: draw calls per settlement node category (hide one category at a time, render, compare).
func _dc_breakdown() -> void:
	var stl = main.get("settlements")
	var cats := {"Ext": [], "ExtShadow": [], "Int": [], "IP": [], "OP": [], "Doors": [], "Far": [], "Wheel": [], "Rail": [],
		"People": []}
	for n in stl.find_children("*", "GeometryInstance3D", true, false):
		var nm := str(n.name)
		var k := "Rail" if nm.begins_with("Track") else nm.get_slice("_", 0)
		if cats.has(k):
			cats[k].append(n)
	for h in get_tree().get_nodes_in_group("humans"):
		cats["People"].append(h)
	var base := await _dc_frame()
	var parts: PackedStringArray = []
	for k in cats:
		if cats[k].is_empty():
			continue
		for n in cats[k]:
			n.visible = false
		var dc := await _dc_frame()
		for n in cats[k]:
			n.visible = true
		parts.append("%s %d (%d nodes)" % [k, base - dc, cats[k].size()])
	print("draw calls: total %d | %s" % [base, ", ".join(parts)])

func _dc_frame() -> int:
	for i in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)

## Bake the town's navmesh, place residents where the hour puts them, start the strollers walking, run a few
## seconds of physics (--sim S, default 4) so the street has people mid-stride.
func _town_life(p: Vector3) -> void:
	var stl = main.get("settlements")
	var tid: String = stl.town_at(p, 60.0) if stl != null else ""
	if tid == "":
		return
	Game.args["memlog"] = true
	stl.mem("town life: start")
	stl.bake_navigation_now(tid)
	stl.mem("town life: navmesh")
	var t0 := Time.get_ticks_msec()
	while not stl.navigation_ready(tid) and Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
	for i in 3:
		await get_tree().physics_frame
	Game.population.fill_now()
	stl.mem("town life: residents spawned")
	for i in 10:
		await get_tree().physics_frame
	Game.population.stir(0.5)
	var n := int(Game.arg_f("sim", 4.0) * 60.0)
	for i in n:
		await get_tree().physics_frame
	var m: Dictionary = Game.population.town_metrics()
	print("town life: %d residents, %d walking, %d chats" % [m.residents, Game.population.walking(), m.chats])

var _horse: Horse

func _place_horse(cam: Camera3D) -> void:
	var w: WorldData = Game.world
	if _horse == null:
		_horse = Horse.spawn(int(Game.args.get("horse_seed", 1899)), str(Game.args.get("horse_breed", "quarter")))
		main.add_child(_horse)
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var p := cam.global_position + fwd * Game.arg_f("horse", 8.0)
	p.y = w.height(p.x, p.z)
	Game.terrain.ensure_collision_at(p)
	_horse.global_position = p
	var face := atan2(-fwd.x, -fwd.z) + deg_to_rad(Game.arg_f("horse_yaw", 90.0))
	_horse.yaw = face
	_horse.rotation.y = face
	if Game.args.has("horse_anim") and _horse.visual.anim_player:
		_horse.set_physics_process(false)
		_horse.visual.set_locomotion(str(Game.args["horse_anim"]), 1.0)
