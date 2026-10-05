class_name Weapons
extends Node3D
## The player's arsenal, carried under the camera: the Capital's service carbine (automatic), a marksman rifle
## (4x scope), a sidearm, a rocket launcher, and grenades. First-person models are built from the Kit and move
## with sway (they lag the view), bob, recoil kick and recovery (the view climbs and settles), aim-down-sights,
## reload animations, muzzle flashes, shell ejection and spread that blooms with movement and firing.

const ARSENAL := [
	{"name": "LC-7 CARBINE", "auto": true, "rpm": 680.0, "mag": 32, "reserve": 192, "dmg": 34.0, "speed": 880.0,
		"spread": 0.9, "ads_spread": 0.15, "recoil": 0.9, "zoom": 0.7, "reload": 2.1, "tracer": 3},
	{"name": "LM-2 MARKSMAN", "auto": false, "rpm": 160.0, "mag": 10, "reserve": 50, "dmg": 92.0, "speed": 1050.0,
		"spread": 1.6, "ads_spread": 0.02, "recoil": 2.2, "zoom": 0.24, "reload": 2.6, "tracer": 1},
	{"name": "SIDEARM", "auto": false, "rpm": 380.0, "mag": 14, "reserve": 70, "dmg": 30.0, "speed": 400.0,
		"spread": 1.1, "ads_spread": 0.35, "recoil": 1.1, "zoom": 0.85, "reload": 1.5, "tracer": 0},
	{"name": "RL-4 LAUNCHER", "auto": false, "rpm": 30.0, "mag": 1, "reserve": 6, "dmg": 0.0, "speed": 160.0,
		"spread": 0.5, "ads_spread": 0.2, "recoil": 5.0, "zoom": 0.6, "reload": 3.2, "tracer": 0},
]

var cur := 0
var ammo: Array = []
var reserve: Array = []
var models: Array[Node3D] = []
var muzzles: Array[Node3D] = []
var cooldown := 0.0
var reloading := 0.0
var bloom := 0.0
var kick := 0.0
var sway := Vector2.ZERO
var _last_cam_rot := Vector3.ZERO
var grenades := 4
var ads := 0.0
var spread_px := 9.0
var _shots := 0
var _bob := 0.0
var _melee_t := 0.0
var mat: Material


func _ready() -> void:
	for w in ARSENAL:
		ammo.append(w["mag"])
		reserve.append(w["reserve"])
	mat = ShaderMaterial.new()
	(mat as ShaderMaterial).shader = load("res://shaders/building.gdshader")
	for i in ARSENAL.size():
		var m := _model(i)
		m.visible = i == cur
		m.position = Vector3(0.18, -0.2, -0.36)    # the hip pose (paused before the first pose, it sat in the camera)
		add_child(m)
		models.append(m)


