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
	Game.args["vr_sim"] = true
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
	for v in str(Game.args.get("views", "hud,menu,hands,gun_aim,fire,two_hand,reload,nerve,riding,door,door_open,stereo")).split(","):
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
	shots.reset()
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	if Game.get("menus") and Game.menus.has_method("close_all"):
		Game.menus.close_all()

func _shot(name: String) -> void:
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
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
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
	g.material_override = _mat(Color(0.55, 0.46, 0.34), "res://assets/ext/packed/terrain_ah.png", 0.5)
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
