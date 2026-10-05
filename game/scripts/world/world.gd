class_name GameWorld
extends Node3D
## The world: sky and day-night, terrain, water, vegetation, weather, then the Capital (cities and bases),
## the armies and the vehicles. Also the benchmark camera paths and the screenshot list.

var gen: WorldGen
var sky: SkySystem
var terrain: Terrain
var water: WaterSystem
var vegetation: Node3D
var weather: Node
var cities: Node3D
var city_list: Array = []
var bases: Bases
var roads: Roads
var _focus := Vector3.ZERO


func setup(g: WorldGen) -> void:
	gen = g
	G.world = self
	sky = SkySystem.new()
	sky.name = "Sky"
	add_child(sky)
	sky.setup()
	G.sky = sky
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(gen)
	G.terrain = terrain
	water = WaterSystem.new()
	water.name = "Water"
	add_child(water)
	water.setup(gen)
	cities = Node3D.new()
	cities.name = "Capital"
	add_child(cities)
	G.cities = cities
	var capital := CapitalCity.new()
	capital.name = "Candor"
	cities.add_child(capital)
	var cs: Vector3 = gen.sites["capital"]
	capital.build(cs, 1500.0, G.seed * 3 + 1, "Candor")
	city_list.append(capital)
	_add_optional("res://scripts/world/vegetation.gd", "Vegetation", "vegetation")
	if vegetation:
		for c in city_list:
			vegetation.add_trees(c.trees)
			vegetation.exclude.append([Vector2(c.center.x, c.center.z), c.radius + 30.0])
	bases = Bases.new()
	bases.name = "Bases"
	add_child(bases)
	bases.build(gen, capital.mat)
	roads = Roads.new()
	roads.name = "Roads"
	add_child(roads)
	roads.setup(gen)
	var battle := Battle.new()
	battle.name = "Battle"
	add_child(battle)
	battle.setup()
	var combat := Combat.new()
	combat.name = "Combat"
	add_child(combat)
	combat.setup()
	var destruction := Destruction.new()
	destruction.name = "Destruction"
	add_child(destruction)
	destruction.setup()
	if "vehicles" in OS.get_environment("CAPITAL_SKIP").split(","):
		return
	var veh := Vehicles.new()
	veh.name = "Vehicles"
	add_child(veh)
	veh.setup(capital.mat)
	var hud := Hud.new()
	hud.name = "Hud"
	add_child(hud)
	if vegetation:
		for k in bases.sites:
			var s: Dictionary = bases.sites[k]
			vegetation.exclude.append([Vector2(s["pos"].x, s["pos"].z), s["radius"]])
	_add_optional("res://scripts/world/weather.gd", "Weather", "weather")
	if weather:
		G.weather = weather


func _exit_tree() -> void:
	G.reset()


func _add_optional(path: String, node_name: String, field: String) -> void:
	if not ResourceLoader.exists(path) or node_name.to_lower() in OS.get_environment("CAPITAL_SKIP").split(","):
		return
	var n: Node = load(path).new()
	n.name = node_name
	add_child(n)
	if n.has_method("setup"):
		n.setup(gen)
	set(field, n)


func is_settled() -> bool:
	return vegetation == null or vegetation.is_settled()


func focus(p: Vector3) -> void:
	_focus = p
	terrain.focus(p)
	if vegetation and vegetation.has_method("focus"):
		vegetation.focus(p)


func spawn_player() -> void:
	var sp: Vector3 = gen.sites["spawn"]
	terrain.collision_now(sp)
	var player := preload("res://scripts/player/player.gd").new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(sp.x, surface_at(sp.x, sp.z) + 0.1, sp.z)
	player.rotation.y = deg_to_rad(-70.0)
	G.player = player


## Walkable ground height (terrain, or a city podium).
func ground_at(x: float, z: float) -> float:
	for c in city_list:
		if c.in_city(x, z):
			return c.podium_y
	return gen.height_at(x, z)


func site(name: String) -> Vector3:
	return gen.sites.get(name, Vector3.ZERO)


