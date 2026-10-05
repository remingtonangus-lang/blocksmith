extends Node3D
## Town-life pose sheet (cheap: a few characters, no world): hand props, procedural poses, lying in bed.
## godot --path frontier --resolution 640x360 res://scenes/town_poses.tscn -- --out DIR [--only drink,hands] [--yaw DEG]
## Four cells per PNG (poses_0.png, poses_1.png...).

const CELLS := [
	["drink + glass", "npc_008", "drink", "", "glass"],
	["bar schooner", "npc_016", "drink_smoke", "", "schooner"],
	["sweeping", "npc_011", "idle_shift", "", "broom"],
	["hands up", "npc_009", "", "hands_up", ""],
	["cower", "npc_026", "idle_crouch", "cower", ""],
	["passed out", "npc_019", "sit_idle", "slump", ""],
	["piano", "npc_013", "sit_idle", "play", ""],
	["newspaper", "npc_022", "sit_idle", "read", "newspaper"],
	["cards", "npc_014", "sit_idle", "cards", "cards"],
	["smithy", "npc_017", "idle_wait", "", "hammer"],
	["asleep", "npc_010", "", "", ""],
]

func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func(): get_tree().quit(2))
	var out := str(Game.args.get("out", "user://poses"))
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.40, 0.37)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.78)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.5
	add_child(sun)
	var only := str(Game.args.get("only", ""))
	var cells := []
	for c in CELLS:
		if only == "" or only.split(",").has(str(c[0]).split(" ")[0]):
			cells.append(c)
	var chars := []
	for i in cells.size():
		var c: Array = cells[i]
		var ch: FrontierCharacter = CharacterFactory.spawn_id(c[1], {"variant_seed": i})
		if ch == null:
			continue
		var holder := Node3D.new()
		holder.position = Vector3((i % 4) * 1.4 - 2.1, 0, 0)
		holder.rotation.y = PI        # characters face -Z: turn them to the camera
		add_child(holder)
		holder.add_child(ch)
		if str(c[0]) == "asleep":
			ch.transform = FrontierCharacter.lie_transform(Vector3(1, 0, 0), 0.55)
			var bed := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.9, 0.5, 0.9)
			bed.mesh = bm
			bed.position = Vector3(0, 0.25, 0)
			holder.add_child(bed)
		chars.append([ch, c])
	for i in chars.size() + 2:
		for e2 in chars:
			e2[0].set_locomotion(0.0, "idle")
		await get_tree().process_frame
	for e2 in chars:
		var ch: FrontierCharacter = e2[0]
		var c: Array = e2[1]
		if str(c[2]) != "":
			ch.set_activity(c[2])
		if str(c[3]) != "":
			ch.set_pose(c[3])
		if str(c[4]) != "":
			HandProps.hold(ch, c[4])
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	var yaw := deg_to_rad(float(Game.args.get("yaw", 0.0)))
	var rows := int(ceil(chars.size() / 4.0))
	for row in rows:
		for i in chars.size():
			chars[i][0].get_parent().visible = i / 4 == row
		cam.position = Vector3(sin(yaw) * 5.4, 1.3, cos(yaw) * 5.4)
		cam.look_at(Vector3(0, 0.85, 0))
		var t := 0.0
		while t < 3.4:
			for e2 in chars:
				e2[0].set_locomotion(0.0, "idle")
			await get_tree().process_frame
			t += get_process_delta_time()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("poses_%d.png" % row))
		var labels := []
		for i in chars.size():
			if i / 4 == row:
				labels.append(chars[i][1][0])
		print("town_poses: row %d: %s" % [row, ", ".join(labels)])
	if not chars.is_empty():
		var sk: Skeleton3D = chars[0][0].skeleton
		var rh := sk.find_bone("RightHand")
		print("town_poses: RightHand rest basis ", sk.get_bone_global_rest(rh).basis, " bones ", sk.get_bone_count())
	get_tree().quit(0)
