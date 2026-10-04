extends Node
## Adaptive 3D resolution: holds the frame-time target by moving the 3D render scale (in 5% steps, at most
## every 1.5 s, because a change reallocates the render buffers) between 60% of the preset scale and the preset
## scale. Uses the measured GPU time when the driver reports it, else the frame time.

var _acc := 0.0
var _gpu := 0.0
var _frame := 0.0
var _n := 0


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(delta: float) -> void:
	if not Settings.adaptive_resolution or Settings.has_arg("benchmark") or Settings.has_arg("shots"):
		return
	var rid := get_viewport().get_viewport_rid()
	_gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	_frame += delta * 1000.0
	_n += 1
	_acc += delta
	if _acc < 1.5:
		return
	var gpu := _gpu / _n
	var frame := _frame / _n
	_acc = 0.0; _gpu = 0.0; _frame = 0.0; _n = 0
	var budget := 1000.0 / Settings.target_fps
	var cost := gpu if gpu > 0.05 else frame
	var vp := get_viewport()
	var top: float = Settings.q["render_scale"]
	var s := vp.scaling_3d_scale
	var ns := s
	if cost > budget * 0.97:
		ns = s - 0.05
	elif cost < budget * 0.72:
		ns = s + 0.05
	ns = clampf(snappedf(ns, 0.05), top * 0.6, top)
	if absf(ns - s) > 0.001:
		vp.scaling_3d_scale = ns
