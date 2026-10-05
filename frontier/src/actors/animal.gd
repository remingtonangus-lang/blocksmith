class_name Animal
extends CharacterBody3D
## Wildlife: one script for every species (table below). Grazers move in herds and flee from threats they see,
## hear or smell (wind-dependent); predators stalk and chase prey (and sometimes the player); birds and small game
## flush. Day/night activity. Hunting: pelt quality from weapon + hit zone + shot count, skinning via interact,
## carcass/pelt items with prices. Visuals come from the quadruped pipeline when present (animals/<species>.glb),
## else a simple stand-in body.

const SPECIES := {
	"mule_deer": {"name": "Mule Deer", "size": Vector3(0.5, 1.0, 1.6), "hp": 70.0, "walk": 1.3, "run": 13.0, "herd": [2, 6],
		"diet": "grazer", "wary": 70.0, "biomes": [0.45, 1.0], "active": "crepuscular", "pelt": 3.0, "meat": 2.0, "color": Color(0.5, 0.38, 0.27)},
	"elk": {"name": "Elk", "size": Vector3(0.7, 1.5, 2.3), "hp": 160.0, "walk": 1.4, "run": 12.0, "herd": [3, 9],
		"diet": "grazer", "wary": 80.0, "biomes": [0.65, 1.0], "active": "crepuscular", "pelt": 7.0, "meat": 4.0, "color": Color(0.55, 0.4, 0.28)},
	"pronghorn": {"name": "Pronghorn", "size": Vector3(0.45, 0.9, 1.4), "hp": 55.0, "walk": 1.4, "run": 17.0, "herd": [4, 12],
		"diet": "grazer", "wary": 110.0, "biomes": [0.2, 0.6], "active": "day", "pelt": 3.5, "meat": 1.5, "color": Color(0.72, 0.52, 0.32)},
	"bison": {"name": "Bison", "size": Vector3(1.1, 1.8, 3.0), "hp": 320.0, "walk": 1.0, "run": 11.0, "herd": [5, 14],
		"diet": "grazer", "wary": 45.0, "biomes": [0.35, 0.6], "active": "day", "pelt": 12.0, "meat": 6.0, "color": Color(0.24, 0.17, 0.12)},
	"rabbit": {"name": "Jackrabbit", "size": Vector3(0.18, 0.3, 0.45), "hp": 8.0, "walk": 1.0, "run": 12.0, "herd": [1, 1],
		"diet": "grazer", "wary": 25.0, "biomes": [0.0, 0.8], "active": "crepuscular", "pelt": 0.6, "meat": 0.3, "color": Color(0.6, 0.52, 0.42)},
	"coyote": {"name": "Coyote", "size": Vector3(0.3, 0.6, 1.1), "hp": 40.0, "walk": 1.6, "run": 14.0, "herd": [1, 3],
		"diet": "predator", "prey": ["rabbit", "pronghorn"], "wary": 50.0, "biomes": [0.0, 0.7], "active": "night", "pelt": 2.0, "meat": 0.8, "color": Color(0.58, 0.48, 0.36)},
	"wolf": {"name": "Grey Wolf", "size": Vector3(0.38, 0.8, 1.4), "hp": 80.0, "walk": 1.7, "run": 15.0, "herd": [3, 6],
		"diet": "predator", "prey": ["mule_deer", "elk", "pronghorn"], "attack_player": 0.35, "wary": 60.0, "biomes": [0.6, 1.0], "active": "night", "pelt": 5.0, "meat": 1.5, "color": Color(0.45, 0.44, 0.42)},
	"cougar": {"name": "Cougar", "size": Vector3(0.4, 0.75, 1.6), "hp": 110.0, "walk": 1.5, "run": 16.0, "herd": [1, 1],
		"diet": "predator", "prey": ["mule_deer", "rabbit"], "attack_player": 0.7, "wary": 40.0, "biomes": [0.55, 1.0], "active": "crepuscular", "pelt": 9.0, "meat": 1.5, "color": Color(0.66, 0.5, 0.34)},
	"black_bear": {"name": "Black Bear", "size": Vector3(0.75, 1.0, 1.7), "hp": 260.0, "walk": 1.2, "run": 12.0, "herd": [1, 1],
		"diet": "omnivore", "attack_player": 0.4, "wary": 30.0, "biomes": [0.7, 1.0], "active": "day", "pelt": 11.0, "meat": 4.0, "color": Color(0.12, 0.1, 0.09)},
	"turkey": {"name": "Wild Turkey", "size": Vector3(0.3, 0.8, 0.7), "hp": 15.0, "walk": 1.0, "run": 8.0, "herd": [3, 8],
		"diet": "grazer", "wary": 35.0, "biomes": [0.5, 0.9], "active": "day", "pelt": 1.0, "meat": 0.8, "color": Color(0.25, 0.2, 0.15)},
	"raccoon": {"name": "Raccoon", "size": Vector3(0.25, 0.35, 0.65), "hp": 15.0, "walk": 0.9, "run": 6.0, "herd": [1, 2],
		"diet": "omnivore", "wary": 15.0, "biomes": [0.55, 1.0], "active": "night", "pelt": 1.4, "meat": 0.3, "color": Color(0.36, 0.34, 0.32)},
	"fox": {"name": "Red Fox", "size": Vector3(0.22, 0.4, 0.9), "hp": 20.0, "walk": 1.2, "run": 13.0, "herd": [1, 1],
		"diet": "predator", "prey": ["rabbit"], "wary": 40.0, "biomes": [0.4, 1.0], "active": "crepuscular", "pelt": 2.5, "meat": 0.3, "color": Color(0.7, 0.35, 0.15)},
}

