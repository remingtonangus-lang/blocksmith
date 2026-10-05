extends Node
## --drawreport SEGMENT: stands at the start of a benchmark segment (city, battle, forest), waits for streaming,
## then estimates the draw calls by walking the scene: every visible geometry instance in the view frustum and
## inside its visibility range costs one draw per surface in the main pass, plus one per shadow cascade it falls
## in when it casts shadows. Groups the result by owner (the node under World) and writes drawreport.json, so
## draw-call work starts from a measured list instead of guesses. Headless is fine.

var seg: Dictionary = {}
var cam: Camera3D
var wait := 0
var groups := {}                   # owner -> {main, shadow, nodes}


func start(segment: Dictionary) -> void:
	seg = segment
	cam = Camera3D.new()
	cam.fov = Settings.fov
	cam.far = 160000.0
	G.main.add_child(cam)
	cam.make_current()
	G.cam = cam
	var path: Array = seg["path"]
	var look: Array = seg["look"]
	cam.global_position = path[0]
	cam.look_at(look[0], Vector3.UP)
	if seg.has("setup"):
		(seg["setup"] as Callable).call()
	G.world.focus(cam.global_position)
	wait = 120


func _process(_delta: float) -> void:
	if wait <= 0:
		return
	if not G.world.is_settled() and wait > 2:
		return
	wait -= 1
	if wait > 0:
		return
	var planes := cam.get_frustum()
	var cp := cam.global_position
	var shadow_far: float = float(Settings.q["shadow_dist"])
	_walk(G.world, planes, cp, shadow_far)
	var rows: Array = []
	var tm := 0
	var ts := 0
	for k in groups:
		var g: Dictionary = groups[k]
		rows.append([k, g["main"], g["shadow"], g["nodes"]])
		tm += g["main"]
		ts += g["shadow"]
	rows.sort_custom(func(a, b): return a[1] + a[2] > b[1] + b[2])
	print("drawreport %s: ~%d main draws, ~%d shadow draws (estimate)" % [seg["name"], tm, ts])
	for r in rows.slice(0, 30):
		print("  %-46s main %4d  shadow %4d  (%d nodes)" % r)
	G.write_json(G.log_dir() + "/drawreport.json", {"segment": seg["name"], "main": tm, "shadow": ts,
		"groups": rows.map(func(r): return {"owner": r[0], "main": r[1], "shadow": r[2], "nodes": r[3]})})
	get_tree().quit(0)


func _owner_key(n: Node) -> String:
	# The path below World, two levels deep (World/Vehicles/Convoy_WesternHighway), with numbered names folded.
	var parts: PackedStringArray = String(G.world.get_path_to(n)).split("/")
	var key := "/".join(parts.slice(0, mini(2, parts.size() - 1)))
	var re := RegEx.create_from_string("[0-9]+")
	return re.sub(key, "#", true)


func _walk(n: Node, planes: Array[Plane], cp: Vector3, shadow_far: float) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	if n is GeometryInstance3D:
		_count(n as GeometryInstance3D, planes, cp, shadow_far)
	for c in n.get_children():
		_walk(c, planes, cp, shadow_far)


func _count(gi: GeometryInstance3D, planes: Array[Plane], cp: Vector3, shadow_far: float) -> void:
	var surfaces := 0
	if gi is MeshInstance3D:
		var m := (gi as MeshInstance3D).mesh
		surfaces = m.get_surface_count() if m else 0
	elif gi is MultiMeshInstance3D:
		var mm := (gi as MultiMeshInstance3D).multimesh
		if mm and mm.mesh and (mm.visible_instance_count != 0) and mm.instance_count > 0:
			surfaces = mm.mesh.get_surface_count()
	elif gi is GPUParticles3D:
		surfaces = 1 if (gi as GPUParticles3D).draw_pass_1 else 0
	if surfaces == 0:
		return
	var aabb := gi.global_transform * gi.get_aabb()
	if gi.custom_aabb.size != Vector3.ZERO:
		aabb = gi.global_transform * gi.custom_aabb
	var center := aabb.get_center()
	var d := cp.distance_to(center)
	if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end + gi.visibility_range_end_margin:
		return
	if gi.visibility_range_begin > 0.0 and d < gi.visibility_range_begin - gi.visibility_range_begin_margin:
		return
	var in_view := _aabb_in(aabb, planes)
	var casts := gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var near_shadow := casts and (d - aabb.size.length() * 0.5) < shadow_far
	if not in_view and not near_shadow:
		return
	var key := _owner_key(gi)
	if not groups.has(key):
		groups[key] = {"main": 0, "shadow": 0, "nodes": 0}
	var g: Dictionary = groups[key]
	g["nodes"] += 1
	if in_view and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		g["main"] += surfaces
	if near_shadow:
		# Four cascades split the shadow distance; a big object spans several.
		var span := clampi(int(ceil(aabb.size.length() / (shadow_far * 0.25))) + 1, 1, 4)
		g["shadow"] += surfaces * span


func _aabb_in(b: AABB, planes: Array[Plane]) -> bool:
	for p in planes:
		# The corner furthest along the plane normal; if it is outside, the box is outside.
		var v := Vector3(b.end.x if p.normal.x < 0.0 else b.position.x,
			b.end.y if p.normal.y < 0.0 else b.position.y,
			b.end.z if p.normal.z < 0.0 else b.position.z)
		if p.is_point_over(v):
			return false
	return true
