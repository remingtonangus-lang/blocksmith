extends Node
## Screenshot harness. --shot out.png [--at x,z] [--up 1.7] [--yaw deg] [--pitch deg] [--fov deg] [--frames n]
## or --tour DIR (named vantage points in TOUR). Waits for streaming/shaders, saves PNGs, prints timings, quits.

const TOUR := [
	# name, x, z, height above ground, yaw (deg, 0 = north, 90 = east), pitch, hour, weather
	["bitter_spring_street", "town:bitter_spring", 0, 1.7, 110, -2, 10.0, "fair"],
	["river_valley_vista", -380, -400, 60, 140, -8, 16.5, "fair"],
	["kestrel_range", -1400, -900, 25, -30, 6, 8.0, "clear"],
	["ocotillo_mesas", -2200, 1900, 30, 200, -4, 17.6, "clear"],
	["plains_noon", 500, 1500, 2.0, 60, 0, 12.5, "fair"],
	["lake_agnes", 2700, 300, 12, 90, -3, 7.0, "fog"],
	["night_town", "town:bitter_spring", 0, 1.7, 290, 2, 22.5, "clear"],
	["storm_plains", 200, 900, 2.0, 30, 2, 15.0, "storm"],
]

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
	var t0 := Time.get_ticks_msec()
	# let streaming (tree chunks, collision, grass) settle before counting frames
	var veg = main.vegetation
	await get_tree().process_frame
	if veg != null and veg.has_method("settle_now"):
		veg.settle_now()
		var inst := 0
		for r in veg._regions.values():
			inst += r.multimesh.instance_count
		print("vegetation: %d regions, %d trees, %d near chunks, %d grass cells" % [veg._regions.size(), inst, veg._near.size(), veg._grass_cells.size()])
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
	print("shot: %s at (%.0f, %.0f, %.0f) yaw %.0f pitch %.0f %.1fh %s  ~%.1f ms/frame" % [path, px, cam.global_position.y, pz, yaw, pitch, hour, weather, ft])
