extends Node
## Ambient hold-up targets: a Sable Valley Stage Line coach on the stage roads out of Bitter Spring and the Meridian
## & Western train on the main line pass Ruth now and then (the ch5 train kit: kinematic cars on a path). Point a
## drawn gun at the driver's box (or the locomotive cab) for a moment and the vehicle stops: the crew climb down with
## their hands up (a shotgun guard or express messenger may make a fight of it), passengers step out to be robbed
## (Robbery: walk up and take what they carry), and the strongbox / express safe can be opened for the line's money.
## The crime counts by witnesses (WorldState.crime "stage_robbery" / "train_robbery", a bounty in that county),
## brings a county posse out from the nearest town (Hunters.law_response), makes the papers and the gossip.
## Bots: `--bot roam` stops a coach and a train under test control.

const TRAIN = preload("res://src/missions/ch5/train.gd")
const STAGE_ROUTES := [["bitter_spring", "coldwater"], ["bitter_spring", "mesquite_wells"], ["bitter_spring", "port_linden"],
	["bitter_spring", "greer_post"]]
const COACH_SPEC := [{"kind": "stagecoach", "len": 5.4, "w": 1.9, "h": 3.0}]
const COACH_SPEED := 7.0
const TRAIN_SPEED := 14.0
const STAGE_EVERY := 260.0
const TRAIN_EVERY := 340.0
const AIM_CONE_DEG := 12.0
const HOLD_TIME := 1.2
## What the line carries: [min $, max $, chance of a gold bar].
const TAKE := {"stage": [60.0, 180.0, 0.15], "train": [150.0, 400.0, 0.35]}

var vehicles: Array = []           # {kind, node, route, crew: [{h, off, role}], held, stopped_at, looted, box, people: [], done_t}
var history: Array = []
var rng := RandomNumberGenerator.new()
var _t_stage := 120.0
var _t_train := 160.0
var _aim := {}                     # vehicle dict id -> seconds in sights
var enabled := true                # bots switch the ambient spawning off and stage their own

func _ready() -> void:
	rng.seed = 1899 * 41
	Game.set_meta("holdups", self)
	if Game.missions:
		Game.missions._load_dialogue("res://design/dialogue/holdups.json")

# ------------------------------------------------------------------ ambient traffic
func _quiet() -> bool:
	var md = Game.missions
	var enc = Game.get("encounters")
	return md != null and md.active == null and (enc == null or str(enc.active) == "")

func _process(dt: float) -> void:
	if Game.player == null or Game.world == null:
		return
	var pp: Vector3 = Game.player.global_position
	for v in vehicles.duplicate():
		_tick_vehicle(v, dt, pp)
	if not enabled or not _quiet() or Game.args.has("bot"):
		return
	_t_stage -= dt
	_t_train -= dt
	if _t_stage <= 0.0:
		_t_stage = STAGE_EVERY * rng.randf_range(0.7, 1.3)
		if _count("stage") == 0:
			spawn_stage(pp)
	if _t_train <= 0.0:
		_t_train = TRAIN_EVERY * rng.randf_range(0.7, 1.3)
		if _count("train") == 0:
			spawn_train(pp)

func _count(kind: String) -> int:
	return vehicles.filter(func(v): return v.kind == kind).size()

## The stage road nearest a point (within 300 m), as [route, points].
static func stage_road_near(p: Vector3) -> Array:
	var best: Array = []
	var bd := 300.0
	for r in Game.world.features.roads:
		var ab := [str(r.get("a", "")), str(r.get("b", ""))]
		var ok := false
		for sr in STAGE_ROUTES:
			if (sr[0] == ab[0] and sr[1] == ab[1]) or (sr[0] == ab[1] and sr[1] == ab[0]):
				ok = true
		if not ok:
			continue
		for q in r.points:
			var d := Vector2(float(q[0]) - p.x, float(q[1]) - p.z).length()
			if d < bd:
				bd = d
				best = [ab, r.points]
	return best

## A coach on the stage road near p, `ahead` metres before the nearest point (it drives past). Returns the vehicle.
func spawn_stage(p: Vector3, ahead := 260.0, speed := COACH_SPEED) -> Dictionary:
	var road := stage_road_near(p)
	if road.is_empty():
		return {}
	var w = TRAIN.new()
	w.car_specs = COACH_SPEC
	w.accel = 1.6
	w.target_speed = speed
	Game.main.add_child(w)
	var from_end := rng.randf() < 0.5
	w.setup(road[1], from_end, true)
	w.name = "StageCoach"
	var s0: float = clampf(w.nearest_s(p) - ahead, 8.0, w.length() - 40.0)
	w.place_at(s0, speed)
	var v := {"kind": "stage", "node": w, "route": road[0] if not from_end else [road[0][1], road[0][0]], "crew": [], "held": false,
		"stopped_at": Vector3.INF, "looted": false, "box": null, "people": [], "done_t": -1.0, "id": rng.randi()}
	_crew(v, [["driver", Vector3(-0.38, 2.4, -2.0), "Stage Driver", "worker", ""],
		["guard", Vector3(0.38, 2.4, -2.0), "Shotgun Guard", "guard", "harlan_carbine"]])
	vehicles.append(v)
	Game.log_event("stage_spawn", {"route": v.route, "s": s0})
	return v

