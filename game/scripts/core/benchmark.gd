extends Node
## --benchmark: flies a fixed camera path through segments the world provides (city, battle, forest...),
## records every frame time, and writes fps / frame-time percentiles, GPU time, draw calls and memory to
## ~/Library/Logs/CapitalGame/benchmark.json (or --benchmark-out PATH), then quits.
## Options: --preset NAME, --only SEGMENT, --res WxH (window size), --scale S (3D scale).

var segments: Array = []
var cam: Camera3D
var seg_i := -1
var t := 0.0
var warm := 0.0
var times := PackedFloat32Array()
var gpu_sum := 0.0
var draws_sum := 0.0
var prims_sum := 0.0
var results: Array = []
var timed_out := false
var peak_static := 0.0
var peak_vram := 0.0
var started_ms := 0
const WARMUP := 3.0
var _log_t := 0.0
var _limit := 0.0
var _seg_frames := 0


func start(segs: Array) -> void:
	segments = segs
	var only: String = String(Settings.arg("only", ""))
	if only != "":
		segments = segments.filter(func(s): return s["name"] == only)
	cam = Camera3D.new()
	cam.name = "BenchCam"
	cam.far = 160000.0
	cam.near = 0.1
	cam.fov = Settings.fov
	G.main.add_child(cam)
	cam.make_current()
	G.cam = cam
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	started_ms = Time.get_ticks_msec()
	# Watchdog: every segment's time plus warm-up and a generous margin for shader compiles and streaming.
	var total := 0.0
	for sg in segments:
		total += float(sg["duration"]) + WARMUP
	_limit = total + 180.0
	G.log_line("benchmark: %d segments, preset %s, driver %s, adapter %s" % [segments.size(), Settings.preset,
		RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name()])
	_next()


func _next() -> void:
	if seg_i >= 0:
		_finish_segment()
	seg_i += 1
	if seg_i >= segments.size():
		_write()
		return
	var s: Dictionary = segments[seg_i]
	G.log_line("benchmark: segment %d/%d '%s' starting at %.1f s" % [seg_i + 1, segments.size(), s["name"], (Time.get_ticks_msec() - started_ms) / 1000.0])
	_seg_frames = 0
	t = 0.0
	warm = 0.0
	times = PackedFloat32Array()
	gpu_sum = 0.0; draws_sum = 0.0; prims_sum = 0.0
	if s.has("setup"):
		(s["setup"] as Callable).call()
	_place(0.0)


func _place(u: float) -> void:
	var s: Dictionary = segments[seg_i]
	var pts: Array = s["path"]
	var looks: Array = s["look"]
	var f := clampf(u, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	var k := f - i
	var p: Vector3 = _catmull(pts, i, k)
	var l: Vector3 = _catmull(looks, i, k) if looks.size() == pts.size() else looks[0]
	cam.global_position = p
	if p.distance_to(l) > 0.01:
		cam.look_at(l, Vector3.UP)
	if G.world and G.world.has_method("focus"):
		G.world.focus(p)


func _catmull(a: Array, i: int, k: float) -> Vector3:
	var p0: Vector3 = a[maxi(i - 1, 0)]
	var p1: Vector3 = a[i]
	var p2: Vector3 = a[mini(i + 1, a.size() - 1)]
	var p3: Vector3 = a[mini(i + 2, a.size() - 1)]
	var k2 := k * k
	var k3 := k2 * k
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * k + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * k2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * k3)


func _process(delta: float) -> void:
	if seg_i < 0 or seg_i >= segments.size():
		return
	var wall := (Time.get_ticks_msec() - started_ms) / 1000.0
	_log_t += delta
	_seg_frames += 1
	if _log_t >= 5.0:
		_log_t = 0.0
		G.log_line("benchmark: '%s' %s %.1f s, %d frames this segment, %.1f fps now, wall %.0f s" % [segments[seg_i]["name"],
			"warm-up" if warm < WARMUP else "t", warm if warm < WARMUP else t, _seg_frames, Engine.get_frames_per_second(), wall])
	if wall > _limit:
		G.log_line("benchmark: TIMEOUT after %.0f s in segment '%s' (t %.1f, warm %.1f): writing partial results" % [wall, segments[seg_i]["name"], t, warm])
		_finish_segment()
		timed_out = true
		seg_i = segments.size()
		_write()
		return
	var s: Dictionary = segments[seg_i]
	peak_static = maxf(peak_static, Performance.get_monitor(Performance.MEMORY_STATIC))
	peak_vram = maxf(peak_vram, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	if warm < WARMUP:
		warm += delta
		_place(0.0)
		return
	times.append(delta * 1000.0)
	var rid := get_viewport().get_viewport_rid()
	gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	draws_sum += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	prims_sum += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	t += delta
	var dur: float = s["duration"]
	_place(t / dur)
	if t >= dur:
		_next()


func _pct(sorted: PackedFloat32Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(round(p * (sorted.size() - 1))), 0, sorted.size() - 1)]