func _model(i: int) -> Node3D:
	var root := Node3D.new()
	var k := Kit.new()
	var metal := k.col(Kit.METAL, 0.2)
	var white := k.col(Kit.STONE, 0.2, 1.0, false)
	var trim := k.col(Kit.TRIM, 0.2)
	var mz := Node3D.new()
	match i:
		0:
			# Carbine: a sleek white polymer body (side profile extruded), grey trim line, a top optic with a
			# smoked lens, a curved magazine, a slim barrel and muzzle brake.
			_side(k, [Vector2(0.30, 0.02), Vector2(0.30, -0.10), Vector2(0.22, -0.11), Vector2(0.10, -0.06),
				Vector2(-0.20, -0.05), Vector2(-0.36, -0.035), Vector2(-0.40, -0.005), Vector2(-0.40, 0.03),
				Vector2(-0.30, 0.05), Vector2(0.0, 0.056), Vector2(0.20, 0.05), Vector2(0.28, 0.036)], 0.028, white)
			_side(k, [Vector2(0.21, 0.004), Vector2(0.21, 0.016), Vector2(-0.33, 0.016), Vector2(-0.33, 0.004)], 0.0295, trim)
			_side(k, [Vector2(0.065, -0.055), Vector2(0.025, -0.055), Vector2(0.04, -0.16), Vector2(0.082, -0.16)], 0.016, trim)
			_side(k, [Vector2(-0.035, -0.05), Vector2(-0.095, -0.05), Vector2(-0.115, -0.175), Vector2(-0.07, -0.185)], 0.013, metal)
			_side(k, [Vector2(-0.02, 0.056), Vector2(-0.15, 0.056), Vector2(-0.16, 0.085), Vector2(-0.14, 0.1),
				Vector2(-0.03, 0.1), Vector2(-0.01, 0.085)], 0.018, metal)
			k.box(Transform3D.IDENTITY, Vector3(0, 0.083, -0.161), Vector3(0.03, 0.028, 0.004), k.col(Kit.DARKGLASS, 0.2, 1.0, false))
			k.tube(Vector3(0, 0.012, -0.40), Vector3(0, 0.012, -0.58), 0.011, 10, metal, true)
			k.tube(Vector3(0, 0.012, -0.56), Vector3(0, 0.012, -0.625), 0.017, 8, metal, true)
			mz.position = Vector3(0, 0.012, -0.64)
			_arms(k, Vector3(0.0, -0.1, 0.05), Vector3(0.0, -0.045, -0.27))
		1:
			k.box(Transform3D.IDENTITY, Vector3(0, 0, -0.2), Vector3(0.055, 0.08, 0.62), white)
			k.box(Transform3D.IDENTITY, Vector3(0, -0.02, 0.2), Vector3(0.045, 0.12, 0.26), white)
			k.tube(Vector3(0, 0.085, -0.02), Vector3(0, 0.085, -0.34), 0.026, 10, metal, true)
			k.tube(Vector3(0, 0.0, -0.5), Vector3(0, 0.0, -0.86), 0.013, 8, metal, true)
			k.box(Transform3D.IDENTITY, Vector3(0, -0.08, -0.1), Vector3(0.035, 0.1, 0.07), trim)
			mz.position = Vector3(0, 0, -0.88)
			_arms(k, Vector3(0.0, -0.11, 0.12), Vector3(0.0, -0.05, -0.36))
		2:
			k.box(Transform3D.IDENTITY, Vector3(0, 0, -0.06), Vector3(0.032, 0.045, 0.19), white)
			k.box(Transform3D.IDENTITY, Vector3(0, -0.06, 0.01), Vector3(0.028, 0.1, 0.045), trim)
			mz.position = Vector3(0, 0.005, -0.16)
			_arms(k, Vector3(0.0, -0.09, 0.02), Vector3(-0.03, -0.1, -0.01))
		3:
			k.tube(Vector3(0, 0, 0.3), Vector3(0, 0, -0.62), 0.065, 12, white, true)
			k.box(Transform3D.IDENTITY, Vector3(0, -0.09, -0.05), Vector3(0.035, 0.12, 0.06), trim)
			k.box(Transform3D.IDENTITY, Vector3(0.07, 0.04, -0.12), Vector3(0.03, 0.05, 0.14), metal)
			mz.position = Vector3(0, 0, -0.66)
			_arms(k, Vector3(0.0, -0.13, -0.05), Vector3(0.0, -0.08, -0.32))
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	root.add_child(mz)
	muzzles.append(mz)
	return root


## A side profile (z forward-negative, y up) extruded across the gun's width (x from -hw to hw).
func _side(k: Kit, prof: Array, hw: float, c: Color) -> void:
	var xf := Transform3D(Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)), Vector3.ZERO)
	k.prism(xf, PackedVector2Array(prof), -hw, hw, c, true, true)


## The soldier's arms: graphite undersuit sleeves (as the Capital's line troops wear under their white plates),
## grey cuffs and dark gloves, from the grip and the fore hand back out of view. (White dress sleeves vanished
## against the Capital's white ground; only ~20 cm of forearm is ever on screen, so it carries the contrast.)
func _arms(k: Kit, grip: Vector3, fore: Vector3) -> void:
	var sleeve := k.col(Kit.CLOTH, 0.6, 1.0, false)
	var cuff := k.col(Kit.TRIM, 0.6)
	var glove := k.col(Kit.METAL, 0.8)
	var r_elbow := grip + Vector3(0.16, -0.22, 0.42)
	var l_elbow := fore + Vector3(-0.2, -0.24, 0.36)
	for pr in [[grip, r_elbow, true], [fore, l_elbow, false]]:
		var hand: Vector3 = pr[0]
		var elbow: Vector3 = pr[1]
		var dir := (elbow - hand).normalized()
		if pr[2]:
			# Gripping hand: wrapped round the pistol grip, knuckles forward.
			k.box(Transform3D.IDENTITY, hand + Vector3(0, -0.005, -0.005), Vector3(0.058, 0.085, 0.07), glove)
			k.box(Transform3D.IDENTITY, hand + Vector3(-0.018, 0.035, -0.03), Vector3(0.022, 0.025, 0.05), glove)   # thumb
		else:
			# Supporting hand: palm under the handguard, fingers curled up its far side.
			k.box(Transform3D.IDENTITY, hand + Vector3(0, -0.035, 0), Vector3(0.07, 0.03, 0.1), glove)
			k.box(Transform3D.IDENTITY, hand + Vector3(-0.03, -0.01, 0), Vector3(0.016, 0.06, 0.09), glove)
		k.tube(hand + dir * 0.05, hand + dir * 0.1, 0.05, 10, cuff, true)
		k.tube(hand + dir * 0.1, elbow, 0.047, 10, sleeve, true)
		k.tube(elbow, elbow + Vector3(0, -0.1, 0.35), 0.055, 10, sleeve, true)


