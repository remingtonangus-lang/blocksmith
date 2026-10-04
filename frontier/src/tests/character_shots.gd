extends Node3D
## Character lineup / portrait harness (scene res://scenes/character_shots.tscn).
## godot --path frontier --resolution 960x540 res://scenes/character_shots.tscn -- --out DIR
##   [--ids a,b,c | --seeds 0..9] [--mode lineup|faces|anim|all] [--anim walk] [--t 0.4] [--frames 6]
## Spawns characters through CharacterFactory, frames them, renders and saves PNGs, then quits (hard timeout).

var out_dir := "user://shots"
var frames := 6

func _ready() -> void:
	get_tree().create_timer(float(Game.args.get("timeout", 900))).timeout.connect(func(): get_tree().quit(2))
	out_dir = str(Game.args.get("out", out_dir))
	frames = int(Game.args.get("frames", 6))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_setup_world()
	var chars := _spawn_all()
	if chars.is_empty():
		push_error("character_shots: nothing to show")
		get_tree().quit(1)
		return
	var mode := str(Game.args.get("mode", "all"))
	if mode in ["lineup", "all"]:
		await _lineup(chars, "lineup.png", str(Game.args.get("pose", "idle")), 0.3)
	if mode in ["anim", "all"]:
		await _lineup(chars, "lineup_walk.png", str(Game.args.get("anim", "walk")), float(Game.args.get("t", 0.35)))
	if mode in ["faces", "all"]:
		await _faces(chars)
	print("character_shots: done -> ", ProjectSettings.globalize_path(out_dir))
	get_tree().quit(0)

func _setup_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.40, 0.37)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.74)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -140, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.75, 0.82, 1.0)
	add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.31, 0.25)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)

func _spawn_all() -> Array:
	var chars: Array = []
	if Game.args.has("clips"):
		var id := str(Game.args.get("ids", "")).split(",")[0]
		for clip in str(Game.args["clips"]).split(","):
			var c := CharacterFactory.spawn_id(id) if id != "" else CharacterFactory.spawn(0)
			if c:
				c.set_meta("clip", clip)
				chars.append(c)
	elif Game.args.has("ids"):
		for id in str(Game.args["ids"]).split(","):
			var c := CharacterFactory.spawn_id(id)
			if c:
				chars.append(c)
	else:
		var r := str(Game.args.get("seeds", "0..7")).split("..")
		for s in range(int(r[0]), int(r[r.size() - 1]) + 1):
			var c := CharacterFactory.spawn(s)
			if c:
				chars.append(c)
	var x := -0.5 * 0.9 * (chars.size() - 1)
	for c in chars:
		add_child(c)
		c.position = Vector3(x, 0, 0)
		x += 0.9
	return chars

func _pose_all(chars: Array, anim: String, t: float) -> void:
	if anim == "rest":
		return
	for c in chars:
		c.play(str(c.get_meta("clip", anim)), 0.0)
		c.seek(t)

func _render(path: String) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(path))
	print("saved ", path)

func _lineup(chars: Array, file: String, anim: String, t: float) -> void:
	_pose_all(chars, anim, t)
	var cam := _camera()
	var w := 0.9 * chars.size()
	var vfov := deg_to_rad(cam.fov)
	var aspect := float(get_viewport().get_visible_rect().size.x) / get_viewport().get_visible_rect().size.y
	var dist := maxf(2.1 / (2.0 * tan(vfov * 0.5)), (w * 0.55) / (aspect * tan(vfov * 0.5))) + 0.6
	var yaw := deg_to_rad(float(Game.args.get("yaw", 0.0)))
	cam.position = Vector3(sin(yaw) * dist, 1.0, cos(yaw) * dist)
	cam.look_at(Vector3(0, 0.92, 0))
	await _render(file)

func _faces(chars: Array) -> void:
	var cam := _camera()
	cam.fov = 22.0
	var exprs := ["", "smile", "AA", "brow_raise"]
	for i in chars.size():
		var c = chars[i]
		_pose_all([c], "idle", 0.1)
		var head: Vector3 = c.head_position()
		for k in exprs.size():
			c.clear_face()
			if exprs[k] != "":
				c.set_expression(exprs[k], 1.0)
			c.look_at_point(cam.global_position if k != 3 else head + Vector3(0.6, 0.3, 1.0))
			cam.position = head + Vector3(0.35, 0.04, 1.05)
			cam.look_at(head + Vector3(0, -0.02, 0))
			await _render("face_%02d_%d.png" % [i, k])

func _camera() -> Camera3D:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = Camera3D.new()
		add_child(cam)
		cam.current = true
	cam.fov = 40.0
	cam.near = 0.05
	return cam
