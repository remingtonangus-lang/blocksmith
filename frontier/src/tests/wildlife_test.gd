extends Node3D
## Wildlife look-dev harness (no world needed): neutral lit ground; renders a species line-up, per-species close-ups
## and gait strips, and runs the gait oracle on every species' gait animations. Saves PNGs and quits.
##   godot --path frontier --resolution 1280x540 res://scenes/wildlife_test.tscn -- --out DIR
##       [--only lineup,closeups,strips,actions] [--species a,b] [--quit 600]
## Prints one "GAIT <species>/<gait>" line per gait and "WILDLIFE ORACLE PASS|FAIL".

const SPECIES := ["bison", "elk", "mule_deer", "pronghorn", "black_bear", "cougar", "wolf", "coyote", "fox", "raccoon", "rabbit"]

var out_dir := "user://wildlife_shots"
var cam: Camera3D
var sun: DirectionalLight3D
var nodes: Array = []

func _ready() -> void:
	var t := Timer.new()
	t.wait_time = Game.arg_f("quit", 900.0)
	t.one_shot = true
	t.timeout.connect(func():
		print("WILDLIFE_TEST: quit timeout")
		get_tree().quit(3))
	add_child(t)
	t.start()
	out_dir = str(Game.args.get("out", out_dir))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_env()
	await get_tree().process_frame
	var ok := _oracle()
	var only := str(Game.args.get("only", "lineup,closeups,strips,actions"))
	for s in only.split(","):
		match s:
			"lineup": await _lineup()
			"closeups": await _closeups()
			"strips": await _strips()
			"actions": await _actions()
	print("WILDLIFE ORACLE %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _species() -> Array:
	var list: Array = SPECIES
	if Game.args.has("species"):
		list = Array(str(Game.args["species"]).split(","))
	return list.filter(func(sp): return HorseVisual.model_path_for(sp) != "")

func _env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.32, 0.45, 0.68)
	psm.sky_horizon_color = Color(0.70, 0.72, 0.74)
	psm.ground_horizon_color = Color(0.55, 0.52, 0.48)
	psm.ground_bottom_color = Color(0.25, 0.22, 0.2)
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_energy = 2.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	sun.rotation = Vector3(deg_to_rad(-42), deg_to_rad(-35), 0)
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.46, 0.41, 0.34)
	gm.roughness = 0.95
	g.material_override = gm
	add_child(g)
	cam = Camera3D.new()
	add_child(cam)
	cam.make_current()

func _clear() -> void:
	for n in nodes:
		n.queue_free()
	nodes.clear()

func _animal(sp: String, pos: Vector3, yaw: float, seed := 7) -> HorseVisual:
	var v := HorseVisual.new()
	add_child(v)
	v.build(AnimalCoats.roll(sp, seed), sp)
	v.position = pos
	v.rotation.y = yaw
	if v.ik:
		v.ik.ground_fn = func(_x: float, _z: float) -> float: return 0.0
	nodes.append(v)
	return v

func _pose(v: HorseVisual, anim: String, t: float) -> void:
	if v.tree:
		v.tree.active = false
	if v.anim_player and v.anim_player.has_animation(anim):
		v.anim_player.play(anim)
		v.anim_player.seek(t, true)
		v.anim_player.pause()

func _look(from: Vector3, at: Vector3, fov := 40.0) -> void:
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = fov
	cam.global_position = from
	cam.look_at(at, Vector3.UP)