## The Meridian train on the main line near p, starting `ahead` metres back along the rail.
func spawn_train(p: Vector3, ahead := 650.0, speed := TRAIN_SPEED) -> Dictionary:
	var rail = Game.world.features.get("rail", null)
	if rail == null:
		return {}
	var w = TRAIN.new()
	w.target_speed = speed
	w.accel = 1.1
	Game.main.add_child(w)
	var from_end := rng.randf() < 0.5
	w.setup(rail.points, from_end, true)
	w.name = "MeridianTrain"
	if Vector2(w.at(w.nearest_s(p)).x - p.x, w.at(w.nearest_s(p)).z - p.z).length() > 450.0:
		w.queue_free()
		return {}
	var s0: float = clampf(w.nearest_s(p) - ahead, 60.0, w.length() - 80.0)
	w.place_at(s0, speed)
	var v := {"kind": "train", "node": w, "route": ["main_line"], "crew": [], "held": false, "stopped_at": Vector3.INF,
		"looted": false, "box": null, "people": [], "done_t": -1.0, "id": rng.randi()}
	_crew(v, [["engineer", Vector3(0.55, 1.3, 3.4), "Engineer", "worker", ""], ["fireman", Vector3(-0.55, 1.3, 3.4), "Fireman", "worker", ""]])
	vehicles.append(v)
	Game.log_event("train_spawn", {"s": s0})
	return v

func _crew(v: Dictionary, specs: Array) -> void:
	for c in specs:
		var opts := {"seed": rng.randi(), "role": c[3], "faction": "civilian", "name": c[2]}
		if str(c[4]) != "":
			opts["weapon"] = c[4]
			opts["skill"] = 0.45
		var h := Human.spawn(Game.main, v.node.car_center(0) + Vector3(0, 2, 0), opts)
		_seat(h)
		v.crew.append({"h": h, "off": c[1], "role": c[0]})

func _seat(h: Human) -> void:
	h.set_physics_process(false)
	if h.brain:
		h.brain.set_physics_process(false)
	h.collision_layer = 0
	h.collision_mask = 0
	if h.visual and h.visual.has_method("set_activity"):
		h.visual.set_activity("sit_idle")

func _unseat(h: Human, at: Vector3) -> void:
	h.collision_layer = 8
	h.collision_mask = 1 | 2 | 8
	h.rotation = Vector3.ZERO
	h.set_physics_process(true)
	if h.brain:
		h.brain.set_physics_process(true)
		h.brain.home = at
	if h.visual and h.visual.has_method("set_activity"):
		h.visual.set_activity("")
	Game.missions._put_on_ground(h, at)

## Where a vehicle's crew sits in the world (driver's box / locomotive cab): the hold-up aim point.
func aim_point(v: Dictionary) -> Vector3:
	var w = v.node
	var i := 0
	var car: Node3D = w.cars[i].node
	var off: Vector3 = v.crew[0].off if not v.crew.is_empty() else Vector3(0, 2.4, 0)
	return car.global_transform * off

## True when a ray from origin along dir is within the hold-up cone of the vehicle's crew and close enough.
func aimed_at(v: Dictionary, origin: Vector3, dir: Vector3) -> bool:
	var to := aim_point(v) - origin
	var limit := 40.0 if v.kind == "stage" else 48.0
	if to.length() > limit:
		return false
	return dir.normalized().dot(to.normalized()) > cos(deg_to_rad(AIM_CONE_DEG))

