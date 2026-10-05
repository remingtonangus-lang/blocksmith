extends Node
## Exhibition shooting, the way "Miss Ruthie, the Ozark Wonder" did it in the ring: glass balls tossed into the air
## in front of Ruth, one after another; shoot them with whatever gun she carries (Nerve helps). Each ball is a tiny
## Damageable with a hitbox, so the real gun code scores the hits. Returns {ok, hits, thrown}.
## opts: count (8), need (5), interval (1.6 s), distance (11 m), auto (bots: hits = need + 1).

var balls: Array = []
var hits := 0

func play(opts: Dictionary) -> Dictionary:
	var count := int(opts.get("count", 8))
	var need := int(opts.get("need", 5))
	if bool(opts.get("auto", false)) or Game.headless:
		hits = mini(need + 1, count)
		return {"ok": hits >= need, "hits": hits, "thrown": count, "auto": true}
	var interval := float(opts.get("interval", 1.6))
	var dist := float(opts.get("distance", 11.0))
	var p = Game.player
	var fwd := Vector3(-sin(p.facing), 0, -cos(p.facing))
	var side := fwd.cross(Vector3.UP)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 1880))
	if Game.hud:
		Game.hud.notice("Aim (right mouse / LT) and shoot the glass balls. Nerve (Q / R3) slows them.", 5.0)
	for i in count:
		var origin: Vector3 = p.global_position + fwd * dist + side * rng.randf_range(-4.0, 4.0)
		origin.y = Game.world.height(origin.x, origin.z) + 0.8
		var vel := Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(7.0, 9.5), rng.randf_range(-1.0, 1.0))
		_throw(origin, vel)
		if Game.hud:
			Game.hud.prompt("Glass balls: %d / %d hit" % [hits, i + 1])
		await get_tree().create_timer(interval).timeout
	await get_tree().create_timer(2.0).timeout
	for b in balls:
		if is_instance_valid(b):
			b.queue_free()
	return {"ok": hits >= need, "hits": hits, "thrown": count}

func _throw(origin: Vector3, vel: Vector3) -> void:
	var b := Node3D.new()
	b.name = "GlassBall"
	Game.main.add_child(b)
	b.global_position = origin
	var dmg := Damageable.new()
	dmg.max_health = 1.0
	b.add_child(dmg)
	var sh := SphereShape3D.new()
	sh.radius = 0.22
	Damageable.make_hitbox(b, dmg, "chest", sh)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.8, 0.75, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.3
	mat.roughness = 0.1
	mi.material_override = mat
	b.add_child(mi)
	balls.append(b)
	dmg.died.connect(func(_info):
		hits += 1
		Game.log_event("glass_ball", {"hits": hits})
		if Game.audio and Game.audio.has_method("play"):
			Game.audio.play("glass", b.global_position)
		b.queue_free())
	var t := 0.0
	var v := vel
	while is_instance_valid(b) and t < 3.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		v.y -= 9.81 * dt
		b.global_position += v * dt
		if b.global_position.y < Game.world.height(b.global_position.x, b.global_position.z):
			break
	if is_instance_valid(b):
		b.queue_free()
