extends Node
## Random encounters along the roads: every few minutes of travel, if the player is on or near a road and away from
## towns, one of the encounter types may stage itself ahead of her (out of sight), play out through the mission
## director's verbs, and resolve by what she does. Outcomes touch Standing, money, items and the law.

const TYPES := ["wagon", "robbery", "prisoner", "snakebite", "hunter", "grave"]
const COOLDOWN := 150.0

var _t := 90.0
var active := ""
var nodes: Array = []
var rng := RandomNumberGenerator.new()
var history := []

func _ready() -> void:
	rng.seed = 1899 * 13
	Game.set("encounters", self)
	if Game.missions:
		Game.missions._load_dialogue("res://design/dialogue/encounters.json")

func _process(dt: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_process_impl(dt)
	Game.prof("encounters.gd _process", _pt0)

func _process_impl(dt: float) -> void:
	if Game.player == null or Game.missions == null or Game.missions.active != null or active != "":
		return
	_t -= dt * (1.0 + clampf(float(Game.player.get("speed")), 0.0, 10.0) / 4.0)
	if _t > 0.0:
		return
	_t = COOLDOWN * rng.randf_range(0.7, 1.3)
	var pp: Vector3 = Game.player.global_position
	var near := Game.world.nearest_settlement(pp.x, pp.z)
	if not near.is_empty() and Vector2(near.x - pp.x, near.z - pp.z).length() < float(near.r) + 250.0:
		return
	var kind: String = TYPES[rng.randi() % TYPES.size()]
	start(kind)

## Stage an encounter ahead of the player on the nearest road (or at a given point for tests).
func start(kind: String, at := Vector3.INF) -> void:
	var p := at
	if p == Vector3.INF:
		var pp: Vector3 = Game.player.global_position
		var fwd := Vector3(-sin(Game.player.facing), 0, -cos(Game.player.facing))
		var id := Game.roads.nearest(pp + fwd * 110.0) if Game.roads else -1
		p = Game.roads.pts[id] if id >= 0 else pp + fwd * 110.0
	p.y = Game.world.height(p.x, p.z)
	active = kind
	history.append(kind)
	Game.log_event("encounter", {"kind": kind, "at": [p.x, p.z]})
	await call("_" + kind, p)
	for n in nodes:
		if is_instance_valid(n) and n.get("alive") != false:
			n.brain.state = n.brain.State.ROUTINE if n.brain else 0
	nodes.clear()
	active = ""

func _spawn(p: Vector3, opts: Dictionary) -> Human:
	Game.terrain.ensure_tile(p)
	var h := Human.spawn(Game.main, p + Vector3(0, 0.3, 0), opts)
	nodes.append(h)
	return h

func _wait_near(p: Vector3, r: float, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if Game.player.global_position.distance_to(p) < r or Game.missions.autopilot:
			return true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return false

func _wagon(p: Vector3) -> void:
	var w := _spawn(p + Vector3(2, 0, 0), {"seed": rng.randi(), "role": "wagoner", "faction": "civilian", "name": "Wagoner"})
	w.brain.state = w.brain.State.IDLE
	if not await _wait_near(p, 12.0, 120.0):
		return
	await Game.missions.say("enc_wagon_01", w)
	await Game.missions.interact(p + Vector3(1, 0, 1), "Help lift the wagon")
	await Game.missions.say("enc_wagon_02", Game.player)
	await Game.missions.say("enc_wagon_03", w)
	Game.state.good_deed("help_stranger")
	Game.state.add_item("coffee")

func _robbery(p: Vector3) -> void:
	var gang: Array = []
	for i in rng.randi_range(2, 3):
		gang.append(_spawn(p + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)),
			{"seed": rng.randi(), "role": "gunman", "faction": "bandit", "name": "Road Agent", "weapon": "lockhart_sa", "skill": 0.35}))
	for g in gang:
		g.brain.group = gang
		g.brain.aggressive = false
	if not await _wait_near(p, 18.0, 120.0):
		return
	await Game.missions.say("enc_robbery_01", gang[0])
	await Game.missions.say("enc_robbery_02", Game.player)
	for g in gang:
		g.brain.aggressive = true
		g.brain.share_target(Game.player)
	await Game.missions.wait_dead(gang, "Road agents")

func _prisoner(p: Vector3) -> void:
	var dep := _spawn(p, {"seed": rng.randi(), "role": "lawman", "faction": "law", "name": "Deputy", "weapon": "harlan_carbine"})
	var pri := _spawn(p + Vector3(1.5, 0, 0.5), {"seed": rng.randi(), "role": "prisoner", "faction": "civilian", "name": "Prisoner"})
	pri.brain.state = pri.brain.State.SURRENDER
	if not await _wait_near(p, 12.0, 120.0):
		return
	await Game.missions.say("enc_prisoner_01", pri)
	await Game.missions.say("enc_prisoner_02", dep)
	await Game.missions.say("enc_prisoner_03", Game.player)
	# freeing him means drawing on the deputy: that path is the player's choice (crime system judges it)

func _snakebite(p: Vector3) -> void:
	var v := _spawn(p, {"seed": rng.randi(), "role": "prospector", "faction": "civilian", "name": "Prospector", "health": 30.0})
	v.brain.state = v.brain.State.COWER
	if not await _wait_near(p, 10.0, 120.0):
		return
	await Game.missions.say("enc_snake_01", v)
	if int(Game.state.inventory.get("tonic_health", 0)) > 0:
		await Game.missions.interact(p, "Give him a tonic")
		Game.state.inventory["tonic_health"] -= 1
		await Game.missions.say("enc_snake_02", Game.player)
		await Game.missions.say("enc_snake_03", v)
		Game.state.good_deed("help_stranger")
		Game.state.flags["snakebite_tip"] = true

func _hunter(p: Vector3) -> void:
	var h := _spawn(p, {"seed": rng.randi(), "role": "hunter", "faction": "civilian", "name": "Meat Hunter", "weapon": "bowden_bolt"})
	if not await _wait_near(p, 10.0, 120.0):
		return
	await Game.missions.say("enc_hunter_01", h)
	if Game.state.money >= 0.5:
		Game.state.add_money(-0.5)
		Game.state.add_item("meat_mule_deer")

func _grave(p: Vector3) -> void:
	var w := _spawn(p, {"seed": rng.randi(), "role": "lady", "faction": "civilian", "name": "Mourner"})
	w.brain.state = w.brain.State.IDLE
	if not await _wait_near(p, 10.0, 120.0):
		return
	await Game.missions.say("enc_grave_01", w)
	await Game.missions.interact(p + Vector3(1.5, 0, 0), "Dig the grave")
	await Game.missions.say("enc_grave_02", Game.player)
	Game.state.good_deed("help_stranger")
