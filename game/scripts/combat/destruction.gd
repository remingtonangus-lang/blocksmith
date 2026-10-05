class_name Destruction
extends Node3D
## Buildings and vehicles break apart. A building takes blast damage (hit points from its size); at zero its
## own mesh is fractured on the spot: every triangle goes to a cell of a 3D grid (the precomputed fracture
## pattern, 6-14 m cells by building size), each cell becomes a convex rigid body with its piece of the facade,
## and the tower collapses under gravity in a storm of dust, while the city re-meshes the affected cells without
## it. Vehicles fracture the same way into burning wreckage. Debris is capped by the quality preset; settled
## pieces freeze, the oldest are cleared.

var debris: Array = []             # [RigidBody3D, age]
var fires: Array = []              # [position, time left, power]
var debris_mat: ShaderMaterial
var _fire_t := 0.0


func setup() -> void:
	var src: Shader = load("res://shaders/building.gdshader")
	var sh := Shader.new()
	sh.code = src.code.replace("render_mode cull_back;", "render_mode cull_disabled;")
	debris_mat = ShaderMaterial.new()
	debris_mat.shader = sh
	if G.combat:
		G.combat.destruction = self


## Blast damage to buildings near `at`.
func blast(at: Vector3, power: float) -> void:
	if G.world == null:
		return
	for c in G.world.city_list:
		var city: CapitalCity = c
		if not city.in_city(at.x, at.z, -300.0):
			continue
		for b in city.buildings:
			if not b["alive"]:
				continue
			var bp: Vector3 = b["pos"]
			var h: float = b["h"]
			var d := Vector2(at.x - bp.x, at.z - bp.z).length()
			var reach := 30.0 + 12.0 * power
			if d > reach or at.y > bp.y + h + 20.0 or at.y < bp.y - 10.0:
				continue
			if not b.has("hp"):
				b["hp"] = 600.0 + h * 25.0
			b["hp"] -= 260.0 * power * (1.0 - d / reach)
			if b["hp"] <= 0.0:
				collapse(city, b)


func collapse(city: CapitalCity, b: Dictionary) -> void:
	if not b["alive"]:
		return
	b["alive"] = false
	city.rebuild_for(b)
	_fracture_building(b, int(Settings.q["debris"]))
	var h: float = b["h"]
	var p: Vector3 = b["pos"]
	if G.fx:
		# A pale dust cloud: a column where the tower stood and a surge rolling out along the ground.
		for k2 in 70:
			var y := randf() * h
			G.fx._emit(G.fx.cloud, p + Vector3(randf_range(-12, 12), y, randf_range(-12, 12)), Vector3(randf_range(-3, 3), randf_range(-1, 2), randf_range(-3, 3)))
		for k2 in 70:
			var a := randf() * TAU
			var dir := Vector3(cos(a), 0, sin(a))
			G.fx._emit(G.fx.cloud, p + dir * randf_range(5, 25) + Vector3(0, 4, 0), dir * randf_range(8, 22) + Vector3(0, randf_range(0, 2), 0))
		G.fx.explosion(p + Vector3(0, 2, 0), 2.5)
		for k3 in 3:
			fires.append([p + Vector3(randf_range(-12, 12), 1.0, randf_range(-12, 12)), 60.0, 2.0])
		G.fx.shake = maxf(G.fx.shake, 1.0)
	if Sfx.has_method("explosion"):
		Sfx.explosion(p + Vector3(0, h * 0.5, 0), 3.0)
	if G.hud:
		G.hud.message("A tower falls in %s" % city.name_)


