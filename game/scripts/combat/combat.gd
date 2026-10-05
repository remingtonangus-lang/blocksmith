class_name Combat
extends Node3D
## Projectiles and damage. Bullets: fast rounds stepped each physics frame (ray against the world, capsule test
## against soldiers), drawn as tracers, with impacts and hit markers. Shells and cannon rounds: ballistic
## (gravity, drag-free), exploding on contact with the ground, buildings or vehicles; splash damage hits soldiers,
## vehicles and destructible buildings. Vehicles that run out of health burn and break apart (Destruction).

var bullets: Array = []          # [pos, vel, damage, faction, exclude, tracer, life, from_player]
var shells: Array = []           # [pos, vel, power, faction, exclude, life]
var destruction: Node = null


func setup() -> void:
	G.combat = self


func bullet(o: Vector3, dir: Vector3, speed: float, dmg: float, faction: int, exclude: Array, tracer: bool, from_player: bool = false) -> void:
	bullets.append([o, dir * speed, dmg, faction, exclude, tracer, 2.5, from_player])
	if G.fx:
		G.fx.flash(o, 0.4)
		if tracer:
			G.fx.tracer(o, o + dir * minf(speed * 1.2, 900.0), faction)
	if Sfx.has_method("gunshot"):
		Sfx.gunshot(o, faction)


func cannon_round(o: Vector3, dir: Vector3, speed: float, faction: int, exclude: Array) -> void:
	shells.append([o, dir * speed, 0.35, faction, exclude, 6.0])
	if G.fx:
		G.fx.flash(o, 1.4)
		G.fx.tracer(o, o + dir * 600.0, faction)
	if Sfx.has_method("cannon"):
		Sfx.cannon(o, 0.35)


func shell(o: Vector3, dir: Vector3, speed: float, power: float, faction: int, exclude: Array) -> void:
	shells.append([o, dir * speed, power, faction, exclude, 60.0])
	if G.fx:
		G.fx.flash(o, 2.0 + power * 2.0)
	if Sfx.has_method("cannon"):
		Sfx.cannon(o, power)


