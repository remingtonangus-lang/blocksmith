extends Node3D
## Horse look-dev harness (no world needed): neutral lit ground, renders the horse in poses / gait strips /
## coat line-ups / close-ups, saves PNGs and quits. Also runs the gait oracle on the bare animation.
##   godot --path frontier --resolution 960x540 res://scenes/horse_test.tscn -- --out DIR [--only a,b] [--quit 600]
## Shots: rest, front34, rear34, head, head34, walk, trot, canter, gallop, coats, tack, actions

const SHOTS := ["rest", "front34", "head", "head34", "shoulder", "walk", "trot", "canter", "gallop", "coats", "rear34", "actions"]

var out_dir := "user://horse_shots"
var cam: Camera3D
var sun: DirectionalLight3D
var horses: Array = []

func _ready() -> void:
	var t := Timer.new()
	t.wait_time = Game.arg_f("quit", 900.0)
	t.one_shot = true
	t.timeout.connect(func():
		print("HORSE_TEST: quit timeout")
		get_tree().quit(3))
	add_child(t)
	t.start()
	out_dir = str(Game.args.get("out", out_dir))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_env()
	await get_tree().process_frame
	var only := str(Game.args.get("only", ""))
	var list: Array = SHOTS if only == "" else Array(only.split(","))
	if Game.args.has("oracle") or only == "":
		_oracle()
	for s in list:
		await _shot(s)
	print("HORSE_TEST: done")
	get_tree().quit(0)

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
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_energy = 2.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.rotation = Vector3(deg_to_rad(-42), deg_to_rad(-35), 0)
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.46, 0.41, 0.34)
	gm.roughness = 0.95
	g.material_override = gm
	add_child(g)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.make_current()

func _clear() -> void:
	for h in horses:
		h.queue_free()
	horses.clear()

func _horse(seed: int, breed: String, pos: Vector3, yaw: float, coat := "", tack := true) -> HorseVisual:
	var v := HorseVisual.new()
	add_child(v)
	v.build(HorseCoats.roll(seed, breed, coat))
	v.position = pos
	v.rotation.y = yaw
	if v.ik:
		v.ik.ground_fn = func(_x: float, _z: float) -> float: return 0.0
	v.set_tack_visible(tack)
	horses.append(v)
	return v

func _pose(v: HorseVisual, anim: String, t: float) -> void:
	if v.tree:
		v.tree.active = false
	if v.anim_player and v.anim_player.has_animation(anim):
		v.anim_player.play(anim)
		v.anim_player.seek(t, true)
		v.anim_player.pause()

func _look(from: Vector3, at: Vector3, fov := 40.0, ortho := 0.0) -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL if ortho > 0.0 else Camera3D.PROJECTION_PERSPECTIVE
	if ortho > 0.0:
		cam.size = ortho
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
	print("HORSE_TEST: wrote ", p)

