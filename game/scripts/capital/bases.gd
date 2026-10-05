class_name Bases
extends Node3D
## Military sites: the Capital citadel (terraced podium, grand stair, gate pylons, reflecting pool, glass hall,
## a 160 m rounded tower with a landing pad and beacon, two side towers with a skyway, two twin 42 cm turrets),
## the mountain radar station (domes, a rotating dish, a mast, searchlights, a turret battery), Fort Lumen
## (walls, towers, arched hangars, helipads, barracks), the airfield (runway, hangars, control tower), the naval
## harbour (piers, cranes, sheds, coastal battery) and the Cinder Pact camps (olive and rust sheds, sandbag
## walls, lattice watchtowers, fuel tanks, tents). Each site is one merged mesh plus live parts (turrets, dish,
## searchlights).

var mat: ShaderMaterial
var gen: WorldGen
var turrets: Array[HeavyTurret] = []
var searchlights: Array = []          # [SpotLight3D, base yaw, phase, beam MeshInstance3D]
var dishes: Array[Node3D] = []
var beacons: Array = []               # [OmniLight3D, phase]
var pads := {}                        # site name -> Array of pad world positions (for dropships, helicopters)
var sites := {}                       # name -> {"pos": Vector3, "faction": String, "radius": float}
var rng := RandomNumberGenerator.new()
var _beam_mat: ShaderMaterial


func build(g: WorldGen, material: ShaderMaterial) -> void:
	gen = g
	mat = material
	rng.seed = g.seed * 17 + 5
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = load("res://shaders/beam.gdshader")
	_citadel(g.sites["citadel"])
	_radar(g.sites["radar"])
	_fort(g.sites["fort_lumen"])
	_airfield(g.sites["airfield"])
	_harbor(g.sites["harbor"])
	_cinder_camp(g.sites["cinder_camp"], 1.0)
	_cinder_camp(g.sites["cinder_outpost"], 0.6)
	_artillery_park(g.sites["artillery"])


func _ground(x: float, z: float) -> float:
	return gen.height_at(x, z)


func _site(name: String, pos: Vector3, faction: String, radius: float) -> void:
	sites[name] = {"pos": pos, "faction": faction, "radius": radius}


func _commit(k: Kit, name: String, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = k.commit()
	mi.material_override = mat
	mi.position = at
	mi.visibility_range_end = 12000.0
	add_child(mi)
	# Collision from the mesh faces (static, concave): one shape per site.
	var body := StaticBody3D.new()
	body.position = at
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)


func _turret(at: Vector3, yaw: float, faction: String = "capital") -> HeavyTurret:
	var t := HeavyTurret.new()
	t.name = "Turret42_%d" % turrets.size()
	t.position = at
	t.rotation.y = yaw
	t.build(mat, faction)
	add_child(t)
	turrets.append(t)
	return t


func _searchlight(at: Vector3, yaw: float) -> void:
	var l := SpotLight3D.new()
	l.position = at
	l.spot_range = 900.0
	l.spot_angle = 4.5
	l.spot_attenuation = 0.4
	l.light_energy = 0.0
	l.light_color = Color(0.92, 0.95, 1.0)
	l.light_volumetric_fog_energy = 6.0
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 1800.0
	l.distance_fade_length = 300.0
	add_child(l)
	var beam := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.6
	cone.bottom_radius = 60.0
	cone.height = 700.0
	cone.radial_segments = 12
	cone.cap_top = false
	cone.cap_bottom = false
	beam.mesh = cone
	beam.material_override = _beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.rotation.x = PI * 0.5
	beam.position = Vector3(0, 0, -350.0)
	l.add_child(beam)
	searchlights.append([l, yaw, rng.randf() * TAU, beam])