func _save(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := out_dir.path_join(name + ".png")
	img.save_png(p)
	print("WILDLIFE_TEST: wrote ", p)

func _length(v: HorseVisual) -> float:
	return float(v.meta.get("rest", {}).get("length", 1.5))

## Side-on line-up of every species (largest first), each facing left.
func _lineup() -> void:
	_clear()
	await get_tree().process_frame
	var z := 0.0
	var maxh := 0.0
	for sp in _species():
		var v := _animal(sp, Vector3.ZERO, PI * 0.5)       # facing -X... turned to face the camera's left
		var L := _length(v)
		v.position = Vector3(0, 0, z + L * 0.5)
		z += L + 0.5
		maxh = maxf(maxh, float(v.meta.get("rest", {}).get("withers_height", 1.0)))
		_pose(v, "idle", 0.0)
	var mid := z * 0.5
	var w := z + 1.0
	_look(Vector3(-w * 0.62, maxh * 0.9, mid), Vector3(0, maxh * 0.45, mid), 52.0)
	await _save("lineup")

func _closeups() -> void:
	for sp in _species():
		_clear()
		await get_tree().process_frame
		var v := _animal(sp, Vector3.ZERO, 0.0)
		_pose(v, "idle", 0.0)
		var H := float(v.meta.get("rest", {}).get("withers_height", 1.0))
		var L := _length(v)
		_look(Vector3(-L * 1.25, H * 0.95, -L * 0.85), Vector3(0, H * 0.6, -L * 0.1), 40.0)
		await _save(sp + "_34")
		var an: Dictionary = v.meta.get("anchors", {})
		if an.has("poll"):
			var p: Array = an.poll
			var n: Array = an.nose
			var hc := (Vector3(p[0], p[2], -p[1]) + Vector3(n[0], n[2], -n[1])) * 0.5
			var hl := Vector3(p[0], p[2], -p[1]).distance_to(Vector3(n[0], n[2], -n[1]))
			_look(hc + Vector3(-hl * 2.4, hl * 0.6, -hl * 1.6), hc, 38.0)
			await _save(sp + "_head")

## Gait strips: 5 phases of each gait side by side, per species.
func _strips() -> void:
	for sp in _species():
		_clear()
		await get_tree().process_frame
		var probe := _animal(sp, Vector3(500, 0, 0), 0.0)
		var gaits: Dictionary = probe.meta.get("gaits", {})
		var L := _length(probe)
		var H := float(probe.meta.get("rest", {}).get("withers_height", 1.0))
		var row := 0
		for g in gaits:
			for i in 5:
				var v := _animal(sp, Vector3(row * H * 2.6, 0, (i - 2) * L * 1.15), 0.0)
				var len := v.action_length(g)
				_pose(v, g, len * float(i) / 5.0)
			row += 1
		var w := L * 1.15 * 5.0
		_look(Vector3(-w * 0.75 - row * H, H * 2.0 + row * H * 0.9, 0), Vector3(row * H * 1.1, H * 0.3, 0), 50.0)
		await _save(sp + "_gaits")

func _actions() -> void:
	for sp in _species():
		_clear()
		await get_tree().process_frame
		var probe := _animal(sp, Vector3(500, 0, 0), 0.0)
		var L := _length(probe)
		var H := float(probe.meta.get("rest", {}).get("withers_height", 1.0))
		var acts := ["graze", "alert", "look", "flee_start", "attack", "death", "carcass"]
		var k := 0
		for a in acts:
			if probe.anim_player == null or not probe.anim_player.has_animation(a):
				continue
			var v := _animal(sp, Vector3(0, 0, (k - 3) * L * 1.2), 0.0)
			_pose(v, a, v.action_length(a) * (0.5 if a in ["flee_start", "attack"] else 0.9))
			k += 1
		_look(Vector3(-L * 5.0, H * 2.2, 0), Vector3(0, H * 0.4, 0), 45.0)
		await _save(sp + "_actions")

## Gait oracle on every species' gait cycles (bare animation, in-place ground at the authored speed).
func _oracle() -> bool:
	var ok := true
	for sp in _species():
		var v := _animal(sp, Vector3(800, 0, 0), 0.0)
		for g in v.meta.get("gaits", {}):
			var r := HorseGaitOracle.analyse_animation(v, g)
			print(HorseGaitOracle.format_line("%s/%s" % [sp, g], r).replace("GAIT %s/%s" % [sp, g], "GAIT %s/%s" % [sp, g]))
			if not r.get("ok", false):
				ok = false
	_clear()
	return ok
