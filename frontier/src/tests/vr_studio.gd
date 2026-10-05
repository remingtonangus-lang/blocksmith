extends Node3D
## VR evidence on a light studio set (no world streaming, a few hundred MB): the real Player with the VR rig under
## the desktop simulator, a horse, three figures down range, a plank wall with a door and a campfire ring.
##   godot --path . res://scenes/vr_studio.tscn -- --out DIR [--views hud,menu,hands,gun_aim,two_hand,reload,nerve,riding,door,stereo]
## Each view is a scene from src/tests/vr_shots.gd rendered through the head camera (DIR/vr_<view>.png).

var out_dir := "/tmp/vr_studio"
var cam: Camera3D
var shots: VRShots
var door: TownDoor
var _spawned: Array = []

func _ready() -> void:
	if not Game.args.has("flat"):
		Game.args["vr_sim"] = true          # --flat: the same set without VR (third-person comparisons)
	out_dir = str(Game.args.get("out", out_dir))
	DirAccess.make_dir_recursive_absolute(out_dir)
	if Game.has_method("arm_watchdog"):
		Game.arm_watchdog(float(Game.args.get("watchdog", 1500)))
	var res := str(Game.args.get("res", "960x540")).split("x")
	get_window().size = Vector2i(int(res[0]), int(res[1]))
	_studio()
	cam = Camera3D.new()
	add_child(cam)
	var pl = load("res://src/actors/player.gd").new()
	pl.name = "Player"
	add_child(pl)
	pl.global_position = Vector3(0, 0.05, 0)
	pl.setup(cam)
	Game.player = pl
	if not Game.disabled("horse"):
		var hz := Horse.spawn(1899, "quarter")
		add_child(hz)
		hz.global_position = Vector3(3.0, 0, 4.0)
		hz.yaw = 0.0
		Horse.player_horse = hz
	shots = VRShots.new(self)
	await _settle(10)
	if Game.args.has("dump"):
		_dump()
	for v in str(Game.args.get("views", "hud,menu,comfort,hands,body,body_ext,gun_aim,fire,two_hand,two_hand_ext,reload,bolt,pump,nerve,riding,riding_ext,door,door_open,stereo")).split(","):
		var t0 := Time.get_ticks_msec()
		_reset_player()
		await call("_view_" + v)
		await _shot("vr_" + v)
		_cleanup()
		print("vr_studio: %s (%d ms)" % [v, Time.get_ticks_msec() - t0])
	print("vr_studio: done")
	get_tree().quit(0)

# ------------------------------------------------------------------ host API for VRShots
func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func _ground(_x: float, _z: float) -> float:
	return 0.0

func _vr_target(pos: Vector3, seed: int) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var ch: Node3D = CharacterFactory.spawn(seed, "") if CharacterFactory.available() else null
	if ch == null:
		ch = MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.25
		cm.height = 1.75
		(ch as MeshInstance3D).mesh = cm
		ch.position.y = 0.88
	root.add_child(ch)
	ch.rotation.y = PI + (Game.player.global_position - pos).signed_angle_to(Vector3.BACK, Vector3.UP) * -1.0
	if ch.has_method("set_locomotion"):
		ch.set_locomotion(0.0, "idle", true)
	# a body-sized collider so Nerve marks and shots land on them
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	sb.add_child(cs)
	root.add_child(sb)
	_spawned.append(root)
	return root

# ------------------------------------------------------------------ views
func _view_hud() -> void:
	await shots.hud(0.0)

func _view_menu() -> void:
	await shots.menu(0.0)

func _view_hands() -> void:
	await shots.hands(0.0)

func _view_gun_aim() -> void:
	await shots.gun_aim(0.0)

func _view_fire() -> void:
	await shots.gun_aim(0.0, true)

func _view_two_hand() -> void:
	await shots.two_hand(0.0)

func _view_reload() -> void:
	await shots.reload(0.0)

func _view_nerve() -> void:
	await shots.nerve(0.0)

func _view_riding() -> void:
	var hz: Horse = Horse.player_horse
	if hz == null:
		return
	hz.mount(Game.player)
	await _settle(60)
	await shots.riding()

func _view_door() -> void:
	# stand a step in front of the door and reach for the leaf
	var front := door.global_transform * Vector3(door.width * 0.5, 0.0, -0.95)
	Game.player.global_position = Vector3(front.x, 0.05, front.z)
	await _settle(5)
	var fz := door.global_basis.z
	var yaw := rad_to_deg(atan2(fz.x, -fz.z))
	await shots.reach(yaw, door.global_transform * Vector3(door.width * 0.85, 1.0, -0.05), _open_door)