func _beacon(at: Vector3, color: Color) -> void:
	var l := OmniLight3D.new()
	l.position = at
	l.light_color = color
	l.omni_range = 40.0
	l.light_energy = 0.0
	l.distance_fade_enabled = true
	l.distance_fade_begin = 2500.0
	l.distance_fade_length = 400.0
	add_child(l)
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.8
	s.height = 1.6
	var sm := StandardMaterial3D.new()
	sm.albedo_color = color
	sm.emission_enabled = true
	sm.emission = color
	sm.emission_energy_multiplier = 4.0
	s.material = sm
	m.mesh = s
	l.add_child(m)
	beacons.append([l, rng.randf() * TAU, sm])


# ---------------------------------------------------------------------------------------------- citadel

func _citadel(p: Vector3) -> void:
	var y := p.y
	var at := Vector3(p.x, y, p.z)
	_site("citadel", at, "capital", 260.0)
	var k := Kit.new()
	var I := Transform3D.IDENTITY
	# Octagonal plaza podium over two terraced garden steps.
	var oct := Kit.ngon(120.0, 8, PI / 8.0)
	k.prism(I, Kit.ngon(150.0, 8, PI / 8.0), -6.0, 0.0, k.col(Kit.STONE, 0.1, 3.0, false), true)
	k.prism(I, Kit.ngon(144.0, 8, PI / 8.0), 0.0, 1.0, k.col(Kit.GARDEN, 0.1), true)
	k.prism(I, Kit.ngon(136.0, 8, PI / 8.0), 0.0, 3.0, k.col(Kit.STONE, 0.1, 3.0, false), true)
	k.prism(I, Kit.ngon(130.0, 8, PI / 8.0), 3.0, 4.0, k.col(Kit.GARDEN, 0.1), true)
	k.prism(I, oct, 0.0, 6.0, k.col(Kit.STONE, 0.1, 3.0, false), true)
	k.band(I, oct, 5.6, 0.6, 0.5, k.col(Kit.TRIM, 0.1), false)
	# Grand stair to the south with gate pylons.
	for i in 12:
		k.box(I, Vector3(0, i * 0.5 + 0.25, 128.0 + 30.0 - i * 2.4), Vector3(46, 0.5, 2.4), k.col(Kit.STONE, 0.1, 3.0, false))
	for side in [-1.0, 1.0]:
		k.prism(Transform3D(Basis.IDENTITY, Vector3(side * 30.0, 6.0, 112.0)), Kit.chamfer_rect(8, 8, 2), 0.0, 26.0, k.col(Kit.STONE, 0.2, 4.0, false), true)
		k.band(Transform3D(Basis.IDENTITY, Vector3(side * 30.0, 6.0, 112.0)), Kit.chamfer_rect(8, 8, 2), 24.0, 1.2, 0.6, k.col(Kit.TRIM, 0.2))
		_beacon(at + Vector3(side * 30.0, 33.0, 112.0), Color(1.0, 0.95, 0.85))
	# Reflecting pool between birch rows on the axis.
	k.band(Transform3D(Basis.IDENTITY, Vector3(0, 6.0, 55.0)), Kit.rect(20, 70), -0.4, 0.6, 0.8, k.col(Kit.TRIM, 0.1), false)
	var pool := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 70)
	pool.mesh = pm
	pool.position = at + Vector3(0, 5.9, 55.0)
	pool.material_override = G.world.water.river_mat
	add_child(pool)
	var trees := []
	for side in [-1.0, 1.0]:
		for i in 7:
			trees.append([TreeBuilder.BIRCH, i % 3, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.55), at + Vector3(side * 17.0, 6.0, 25.0 + i * 10.0)), 0.2, i / 7.0])
	# Octagonal glass-and-pier hall at the centre, roof garden on top.
	var hall := Kit.ngon(42.0, 8, PI / 8.0)
	k.prism(Transform3D(Basis.IDENTITY, Vector3(0, 6.0, 0)), hall, 0.0, 16.0, k.col(Kit.GLASS, 0.6, 5.3), true)
	for i in 8:
		var a := TAU * i / 8.0
		k.box(I, Vector3(cos(a) * 41.0, 14.0, sin(a) * 41.0), Vector3(3.0, 16.0, 3.0), k.col(Kit.STONE, 0.6))
	k.band(Transform3D(Basis.IDENTITY, Vector3(0, 6.0, 0)), hall, 16.0, 1.4, 1.0, k.col(Kit.TRIM, 0.6))
	k.prism(Transform3D(Basis.IDENTITY, Vector3(0, 6.0, 0)), Kit.inset(hall, 4.0), 17.4, 18.2, k.col(Kit.GARDEN, 0.6), true)
	# The main tower behind the hall: rounded, 160 m, setback garden terrace, cantilevered pad, beacon crown.
	var tower_c := Vector3(0, 6.0, -70.0)
	var tp := Kit.rounded_rect(40.0, 30.0, 12.0, 6)
	k.prism(Transform3D(Basis.IDENTITY, tower_c), tp, 0.0, 100.0, k.col(Kit.BANDED, 0.7, 4.2), true)
	k.prism(Transform3D(Basis.IDENTITY, tower_c), Kit.inset(tp, 1.2), 100.0, 101.0, k.col(Kit.GARDEN, 0.7), true)
	var tp2 := Kit.scaled(tp, 0.78)
	k.prism(Transform3D(Basis.IDENTITY, tower_c), tp2, 100.0, 160.0, k.col(Kit.GLASS, 0.7, 4.2), true)
	k.band(Transform3D(Basis.IDENTITY, tower_c), tp2, 158.0, 2.0, 0.6, k.col(Kit.TRIM, 0.7))
	k.tube(at * 0.0 + tower_c + Vector3(0, 160.0, 0), tower_c + Vector3(0, 186.0, 0), 1.0, 6, k.col(Kit.METAL, 0.7), true)
	_beacon(at + tower_c + Vector3(0, 187.0, 0), Color(1.0, 0.2, 0.15))
	var pad_c := tower_c + Vector3(0, 120.0, -34.0)
	k.disc(pad_c, 14.0, 1.0, 20, k.col(Kit.TRIM, 0.7), k.col(Kit.PAD, 0.7))
	k.tube(pad_c + Vector3(0, -1.0, 6.0), tower_c + Vector3(0, 96.0, -14.0), 1.2, 6, k.col(Kit.STONE, 0.7), true)
	pads["citadel"] = [at + pad_c, at + Vector3(80, 6.0, -10), at + Vector3(-80, 6.0, -10)]
	for pp in [Vector3(80, 6.0, -10), Vector3(-80, 6.0, -10)]:
		k.disc(pp + Vector3(0, 0.15, 0), 14.0, 0.2, 20, k.col(Kit.TRIM, 0.4), k.col(Kit.PAD, 0.4))
	# Two side towers joined by an enclosed glass skyway and an open bridge to their roof gardens.
	for side in [-1.0, 1.0]:
		var c := Vector3(side * 70.0, 6.0, -60.0)
		var sp := Kit.chamfer_rect(24.0, 24.0, 6.0)
		k.prism(Transform3D(Basis.IDENTITY, c), sp, 0.0, 88.0, k.col(Kit.GLASS, 0.5 + side * 0.1, 4.0), true)
		k.band(Transform3D(Basis.IDENTITY, c), sp, 86.0, 2.0, 0.5, k.col(Kit.TRIM, 0.5))
		k.prism(Transform3D(Basis.IDENTITY, c), Kit.inset(sp, 1.5), 88.0, 88.8, k.col(Kit.GARDEN, 0.5), true)
		trees.append([TreeBuilder.BIRCH, 1, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.4), at + c + Vector3(4, 88.8, 4)), 0.3, 0.5])
		trees.append([TreeBuilder.BROADLEAF, 2, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.35), at + c + Vector3(-4, 88.8, -4)), 0.6, 0.2])
	k.tube(Vector3(-58.0, 6.0 + 52.0, -60.0), Vector3(58.0, 6.0 + 52.0, -60.0), 4.0, 12, k.col(Kit.GLASS, 0.5, 4.0), false)
	k.box(I, Vector3(0, 6.0 + 88.4, -60.0), Vector3(92.0, 0.8, 5.0), k.col(Kit.TRIM, 0.5))
	_commit(k, "Citadel", at)
	# Two barbettes with twin 42 cm turrets on the front corners.
	for side in [-1.0, 1.0]:
		_turret(at + Vector3(side * 92.0, 6.0, 72.0), PI)
	for side in [-1.0, 1.0]:
		_searchlight(at + Vector3(side * 112.0, 8.0, 0.0), side * PI * 0.5)
	if G.world.vegetation:
		G.world.vegetation.add_trees(trees)


