extends Node3D
## GPU shader compatibility probe (CI): renders one spatial shader on a few primitive meshes (plus skinned-style
## sphere/box/plane) for a handful of frames, then quits 0. A shader that hangs the paravirtual GPU / MoltenVK never
## prints "shader ok", so the CI loop around this names it.
## godot --path frontier res://scenes/shader_probe.tscn -- --shader res://shaders/building.gdshader

func _ready() -> void:
	var path := str(Game.args.get("shader", ""))
	var sh = load(path) if path != "" else null
	if not (sh is Shader):
		print("shader probe: cannot load ", path)
		get_tree().quit(2)
		return
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.2, 4.0)
	cam.look_at(Vector3(0, 0.6, 0))
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	add_child(env)
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var meshes: Array = [SphereMesh.new(), BoxMesh.new(), PlaneMesh.new(), CapsuleMesh.new()]
	for i in meshes.size():
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[i]
		mi.material_override = mat
		mi.position = Vector3(-2.25 + i * 1.5, 0.6, 0)
		add_child(mi)
	var t0 := Time.get_ticks_msec()
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("shader ok: %s (%d ms)" % [path, Time.get_ticks_msec() - t0])
	get_tree().quit(0)
