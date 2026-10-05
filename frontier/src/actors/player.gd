extends CharacterBody3D
## Ruth Caddell on foot: weighty third-person locomotion (walk / jog / sprint with stamina, acceleration and
## speed-dependent turn rates, slope slowdown, step-up, jumping), an over-the-shoulder orbit camera with collision,
## and an `intent` interface so bots drive exactly the same code path as a human (src/tests/bot_runner.gd).
## The visual body is a CharacterFactory character when available, else a simple stand-in.

signal mounted(horse: Node)
signal dismounted

const WALK := 1.55
const JOG := 3.7
const SPRINT := 6.6
const ACCEL := 7.0
const DECEL := 9.0
const GRAVITY := 9.81
const JUMP_V := 4.4
const STAMINA_MAX := 100.0

var camera: Camera3D
var cam_yaw := 0.0
var cam_pitch := -0.12
var cam_dist := 3.4
var cam_side := 0.55
var cam_shoulder := 1.0
var mouse_sens := 0.0025
var invert_y := false
var pad_sens := 2.6
var base_fov := 62.0           # settings > Field of view (aiming narrows from here)
var intent := {"move": Vector2.ZERO, "sprint": false, "walk": false, "jump": false, "aim": false, "fire": false,
	"interact": false, "crouch": false, "cover": false, "melee": false, "lasso": false}
var bot_driven := false
var stamina := STAMINA_MAX
var health := 100.0
var speed := 0.0               # current planar speed (m/s)
var facing := 0.0              # body yaw (radians)
var on_horse: Node = null
var gait := "idle"
var visual: Node3D
var _cam_target := Vector3.ZERO
var _cam_cur_dist := 3.4
var _walk_mode := false
var _aim_latch := false        # accessibility: toggle-to-aim
var _aim_prev := false
var _last_floor_y := 0.0
var _air_time := 0.0
var fall_damage_taken := 0.0
var gun: GunHandler
var holder: WeaponHolder       # visible guns: holsters, hand pose, part animation (src/combat/weapon_holder.gd)
var damageable: Damageable
var nerve: Nerve
var hud: CanvasLayer

