extends Node3D
## Boots the Sable River country: world data, terrain, sky, water, vegetation, settlements, actors, UI.
## Modes (command line, see docs/status/frontier.md): normal play, --shot/--tour (screenshots), --bot (automated
## playtests with oracles), --benchmark (perf numbers to ~/Library/Logs/Frontier/benchmark.json).

var world: WorldData
var terrain: Terrain
var sky: SkySystem
var camera: Camera3D
var water: Node3D
var vegetation: Node3D
var settlements: Node3D
var scatter: Node3D

func _ready() -> void:
	Game.main = self
	var t0 := Time.get_ticks_msec()
	world = WorldData.new()
	if not world.load_all():
		push_error("cannot start without world data")
		get_tree().quit(2)
		return
	Game.world = world
	_apply_viewport_quality()
	camera = Camera3D.new()
	camera.name = "MainCamera"
	camera.fov = 62.0
	camera.near = 0.08
	camera.far = 12000.0
	add_child(camera)
	camera.make_current()
	Game.camera = camera
	sky = SkySystem.new()
	sky.name = "Sky"
	add_child(sky)
	sky.setup(Game.quality)
	print("boot: %s %d ms" % ["sky", Time.get_ticks_msec() - t0])
	camera.attributes = sky.cam_attr
	Game.sky = sky
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(world, camera)
	print("boot: %s %d ms" % ["terrain", Time.get_ticks_msec() - t0])
	terrain.set_quality(Game.quality.terrain_range)
	Game.terrain = terrain
	water = load("res://src/world/water.gd").new()
	water.name = "Water"
	add_child(water)
	water.setup(world)
	print("boot: %s %d ms" % ["water", Time.get_ticks_msec() - t0])
	vegetation = load("res://src/world/vegetation.gd").new()
	vegetation.name = "Vegetation"
	add_child(vegetation)
	vegetation.setup(world, camera)
	print("boot: %s %d ms" % ["vegetation", Time.get_ticks_msec() - t0])
	scatter = load("res://src/world/scatter.gd").new()
	scatter.name = "Scatter"
	add_child(scatter)
	scatter.setup(world, camera)
	settlements = load("res://src/world/settlements.gd").new()
	settlements.name = "Settlements"
	add_child(settlements)
	settlements.setup(world)
	print("boot: %s %d ms" % ["settlements", Time.get_ticks_msec() - t0])
	print("boot: world built in %d ms" % (Time.get_ticks_msec() - t0))
	var ws := WorldState.new()
	ws.name = "WorldState"
	add_child(ws)
	var pop = load("res://src/ai/population.gd").new()
	pop.name = "Population"
	add_child(pop)
	var wl = load("res://src/ai/wildlife.gd").new()
	wl.name = "Wildlife"
	add_child(wl)
	var camp = load("res://src/ai/camp.gd").new()
	camp.name = "Camp"
	add_child(camp)
	var md := MissionDirector.new()
	md.name = "Missions"
	add_child(md)
	if Game.args.has("time"):
		sky.set_time(Game.arg_f("time", 9.0))
	if Game.args.has("weather"):
		sky.set_weather(SkySystem.Weather.get(str(Game.args["weather"]).to_upper(), SkySystem.Weather.FAIR), true)
	Game.world_ready.emit()
	if Game.args.has("shot") or Game.args.has("tour"):
		var shots = load("res://src/tests/shots.gd").new()
		add_child(shots)
		shots.run(self)
	elif Game.args.has("bot") or Game.args.has("benchmark"):
		_spawn_player()
		var bots = load("res://src/tests/bot_runner.gd").new()
		add_child(bots)
		bots.run(self)
	else:
		_spawn_player()
		if not Game.args.has("free_roam"):
			_start_story.call_deferred()

func _start_story() -> void:
	await get_tree().create_timer(0.5).timeout
	var avail: Array = Game.missions.available()
	if avail.size() > 0:
		Game.missions.start(avail[0])

func _spawn_player() -> void:
	var town := world.town("bitter_spring")
	var spawn := Vector3(town.x + 40.0, 0.0, town.z + 60.0)
	if Game.args.has("spawn"):
		var p: PackedStringArray = str(Game.args["spawn"]).split(",")
		spawn = Vector3(float(p[0]), 0.0, float(p[1]))
	spawn.y = world.height(spawn.x, spawn.z) + 1.2
	terrain.ensure_collision_at(spawn)
	var player = load("res://src/actors/player.gd").new()
	player.name = "Player"
	add_child(player)
	player.global_position = spawn
	player.setup(camera)
	terrain.foci.append(player)
	Game.player = player

func _apply_viewport_quality() -> void:
	var vp := get_viewport()
	var q := Game.quality
	var scale: float = q.render_scale
	if Game.args.has("render_scale"):
		scale = Game.arg_f("render_scale", scale)
	var up: String = q.upscale
	var metal := RenderingServer.get_current_rendering_driver_name().to_lower().contains("metal")
	vp.scaling_3d_scale = scale
	if scale >= 0.999 or up == "none":
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	elif up.begins_with("metalfx") and metal:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL if up == "metalfx_temporal" else Viewport.SCALING_3D_MODE_METALFX_SPATIAL
	elif up == "fsr" or RenderingServer.get_current_rendering_method() != "forward_plus":
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	vp.use_taa = q.taa
	vp.msaa_3d = Viewport.MSAA_DISABLED if q.msaa == 0 else (Viewport.MSAA_2X if q.msaa == 2 else Viewport.MSAA_4X)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA if (not q.taa and scale >= 0.999) else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = 1.0 / maxf(q.lod_bias, 0.1)
	RenderingServer.directional_shadow_atlas_set_size(q.shadow_size, true)
