extends RefCounted
## Chapter 5 (The Meridian Line) helpers: the westbound express on the worldgen rail and Kessler's Tank, the water
## stop on the grade between Port Linden and Bitter Spring where the robbery is staged.

const TRAIN = preload("res://src/missions/ch5/train.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")

const TANK_S := 2000.0       # metres along the line from Port Linden
const START_S := 1720.0      # where the express is when Ruth first sees its smoke
const LIMIT_S := 3000.0      # past here it's into Bitter Spring: it got away
const POLE_S := 2250.0       # the rag on the third pole past the tank: Ruth waits here and goes when the engine passes

static func make_train(d, with_cars := true) -> Node3D:
	var t = TRAIN.new()
	Game.main.add_child(t)
	t.setup(Game.world.features.get("rail", {}).get("points", []), true, with_cars)
	t.slow_zones = [{"s": TANK_S, "r": 60.0, "v": 3.5}]
	d.track(t)
	return t

## A board water tower on legs beside the track (a prop; tracked by the director).
static func water_tower(d, pos: Vector3) -> void:
	var n := Node3D.new()
	n.name = "KesslersTank"
	Game.main.add_child(n)
	n.global_position = Vector3(pos.x, Game.world.height(pos.x, pos.z), pos.z)
	d.track(n)
	if Game.headless:
		return
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.4, 0.3, 0.2)
	wood.roughness = 0.9
	for x in [-1.4, 1.4]:
		for z in [-1.4, 1.4]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.25, 5.0, 0.25)
			leg.mesh = lm
			leg.material_override = wood
			leg.position = Vector3(x, 2.5, z)
			n.add_child(leg)
	var tank := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.2
	cm.bottom_radius = 2.2
	cm.height = 3.2
	tank.mesh = cm
	tank.material_override = wood
	tank.position = Vector3(0, 6.6, 0)
	n.add_child(tank)

## Where to wait: beside the track at the rag pole past the tank.
static func wait_spot(train) -> Vector3:
	var p: Vector3 = train.at(POLE_S)
	var side: Vector3 = train.tangent(POLE_S).cross(Vector3.UP).normalized()
	return C3.dry(p + side * 55.0 - train.tangent(POLE_S) * 30.0)   # back in the cut, out of the crew's sight