enum State { GRAZE, WANDER, ALERT, FLEE, STALK, CHASE, ATTACK, DEAD }

var species := "mule_deer"
var spec: Dictionary
var state: int = State.GRAZE
var herd: Array = []
var leader: Animal = null
var damageable: Damageable
var visual: Node3D
var speed := 0.0
var heading := 0.0
var goal := Vector3.INF
var threat: Node3D = null
var prey: Node3D = null
var t_state := 0.0
var rng := RandomNumberGenerator.new()
var shots_taken := 0
var hit_zones: Array = []
var killer_weapon := ""
var skinned := false
var alive := true

static func spawn(parent: Node, pos: Vector3, sp: String, seed: int) -> Animal:
	var a := Animal.new()
	a.species = sp
	a.spec = SPECIES[sp]
	a.rng.seed = seed
	a.name = "%s_%d" % [sp, seed % 100000]
	parent.add_child(a)
	a.global_position = pos
	a._setup()
	return a

func _setup() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.5
	var sz: Vector3 = spec.size
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(sz.x, sz.y * 0.7, sz.z)
	cs.shape = box
	cs.position.y = sz.y * 0.55
	add_child(cs)
	damageable = Damageable.new()
	damageable.max_health = spec.hp
	damageable.kind = "animal"
	damageable.zone_mult = {"head": 3.0, "chest": 1.9, "leg": 0.45}
	add_child(damageable)
	damageable.damaged.connect(_on_damaged)
	damageable.died.connect(_on_died)
	var hb := Node3D.new()
	add_child(hb)
	var body := BoxShape3D.new()
	body.size = Vector3(sz.x, sz.y * 0.5, sz.z * 0.78)
	Damageable.make_hitbox(hb, damageable, "chest", body, Transform3D(Basis(), Vector3(0, sz.y * 0.62, 0)))
	var head := SphereShape3D.new()
	head.radius = maxf(sz.x * 0.4, 0.06)
	Damageable.make_hitbox(hb, damageable, "head", head, Transform3D(Basis(), Vector3(0, sz.y * 0.95, -sz.z * 0.55)))
	for lz in [-1.0, 1.0]:
		var legs := BoxShape3D.new()
		legs.size = Vector3(sz.x * 0.7, sz.y * 0.38, sz.z * 0.14)
		Damageable.make_hitbox(hb, damageable, "leg", legs, Transform3D(Basis(), Vector3(0, sz.y * 0.19, lz * sz.z * 0.32)))
	_build_visual()
	heading = rng.randf() * TAU
	add_to_group("animals")
	if Game.terrain:
		Game.terrain.foci.append(self)
	tree_exiting.connect(func(): if Game.terrain: Game.terrain.foci.erase(self))

func _build_visual() -> void:
	var path := "res://assets/ext/animals/%s.glb" % species
	if ResourceLoader.exists(path):
		var ps: PackedScene = load(path)
		visual = ps.instantiate()
	else:
		visual = Node3D.new()
		var sz: Vector3 = spec.size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec.color
		mat.roughness = 0.95
		var torso := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = sz.x * 0.5
		cap.height = sz.z
		torso.mesh = cap
		torso.rotation_degrees.x = 90
		torso.position.y = sz.y * 0.62
		torso.material_override = mat
		visual.add_child(torso)
		var head := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = sz.x * 0.38
		sm.height = sz.x * 0.7
		head.mesh = sm
		head.position = Vector3(0, sz.y * 0.92, -sz.z * 0.55)
		head.material_override = mat
		visual.add_child(head)
		for lx in [-1, 1]:
			for lz in [-1, 1]:
				var leg := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = sz.x * 0.12
				cyl.bottom_radius = sz.x * 0.08
				cyl.height = sz.y * 0.5
				leg.mesh = cyl
				leg.position = Vector3(lx * sz.x * 0.3, sz.y * 0.25, lz * sz.z * 0.32)
				leg.material_override = mat
				visual.add_child(leg)
	add_child(visual)