func setup(cam: Camera3D) -> void:
	camera = cam
	InputSetup.ensure()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.78
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.89
	add_child(cs)
	collision_layer = 2
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.45
	max_slides = 6
	_build_visual()
	_setup_combat()
	cam_yaw = rotation.y
	facing = rotation.y
	_cam_target = global_position + Vector3(0, 1.6, 0)
	if not Game.headless and not bot_driven and not Game.args.has("bot") and not Game.args.has("benchmark"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if OS.has_feature("android") or Game.args.has("vr") or Game.args.has("vr_sim"):
		var vr := VR.try_start()
		if vr != null:
			add_child(vr)
			vr.attach(self, get_tree().current_scene)

func _setup_combat() -> void:
	damageable = Damageable.new()
	damageable.name = "Damageable"
	damageable.max_health = 100.0
	damageable.regen_rate = 4.0
	damageable.damage_scale = float(Game.args.get("player_damage_scale", 0.3))   # "normal" difficulty
	add_child(damageable)
	damageable.damaged.connect(func(info):
		health = damageable.health
		if visual and visual.has_method("hit") and damageable.alive:
			visual.hit(info))
	damageable.died.connect(_on_died)
	# hitboxes so enemies can hit Ruth (head / chest / belly / legs)
	var hb := Node3D.new()
	hb.name = "Hitboxes"
	add_child(hb)
	var head := SphereShape3D.new(); head.radius = 0.13
	Damageable.make_hitbox(hb, damageable, "head", head, Transform3D(Basis(), Vector3(0, 1.62, 0)))
	var chest := BoxShape3D.new(); chest.size = Vector3(0.42, 0.42, 0.26)
	Damageable.make_hitbox(hb, damageable, "chest", chest, Transform3D(Basis(), Vector3(0, 1.28, 0)))
	var belly := BoxShape3D.new(); belly.size = Vector3(0.38, 0.3, 0.24)
	Damageable.make_hitbox(hb, damageable, "belly", belly, Transform3D(Basis(), Vector3(0, 0.95, 0)))
	var legs := BoxShape3D.new(); legs.size = Vector3(0.36, 0.8, 0.24)
	Damageable.make_hitbox(hb, damageable, "leg", legs, Transform3D(Basis(), Vector3(0, 0.42, 0)))
	for a in hb.get_children():      # crouching lowers them (moved, not scaled: Jolt rejects non-uniform scale)
		var cs: CollisionShape3D = a.get_child(0)
		_hitboxes.append([cs, cs.position.y])
	cover = PlayerCover.new(self)
	lasso = Lasso.new()
	lasso.name = "Lasso"
	add_child(lasso)
	lasso.setup(self)
	gun = GunHandler.new()
	gun.name = "Guns"
	add_child(gun)
	gun.setup(self, damageable, true)
	holder = WeaponHolder.attach(self, gun)     # null when headless
	gun.hit_landed.connect(func(info):
		if hud and hud.has_method("hit_confirm"):
			var t: Damageable = info.get("target")
			hud.hit_confirm(t != null and not t.alive)
		if nerve and info.get("zone", "") == "head":
			nerve.reward(6.0)
		# kills while Nerve is running build its rank (a headshot kill counts double)
		var tk: Damageable = info.get("target")
		if nerve and nerve.active and tk != null and not tk.alive and tk.kind == "human":
			nerve.add_xp(2.0 if info.get("zone", "") == "head" else 1.0))
	if not Game.headless:
		hud = load("res://src/ui/hud.gd").new()
		hud.name = "HUD"
		get_tree().current_scene.add_child.call_deferred(hud)
		hud.setup.call_deferred(self)
		Game.hud = hud
	if not Game.headless:
		var menus = load("res://src/ui/menus.gd").new()
		menus.name = "Menus"
		get_tree().current_scene.add_child.call_deferred(menus)
		Game.set("menus", menus)
	nerve = Nerve.new()
	nerve.name = "Nerve"
	add_child(nerve)
	nerve.setup(gun, hud)
	if not Game.headless:
		var wheel := WeaponWheel.new()
		wheel.name = "WeaponWheel"
		add_child(wheel)
		wheel.setup(self)

func _aim_kind() -> String:
	if gun == null or gun.weapons.is_empty():
		return "pistol"
	return str(Weapons.get_def(gun.weapon_id()).get("ammo", "revolver")).replace("revolver", "pistol").replace("varmint", "rifle")

func _on_died(info: Dictionary) -> void:
	if visual and visual.has_method("die"):
		visual.die(info)
	Game.log_event("player_died", {})
	Game.say("You have died.", 6.0)
	# respawn at the nearest settlement after a beat (death/consequence system refines this)
	await get_tree().create_timer(4.0, true, false, true).timeout
	var near := Game.world.nearest_settlement(global_position.x, global_position.z)
	var p := Vector3(near.x + 10.0, 0, near.z + 10.0)
	p.y = Game.world.height(p.x, p.z) + 1.0
	Game.terrain.ensure_collision_at(p)
	global_position = p
	damageable.alive = true
	damageable.health = damageable.max_health
	if visual and visual.has_method("revive"):
		visual.revive()
	health = damageable.max_health

## Combat input each frame: draw/holster, aim, fire, reload, weapon switch, Nerve.
func _combat(dt: float) -> void:
	if gun == null:
		return
	var aiming: bool = intent.aim
	if get_meta("blocking", false):
		aiming = false                     # guard up in a fistfight: Aim doesn't draw the gun
	if aiming and not gun.drawn:
		gun.drawn = true
		gun.cooldown = 0.25
	gun.aim_tick(aiming, dt)
	if not bot_driven:
		if Input.is_action_just_pressed("holster"):
			gun.drawn = not gun.drawn
		if Input.is_action_just_pressed("reload"):
			gun.start_reload()
		if Input.is_action_just_pressed("nerve") and aiming:
			if nerve.active:
				nerve.execute()
			else:
				nerve.activate()
	if nerve.active and (not aiming):
		nerve.execute()
	if _fire_edge:
		var aim := aim_ray()
		if nerve.active:
			nerve.mark(aim.origin, aim.dir)
		elif gun.drawn or (cover != null and cover.active):
			if not gun.drawn:
				gun.drawn = true
			var muzzle := global_position + Vector3(0, 1.45, 0) + Vector3(-sin(facing), 0, -cos(facing)) * 0.35
			var blind: bool = cover != null and cover.active and not aiming
			if blind:
				muzzle = cover.blind_muzzle()     # over the top / around the edge, wide spread
			var dir: Vector3 = (aim.point - muzzle).normalized()
			var hits := gun.fire(muzzle, dir, aiming, 1.8 if blind else 1.0)
			if gun.cooldown > 0.0:
				# flash at the visible gun's real muzzle when a WeaponHolder shows one (ballistics keep `muzzle`)
				if holder and holder.has_drawn_model():
					var mt := holder.muzzle_transform()
					Effects.muzzle_flash(get_tree().current_scene, mt.origin, -mt.basis.z)
				else:
					Effects.muzzle_flash(get_tree().current_scene, muzzle, dir)
			Game.log_event("player_fire", {"hits": hits.size()})
	# recoil kicks the camera
	cam_pitch = clampf(cam_pitch + deg_to_rad(gun.recoil_kick.x) * dt * 6.0, -1.2, 0.9)
	cam_yaw += deg_to_rad(gun.recoil_kick.y) * dt * 6.0

var _fire_edge := false
var _interact_target: Node = null
var busy: Node = null          # an activity holding Ruth in place (fishing, minigames): no walking or gunplay

## Context interaction: nearest node in group "interactable" within reach that offers a prompt.
func _interactions() -> void:
	var best: Node = null
	var bd := 2.8
	for n in get_tree().get_nodes_in_group("interactable"):
		if not (n is Node3D) or not n.has_method("interact_prompt"):
			continue
		var d := global_position.distance_to((n as Node3D).global_position)
		if d < bd and n.interact_prompt() != "":
			bd = d
			best = n
	_interact_target = best
	if hud and hud.has_method("prompt") and (Game.missions == null or Game.missions.active == null or Game.missions.objective == ""):
		hud.prompt(("[E]  " + best.interact_prompt()) if best != null else "")
	if best != null and intent.interact:
		best.interact(self)
var _fire_was := false

## Camera-centre aim: origin, direction and the first solid point (for converging muzzle shots).
func aim_ray() -> Dictionary:
	var o := camera.global_position if camera else global_position + Vector3(0, 1.6, 0)
	var d := -camera.global_basis.z if camera else Vector3(-sin(facing), 0, -cos(facing))
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(o, o + d * 600.0, 1 | 4 | 16)
	q.collide_with_areas = true
	var ex: Array[RID] = [get_rid()]
	for a in find_children("*", "Area3D", true, false):
		ex.append(a.get_rid())
	q.exclude = ex
	var hit := space.intersect_ray(q)
	return {"origin": o, "dir": d, "point": hit.position if not hit.is_empty() else o + d * 600.0}

func _build_visual() -> void:
	var factory = load("res://src/actors/character_factory.gd") if ResourceLoader.exists("res://src/actors/character_factory.gd") else null
	if factory != null and factory.available():
		visual = factory.spawn_id("ruth_caddell")
		HumanFootIK.attach.call_deferred(self)   # feet meet slopes, steps and porches
	if visual == null:
		visual = Node3D.new()
		var body := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.25
		cm.height = 1.5
		body.mesh = cm
		body.position.y = 0.8
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.36, 0.28, 0.22)
		mat.roughness = 0.85
		body.material_override = mat
		visual.add_child(body)
		var head := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		head.mesh = sm
		head.position.y = 1.66
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color(0.72, 0.55, 0.45)
		head.material_override = hm
		visual.add_child(head)
		var hat := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.2
		cyl.bottom_radius = 0.22
		cyl.height = 0.03
		hat.mesh = cyl
		hat.position.y = 1.76
		var hatm := StandardMaterial3D.new()
		hatm.albedo_color = Color(0.25, 0.2, 0.15)
		hat.material_override = hatm
		visual.add_child(hat)
	add_child(visual)

