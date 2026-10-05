extends Node
## The Outfit's camp at Willow Bend: a campfire with light and crackle, companions who live there once recruited
## (story flags), daily camp routines (sitting at the fire, cooking, tending horses, sleeping at night), and the
## player's camp actions: sleep (pass the night, autosave), cook meat at the fire (heal + stamina), contribute money
## to the camp ledger (Standing, unlocks upgrades), talk to companions (barks reflecting Standing and recent deeds).

const COMPANIONS := {
	"hap": {"name": "Hap Lindqvist", "flag_mission": "c1_drover", "seed": 7, "weapon": "harlan_carbine", "role": "drover"},
	"billy": {"name": "Billy Pruitt", "flag": "billy_joined", "seed": 14, "weapon": "", "role": "child"},
}

var center := Vector3.ZERO
var fire_light: OmniLight3D
var members := {}            # id -> Human
var ledger := 0.0
var upgrades := {}           # "lodging", "ammo_box", "medicine" ...
var _t := 0.0
var _fire: Node3D

func _ready() -> void:
	Game.set("camp", self)
	var c := Game.world.poi("caddell_camp")
	center = Vector3(c.x, Game.world.height(c.x, c.z), c.z)
	_build_fire()

func _build_fire() -> void:
	_fire = load("res://src/ai/campfire.gd").new()
	_fire.name = "Campfire"
	_fire.camp = self
	_fire.add_to_group("interactable")
	add_child(_fire)
	_fire.global_position = center
	if Game.headless:
		return
	# stone ring + logs
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.45
	tm.outer_radius = 0.7
	tm.rings = 16
	ring.mesh = tm
	ring.scale = Vector3(1, 0.5, 1)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.32, 0.3, 0.28)
	sm.roughness = 0.95
	ring.material_override = sm
	_fire.add_child(ring)
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.62, 0.3)
	fire_light.light_energy = 2.6
	fire_light.omni_range = 11.0
	fire_light.shadow_enabled = true
	fire_light.position.y = 0.6
	_fire.add_child(fire_light)
	var flames := CPUParticles3D.new()
	flames.amount = 40
	flames.lifetime = 0.8
	flames.direction = Vector3.UP
	flames.spread = 12.0
	flames.initial_velocity_min = 0.6
	flames.initial_velocity_max = 1.4
	flames.gravity = Vector3(0, 1.2, 0)
	flames.scale_amount_min = 0.15
	flames.scale_amount_max = 0.35
	var q := QuadMesh.new()
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.vertex_color_use_as_albedo = true
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = fm
	flames.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.75, 0.35, 0.9))
	g.set_color(1, Color(0.6, 0.15, 0.05, 0.0))
	flames.color_ramp = g
	flames.position.y = 0.15
	_fire.add_child(flames)

func _process(dt: float) -> void:
	if fire_light:
		fire_light.light_energy = 2.4 + sin(Time.get_ticks_msec() * 0.013) * 0.25 + sin(Time.get_ticks_msec() * 0.031) * 0.18
	_t -= dt
	if _t > 0.0 or Game.player == null:
		return
	_t = 2.0
	var near := Game.player.global_position.distance_to(center) < 300.0
	for id in COMPANIONS.keys():
		var c: Dictionary = COMPANIONS[id]
		var joined: bool = (c.has("flag_mission") and Game.missions != null and Game.missions.completed.has(c.flag_mission)) \
			or (c.has("flag") and Game.state != null and Game.state.flags.get(c.flag, false))
		var busy_in_mission: bool = Game.missions != null and Game.missions.active != null
		if joined and near and not busy_in_mission and not members.has(id):
			_spawn_member(id, c)
		elif members.has(id) and (not near or busy_in_mission):
			if is_instance_valid(members[id]):
				members[id].queue_free()
			members.erase(id)
	for id in members.keys():
		var h: Human = members[id]
		if is_instance_valid(h) and h.alive:
			_routine(id, h)

func _spawn_member(id: String, c: Dictionary) -> void:
	var p := center + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
	p.y = Game.world.height(p.x, p.z) + 0.3
	Game.terrain.ensure_tile(p)
	var h := Human.spawn(Game.main, p, {"seed": c.seed, "role": c.role, "faction": "outfit", "name": c.name, "weapon": c.weapon})
	h.brain.home = center
	members[id] = h

## Camp routine by hour: evenings at the fire, daytime chores around camp, nights asleep by the wagon.
func _routine(id: String, h: Human) -> void:
	if h.brain.state != h.brain.State.ROUTINE and h.brain.state != h.brain.State.IDLE:
		return
	var hour: float = Game.sky.hours if Game.sky else 12.0
	var r := RandomNumberGenerator.new()
	r.seed = hash(id) + int(hour * 4.0)
	if hour > 18.0 or hour < 1.0:
		var a := r.randf() * TAU
		h.intent.move_to = center + Vector3(cos(a) * 2.2, 0, sin(a) * 2.2)
		h.intent.speed = Human.WALK
		h.intent.face = center - h.global_position
	elif hour < 6.0:
		h.intent.move_to = center + Vector3(5.0, 0, 3.0 + (1.5 if id == "billy" else 0.0))
	else:
		h.intent.move_to = center + Vector3(r.randf_range(-12, 12), 0, r.randf_range(-12, 12))
		h.intent.speed = Human.WALK

# ------------------------------------------------------------------ player actions
## Sleep until morning (or 8 hours), heal, autosave.
func sleep() -> void:
	if Game.sky == null:
		return
	var h: float = Game.sky.hours
	var wake := 6.5 if h > 17.0 or h < 6.0 else fmod(h + 8.0, 24.0)
	if h > 17.0:
		Game.sky.day += 1
	Game.sky.set_time(wake)
	if Game.player and Game.player.damageable:
		Game.player.damageable.health = Game.player.damageable.max_health
		Game.player.stamina = Game.player.STAMINA_MAX
	if Game.state:
		Game.state.save_game("auto")
	Game.say("You slept at Willow Bend.", 3.0)

## Cook any meat in the satchel at the fire: each portion heals and fills stamina.
func cook() -> int:
	if Game.state == null:
		return 0
	var n := 0
	for k in Game.state.inventory.keys():
		if str(k).begins_with("meat_") and int(Game.state.inventory[k]) > 0:
			n += int(Game.state.inventory[k])
			Game.state.inventory[k] = 0
	if n > 0:
		Game.state.add_item("cooked_meat", n)
		Game.say("Cooked %d portions of meat." % n, 3.0)
	return n

func contribute(amount: float) -> bool:
	if Game.state == null or Game.state.money < amount:
		return false
	Game.state.add_money(-amount)
	ledger += amount
	Game.state.good_deed("donation")
	if ledger >= 40.0 and not upgrades.has("ammo_box"):
		upgrades["ammo_box"] = true
		Game.say("Hap built an ammunition box. Take what you need.", 4.0)
	return true