func is_active_now() -> bool:
	if Game.sky == null:
		return true
	var h: float = Game.sky.hours
	match spec.active:
		"day": return h > 6.0 and h < 19.0
		"night": return h < 6.5 or h > 18.5
		_: return true

func _physics_process(dt: float) -> void:
	if not alive:
		if not is_on_floor():
			velocity.y -= 9.81 * dt
			move_and_slide()
		return
	t_state -= dt
	match state:
		State.GRAZE, State.WANDER:
			_calm(dt)
		State.ALERT:
			_alert(dt)
		State.FLEE:
			_flee(dt)
		State.STALK, State.CHASE, State.ATTACK:
			_hunt(dt)
	_move(dt)

func _senses() -> Node3D:
	# sight + hearing of the player (and horse) with wind-carried scent; predators for prey animals
	var p = Game.player
	if p == null:
		return null
	var to: Vector3 = p.global_position - global_position
	var d := to.length()
	var wary: float = spec.wary
	var pspeed: float = p.get("speed") if p.get("speed") != null else 0.0
	var crouch: bool = p.intent.get("crouch", false) if p.get("intent") != null else false
	var noise := wary * (0.35 if crouch else 0.6) * (1.0 + pspeed / 3.0)
	if p.get("on_horse") != null:
		noise *= 1.5
	# scent travels downwind: animals downwind of the player smell her from far
	var wind: Vector2 = Game.sky.wind if Game.sky else Vector2(1, 0.3)
	var downwind := Vector2(-to.x, -to.z).normalized().dot(wind.normalized())
	var scent := wary * 1.4 * clampf(downwind, 0.0, 1.0)
	if d < maxf(noise, scent):
		return p
	return null

func _calm(dt: float) -> void:
	if t_state <= 0.0:
		t_state = rng.randf_range(4.0, 12.0)
		if leader != null and is_instance_valid(leader) and leader.alive:
			goal = leader.global_position + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
		elif rng.randf() < 0.55:
			goal = global_position + Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-30, 30))
		else:
			goal = Vector3.INF
		state = State.WANDER if goal != Vector3.INF else State.GRAZE
	var t := _senses()
	if t != null:
		threat = t
		if spec.diet == "predator" and spec.has("attack_player") and rng.randf() < float(spec.attack_player) * dt:
			state = State.STALK
			prey = t
			return
		state = State.ALERT
		t_state = rng.randf_range(0.6, 1.8)
		for a in herd:
			if is_instance_valid(a) and a != self and a.state < State.ALERT:
				a.threat = t
				a.state = State.ALERT
				a.t_state = rng.randf_range(0.3, 1.0)
	elif spec.diet == "predator" and rng.randf() < 0.002:
		prey = _find_prey()
		if prey != null:
			state = State.STALK

func _alert(_dt: float) -> void:
	goal = Vector3.INF
	if threat != null:
		var to := threat.global_position - global_position
		heading = lerp_angle(heading, atan2(-to.x, -to.z), 0.1)
	if t_state <= 0.0:
		state = State.FLEE
		t_state = rng.randf_range(8.0, 15.0)

func _flee(_dt: float) -> void:
	if threat == null or not is_instance_valid(threat):
		state = State.WANDER
		return
	var away := global_position - threat.global_position
	away.y = 0
	goal = global_position + away.normalized() * 25.0
	if t_state <= 0.0 and away.length() > float(spec.wary) * 1.6:
		state = State.WANDER
		threat = null

func _find_prey() -> Node3D:
	var best: Node3D = null
	var bd := 120.0
	for a in get_tree().get_nodes_in_group("animals"):
		if a != self and a.alive and a.species in spec.get("prey", []):
			var d := global_position.distance_to(a.global_position)
			if d < bd:
				bd = d
				best = a
	return best

