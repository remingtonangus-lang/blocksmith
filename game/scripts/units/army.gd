class_name Army
extends Node3D
## Every infantryman in the world, both factions, as flat arrays (fast in GDScript) drawn by three GPU-animated
## MultiMeshes (trooper, officer, heavy bodies). Soldiers think at ~4 Hz on a staggered schedule (find targets
## through a 32 m spatial hash with a terrain line-of-sight check, move to their squad's objective in bounds,
## crouch and fire bursts), and integrate movement every frame. Corpses stay for a while. `ray_hit` lets the
## player's bullets find soldiers; `hit` applies damage.

const CAP := 900
const GRID := 32.0
const DRAW_DIST := 2600.0
const THINK := 0.25

enum { CAPITAL, CINDER }
enum { S_IDLE, S_WALK, S_RUN, S_AIM, S_CROUCH, S_DEAD }

# Palettes (8 slots each): visor, uniform, trim, boots/gloves, weapon, accent (rank), under-suit, skin.
const PALETTES := [
	# 0 Capital trooper: white dress armour, grey trim, smoked visor.
	[Color(0.03, 0.04, 0.05), Color(0.86, 0.87, 0.86), Color(0.42, 0.44, 0.47), Color(0.16, 0.17, 0.19), Color(0.12, 0.12, 0.13), Color(0.82, 0.83, 0.83), Color(0.32, 0.33, 0.35), Color(0.72, 0.56, 0.46)],
	# 1 Capital sergeant: grey pauldrons.
	[Color(0.03, 0.04, 0.05), Color(0.86, 0.87, 0.86), Color(0.42, 0.44, 0.47), Color(0.16, 0.17, 0.19), Color(0.12, 0.12, 0.13), Color(0.5, 0.52, 0.55), Color(0.32, 0.33, 0.35), Color(0.72, 0.56, 0.46)],
	# 2 Capital officer: white coat, silver trim, black cap band.
	[Color(0.03, 0.04, 0.05), Color(0.9, 0.9, 0.89), Color(0.62, 0.64, 0.67), Color(0.08, 0.08, 0.09), Color(0.2, 0.2, 0.21), Color(0.78, 0.76, 0.66), Color(0.86, 0.87, 0.86), Color(0.74, 0.58, 0.48)],
	# 3 Capital heavy: light grey plates, dark trim.
	[Color(0.03, 0.04, 0.05), Color(0.7, 0.72, 0.74), Color(0.3, 0.31, 0.33), Color(0.14, 0.15, 0.16), Color(0.15, 0.15, 0.16), Color(0.86, 0.87, 0.86), Color(0.25, 0.26, 0.28), Color(0.7, 0.55, 0.45)],
	# 4 Cinder rifleman: olive fatigues, brown webbing and helmet, rust scarf, dark mask.
	[Color(0.05, 0.05, 0.04), Color(0.22, 0.25, 0.1), Color(0.24, 0.17, 0.09), Color(0.1, 0.07, 0.05), Color(0.09, 0.09, 0.09), Color(0.6, 0.2, 0.06), Color(0.2, 0.19, 0.11), Color(0.6, 0.44, 0.34)],
	# 5 Cinder veteran: darker drab, orange scarf.
	[Color(0.05, 0.05, 0.04), Color(0.18, 0.2, 0.09), Color(0.28, 0.2, 0.1), Color(0.09, 0.07, 0.05), Color(0.09, 0.09, 0.09), Color(0.72, 0.32, 0.06), Color(0.17, 0.16, 0.1), Color(0.58, 0.43, 0.33)],
	# 6 Cinder officer: rust coat, olive trim.
	[Color(0.05, 0.05, 0.04), Color(0.4, 0.17, 0.07), Color(0.22, 0.24, 0.11), Color(0.08, 0.06, 0.04), Color(0.13, 0.13, 0.13), Color(0.7, 0.58, 0.3), Color(0.22, 0.25, 0.1), Color(0.6, 0.45, 0.35)],
	# 7 Cinder heavy.
	[Color(0.05, 0.05, 0.04), Color(0.17, 0.19, 0.09), Color(0.36, 0.2, 0.08), Color(0.09, 0.07, 0.05), Color(0.11, 0.11, 0.11), Color(0.62, 0.24, 0.07), Color(0.16, 0.15, 0.1), Color(0.58, 0.43, 0.33)],
]