func _unhandled_input(event: InputEvent) -> void:
	if bot_driven:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * mouse_sens
		cam_pitch = clampf(cam_pitch - event.relative.y * mouse_sens * (-1.0 if invert_y else 1.0), -1.2, 0.9)
	elif event.is_action_pressed("camera_side"):
		cam_shoulder = -cam_shoulder
	elif event.is_action_pressed("walk_toggle"):
		_walk_mode = not _walk_mode
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _read_human_intent(dt: float) -> void:
	var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	intent.move = Vector2(mv.x, -mv.y)
	intent.sprint = Input.is_action_pressed("sprint")
	intent.walk = _walk_mode
	intent.jump = Input.is_action_just_pressed("jump")
	if Accessibility.aim_toggle:
		if Input.is_action_just_pressed("aim"):
			_aim_latch = not _aim_latch
		intent.aim = _aim_latch
	else:
		intent.aim = Input.is_action_pressed("aim")
	intent.fire = Input.is_action_pressed("fire")
	intent.interact = Input.is_action_just_pressed("interact")
	intent.crouch = Input.is_action_pressed("crouch")
	if Input.is_action_just_pressed("cover"):
		intent.cover = true
	if Input.is_action_just_pressed("melee"):
		intent.melee = true
	if Input.is_action_just_pressed("lasso") and not (busy != null):
		intent.lasso = true
	var assist: bool = intent.aim and Accessibility.assist_on() and camera != null
	if assist and not _aim_prev:
		AimAssist.snap(self)
	_aim_prev = intent.aim
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var k := pad_sens * dt
	if assist:
		if look != Vector2.ZERO:
			k *= AimAssist.slow_factor(self)
		AimAssist.track(self, dt)
	cam_yaw -= look.x * k
	cam_pitch = clampf(cam_pitch - look.y * k * 0.7 * (-1.0 if invert_y else 1.0), -1.2, 0.9)

