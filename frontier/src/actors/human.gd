class_name Human
extends CharacterBody3D
## A person in the world (NPC): body, health, guns, locomotion and an AI brain. Movement mirrors the player's
## weighty locomotion (shared speeds) but is driven by `intent` from src/ai/brain.gd. Appearance comes from
## CharacterFactory when present (seeded), else a stand-in. Hitboxes per zone feed Damageable.
## Spawn with Human.spawn(parent, pos, {seed, role, faction, weapon, name}).

const WALK := 1.45
const JOG := 3.5
const SPRINT := 6.0

var role := "townsfolk"            # townsfolk, lawman, gunman, rancher, worker, shopkeeper...
var faction := "civilian"          # civilian, law, outfit, shale, syndicate, bandit
var display_name := "Stranger"
var seed := 0
var intent := {"move_to": null, "speed": WALK, "face": null, "aim_at": null, "fire": false, "crouch": false}
var speed := 0.0
var facing := 0.0
var damageable: Damageable
var gun: GunHandler
var brain: Node
var visual: Node3D
var alive := true
var ragdoll_t := -1.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var stuck_events := 0
var nav: NavigationAgent3D

static func spawn(parent: Node, pos: Vector3, opts: Dictionary = {}) -> Human:
	var h := Human.new()
	h.seed = int(opts.get("seed", randi()))
	h.role = opts.get("role", "townsfolk")
	h.faction = opts.get("faction", "civilian")
	h.display_name = opts.get("name", "Stranger")
	h.name = "%s_%d" % [h.display_name.replace(" ", ""), h.seed % 100000]
	parent.add_child(h)
	h.global_position = pos
	h._setup(opts)
	return h

func _setup(opts: Dictionary) -> void:
	collision_layer = 8
	collision_mask = 1 | 2 | 8
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.76
	cs.shape = cap
	cs.position.y = 0.88
	add_child(cs)
	damageable = Damageable.new()
	damageable.max_health = float(opts.get("health", 100.0))
	add_child(damageable)
	damageable.damaged.connect(_on_damaged)
	damageable.died.connect(_on_died)
	_make_hitboxes()
	gun = GunHandler.new()
	add_child(gun)
	var w: String = opts.get("weapon", "")
	if w != "":
		gun.weapons = [w]
	gun.setup(self, damageable, false)
	_build_visual(opts)
	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.8
	nav.target_desired_distance = 0.8
	nav.radius = 0.35
	nav.avoidance_enabled = true
	add_child(nav)
	var brain_script: Script = load("res://src/ai/brain.gd")
	brain = brain_script.new()
	brain.name = "Brain"
	add_child(brain)
	brain.setup(self, opts)
	facing = randf() * TAU
	add_to_group("humans")
	if Game.terrain:
		Game.terrain.foci.append(self)

func _make_hitboxes() -> void:
	var hb := Node3D.new()
	hb.name = "Hitboxes"
	add_child(hb)
	var head := SphereShape3D.new(); head.radius = 0.13
	Damageable.make_hitbox(hb, damageable, "head", head, Transform3D(Basis(), Vector3(0, 1.62, 0)))
	var neck := SphereShape3D.new(); neck.radius = 0.07
	Damageable.make_hitbox(hb, damageable, "neck", neck, Transform3D(Basis(), Vector3(0, 1.48, 0)))
	var chest := BoxShape3D.new(); chest.size = Vector3(0.42, 0.4, 0.26)
	Damageable.make_hitbox(hb, damageable, "chest", chest, Transform3D(Basis(), Vector3(0, 1.26, 0)))
	var belly := BoxShape3D.new(); belly.size = Vector3(0.38, 0.28, 0.24)
	Damageable.make_hitbox(hb, damageable, "belly", belly, Transform3D(Basis(), Vector3(0, 0.95, 0)))
	var arms := BoxShape3D.new(); arms.size = Vector3(0.75, 0.12, 0.14)
	Damageable.make_hitbox(hb, damageable, "arm", arms, Transform3D(Basis(), Vector3(0, 1.22, 0)))
	var legs := BoxShape3D.new(); legs.size = Vector3(0.36, 0.8, 0.22)
	Damageable.make_hitbox(hb, damageable, "leg", legs, Transform3D(Basis(), Vector3(0, 0.42, 0)))

func _build_visual(opts: Dictionary) -> void:
	var factory = load("res://src/actors/character_factory.gd") if ResourceLoader.exists("res://src/actors/character_factory.gd") else null
	if factory != null and factory.has_method("spawn"):
		visual = factory.spawn(seed, role)
	if visual == null:
		visual = Node3D.new()
		var r := RandomNumberGenerator.new()
		r.seed = seed
		var coat := Color.from_hsv(r.randf_range(0.02, 0.12), r.randf_range(0.2, 0.5), r.randf_range(0.18, 0.5))
		if faction in ["shale", "bandit"]:
			coat = Color(0.15, 0.12, 0.1)
		elif faction == "law":
			coat = Color(0.25, 0.2, 0.16)
		var body := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.24
		cm.height = 1.48
		body.mesh = cm
		body.position.y = 0.8
		var m := StandardMaterial3D.new()
		m.albedo_color = coat
		m.roughness = 0.9
		body.material_override = m
		visual.add_child(body)
		var head := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		head.mesh = sm
		head.position.y = 1.64
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color.from_hsv(0.07, r.randf_range(0.3, 0.6), r.randf_range(0.35, 0.8))
		head.material_override = hm
		visual.add_child(head)
		if r.randf() < 0.8:
			var hat := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.12
			cyl.bottom_radius = 0.21
			cyl.height = 0.14
			hat.mesh = cyl
			hat.position.y = 1.77
			var hatm := StandardMaterial3D.new()
			hatm.albedo_color = Color.from_hsv(0.08, 0.3, r.randf_range(0.1, 0.4))
			hat.material_override = hatm
			visual.add_child(hat)
	add_child(visual)