func w() -> Dictionary:
	return ARSENAL[cur]


func hud_text() -> String:
	var s := "%s   %d / %d" % [w()["name"], ammo[cur], reserve[cur]]
	if reloading > 0.0:
		s += "   RELOADING"
	return s + "\nGRENADES %d" % grenades


## Field of view while aiming (the player lerps toward it).
func zoom_fov(base: float, aiming: bool) -> float:
	return base * (w()["zoom"] if aiming else 1.0)


func _process(delta: float) -> void:
	var p: Player = G.player
	if p == null or p.vehicle != null:
		visible = false
		return
	visible = true
	cooldown = maxf(0.0, cooldown - delta)
	_melee_t = maxf(0.0, _melee_t - delta)
	var aiming := Input.is_action_pressed("aim")
	ads = move_toward(ads, 1.0 if aiming and reloading <= 0.0 else 0.0, delta * 6.0)
	# Switching.
	if Input.is_action_just_pressed("switch_weapon") or Input.is_action_just_pressed("weapon_next"):
		_select((cur + 1) % ARSENAL.size())
	elif Input.is_action_just_pressed("weapon_prev"):
		_select((cur + ARSENAL.size() - 1) % ARSENAL.size())
	for k in 4:
		if Input.is_action_just_pressed("weapon_%d" % (k + 1)):
			_select(k)
	# Reload.
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			var need: int = w()["mag"] - ammo[cur]
			var take: int = mini(need, reserve[cur])
			ammo[cur] += take
			reserve[cur] -= take
	elif Input.is_action_just_pressed("reload") and ammo[cur] < w()["mag"] and reserve[cur] > 0:
		_reload()
	# Fire.
	# Own edge detection: works for key, mouse and analogue trigger alike, whatever the node order.
	var trig := Input.is_action_pressed("fire") or Controls.trigger(true) > 0.4
	var just := trig and not _trig_was
	_trig_was = trig
	if reloading <= 0.0 and cooldown <= 0.0 and (trig if w()["auto"] else just):
		if ammo[cur] > 0:
			_fire(p)
		elif just:
			Sfx.play_ui("dry")
			if reserve[cur] > 0:
				_reload()
	if Input.is_action_just_pressed("grenade") and grenades > 0:
		_throw(p)
	if Input.is_action_just_pressed("melee") and _melee_t <= 0.0:
		_melee(p)
	# Spread: bloom recovers; moving widens it.
	var move := Vector2(p.velocity.x, p.velocity.z).length()
	bloom = maxf(0.0, bloom - delta * 3.5)
	var base: float = lerpf(w()["spread"], w()["ads_spread"], ads)
	var spread: float = base * (1.0 + move * 0.12 + bloom)
	spread_px = 6.0 + spread * 9.0
	_pose(delta, p, spread)


var _trig_was := false


func _select(i: int) -> void:
	if i == cur:
		return
	models[cur].visible = false
	cur = i
	models[cur].visible = true
	reloading = 0.0
	cooldown = 0.35
	models[cur].position = Vector3(0.2, -0.45, -0.3)
	Sfx.play_ui("reload")


func _reload() -> void:
	reloading = w()["reload"]
	Sfx.play_ui("reload")