## The precomputed fracture of a tower: every section's plan is cut into wedges around its centre and its height
## into slabs (sized so the whole tower makes about `cap` pieces); each piece is a closed prism (facade outside,
## stone at the cuts) and a convex rigid body. The ground slab turns to dust, so the rest comes down.
func _fracture_building(b: Dictionary, cap: int) -> void:
	var xf: Transform3D = b["xf"]
	var seed: float = b["seed"]
	var secs: Array = b["sections"]
	var total := 0.0
	for sec in secs:
		total += float(sec["y1"]) - float(sec["y0"])
	const W := 4
	var slab := maxf(6.0, total * W / maxf(cap, 8))
	var made := 0
	var stone := Color(Kit.STYLE_V[Kit.STONE], seed, 0.5, 0.0)
	var la := randf() * TAU
	var lean := Vector3(cos(la), 0, sin(la))     # the side it falls to
	for sec in secs:
		var prof: PackedVector2Array = sec["prof"]
		var y0: float = sec["y0"]
		var y1: float = sec["y1"]
		var n := prof.size()
		if n < 3:
			continue
		var c2 := Vector2.ZERO
		for v in prof:
			c2 += v
		c2 /= n
		var slabs := maxi(1, int(round((y1 - y0) / slab)))
		var wedges := mini(W, n)
		for sy in slabs:
			var ya := lerpf(y0, y1, float(sy) / slabs)
			var yb := lerpf(y0, y1, float(sy + 1) / slabs)
			if ya < minf(12.0, total * 0.2):
				continue                               # the lower floors go up in dust
			for wi in wedges:
				var i0 := wi * n / wedges
				var i1 := (wi + 1) * n / wedges
				var poly := PackedVector2Array([c2])
				for i in range(i0, i1 + 1):
					poly.append(prof[i % n])
				var cl := Vector2.ZERO
				for v in poly:
					cl += v
				cl /= poly.size()
				# Shrink a little so neighbours start apart (no depenetration kick).
				var local := PackedVector2Array()
				for v in poly:
					local.append((v - cl) * 0.96)
				var cy := (ya + yb) * 0.5
				var k := Kit.new()
				var half := (yb - ya) * 0.48
				k.prism(Transform3D.IDENTITY, local, -half, half, k.col(sec["style"], seed, sec["floor"]), true, true, stone)
				var mesh := k.commit()
				if mesh == null:
					continue
				var pts := PackedVector3Array()
				for v in local:
					pts.append(Vector3(v.x, -half, v.y))
					pts.append(Vector3(v.x, half, v.y))
				var at := xf * Vector3(cl.x, cy, cl.y)
				var out := (xf.basis * Vector3(cl.x - c2.x, 0, cl.y - c2.y)).normalized()
				# Lower pieces are blown out hardest; the upper tower then drops through the gap and topples.
				var f := clampf(cy / maxf(total, 1.0), 0.0, 1.0)
				var vel := out * lerpf(9.0, 1.5, f) * randf_range(0.7, 1.3) + lean * f * 6.0 + Vector3(0, -randf_range(0.0, 3.0), 0)
				_piece(mesh, pts, Transform3D(xf.basis, at), vel, (Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) + lean.cross(Vector3.UP)) * lerpf(0.8, 0.3, f))
				made += 1
	_trim()