# ------------------------------------------------------------------------------------------- radar site

func _radar(p: Vector3) -> void:
	var at := p
	_site("radar", at, "capital", 230.0)
	var k := Kit.new()
	var I := Transform3D.IDENTITY
	k.prism(I, Kit.chamfer_rect(260.0, 200.0, 40.0), -12.0, 0.4, k.col(Kit.CONCRETE, 0.1, 3.0, false), true)
	# Three geodesic-looking radomes on cylindrical bases.
	for d in [Vector3(-60, 0, -40), Vector3(0, 0, -70), Vector3(60, 0, -40)]:
		k.prism(Transform3D(Basis.IDENTITY, d), Kit.ngon(13.0, 16), 0.0, 10.0, k.col(Kit.STONE, 0.3, 3.3, false), true)
		k.sphere(d + Vector3(0, 20.0, 0), 14.0, 10, 16, k.col(Kit.STONE, 0.4))
	# Operations block and bunkers.
	k.prism(Transform3D(Basis.IDENTITY, Vector3(0, 0, 30)), Kit.chamfer_rect(60, 24, 6), 0.0, 12.0, k.col(Kit.BANDED, 0.5, 4.0), true)
	k.band(Transform3D(Basis.IDENTITY, Vector3(0, 0, 30)), Kit.chamfer_rect(60, 24, 6), 11.0, 1.0, 0.5, k.col(Kit.TRIM, 0.5))
	for i in 3:
		k.prism(Transform3D(Basis.IDENTITY, Vector3(-80 + i * 80, 0, 75)), Kit.chamfer_rect(22, 14, 5), 0.0, 4.5, k.col(Kit.CONCRETE, 0.2, 3.0, false), true)
	# Communications mast with red lights.
	k.tube(Vector3(90, 0, 40), Vector3(90, 64, 40), 1.4, 6, k.col(Kit.TRIM, 0.4), true)
	for h in [20.0, 40.0, 60.0]:
		k.box(I, Vector3(90, h, 40), Vector3(7.0, 0.4, 0.4), k.col(Kit.METAL, 0.4))
	_beacon(at + Vector3(90, 65, 40), Color(1.0, 0.15, 0.1))
	k.disc(Vector3(-90, 0.6, 40), 14.0, 0.2, 20, k.col(Kit.TRIM, 0.4), k.col(Kit.PAD, 0.4))
	pads["radar"] = [at + Vector3(-90, 0.6, 40)]
	_commit(k, "RadarStation", at)
	# The rotating search radar on the operations roof.
	var dish := Node3D.new()
	dish.position = at + Vector3(0, 12.0, 30)
	add_child(dish)
	var dk := Kit.new()
	dk.tube(Vector3.ZERO, Vector3(0, 4, 0), 0.8, 8, dk.col(Kit.METAL, 0.3), true)
	dk.box(Transform3D.IDENTITY, Vector3(0, 6.5, 0), Vector3(18.0, 4.5, 0.6), dk.col(Kit.STONE, 0.3))
	dk.box(Transform3D.IDENTITY, Vector3(0, 6.5, -0.8), Vector3(16.0, 0.4, 1.4), dk.col(Kit.METAL, 0.3))
	var dmi := MeshInstance3D.new()
	dmi.mesh = dk.commit()
	dmi.material_override = mat
	dish.add_child(dmi)
	dishes.append(dish)
	# A turret battery covering the valley (south), searchlights on the corners.
	_turret(at + Vector3(-70, 0.4, 92), PI)
	_turret(at + Vector3(70, 0.4, 92), PI)
	for c in [Vector3(-125, 2, -95), Vector3(125, 2, -95), Vector3(-125, 2, 95), Vector3(125, 2, 95)]:
		_searchlight(at + c, atan2(c.x, c.z))


