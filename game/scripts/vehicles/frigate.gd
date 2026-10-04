class_name Frigate
extends AnimatableBody3D
## A Capital sky frigate, 180 m: a white lens-shaped hull with stacked decks, a glass bridge tower, a garden
## atrium under glass on the aft deck, engine nacelles with glowing exhausts, five twin 15 cm turrets (three
## dorsal, two ventral), a landing pad on the foredeck. Patrols a loop between the citadel and the front at
## altitude (kinematic, so people standing on the deck ride along); the turrets engage Cinder groups below.
## Take the helm on the bridge to fly it: stick / WASD heading and speed, A / Space and B / C altitude,
## RT / LMB fires every turret that bears on the crosshair.

const LENGTH := 180.0

var route: Array[Vector3] = []
var route_i := 0
var speed := 0.0
var cruise := 26.0
var yaw := 0.0
var alt_offset := 230.0
var turrets: Array = []          # [yaw node, pitch node, muzzle, reload]
var helm: Player = null
var cam: VehicleCam
var engines: Array[OmniLight3D] = []
var _bank := 0.0
var hp := 30000.0
var mat: Material


func build(m: Material, start: Vector3, loop: Array[Vector3]) -> void:
	mat = m
	route = loop
	sync_to_physics = false
	collision_layer = 4
	collision_mask = 0
	var k := Kit.new()
	var hull := Kit.lens(LENGTH, 38.0, 14)
	# Rotate the lens so its long axis runs along z (bow at -z).
	var plan := PackedVector2Array()
	for v in hull:
		plan.append(Vector2(v.y, v.x))
	var I := Transform3D.IDENTITY
	k.prism(I, Kit.scaled(plan, 0.82), -9.0, -4.0, k.col(Kit.STONE, 0.7, 2.5, false), true, true)
	k.prism(I, plan, -4.0, 2.0, k.col(Kit.BANDED, 0.7, 3.0), true, false, k.col(Kit.STONE, 0.7))
	k.band(I, plan, 1.4, 0.8, 0.6, k.col(Kit.TRIM, 0.7), false)
	var deck2 := Kit.scaled(plan, 0.7)
	k.prism(I, deck2, 2.0, 7.0, k.col(Kit.GLASS, 0.75, 2.5), true, false, k.col(Kit.STONE, 0.7))
	k.band(I, deck2, 6.4, 0.7, 0.4, k.col(Kit.TRIM, 0.7), false)
	# Keel fins below and a spine.
	k.box(I, Vector3(0, -13.0, 10.0), Vector3(1.6, 8.0, 70.0), k.col(Kit.STONE, 0.7))
	for s in [-1.0, 1.0]:
		k.box(Transform3D(Basis(Vector3.FORWARD, s * 0.5), Vector3(s * 8.0, -9.0, 20.0)), Vector3.ZERO, Vector3(1.2, 9.0, 40.0), k.col(Kit.STONE, 0.7))
	# Bridge tower aft of midships: a chamfered tower, a wide glass bridge, a mast.
	var tower := Kit.chamfer_rect(18.0, 26.0, 5.0)
	k.prism(Transform3D(Basis.IDENTITY, Vector3(0, 7.0, 22.0)), tower, 0.0, 16.0, k.col(Kit.BANDED, 0.8, 4.0), true)
	k.prism(Transform3D(Basis.IDENTITY, Vector3(0, 7.0, 18.0)), Kit.chamfer_rect(24.0, 10.0, 3.0), 16.0, 21.0, k.col(Kit.GLASS, 0.8, 5.0), true)
	k.band(Transform3D(Basis.IDENTITY, Vector3(0, 7.0, 18.0)), Kit.chamfer_rect(24.0, 10.0, 3.0), 21.0, 0.8, 0.6, k.col(Kit.TRIM, 0.8))
	k.tube(Vector3(0, 28.0, 24.0), Vector3(0, 48.0, 24.0), 0.6, 6, k.col(Kit.METAL, 0.8), true)
	k.box(I, Vector3(0, 40.0, 24.0), Vector3(10.0, 0.5, 0.5), k.col(Kit.METAL, 0.8))
	# Garden atrium under a glass vault on the aft deck.
	var atrium_c := Vector3(0, 7.0, 52.0)
	k.prism(Transform3D(Basis.IDENTITY, atrium_c), Kit.ngon(9.0, 16), 0.0, 0.8, k.col(Kit.GARDEN, 0.8), true)
	k.dome(atrium_c + Vector3(0, 0.8, 0), 9.6, 5, 16, k.col(Kit.GLASS, 0.85, 3.0, false), 0.8)
	# Landing pad on the foredeck.
	k.disc(Vector3(0, 7.3, -38.0), 13.0, 0.3, 20, k.col(Kit.TRIM, 0.6), k.col(Kit.PAD, 0.6))
	# Engine nacelles at the stern.
	for s in [-1.0, 1.0]:
		k.tube(Vector3(s * 12.0, -1.0, 62.0), Vector3(s * 12.0, -1.0, 94.0), 4.0, 14, k.col(Kit.STONE, 0.7), false)
		k.tube(Vector3(s * 12.0, -1.0, 93.0), Vector3(s * 12.0, -1.0, 95.0), 3.4, 14, k.col(Kit.PAD, 0.9, 1.0, true), true)
		var l := OmniLight3D.new()
		l.position = Vector3(s * 12.0, -1.0, 100.0)
		l.light_color = Color(0.7, 0.85, 1.0)
		l.omni_range = 40.0
		l.light_energy = 4.0
		l.distance_fade_enabled = true
		l.distance_fade_begin = 1500.0
		l.distance_fade_length = 300.0
		add_child(l)
		engines.append(l)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	mi.material_override = mat
	mi.visibility_range_end = 14000.0
	add_child(mi)
	_glow(Vector3(-12, -1, 95.2))
	_glow(Vector3(12, -1, 95.2))
	# Deck collision: the walkable decks and the bridge tower.
	_box(Vector3(0, -1.0, 0), Vector3(30.0, 6.0, 150.0))
	_box(Vector3(0, 4.5, 0), Vector3(24.0, 5.0, 120.0))
	_box(Vector3(0, 15.0, 22.0), Vector3(18.0, 16.0, 26.0))
	# Turrets: three dorsal on the centreline, two ventral.
	for z in [-62.0, -20.0, 70.0]:
		_turret(Vector3(0, 7.0, z), false)
	for z in [-40.0, 40.0]:
		_turret(Vector3(0, -9.0, z), true)
	global_position = start
	yaw = 0.0
	G.add_interactable(self, Vector3(0, 23.6, 16.0), 6.0, "Take the frigate's helm", _take_helm)