var n := 0
var pos := PackedVector3Array()
var yaw := PackedFloat32Array()
var fac := PackedByteArray()
var body := PackedByteArray()
var pal := PackedByteArray()
var hp := PackedFloat32Array()
var state := PackedByteArray()
var target := PackedInt32Array()      # soldier index, -2 = the player, -1 = none
var squad := PackedInt32Array()
var goal := PackedVector3Array()
var think_t := PackedFloat32Array()
var fire_t := PackedFloat32Array()
var burst := PackedInt32Array()
var phase := PackedFloat32Array()
var aim := PackedFloat32Array()
var mode_t := PackedFloat32Array()     # time left in the current move / fire phase
var moving := PackedByteArray()
var dead_t := PackedFloat32Array()
var crouch := PackedByteArray()
var grid := {}                         # Vector2i -> PackedInt32Array of indices
var squads: Array = []                 # {faction, members: Array, objective: Vector3, spread: float}
var mm: Array[MultiMesh] = []
var mmi: Array[MultiMeshInstance3D] = []
var bufs: Array[PackedFloat32Array] = []
var counts := [0, 0, 0, 0, 0, 0]
var mat: ShaderMaterial
var free_list: Array[int] = []
var kills := [0, 0]
var fx: Node = null
var rng := RandomNumberGenerator.new()
var _t := 0.0
var player_hp_cb: Callable


func setup() -> void:
	rng.seed = 4711
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/soldier.gdshader")
	var flat := PackedVector3Array()
	for p in PALETTES:
		for c in p:
			flat.append(Vector3(c.r, c.g, c.b))
	mat.set_shader_parameter("palette", flat)
	for b in 6:
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.use_custom_data = true
		m.mesh = SoldierMesh.build(b % 3, b >= 3)
		m.instance_count = CAP
		m.visible_instance_count = 0
		var inst := MultiMeshInstance3D.new()
		inst.name = ["Troopers", "Officers", "Heavies", "CinderRiflemen", "CinderOfficers", "CinderHeavies"][b]
		inst.multimesh = m
		inst.material_override = mat
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(inst)
		mm.append(m)
		mmi.append(inst)
		var buf := PackedFloat32Array()
		buf.resize(CAP * 16)
		bufs.append(buf)
	for arr in [pos, goal]:
		arr.resize(CAP)
	for arr in [yaw, hp, think_t, fire_t, phase, aim, mode_t, dead_t]:
		arr.resize(CAP)
	for arr in [fac, body, pal, state, moving, crouch]:
		arr.resize(CAP)
	for arr in [target, squad, burst]:
		arr.resize(CAP)


func spawn(p: Vector3, faction: int, rank: int, sq: int) -> int:
	var i: int
	if free_list.size() > 0:
		i = free_list.pop_back()
	elif n < CAP:
		i = n
		n += 1
	else:
		return -1
	var y := G.world.ground_at(p.x, p.z) if G.world else p.y
	pos[i] = Vector3(p.x, y, p.z)
	yaw[i] = rng.randf() * TAU
	fac[i] = faction
	# Ranks: 0 trooper, 1 sergeant, 2 officer, 3 heavy.
	body[i] = SoldierMesh.OFFICER if rank == 2 else (SoldierMesh.HEAVY if rank == 3 else SoldierMesh.TROOPER)
	pal[i] = rank + (4 if faction == CINDER else 0)
	hp[i] = 100.0 if rank != 3 else 160.0
	state[i] = S_IDLE
	target[i] = -1
	squad[i] = sq
	goal[i] = pos[i]
	think_t[i] = rng.randf() * THINK
	fire_t[i] = 0.0
	burst[i] = 0
	phase[i] = rng.randf()
	aim[i] = 0.0
	mode_t[i] = rng.randf_range(1.0, 4.0)
	moving[i] = 1
	dead_t[i] = 0.0
	crouch[i] = 0
	_grid_add(i)
	return i


func alive(i: int) -> bool:
	return i >= 0 and i < n and state[i] != S_DEAD and hp[i] > 0.0


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / GRID), floori(p.z / GRID))


