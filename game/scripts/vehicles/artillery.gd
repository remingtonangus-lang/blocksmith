class_name ArtilleryBattery
extends Node3D
## Four towed 155 mm howitzers on the artillery park's gun pits (the Capital), or two mortars in a sandbagged pit
## (the Cinder Pact). `fire_at(points)` lays the guns, fires (flash, smoke, report) and sends real shells on
## ballistic arcs that land on the targets (Combat.shell), so barrages are seen leaving and arriving.

var faction := 0
var guns: Array = []            # [carriage, barrel, muzzle, reload]
var mat: Material
var queue: Array = []           # target points waiting for a gun


func build(f: int, m: Material, at: Vector3, count: int) -> void:
	faction = f
	mat = m
	global_position = at
	for i in count:
		var c := Node3D.new()
		c.position = Vector3(-54 + i * 36, 0.3, 0) if f == 0 else Vector3(-6 + i * 12, 0.0, 0)
		add_child(c)
		var k := Kit.new()
		var main := Kit.STONE if f == 0 else Kit.OLIVE
		if f == 0:
			# Split trail carriage, shield, wheels.
			for s in [-1.0, 1.0]:
				k.box(Transform3D(Basis(Vector3.UP, s * 0.35), Vector3(s * 1.2, 0.5, 2.8)), Vector3.ZERO, Vector3(0.3, 0.3, 4.8), k.col(main, 0.3))
				k.tube(Vector3(s * 1.3, 0.75, -0.4), Vector3(s * 1.7, 0.75, -0.4), 0.75, 12, k.col(Kit.METAL, 0.3), true)
			k.box(Transform3D.IDENTITY, Vector3(0, 1.2, -0.6), Vector3(2.4, 0.9, 1.6), k.col(main, 0.3))
			k.box(Transform3D.IDENTITY, Vector3(0, 1.9, -1.6), Vector3(3.0, 1.4, 0.12), k.col(Kit.TRIM, 0.3))
		else:
			k.prism(Transform3D.IDENTITY, Kit.ngon(2.4, 10), 0.0, 0.9, k.col(Kit.OLIVE, 0.3, 1.0, false), false)
			k.box(Transform3D.IDENTITY, Vector3(0, 0.15, 0), Vector3(0.8, 0.3, 0.8), k.col(Kit.METAL, 0.3))
		var mi := MeshInstance3D.new()
		mi.mesh = k.commit()
		mi.material_override = mat
		c.add_child(mi)
		var b := Node3D.new()
		b.position = Vector3(0, 1.5, -0.6) if f == 0 else Vector3(0, 0.3, 0)
		c.add_child(b)
		var g := Kit.new()
		if f == 0:
			g.tube(Vector3(0, 0, 1.0), Vector3(0, 0, -6.2), 0.16, 10, g.col(Kit.METAL, 0.3), true)
			g.box(Transform3D.IDENTITY, Vector3(0, 0, -6.2), Vector3(0.5, 0.4, 0.5), g.col(Kit.METAL, 0.3))
			g.box(Transform3D.IDENTITY, Vector3(0, 0, 0.3), Vector3(0.7, 0.7, 1.6), g.col(main, 0.3))
		else:
			g.tube(Vector3(0, 0, 0), Vector3(0, 0, -1.4), 0.07, 8, g.col(Kit.METAL, 0.3), true)
		var gmi := MeshInstance3D.new()
		gmi.mesh = g.commit()
		gmi.material_override = mat
		b.add_child(gmi)
		var mz := Node3D.new()
		mz.position = Vector3(0, 0, -6.6) if f == 0 else Vector3(0, 0, -1.5)
		b.add_child(mz)
		guns.append([c, b, mz, 0.0])
		b.rotation.x = 0.5 if f == 0 else 1.1


func fire_at(points: Array) -> void:
	queue.append_array(points)


func _process(delta: float) -> void:
	for g in guns:
		g[3] = maxf(0.0, g[3] - delta)
		if queue.is_empty() or g[3] > 0.0:
			continue
		var target: Vector3 = queue.pop_front()
		var c: Node3D = g[0]
		var b: Node3D = g[1]
		var m: Node3D = g[2]
		var to := target - c.global_position
		c.rotation.y = atan2(-to.x, -to.z) - rotation.y
		var speed := 380.0 if faction == 0 else 160.0
		var d := Vector2(to.x, to.z).length()
		var v2 := speed * speed
		var disc := v2 * v2 - 9.81 * (9.81 * d * d + 2.0 * to.y * v2)
		var ang := deg_to_rad(45.0)
		if disc >= 0.0:
			# Mortars use the high arc, guns the low one.
			ang = atan((v2 + sqrt(disc)) / (9.81 * d)) if faction == 1 else atan((v2 - sqrt(disc)) / (9.81 * d))
		b.rotation.x = ang
		g[3] = 5.0 if faction == 0 else 3.0
		var dir := (Basis(Vector3.UP, atan2(-to.x, -to.z)) * Basis(Vector3.RIGHT, ang) * Vector3(0, 0, -1)).normalized()
		if G.fx:
			G.fx.flash(m.global_position, 2.5 if faction == 0 else 1.0)
			for k in 6:
				G.fx._emit(G.fx.smoke, m.global_position, dir * randf_range(2, 6) + Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)))
		if Sfx.has_method("cannon"):
			Sfx.cannon(m.global_position, 1.0 if faction == 0 else 0.5)
		if G.combat and G.combat.has_method("shell"):
			G.combat.shell(m.global_position, dir, speed, 1.4 if faction == 0 else 0.8, faction, [])