# ------------------------------------------------------------------------------------------- Fort Lumen

func _fort(p: Vector3) -> void:
	var at := p
	_site("fort_lumen", at, "capital", 240.0)
	var k := Kit.new()
	var I := Transform3D.IDENTITY
	k.prism(I, Kit.ngon(150.0, 8, PI / 8.0), -10.0, 0.3, k.col(Kit.CONCRETE, 0.1, 3.0, false), true)
	# Perimeter wall (8 segments, a gap on the east for the gate) with corner towers.
	var poly := Kit.ngon(145.0, 8, PI / 8.0)
	for i in 8:
		var a := poly[i]
		var b := poly[(i + 1) % 8]
		var mid := (a + b) * 0.5
		var len := a.distance_to(b)
		var ang := atan2(b.y - a.y, b.x - a.x)
		var xf := Transform3D(Basis(Vector3.UP, -ang), Vector3(mid.x, 0, mid.y))
		if i == 0:
			for s in [-1.0, 1.0]:
				k.box(xf, Vector3(s * len * 0.32, 4.0, 0), Vector3(len * 0.36, 8.0, 2.4), k.col(Kit.STONE, 0.2, 2.0, false))
		else:
			k.box(xf, Vector3(0, 4.0, 0), Vector3(len, 8.0, 2.4), k.col(Kit.STONE, 0.2, 2.0, false))
		k.box(xf, Vector3(0, 8.3, 0), Vector3(len, 0.6, 3.0), k.col(Kit.TRIM, 0.2))
		k.prism(Transform3D(Basis.IDENTITY, Vector3(a.x, 0, a.y)), Kit.chamfer_rect(9, 9, 2), 0.0, 16.0, k.col(Kit.STONE, 0.3, 4.0, false), true)
		k.band(Transform3D(Basis.IDENTITY, Vector3(a.x, 0, a.y)), Kit.chamfer_rect(9, 9, 2), 14.0, 2.0, 0.8, k.col(Kit.TRIM, 0.3))
		_searchlight(at + Vector3(a.x, 18.0, a.y), atan2(a.x, a.y))
	# Arched hangars (barrel vaults) along the north side.
	for i in 3:
		var hc := Vector3(-70 + i * 70, 0, -80)
		var arch := PackedVector2Array()
		for s in 13:
			var a := PI * s / 12.0
			arch.append(Vector2(cos(a) * 22.0, sin(a) * 15.0))
		var hx := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), hc + Vector3(0, 0, 24.0))
		k.prism(hx, arch, 0.0, 48.0, k.col(Kit.STONE, 0.4 + i * 0.1, 3.0, false), true, true, k.col(Kit.DARKGLASS, 0.4))
	# Barracks and command block.
	for i in 4:
		k.prism(Transform3D(Basis.IDENTITY, Vector3(-80 + i * 40, 0, 40)), Kit.chamfer_rect(30, 14, 3), 0.0, 9.0, k.col(Kit.BANDED, 0.3 + i * 0.05, 4.5), true)
	k.prism(Transform3D(Basis.IDENTITY, Vector3(60, 0, 20)), Kit.rounded_rect(36, 28, 9, 4), 0.0, 22.0, k.col(Kit.GLASS, 0.8, 4.4), true)
	k.band(Transform3D(Basis.IDENTITY, Vector3(60, 0, 20)), Kit.rounded_rect(36, 28, 9, 4), 21.0, 1.2, 0.5, k.col(Kit.TRIM, 0.8))
	k.sphere(Vector3(60, 30, 20), 7.0, 8, 12, k.col(Kit.STONE, 0.8))
	var fort_pads := []
	for i in 4:
		var pc := Vector3(-60 + i * 40, 0.4, 95)
		k.disc(pc, 13.0, 0.2, 20, k.col(Kit.TRIM, 0.4), k.col(Kit.PAD, 0.4))
		fort_pads.append(at + pc)
	pads["fort_lumen"] = fort_pads
	_commit(k, "FortLumen", at)
	_turret(at + Vector3(-110, 0.3, 0), -PI * 0.5)