func _grid_add(i: int) -> void:
	var c := _cell(pos[i])
	if not grid.has(c):
		grid[c] = PackedInt32Array()
	var a: PackedInt32Array = grid[c]
	a.append(i)
	grid[c] = a


func _grid_remove(i: int, c: Vector2i) -> void:
	if not grid.has(c):
		return
	var a: PackedInt32Array = grid[c]
	var k := a.find(i)
	if k >= 0:
		a.remove_at(k)
		grid[c] = a


## Nearest living enemy of `faction` within `r` of p (squared-distance search over the grid).
func nearest_enemy(p: Vector3, faction: int, r: float) -> int:
	var best := -1
	var bd := r * r
	var c := _cell(p)
	var k := int(ceil(r / GRID))
	for dz in range(-k, k + 1):
		for dx in range(-k, k + 1):
			var cc := c + Vector2i(dx, dz)
			if not grid.has(cc):
				continue
			for j in grid[cc]:
				if fac[j] == faction or state[j] == S_DEAD:
					continue
				var d := pos[j].distance_squared_to(p)
				if d < bd:
					bd = d
					best = j
	return best


## Terrain line of sight between two points (eye heights added by the caller).
func los(a: Vector3, b: Vector3) -> bool:
	for k in range(1, 8):
		var t := k / 8.0
		var p := a.lerp(b, t)
		if G.world.ground_at(p.x, p.z) > p.y:
			return false
	return true


func _process(delta: float) -> void:
	if n == 0:
		return
	_t += delta
	var cam := get_viewport().get_camera_3d()
	var cp := cam.global_position if cam else Vector3.ZERO
	var player_p: Vector3 = G.player.global_position if G.player and is_instance_valid(G.player) and G.player.vehicle == null else Vector3(1e9, 0, 0)
	for i in n:
		if state[i] == S_DEAD:
			dead_t[i] += delta
			if dead_t[i] > 120.0 and pos[i].distance_to(cp) > 60.0:
				state[i] = 255
				free_list.append(i)
			continue
		if state[i] == 255:
			continue
		think_t[i] -= delta
		if think_t[i] <= 0.0:
			think_t[i] += THINK
			_think(i, player_p)
		_act(i, delta, player_p)
	_upload(cp)


func _think(i: int, player_p: Vector3) -> void:
	var p := pos[i]
	var f := fac[i]
	# Targets: an enemy soldier in range, or the player if this is a Cinder soldier and the player is close.
	var t := target[i]
	if t >= 0 and (not alive(t) or pos[t].distance_squared_to(p) > 380.0 * 380.0):
		t = -1
	if t == -1:
		var e := nearest_enemy(p, f, 340.0)
		if e >= 0 and los(p + Vector3(0, 1.5, 0), pos[e] + Vector3(0, 1.2, 0)):
			t = e
	if f == CINDER and player_p.distance_squared_to(p) < 260.0 * 260.0:
		if t == -1 or player_p.distance_squared_to(p) < pos[t].distance_squared_to(p):
			if los(p + Vector3(0, 1.5, 0), player_p + Vector3(0, 1.4, 0)):
				t = -2
	target[i] = t
	# Bounding movement: alternate moving and firing phases.
	mode_t[i] -= THINK
	if mode_t[i] <= 0.0:
		if t != -1 and moving[i] == 1:
			moving[i] = 0
			crouch[i] = 1 if rng.randf() < 0.55 else 0
			mode_t[i] = rng.randf_range(2.5, 6.0)
		else:
			moving[i] = 1
			crouch[i] = 0
			mode_t[i] = rng.randf_range(2.0, 5.0)
			var sq: Dictionary = squads[squad[i]] if squad[i] >= 0 and squad[i] < squads.size() else {}
			if not sq.is_empty():
				var obj: Vector3 = sq["objective"]
				var spread: float = sq["spread"]
				var g := obj + Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
				# Advance in bounds: never more than ~40 m per bound toward the objective.
				var d := g - p
				d.y = 0.0
				if d.length() > 45.0:
					g = p + d.normalized() * rng.randf_range(25.0, 45.0)
				if G.gen.water_at(g.x, g.z) > -100.0:
					g = p
				goal[i] = g