func _fire(p: Player) -> void:
	ammo[cur] -= 1
	cooldown = 60.0 / float(w()["rpm"])
	_shots += 1
	var cam := p.camera
	var base: float = lerpf(w()["spread"], w()["ads_spread"], ads)
	var move := Vector2(p.velocity.x, p.velocity.z).length()
	var spread: float = deg_to_rad(base * (1.0 + move * 0.12 + bloom))
	var fwd := -cam.global_transform.basis.z
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var a := randf() * TAU
	var r := sqrt(randf()) * spread
	var dir := (fwd + right * cos(a) * r + up * sin(a) * r).normalized()
	var origin := cam.global_position
	var muzzle := muzzles[cur].global_position
	if cur == 3:
		if G.fx:
			G.fx.rocket(muzzle, origin + dir * 1500.0, 0, [p.get_rid()])
	else:
		var tr: int = w()["tracer"]
		G.combat.bullet(origin, dir, w()["speed"], w()["dmg"], 0, [p.get_rid()], tr > 0 and _shots % tr == 0, true)
		if G.fx:
			G.fx.flash(muzzle, 0.18)
	Sfx.player_shot(muzzle)
	# Recoil: the view climbs (recovering over time in Player), the model kicks back.
	var rec: float = w()["recoil"] * lerpf(1.0, 0.6, ads)
	p.pitch = clampf(p.pitch + deg_to_rad(rec * randf_range(0.6, 1.0)), deg_to_rad(-88.0), deg_to_rad(88.0))
	p.rotation.y += deg_to_rad(rec * randf_range(-0.3, 0.3))
	kick = minf(kick + rec * 0.035, 0.12)
	bloom = minf(bloom + rec * 0.35, 3.0)
	Controls.rumble(0.15 * rec, 0.25 * rec, 0.06)
	if G.fx and cur < 3:
		G.fx._emit(G.fx.sparks, muzzle + right * 0.05, right * randf_range(2.0, 3.5) + up * randf_range(1.0, 2.0), Color(1.4, 1.1, 0.5, 1.0))


func _throw(p: Player) -> void:
	grenades -= 1
	Sfx.play_ui("grenade_pin")
	var g := RigidBody3D.new()
	g.mass = 0.6
	g.collision_layer = 0
	g.collision_mask = 1 | 4 | 16
	g.continuous_cd = true
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.06
	cs.shape = sp
	g.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	mi.mesh = sm
	g.add_child(mi)
	get_tree().root.add_child(g)
	var cam := p.camera
	g.global_position = cam.global_position + (-cam.global_transform.basis.z) * 0.5
	g.linear_velocity = (-cam.global_transform.basis.z + Vector3(0, 0.25, 0)).normalized() * 19.0 + p.velocity
	g.angular_velocity = Vector3(randf(), randf(), randf()) * 8.0
	var t := get_tree().create_timer(3.2)
	t.timeout.connect(func():
		if is_instance_valid(g):
			if G.combat:
				G.combat.explode(g.global_position, 0.6)
			g.queue_free())


func _melee(p: Player) -> void:
	_melee_t = 0.8
	kick = 0.1
	if G.battle and G.battle.army:
		var cam := p.camera
		var hit: Array = G.battle.army.ray_hit(cam.global_position, -cam.global_transform.basis.z, 2.2)
		if not hit.is_empty():
			G.battle.army.hit_soldier(hit[0], 120.0, -cam.global_transform.basis.z)
			if G.hud:
				G.hud.hit_marker()


func _pose(delta: float, p: Player, _spread: float) -> void:
	# Sway: the model lags behind rotation.
	var rot := Vector3(p.pitch, p.rotation.y, 0)
	var d := rot - _last_cam_rot
	d.y = angle_difference(_last_cam_rot.y, rot.y)
	_last_cam_rot = rot
	sway = sway.lerp(Vector2(-d.y, d.x) * 2.0, 1.0 - exp(-delta * 10.0))
	sway = sway.lerp(Vector2.ZERO, 1.0 - exp(-delta * 6.0))
	var hv := Vector2(p.velocity.x, p.velocity.z).length()
	if p.is_on_floor():
		_bob += delta * hv * 1.7
	var bob := Vector3(cos(_bob * 0.5) * 0.012, absf(sin(_bob * 0.5)) * 0.014, 0.0) * clampf(hv / 6.0, 0.0, 1.0) * (1.0 - ads * 0.85)
	kick = maxf(0.0, kick - delta * 0.5)
	var hip := Vector3(0.18, -0.2, -0.36)
	var aimed := Vector3(0.0, -0.105 if cur != 1 else -0.12, -0.26)
	if cur == 2:
		hip = Vector3(0.16, -0.16, -0.3)
		aimed = Vector3(0.0, -0.075, -0.24)
	var target := hip.lerp(aimed, ads) + bob + Vector3(sway.x * 0.05, sway.y * 0.05, kick)
	if reloading > 0.0:
		var rt: float = 1.0 - reloading / float(w()["reload"])
		target += Vector3(0.0, -0.18 * sin(rt * PI), 0.05 * sin(rt * PI))
	var m := models[cur]
	m.position = m.position.lerp(target, 1.0 - exp(-delta * 18.0))
	var tilt := Vector3(kick * 1.6 + (0.6 * sin((1.0 - reloading / float(w()["reload"])) * PI) if reloading > 0.0 else 0.0), sway.x * 0.4, sway.x * 0.6)
	m.rotation = m.rotation.lerp(tilt, 1.0 - exp(-delta * 16.0))
	# The marksman scope hides the model when fully aimed.
	m.visible = not (cur == 1 and ads > 0.95)
