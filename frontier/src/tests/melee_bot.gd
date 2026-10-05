extends RefCounted
## Fistfight oracle (headless, real physics): Ruth punches a brave townsman on a plank above the map.
## Checks: the first blow lands and he squares up (brain FIST); his blows reach Ruth; her guard soaks most of a blow
## from the front; she knocks him down without killing him; he gets up again and the fight is over.

static var tree: SceneTree

static func run(runner: Node) -> Dictionary:
	var res := {"bot": "melee", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "checks": {}}
	tree = runner.get_tree()
	var p = Game.player
	var o := Vector3(-400.0, 3000.0, 400.0)
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(30, 0.5, 30)
	cs.shape = sh
	floor.add_child(cs)
	Game.main.add_child(floor)
	floor.global_position = o + Vector3(0, -0.25, 0)
	var was_bot: bool = p.bot_driven
	p.bot_driven = true
	p.global_position = o + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	p.facing = 0.0
	p.cam_yaw = 0.0
	p.gun.drawn = false
	p.damageable.health = p.damageable.max_health
	var h := Human.spawn(Game.main, o + Vector3(0, 0.1, -1.1), {"seed": 515, "faction": "civilian", "name": "Brawler"})
	h.brain.bravery = 0.95
	h.brain.skill = 0.5
	h.facing = PI
	await _physics(20)
	# 1. first punch lands, he squares up
	p.intent.melee = true
	await _physics(4)
	var hp0: float = h.damageable.health
	res.checks["first_blow_hp"] = snappedf(hp0, 0.1)
	if hp0 >= h.damageable.max_health:
		_fail(res, "first punch did not land")
	if h.brain.state != h.brain.State.FIST:
		_fail(res, "punched townsman did not square up (state %s)" % h.brain.State.keys()[h.brain.state])
	# 2. he hits back within a few seconds; guard up soaks it
	var ph0: float = p.damageable.health
	await _physics(240)
	var taken_open: float = ph0 - p.damageable.health
	res.checks["taken_open"] = snappedf(taken_open, 0.1)
	if taken_open <= 0.0:
		_fail(res, "he never landed a blow in 4 s")
	p.damageable.health = p.damageable.max_health
	p.intent.aim = true                       # guard (no gun drawn)
	var ph1: float = p.damageable.health
	await _physics(240)
	p.intent.aim = false
	var taken_guard: float = ph1 - p.damageable.health
	res.checks["taken_guard"] = snappedf(taken_guard, 0.1)
	if taken_open > 0.0 and taken_guard > taken_open * 0.5:
		_fail(res, "the guard did not soak his blows (%.1f vs %.1f open)" % [taken_guard, taken_open])
	# 3. knock him down (not dead)
	p.damageable.health = p.damageable.max_health
	var ko := false
	for i in 40:
		if Melee.is_down(h):
			ko = true
			break
		p.intent.melee = true
		var to: Vector3 = h.global_position - p.global_position
		p.facing = atan2(-to.x, -to.z)
		await _physics(35)
	res.checks["knocked_down"] = ko
	res.checks["alive"] = h.damageable.alive
	if not ko:
		_fail(res, "could not knock him down (hp %.1f)" % h.damageable.health)
	if not h.damageable.alive:
		_fail(res, "a fistfight killed him")
	# 4. gets up, fight over
	await _physics(60 * 7)
	res.checks["got_up"] = not Melee.is_down(h)
	res.checks["state_after"] = h.brain.State.keys()[h.brain.state]
	if Melee.is_down(h):
		_fail(res, "still down after 7 s")
	if h.brain.state == h.brain.State.FIST:
		_fail(res, "still fighting after the knockdown")
	print("  melee: %s" % str(res.checks))
	p.bot_driven = was_bot
	p.intent.aim = false
	for m in ["in_fight", "blocking", "melee_t", "stagger_t", "knocked_down"]:
		if p.has_meta(m):
			p.remove_meta(m)
	h.queue_free()
	floor.queue_free()
	await _physics(2)
	return res

static func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)
	print("  melee FAIL: " + why)

static func _physics(n: int) -> void:
	for i in n:
		await tree.physics_frame
