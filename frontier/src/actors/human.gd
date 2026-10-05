class_name Human
extends CharacterBody3D
## A person in the world (NPC): body, health, guns, locomotion and an AI brain. Movement mirrors the player's
## weighty locomotion (shared speeds) but is driven by `intent` from src/ai/brain.gd. Appearance comes from
## CharacterFactory when present (seeded), else a stand-in. Hitboxes per zone feed Damageable.
## Spawn with Human.spawn(parent, pos, {seed, role, faction, weapon, name}).

# gameplay roles -> generated character looks (CharacterFactory roles/tags); unknown roles pick any NPC
const ROLE_LOOKS := {"lawman": "lawman", "gunman": "drifter", "bartender": "townsman", "gambler": "gentleman",
	"shopkeeper": "townsman", "rancher": "rancher", "worker": "worker", "drover": "cowhand", "cowhand": "cowhand",
	"townsfolk": "", "traveller": "", "woman": "townswoman", "elder": "elder"}
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
var holder: WeaponHolder           # visible guns (src/combat/weapon_holder.gd); null when headless
var brain: Node
var visual: Node3D
var alive := true
var ragdoll_t := -1.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var stuck_events := 0
var nav: NavigationAgent3D
# town life (src/ai/routine.gd): anchored = held kinematically on an interaction spot (seat, counter, bar rail);
# doors on the way are opened via TownDoor.open_from; in_town = floors come from the navmesh when gliding far away
var anchored := false
var in_town := false
var doors_used := 0
var _anchor_from := Transform3D.IDENTITY
var _anchor_xf := Transform3D.IDENTITY
var _anchor_t := 1.0
var _anchor_blend := 0.6
var _door_t := 0.0
var _gy_t := 0.0
var _gy_off := 0.0
var _bump_t := 0.0
var _ghost_t := 0.0
var _ghost_path := PackedVector3Array()
var _ghost_i := 0
var _path := PackedVector3Array()
var _path_i := 0
var _path_goal := Vector3.INF
var _path_t := 0.0

static func spawn(parent: Node, pos: Vector3, opts: Dictionary = {}) -> Human:
	var t0 := Time.get_ticks_usec()
	var h := _spawn(parent, pos, opts)
	Game.prof("Human.spawn " + str(opts.get("role", "")), t0)
	return h

static func _spawn(parent: Node, pos: Vector3, opts: Dictionary = {}) -> Human:
	var h := Human.new()
	h.seed = int(opts.get("seed", randi()))
	h.role = opts.get("role", "townsfolk")
	h.faction = opts.get("faction", "civilian")
	h.display_name = opts.get("name", "Stranger")
	h.name = "%s_%d" % [h.display_name.replace(" ", ""), h.seed % 100000]
	parent.add_child(h)
	h.global_position = pos
	h._setup(opts)
	if opts.has("facing"):
		h.facing = float(opts.facing)
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
	if w != "":
		holder = WeaponHolder.attach(self, gun)     # only armed NPCs carry visible guns
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
	add_to_group("interactable")
	tree_exiting.connect(func(): if Game.terrain: Game.terrain.foci.erase(self))
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
		if factory.available():
			var look_id: String = opts.get("look_id", "")
			if look_id != "" and (not CharacterFactory._warming or CharacterFactory._is_ready(look_id)):
				visual = factory.spawn_id(look_id, {"variant_seed": seed})
			if visual == null:
				visual = factory.spawn(seed, opts.get("look", ROLE_LOOKS.get(role, "")))
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
	if opts.has("scale"):
		visual.scale = Vector3.ONE * float(opts.scale)
	add_child(visual)
	if not has_meta("voice_type"):
		set_meta("voice_type", opts.get("voice", _voice_for(visual.get("info") if visual.get("info") is Dictionary else {})))

## Bark voice for this person (audio manifest speakers): lawman, shopkeeper, man_old/young/rough/town, woman_old/town.
func _voice_for(info: Dictionary) -> String:
	var age := int(info.get("age", 35))
	if role == "lawman" or faction == "law":
		return "lawman"
	if role in ["shopkeeper", "bartender"]:
		return "shopkeeper"
	if str(info.get("sex", "male")) == "female":
		return "woman_old" if age >= 55 else "woman_town"
	if age >= 58:
		return "man_old"
	if faction in ["shale", "bandit"] or role in ["gunman", "drunk", "drover", "cowhand"]:
		return "man_rough"
	return "man_young" if age < 28 else "man_town"