func _tick_vehicle(v: Dictionary, dt: float, pp: Vector3) -> void:
	var w = v.node
	if w == null or not is_instance_valid(w):
		vehicles.erase(v)
		return
	# crew ride along until they climb down
	for c in v.crew:
		var h: Human = c.h
		if is_instance_valid(h) and h.alive and not h.get_meta("down", false):
			var car: Node3D = w.cars[0].node
			var xf: Transform3D = car.global_transform
			var fwd := -xf.basis.z
			var yaw := atan2(-fwd.x, -fwd.z)
			h.global_transform = Transform3D(Basis(Vector3.UP, yaw), xf * c.off)
			h.facing = yaw
		elif is_instance_valid(h) and not h.alive and not h.get_meta("down", false) and not v.held:
			# a driver shot off the box: the team runs on a little, then stops
			w.brake()
	var center: Vector3 = w.car_center(0)
	var dist := Vector2(center.x - pp.x, center.z - pp.z).length()
	if not v.held:
		var p = Game.player
		if p.get("intent") != null and p.intent.get("aim", false) and p.gun != null and p.gun.drawn:
			var ray: Dictionary = p.aim_ray()
			if aimed_at(v, ray.origin, ray.dir):
				_aim[v.id] = float(_aim.get(v.id, 0.0)) + dt
				if float(_aim[v.id]) >= HOLD_TIME:
					holdup(v)
			else:
				_aim[v.id] = 0.0
		var at_end: bool = w.s >= w.length() - 6.0
		if (dist > 900.0 and float(_aim.get(v.id, 0.0)) == 0.0) or (at_end and dist > 250.0):
			_despawn(v)
		return
	# held up: release the crew once Ruth rides away (or after four minutes), then the vehicle goes on
	if v.done_t >= 0.0:
		v.done_t += dt
	var site: Vector3 = v.stopped_at if v.stopped_at != Vector3.INF else center
	if (pp.distance_to(site) > 160.0 and v.done_t >= 0.0) or v.done_t > 240.0 or pp.distance_to(site) > 700.0:
		_despawn(v)

func _despawn(v: Dictionary) -> void:
	for c in v.crew:
		if is_instance_valid(c.h):
			c.h.queue_free()
	for h in v.people:
		if is_instance_valid(h):
			h.queue_free()
	if is_instance_valid(v.box):
		v.box.queue_free()
	if is_instance_valid(v.node):
		v.node.queue_free()
	vehicles.erase(v)
	Game.log_event("holdup_vehicle_gone", {"kind": v.kind})

# ------------------------------------------------------------------ the hold-up
## Stop the vehicle at gunpoint: brakes, the crew climbs down, passengers step out, the box is thrown down.
func holdup(v: Dictionary) -> void:
	if v.held:
		return
	v.held = true
	var w = v.node
	var md = Game.missions
	Game.log_event("holdup_vehicle", {"kind": v.kind})
	md.say_async("hu_ruth_stop_coach" if v.kind == "stage" else "hu_ruth_stop_train", Game.player)
	w.brake()
	var t := 0.0
	while is_instance_valid(w) and w.speed > 0.3 and t < 20.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	if not is_instance_valid(w):
		return
	w.speed = 0.0
	var car0: Node3D = w.cars[0].node
	var side: Vector3 = car0.global_transform.basis.x.normalized()
	if side.dot(Game.player.global_position - car0.global_position) < 0.0:
		side = -side                                     # climb down on Ruth's side
	v.stopped_at = car0.global_position
	var stout := false
	for c in v.crew:
		var h: Human = c.h
		if not is_instance_valid(h) or not h.alive:
			continue
		h.set_meta("down", true)
		_unseat(h, car0.global_position + side * 2.2 + car0.global_transform.basis.z * (float(v.crew.find(c)) * 1.4 - 0.7))
		if c.role == "guard":
			stout = rng.randf() < 0.45
			if stout:
				_resist(h, "hu_guard_resist")
				continue
			md.say_async("hu_guard_yield", h)
		_hands_up(h)
	if v.kind == "stage":
		md.say_async("hu_driver_yield", v.crew[0].h if is_instance_valid(v.crew[0].h) else null)
	else:
		md.say_async("hu_engineer_yield", v.crew[0].h if is_instance_valid(v.crew[0].h) else null)
	# passengers
	var pc: int = rng.randi_range(1, 3) if v.kind == "stage" else rng.randi_range(2, 4)
	var pcar: Node3D = car0 if v.kind == "stage" else w.cars[w.car_index("coach")].node
	var roles := ["woman", "townsfolk", "gambler", "traveller"]
	for i in pc:
		var r: String = roles[rng.randi() % roles.size()]
		var h := Human.spawn(Game.main, pcar.global_position + side * (2.6 + float(i % 2)) + pcar.global_transform.basis.z * (float(i) * 1.3 - 1.5),
			{"seed": rng.randi(), "role": r, "faction": "civilian", "name": "Passenger"})
		h.set_meta("passenger", true)
		_hands_up(h)
		v.people.append(h)
	# the express messenger rides in the express car
	if v.kind == "train":
		var ecar: Node3D = w.cars[w.car_index("express")].node
		var m := Human.spawn(Game.main, ecar.global_position + side * 2.4, {"seed": rng.randi(), "role": "guard", "faction": "civilian",
			"name": "Express Messenger", "weapon": "lockhart_sa", "skill": 0.5})
		v.people.append(m)
		if rng.randf() < 0.5:
			_resist(m, "hu_messenger_resist")
			stout = true
		else:
			_hands_up(m)
			md.say_async("hu_messenger_yield", m)
	# the box: thrown down beside the driver's box, or the safe at the express car door
	var bpos: Vector3 = car0.global_position + side * 3.4 if v.kind == "stage" else w.cars[w.car_index("express")].node.global_position + side * 1.9
	var box := Strongbox.new()
	box.vehicle = v
	box.name = "Strongbox" if v.kind == "stage" else "ExpressSafe"
	Game.main.add_child(box)
	box.global_position = Vector3(bpos.x, Game.world.height(bpos.x, bpos.z), bpos.z)
	v.box = box
	# witnesses: everyone who climbed down sees it; the county hears of it from them
	var kind := "stage_robbery" if v.kind == "stage" else "train_robbery"
	var flags: Dictionary = Game.state.flags
	flags[kind + "_count"] = int(flags.get(kind + "_count", 0)) + 1
	flags[kind] = true
	if int(flags[kind + "_count"]) >= 3:
		flags[kind + "_3"] = true
	Game.state.crime(kind, Game.player.global_position, null)     # seen from the road, where she stands
	if Game.state.wanted >= 2 and Game.has_meta("hunters"):
		Game.get_meta("hunters").law_response(Game.state.county_at(v.stopped_at), v.stopped_at)
	Game.log_event("holdup_stopped", {"kind": v.kind, "passengers": pc, "resisted": stout, "wanted": Game.state.wanted})
	v.done_t = 0.0