func _physics_process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var keep := []
	for b in bullets:
		var p: Vector3 = b[0]
		var v: Vector3 = b[1]
		var np := p + v * delta
		v.y -= 9.81 * delta
		b[6] -= delta
		var hit := _trace(space, p, np, b[4])
		var seg := np - p
		if not b[7] and G.cam and is_instance_valid(G.cam):
			var c := G.cam.global_position
			var tt := clampf((c - p).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
			if (p + seg * tt).distance_to(c) < 3.0:
				Sfx.play_at("whizz", p + seg * tt, -4.0)
		var len := seg.length()
		# Soldiers along the segment.
		if G.battle and G.battle.army and len > 0.0:
			var sh: Array = G.battle.army.ray_hit(p, seg / len, len if hit.is_empty() else p.distance_to(hit["position"]))
			if not sh.is_empty() and G.battle.army.fac[sh[0]] != b[3]:
				G.battle.army.hit_soldier(sh[0], b[2], seg / len)
				if b[7] and G.hud:
					G.hud.hit_marker()
				continue
		if not hit.is_empty():
			_impact(hit, b[2], seg.normalized(), 0.0, b[7])
			continue
		if b[6] <= 0.0 or np.y < -50.0:
			continue
		b[0] = np
		b[1] = v
		keep.append(b)
	bullets = keep
	var keep_s := []
	for s in shells:
		var p: Vector3 = s[0]
		var v: Vector3 = s[1]
		v.y -= 9.81 * delta
		var np := p + v * delta
		s[5] -= delta
		var hit := _trace(space, p, np, s[4])
		if not hit.is_empty():
			_explode(hit["position"], s[2], hit)
			continue
		if s[5] <= 0.0:
			continue
		s[0] = np
		s[1] = v
		keep_s.append(s)
	shells = keep_s


## Ray against physics bodies, then against the terrain height (beyond the collision window) and the sea.
func _trace(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, exclude: Array) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = exclude
	q.collision_mask = 1 | 2 | 4
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return hit
	var g := G.world.ground_at(b.x, b.z) if G.world else -1e9
	if b.y < g:
		return {"position": Vector3(b.x, g, b.z), "normal": Vector3.UP, "collider": null}
	if b.y < 0.0 and G.gen and G.gen.water_at(b.x, b.z) > -100.0:
		return {"position": Vector3(b.x, 0.0, b.z), "normal": Vector3.UP, "collider": null, "water": true}
	return {}


func _impact(hit: Dictionary, dmg: float, dir: Vector3, _power: float, from_player: bool) -> void:
	var col: Object = hit.get("collider")
	var metal := false
	if col and col.has_method("damage"):
		col.damage(dmg, hit["position"])
		metal = true
		if from_player and G.hud:
			G.hud.hit_marker()
	elif col and G.player and col == G.player:
		G.player.take_damage(dmg, hit["position"] - dir * 5.0)
	if G.fx:
		if hit.has("water"):
			G.fx._emit(G.fx.dust, hit["position"], Vector3(0, 3, 0), Color(0.9, 0.95, 1.0, 0.7))
		else:
			G.fx.impact(hit["position"], hit["normal"], metal)


func _explode(at: Vector3, power: float, hit: Dictionary) -> void:
	explode(at, power, hit)


## Every explosion in the game: visuals, then blast damage to soldiers, the player, vehicles and buildings.
func explode(at: Vector3, power: float, hit: Dictionary = {}) -> void:
	if G.fx:
		if hit.has("water"):
			for k in 20:
				G.fx._emit(G.fx.dust, at, Vector3(randf_range(-3, 3), randf_range(8, 22), randf_range(-3, 3)) * sqrt(power), Color(0.9, 0.95, 1.0, 0.85))
			if Sfx.has_method("explosion"):
				Sfx.explosion(at, power * 0.6)
		else:
			G.fx.explosion(at, power)
	var col: Object = hit.get("collider")
	if col and col.has_method("damage"):
		col.damage(400.0 * power, at)
	# Splash damage to vehicles and destructible structures nearby.
	var r := 8.0 * power
	for v in get_tree().get_nodes_in_group("vehicles"):
		var n := v as Node3D
		if n and n != col and n.global_position.distance_to(at) < r * 1.5 and n.has_method("damage"):
			n.damage(250.0 * power * (1.0 - n.global_position.distance_to(at) / (r * 1.5)), at)
	if destruction and destruction.has_method("blast"):
		destruction.blast(at, power)
	if G.battle and G.battle.army:
		var army: Army = G.battle.army
		var rs := 9.0 * power
		var c := army._cell(at)
		var k := int(ceil(rs / Army.GRID))
		for dz in range(-k, k + 1):
			for dx in range(-k, k + 1):
				var cc := c + Vector2i(dx, dz)
				if not army.grid.has(cc):
					continue
				var ids: PackedInt32Array = army.grid[cc]
				for j in ids:
					var d := army.pos[j].distance_to(at)
					if d < rs:
						army.hit_soldier(j, 220.0 * (1.0 - d / rs), (army.pos[j] - at).normalized())
	if G.player and is_instance_valid(G.player) and G.player.vehicle == null:
		var d: float = G.player.global_position.distance_to(at)
		if d < 9.0 * power:
			G.player.take_damage(140.0 * (1.0 - d / (9.0 * power)), at)


## A vehicle dies: a big blast, burning wreckage, and the hull breaks into pieces (Destruction).
func destroy_vehicle(v: Node3D) -> void:
	if v.has_meta("destroyed"):
		return
	v.set_meta("destroyed", true)
	var at := v.global_position
	if G.fx:
		G.fx.explosion(at + Vector3(0, 1.5, 0), 2.2)
	if destruction and destruction.has_method("break_vehicle"):
		destruction.break_vehicle(v)
	else:
		v.queue_free()