func _act(i: int, delta: float, player_p: Vector3) -> void:
	var p := pos[i]
	var t := target[i]
	var tp := Vector3.ZERO
	var has_t := t != -1
	if t >= 0:
		tp = pos[t]
	elif t == -2:
		tp = player_p
	if think_t[i] > 1e8:
		return
	if moving[i] == 1:
		var d := goal[i] - p
		d.y = 0.0
		var dist := d.length()
		if dist > 1.0:
			var run := dist > 18.0
			var speed := 4.2 if run else 1.5
			var step := d / dist * minf(speed * delta, dist)
			p += step
			# Round tree trunks; a goal next to a trunk counts as reached (it may lie inside it).
			var veg: Node = G.world.vegetation
			if veg:
				var q: Vector3 = veg.avoid(p, 0.35)
				if q != p and dist < 2.5:
					goal[i] = q
				p = q
			yaw[i] = lerp_angle(yaw[i], atan2(-d.x, -d.z), 1.0 - exp(-delta * 6.0))
			phase[i] += delta * (1.45 if run else 0.9)
			state[i] = S_RUN if run else S_WALK
			if (i + G.frame) % 3 == 0:
				p.y = G.world.ground_at(p.x, p.z)
			var oc := _cell(pos[i])
			pos[i] = p
			var nc := _cell(p)
			if nc != oc:
				_grid_remove(i, oc)
				_grid_add(i)
		else:
			state[i] = S_AIM if has_t else S_IDLE
	else:
		state[i] = (S_CROUCH if crouch[i] == 1 else S_AIM) if has_t else S_IDLE
	if has_t and moving[i] == 0:
		var to := tp - p
		yaw[i] = lerp_angle(yaw[i], atan2(-to.x, -to.z), 1.0 - exp(-delta * 8.0))
		var hd := Vector2(to.x, to.z).length()
		aim[i] = lerpf(aim[i], atan2(to.y, hd), 1.0 - exp(-delta * 5.0))
		fire_t[i] -= delta
		if fire_t[i] <= 0.0:
			_shoot(i, t, tp)


func _shoot(i: int, t: int, tp: Vector3) -> void:
	var rank := pal[i] % 4
	if burst[i] <= 0:
		burst[i] = rng.randi_range(3, 6) if rank != 3 else 1
		fire_t[i] = rng.randf_range(0.8, 2.2)
		return
	burst[i] -= 1
	fire_t[i] = 0.11 if rank != 3 else 4.0
	var p := pos[i]
	var eye := p + Vector3(0, 0.95 if crouch[i] == 1 else 1.45, 0)
	var dist := eye.distance_to(tp)
	var chance := clampf(0.42 * (1.0 - dist / 420.0), 0.03, 0.42)
	if t >= 0 and crouch[t] == 1:
		chance *= 0.55
	if t >= 0 and moving[t] == 1:
		chance *= 0.6
	var hit := rng.randf() < chance
	var aim_p := tp + Vector3(0, 1.1, 0)
	if not hit:
		aim_p += Vector3(rng.randf_range(-3, 3), rng.randf_range(-1.0, 2.5), rng.randf_range(-3, 3))
	if fx:
		var fwd := Basis(Vector3.UP, yaw[i]) * Vector3(0.18, 0.0, -0.75)
		var muzzle := eye + fwd + Vector3(0, -0.05, 0)
		if rank == 3:
			fx.rocket(muzzle, aim_p, fac[i])
		else:
			fx.shot(muzzle, aim_p, fac[i], hit)
	if hit:
		var dmg := rng.randf_range(22.0, 55.0) if rank != 3 else 120.0
		if t >= 0:
			hit_soldier(t, dmg, (tp - p).normalized())
		elif t == -2 and G.player and G.player.has_method("take_damage"):
			G.player.take_damage(dmg * 0.35, p)


func hit_soldier(i: int, dmg: float, dir: Vector3) -> void:
	if not alive(i):
		return
	hp[i] -= dmg
	if hp[i] <= 0.0:
		state[i] = S_DEAD
		dead_t[i] = 0.0
		kills[1 - fac[i]] += 1
		_grid_remove(i, _cell(pos[i]))
		# Fall away from the shot.
		yaw[i] = atan2(dir.x, dir.z) + rng.randf_range(-0.6, 0.6)
		if fx and fx.has_method("blood"):
			fx.blood(pos[i] + Vector3(0, 1.2, 0), dir)
	elif rng.randf() < 0.5:
		# Wounded soldiers go to ground.
		crouch[i] = 1
		moving[i] = 0
		mode_t[i] = 3.0