func _hunt(dt: float) -> void:
	if prey == null or not is_instance_valid(prey) or (prey.get("alive") == false):
		state = State.WANDER
		prey = null
		return
	var d := global_position.distance_to(prey.global_position)
	goal = prey.global_position
	if state == State.STALK and d < 18.0:
		state = State.CHASE
		Game.log_event("predator_chase", {"who": species, "prey": str(prey.name)})
		if prey is Animal:
			prey.threat = self
			prey.state = State.FLEE
			prey.t_state = 10.0
	elif state == State.CHASE and d < 1.8:
		state = State.ATTACK
		t_state = 0.8
	elif state == State.ATTACK and t_state <= 0.0:
		var dmg: Damageable = prey.get("damageable")
		if dmg != null:
			dmg.apply_hit({"amount": 18.0 if prey == Game.player else 40.0, "zone": "chest", "attacker": self})
			if prey != Game.player and not dmg.alive:
				Game.log_event("predation", {"predator": species, "prey": prey.get("species")})
		state = State.CHASE
	if d > 150.0:
		state = State.WANDER

func _move(dt: float) -> void:
	var tspeed := 0.0
	if goal != Vector3.INF:
		var to := Vector3(goal.x - global_position.x, 0, goal.z - global_position.z)
		if to.length() > 1.0:
			var want := atan2(-to.x, -to.z)
			var fast := state in [State.FLEE, State.CHASE, State.ATTACK]
			tspeed = float(spec.run) if fast else (float(spec.walk) * 0.6 if state == State.STALK else float(spec.walk))
			heading = lerp_angle(heading, want, 1.0 - exp(-(4.0 if fast else 2.0) * dt))
			# avoid water and cliffs
			var ahead := global_position + Vector3(-sin(heading), 0, -cos(heading)) * 3.0
			if Game.world and (Game.world.is_water(ahead.x, ahead.z) or (1.0 - Game.world.normal(ahead.x, ahead.z).y) > 0.55):
				heading += 0.8
	speed = move_toward(speed, tspeed, (12.0 if tspeed > speed else 8.0) * dt)
	var dir := Vector3(-sin(heading), 0, -cos(heading))
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = -0.5 if is_on_floor() else velocity.y - 9.81 * dt
	move_and_slide()
	visual.rotation.y = heading
	if visual.has_method("set_gait"):
		visual.set_gait(speed)

func _on_damaged(info: Dictionary) -> void:
	shots_taken += 1
	hit_zones.append(info.get("zone", "chest"))
	killer_weapon = info.get("weapon", "")
	threat = info.get("attacker")
	if spec.diet == "predator" or species == "black_bear":
		if threat != null and rng.randf() < float(spec.get("attack_player", 0.2)) + 0.3:
			prey = threat
			state = State.CHASE
			return
	state = State.FLEE
	t_state = 12.0

func _on_died(info: Dictionary) -> void:
	alive = false
	collision_layer = 0
	if Game.state:
		Game.state.kills.animal += 1
	Game.log_event("animal_killed", {"species": species, "quality": pelt_quality(), "zones": hit_zones})
	var tw := create_tween()
	tw.tween_property(visual, "rotation:z", PI * 0.5, 0.6).set_ease(Tween.EASE_IN)
	add_to_group("interactable")

func interact_prompt() -> String:
	return "" if alive or skinned else "Skin the %s" % str(spec.name).to_lower()

func interact(_who: Node) -> void:
	var r := skin()
	if not r.is_empty() and Game.hud:
		Game.hud.notice("%s pelt — %s" % [spec.name, ["", "poor", "good", "perfect"][r.quality]], 3.5)

## Pelt quality 1 (poor) .. 3 (perfect): right weapon for the size, one clean shot, head/heart hit.
func pelt_quality() -> int:
	var big: bool = spec.size.z > 1.3
	var ok_weapon := true
	var wdef: Dictionary = Weapons.get_def(killer_weapon) if killer_weapon != "" else {}
	if not wdef.is_empty():
		if big and wdef.kind == "shotgun":
			ok_weapon = false
		if not big and wdef.damage > 60.0:
			ok_weapon = false
		if spec.size.z < 0.8 and wdef.kind != "rifle":
			ok_weapon = wdef.id == "pellman_varmint" if wdef.has("id") else wdef.damage < 25.0
	var clean: bool = shots_taken <= 1 and (hit_zones.is_empty() or hit_zones[-1] in ["head", "chest"])
	if ok_weapon and clean:
		return 3
	if ok_weapon or clean:
		return 2
	return 1

## Skin the carcass (interact): pelt + meat into the satchel, priced by quality.
func skin() -> Dictionary:
	if alive or skinned:
		return {}
	skinned = true
	var q := pelt_quality()
	var item := "pelt_%s_q%d" % [species, q]
	if Game.state:
		Game.state.add_item(item)
		Game.state.add_item("meat_" + species, 1)
	visual.scale = Vector3(1, 0.6, 1)
	Game.log_event("skinned", {"species": species, "quality": q})
	return {"item": item, "quality": q, "value": float(spec.pelt) * [0.0, 0.4, 0.75, 1.0][q]}