var _open_door := false
func _view_door_open() -> void:
	_open_door = true
	await _view_door()
	_open_door = false

func _view_comfort() -> void:
	await shots.comfort(0.0)

func _view_body() -> void:
	await shots.body(0.0)

func _view_bolt() -> void:
	await shots.bolt_reload(0.0)

func _view_pump() -> void:
	await shots.pump_reload(0.0)

## Third-person checks of the IK'd body: a studio camera looks at the player while the VR pose holds.
func _ext(from: Vector3, at: Vector3) -> void:
	var pl: Node3D = Game.player
	cam.global_position = pl.global_position + from
	cam.look_at(pl.global_position + at)
	cam.fov = 45.0
	cam.make_current()
	var v := shots.vr()
	if v != null and v.play != null:
		v.play.hide_self = false          # stop the periodic re-hide while the spectator camera looks
		VRBody.hide_head(pl.get("visual"), true)
	await _settle(3)

func _restore_cam() -> void:
	var v := shots.vr() if Game.is_vr else null
	if v != null:
		v.cam.make_current()
		if v.body != null and v.play != null:
			v.play.hide_self = true
			VRBody.hide_head(Game.player.get("visual"))

func _view_body_ext() -> void:
	await shots.reach_out(0.0)
	await _ext(Vector3(1.6, 1.3, -2.2), Vector3(0, 1.15, 0))

func _view_two_hand_ext() -> void:
	await shots.two_hand(0.0)
	await _ext(Vector3(2.0, 1.4, -1.2), Vector3(0, 1.35, -0.3))

func _view_two_hand_ots() -> void:
	await shots.two_hand(0.0)
	await _ext(Vector3(0.35, 1.85, 0.7), Vector3(-0.05, 1.5, -0.6))

func _view_riding_ext() -> void:
	await _view_riding()
	if Game.args.has("vr_debug"):
		var holder0 = Game.player.get("holder")
		for bn in ["Hips", "Head", "RightHand", "LeftFoot"]:
			var dot := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.05
			sm.height = 0.1
			var mm := StandardMaterial3D.new()
			mm.albedo_color = Color(1, 0, 0)
			mm.no_depth_test = true
			mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.material = mm
			dot.mesh = sm
			add_child(dot)
			dot.top_level = true
			dot.global_position = holder0._bone(bn, Vector3.ZERO)
			_spawned.append(dot)
		var sk4: Skeleton3D = holder0.skel
		for bn2 in ["Root", "Hips"]:
			var bi := GunHands.bone_index(sk4, bn2)
			if bi >= 0:
				print("  dbg bone %s parent %d pose_pos %s rest_pos %s global %s" % [bn2, sk4.get_bone_parent(bi), sk4.get_bone_pose_position(bi), sk4.get_bone_rest(bi).origin, sk4.get_bone_global_pose(bi).origin])
		print("  dbg skel xf %s  model pos %s" % [sk4.global_transform, (Game.player.visual as Node3D).get("model").position if Game.player.visual.get("model") else "-"])
	await _ext(Vector3(2.6, 2.2, -2.2), Vector3(0, 0.9, 0))

func _view_mount_flat() -> void:
	var hz: Horse = Horse.player_horse
	hz.mount(Game.player)
	await _settle(60)
	if Game.args.has("vr_debug"):
		var holder0 = Game.player.get("holder")
		for bn in ["Hips", "Head", "RightHand", "LeftFoot"]:
			var dot := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.06
			sm.height = 0.12
			var mm := StandardMaterial3D.new()
			mm.albedo_color = Color(1, 0, 0)
			mm.no_depth_test = true
			mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.material = mm
			dot.mesh = sm
			add_child(dot)
			dot.global_position = holder0._bone(bn, Vector3.ZERO)
			_spawned.append(dot)
	var pl: Node3D = Game.player
	cam.global_position = pl.global_position + Vector3(2.6, 2.2, -2.2)
	cam.look_at(pl.global_position + Vector3(0, 0.9, 0))
	cam.make_current()
	var holder = pl.get("holder")
	if holder != null and holder.skel != null:
		print("  dbg hips bone %s  rider root %s" % [holder._bone("Hips", Vector3.ZERO), pl.global_position])
	await _settle(3)

func _view_stereo() -> void:
	Game.args["vr_stereo"] = true
	await shots.gun_aim(0.0, false)
	await _settle(4)

