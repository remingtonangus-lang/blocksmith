extends Node3D
## Firearm beauty shots on a neutral studio backdrop (key/fill/rim + soft sky reflections) for judging the
## generated weapon models (tools/weapons/gun_gen.py) in the real renderer.
##   godot --path . res://scenes/weapon_lineup.tscn -- --out /tmp/guns --ids lockhart_sa,merriman_lever
##       --views q34,side,detail,open,lineup [--res 960x540] [--watchdog 900]
## Views: q34 (3/4 from the right rear), side (right side), left, detail (action close-up), open (action close-up
## with the parts posed open/cocked), front (muzzle), lineup (all ids, orthographic, to scale).

var cam: Camera3D
var out_dir := "/tmp/guns"

func _ready() -> void:
	out_dir = str(Game.args.get("out", "/tmp/guns"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	Game.arm_watchdog(float(Game.args.get("watchdog", 900)))
	var res := str(Game.args.get("res", "960x540")).split("x")
	get_window().size = Vector2i(int(res[0]), int(res[1]))
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_studio()
	var ids: PackedStringArray = str(Game.args.get("ids", ",".join(Weapons.DEFS.keys()))).split(",")
	var views: PackedStringArray = str(Game.args.get("views", "q34,side,detail")).split(",")
	for v in views:
		if v == "lineup":
			await _lineup(ids)
			continue
		for id in ids:
			await _shot(id, v)
	print("weapon_lineup: done")
	get_tree().quit(0)

func _studio() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.62, 0.64, 0.68)
	sm.sky_horizon_color = Color(0.42, 0.42, 0.43)
	sm.ground_horizon_color = Color(0.3, 0.29, 0.28)
	sm.ground_bottom_color = Color(0.08, 0.08, 0.08)
	sm.sun_angle_max = 1.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.2, 0.21)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 0.06
	env.ssao_intensity = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.26, 0.255, 0.25)
	fm.roughness = 0.9
	floor_mi.material_override = fm
	floor_mi.position.y = -0.2
	floor_mi.name = "Floor"
	add_child(floor_mi)
	for l in [["Key", Vector3(-38, 35, 0), 2.2, Color(1.0, 0.95, 0.88), true],
			["Fill", Vector3(-15, -120, 0), 0.55, Color(0.85, 0.9, 1.0), false],
			["Rim", Vector3(-25, 160, 0), 1.6, Color(1, 1, 1), false]]:
		var d := DirectionalLight3D.new()
		d.name = l[0]
		d.rotation_degrees = l[1]
		d.light_energy = l[2]
		d.light_color = l[3]
		d.shadow_enabled = l[4]
		d.directional_shadow_max_distance = 6.0
		add_child(d)
	cam = Camera3D.new()
	cam.fov = 30
	add_child(cam)
	cam.make_current()

func _aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible or not mi.is_visible_in_tree():
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func _capture(path: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("shot: ", path)

func _shot(id: String, view: String) -> void:
	var m := WeaponModel.create(id)
	add_child(m)
	m.set_process(false)
	if view == "open":
		m.pose_open()
	elif view == "cycle":
		# mid-cycle after a shot (lever/bolt/pump open, hammer coming back), stepped deterministically
		m.pose({"hammer": 1.0, "hammer_r": 1.0, "hammer_l": 1.0})
		m.fire_anim()
		var ct: float = m.def.get("cock_time", 0.5)
		for i in int(ct * 0.5 / 0.01):
			m._process(0.01)
	elif view == "detail" or view == "q34":
		m.pose({"hammer": 1.0, "hammer_r": 1.0, "hammer_l": 1.0})
	var box := _aabb(m)
	var c := box.get_center()
	var size := box.size.length()
	var floor_n: Node3D = get_node("Floor")
	floor_n.position.y = box.position.y - 0.03
	var dir := Vector3.ZERO
	var dist := size * 2.0
	var target := c
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 30
	match view:
		"q34":
			dir = Vector3(0.82, 0.32, 0.47)
			dist = size * 1.85
		"side":
			dir = Vector3(1, 0.04, 0)
			dist = size * 1.75
		"left":
			dir = Vector3(-1, 0.04, 0)
			dist = size * 1.75
		"front":
			var mz := m.marker("muzzle")
			target = mz.global_position if mz else c
			dir = Vector3(0.25, 0.12, -1)
			dist = 0.32
		"detail", "open", "cycle":
			var pistol: bool = m.def.get("slot", "") == "sidearm"
			var anchor := m.marker("holster_attach")
			target = anchor.global_position if anchor and pistol else Vector3(0, 0.02, -0.11 if not pistol else -0.04)
			if not pistol:
				target = Vector3(0, 0.035, -0.12)
			dir = Vector3(0.78, 0.38, -0.5)
			dist = 0.34 if pistol else 0.48
	cam.global_position = target + dir.normalized() * dist
	cam.look_at(target, Vector3.UP)
	await _capture(out_dir.path_join("%s_%s.png" % [id, view]))
	m.queue_free()
	await get_tree().process_frame

func _lineup(ids: PackedStringArray) -> void:
	var y := 0.0
	var models := []
	var widest := 0.0
	# long guns stacked, pistols side by side on the bottom row
	var pistols := []
	for id in ids:
		if Weapons.get_def(id).get("slot", "") == "sidearm":
			pistols.append(id)
			continue
		var m := WeaponModel.create(id)
		add_child(m)
		m.set_process(false)
		var b := _aabb(m)
		m.position = Vector3(0, y - b.position.y, -b.get_center().z)
		y += b.size.y + 0.05
		widest = maxf(widest, b.size.z)
		models.append(m)
	var x := -0.55
	var row_h := 0.0
	for id in pistols:
		var m := WeaponModel.create(id)
		add_child(m)
		m.set_process(false)
		var b := _aabb(m)
		m.position = Vector3(0, y - b.position.y, x - b.position.z - b.size.z)
		x += b.size.z + 0.06
		row_h = maxf(row_h, b.size.y)
		models.append(m)
	y += row_h
	var floor_n: Node3D = get_node("Floor")
	floor_n.position.y = -0.03
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var aspect := float(get_viewport().size.x) / float(get_viewport().size.y)
	cam.size = maxf(y + 0.12, (maxf(widest, 1.2) + 0.12) / aspect)
	cam.global_position = Vector3(3.0, y * 0.5, 0)
	cam.look_at(Vector3(0, y * 0.5, 0), Vector3.UP)
	await _capture(out_dir.path_join("lineup.png"))
	for m in models:
		m.queue_free()
