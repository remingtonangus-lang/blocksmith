extends Node3D
## Lineup of every tree/shrub species (full mesh) on a plain ground under the game sky, for judging the
## procedural vegetation. --out PATH (default /tmp/veg_lineup.png) --species a,b --time H --dist M
func _ready() -> void:
	var out := str(Game.args.get("out", "/tmp/veg_lineup.png"))
	var sky := SkySystem.new()
	add_child(sky)
	sky.setup(Game.PRESETS["preview"])
	sky.set_time(Game.arg_f("time", 15.5))
	sky.paused = true
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.37, 0.25)
	gm.roughness = 1.0
	g.material_override = gm
	add_child(g)
	var leaf := TreeGen.make_leaf_atlas()
	var gen := TreeGen.new()
	var names: Array = str(Game.args.get("species", ",".join(TreeGen.SPECIES.keys()))).split(",")
	var x := 0.0
	var veg = load("res://src/world/vegetation.gd").new()
	veg._leaf_tex = leaf
	for sp in names:
		var spec: Dictionary = TreeGen.SPECIES[sp]
		var m := gen.build(sp, hash(sp), 0)
		veg._meshes[sp] = [m]
		var mats: Dictionary = veg._make_materials_for_test(sp, m)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		var w := maxf(m.get_aabb().size.x, 2.0)
		x += w * 0.5 + 1.5
		mi.position = Vector3(x, 0, 0)
		x += w * 0.5 + 1.5
		add_child(mi)
		var l := Label3D.new()
		l.text = sp
		l.position = Vector3(mi.position.x, -0.5, 4)
		l.font_size = 96
		l.rotation_degrees = Vector3(-30, 0, 0)
		add_child(l)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50
	var d := Game.arg_f("dist", x * 0.62)
	cam.position = Vector3(x * 0.5, 7.0, d)
	cam.look_at(Vector3(x * 0.5, 6.0, 0))
	cam.make_current()
	cam.attributes = sky.cam_attr
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("lineup: ", out)
	get_tree().quit()
