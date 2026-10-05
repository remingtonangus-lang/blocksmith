extends Node3D
## Impostor check (needs a renderer: xvfb-run on Linux): bakes the tree impostors (src/world/impostor_baker.gd), saves
## the atlases, then renders every species twice side by side, full mesh (left) and impostor (right), under the game
## sky at a chosen distance, so the hand-off can be judged.
##   godot --path frontier res://scenes/impostor_test.tscn -- [--out DIR] [--species a,b] [--dist M] [--fov DEG]
##         [--yaw DEG] [--time H] [--rebake] [--no_lineup]
## Writes DIR/impostor_albedo.png (colour over grey), DIR/impostor_normal.png, DIR/impostor_lineup.png.

const VARIANTS := 3     # = vegetation.gd VARIANTS

func _ready() -> void:
	var out := str(Game.args.get("out", "/tmp"))
	DirAccess.make_dir_recursive_absolute(out)
	var sky := SkySystem.new()
	add_child(sky)
	sky.setup(Game.PRESETS["preview"])
	sky.set_time(Game.arg_f("time", 15.5))
	sky.paused = true
	var veg = load("res://src/world/vegetation.gd").new()
	veg._leaf_tex = TreeGen.make_leaf_atlas()
	var gen := TreeGen.new()
	var all: Array = TreeGen.SPECIES.keys()
	for sp in all:
		var vs := []
		for v in VARIANTS:
			vs.append(gen.build(sp, hash(sp) + v * 7919, 0))
		veg._meshes[sp] = vs
		veg._mats[sp] = veg._make_materials(sp)
	var ib := ImpostorBaker.new()
	if not ib.bake(self, veg._meshes, all, VARIANTS):
		print("IMPOSTOR FAIL: bake")
		get_tree().quit(1)
		return
	_save_atlases(ib, out)
	if Game.args.has("no_lineup"):
		get_tree().quit()
		return
	# lineup: mesh | impostor per species (variant 0)
	var names: Array = str(Game.args.get("species", ",".join(all))).split(",")
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/impostor_tree.gdshader")
	var info := PackedVector4Array()
	for sp in all:
		for v in VARIANTS:
			info.append(Vector4(0.0, float(TreeGen.SPECIES[sp].height[1]), 1.0 if TreeGen.SPECIES[sp].leaf != "" else 0.0, 0.0))
	mat.set_shader_parameter("entry_info", info)
	mat.set_shader_parameter("far_end", 1e6)
	mat.set_shader_parameter("albedo_atlas", ib.albedo)
	mat.set_shader_parameter("normal_atlas", ib.normal)
	mat.set_shader_parameter("atlas_px", Vector2(ib.atlas_size))
	mat.set_shader_parameter("entry_rect", ib.entry_rect)
	mat.set_shader_parameter("entry_frame", ib.entry_frame)
	mat.set_shader_parameter("entry_crown", ib.entry_crown)
	mat.set_shader_parameter("light_dir", sky.sun.global_basis.z)
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.center_offset = Vector3(0, 0.5, 0)
	quad.custom_aabb = AABB(Vector3(-25, -5, -25), Vector3(50, 50, 50))
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2000, 2000)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.37, 0.25)
	gm.roughness = 1.0
	g.material_override = gm
	add_child(g)
	var yaw := deg_to_rad(Game.arg_f("yaw", 0.0))
	var x := 0.0
	var top := 0.0
	for sp in names:
		var si := all.find(sp)
		var m: ArrayMesh = veg._meshes[sp][0]
		for mt in m.get_surface_count():
			m.surface_get_material(mt).set_shader_parameter("lod_end", 1e6)
		var w := maxf(m.get_aabb().size.x, 1.5)
		top = maxf(top, m.get_aabb().end.y)
		x += w * 0.5 + 0.5
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.position = Vector3(x, 0, 0)
		mi.rotation.y = yaw
		add_child(mi)
		x += w + 0.5
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis(), Vector3(x, 0, 0)))
		mm.set_instance_custom_data(0, Color(si * VARIANTS, 1.0, yaw, 0.5))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		add_child(mmi)
		x += w * 0.5 + 2.5
	var cam := Camera3D.new()
	add_child(cam)
	# default: frame the whole row (16:9) with a 30 degree lens; --dist / --fov override
	cam.fov = Game.arg_f("fov", 30.0)
	var half_h := tan(deg_to_rad(cam.fov) * 0.5)
	var d := Game.arg_f("dist", maxf(x * 0.52 / (half_h * 16.0 / 9.0), top * 0.6 / half_h))
	cam.far = 5000.0
	cam.position = Vector3(x * 0.5, top * 0.45, d)
	cam.look_at(Vector3(x * 0.5, top * 0.45, 0))
	cam.make_current()
	cam.attributes = sky.cam_attr
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("impostor_lineup.png"))
	print("impostor lineup: ", out.path_join("impostor_lineup.png"))
	get_tree().quit()

## Albedo as seen (un-premultiplied, x2, over grey) and the normal atlas, at full size.
func _save_atlases(ib: ImpostorBaker, out: String) -> void:
	var imgs: Array = ib.images()
	if imgs.size() < 2:
		return
	var a: Image = imgs[0].duplicate()
	a.clear_mipmaps()
	var n: Image = imgs[1].duplicate()
	n.clear_mipmaps()
	var data := a.get_data()
	var nd := n.get_data()
	var cov := 0
	for i in range(0, data.size(), 4):
		var al := data[i + 3]
		if al > 0:
			cov += 1
		for c in 3:
			# stored premultiplied at half scale; show colour over 50% grey (approximate, in sRGB)
			var v := float(data[i + c]) / maxf(al / 255.0, 0.004) / 255.0
			var lin := pow(v, 2.2) * 2.0
			var shown := pow(clampf(lin, 0.0, 1.0), 1.0 / 2.2) * 255.0
			data[i + c] = int(lerpf(128.0, shown, al / 255.0))
			nd[i + c] = int(lerpf(0.0, float(nd[i + c]) / maxf(al / 255.0, 0.004), al / 255.0)) if al > 0 else 0
		data[i + 3] = 255
		nd[i + 3] = 255
	Image.create_from_data(a.get_width(), a.get_height(), false, Image.FORMAT_RGBA8, data).save_png(out.path_join("impostor_albedo.png"))
	Image.create_from_data(n.get_width(), n.get_height(), false, Image.FORMAT_RGBA8, nd).save_png(out.path_join("impostor_normal.png"))
	print("impostor atlases: %s (coverage %.1f%%)" % [out, 100.0 * cov / (data.size() / 4)])