func _glow(at: Vector3) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 3.6
	s.height = 2.0
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.75, 0.88, 1.0)
	sm.emission_enabled = true
	sm.emission = Color(0.6, 0.8, 1.0)
	sm.emission_energy_multiplier = 6.0
	s.material = sm
	m.mesh = s
	m.position = at
	m.rotation.x = PI * 0.5
	add_child(m)


func _box(c: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = c
	add_child(cs)


func _turret(at: Vector3, ventral: bool) -> void:
	var y := Node3D.new()
	y.position = at
	if ventral:
		y.rotation.z = PI
	add_child(y)
	var k := Kit.new()
	k.prism(Transform3D.IDENTITY, Kit.ngon(3.6, 12), 0.0, 1.0, k.col(Kit.TRIM, 0.6, 1.0, false), true)
	var house := PackedVector2Array([Vector2(-3.0, -3.2), Vector2(3.0, -3.2), Vector2(3.6, 0.0), Vector2(3.4, 3.6), Vector2(-3.4, 3.6), Vector2(-3.6, 0.0)])
	k.prism(Transform3D.IDENTITY, house, 1.0, 3.6, k.col(Kit.STONE, 0.6, 1.5, false), true)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	mi.material_override = mat
	y.add_child(mi)
	var p := Node3D.new()
	p.position = Vector3(0, 2.4, -2.8)
	y.add_child(p)
	var g := Kit.new()
	for s in [-1.0, 1.0]:
		g.tube(Vector3(s * 0.9, 0, 0), Vector3(s * 0.9, 0, -9.0), 0.28, 10, g.col(Kit.METAL, 0.6), true)
	var gmi := MeshInstance3D.new()
	gmi.mesh = g.commit()
	gmi.material_override = mat
	p.add_child(gmi)
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0, 0, -9.5)
	p.add_child(muzzle)
	turrets.append([y, p, muzzle, randf() * 6.0, ventral])


