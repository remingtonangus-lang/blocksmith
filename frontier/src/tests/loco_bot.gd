extends RefCounted
## Locomotion accents oracle (headless): on a real character model, turning on the spot plays turn_in_place_L/R in
## the right direction, a run brought to a halt plays run_stop, a brisk walk stopping plays walk_stop; walking
## steadily plays nothing.

static func run(runner: Node) -> Dictionary:
	var res := {"bot": "loco", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "checks": {}}
	if not CharacterFactory.available():
		print("  loco: SKIP (no character assets)")
		return res
	var tree := runner.get_tree()
	var vis := CharacterFactory.spawn_id("ruth_caddell")
	Game.main.add_child(vis)
	vis.global_position = Vector3(0, 3800.0, 0)
	for i in 30:
		await tree.process_frame
	var dt := 1.0 / 60.0
	var la := LocoAccents.new()
	var yaw := 0.0
	# steady walk: nothing
	for i in 60:
		la.tick(vis, yaw, 1.5, dt)
	var steady := la.played.duplicate()
	# turn left on the spot (yaw increasing)
	for i in 40:
		yaw += 2.2 * dt
		la.tick(vis, yaw, 0.0, dt)
	for i in 90:
		la.tick(vis, yaw, 0.0, dt)
	# turn right
	for i in 40:
		yaw -= 2.2 * dt
		la.tick(vis, yaw, 0.0, dt)
	for i in 90:
		la.tick(vis, yaw, 0.0, dt)
	# run, then stop
	for i in 30:
		la.tick(vis, yaw, 5.5, dt)
	for i in 28:                                  # ~12 m/s^2, the player's deceleration
		la.tick(vis, yaw, maxf(5.5 - (i + 1) * 0.2, 0.0), dt)
	for i in 90:
		la.tick(vis, yaw, 0.0, dt)
	# brisk walk, then stop
	for i in 30:
		la.tick(vis, yaw, 2.6, dt)
	for i in 14:
		la.tick(vis, yaw, maxf(2.6 - (i + 1) * 0.2, 0.0), dt)
	res.checks = {"steady": steady.size(), "played": la.played}
	if not steady.is_empty():
		_fail(res, "a steady walk played accents: %s" % str(steady))
	for c in ["turn_in_place_L", "turn_in_place_R", "run_stop", "walk_stop"]:
		if int(la.played.get(c, 0)) < 1:
			_fail(res, "%s never played (%s)" % [c, str(la.played)])
	vis.queue_free()
	await tree.process_frame
	print("  loco: %s" % str(res.checks))
	return res

static func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)
	print("  loco FAIL: " + why)