func _physics_process(dt: float) -> void:
	if on_horse != null:
		return
	if not bot_driven and not Game.is_vr:          # VR writes intent from the controllers (src/xr/vr.gd)
		_read_human_intent(dt)
	if busy != null:
		intent.move = Vector2.ZERO
		intent.aim = false
		intent.fire = false
		intent.jump = false
	_fire_edge = intent.fire and not _fire_was
	_fire_was = intent.fire
	if intent.get("cover", false):
		intent.cover = false
		if cover.active:
			cover.leave()
		elif is_on_floor():
			cover.try_enter(Basis(Vector3.UP, cam_yaw) * Vector3.FORWARD)
	if cover.active:
		intent.crouch = cover.crouched(intent.aim)
	if Melee.is_down(self):                # knocked down in a fistfight
		intent.move = Vector2.ZERO
		intent.aim = false
		intent.fire = false
		intent.melee = false
	_melee(dt)
	if intent.get("lasso", false):
		intent.lasso = false
		if lasso.caught != null:
			lasso.release()
		elif not Melee.is_down(self):
			lasso.throw(cam_yaw if intent.aim else facing)
	# hogtie a downed catch close by (Interact)
	if intent.interact and lasso.caught != null and lasso.hogtie():
		intent.interact = false
	_combat(dt)
	_interactions()
	var mv: Vector2 = intent.move
	var want_dir := Vector3.ZERO
	if mv.length() > 0.08:
		var cam_basis := Basis(Vector3.UP, cam_yaw)
		want_dir = (cam_basis * Vector3(mv.x, 0, -mv.y))
		want_dir.y = 0
		want_dir = want_dir.normalized()
	if cover.active:
		var cv := cover.step(dt, want_dir, intent.aim, intent.sprint)
		if cover.active:
			want_dir = Vector3.ZERO
			speed = Vector2(cv.x, cv.z).length()
			facing = lerp_angle(facing, cover.facing(cv, intent.aim, cam_yaw), 1.0 - exp(-12.0 * dt))
			velocity.x = cv.x
			velocity.z = cv.z
	if not cover.active:
		_move_free(dt, want_dir)
	_after_move(dt)