func _piece(mesh: ArrayMesh, hull_pts: PackedVector3Array, at: Transform3D, vel: Vector3, spin: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 1 | 8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = debris_mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = hull_pts
	cs.shape = hull
	body.add_child(cs)
	var size := mesh.get_aabb().size
	body.mass = clampf(size.x * size.y * size.z * 120.0, 50.0, 200000.0)
	add_child(body)
	body.global_transform = at
	body.linear_velocity = vel
	body.angular_velocity = spin
	debris.append([body, 0.0])
	return body


## Splits a mesh (world-space positions under `xf`) into convex rigid pieces on a grid.
func _fracture(mesh: ArrayMesh, xf: Transform3D, cell: float, cap: int, push: Vector3, spin: float) -> void:
	# Triangles by grid cell: key -> [surface, first index of each triangle...] (Arrays are references, packed
	# arrays held in containers are copies, so the vertex data is gathered afterwards per piece).
	var groups := {}
	var surf: Array = []
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(v.size())
			for i in v.size():
				idx[i] = i
		surf.append([arr, idx])
		for t in range(0, idx.size(), 3):
			var c := xf * ((v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0)
			var key := Vector4i(floori(c.x / cell), floori(c.y / cell), floori(c.z / cell), s)
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(t)
	var keys := groups.keys()
	keys.shuffle()
	var made := 0
	for key in keys:
		var tris: Array = groups[key]
		if tris.size() < 3:
			continue
		if made >= cap:
			break
		made += 1
		var sd: Array = surf[key.w]
		var arr: Array = sd[0]
		var idx: PackedInt32Array = sd[1]
		var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var sn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var su: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var sc: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var verts := PackedVector3Array()
		var nrms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		for t in tris:
			for j in 3:
				var i: int = idx[t + j]
				verts.append(xf * sv[i])
				nrms.append((xf.basis * sn[i]).normalized())
				uvs.append(su[i] if i < su.size() else Vector2.ZERO)
				cols.append(sc[i] if i < sc.size() else Color(0.21, 0.5, 0.5, 0))
		var center := Vector3.ZERO
		for p in verts:
			center += p
		center /= verts.size()
		var local := PackedVector3Array()
		for p in verts:
			local.append(p - center)
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = local
		a[Mesh.ARRAY_NORMAL] = nrms
		a[Mesh.ARRAY_TEX_UV] = uvs
		a[Mesh.ARRAY_COLOR] = cols
		var pm := ArrayMesh.new()
		pm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		var vel := push + Vector3(randf_range(-1, 1), randf_range(-0.5, 1.0), randf_range(-1, 1)) * (2.0 + spin * 4.0)
		_piece(pm, _subsample(local, 48), Transform3D(Basis.IDENTITY, center), vel, Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spin)
	_trim()


func _subsample(p: PackedVector3Array, n: int) -> PackedVector3Array:
	if p.size() <= n:
		return p
	var out := PackedVector3Array()
	var step := float(p.size()) / n
	for i in n:
		out.append(p[int(i * step)])
	return out


func _trim() -> void:
	var cap := int(Settings.q["debris"]) * 2
	while debris.size() > cap:
		var d: Array = debris.pop_front()
		if is_instance_valid(d[0]):
			(d[0] as Node).queue_free()


## A vehicle breaks into burning pieces.
func break_vehicle(v: Node3D) -> void:
	var at := v.global_position
	var vel := Vector3.ZERO
	if v is RigidBody3D:
		vel = (v as RigidBody3D).linear_velocity
	var meshes: Array[MeshInstance3D] = []
	_collect(v, meshes)
	for mi in meshes:
		if mi.mesh is ArrayMesh and mi.is_visible_in_tree():
			_fracture(mi.mesh, mi.global_transform, 1.8, 14, vel + Vector3(0, 6, 0), 2.0)
	fires.append([at + Vector3(0, 1.5, 0), 45.0, 1.0])
	if G.player and G.player.vehicle == v and v.has_method("exit"):
		G.player.vehicle = null
		G.player.exit_vehicle(at + Vector3(4, 2, 0))
		G.player.take_damage(60.0, at)
	v.queue_free()


func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _physics_process(delta: float) -> void:
	for d in debris:
		d[1] += delta
		if not is_instance_valid(d[0]):
			continue
		var b: RigidBody3D = d[0]
		if not b.freeze and G.fx:
			# A piece that was falling fast and stopped hit something: a puff of dust.
			var v := b.linear_velocity
			if d.size() < 3:
				d.append(v)
			var was: Vector3 = d[2]
			if was.y < -8.0 and v.y > was.y * 0.4:
				G.fx._emit(G.fx.cloud, b.global_position, Vector3(randf_range(-4, 4), 2.0, randf_range(-4, 4)))
				G.fx._emit(G.fx.dust, b.global_position, Vector3(0, 4, 0))
			d[2] = v
		if G.terrain and G.terrain.guard_body(b, 0.3):
			continue
		if not b.freeze and (d[1] > 30.0 or (d[1] > 4.0 and b.linear_velocity.length() < 0.2)):
			b.freeze = true
	_fire_t += delta
	if _fire_t > 0.1 and G.fx:
		_fire_t = 0.0
		var keep := []
		for f in fires:
			f[1] -= 0.1
			if f[1] > 0.0:
				keep.append(f)
				var p: Vector3 = f[0]
				G.fx._emit(G.fx.fire, p + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * f[2], Vector3(0, randf_range(1.5, 3.5), 0))
				if randf() < 0.5:
					G.fx._emit(G.fx.smoke, p + Vector3(0, 2, 0), Vector3(randf_range(-0.5, 0.5), randf_range(2.0, 4.0), randf_range(-0.5, 0.5)), Color(0.12, 0.11, 0.1, 0.7))
		fires = keep