## The top walkable surface at (x, z): the analytic ground or any static body above it (base platforms, decks,
## roofs), found by a ray from `from_h` metres down. Use for every teleport: the analytic ground alone can put
## the player inside a platform, and depenetration then pushes them down through the terrain.
func surface_at(x: float, z: float, from_h: float = 120.0) -> float:
	var g := ground_at(x, z)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, g + from_h, z), Vector3(x, g - 2.0, z))
	q.collision_mask = 1 | 4
	var h := space.intersect_ray(q)
	if not h.is_empty():
		return maxf(g, (h["position"] as Vector3).y)
	return g


## Camera point at a height above the ground.
func above(x: float, z: float, h: float) -> Vector3:
	return Vector3(x, maxf(ground_at(x, z), 0.0) + h, z)


## Benchmark segments: a city flyover, a battle and a forest walk (positions from the world's sites).
func benchmark_segments() -> Array:
	var c := site("capital")
	var f := site("forest")
	var b := site("front")
	return [
		{"name": "city", "duration": 30.0,
			"path": [above(c.x - 1800, c.z + 900, 140), above(c.x - 900, c.z + 300, 90), above(c.x - 200, c.z - 100, 70),
				above(c.x + 500, c.z - 600, 110), above(c.x + 1300, c.z - 400, 160)],
			"look": [c + Vector3(0, 80, 0), c + Vector3(200, 60, 0), c + Vector3(600, 70, -300), c + Vector3(1200, 80, -600), c + Vector3(2500, 40, 200)],
			"setup": func(): _bench_setup(10.5, "clear")},
		{"name": "battle", "duration": 30.0,
			"path": [above(b.x - 300, b.z - 350, 35), above(b.x - 120, b.z - 120, 22), above(b.x + 80, b.z + 60, 18), above(b.x + 260, b.z + 300, 30)],
			"look": [b, b + Vector3(60, 0, 40), b + Vector3(200, 0, 160), b + Vector3(500, 0, 450)],
			"setup": func(): _bench_setup(16.5, "overcast")},
		{"name": "forest", "duration": 30.0,
			"path": [above(f.x - 250, f.z - 200, 2.0), above(f.x - 100, f.z - 60, 2.0), above(f.x + 60, f.z + 40, 2.0), above(f.x + 220, f.z + 180, 2.0)],
			"look": [above(f.x - 50, f.z, 1.5), above(f.x + 100, f.z + 100, 1.5), above(f.x + 250, f.z + 200, 2.0), above(f.x + 400, f.z + 350, 2.0)],
			"setup": func(): _bench_setup(8.0, "clear")},
	]


func _park_frigate(at: Vector3) -> void:
	if G.vehicles and G.vehicles.frigates.size() > 0:
		var f: Frigate = G.vehicles.frigates[0]
		f.global_position = at
		f.yaw = 0.3
		f.rotation = Vector3(0, 0.3, 0)
		f.route = []
		f.speed = 0.0
		print("frigate parked at %s, children %d, visible %s, in tree %s" % [f.global_position, f.get_child_count(), f.is_visible_in_tree(), f.is_inside_tree()])


## A point beside road `name` at fraction `f` of its length, `di` points along it, `side` metres to the side and
## `up` metres above (camera spots that follow the road wherever world generation routes it).
func _along_road(name: String, f: float, di: int, side: float, up: float) -> Vector3:
	for r in gen.roads:
		if r["name"] == name:
			var pts: PackedVector3Array = r["pts"]
			var i := clampi(int(pts.size() * f) + di, 1, pts.size() - 2)
			var dir := (pts[i + 1] - pts[i - 1]).normalized()
			var lat := Vector3(-dir.z, 0, dir.x)
			return pts[i] + lat * side + Vector3(0, up, 0)
	return Vector3.ZERO


## A mid-height tower at the edge of Candor, for the collapse shot.
func _collapse_target() -> Vector3:
	for b in (city_list[0] as CapitalCity).buildings:
		var h: float = b["h"]
		if h > 45.0 and h < 90.0 and (b["pos"] as Vector3).distance_to((city_list[0] as CapitalCity).center) > 300.0:
			return b["pos"]
	return (city_list[0] as CapitalCity).center