func _physics_process(dt: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_physics_process_impl(dt)
	Game.acc("human", _pt0)

func _physics_process_impl(dt: float) -> void:
	if not alive:
		_dead_tick(dt)
		return
	if anchored:
		_anchor_tick(dt)
		return
	var target = intent.move_to
	var want := Vector3.ZERO
	var tspeed := 0.0
	if target != null:
		var tp: Vector3 = target
		var next := tp
		if in_town:
			next = _town_next(tp, dt)
		elif nav.get_navigation_map().is_valid() and NavigationServer3D.map_get_iteration_id(nav.get_navigation_map()) > 0:
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
	if _ghost_t > 0.0:
		_ghost_tick(dt)
	elif ActorLOD.far(self):
		ActorLOD.glide(self, dt)        # beyond physics range: walk the heightmap kinematically
		if in_town:
			_far_floor(dt)
	else:
		if in_town and want != Vector3.ZERO and is_on_floor():
			_step_up(dt)
		move_and_slide()
	if in_town:
		_town_tick(dt)
	visual.rotation.y = facing
	if visual.has_method("set_locomotion"):
		visual.set_locomotion(speed, "idle" if speed < 0.2 else ("walk" if speed < 2.4 else "run"), is_on_floor())
	if visual.has_method("set_aim"):
		var kind := ""
		if intent.aim_at != null and gun and not gun.weapons.is_empty():
			kind = str(Weapons.get_def(gun.weapon_id()).get("ammo", "revolver")).replace("revolver", "pistol")
		visual.set_aim(kind)
	# stuck detection (for the behaviour oracle)
	if target != null and tspeed > 0.5:
		_stuck_t += dt
		if _stuck_t > 4.0:
			if global_position.distance_to(_last_pos) < 0.5:
				stuck_events += 1
				Game.log_event("npc_stuck", {"npc": str(name), "pos": [global_position.x, global_position.z]})
				if Game.args.has("town_debug"):
					var col := get_last_slide_collision()
					var cn: String = str(col.get_collider().name) + "/" + str(col.get_collider().get_parent().name) if col and col.get_collider() else "-"
					var rt = brain.get("routine")
					print("STUCK %s spd %.2f/%.2f vel %s at %s next %s fin %s far %s hit %s last %s" % [name, speed, float(intent.speed), str(velocity.snapped(Vector3.ONE * 0.01)), str(global_position.snapped(Vector3.ONE * 0.01)),
						str(nav.get_next_path_position().snapped(Vector3.ONE * 0.01)), str(nav.is_navigation_finished()), str(ActorLOD.far(self)),
						cn, str(rt.last_type) if rt != null else ""])
				if brain.has_method("on_stuck"):
					brain.on_stuck()
				if in_town:
					_start_ghost()
			_stuck_t = 0.0
			_last_pos = global_position
	else:
		_stuck_t = 0.0
		_last_pos = global_position

# ------------------------------------------------------------------ town life

## Hold the body on an interaction spot (stand here, face -Z), blending there over `blend` seconds. No physics move
## while anchored (seats sit inside furniture colliders); the routine plays the matching activity.
func anchor_to(xf: Transform3D, blend := 0.6) -> void:
	anchored = true
	_anchor_from = Transform3D(Basis(Vector3.UP, facing), global_position)
	_anchor_xf = xf
	_anchor_blend = maxf(blend, 0.01)
	_anchor_t = 0.0 if blend > 0.0 else 1.0
	intent.move_to = null
	speed = 0.0
	velocity = Vector3.ZERO
	_stuck_t = 0.0
	if blend <= 0.0:
		global_position = xf.origin
		facing = spot_yaw(xf)

func release_anchor() -> void:
	anchored = false
	_stuck_t = 0.0
	_last_pos = global_position

static func spot_yaw(xf: Transform3D) -> float:
	return atan2(xf.basis.z.x, xf.basis.z.z)

func _anchor_tick(dt: float) -> void:
	if _anchor_t < 1.0:
		_anchor_t = minf(_anchor_t + dt / _anchor_blend, 1.0)
		var k := smoothstep(0.0, 1.0, _anchor_t)
		global_position = _anchor_from.origin.lerp(_anchor_xf.origin, k)
		facing = lerp_angle(facing, spot_yaw(_anchor_xf), 1.0 - exp(-10.0 * dt))
	else:
		global_position = _anchor_xf.origin
		facing = lerp_angle(facing, spot_yaw(_anchor_xf), 1.0 - exp(-6.0 * dt))
	if intent.face != null:
		var fd: Vector3 = intent.face
		if fd.length() > 0.01:
			facing = lerp_angle(facing, atan2(-fd.x, -fd.z), 1.0 - exp(-4.0 * dt))
	speed = 0.0
	visual.rotation.y = facing
	if visual.has_method("set_locomotion"):
		visual.set_locomotion(0.0, "idle", true)
	if visual.has_method("set_aim"):
		visual.set_aim("")

## Open doors in the way (NPCs path through doorways) and notice Ruth pushing past.
func _town_tick(dt: float) -> void:
	_door_t -= dt
	if _door_t <= 0.0 and speed > 0.3:
		_door_t = 0.25 if speed < 2.5 else 0.12
		var st = Game.main.settlements if Game.main else null
		if st != null:
			var fwd := Vector3(-sin(facing), 0, -cos(facing))
			var d: TownDoor = st.nearest_door(global_position + Vector3(0, 1.0, 0) + fwd * (0.8 + speed * 0.3), 1.5)
			if d != null:
				if d.kind == "batwing":
					d.push(self)
					doors_used += 1
				elif absf(d.target) < 0.01:
					doors_used += 1
					d.open_from(global_position, 2.5)
				else:
					d.keep_open(2.5)              # never re-swing a door someone is walking through
	_bump_t -= dt
	if _bump_t <= 0.0:
		_bump_t = 0.2
		var p = Game.player
		if p != null and is_instance_valid(p) and p.get("speed") != null and float(p.speed) > 0.6:
			var to: Vector3 = global_position - p.global_position
			to.y = 0.0
			if to.length() < 0.85 and brain.has_method("on_bumped"):
				var pv: Vector3 = p.velocity
				pv.y = 0.0
				if pv.length() > 0.3 and pv.normalized().dot(to.normalized()) > 0.4:
					brain.on_bumped(p)
					_bump_t = 2.0

## Unsticking (snagged on a porch lip, trough, post or a door leaf in the way): walk the navmesh path kinematically
## for a moment, ignoring physics, then hand back to the body.
func _start_ghost() -> void:
	_ghost_path = _path
	_ghost_i = clampi(_path_i, 0, maxi(_ghost_path.size() - 1, 0))
	_ghost_t = 1.6 if _ghost_path.size() > 1 else 0.0

## Town residents follow their own copy of the navmesh path (queried once per goal, refreshed every few seconds or
## when pushed off it): steadier than re-pathing every frame, and door links are walked straight through.
func _town_next(tp: Vector3, dt: float) -> Vector3:
	var m := nav.get_navigation_map()
	if not m.is_valid() or NavigationServer3D.map_get_iteration_id(m) == 0:
		return tp
	_path_t -= dt
	var off := 0.0
	if _path_i < _path.size() and _path_i > 0:
		off = _seg_dist(global_position, _path[_path_i - 1], _path[_path_i])
	if _path.is_empty() or tp.distance_to(_path_goal) > 0.3 or _path_t <= 0.0 or off > 2.5:
		_path = NavigationServer3D.map_get_path(m, global_position, tp, true)
		_path_i = 1
		_path_goal = tp
		_path_t = 8.0
	if _path.size() < 2:
		return tp
	while _path_i < _path.size() - 1 and Vector2(_path[_path_i].x - global_position.x, _path[_path_i].z - global_position.z).length() < 0.45:
		_path_i += 1
	return _path[mini(_path_i, _path.size() - 1)]

## True when the body has walked its path to the closest reachable point of the goal.
func path_done() -> bool:
	if not in_town:
		return nav.is_navigation_finished()
	if _path.size() < 2:
		return false
	var e: Vector3 = _path[_path.size() - 1]
	return _path_i >= _path.size() - 1 and Vector2(e.x - global_position.x, e.z - global_position.z).length() < 0.5

static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return (ap - ab * t).length()

func _ghost_tick(dt: float) -> void:
	_ghost_t -= dt
	var step := maxf(speed, 1.0) * dt
	while step > 0.0 and _ghost_i < _ghost_path.size():
		var p: Vector3 = _ghost_path[_ghost_i]
		var to := p - global_position
		var d := to.length()
		if d <= step:
			global_position = p
			step -= d
			_ghost_i += 1
		else:
			global_position += to / d * step
			step = 0.0
			facing = lerp_angle(facing, atan2(-to.x, -to.z), 1.0 - exp(-10.0 * dt))
	if _ghost_i >= _ghost_path.size():
		_ghost_t = 0.0
	velocity = Vector3.ZERO
	_last_pos = global_position

## Climb a small lip (boardwalk edge, threshold, porch step up to 0.3 m) that the capsule would treat as a wall.
func _step_up(dt: float) -> void:
	var motion := Vector3(velocity.x, 0.0, velocity.z) * dt * 2.0
	if motion.length() < 0.001 or not test_move(global_transform, motion):
		return
	var lift := Vector3(0, 0.32, 0)
	if test_move(global_transform, lift):
		return
	var raised := global_transform.translated(lift)
	if not test_move(raised, motion):
		global_position += lift

## Gliding beyond physics range follows the heightmap; inside buildings the floor is the navmesh's.
func _far_floor(_dt: float) -> void:
	var m := nav.get_navigation_map()
	if m.is_valid() and NavigationServer3D.map_get_iteration_id(m) > 0:
		var cp := NavigationServer3D.map_get_closest_point(m, global_position + Vector3(0, 0.6, 0))
		if Vector2(cp.x - global_position.x, cp.z - global_position.z).length() < 0.6 and cp.y > global_position.y - 0.3:
			global_position.y = cp.y

## Residents of a town: a slimmer collision capsule than the navmesh agent radius (0.25 m) so paths that hug walls
## and porch posts don't snag; doors and navmesh floors as above.
func set_town_mode() -> void:
	in_town = true
	for c in get_children():
		if c is CollisionShape3D and c.shape is CapsuleShape3D:
			(c.shape as CapsuleShape3D).radius = 0.21

func interact_prompt() -> String:
	if not alive or brain == null or brain.state in [brain.State.COMBAT, brain.State.FLEE]:
		return ""
	if has_meta("held_up") and not has_meta("robbed") and brain.state == brain.State.SURRENDER:
		return "Rob %s" % display_name
	return "Greet %s" % display_name if faction in ["civilian", "law"] else ""

func interact(_who: Node) -> void:
	if has_meta("held_up") and not has_meta("robbed") and Game.get("robbery"):
		Game.robbery.rob(self)
		return
	if Game.missions:
		var lines := ["bark_greet_01", "bark_greet_02", "bark_greet_03"]
		Game.missions.say(lines[seed % lines.size()], self)
	if Game.state:
		Game.state.good_deed("greet")
	intent.face = Game.player.global_position - global_position

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
	# flash at the visible gun's real muzzle when a WeaponHolder shows one (ballistics keep `muzzle`)
	if holder and holder.has_drawn_model():
		var mt := holder.muzzle_transform()
		Effects.muzzle_flash(get_tree().current_scene, mt.origin, -mt.basis.z)
	else:
		Effects.muzzle_flash(get_tree().current_scene, muzzle, dir)
	return true

func _on_damaged(info: Dictionary) -> void:
	if Game.state and info.get("attacker") == Game.player and damageable.alive and faction in ["civilian", "law"] \
		and not (brain.aggressive and brain.target == Game.player):
		Game.state.crime("assault", global_position, self)
	if brain and brain.has_method("on_damaged"):
		brain.on_damaged(info)
	if visual.has_method("hit") and damageable.alive:
		visual.hit(info)
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
	_judge_kill(info)
	if visual.has_method("die"):
		visual.die(info)
	if Game.terrain:
		Game.terrain.foci.erase(self)

## The law and Standing judge a killing by who it was and whether they were fighting Ruth.
func _judge_kill(info: Dictionary) -> void:
	if Game.state == null or info.get("attacker") != Game.player:
		return
	var self_defense: bool = brain != null and (brain.aggressive or brain.state == brain.State.COMBAT) and brain.target == Game.player
	if self_defense or faction in ["shale", "bandit"]:
		Game.state.kills.outlaw += 1
		if brain.state == brain.State.SURRENDER:
			Game.state.change_standing(-6.0, "killed a man who surrendered")
		return
	if faction == "law":
		Game.state.kills.law += 1
		Game.state.crime("murder_lawman", global_position, self)
	else:
		Game.state.kills.civilian += 1
		Game.state.crime("murder", global_position, self)

func _dead_tick(dt: float) -> void:
	# stand-in fall: topple over the first second (the character rig replaces this with ragdoll)
	if ragdoll_t >= 0.0 and ragdoll_t < 1.0 and not visual.has_method("die"):
		ragdoll_t += dt
		visual.rotation.x = lerpf(0.0, -PI * 0.5, minf(ragdoll_t * 1.6, 1.0))
		visual.position.y = lerpf(0.0, 0.25, minf(ragdoll_t * 1.6, 1.0))
	if ActorLOD.far(self):
		global_position.y = Game.world.height(global_position.x, global_position.z)   # bodies stay on the ground
	elif not is_on_floor():
		velocity = Vector3(0, velocity.y - 9.81 * dt, 0)
		move_and_slide()
