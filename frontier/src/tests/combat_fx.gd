extends Node3D
## Combat-feel render checks on a small studio set (no world streaming):
##   godot --path . res://scenes/combat_fx.tscn -- --out /tmp/cfx --views aim,reload,hold,pistol,ragdoll,impacts,nerve,night
## aim: pistol and rifle aimed, from the side and over the shoulder (the player camera), plus low ready
## reload: revolver at the loading gate, repeater pushing rounds into the gate, bolt rifle cycling
## hold: character shouldering the repeater (arm IK to grip_r/grip_l, gun belt + holstered revolver, sling)
## pistol: two-handed revolver aim; ragdoll: a character shot in the chest, captured mid-fall and settled;
## impacts: bullet effects per surface; nerve: the Nerve grade with inked marks; night: muzzle flash light at night.

const ACTOR := preload("res://src/tests/test_actor.gd")
var cam: Camera3D
var out_dir := "/tmp/cfx"
var env: Environment
var sun: DirectionalLight3D

func _ready() -> void:
	out_dir = str(Game.args.get("out", "/tmp/cfx"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	Game.arm_watchdog(float(Game.args.get("watchdog", 1500)))
	var res := str(Game.args.get("res", "960x540")).split("x")
	get_window().size = Vector2i(int(res[0]), int(res[1]))
	_studio()
	for v in str(Game.args.get("views", "hold,pistol,ragdoll,impacts,nerve,night")).split(","):
		await call("_view_" + v)
	print("combat_fx: done")
	get_tree().quit(0)

func _studio() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.42, 0.55, 0.72)
	sm.sky_horizon_color = Color(0.75, 0.72, 0.66)
	sm.ground_horizon_color = Color(0.5, 0.45, 0.38)
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
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	# ground with collision (ragdolls, casings)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.52, 0.44, 0.33)
	gm.roughness = 1.0
	var tp := "res://assets/ext/packed/terrain_ah.png"
	if ResourceLoader.exists(tp):
		gm.albedo_texture = load(tp)
		gm.uv1_triplanar = true
		gm.uv1_scale = Vector3(0.5, 0.5, 0.5)
	g.material_override = gm
	add_child(g)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.make_current()

func _actor(pos: Vector3, yaw: float, weapons: Array, seed: int, id := "") -> Node3D:
	var a: Node3D = ACTOR.new()
	a.name = "Actor%d" % seed
	add_child(a)
	a.global_position = pos
	var ch: Node3D = null
	if CharacterFactory.available():
		ch = CharacterFactory.spawn_id(id) if id != "" else CharacterFactory.spawn(seed, "")
	if ch == null:
		ch = Node3D.new()
		var m := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.25
		cm.height = 1.5
		m.mesh = cm
		m.position.y = 0.8
		ch.add_child(m)
	a.add_child(ch)
	a.visual = ch
	a.facing = yaw
	ch.rotation.y = yaw
	if ch.has_method("set_locomotion"):
		ch.set_locomotion(0.0, "idle", true)
	var g := GunHandler.new()
	g.weapons.assign(weapons)
	a.add_child(g)
	g.setup(a, null, false)
	var h := WeaponHolder.attach(a, g)
	h.snap = true
	a.set_meta("gun", g)
	a.set_meta("holder", h)
	return a

func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await _settle(2)
	await RenderingServer.frame_post_draw
	var p := out_dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(p)
	print("shot: ", p)

func _clear() -> void:
	for c in get_children():
		if c.has_meta("gun") or c.is_in_group("fx_tmp"):
			c.queue_free()
	await get_tree().process_frame

func _pose_shots(a: Node3D, prefix: String) -> void:
	var h: WeaponHolder = a.get_meta("holder")
	var eye := h._bone("Head", Vector3(0, 1.62, 0))
	cam.fov = 38
	cam.global_position = eye + Vector3(2.0, -0.1, -0.35)
	cam.look_at(eye + Vector3(0.0, -0.22, -0.4))
	await _shot(prefix + "_side")
	# the game's over-the-shoulder aim camera (player.gd: 1.6 m back, ~0.63 m right, pivot near head height)
	cam.fov = 50
	cam.global_position = eye + Vector3(0.63, 0.02, 1.6)
	cam.look_at(eye + Vector3(0.0, -0.1, -25.0))
	await _shot(prefix + "_ots")
	# hands close-up
	var m := h.model()
	if m != null:
		var gp := m.grip_transform("grip_r").origin
		cam.fov = 30
		cam.global_position = gp + Vector3(0.55, 0.12, -0.35)
		cam.look_at(gp + Vector3(0.0, 0.0, -0.08))
		await _shot(prefix + "_hands")
		cam.global_position = gp + Vector3(-0.45, 0.05, -0.45)
		cam.look_at(gp + Vector3(0.0, 0.0, -0.08))
		await _shot(prefix + "_hands_left")

func _view_aim() -> void:
	var a := _actor(Vector3.ZERO, 0.0, ["lockhart_sa", "merriman_lever"], 5, "ruth_caddell")
	var g: GunHandler = a.get_meta("gun")
	g.drawn = true
	a.intent.aim_at = Vector3(0.0, 1.5, -25)
	if a.visual.has_method("set_aim"):
		a.visual.set_aim("pistol")
	var hh: WeaponHolder = a.get_meta("holder")
	if Game.args.has("one_hand") and hh.hands != null:
		hh.hands.two_hand_pistol = false
	await _settle(8)
	await _pose_shots(a, "aim_pistol")
	a.intent.aim_at = null
	if a.visual.has_method("set_aim"):
		a.visual.set_aim("")
	await _settle(4)
	cam.fov = 34
	cam.global_position = Vector3(2.0, 1.4, -0.9)
	cam.look_at(Vector3(0.1, 1.1, -0.3))
	await _shot("ready_pistol")
	g.select(1)
	g.cooldown = 0.0
	a.intent.aim_at = Vector3(0.0, 1.5, -25)
	if a.visual.has_method("set_aim"):
		a.visual.set_aim("rifle")
	await _settle(8)
	await _pose_shots(a, "aim_rifle")
	await _clear()

func _view_reload() -> void:
	var a := _actor(Vector3.ZERO, 0.0, ["lockhart_sa", "merriman_lever", "bowden_bolt"], 5, "ruth_caddell")
	var g: GunHandler = a.get_meta("gun")
	g.drawn = true
	await _settle(3)
	g.clip["lockhart_sa"] = 2
	g.start_reload()
	await _settle(5)
	cam.fov = 34
	cam.global_position = Vector3(1.6, 1.45, -1.2)
	cam.look_at(Vector3(0.05, 1.15, -0.3))
	await _shot("reload_revolver")
	g.cancel_reload()
	g.select(1)
	g.cooldown = 0.0
	await _settle(3)
	g.clip["merriman_lever"] = 4
	g.start_reload()
	await _settle(5)
	await _shot("reload_repeater")
	g.cancel_reload()
	g.select(2)
	g.cooldown = 0.0
	a.intent.aim_at = Vector3(0.0, 1.5, -25)
	await _settle(4)
	var h: WeaponHolder = a.get_meta("holder")
	var m := h.model()
	m.pose({"bolt_rot": 1.0, "bolt": 0.6})
	m.set_process(false)
	await _settle(3)
	cam.global_position = Vector3(2.0, 1.55, -0.9)
	cam.look_at(Vector3(0.1, 1.38, -0.35))
	await _shot("cycle_bolt")
	m.set_process(true)
	await _clear()

func _view_hold() -> void:
	var a := _actor(Vector3.ZERO, 0.0, ["merriman_lever", "lockhart_sa"], 3)
	var g: GunHandler = a.get_meta("gun")
	g.drawn = true
	a.intent.aim_at = Vector3(0.3, 1.4, -20)
	if a.visual.has_method("set_aim"):
		a.visual.set_aim("rifle")
	await _settle(8)
	cam.fov = 32
	cam.global_position = Vector3(1.9, 1.55, -1.6)
	cam.look_at(Vector3(0.05, 1.2, -0.15))
	await _shot("hold_rifle")
	cam.global_position = Vector3(-1.2, 1.3, 1.8)
	cam.look_at(Vector3(0.1, 1.1, 0))
	await _shot("hold_rifle_back")
	await _clear()

func _view_pistol() -> void:
	var a := _actor(Vector3.ZERO, 0.0, ["lockhart_sa"], 5)
	var g: GunHandler = a.get_meta("gun")
	g.drawn = true
	a.intent.aim_at = Vector3(0.0, 1.45, -20)
	if a.visual.has_method("set_aim"):
		a.visual.set_aim("pistol")
	await _settle(8)
	cam.fov = 32
	cam.global_position = Vector3(1.7, 1.6, -1.7)
	cam.look_at(Vector3(0.0, 1.3, -0.25))
	await _shot("hold_pistol")
	# holstered: belt + holster on the hip
	g.drawn = false
	if a.visual.has_method("set_aim"):
		a.visual.set_aim("")
	await _settle(6)
	cam.fov = 30
	cam.global_position = Vector3(1.4, 1.1, -0.9)
	cam.look_at(Vector3(0.15, 0.9, 0.0))
	await _shot("holstered")
	await _clear()

func _view_ragdoll() -> void:
	var a := _actor(Vector3.ZERO, 0.0, ["lockhart_sa"], 7)
	await _settle(4)
	cam.fov = 40
	cam.global_position = Vector3(3.2, 1.4, 1.2)
	cam.look_at(Vector3(0, 0.7, 0.3))
	if a.visual.has_method("die"):
		a.alive = false
		a.visual.die({"direction": Vector3(0, 0, 1), "zone": "chest", "amount": 70.0})
	await _settle(4)
	await _shot("ragdoll_fall")
	await _settle(20)
	await _shot("ragdoll_settled")
	print("ragdolls simulating: ", Ragdoll.active_count())
	await _clear()

func _view_impacts() -> void:
	var surfs := ["dirt", "sand", "snow", "wood", "stone", "water", "flesh"]
	var x := -2.4
	for s in surfs:
		var lab := Label3D.new()
		lab.text = s
		lab.font_size = 48
		lab.position = Vector3(x, 0.05, 0.6)
		lab.rotation_degrees = Vector3(-60, 0, 0)
		lab.add_to_group("fx_tmp")
		add_child(lab)
		var n := Vector3.UP
		var pos := Vector3(x, 0.0, 0.0)
		if s in ["wood", "stone"]:
			var wall := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.6, 0.8, 0.2)
			wall.mesh = bm
			var wm := StandardMaterial3D.new()
			wm.albedo_color = Color(0.45, 0.32, 0.2) if s == "wood" else Color(0.55, 0.53, 0.5)
			wall.material_override = wm
			wall.position = Vector3(x, 0.4, -0.3)
			wall.add_to_group("fx_tmp")
			add_child(wall)
			pos = Vector3(x, 0.45, -0.199)
			n = Vector3(0, 0, 1)
		var info := {"position": pos, "normal": n, "direction": -n, "surface": s}
		if s == "flesh":
			info["target"] = null
			pos.y = 1.0
			info.position = pos
			info.direction = Vector3(1, 0, 0)
		Effects.impact(self, info)
		x += 0.8
	await _settle(3)
	cam.fov = 45
	cam.global_position = Vector3(0, 1.4, 3.2)
	cam.look_at(Vector3(0, 0.4, 0))
	await _shot("impacts")
	await _settle(30)
	await _shot("impacts_decals")
	await _clear()

