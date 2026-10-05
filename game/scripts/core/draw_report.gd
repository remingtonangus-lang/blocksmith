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


var _abl: Array = []               # [key, nodes] still to measure
var _abl_i := -1
var _abl_wait := 0
var _base := 0
var measured: Array = []           # [key, draws saved when hidden]


func _draws() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)


func _process(_delta: float) -> void:
	if _abl_i >= 0:
		_ablate()
		return
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
	print("drawreport %s: ~%d main draws, ~%d shadow draws (scene-walk estimate)" % [seg["name"], tm, ts])
	for r in rows.slice(0, 30):
		print("  %-46s main %4d  shadow %4d  (%d nodes)" % r)
	_rows = rows
	var veg: Node = G.world.vegetation
	if veg:
		var kinds := {}
		for c in veg.get_children():
			var nm: String = c.get_class()
			var surf := 0
			var kids := 1
			if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh and (c as MultiMeshInstance3D).multimesh.mesh:
				surf = (c as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
			elif c.get_child_count() > 0:
				nm = "Node3D(super)"
				kids = c.get_child_count()
				for cc in c.get_children():
					if cc is MultiMeshInstance3D and (cc as MultiMeshInstance3D).multimesh.mesh:
						surf += (cc as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
			if not kinds.has(nm):
				kinds[nm] = [0, 0, 0]
			kinds[nm][0] += 1
			kinds[nm][1] += kids
			kinds[nm][2] += surf
		print("vegetation children: %s (count, instances, surfaces)" % kinds)
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	# Ablation with the real renderer: hide one owner group at a time and read the frame's draw calls.
	var by_key := {}
	_collect(G.world, by_key)
	for k in by_key:
		_abl.append([k, by_key[k]])
	_abl_i = -1
	_abl_wait = 4
	_abl_i = 0
	_base = -1


var _rows: Array = []


func _collect(n: Node, out: Dictionary) -> void:
	if n is Node3D and n != G.world and n.get_parent() != null:
		var key := _owner_key(n)
		var depth := String(G.world.get_path_to(n)).count("/")
		if depth <= 1:
			if not out.has(key):
				out[key] = []
			(out[key] as Array).append(n)
			if depth == 1:
				return
	for c in n.get_children():
		_collect(c, out)


func _ablate() -> void:
	_abl_wait -= 1
	if _abl_wait > 0:
		return
	if _base < 0:
		_base = _draws()
		print("drawreport %s: base %d draws, %.2f M primitives" % [seg["name"], _base,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1e6])
		if OS.get_environment("DRAWREPORT_QUICK") == "1":
			get_tree().quit(0)
			return
		_abl_wait = 4
		_hide(0, true)
		return
	var d := _draws()
	measured.append([_abl[_abl_i][0], _base - d])
	_hide(_abl_i, false)
	_abl_i += 1
	if _abl_i >= _abl.size():
		_abl_i = -1
		_finish()
		return
	_hide(_abl_i, true)
	_abl_wait = 4


func _hide(i: int, h: bool) -> void:
	for n in _abl[i][1]:
		if is_instance_valid(n):
			(n as Node3D).visible = not h


func _finish() -> void:
	measured.sort_custom(func(a, b): return a[1] > b[1])
	if not measured.is_empty():
		print("drawreport %s: %d draw calls measured; saved when each group is hidden:" % [seg["name"], _base])
		for m in measured.slice(0, 30):
			print("  %-46s %5d" % m)
	G.write_json(G.log_dir() + "/drawreport_%s.json" % seg["name"], {"segment": seg["name"], "measured_total": _base,
		"ablation": measured.map(func(m): return {"owner": m[0], "draws": m[1]}),
		"estimate": _rows.map(func(r): return {"owner": r[0], "main": r[1], "shadow": r[2], "nodes": r[3]})})
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
