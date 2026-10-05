extends RefCounted
## Foot IK oracle (headless): Ruth's model stands on a 15 degree plank tilted across her stance. Without IK the
## uphill ankle buries and the downhill one floats; with HumanFootIK both ankles must sit at the same height above
## the ground under them, close to the flat-ground ankle height.

static func run(runner: Node) -> Dictionary:
	var res := {"bot": "footik", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "checks": {}}
	if not CharacterFactory.available():
		print("  footik: SKIP (no character assets)")
		return res
	var tree := runner.get_tree()
	var origin := Vector3(0, 3000.0, 0)     # high above the map: nothing else under the feet
	var plank := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 0.4, 6)
	cs.shape = box
	plank.add_child(cs)
	Game.main.add_child(plank)
	var results := {}
	for mode in ["flat", "off", "ik"]:
		plank.global_transform = Transform3D(Basis(Vector3.FORWARD, 0.0 if mode == "flat" else deg_to_rad(15.0)), origin - Vector3(0, 0.2, 0))
		var body := CharacterBody3D.new()
		var cap := CollisionShape3D.new()
		var cc := CapsuleShape3D.new()
		cc.radius = 0.25
		cc.height = 1.7
		cap.shape = cc
		cap.position.y = 0.85
		body.add_child(cap)
		Game.main.add_child(body)
		body.global_position = origin + Vector3(0, 0.3, 0)
		var vis := CharacterFactory.spawn_id("ruth_caddell")
		body.add_child(vis)
		body.set("visual", vis) if "visual" in body else body.set_meta("visual", vis)
		var ik: HumanFootIK = null
		for i in 240:
			body.velocity = Vector3(0, -2.0, 0)
			body.move_and_slide()
			if i == 20 and mode == "ik":
				ik = HumanFootIK.new()
				ik.name = "FootIK"
				vis.skeleton.add_child(ik)
				vis.skeleton.move_child(ik, 0)
				ik.use_cam_range = false
				ik.setup(body)
			await tree.physics_frame
		var sk: Skeleton3D = vis.skeleton
		var hs: Array = [0.0, 0.0]
		# sample the final pose right after the modifier stack ran (outside it the animation pose is back)
		var sampler := HumanFootIK.new()   # a no-op modifier last in the stack, only to get its signal
		sampler.name = "Sampler"
		sampler.active = true
		sk.add_child(sampler)
		var got := [false]
		sampler.modification_processed.connect(func():
			for j in 2:
				var f: String = ["LeftFoot", "RightFoot"][j]
				var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(f)).origin
				var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p - Vector3(0, 2.0, 0), 1)
				q.exclude = [body.get_rid()]
				var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
				hs[j] = p.y - (hit.position.y if not hit.is_empty() else p.y)
			got[0] = true)
		for i in 4:
			await tree.process_frame
		results[mode] = hs
		print("  footik %s: ankle above ground L %.3f R %.3f%s" % [mode, hs[0], hs[1], ("  (ik solves %d, weight %.2f)" % [ik.calls, ik._w]) if ik else ""])
		body.queue_free()
		await tree.physics_frame
	plank.queue_free()
	var flat: float = (results.flat[0] + results.flat[1]) * 0.5
	var off_err: float = absf(results.off[0] - results.off[1])
	var ik_err: float = absf(results.ik[0] - results.ik[1])
	res.checks["ankle_diff_cm"] = {"off": snappedf(off_err * 100.0, 0.1), "ik": snappedf(ik_err * 100.0, 0.1)}
	if ik_err > 0.035:
		res.ok = false
		res.failures.append("feet uneven on the slope with IK: %.1f cm (without: %.1f cm)" % [ik_err * 100.0, off_err * 100.0])
	for h in results.ik:
		if absf(h - flat) > 0.06:
			res.ok = false
			res.failures.append("ankle %.3f m above the slope vs %.3f on flat ground" % [h, flat])
	return res