# ---------------------------------------------------------------------------------------------- airfield

func _airfield(p: Vector3) -> void:
	var at := p
	_site("airfield", at, "capital", 700.0)
	var k := Kit.new()
	var I := Transform3D.IDENTITY
	# Runway (east-west) with threshold bars and a centreline, taxiway and apron.
	k.prism(I, Kit.rect(1500, 50), -1.5, 0.25, k.col(Kit.CONCRETE, 0.05, 3.0, false), true)
	for i in 50:
		k.box(I, Vector3(-700 + i * 28.6, 0.27, 0), Vector3(14.0, 0.04, 0.9), k.col(Kit.STONE, 0.1))
	for s in [-1.0, 1.0]:
		for j in 8:
			k.box(I, Vector3(s * 720.0, 0.27, -19.0 + j * 5.4), Vector3(30.0, 0.04, 2.4), k.col(Kit.STONE, 0.1))
	k.prism(I, Kit.rect(900, 22), -1.5, 0.2, k.col(Kit.CONCRETE, 0.1, 3.0, false), true)
	k.prism(Transform3D(Basis.IDENTITY, Vector3(0, 0, -120)), Kit.rect(600, 140), -1.5, 0.22, k.col(Kit.CONCRETE, 0.12, 3.0, false), true)
	for i in 4:
		var hc := Vector3(-225 + i * 150, 0, -230)
		var arch := PackedVector2Array()
		for s in 13:
			var a := PI * s / 12.0
			arch.append(Vector2(cos(a) * 40.0, sin(a) * 24.0))
		var hx := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), hc + Vector3(0, 0, 40.0))
		k.prism(hx, arch, 0.0, 80.0, k.col(Kit.STONE, 0.3 + i * 0.1, 3.0, false), true, true, k.col(Kit.DARKGLASS, 0.3))
	# Control tower: a slender shaft with a flared glass cab.
	var tc := Vector3(360, 0, -150)
	k.prism(Transform3D(Basis.IDENTITY, tc), Kit.ngon(5.0, 8, PI / 8.0), 0.0, 38.0, k.col(Kit.STONE, 0.5, 4.0, false), true)
	k.prism(Transform3D(Basis.IDENTITY, tc), Kit.ngon(11.0, 8, PI / 8.0), 38.0, 45.0, k.col(Kit.GLASS, 0.5, 7.0), true)
	k.band(Transform3D(Basis.IDENTITY, tc), Kit.ngon(11.0, 8, PI / 8.0), 45.0, 1.2, 0.8, k.col(Kit.TRIM, 0.5))
	_beacon(at + tc + Vector3(0, 48, 0), Color(1.0, 0.2, 0.1))
	var air_pads := []
	for i in 6:
		var pc := Vector3(-250 + i * 100, 0.26, -120)
		k.disc(pc, 16.0, 0.02, 20, k.col(Kit.TRIM, 0.4), k.col(Kit.PAD, 0.4))
		air_pads.append(at + pc)
	pads["airfield"] = air_pads
	_commit(k, "Airfield", at)