func _take_helm(pl: Player) -> void:
	if helm:
		return
	helm = pl
	pl.enter_vehicle(self)
	cam = VehicleCam.new()
	get_tree().root.add_child(cam)
	var ex: Array[RID] = [get_rid()]
	cam.attach(self, 170.0, 30.0, ex)
	if G.hud:
		G.hud.message("Frigate helm: stick / WASD heading and speed, A / Space climb, B / C descend, RT / LMB fire the turrets")


func exit(pl: Player) -> void:
	if helm != pl:
		return
	helm = null
	pl.exit_vehicle(global_transform * Vector3(0, 23.6, 12.0))
	if cam:
		cam.queue_free()
		cam = null


func hud_text() -> String:
	return "FRIGATE  %3d km/h  ALT %4d m\nTURRETS %d" % [int(speed * 3.6), int(global_position.y), turrets.size()]


func _physics_process(delta: float) -> void:
	var p := global_position
	var turn := 0.0
	var climb := 0.0
	if helm and cam:
		var mv := Controls.move_vector()
		turn = -mv.x * 0.12
		speed = move_toward(speed, clampf(speed + mv.y * 6.0, -6.0, 40.0), delta * 4.0)
		climb = (float(Input.is_action_pressed("ascend")) - float(Input.is_action_pressed("descend"))) * 8.0
	elif route.size() > 0:
		var goal := route[route_i]
		var to := goal - p
		to.y = 0.0
		if to.length() < 220.0:
			route_i = (route_i + 1) % route.size()
		var want_yaw := atan2(-to.x, -to.z)
		turn = clampf(angle_difference(yaw, want_yaw), -1.0, 1.0) * 0.06
		speed = move_toward(speed, cruise, delta * 1.5)
		var ground := maxf(G.world.ground_at(p.x, p.z), G.world.ground_at(p.x - sin(yaw) * 400.0, p.z - cos(yaw) * 400.0))
		climb = clampf(ground + alt_offset - p.y, -6.0, 6.0)
	yaw += turn * delta
	_bank = lerpf(_bank, -turn * 2.5, 1.0 - exp(-delta * 0.8))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	global_position = p + fwd * speed * delta + Vector3(0, climb * delta, 0)
	rotation = Vector3(0.0, yaw, _bank)


func _process(delta: float) -> void:
	for e in engines:
		e.light_energy = 3.0 + speed * 0.08 + sin(Time.get_ticks_msec() * 0.02) * 0.3
	# Turrets: under player control they follow the crosshair; otherwise they engage Cinder soldiers below.
	var aim := Vector3.ZERO
	var has_aim := false
	if helm and cam:
		aim = cam.aim_point([get_rid()])
		has_aim = true
	elif G.battle and G.battle.army:
		var e := G.battle.army.nearest_enemy(global_position, 0, 2500.0)
		if e >= 0:
			aim = G.battle.army.pos[e]
			has_aim = true
	for t in turrets:
		var y: Node3D = t[0]
		var pn: Node3D = t[1]
		t[3] = maxf(0.0, t[3] - delta)
		if not has_aim:
			continue
		var local := y.global_transform.affine_inverse() * aim
		var want := atan2(-local.x, -local.z)
		y.rotation.y += clampf(angle_difference(0.0, want), -0.5 * delta, 0.5 * delta)
		var lp := pn.global_transform.affine_inverse() * aim
		var want_p := atan2(lp.y, -lp.z)
		pn.rotation.x = clampf(pn.rotation.x + clampf(want_p, -0.4 * delta, 0.4 * delta), -0.1, 1.2)
		var laid := absf(want) < 0.05 and absf(want_p) < 0.05
		var fire := (helm != null and (Input.is_action_pressed("fire") or Controls.trigger(true) > 0.4)) or (helm == null and randf() < 0.01)
		if laid and fire and t[3] <= 0.0:
			t[3] = 6.0
			var m: Node3D = t[2]
			if G.combat and G.combat.has_method("shell"):
				G.combat.shell(m.global_position, -m.global_transform.basis.z, 520.0, 1.6, 0, [get_rid()])
			elif G.fx:
				G.fx.flash(m.global_position, 4.0)
				G.fx.explosion(aim + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15)), 1.4)


func damage(amount: float, _at: Vector3) -> void:
	hp -= amount
	if hp <= 0.0 and G.combat:
		G.combat.destroy_vehicle(self)