## Free movement (not in cover): gait speed from the stick, slope, momentum turning.
func _move_free(dt: float, want_dir: Vector3) -> void:
	var mv: Vector2 = intent.move
	# target speed from stick magnitude and gait
	var target := 0.0
	if want_dir != Vector3.ZERO:
		var mag := clampf(mv.length(), 0.0, 1.0)
		target = JOG * mag
		if intent.walk or mag < 0.45:
			target = WALK * clampf(mag / 0.45, 0.3, 1.0) if not intent.walk else WALK
		if intent.sprint and stamina > 1.0 and not intent.aim:
			target = SPRINT
		if intent.crouch:
			target = minf(target, 1.4)
		if intent.aim:
			target = minf(target, 2.2)
	# slope: slower uphill, a little faster downhill
	if is_on_floor() and want_dir != Vector3.ZERO:
		var n := get_floor_normal()
		var uphill := -want_dir.dot(Vector3(n.x, 0, n.z))
		target *= clampf(1.0 - uphill * 1.3, 0.45, 1.12)
	var rate := ACCEL if target > speed else DECEL
	speed = move_toward(speed, target, rate * dt)
	# body turns toward the move direction; slower when fast (momentum), instant-ish when aiming
	if want_dir != Vector3.ZERO:
		var want_yaw := atan2(-want_dir.x, -want_dir.z)
		var turn_rate := lerpf(10.0, 3.2, clampf(speed / SPRINT, 0.0, 1.0))
		if intent.aim:
			want_yaw = cam_yaw
			turn_rate = 14.0
		facing = lerp_angle(facing, want_yaw, 1.0 - exp(-turn_rate * dt))
	elif intent.aim:
		facing = lerp_angle(facing, cam_yaw, 1.0 - exp(-14.0 * dt))
	var fwd := Vector3(-sin(facing), 0, -cos(facing))
	var move_dir := fwd if not intent.aim or want_dir == Vector3.ZERO else want_dir
	var hv := move_dir * speed
	velocity.x = hv.x
	velocity.z = hv.z

## Stamina, gravity/falls, the slide itself and the visual for both free movement and cover.
func _after_move(dt: float) -> void:
	# stamina
	if speed > JOG + 0.5:
		stamina = maxf(stamina - 9.0 * dt, 0.0)
	else:
		stamina = minf(stamina + (6.0 if speed > 0.1 else 12.0) * dt, STAMINA_MAX)
	# vertical
	if is_on_floor():
		if _air_time > 0.6:
			var impact := -_last_vy
			if impact > 9.0:
				var dmg := (impact - 9.0) * 12.0
				fall_damage_taken += dmg
				if damageable:
					damageable.apply_hit({"amount": dmg, "zone": "belly", "attacker": self})
					health = damageable.health
				else:
					health -= dmg
				Game.log_event("fall_damage", {"impact": impact, "damage": dmg})
		_air_time = 0.0
		velocity.y = -0.5
		if intent.jump:
			velocity.y = JUMP_V
			intent.jump = false
	else:
		_air_time += dt
		velocity.y -= GRAVITY * dt
	_last_vy = velocity.y
	move_and_slide()
	rotation.y = 0.0
	if visual:
		visual.rotation.y = facing
	gait = "idle" if speed < 0.2 else ("walk" if speed < 2.4 else ("jog" if speed < 4.8 else "sprint"))
	if visual and visual.has_method("set_locomotion"):
		visual.set_locomotion(speed, "mounted" if get("on_horse") != null else gait, is_on_floor())
	if visual and visual.has_method("set_aim"):
		visual.set_aim(_aim_kind() if intent.aim else "")
	# crouch: hitboxes drop, crouched idle pose
	_crouch_k = move_toward(_crouch_k, 1.0 if intent.crouch else 0.0, dt * 6.0)
	for h in _hitboxes:
		h[0].position.y = h[1] * lerpf(1.0, 0.52, _crouch_k)
	var want_act := "idle_crouch" if intent.crouch and speed < 0.4 else ""
	if want_act != _crouch_act and visual and visual.has_method("set_activity"):
		_crouch_act = want_act
		visual.set_activity(want_act)

