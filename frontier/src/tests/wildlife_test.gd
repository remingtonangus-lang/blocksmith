extends Node3D
## Wildlife look-dev harness (no world needed): neutral lit ground; renders a species line-up, per-species close-ups
## and gait strips, and runs the gait oracle on every species' gait animations. Saves PNGs and quits.
##   godot --path frontier --resolution 1280x540 res://scenes/wildlife_test.tscn -- --out DIR
##       [--only lineup,closeups,strips,actions,fur,furbench] [--species a,b] [--quit 600] [--fur_shells N]
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
			"fur": await _fur_shots()
			"furbench": await _furbench()
			"turncheck": _turncheck()
			"birds": await _birds()
			"wingcheck": _wingcheck()
	ok = ok and turn_ok
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
	v.build(HorseCoats.roll(seed, "quarter") if sp == "horse" else AnimalCoats.roll(sp, seed), sp)
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

func _bounds(v: HorseVisual) -> AABB:
	var inv := v.global_transform.affine_inverse()
	var bb := AABB()
	var first := true
	for mi in v.meshes:
		if not String(mi.name).begins_with("Body_LOD"):
			var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
			bb = b if first else bb.merge(b)
			first = false
	return bb

func _length(v: HorseVisual) -> float:
	return float(v.meta.get("rest", {}).get("length", 1.5))

## Side-on line-up of every species (largest first), each facing left.
func _lineup() -> void:
	_clear()
	await get_tree().process_frame
	var z := 0.0
	var maxh := 0.0
	for sp in _species():
		var v := _animal(sp, Vector3.ZERO, 0.0)            # facing -Z: side-on to the camera, nose to the left
		var L := _length(v)
		v.position = Vector3(0, 0, z + L * 0.5)
		z += L + 0.5
		maxh = maxf(maxh, float(v.meta.get("rest", {}).get("withers_height", 1.0)))
		_pose(v, "idle", 0.0)
	var mid := z * 0.5
	var w := z + 1.0
	_look(Vector3(-w * 0.47, maxh * 0.55, mid), Vector3(0, maxh * 0.5, mid), 50.0)
	await _save("lineup")

func _closeups() -> void:
	for sp in _species():
		_clear()
		await get_tree().process_frame
		var v := _animal(sp, Vector3.ZERO, 0.0)
		_pose(v, "idle", 0.0)
		# frame the whole animal (antlers, tail) from the front-left, using the meshes' bounds
		var bb := _bounds(v)
		var c := bb.get_center()
		var rad := bb.size.length() * 0.5
		var dir := Vector3(-1.0, 0.32, -0.8).normalized()
		_look(c + dir * rad / sin(deg_to_rad(20.0)) * 0.78, c, 40.0)
		await _save(sp + "_34")
		var an: Dictionary = v.meta.get("anchors", {})
		if an.has("poll"):
			var p: Array = an.poll
			var n: Array = an.nose
			var hc := (Vector3(p[0], p[2], -p[1]) + Vector3(n[0], n[2], -n[1])) * 0.5
			var hl := Vector3(p[0], p[2], -p[1]).distance_to(Vector3(n[0], n[2], -n[1]))
			_look(hc + Vector3(-hl * 2.4, hl * 0.6, -hl * 1.6), hc, 38.0)
			await _save(sp + "_head")
			if v.anim_player and v.anim_player.has_animation("attack"):
				# jaws open at the height of the lunge: frame the head where the clip carries it
				_pose(v, "attack", v.action_length("attack") * 0.55)
				await get_tree().process_frame
				var hb := v.skeleton.find_bone("head")
				var hp := v.global_transform * (v.skeleton.global_transform * v.skeleton.get_bone_global_pose(hb)).origin
				_look(hp + Vector3(-hl * 2.6, hl * 0.3, -hl * 1.4), hp + Vector3(0, -hl * 0.1, -hl * 0.5), 38.0)
				await _save(sp + "_attack_head")

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

