class_name Vehicles
extends Node3D
## Places and runs every vehicle: crawlers and a gunship parked for the player at the citadel and Fort Lumen, an
## AI crawler patrol on the front track, gunships over the front for both sides, Capital dropships shuttling
## squads from the airfield and the citadel, a frigate patrolling citadel - front, truck convoys on the roads,
## warships at sea, and the artillery batteries that fire the battle's barrages.

var mat: Material
var crawlers: Array[Crawler] = []
var helis: Array[Helicopter] = []
var dropships: Array[Dropship] = []
var frigates: Array[Frigate] = []
var convoys: Array[Convoy] = []
var ships: Array[NavalShip] = []
var batteries := {}


func setup(m: Material) -> void:
	mat = m
	G.vehicles = self
	var gen := G.gen
	var bases: Bases = G.world.bases
	var spawn: Vector3 = gen.sites["spawn"]
	# Player vehicles near the spawn (the citadel's west apron) and at Fort Lumen.
	_crawler(0, _ground(spawn + Vector3(18, 0, 10)), -1.2)
	_crawler(0, _ground(spawn + Vector3(26, 0, -6)), -1.0)
	var fl: Vector3 = gen.sites["fort_lumen"]
	_crawler(0, _ground(fl + Vector3(40, 0, 60)), PI * 0.5)
	var cit_pads: Array = bases.pads.get("citadel", [])
	if cit_pads.size() > 1:
		var h := _heli(0, cit_pads[1] + Vector3(0, 0.3, 0), 0.0)
		h.engine_on = false
	# AI crawler patrol on the front track (drives to the front and back).
	var front_track := _road("Front Track")
	if front_track.size() > 2:
		var c := _crawler(0, front_track[0] + Vector3(0, 1.5, 0), 0.0)
		c.follow(front_track)
		c.set_meta("patrol", front_track)
	# Gunships over the front.
	var front: Vector3 = gen.sites["front"]
	for f in 2:
		var h := _heli(f, front + Vector3(300.0 * (1 - 2 * f), 140.0, 0), 0.0)
		h.ai = true
		h.ai_orbit = front + Vector3(250.0 * (1 - 2 * f), 0, 100.0 * f)
		h.ai_alt = 110.0 + f * 30.0
		h.ai_radius = 420.0
		h.ai_angle = f * PI
	# Dropships: from the airfield and the citadel to the Capital's landing zone near the front.
	var lz: Vector3 = G.battle.stage[0] + Vector3(-60, 0, -40)
	var air: Array = bases.pads.get("airfield", [])
	if air.size() > 0:
		_dropship(air[0], lz)
	if cit_pads.size() > 2:
		_dropship(cit_pads[2], lz + Vector3(80, 0, 90))
	# The frigate: citadel - Fort Lumen - front - Candor.
	var cit: Vector3 = gen.sites["citadel"]
	var loop: Array[Vector3] = [cit + Vector3(0, 0, 300), fl + Vector3(0, 0, -200), front + Vector3(300, 0, -300),
		front + Vector3(500, 0, 400), gen.sites["capital"] + Vector3(-600, 0, -200)]
	var fr := Frigate.new()
	fr.name = "Frigate"
	add_child(fr)
	fr.build(mat, cit + Vector3(0, 260, 300), loop)
	fr.add_to_group("vehicles")
	frigates.append(fr)
	# Convoys.
	_convoy(0, "Western Highway", 5)
	_convoy(0, "Coast Road", 3)
	_convoy(1, "Red Track", 4)
	_convoy(1, "Ash Track", 3)
	# Ships: a Capital destroyer east of Candor, two Cinder gunboats along the south coast.
	var cap: Vector3 = gen.sites["capital"]
	var east: Array[Vector3] = [Vector3(7400, 0, -1800), Vector3(7600, 0, 2600), Vector3(5200, 0, 6200), Vector3(2000, 0, 7200)]
	_ship(0, Vector3(7400, 0, 0), east)
	var south: Array[Vector3] = [Vector3(-3000, 0, 7300), Vector3(1500, 0, 7400), Vector3(4200, 0, 6800), Vector3(-1000, 0, 7700)]
	_ship(1, Vector3(-2000, 0, 7400), south)
	_ship(1, Vector3(2600, 0, 7600), south)
	# Artillery.
	var art := ArtilleryBattery.new()
	art.name = "CapitalBattery"
	add_child(art)
	art.build(0, mat, gen.sites["artillery"], 4)
	batteries[0] = art
	var mort := ArtilleryBattery.new()
	mort.name = "CinderMortars"
	add_child(mort)
	mort.build(1, mat, _ground(gen.sites["cinder_outpost"] + Vector3(60, 0, -60)), 2)
	batteries[1] = mort


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, G.world.ground_at(p.x, p.z), p.z)


func _road(name: String) -> PackedVector3Array:
	for r in G.gen.roads:
		if r["name"] == name:
			return r["pts"]
	return PackedVector3Array()


func _crawler(f: int, at: Vector3, yaw: float) -> Crawler:
	var c := Crawler.new()
	c.name = "Crawler%d" % crawlers.size()
	add_child(c)
	c.build(f, mat)
	c.global_position = at + Vector3(0, 0.6, 0)
	c.rotation.y = yaw
	c.add_to_group("vehicles")
	crawlers.append(c)
	return c


func _heli(f: int, at: Vector3, yaw: float) -> Helicopter:
	var h := Helicopter.new()
	h.name = "Gunship%d" % helis.size()
	add_child(h)
	h.build(f, mat)
	h.global_position = at
	h.rotation.y = yaw
	h.add_to_group("vehicles")
	helis.append(h)
	return h


func _dropship(pad: Vector3, lz: Vector3) -> void:
	var d := Dropship.new()
	d.name = "Dropship%d" % dropships.size()
	add_child(d)
	d.build(0, mat, pad, lz)
	d.add_to_group("vehicles")
	dropships.append(d)


func _convoy(f: int, road: String, n: int) -> void:
	var pts := _road(road)
	if pts.size() < 4:
		return
	var c := Convoy.new()
	c.name = "Convoy_" + road.replace(" ", "")
	add_child(c)
	c.build(f, mat, pts, n)
	convoys.append(c)


func _ship(f: int, at: Vector3, route: Array[Vector3]) -> void:
	var s := NavalShip.new()
	s.name = "Destroyer" if f == 0 else "Gunboat%d" % ships.size()
	add_child(s)
	s.build(f, mat, at, route)
	s.add_to_group("vehicles")
	ships.append(s)


func _physics_process(_delta: float) -> void:
	if G.terrain == null:
		return
	for v in get_tree().get_nodes_in_group("vehicles"):
		var rb := v as RigidBody3D
		if rb:
			G.terrain.guard_body(rb, 1.0)


func _process(_delta: float) -> void:
	# The patrol crawler turns around at the end of its track.
	for c in crawlers:
		if c.has_meta("patrol") and c.driver == null and c.path.size() > 1 and c.path_i >= c.path.size() - 1:
			var p: PackedVector3Array = c.path.duplicate()
			p.reverse()
			c.follow(p)