## The first living soldier hit by a ray (capsule test), within max_d. Returns [index, distance] or [].
func ray_hit(o: Vector3, dir: Vector3, max_d: float) -> Array:
	var best := -1
	var bt := max_d
	var steps := int(max_d / GRID) + 1
	var seen := {}
	for s in steps + 1:
		var p := o + dir * minf(s * GRID, max_d)
		var c := _cell(p)
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var cc := c + Vector2i(dx, dz)
				if seen.has(cc) or not grid.has(cc):
					continue
				seen[cc] = true
				for j in grid[cc]:
					if state[j] == S_DEAD:
						continue
					var h := 0.95 if crouch[j] == 1 and moving[j] == 0 else 1.75
					var t := _ray_capsule(o, dir, pos[j] + Vector3(0, 0.3, 0), pos[j] + Vector3(0, h - 0.25, 0), 0.32)
					if t >= 0.0 and t < bt:
						bt = t
						best = j
		if best >= 0 and bt < s * GRID - GRID:
			break
	return [best, bt] if best >= 0 else []


func _ray_capsule(o: Vector3, d: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	# Closest approach between the ray and the segment ab, then a sphere test at that point.
	var ab := b - a
	var ao := o - a
	var abab := ab.dot(ab)
	var abd := ab.dot(d)
	var aoab := ao.dot(ab)
	var aod := ao.dot(d)
	var denom := abab - abd * abd
	var t := 0.0
	if absf(denom) > 1e-6:
		t = (abd * aoab - abab * aod) / denom
	t = maxf(t, 0.0)
	var q := o + d * t
	var u := clampf((q - a).dot(ab) / abab, 0.0, 1.0)
	var c := a + ab * u
	var oc := o - c
	var bq := oc.dot(d)
	var cq := oc.dot(oc) - r * r
	var disc := bq * bq - cq
	if disc < 0.0:
		return -1.0
	var hit_t := -bq - sqrt(disc)
	return hit_t if hit_t >= 0.0 else -1.0


func _upload(cp: Vector3) -> void:
	var d2 := DRAW_DIST * DRAW_DIST
	var lists := [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	for i in n:
		var st := state[i]
		if st == 255 or pos[i].distance_squared_to(cp) > d2:
			continue
		var key: int = body[i] + 3 * fac[i]
		var l: PackedInt32Array = lists[key]
		l.append(i)
		lists[key] = l
	for b in 6:
		var idx: PackedInt32Array = lists[b]
		var buf: PackedFloat32Array = bufs[b]
		var k := 0
		for i in idx:
			var st := state[i]
			var o := k * 16
			k += 1
			var basis := Basis(Vector3.UP, yaw[i])
			var origin := pos[i]
			if st == S_DEAD:
				# Lie down: rotate about the facing axis and sink to the ground.
				var fall := clampf(dead_t[i] * 2.2, 0.0, 1.0)
				basis = basis * Basis(Vector3.RIGHT, -fall * PI * 0.48)
				origin.y += 0.12 * fall
			buf[o] = basis.x.x; buf[o + 1] = basis.y.x; buf[o + 2] = basis.z.x; buf[o + 3] = origin.x
			buf[o + 4] = basis.x.y; buf[o + 5] = basis.y.y; buf[o + 6] = basis.z.y; buf[o + 7] = origin.y
			buf[o + 8] = basis.x.z; buf[o + 9] = basis.y.z; buf[o + 10] = basis.z.z; buf[o + 11] = origin.z
			buf[o + 12] = phase[i]; buf[o + 13] = float(st); buf[o + 14] = float(pal[i]); buf[o + 15] = aim[i]
		bufs[b] = buf
		counts[b] = k
		mm[b].visible_instance_count = 0
		if k > 0:
			mm[b].buffer = buf
		mm[b].visible_instance_count = k


func count_alive(faction: int) -> int:
	var c := 0
	for i in n:
		if fac[i] == faction and state[i] != S_DEAD and state[i] != 255:
			c += 1
	return c