func _collapse_demo() -> void:
	var at := _collapse_target()
	for b in (city_list[0] as CapitalCity).buildings:
		if b["pos"] == at and G.combat and G.combat.destruction:
			(G.combat.destruction as Destruction).collapse(city_list[0], b)
			return


func _battle_warm(seconds: float) -> void:
	if G.battle:
		G.battle.bench_battle()
		G.battle.simulate(seconds)


func _bench_setup(hour: float, wx: String) -> void:
	sky.set_hour(hour)
	if weather and weather.has_method("set_weather"):
		weather.set_weather(wx, true)
	if G.battle and G.battle.has_method("bench_battle"):
		G.battle.bench_battle()


## Screenshot list for --shots: name, camera position, look target, hour, weather.
func shot_list() -> Array:
	var c := site("capital")
	var sp := site("spawn")
	var rad := site("radar")
	var f := site("forest")
	var h := site("harbor")
	var fr := site("front")
	var ct := site("citadel")
	var fl := site("fort_lumen")
	var cc := site("cinder_camp")
	var shots := [
		{"name": "overview", "pos": above(c.x - 4200, c.z + 2600, 700), "look": c + Vector3(-600, 0, -600), "hour": 10.0, "weather": "clear"},
		{"name": "capital_noon", "pos": above(c.x - 1500, c.z + 700, 120), "look": c + Vector3(0, 60, 0), "hour": 12.5, "weather": "clear"},
		{"name": "citadel", "pos": above(ct.x + 260, ct.z + 300, 60), "look": ct + Vector3(0, 40, 0), "hour": 15.5, "weather": "clear"},
		{"name": "turret_close", "pos": ct + Vector3(-60, 14, 110), "look": ct + Vector3(-92, 12, 72), "hour": 10.5, "weather": "clear"},
		{"name": "radar_night", "pos": rad + Vector3(260, 150, 330), "look": rad + Vector3(0, 10, 0), "hour": 22.5, "weather": "clear"},
		{"name": "fort_lumen", "pos": above(fl.x + 280, fl.z + 260, 70), "look": fl, "hour": 9.5, "weather": "cloudy"},
		{"name": "cinder_camp", "pos": above(cc.x + 220, cc.z + 200, 45), "look": cc, "hour": 17.0, "weather": "clear"},
		{"name": "battle_ground", "pos": above(fr.x + 260, fr.z + 20, 1.7), "look": above(fr.x - 200, fr.z - 40, 2.0), "hour": 16.0, "weather": "overcast", "setup": func(): _battle_warm(25.0)},
		{"name": "battle_wide", "pos": above(fr.x + 420, fr.z + 380, 70), "look": fr + Vector3(0, 10, 0), "hour": 16.5, "weather": "cloudy", "setup": func(): _battle_warm(25.0)},
		{"name": "troops_lineup", "fov": 32.0, "pos": above(fr.x + 607, fr.z - 400, 1.3), "look": above(fr.x + 595, fr.z - 400, 0.9), "hour": 11.0, "weather": "clear", "setup": func(): G.battle.lineup(above(fr.x + 595, fr.z - 400, 0.0), above(fr.x + 601, fr.z - 400, 0.0))},
		{"name": "road_bridge", "pos": Vector3(1690, 46, 880), "look": Vector3(1632, 24, 774), "hour": 13.0, "weather": "clear"},
		{"name": "pass_road", "pos": _along_road("Pass Road", 0.55, -14, 9.0, 12.0), "look": _along_road("Pass Road", 0.55, 14, 0.0, 1.0), "hour": 10.0, "weather": "clear"},
		{"name": "vehicles_spawn", "pos": sp + Vector3(-6, 3.5, 30), "look": sp + Vector3(22, 1.5, 2), "hour": 10.0, "weather": "clear"},
		{"name": "frigate", "pos": ct + Vector3(-160, 300, 470), "look": ct + Vector3(0, 262, 300), "hour": 15.0, "weather": "cloudy", "setup": func(): _park_frigate(ct + Vector3(0, 262, 300))},
		{"name": "frigate_deck", "pos": ct + Vector3(-6, 272, 360), "look": ct + Vector3(0, 280, 300), "hour": 15.5, "weather": "clear", "setup": func(): _park_frigate(ct + Vector3(0, 262, 300))},
		{"name": "gunship_pad", "pos": ct + Vector3(-50, 16, 20), "look": ct + Vector3(-80, 8, -10), "hour": 11.0, "weather": "clear"},
		{"name": "horizon_test", "pos": Vector3(7000, 400, 3000), "look": Vector3(20000, 400, 3000), "hour": 12.0, "weather": "clear", "setup": func(): water.ocean.visible = false},
		{"name": "capital_top", "pos": c + Vector3(500, 420, 1), "look": c + Vector3(500, 0, 0), "hour": 12.0, "weather": "clear"},
		{"name": "capital_dusk", "pos": above(c.x - 1300, c.z + 1200, 90), "look": c + Vector3(0, 70, 0), "hour": 19.6, "weather": "clear"},
		{"name": "collapse", "pos": _collapse_target() + Vector3(-110, 50, 150), "look": _collapse_target() + Vector3(0, 22, 0), "hour": 14.0, "weather": "clear", "late": func(): _collapse_demo(), "late_frames": 40},
		{"name": "capital_night", "pos": above(c.x - 1200, c.z + 800, 110), "look": c + Vector3(0, 40, 0), "hour": 23.0, "weather": "clear"},
		{"name": "spawn_view", "pos": sp + Vector3(0, 2.0, 0), "look": c + Vector3(0, 30, 0), "hour": 9.0, "weather": "clear"},
		{"name": "mountains", "pos": above(rad.x - 900, rad.z + 1800, 260), "look": rad + Vector3(0, 400, -1800), "hour": 15.0, "weather": "clear"},
		{"name": "snow_peaks", "pos": above(rad.x + 600, rad.z - 1800, 120), "look": rad + Vector3(-600, 900, -3600), "hour": 11.0, "weather": "snow"},
		{"name": "forest_floor", "pos": above(f.x, f.z, 1.7), "look": above(f.x + 60, f.z + 30, 4.0), "hour": 9.0, "weather": "clear"},
		{"name": "shadow_test", "pos": above(f.x, f.z + 30, 3.0), "look": above(f.x, f.z - 40, 0.0), "hour": 13.0, "weather": "clear"},
		{"name": "forest_rain", "pos": above(f.x - 80, f.z - 40, 2.0), "look": above(f.x + 40, f.z + 60, 6.0), "hour": 14.0, "weather": "rain"},
		{"name": "river_valley", "pos": above(500, -1500, 60), "look": Vector3(1100, 30, -300), "hour": 8.0, "weather": "fog"},
		{"name": "coast", "pos": above(h.x + 800, h.z + 900, 25), "look": h + Vector3(-400, 20, -300), "hour": 17.5, "weather": "clear"},
		{"name": "storm_sea", "pos": Vector3(h.x + 2600, 18, h.z - 400), "look": Vector3(h.x + 6000, 0, h.z - 2000), "hour": 15.0, "weather": "storm"},
		{"name": "front_line", "pos": above(fr.x - 400, fr.z - 300, 40), "look": fr, "hour": 16.0, "weather": "overcast"},
		{"name": "weapon_view", "fps": true, "pos": above(fl.x + 60, fl.z + 90, 1.66), "look": above(fl.x, fl.z, 6.0), "hour": 10.0, "weather": "clear"},
	]
	if Settings.has_arg("only"):
		var only := String(Settings.arg("only")).split(",")
		shots = shots.filter(func(s): return s["name"] in only)
	if Settings.has_arg("shard"):
		# --shard i/n: every n-th shot starting at i (CI splits the list over parallel jobs).
		var parts := String(Settings.arg("shard")).split("/")
		var si := int(parts[0])
		var sn := maxi(1, int(parts[1]))
		var picked := []
		for j in shots.size():
			if j % sn == si:
				picked.append(shots[j])
		shots = picked
	return shots
