extends RefCounted
## Cover oracle (headless, real physics): Ruth tucks behind a waist-high wall and a 2.4 m wall built above the map.
## Checks: enter low cover; slide along it and stop at its end; a shooter on the far side cannot see her head while
## crouched but can once she pops up to aim; blind fire spends a round from above the wall; pushing away leaves;
## high cover is recognised and aiming at its end peeks out around it.

static var tree: SceneTree

static func run(runner: Node) -> Dictionary:
	var res := {"bot": "cover", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "checks": {}}
	tree = runner.get_tree()
	var p = Game.player
	var o := Vector3(400.0, 3000.0, 400.0)
	var parts: Array = []
	parts.append(_box(o + Vector3(0, -0.25, 0), Vector3(30, 0.5, 30)))                 # floor
	parts.append(_box(o + Vector3(0, 0.475, -1.0), Vector3(3.0, 0.95, 0.4)))           # low wall (0.95 m), face at z = o.z - 0.8
	parts.append(_box(o + Vector3(10.0, 1.2, -1.0), Vector3(2.0, 2.4, 0.4)))           # high wall
	await _frames(3)
	var was_bot: bool = p.bot_driven
	p.bot_driven = true
	p.global_position = o + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	p.cam_yaw = 0.0                     # looking toward -z, at the wall
	p.facing = 0.0
	_clear(p)
	await _physics(20)
	# 1. enter low cover
	p.intent.cover = true
	await _physics(10)
	if not p.cover.active or not p.cover.low:
		_fail(res, "did not enter low cover (active %s low %s)" % [p.cover.active, p.cover.low])
		return await _cleanup(res, parts, p, was_bot)
	var gap: float = p.global_position.z - (o.z - 0.8)
	res.checks["gap_m"] = snappedf(gap, 0.01)
	if absf(gap - PlayerCover.GAP) > 0.12:
		_fail(res, "gap to the cover face %.2f m (want %.2f)" % [gap, PlayerCover.GAP])
	# 2. hidden: shooter on the far side aims at the head hitbox
	await _physics(30)
	var shooter := o + Vector3(0.0, 1.3, -12.0)
	var head_hidden := not _head_visible(p, shooter)
	res.checks["hidden_crouched"] = head_hidden
	if not head_hidden:
		_fail(res, "head visible over low cover while crouched")
	# 3. slide right: moves along the wall and stops at its end
	var x0: float = p.global_position.x
	p.intent.move = Vector2(1.0, 0.0)
	await _physics(150)
	p.intent.move = Vector2.ZERO
	await _physics(5)
	var dx: float = p.global_position.x - x0
	res.checks["slid_m"] = snappedf(dx, 0.01)
	if dx < 0.6:
		_fail(res, "slide along cover only %.2f m" % dx)
	if p.global_position.x > o.x + 1.5 + 0.2 or not p.cover.active:
		_fail(res, "slid past the end of the cover (x %.2f, active %s)" % [p.global_position.x - o.x, p.cover.active])
	# 4. pop up to aim: exposed
	p.intent.aim = true
	await _physics(30)
	var exposed := _head_visible(p, shooter)
	res.checks["exposed_aiming"] = exposed
	if not exposed:
		_fail(res, "aiming over low cover did not expose the head")
	p.intent.aim = false
	await _physics(30)
	# 5. blind fire
	p.gun.drawn = true
	p.gun.cooldown = 0.0
	var id: String = p.gun.weapon_id()
	var before: int = p.gun.clip.get(id, 0)
	p.intent.fire = true
	await _physics(2)
	p.intent.fire = false
	await _physics(2)
	var spent: int = before - int(p.gun.clip.get(id, 0))
	res.checks["blind_fire_rounds"] = spent
	if spent != 1:
		_fail(res, "blind fire spent %d rounds" % spent)
	# 6. push away -> out of cover
	p.intent.move = Vector2(0.0, -1.0)
	await _physics(30)
	p.intent.move = Vector2.ZERO
	res.checks["left_cover"] = not p.cover.active
	if p.cover.active:
		_fail(res, "pushing away did not leave cover")
	# 7. high cover + peek at the edge
	p.global_position = o + Vector3(10.6, 0.05, 0.0)
	p.velocity = Vector3.ZERO
	await _physics(20)
	p.intent.cover = true
	await _physics(10)
	if not p.cover.active or p.cover.low:
		_fail(res, "did not enter high cover (active %s low %s)" % [p.cover.active, p.cover.low])
	else:
		var px: float = p.global_position.x
		p.intent.aim = true
		await _physics(40)
		var peek: float = p.global_position.x - px
		res.checks["peek_m"] = snappedf(peek, 0.01)
		res.checks["edge"] = p.cover.edge
		if p.cover.edge != 1 or peek < 0.3:
			_fail(res, "no peek around the high cover's end (edge %d, moved %.2f m)" % [p.cover.edge, peek])
		p.intent.aim = false
	print("  cover: %s" % str(res.checks))
	return await _cleanup(res, parts, p, was_bot)

static func _clear(p) -> void:
	p.intent.move = Vector2.ZERO
	for k in ["aim", "fire", "cover", "sprint", "crouch", "jump"]:
		p.intent[k] = false

static func _cleanup(res: Dictionary, parts: Array, p, was_bot := false) -> Dictionary:
	_clear(p)
	if p.cover.active:
		p.cover.leave()
	p.bot_driven = was_bot
	for n in parts:
		n.queue_free()
	await _frames(2)
	return res

static func _head_visible(p, from: Vector3) -> bool:
	var head: Vector3 = p.global_position
	for h in p._hitboxes:
		if h[0].get_parent().get_meta("zone", "") == "head":
			head = h[0].global_position
	var q := PhysicsRayQueryParameters3D.create(from, head, 1)
	q.exclude = [p.get_rid()]
	return p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

static func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	Game.main.add_child(b)
	b.global_position = pos
	return b

static func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)
	print("  cover FAIL: " + why)

static func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame

static func _physics(n: int) -> void:
	for i in n:
		await tree.physics_frame