func _shot(s: String) -> void:
	_clear()
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	match s:
		"rest", "front34", "rear34", "head", "head34", "shoulder":
			var v := _horse(int(Game.args.get("seed", 3)), str(Game.args.get("breed", "quarter")), Vector3.ZERO, 0.0,
				str(Game.args.get("coat", "")), not Game.args.has("notack"))
			_pose(v, "idle", 0.0)
			# horse faces -Z; its left side is -X
			match s:
				"rest": _look(Vector3(-6.2, 1.2, -0.2), Vector3(0, 1.0, -0.2), 36)
				"front34": _look(Vector3(-3.2, 1.7, -4.2), Vector3(0, 1.05, -0.3), 38)
				"rear34": _look(Vector3(-3.0, 1.8, 4.0), Vector3(0, 1.0, 0.1), 38)
				"head": _look(Vector3(-1.5, 1.85, -1.75), Vector3(0, 1.72, -1.28), 32)
				"head34": _look(Vector3(-1.1, 1.95, -2.6), Vector3(0, 1.7, -1.3), 34)
				"shoulder": _look(Vector3(-2.2, 1.4, -1.2), Vector3(0, 1.15, -0.45), 34)
		"walk", "trot", "canter", "gallop":
			var n := 5
			for i in n:
				var v := _horse(11, "quarter", Vector3(0, 0, (i - 2) * 2.7), 0.0, "bay", false)
				var len := v.action_length(s) if v.anim_player else 1.0
				_pose(v, s, len * float(i) / n)
			_strip_layout(n)
			var vp := get_viewport().get_visible_rect().size
			_look(Vector3(-12.0, 1.0, 0.0), Vector3(0, 1.0, 0.0), 30, maxf(14.2 / (vp.x / vp.y), 2.6))
		"coats":
			var coats := ["bay", "chestnut", "black", "grey_dapple", "palomino", "buckskin", "pinto", "appaloosa"]
			for i in coats.size():
				var v := _horse(100 + i, "quarter", Vector3.ZERO, 0.0, coats[i], false)
				_pose(v, "idle", 0.0)
			_grid_layout(4)
			_look(Vector3(-15.0, 6.0, 6.5), Vector3(0, 0.9, 1.2), 34)
		"lod1", "lod2":
			var v := _horse(5, "quarter", Vector3.ZERO, 0.0, "bay", true)
			_pose(v, "idle", 0.0)
			var d := 40.0 if s == "lod1" else 120.0
			_look(Vector3(-d, 1.2, -0.2), Vector3(0, 1.0, -0.2), 36.0 * 6.2 / d)
			for mi in v.meshes:
				print("  mesh %s visible=%s range=%.0f..%.0f aabb=%s" % [mi.name, mi.visible, mi.visibility_range_begin, mi.visibility_range_end, str(mi.get_aabb())])
		"rider", "rider34", "rider_gallop", "rider_canter", "rider_mount", "rider_mount2", "rider_reins":
			var h := Horse.spawn(3, "quarter")
			add_child(h)
			h.set_physics_process(false)
			h.set_process(false)
			horses.append(h)
			var v: HorseVisual = h.visual
			var ranim := str(Game.args.get("rider_anim", "idle"))
			match s:
				"rider_gallop":
					ranim = "gallop"
					h.gait = "gallop"
					h.speed = 13.0
				"rider_canter":
					ranim = "canter"
					h.gait = "canter"
					h.speed = 7.0
			h.rider_side = -1.0
			_pose(v, ranim, 0.2)
			if CharacterFactory.available():
				var ch := CharacterFactory.spawn_id(str(Game.args.get("rider_id", "npc_000")))
				if ch != null:
					add_child(ch)
					horses.append(ch)
					await get_tree().process_frame
					var seat := v.seat_transform()
					ch.global_transform = Transform3D(seat.basis.orthonormalized(), seat.origin - seat.basis.y.normalized() * Horse.SEAT_DROP)
					ch.set_locomotion(0.0, "mounted")
					var rik := RiderIK.new()
					ch.skeleton.add_child(rik)
					rik.setup(h)
					if s == "rider_mount":
						rik.phase_override = 0.3
					elif s == "rider_mount2":
						rik.phase_override = 0.62
					if s.begins_with("rider_mount"):
						# root where Horse._place_rider has it at that point of the mount
						var side_pt := h.global_transform * Vector3(-0.85, 0.0, -0.1)
						var e := rik.phase_override * rik.phase_override * (3.0 - 2.0 * rik.phase_override)
						var tgt := Transform3D(seat.basis.orthonormalized(), seat.origin - seat.basis.y.normalized() * Horse.SEAT_DROP)
						ch.global_transform = Transform3D(tgt.basis, side_pt).interpolate_with(tgt, e)
						ch.set_locomotion(0.0, "mounted")
					for i in 40:                  # let the cloth springs settle on the barrel
						await get_tree().process_frame
			else:
				print("HORSE_TEST: no character assets, rider shot shows the horse only")
			match s:
				"rider", "rider_gallop", "rider_canter", "rider_mount", "rider_mount2":
					_look(Vector3(-5.2, 1.5, -0.2), Vector3(0, 1.25, -0.2), 38)
				"rider_reins":
					_look(Vector3(-1.9, 2.3, -1.9), Vector3(0, 1.75, -0.8), 40)
				_:
					_look(Vector3(-2.8, 2.2, -3.4), Vector3(0, 1.4, -0.3), 40)
		"actions":
			var acts := ["rear", "buck", "jump", "skid_stop", "graze", "death"]
			for i in acts.size():
				var v := _horse(40 + i, "mustang", Vector3.ZERO, 0.0, "", false)
				var L := v.action_length(acts[i])
				_pose(v, acts[i], L * 0.45)
			_grid_layout(3, 4.4, 3.6)
			_look(Vector3(-15.0, 5.5, 4.4), Vector3(1.8, 0.9, 1.2), 38)
	await _save(s)
	print("HORSE_TEST: %s %.1f s" % [s, (Time.get_ticks_msec() - t0) / 1000.0])

func _strip_layout(n: int) -> void:
	# horses face -Z; to show them side-on in a row, offset each along +Z... they would overlap, so spread
	# along the camera's horizontal axis (world Z) with enough spacing for their 2.6 m length
	for i in n:
		horses[i].position = Vector3(0, 0, (float(i) - (n - 1) * 0.5) * 2.75)

func _grid_layout(cols: int, dx := 3.2, dz := 2.9) -> void:
	for i in horses.size():
		var r := i / cols
		var c := i % cols
		horses[i].position = Vector3(r * dx, 0, (float(c) - (cols - 1) * 0.5) * dz)

# ------------------------------------------------------------------ gait oracle on the bare animation
func _oracle() -> void:
	var v := _horse(1, "quarter", Vector3(200, 0, 0), 0.0, "bay", false)
	if not v.has_model:
		print("GAIT ORACLE: SKIP (no horse model)")
		return
	for g in ["walk", "trot", "canter", "gallop"]:
		var res := HorseGaitOracle.analyse_animation(v, g)
		print(HorseGaitOracle.format_line(g, res))