var _last_vy := 0.0
var _melee_side := 0
var knife_out := false             # weapon wheel: the Bowie knife makes Melee a lethal stab

## Fists: Melee throws jab / cross alternately at the person in front; Aim with no gun drawn raises the guard.
func _melee(dt: float) -> void:
	set_meta("melee_t", maxf(get_meta("melee_t", 0.0) - dt, 0.0))
	var stag: float = get_meta("stagger_t", 0.0)
	if stag > 0.0:
		set_meta("stagger_t", maxf(stag - dt, 0.0))
	set_meta("blocking", intent.aim and gun != null and not gun.drawn and not cover.active and not Melee.is_down(self)
		and (get_meta("in_fight", false) or _fist_threat()))
	if not intent.get("melee", false):
		return
	intent.melee = false
	if get_meta("melee_t", 0.0) > 0.05 or stag > 0.0 or cover.active or Melee.is_down(self):
		return
	if gun != null and gun.drawn:
		knife_out = false
	if Melee.target_for(self, facing) == null and not get_meta("in_fight", false):
		return                              # nothing to hit: leave the button to mount/crouch
	_melee_side = 1 - _melee_side
	var r := Melee.strike(self, facing, "stab" if knife_out else ("jab" if _melee_side == 0 else "cross"))
	if r.get("hit", false):
		set_meta("in_fight", true)
		get_tree().create_timer(6.0).timeout.connect(func(): set_meta("in_fight", false))

## Someone squared up to Ruth with fists close by (Aim raises the guard instead of drawing then).
func _fist_threat() -> bool:
	for h in get_tree().get_nodes_in_group("humans"):
		var b = h.get("brain")
		if b != null and b.get("state") == b.State.FIST and b.get("target") == self \
				and (h as Node3D).global_position.distance_squared_to(global_position) < 16.0:
			return true
	return false

var cover: PlayerCover
var lasso: Lasso
var _hitboxes: Array = []
var _crouch_k := 0.0
var _crouch_act := ""

func _process(dt: float) -> void:
	if camera == null or on_horse != null or Game.is_vr:
		return
	_update_camera(dt)

func _update_camera(dt: float) -> void:
	var aiming: bool = intent.aim
	var want_dist := 1.6 if aiming else cam_dist + clampf(speed - JOG, 0.0, 3.0) * 0.25
	# aiming: a wider shoulder offset so the raised gun reads beside the head and hat brim (combat feel pass)
	var sh := cam_shoulder
	if cover != null and cover.active and cover.edge != 0:
		sh = float(cover.edge)                 # look past the open end of the cover
	var side := cam_side * sh * (1.0 if not aiming else 1.15)
	var pivot := global_position + Vector3(0, 1.55 if not intent.crouch else 1.1, 0)
	_cam_target = _cam_target.lerp(pivot, 1.0 - exp(-14.0 * dt))
	var basis := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
	var back := basis * Vector3(side, 0.15, want_dist)
	# camera collision: pull in when something is behind the player
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(_cam_target, _cam_target + back)
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	var d := back.length()
	if not hit.is_empty():
		d = maxf(_cam_target.distance_to(hit.position) - 0.25, 0.4)
	_cam_cur_dist = lerpf(_cam_cur_dist, d, 1.0 - exp(-(20.0 if d < _cam_cur_dist else 5.0) * dt))
	var pos := _cam_target + back.normalized() * _cam_cur_dist
	# never below the terrain
	var gy := Game.world.height(pos.x, pos.z) + 0.3
	pos.y = maxf(pos.y, gy)
	camera.global_position = pos
	camera.global_basis = basis
	camera.fov = lerpf(camera.fov, base_fov - 12.0 if aiming else base_fov + clampf(speed - JOG, 0.0, 3.0) * 1.5, 1.0 - exp(-8.0 * dt))