# ------------------------------------------------------------------------------------------------ harbor

func _harbor(p: Vector3) -> void:
	var at := Vector3(p.x, maxf(p.y, 6.0), p.z)
	_site("harbor", at, "capital", 420.0)
	var k := Kit.new()
	var I := Transform3D.IDENTITY
	# Quay along the seaward (east) edge and three piers reaching into the river mouth / sea.
	k.prism(Transform3D(Basis.IDENTITY, Vector3(260, 0, 0)), Kit.rect(40, 700), -14.0, 0.5, k.col(Kit.CONCRETE, 0.1, 3.0, false), true)
	for i in 3:
		k.prism(Transform3D(Basis.IDENTITY, Vector3(420, 0, -200 + i * 200)), Kit.rect(300, 24), -14.0, 0.5, k.col(Kit.CONCRETE, 0.15, 3.0, false), true)
		# Gantry crane on each pier.
		var cc := Vector3(400, 0.5, -200 + i * 200)
		for s in [-1.0, 1.0]:
			k.box(I, cc + Vector3(-8, 18, s * 9), Vector3(1.5, 36, 1.5), k.col(Kit.TRIM, 0.4))
			k.box(I, cc + Vector3(8, 18, s * 9), Vector3(1.5, 36, 1.5), k.col(Kit.TRIM, 0.4))
		k.box(I, cc + Vector3(10, 37, 0), Vector3(60, 3, 20), k.col(Kit.STONE, 0.4))
	# Sheds and a naval command block.
	for i in 5:
		k.prism(Transform3D(Basis.IDENTITY, Vector3(160, 0, -260 + i * 120)), Kit.chamfer_rect(60, 34, 4), 0.0, 14.0, k.col(Kit.STONE, 0.2 + i * 0.05, 3.5, false), true)
	k.prism(Transform3D(Basis.IDENTITY, Vector3(120, 0, 300)), Kit.rounded_rect(40, 40, 12, 5), 0.0, 60.0, k.col(Kit.GLASS, 0.9, 4.0), true)
	k.band(Transform3D(Basis.IDENTITY, Vector3(120, 0, 300)), Kit.rounded_rect(40, 40, 12, 5), 58.0, 2.0, 0.6, k.col(Kit.TRIM, 0.9))
	_commit(k, "Harbor", at)
	_turret(at + Vector3(250, 0.5, 340), PI * 0.5)
	_turret(at + Vector3(250, 0.5, -340), PI * 0.5)
	pads["harbor"] = [at + Vector3(120, 60.5, 300)]


