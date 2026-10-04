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
	DirAccess.make_dir_recursive_absolute(dir)
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
	cam.global_position = s["pos"]
	var look: Vector3 = s["look"]
	if cam.global_position.distance_to(look) > 0.01:
		cam.look_at(look, Vector3.UP)
	if G.sky:
		G.sky.set_hour(float(s.get("hour", 10.0)))
	if G.weather and G.weather.has_method("set_weather"):
		G.weather.set_weather(String(s.get("weather", "clear")), true)
	if G.world:
		G.world.focus(cam.global_position)
	if s.has("setup"):
		(s["setup"] as Callable).call()
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
	wait -= 1
	if wait > 0:
		return
	var s: Dictionary = shots[i]
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(String(s["name"]) + ".png")
	img.save_png(path)
	print("shot %s: %s (%d ms)" % [s["name"], path, Time.get_ticks_msec() - t_shot])
	_next()