## Fur close-ups: the 3/4 view of each furred species with shells on and off (<sp>_fur.png / <sp>_nofur.png).
func _fur_shots() -> void:
	for sp in _species():
		if not AnimalCoats.FUR.has(sp):
			continue
		_clear()
		await get_tree().process_frame
		var v := _animal(sp, Vector3.ZERO, 0.0)
		_pose(v, "idle", 0.0)
		var bb := _bounds(v)
		var c := bb.get_center()
		var rad := bb.size.length() * 0.5
		_look(c + Vector3(-1.0, 0.25, -0.55).normalized() * rad / sin(deg_to_rad(20.0)) * 0.62, c, 40.0)
		await _save(sp + "_fur")
		if v.fur_node:
			v.fur_node.visible = false
			await _save(sp + "_nofur")

## GPU cost of the fur: four animals of a species 3-6 m from the camera, render time with shells on and off.
func _furbench() -> void:
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for sp in ["wolf", "bison", "black_bear", "fox"]:
		if HorseVisual.model_path_for(sp) == "":
			continue
		_clear()
		await get_tree().process_frame
		var vs := []
		for i in 4:
			var v := _animal(sp, Vector3((i - 1.5) * 1.6, 0, 3.0 + i), 0.6)
			_pose(v, "idle", 0.0)
			vs.append(v)
		_look(Vector3(0, 1.2, -2.0), Vector3(0, 0.6, 4.0), 50.0)
		var res := []
		for on in [true, false]:
			for v in vs:
				if v.fur_node:
					v.fur_node.visible = on
			for i in 5:
				await get_tree().process_frame
			# minimum over 20 frames: the software rasteriser shares its cores with other jobs
			var gpu := INF
			var cpu := INF
			for i in 20:
				await RenderingServer.frame_post_draw
				gpu = minf(gpu, RenderingServer.viewport_get_measured_render_time_gpu(rid))
				cpu = minf(cpu, RenderingServer.viewport_get_measured_render_time_cpu(rid))
			var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			res.append([gpu, cpu, prims, draws])
		var shells: int = vs[0].fur_mats.size()
		print("FURBENCH %s x4 shells=%d  gpu(min) %.1f -> %.1f ms (x%.2f)  cpu %.2f -> %.2f ms  primitives %d -> %d  draws %d -> %d" % [
			sp, shells, res[1][0], res[0][0], res[0][0] / maxf(res[1][0], 0.01), res[1][1], res[0][1], res[1][2], res[0][2],
			res[1][3], res[0][3]])

## Birds: each species standing (idle) in a row, then the same birds in flight poses (flap, glide, soar/dive)
## above them, side-on; and a close 3/4 of each flying bird.
func _birds() -> void:
	var sps := ["turkey", "sage_grouse", "red_tailed_hawk", "crow"]
	_clear()
	await get_tree().process_frame
	var x := 0.0
	for sp in sps:
		if HorseVisual.model_path_for(sp) == "":
			continue
		var g := _animal(sp, Vector3(x, 0, 0), 0.0)
		_pose(g, "idle", 0.0)
		var f := _animal(sp, Vector3(x, 1.0, 0.6), 0.0)
		_pose(f, "glide" if sp != "red_tailed_hawk" else "soar", 0.0)
		var f2 := _animal(sp, Vector3(x, 2.0, 1.2), 0.0)
		_pose(f2, "flap", f2.action_length("flap") * 0.75)
		x += 1.6
	var mid := (x - 1.6) * 0.5
	_look(Vector3(mid - 1.5, 1.6, -5.5), Vector3(mid, 1.0, 0.4), 50.0)
	await _save("birds_front")
	_look(Vector3(mid - 2.5, 5.0, -2.5), Vector3(mid, 1.0, 0.6), 50.0)
	await _save("birds_above")

