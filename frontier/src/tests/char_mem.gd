extends RefCounted
## CharacterFactory memory report (--charmem, run inside res://scenes/character_shots.tscn):
##   godot [--headless] --path frontier res://scenes/character_shots.tscn -- --charmem [--ids a,b] [--instances 10]
##        [--out DIR]
## For every look: process RSS / Godot static memory / video memory deltas of loading the look and showing one
## instance, plus the analytic texture and mesh bytes of the look's resources (blend shapes counted separately). Then
## `instances` more copies of the first look give the per-instance cost. Prints a table and writes charmem.json.
## Headless runs measure CPU only (no GPU uploads); windowed runs on software Vulkan count "GPU" memory in RSS too.

var host: Node3D
var _seen_tex := {}      # textures already counted (shared fabric maps count once, on the first look)


func run(h: Node3D) -> Dictionary:
	host = h
	var ids: PackedStringArray
	if Game.args.has("ids"):
		ids = str(Game.args["ids"]).split(",")
	else:
		ids = _default_ids()
	# warm-up (not measured): one look outside the list compiles the shader pipelines, and every fabric is loaded,
	# so the per-look deltas below are the look's own textures and meshes
	for c in CharacterFactory.catalog().get("characters", []):
		var wid := str(c["id"])
		if not ids.has(wid):
			var w: FrontierCharacter = CharacterFactory.spawn_id(wid)
			if w:
				host.add_child(w)
				w.position = Vector3(-6, 0, -6)
				w.play("walk", 0.0)
				for f in ["canvas", "denim", "leather", "linen", "wool"]:
					CharacterFactory._materials._fabric(f)
				for t in CharacterFactory._materials._fabric_cache.values():
					for tex in t.values():
						_seen_tex[tex] = true
			break
	await _settle(8)
	# spawn cost: a look not built yet (cold), then the same look again (warm: scene cached), each incl. its first frame
	var cold_id := ""
	for c in CharacterFactory.catalog().get("characters", []):
		if not ids.has(str(c["id"])) and not CharacterFactory._is_ready(str(c["id"])):
			cold_id = str(c["id"])
			break
	var spawn_report := {}
	for pass_name in ["cold", "warm", "warm2"]:
		if cold_id == "":
			break
		var ts := Time.get_ticks_usec()
		var sc: FrontierCharacter = CharacterFactory.spawn_id(cold_id, {"variant_seed": 7})
		var phases: Dictionary = CharacterFactory.last_spawn_ms.duplicate()
		var ta := Time.get_ticks_usec()
		host.add_child(sc)
		sc.position = Vector3(-8, 0, -6)
		sc.play("idle", 0.0)
		var tb := Time.get_ticks_usec()
		await host.get_tree().process_frame
		var tc := Time.get_ticks_usec()
		phases["add_child"] = (tb - ta) / 1000.0
		phases["first_frame"] = (tc - tb) / 1000.0
		phases["spawn_call"] = (ta - ts) / 1000.0
		spawn_report[pass_name] = phases
		print("charmem spawn %-5s %s: %s" % [pass_name, cold_id, JSON.stringify(phases)])
	await _settle(4)
	var base := _sample()
	var looks := []
	var x := 0.0
	for id in ids:
		var before := _sample()
		var c: FrontierCharacter = CharacterFactory.spawn_id(id)
		if c == null:
			continue
		host.add_child(c)
		c.position = Vector3(x, 0, -3.0)
		x += 0.9
		c.play("idle", 0.0)
		await _settle(4)
		var after := _sample()
		var res := _resource_bytes(c)
		var row := {"id": id, "rss_mb": _mb(after.rss - before.rss), "static_mb": _mb(after.static - before.static),
			"video_mb": _mb(after.video - before.video), "texture_mb": _mb(res.tex), "shared_texture_mb": _mb(res.shared_tex),
			"mesh_mb": _mb(res.mesh),
			"blend_mb": _mb(res.blend), "lod_mb": _mb(res.lod), "verts": res.verts, "shapes": res.shapes}
		looks.append(row)
		print("charmem look %-22s rss %6.1f  static %6.1f  video %6.1f | tex %5.1f (+shared %4.1f)  mesh %5.1f (blend %4.1f, lod %4.1f)  verts %d  shapes %d"
			% [id, row.rss_mb, row.static_mb, row.video_mb, row.texture_mb, row.shared_texture_mb, row.mesh_mb, row.blend_mb, row.lod_mb, row.verts, row.shapes])
	# per instance: more copies of the first look
	var n := int(Game.args.get("instances", 10))
	var before_i := _sample()
	var extra := []
	for i in n:
		var c: FrontierCharacter = CharacterFactory.spawn_id(ids[0], {"variant_seed": 100 + i})
		host.add_child(c)
		c.position = Vector3(-1.0 - 0.9 * (i % 10), 0, -4.0 - 1.2 * (i / 10))
		c.play("walk" if i % 2 == 0 else "idle", 0.0)
		_tweak(c, extra[0] if not extra.is_empty() else null)
		extra.append(c)
	await _settle(6)
	var after_i := _sample()
	var per := {"rss_mb": _mb(after_i.rss - before_i.rss) / max(n, 1), "static_mb": _mb(after_i.static - before_i.static) / max(n, 1),
		"video_mb": _mb(after_i.video - before_i.video) / max(n, 1), "nodes": _count_nodes(extra[0]) if n > 0 else 0}
	print("charmem per instance (%d x %s): rss %.2f MB  static %.2f MB  video %.2f MB  nodes %d"
		% [n, ids[0], per.rss_mb, per.static_mb, per.video_mb, per.nodes])
	var tot := _sample()
	var sum_look := 0.0
	for l in looks:
		sum_look += l.rss_mb
	var report := {"headless": DisplayServer.get_name() == "headless", "looks": looks, "per_instance": per,
		"spawn_ms": spawn_report,
		"looks_mean_rss_mb": sum_look / max(looks.size(), 1), "total_rss_delta_mb": _mb(tot.rss - base.rss),
		"total_video_mb": _mb(tot.video), "count_looks": looks.size(), "count_instances": looks.size() + n}
	print("charmem total: %d looks + %d instances -> rss +%.1f MB (looks mean %.1f MB/look)"
		% [looks.size(), n, report.total_rss_delta_mb, report.looks_mean_rss_mb])
	var out := str(Game.args.get("out", "user://charmem"))
	DirAccess.make_dir_recursive_absolute(out)
	var f := FileAccess.open(out.path_join("charmem.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
	return report


func _tweak(c: FrontierCharacter, first: FrontierCharacter) -> void:
	## --inst_mode a,b: isolate per-instance costs (nolod, nospring, noanim, sharedmat, nolook)
	var modes := str(Game.args.get("inst_mode", "")).split(",")
	if modes.has("nolod"):
		for n in ["LOD1", "LOD2"]:
			var l := c.find_child(n, true, false)
			if l:
				l.get_parent().remove_child(l)
				l.free()
	if modes.has("nospring") and c.springs:
		c.springs.get_parent().remove_child(c.springs)
		c.springs.free()
		c.springs = null
	if modes.has("nolook") and c.look:
		c.look.get_parent().remove_child(c.look)
		c.look.free()
		c.look = null
	if modes.has("noanim"):
		c.anim.stop()
		c.set_process(false)
		c.set_physics_process(false)
	if modes.has("sharedmat") and first != null:
		var a := _mesh_list(c)
		var b := _mesh_list(first)
		for k in mini(a.size(), b.size()):
			for s in a[k].mesh.get_surface_count():
				a[k].set_surface_override_material(s, b[k].get_surface_override_material(s))


func _mesh_list(n: Node) -> Array:
	var out := []
	var st: Array = [n]
	while not st.is_empty():
		var x: Node = st.pop_front()
		st.append_array(x.get_children())
		if x is MeshInstance3D:
			out.append(x)
	return out


func _default_ids() -> PackedStringArray:
	# the same role-diverse subset CharacterFactory.warm_up keeps on High (16) + the protagonist
	var by_role := {}
	var out := PackedStringArray(["ruth_caddell"])
	for c in CharacterFactory.catalog().get("characters", []):
		if c.get("tags", []).has("hero"):
			continue
		var r := str(c.get("role", ""))
		if not by_role.has(r):
			by_role[r] = []
		by_role[r].append(str(c["id"]))
	var round := 0
	while out.size() < 17:
		var added := false
		for r in by_role.keys():
			if round < by_role[r].size() and out.size() < 17:
				out.append(by_role[r][round])
				added = true
		if not added:
			break
		round += 1
	# measure an NPC first so the per-instance pass uses an NPC
	out.remove_at(0)
	out.append("ruth_caddell")
	return out


func _settle(frames: int) -> void:
	for i in frames:
		await host.get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _sample() -> Dictionary:
	return {"rss": _rss(), "static": OS.get_static_memory_usage(),
		"video": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}


func _rss() -> int:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return 0
	# /proc files report length 0, so read line by line
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("VmRSS:"):
			return int(line.split(":")[1].strip_edges().split(" ")[0]) * 1024
	return 0


func _mb(b: float) -> float:
	return snappedf(b / 1048576.0, 0.01)


func _count_nodes(n: Node) -> int:
	var k := 1
	for c in n.get_children():
		k += _count_nodes(c)
	return k


func _resource_bytes(root: Node) -> Dictionary:
	var out := {"tex": 0, "shared_tex": 0, "mesh": 0, "blend": 0, "lod": 0, "verts": 0, "shapes": 0}
	var texs := {}
	var meshes := {}
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is MeshInstance3D) or n.mesh == null:
			continue
		var mi: MeshInstance3D = n
		if not meshes.has(mi.mesh):
			meshes[mi.mesh] = mi.name
		for s in mi.mesh.get_surface_count():
			for m in [mi.get_surface_override_material(s), mi.mesh.surface_get_material(s), mi.material_override]:
				_collect_textures(m, texs)
	for t in texs.keys():
		if _seen_tex.has(t):
			continue
		_seen_tex[t] = true
		var tb := _tex_bytes(t)
		if t.resource_path.begins_with(CharacterMaterials.CLOTH_DIR) or t.resource_name.begins_with("fabric/"):
			out.shared_tex += tb
		else:
			out.tex += tb
	for m in meshes.keys():
		var b := 0
		var am := m as ArrayMesh
		if am == null:
			continue
		out.shapes = maxi(out.shapes, am.get_blend_shape_count())
		for s in am.get_surface_count():
			var arrs := am.surface_get_arrays(s)
			b += _arrays_bytes(arrs)
			if arrs.size() > 0 and arrs[Mesh.ARRAY_VERTEX] != null:
				out.verts += (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var bl := 0
			for sh in am.surface_get_blend_shape_arrays(s):
				bl += _arrays_bytes(sh)
			out.blend += bl
			b += bl
		out.mesh += b
		if str(meshes[m]).begins_with("LOD"):
			out.lod += b
	return out


func _collect_textures(m: Material, texs: Dictionary) -> void:
	if m == null:
		return
	if m is ShaderMaterial and m.shader:
		for u in m.shader.get_shader_uniform_list():
			var v = m.get_shader_parameter(u.name)
			if v is Texture2D:
				texs[v] = true
	elif m is BaseMaterial3D:
		for p in ["albedo_texture", "normal_texture", "roughness_texture", "ao_texture", "metallic_texture", "emission_texture"]:
			var v = m.get(p)
			if v is Texture2D:
				texs[v] = true
	if m.next_pass:
		_collect_textures(m.next_pass, texs)


func _tex_bytes(t: Texture2D) -> int:
	var img := t.get_image()
	if img == null:
		return t.get_width() * t.get_height() * 4
	return img.get_data_size()


func _arrays_bytes(arrs: Array) -> int:
	var b := 0
	for a in arrs:
		if a is PackedVector3Array:
			b += a.size() * 12
		elif a is PackedVector2Array:
			b += a.size() * 8
		elif a is PackedFloat32Array or a is PackedInt32Array:
			b += a.size() * 4
		elif a is PackedColorArray:
			b += a.size() * 16
		elif a is PackedByteArray:
			b += a.size()
	return b