# ------------------------------------------------------------------------------------- the Cinder Pact

func _cinder_camp(p: Vector3, scale: float) -> void:
	var at := p
	var name := "cinder_camp" if scale > 0.8 else "cinder_outpost"
	_site(name, at, "cinder", 200.0 * scale)
	var k := Kit.new()
	var I := Transform3D.IDENTITY
	var r := 150.0 * scale
	# Sandbag / earth berm ring with gaps.
	for i in 28:
		var a := TAU * i / 28.0
		if i % 7 == 0:
			continue
		var c := Vector3(cos(a) * r, 1.2, sin(a) * r)
		k.box(Transform3D(Basis(Vector3.UP, -a), c), Vector3.ZERO, Vector3(3.2, 2.4, r * TAU / 28.0 * 0.95), k.col(Kit.OLIVE, 0.2, 2.0, false))
	# Prefab sheds, rusted roofs.
	for i in int(10 * scale) + 2:
		var a := rng.randf() * TAU
		var d := rng.randf_range(20.0, r * 0.75)
		var c := Vector3(cos(a) * d, 0, sin(a) * d)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), c)
		k.prism(xf, Kit.rect(rng.randf_range(12, 26), rng.randf_range(8, 12)), -1.0, 4.5, k.col(Kit.OLIVE, rng.randf(), 3.0, false), true, false, k.col(Kit.RUST, 0.5))
	# Lattice watchtowers.
	for i in int(4 * scale) + 1:
		var a := TAU * (i + 0.5) / (int(4 * scale) + 1)
		var c := Vector3(cos(a) * r * 0.9, 0, sin(a) * r * 0.9)
		for cx in [-1.5, 1.5]:
			for cz in [-1.5, 1.5]:
				k.box(I, c + Vector3(cx, 7, cz), Vector3(0.35, 14, 0.35), k.col(Kit.RUST, 0.3))
		k.box(I, c + Vector3(0, 14.2, 0), Vector3(5, 0.4, 5), k.col(Kit.OLIVE, 0.3))
		k.box(I, c + Vector3(0, 16.5, 0), Vector3(4.6, 0.3, 4.6), k.col(Kit.RUST, 0.3))
		_searchlight(at + c + Vector3(0, 15.5, 0), a)
	# Fuel tanks.
	for i in 3:
		var c := Vector3(-r * 0.4 + i * 14.0, 0, r * 0.45)
		k.prism(Transform3D(Basis.IDENTITY, c), Kit.ngon(5.0, 14), 0.0, 9.0, k.col(Kit.RUST, 0.6, 3.0, false), true)
	# Tents.
	for i in int(8 * scale):
		var c := Vector3(rng.randf_range(-r * 0.6, r * 0.6), 0, rng.randf_range(-r * 0.6, r * 0.6))
		var tent := PackedVector2Array([Vector2(-3.0, 0.0), Vector2(3.0, 0.0), Vector2(0.0, 3.2)])
		var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).rotated(Vector3.UP, rng.randf() * TAU), c + Vector3(0, 0, 4.0))
		k.prism(xf, tent, 0.0, 8.0, k.col(Kit.OLIVE, 0.8, 3.0, false), true, true)
	pads[name] = [at + Vector3(0, 0.3, -r * 0.4)]
	_commit(k, "CinderCamp", at)
	if scale > 0.8:
		_turret(at + Vector3(r * 0.55, 0.3, 0), PI * 0.5, "cinder")