func _reset_player() -> void:
	var pl = Game.player
	if pl.get("on_horse") != null and Horse.player_horse:
		Horse.player_horse.dismount()
	pl.global_position = Vector3(0, 0.05, 0)
	pl.velocity = Vector3.ZERO
	if door != null and door.is_open():
		door.close()

func _cleanup() -> void:
	_restore_cam()
	shots.reset()
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	if Game.get("menus") and Game.menus.has_method("close_all"):
		Game.menus.close_all()

func _shot(name: String) -> void:
	if Game.args.has("hide_mesh"):           # debug: which mesh is that?
		for mi in Game.player.find_children(str(Game.args["hide_mesh"]), "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visible = false
	await _settle(2)
	await RenderingServer.frame_post_draw
	if Game.args.has("vr_debug"):
		var pl = Game.player
		var v := shots.vr()
		var m: WeaponModel = pl.holder.model() if pl.holder else null
		print("  dbg facing %.2f cam_yaw %.2f origin_yaw %.2f head %s holding %s two %s drawn %s gun %s" % [pl.facing, pl.cam_yaw,
			v.origin.global_rotation.y, v.cam.global_position, v.play.holding, v.play.two_hand, pl.gun.drawn, pl.gun.weapon_id()])
		print("  dbg grips L %.2f R %.2f active %s/%s gate %s round %s clip %s nerve %s marks %d rein %s" % [v.hands.left.grip, v.hands.right.grip,
			v.left.get_is_active(), v.right.get_is_active(), v.play._gate_open, v.play._round != null, pl.gun.clip,
			pl.nerve.active if pl.nerve else false, pl.nerve.marks.size() if pl.nerve else 0, v.play._rein])
		print("  dbg lhand %s vis %s fist %s" % [v.left.global_position, v.hands.left.is_visible_in_tree(), v.hands.left.aim_transform().origin])
		if v.body != null:
			var sk3: Skeleton3D = v.body.get_skeleton()
			print("  dbg hips process %s  modification %s" % [(sk3.global_transform * sk3.get_bone_global_pose(GunHands.bone_index(sk3, "Hips"))).origin, v.body.mod_hips])
		if v.body != null:
			var hd = pl.get("holder")
			for bn in ["Hips", "Spine", "Chest", "UpperChest", "LeftShoulder", "Neck", "Head", "LeftUpperArm"]:
				print("  dbg bone %s %s" % [bn, hd._bone(bn, Vector3.ZERO)])
			print("  dbg lfist %s rfist %s" % [v.hands.left.aim_transform().origin, v.hands.right.aim_transform().origin])
		print("  dbg eye %s user_eye %.2f cam %s player %s body %s" % [v.eye_anchor(), v.user_eye(), v.cam.global_position, pl.global_position, v.body != null])
		if m != null:
			print("  dbg gun pos %s fwd %s  rhand %s aim_fwd %s" % [m.global_position, -m.global_basis.z, v.right.global_position, -v.play.aim_frame(v.right).basis.z])
	var p := out_dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(p)
	print("shot: %s  draws %d objects %d prims %d (%s)" % [p, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		RenderingServer.get_current_rendering_method()])

# ------------------------------------------------------------------ set
func _studio() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.42, 0.55, 0.72)
	sm.sky_horizon_color = Color(0.78, 0.74, 0.66)
	sm.ground_horizon_color = Color(0.55, 0.48, 0.38)
	sm.ground_bottom_color = Color(0.3, 0.26, 0.2)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.5
	# the game's sun settings for the active preset (sky.gd), so draw/prim counts match the preset
	sun.shadow_enabled = float(Game.quality.get("shadow_distance", 300.0)) > 0.0
	sun.directional_shadow_max_distance = minf(float(Game.quality.get("shadow_distance", 300.0)), 120.0)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if int(Game.quality.get("shadow_splits", 4)) == 2 and not Game.args.has("splits4") else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	env.glow_enabled = Game.quality.get("glow", true)
	if Game.args.has("shadow_q"):
		RenderingServer.directional_soft_shadow_filter_set_quality(int(Game.args["shadow_q"]))
	sun.shadow_bias = float(Game.args.get("sun_bias", 0.04))          # the game's sun (sky.gd)
	sun.shadow_normal_bias = float(Game.args.get("sun_nbias", 1.4))
	add_child(sun)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(120, 1, 120)
	cs.shape = bs
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	g.mesh = pm
	# (terrain_ah.png is a Texture2DArray for the terrain shader: as a StandardMaterial albedo it rendered as an
	# unbound texture — beige on Forward+, dark grey on Mobile. A noise texture stands in.)
	var gm := _mat(Color(0.62, 0.52, 0.38), "", 1.0)
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.noise = FastNoiseLite.new()
	nt.noise.frequency = 0.05
	nt.color_ramp = Gradient.new()
	nt.color_ramp.set_color(0, Color(0.78, 0.72, 0.62))
	nt.color_ramp.set_color(1, Color(1, 1, 1))
	if not Game.args.has("ground_plain"):
		gm.albedo_texture = nt
		gm.uv1_triplanar = not Game.args.has("ground_uv")
		gm.uv1_scale = Vector3(0.6, 0.6, 0.6) if gm.uv1_triplanar else Vector3(60, 60, 60)
	g.material_override = gm
	if Game.args.has("ground_shader"):
		var shm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nvoid fragment() { ALBEDO = vec3(0.62, 0.52, 0.38); ROUGHNESS = 0.95; }"
		shm.shader = sh
		g.material_override = shm
	if Game.args.has("ground_std"):
		var sm0 := StandardMaterial3D.new()
		sm0.albedo_color = Color(0.62, 0.52, 0.38)
		g.material_override = sm0
	if Game.args.has("ground_noshadow"):
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
	# plank wall with a door to the left of the start
	var wood := _mat(Color(0.42, 0.3, 0.2), "res://assets/ext/packed/build_planks_brown_ah.png", 1.0)
	for side in [-1.0, 1.0]:
		var w := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.0, 2.6, 0.12)
		w.mesh = bm
		w.material_override = wood
		w.position = Vector3(-4.0 + side * 1.5, 1.3, -1.0)
		add_child(w)
	var frame := Node3D.new()           # TownDoor drives its own rotation (swing angle): the frame carries the facing
	frame.position = Vector3(-3.5, 0.0, -1.0)
	frame.rotation.y = PI               # leaf spans the gap in the wall; the door's -Z side faces the start
	add_child(frame)
	door = TownDoor.new()
	door.setup(1.0, 2.1, 0.06)
	frame.add_child(door)
	door.add_to_group("door")
	var leaf := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.0, 2.1, 0.05)
	leaf.mesh = lm
	leaf.material_override = _mat(Color(0.5, 0.36, 0.24), "res://assets/ext/packed/build_planks_brown_ah.png", 1.0)
	leaf.position = Vector3(0.5, 1.05, 0.0)
	door.add_child(leaf)
	var knob := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.03
	sp.height = 0.06
	knob.mesh = sp
	knob.position = Vector3(0.85, 1.0, -0.05)
	door.add_child(knob)
	var knob2 := knob.duplicate()
	knob2.position.z = 0.05
	door.add_child(knob2)
	# a pond with the game's water material on the quest preset (its no-refraction variant needs no depth below;
	# the refracting desktop water would read this flat studio floor as a 3 cm shallow and foam all over)
	if not Game.quality.get("water_refraction", true):
		var wnode = load("res://src/world/water.gd").new()
		var pond := MeshInstance3D.new()
		var pqm := PlaneMesh.new()
		pqm.size = Vector2(5, 4)
		pond.mesh = pqm
		pond.material_override = wnode._material(0.0, 0.5, Color(0.32, 0.36, 0.26), Color(0.05, 0.12, 0.13))
		pond.position = Vector3(7.0, 0.03, -7.0)
		add_child(pond)
		wnode.free()
	# campfire ring to the right
	for i in 8:
		var st := MeshInstance3D.new()
		var sm2 := SphereMesh.new()
		sm2.radius = 0.12
		sm2.height = 0.16
		st.mesh = sm2
		st.material_override = _mat(Color(0.45, 0.43, 0.4), "", 1.0)
		var a := TAU * i / 8.0
		st.position = Vector3(3.5 + cos(a) * 0.45, 0.05, -2.5 + sin(a) * 0.45)
		add_child(st)

func _mat(c: Color, tex: String, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	if tex != "" and ResourceLoader.exists(tex):
		m.albedo_texture = load(tex)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(scale, scale, scale)
	return m

## --dump: every mesh in the set with its triangle count, LOD/visibility range and shadow mode (Quest budgets).
func _dump() -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var tris := 0
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			var idx = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		print("dump %-40s %7d tris  range %.0f-%.0f  shadow %d  vis %s  owner %s" % [str(m.get_path()).right(60), tris,
			m.visibility_range_begin, m.visibility_range_end, m.cast_shadow, m.is_visible_in_tree(), m.owner.name if m.owner else "-"])