func _hands_up(h: Human) -> void:
	if h.brain == null:
		return
	h.brain.state = h.brain.State.SURRENDER
	h.set_meta("held_up", true)

func _resist(h: Human, line: String) -> void:
	Game.missions.say_async(line, h)
	h.faction = "bandit"
	h.brain.aggressive = true
	h.brain.share_target(Game.player)
	Game.log_event("holdup_resisted", {"npc": str(h.name)})

## Open the strongbox or the express safe. Returns the take.
func loot(v: Dictionary) -> float:
	if v.looted:
		return 0.0
	v.looted = true
	var tk: Array = TAKE[v.kind]
	var cash := snappedf(rng.randf_range(float(tk[0]), float(tk[1])), 0.05)
	Game.state.add_money(cash)
	var gold := rng.randf() < float(tk[2])
	if gold:
		Game.state.add_item("gold_bar")
	var kind := "stage_robbery" if v.kind == "stage" else "train_robbery"
	var to_town: String = str(v.route[1]) if v.kind == "stage" and v.route.size() > 1 else str(_nearest_town(v.stopped_at))
	if Game.has_meta("news"):
		Game.get_meta("news").record(kind, {"take": cash, "town": to_town})
	history.append({"kind": v.kind, "cash": cash, "gold": gold})
	Game.missions.say_async("hu_ruth_box" if v.kind == "stage" else "hu_ruth_safe", Game.player)
	Game.say("The %s gives up $%.2f%s." % ["strongbox" if v.kind == "stage" else "express safe", cash, " and a gold bar" if gold else ""], 4.0)
	Game.log_event("holdup_loot", {"kind": v.kind, "cash": cash, "gold": gold})
	if is_instance_valid(v.box):
		v.box.opened = true
	return cash

static func _nearest_town(p: Vector3) -> String:
	var best := ""
	var bd := INF
	for tid in WorldState.COUNTIES.keys():
		var t := Game.world.town(tid)
		var d := Vector2(t.x - p.x, t.z - p.z).length()
		if d < bd:
			bd = d
			best = tid
	return best

class Strongbox extends Node3D:
	var vehicle: Dictionary = {}
	var opened := false

	func _ready() -> void:
		add_to_group("interactable")
		if Game.headless:
			return
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.7, 0.45, 0.45) if name == "Strongbox" else Vector3(0.9, 1.1, 0.8)
		m.mesh = b
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.25, 0.18) if name == "Strongbox" else Color(0.12, 0.12, 0.13)
		mat.metallic = 0.4
		mat.roughness = 0.6
		m.material_override = mat
		m.position.y = b.size.y * 0.5
		add_child(m)

	func interact_prompt() -> String:
		if opened:
			return ""
		return "Break open the strongbox" if name == "Strongbox" else "Open the express safe"

	func interact(_who: Node) -> void:
		if Game.has_meta("holdups") and not opened:
			Game.get_meta("holdups").loot(vehicle)