func _artillery_park(p: Vector3) -> void:
	_site("artillery", p, "capital", 120.0)
	var k := Kit.new()
	k.prism(Transform3D.IDENTITY, Kit.chamfer_rect(160, 90, 20), -4.0, 0.3, k.col(Kit.CONCRETE, 0.2, 3.0, false), true)
	for i in 4:
		var c := Vector3(-54 + i * 36, 0.3, 0)
		k.prism(Transform3D(Basis.IDENTITY, c), Kit.ngon(11.0, 12), 0.0, 1.6, k.col(Kit.STONE, 0.2, 2.0, false), true)
	_commit(k, "ArtilleryPark", p)


# ------------------------------------------------------------------------------------------------ life

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var night: float = 1.0 - (G.sky.daylight if G.sky else 1.0)
	for d in dishes:
		d.rotation.y += delta * 0.9
	for s in searchlights:
		var l: SpotLight3D = s[0]
		var yaw: float = s[1] + sin(t * 0.21 + s[2]) * 0.9
		# Sweeping the night sky, 14-48 degrees up (pointed down, the beams lay on the slopes as white rods).
		var pitch := 0.55 + sin(t * 0.13 + s[2] * 2.0) * 0.3
		l.rotation = Vector3(pitch, yaw + PI, 0.0)
		l.light_energy = night * 18.0
		l.visible = night > 0.02
		(s[3] as MeshInstance3D).visible = night > 0.05
	for b in beacons:
		var l: OmniLight3D = b[0]
		var on := 1.0 if fmod(t + b[1], 1.6) < 0.35 else 0.0
		l.light_energy = on * (0.3 + night * 3.0)
		(b[2] as StandardMaterial3D).emission_energy_multiplier = 0.6 + on * 6.0