## Wing tip positions (model space) in the rest pose and in each flight clip, both sides: a check on the
## generator's bone-rotation conventions (spread = tips far out and level; flap = tips swing up and down).
func _wingcheck() -> void:
	for sp in ["turkey", "red_tailed_hawk"]:
		if HorseVisual.model_path_for(sp) == "":
			continue
		var v := _animal(sp, Vector3(900, 0, 0), 0.0)
		if v.tree:
			v.tree.active = false
		var sk := v.skeleton
		for clip in ["", "idle", "glide", "soar", "dive", "flap"]:
			var phases := [0.0] if clip != "flap" else [0.0, 0.25, 0.5, 0.75]
			for ph in phases:
				if clip != "":
					v.anim_player.play(clip)
					v.anim_player.seek(v.anim_player.get_animation(clip).length * ph, true)
				else:
					sk.reset_bone_poses()
				var out := []
				for side in ["L", "R"]:
					var bi := sk.find_bone("wing3_" + side)
					var tip := sk.get_bone_global_pose(bi) * Vector3(0, sk.get_bone_rest(bi).origin.length(), 0)
					out.append("%s(%.2f %.2f %.2f)" % [side, tip.x, tip.y, tip.z])
				print("WING %s %s@%.2f %s" % [sp, clip if clip != "" else "rest", ph, " ".join(out)])
		v.queue_free()

## Turn-in-place clips: over turn_l the head must swing to the animal's left (-X in model space) and the forefeet
## step left of the hind feet; turn_r mirrors it. Prints TURN lines; a wrong direction fails the run.
var turn_ok := true

func _turncheck() -> void:
	for sp in _species() + ["horse"]:
		if HorseVisual.model_path_for(sp) == "":
			continue
		var v := _animal(sp, Vector3(900, 0, 0), 0.0)
		for clip in ["turn_l", "turn_r"]:
			if v.anim_player == null or not v.anim_player.has_animation(clip):
				print("TURN %s/%s missing" % [sp, clip])
				turn_ok = false
				continue
			if v.tree:
				v.tree.active = false
			var L := v.anim_player.get_animation(clip).length
			var head_x := 0.0
			var fore_x := 0.0
			var n := 0
			var rest_x := {}
			v.anim_player.play("idle")
			v.anim_player.seek(0.0, true)
			for leg in ["LF", "RF", "LH", "RH"]:
				rest_x[leg] = (v.skeleton.get_bone_global_pose(v.hoof_bone(leg)) * v.sole_local(leg)).x
			var hb0 := v.skeleton.find_bone("head")
			var head0 := v.skeleton.get_bone_global_pose(hb0).origin.x
			v.anim_player.play(clip)
			var hind_x := 0.0
			var prev := {}
			for i in 49:
				v.anim_player.seek(fmod(L * float(i) / 24.0, L), true)
				var hb := v.skeleton.find_bone("head")
				if i < 24:
					head_x += (v.skeleton.get_bone_global_pose(hb).origin.x)
					n += 1
				# lateral travel of each foot while it is in the air (the direction it steps)
				for leg in ["LF", "RF", "LH", "RH"]:
					var p: Vector3 = v.skeleton.get_bone_global_pose(v.hoof_bone(leg)) * v.sole_local(leg)
					if prev.has(leg) and i > 24 and p.y > 0.02 * v.size_scale:
						if leg.ends_with("F"):
							fore_x += p.x - float(prev[leg])
						else:
							hind_x += p.x - float(prev[leg])
					prev[leg] = p.x
					if Game.args.has("turn_debug") and leg == "LF":
						print("   %s t=%.2f LF %s" % [clip, fmod(L * float(i) / 24.0, L), str(p)])
			v.anim_player.stop()
			var dh := head_x / n - head0
			var want := -1.0 if clip == "turn_l" else 1.0
			var ok := dh * want > 0.0 and fore_x * want > 0.0 and hind_x * want < 0.0
			if not ok:
				turn_ok = false
			print("TURN %s/%s %s  head dx %+.3f m  stepping forefeet dx %+.4f  hindfeet dx %+.4f  length %.2fs" % [sp, clip,
				"PASS" if ok else "FAIL", dh, fore_x, hind_x, L])
		v.queue_free()

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
