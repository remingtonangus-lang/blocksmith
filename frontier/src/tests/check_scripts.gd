extends Node
## Parse/compile check for every script and shader in the project (CI + local): exits 1 on any failure.
func _ready() -> void:
	var bad := 0
	var files := []
	_collect("res://src", files)
	_collect("res://shaders", files)
	for f in files:
		var r = load(f)
		if r == null:
			print("CHECK FAIL: ", f)
			bad += 1
		elif r is GDScript and not r.can_instantiate():
			print("CHECK FAIL (cannot instantiate): ", f)
			bad += 1
	print("checked %d files, %d failed" % [files.size(), bad])
	get_tree().quit(1 if bad > 0 else 0)

func _collect(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or f.ends_with(".gdshader"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)