func _physics_process(dt: float) -> void:
	if not alive:
		_dead_tick(dt)
		return
	var target = intent.move_to
	var want := Vector3.ZERO
	var tspeed := 0.0
	if target != null:
		var tp: Vector3 = target
		var next := tp
		if nav.get_navigation_map().is_valid() and NavigationServer3D.map_get_iteration_id(nav.get_navigation_map()) > 0:
			nav.target_position = tp
			if not nav.is_navigation_finished():
				next = nav.get_next_path_position()
		var to := Vector3(next.x - global_position.x, 0, next.z - global_position.z)
		if Vector3(tp.x - global_position.x, 0, tp.z - global_position.z).length() > 0.6:
			want = to.normalized()
			tspeed = float(intent.speed)
			if intent.crouch:
				tspeed = minf(tspeed, 1.3)
			# don't walk into water or off cliffs: probe ahead on the heightmap
			if Game.world:
				var ahead := global_position + want * 1.5
				var dh := Game.world.height(ahead.x, ahead.z) - Game.world.height(global_position.x, global_position.z)
				if dh < -2.5 or Game.world.is_water(ahead.x, ahead.z):
					want = want.rotated(Vector3.UP, 0.9)
	speed = move_toward(speed, tspeed, (7.0 if tspeed > speed else 9.0) * dt)
	var face_dir = intent.face
	if intent.aim_at != null:
		var a: Vector3 = intent.aim_at
		face_dir = Vector3(a.x - global_position.x, 0, a.z - global_position.z)
	elif face_dir == null and want != Vector3.ZERO:
		face_dir = want
	if face_dir != null and (face_dir as Vector3).length() > 0.01:
		var fd: Vector3 = face_dir
		var want_yaw := atan2(-fd.x, -fd.z)
		facing = lerp_angle(facing, want_yaw, 1.0 - exp(-lerpf(9.0, 3.5, speed / SPRINT) * dt))
	var move_dir := want if want != Vector3.ZERO else Vector3(-sin(facing), 0, -cos(facing))
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= 9.81 * dt
	move_and_slide()
	visual.rotation.y = facing
	if visual.has_method("set_locomotion"):
		visual.set_locomotion(speed, "idle" if speed < 0.2 else ("walk" if speed < 2.4 else "run"), is_on_floor())
	# stuck detection (for the behaviour oracle)
	if target != null and tspeed > 0.5:
		_stuck_t += dt
		if _stuck_t > 4.0:
			if global_position.distance_to(_last_pos) < 0.5:
				stuck_events += 1
				Game.log_event("npc_stuck", {"npc": str(name), "pos": [global_position.x, global_position.z]})
				if brain.has_method("on_stuck"):
					brain.on_stuck()
			_stuck_t = 0.0
			_last_pos = global_position
	else:
		_stuck_t = 0.0
		_last_pos = global_position

## Fire at a world point if the gun allows; returns true if a shot went off.
func shoot_at(p: Vector3, accuracy_scale: float) -> bool:
	if not gun.drawn:
		gun.drawn = true
		gun.cooldown = 0.5
		return false
	if not gun.can_fire():
		if gun.clip.get(gun.weapon_id(), 0) <= 0:
			gun.start_reload()
		return false
	var muzzle := global_position + Vector3(0, 1.42, 0) + Vector3(-sin(facing), 0, -cos(facing)) * 0.35
	var dir := (p - muzzle).normalized()
	gun.fire(muzzle, dir, true, accuracy_scale * 2.0)
	Effects.muzzle_flash(get_tree().current_scene, muzzle, dir)
	return true

func _on_damaged(info: Dictionary) -> void:
	if brain and brain.has_method("on_damaged"):
		brain.on_damaged(info)
	# flinch: a small shove in the hit direction
	var d: Vector3 = info.get("direction", Vector3.ZERO)
	velocity += Vector3(d.x, 0, d.z) * 1.5

func _on_died(info: Dictionary) -> void:
	alive = false
	ragdoll_t = 0.0
	collision_layer = 0
	for a in find_children("*", "Area3D", true, false):
		a.queue_free()
	Game.log_event("npc_died", {"npc": str(name), "faction": faction, "by": str(info.get("attacker", null).name) if info.get("attacker") else ""})
	if brain and brain.has_method("on_died"):
		brain.on_died(info)
	if visual.has_method("die"):
		visual.die(info)
	if Game.terrain:
		Game.terrain.foci.erase(self)

func _dead_tick(dt: float) -> void:
	# stand-in fall: topple over the first second (the character rig replaces this with ragdoll)
	if ragdoll_t >= 0.0 and ragdoll_t < 1.0 and not visual.has_method("die"):
		ragdoll_t += dt
		visual.rotation.x = lerpf(0.0, -PI * 0.5, minf(ragdoll_t * 1.6, 1.0))
		visual.position.y = lerpf(0.0, 0.25, minf(ragdoll_t * 1.6, 1.0))
	if not is_on_floor():
		velocity = Vector3(0, velocity.y - 9.81 * dt, 0)
		move_and_slide()
