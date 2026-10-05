extends Node
## --shots DIR: renders each entry of World.shot_list() (camera, hour, weather), waits for the frame to settle
## (sky radiance, exposure, streaming), saves DIR/<name>.png and quits. --only a,b limits the list.

var shots: Array = []
var dir := ""
var cam: Camera3D
var i := -1
var wait := 0
var t_shot := 0
const SETTLE := 14


func start(list: Array, out_dir: String) -> void:
	shots = list
	dir = out_dir
	if not dir.is_absolute_path():
		dir = ProjectSettings.globalize_path("res://").path_join(dir) if dir.begins_with("res://") else OS.get_environment("PWD").path_join(dir)
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)   # (on an existing directory it logs ERR_CANT_OPEN)
	cam = Camera3D.new()
	cam.far = 160000.0
	cam.near = 0.1
	cam.fov = Settings.fov
	G.main.add_child(cam)
	cam.make_current()
	G.cam = cam
	if G.sky:
		G.sky.env.sky.process_mode = Sky.PROCESS_MODE_REALTIME
		G.sky.cam_attr.auto_exposure_speed = 30.0
	_next()


func _next() -> void:
	i += 1
	if i >= shots.size():
		print("shots: done (%d)" % shots.size())
		get_tree().quit(0)
		return
	var s: Dictionary = shots[i]
	cam.fov = float(s.get("fov", Settings.fov))
	cam.global_position = s["pos"]
	var look: Vector3 = s["look"]
	if cam.global_position.distance_to(look) > 0.01:
		cam.look_at(look, Vector3.UP)
	cam.make_current()
	G.cam = cam
	if s.get("fps", false) and G.world:
		if G.player == null:
			G.world.spawn_player()
		# First person through the player's own camera (weapon view model, HUD-free).
		var p: Player = G.player
		var d: Vector3 = look - (s["pos"] as Vector3)
		var sp: Vector3 = s["pos"]
		p.global_position = Vector3(sp.x, G.world.surface_at(sp.x, sp.z) + 0.05, sp.z)
		p.velocity = Vector3.ZERO
		p.rotation.y = atan2(-d.x, -d.z)
		p.pitch = atan2(d.y, Vector2(d.x, d.z).length())
		p.camera.make_current()
		G.cam = p.camera
		G.terrain.collision_now(p.global_position)
	# SHOT_HOUR / SHOT_WEATHER override every shot's (bisecting sky problems).
	var hour := float(OS.get_environment("SHOT_HOUR")) if OS.get_environment("SHOT_HOUR") != "" else float(s.get("hour", 10.0))
	var wx := OS.get_environment("SHOT_WEATHER") if OS.get_environment("SHOT_WEATHER") != "" else String(s.get("weather", "clear"))
	if G.sky:
		G.sky.set_hour(hour)
	if G.weather and G.weather.has_method("set_weather"):
		G.weather.set_weather(wx, true)
	if G.world:
		G.world.focus(cam.global_position)
	# Undo what an earlier shot's setup changed (horizon_test hides the ocean; later shots lost the sea).
	if G.world and G.world.water and G.world.water.ocean:
		G.world.water.ocean.visible = true
	if s.has("setup"):
		(s["setup"] as Callable).call()
	# SHOT_HIDE="Roads,Water": hide world groups (bisecting stray geometry in a shot).
	for nm in OS.get_environment("SHOT_HIDE").split(",", false):
		var n := G.world.get_node_or_null(nm)
		if n is Node3D:
			(n as Node3D).visible = false
	wait = int(s.get("settle", SETTLE))
	t_shot = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if i < 0 or i >= shots.size():
		return
	if G.world and not G.world.is_settled() and wait > -150:
		wait = mini(wait, 0) - 1
		return
	if wait < 0:
		wait = SETTLE
	var s0: Dictionary = shots[i]
	if s0.has("late") and not s0.has("_late_done"):
		# Called once the world has settled, then the shot waits its own "late_frames" (moments in motion).
		s0["_late_done"] = true
		(s0["late"] as Callable).call()
		wait = int(s0.get("late_frames", SETTLE))
	wait -= 1
	if wait > 0:
		return
	var s: Dictionary = shots[i]
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(String(s["name"]) + ".png")
	img.save_png(path)
	var vc := get_viewport().get_camera_3d()
	if OS.get_environment("SHOT_PROBE") != "" and vc:
		_probe(vc, OS.get_environment("SHOT_PROBE"))
	print("shot %s: %s (%d ms) camera %s at %s" % [s["name"], path, Time.get_ticks_msec() - t_shot, vc.name if vc else "none", vc.global_position if vc else Vector3.ZERO])
	_next()


## SHOT_PROBE="x,y;x,y" (pixels): what lies under those pixels: the physics hit, and every visible mesh whose
## bounds the ray crosses (nearest first), for tracking down stray geometry in a shot.
func _probe(vc: Camera3D, spec: String) -> void:
	var size := get_viewport().get_visible_rect().size
	for pt in spec.split(";"):
		var xy := pt.split(",")
		var px := Vector2(float(xy[0]), float(xy[1])) * size / Vector2(1280, 720)
		var o := vc.project_ray_origin(px)
		var d := vc.project_ray_normal(px)
		var q := PhysicsRayQueryParameters3D.create(o, o + d * 20000.0)
		var hit := vc.get_world_3d().direct_space_state.intersect_ray(q)
		print("probe %s: physics %s" % [pt, ("%s at %s" % [hit["collider"].get_path() if hit["collider"] is Node else hit["collider"], hit["position"]]) if not hit.is_empty() else "nothing"])
		var cands: Array = []
		_probe_walk(G.world, o, d, cands)
		cands.sort_custom(func(a, b): return a[0] < b[0])
		for c in cands.slice(0, 6):
			print("    mesh at %.0f m: %s" % [c[0], c[1]])


func _probe_walk(n: Node, o: Vector3, d: Vector3, out: Array) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	if n is GeometryInstance3D and not (n is GPUParticles3D):
		var gi := n as GeometryInstance3D
		var bb := gi.global_transform * (gi.custom_aabb if gi.custom_aabb.size != Vector3.ZERO else gi.get_aabb())
		var hit: Variant = bb.intersects_ray(o, d)
		if hit != null and bb.size.length() < 20000.0:
			out.append([o.distance_to(hit), str(gi.get_path()).replace("/root/Main/World/", "")])
	for c in n.get_children():
		_probe_walk(c, o, d, out)