func _finish_segment() -> void:
	var s: Dictionary = segments[seg_i]
	var sorted := times.duplicate()
	sorted.sort()
	var n := maxi(1, sorted.size())
	var total := 0.0
	for x in sorted: total += x
	var avg := total / n
	var r := {
		"name": s["name"], "frames": sorted.size(), "seconds": snappedf(total / 1000.0, 0.01),
		"avg_fps": snappedf(1000.0 / maxf(0.001, avg), 0.1),
		"frame_ms": {"avg": snappedf(avg, 0.01), "p50": snappedf(_pct(sorted, 0.5), 0.01),
			"p90": snappedf(_pct(sorted, 0.9), 0.01), "p95": snappedf(_pct(sorted, 0.95), 0.01),
			"p99": snappedf(_pct(sorted, 0.99), 0.01), "p999": snappedf(_pct(sorted, 0.999), 0.01),
			"max": snappedf(_pct(sorted, 1.0), 0.01)},
		"low1_fps": snappedf(1000.0 / maxf(0.001, _pct(sorted, 0.99)), 0.1),
		"gpu_ms_avg": snappedf(gpu_sum / n, 0.01),
		"draw_calls_avg": int(draws_sum / n), "primitives_avg": int(prims_sum / n),
	}
	results.append(r)
	G.log_line("benchmark %s: %.1f fps avg, p50 %.2f ms, p99 %.2f ms, gpu %.2f ms, draws %d" % [r["name"],
		r["avg_fps"], r["frame_ms"]["p50"], r["frame_ms"]["p99"], r["gpu_ms_avg"], r["draw_calls_avg"]])


func _write() -> void:
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var all_fps := 0.0
	for r in results: all_fps += r["avg_fps"]
	var out := {
		"game": "Alabaster", "version": ProjectSettings.get_setting("application/config/version"),
		"engine": Engine.get_version_info()["string"], "commit": _commit(),
		"date": Time.get_datetime_string_from_system(true), "os": OS.get_name(), "os_version": OS.get_version(),
		"cpu": OS.get_processor_name(), "cores": OS.get_processor_count(),
		"gpu": RenderingServer.get_video_adapter_name(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"preset": Settings.preset, "window": [int(size.x), int(size.y)], "scale_3d": vp.scaling_3d_scale,
		"upscaler": ["bilinear", "fsr1", "fsr2", "metalfx_spatial", "metalfx_temporal", "nearest"][vp.scaling_3d_mode],
		"vsync": DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED,
		"segments": results,
		"timeout": timed_out,
		"command_line": Settings.raw_cmdline,
		"overall_avg_fps": snappedf(all_fps / maxf(1, results.size()), 0.1),
		"memory": {"static_peak_mb": snappedf(peak_static / 1048576.0, 0.1),
			"vram_peak_mb": snappedf(peak_vram / 1048576.0, 0.1),
			"static_end_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)},
		"rss_mb": _rss_mb(),
		"load_seconds": snappedf(G.main.load_seconds, 0.01) if G.main and "load_seconds" in G.main else 0.0,
		"wall_seconds": snappedf((Time.get_ticks_msec() - started_ms) / 1000.0, 0.1),
	}
	var path: String = String(Settings.arg("benchmark-out", G.log_dir() + "/benchmark.json"))
	G.write_json(path, out)
	G.log_line("benchmark written to %s" % path)
	print(JSON.stringify(out))
	get_tree().quit(0)


## Resident memory of this process (release builds do not track static memory).
func _rss_mb() -> float:
	var out := []
	if OS.get_name() in ["macOS", "Linux"]:
		OS.execute("ps", ["-o", "rss=", "-p", str(OS.get_process_id())], out)
		if out.size() > 0:
			return snappedf(float(String(out[0]).strip_edges()) / 1024.0, 0.1)
	return 0.0


func _commit() -> String:
	var f := FileAccess.open("res://build_info.txt", FileAccess.READ)
	return f.get_as_text().strip_edges() if f else "dev"
