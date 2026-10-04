extends CanvasLayer
## F3 performance overlay: fps, frame-time percentiles over the last 2 s, GPU time, draw calls, primitives,
## memory, preset and 3D resolution.

var label: Label
var times := PackedFloat32Array()
var _acc := 0.0


func _ready() -> void:
	layer = 50
	label = Label.new()
	label.position = Vector2(12, 10)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	visible = Settings.show_perf


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("perf_hud"):
		visible = not visible
		Settings.show_perf = visible
	times.append(delta * 1000.0)
	if times.size() > 240:
		times = times.slice(times.size() - 240)
	_acc += delta
	if not visible or _acc < 0.25:
		return
	_acc = 0.0
	var sorted := times.duplicate()
	sorted.sort()
	var n := sorted.size()
	var avg := 0.0
	for t in sorted: avg += t
	avg /= maxf(1.0, n)
	var p99: float = sorted[int(n * 0.99)] if n > 0 else 0.0
	var vp := get_viewport()
	var rid := vp.get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
	var size := vp.get_visible_rect().size
	var s3 := vp.scaling_3d_scale
	var txt := "%d fps  avg %.2f ms  1%% %.2f ms\n" % [Engine.get_frames_per_second(), avg, p99]
	txt += "GPU %.2f ms  render CPU %.2f ms  physics %.2f ms\n" % [gpu, cpu, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0]
	txt += "draws %d  prims %.2fM  objects %d\n" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6,
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)]
	txt += "mem %.0f MB  vram %.0f MB  nodes %d\n" % [
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)]
	txt += "%s  %dx%d  3D %.0f%% (%s)  %s\n" % [Settings.preset, size.x, size.y, s3 * 100.0,
		["bilinear", "FSR1", "FSR2", "MetalFX S", "MetalFX T", "nearest"][vp.scaling_3d_mode],
		RenderingServer.get_current_rendering_driver_name()]
	if G.player:
		var p: Vector3 = G.player.global_position
		txt += "pos %.0f %.0f %.0f" % [p.x, p.y, p.z]
		if G.sky:
			txt += "  time %s" % G.sky.clock_string()
	label.text = txt