func _view_nerve() -> void:
	var a := _actor(Vector3(0, 0, 2.5), PI, ["lockhart_sa"], 9)
	var b := _actor(Vector3(-1.4, 0, -6), 0.4, ["merriman_lever"], 11)
	var c := _actor(Vector3(1.8, 0, -7.5), -0.3, ["lockhart_sa"], 13)
	a.get_meta("gun").drawn = true
	a.intent.aim_at = Vector3(-1.4, 1.4, -6)
	if a.visual.has_method("set_aim"):
		a.visual.set_aim("pistol")
	var nv := Nerve.new()
	var layer := CanvasLayer.new()
	add_child(layer)
	nv.setup(a.get_meta("gun"), layer)
	a.add_child(nv)
	nv.overlay.visible = true
	for t in [b, c]:
		var m := {"pos": t.global_position + Vector3(0, 1.45, 0), "node": null}
		nv._ink(m)
		var m2 := {"pos": t.global_position + Vector3(0, 1.7, 0), "node": null}
		nv._ink(m2)
	await _settle(8)
	cam.fov = 50
	cam.global_position = Vector3(0.7, 1.75, 4.4)
	cam.look_at(Vector3(-0.2, 1.3, -4))
	await _shot("nerve")
	layer.queue_free()
	for n in get_tree().get_nodes_in_group("nerve_ink"):
		n.queue_free()
	await _clear()

func _view_night() -> void:
	sun.light_energy = 0.05
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.015, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.06, 0.1)
	env.ambient_light_energy = 0.4
	var a := _actor(Vector3.ZERO, 0.0, ["lockhart_sa"], 15)
	a.get_meta("gun").drawn = true
	a.intent.aim_at = Vector3(0, 1.45, -20)
	if a.visual.has_method("set_aim"):
		a.visual.set_aim("pistol")
	await _settle(6)
	var h: WeaponHolder = a.get_meta("holder")
	var mt := h.muzzle_transform()
	Effects.night_override = 1.0
	Effects.flash_hold = 100.0
	Effects.muzzle_flash(self, mt.origin, -mt.basis.z)
	WeaponFX.smoke(self, mt.origin, -mt.basis.z, 1.0)
	cam.fov = 40
	cam.global_position = Vector3(2.2, 1.5, -1.2)
	cam.look_at(Vector3(0, 1.3, -0.6))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("night_flash.png"))
	Effects.flash_hold = 1.0
	Effects.night_override = -1.0
	print("shot: night_flash")
	await _clear()
