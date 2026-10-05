extends SceneTree
## Headless test runner: godot --headless --path game -s res://tests/run_tests.gd
## Compiles every script, then runs the logic checks in tests/test_*.gd (each exposes `run(t)` and calls
## t.check(cond, msg)). Exit code = number of failures (0 = pass).

var failures := 0
var passes := 0
var current := ""


func _initialize() -> void:
	print("== Alabaster tests on Godot %s" % Engine.get_version_info()["string"])


var _errors: ErrorCount


func _process(_delta: float) -> bool:
	_errors = ErrorCount.install()
	_compile_all("res://scripts")
	_compile_all("res://tests")
	var files := DirAccess.get_files_at("res://tests")
	files.sort()
	for f in files:
		if f.begins_with("test_") and f.ends_with(".gd"):
			current = f
			var s: GDScript = load("res://tests/" + f)
			if s == null:
				fail("could not load " + f)
				continue
			var inst: Object = s.new()
			var t0 := Time.get_ticks_msec()
			var errs := _errors.n
			_errors.first = ""
			inst.run(self)
			# A runtime script error aborts the file's remaining checks silently (a removed function once skipped
			# five world checks and the run still reported 0 failed).
			if _errors.n > errs:
				fail(_errors.since(errs))
			print("  %s: %d ms" % [f, Time.get_ticks_msec() - t0])
			if inst is Node:
				inst.free()
	print("== %d passed, %d failed" % [passes, failures])
	quit(failures)
	return true


func _compile_all(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			var path := dir.path_join(f)
			var s: Script = load(path)
			check(s != null and s.can_instantiate(), "compiles: " + path)
		elif f.ends_with(".gdshader"):
			pass
	for d in DirAccess.get_directories_at(dir):
		_compile_all(dir.path_join(d))


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		fail(msg)


func fail(msg: String) -> void:
	failures += 1
	printerr("FAIL [%s] %s" % [current, msg])


func near(a: float, b: float, eps: float, msg: String) -> void:
	check(absf(a - b) <= eps, "%s (%f vs %f)" % [msg, a, b])
