extends Node3D
func _ready():
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new(); e.sky.sky_material = ProceduralSkyMaterial.new()
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e; add_child(env)
	var s := DirectionalLight3D.new(); s.rotation_degrees = Vector3(-40, 30, 0); s.shadow_enabled = true; add_child(s)
	var m := MeshInstance3D.new(); m.mesh = BoxMesh.new(); add_child(m)
	var p := MeshInstance3D.new(); p.mesh = PlaneMesh.new(); p.mesh.size = Vector2(20,20); p.position.y=-0.5; add_child(p)
	var c := Camera3D.new(); c.position = Vector3(3,2,3); add_child(c); c.look_at(Vector3.ZERO)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://shot.png")
	print("SHOT ", ProjectSettings.globalize_path("user://shot.png"), " RENDERER ", RenderingServer.get_video_adapter_name(), " ", RenderingServer.get_current_rendering_method())
	get_tree().quit()
