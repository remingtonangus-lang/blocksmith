class_name G
## Global registry: the live systems, shared helpers and the log directory.

static var main: Node3D
static var world: GameWorld
static var terrain: Terrain
static var gen: WorldGen
static var sky: SkySystem
static var weather: Node
static var player: Player
static var cam: Camera3D
static var hud: CanvasLayer
static var fx: Fx
static var combat: Node
static var battle: Battle
static var vehicles: Node3D
static var cities: Node3D
static var interactables: Array = []   # {node, offset, radius, prompt, action}
static var paused := false
static var frame := 0
static var seed := 1337

## Drops every static reference (called when the world leaves the tree): static vars outlive the scene, and
## Callables or objects held there at engine teardown are freed after their scripts.
static func reset() -> void:
	interactables = []
	main = null
	world = null
	terrain = null
	gen = null
	sky = null
	weather = null
	player = null
	cam = null
	hud = null
	fx = null
	combat = null
	battle = null
	vehicles = null
	cities = null


## Registers a "use" spot on a node (vehicle seats, consoles, turrets): prompt text and a Callable(player).
static func add_interactable(node: Node3D, offset: Vector3, radius: float, prompt: String, action: Callable) -> void:
	interactables.append({"node": node, "offset": offset, "radius": radius, "prompt": prompt, "action": action})


## ~/Library/Logs/CapitalGame on macOS, user://logs elsewhere.
static func log_dir() -> String:
	var dir := ""
	if OS.get_name() == "macOS":
		dir = OS.get_environment("HOME") + "/Library/Logs/CapitalGame"
	else:
		dir = ProjectSettings.globalize_path("user://logs")
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return dir


static func log_line(msg: String) -> void:
	print(msg)
	var path := log_dir() + "/game.log"
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line("[%s] %s" % [Time.get_datetime_string_from_system(), msg])


static func write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


## Deterministic hash of two ints to 0..1.
static func hash2(x: int, z: int, s: int = 0) -> float:
	var h := (x * 374761393 + z * 668265263 + s * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / 16777215.0


## Deletes caches of older versions from user:// (each world-generation bump left a 49 MB world file behind:
## ten of them, 490 MB, on the dev box), keeping the current version of every cache. Returns the bytes freed.
static func prune_cache(dir: String = "user://") -> int:
	var keep := {
		"world": WorldGen.GEN_VERSION, "terrain_mats": TerrainMaterials.VERSION,
		"leaf_atlas": TreeBuilder.VERSION, "audio": int(String(preload("res://scripts/audio/sfx.gd").CACHE).get_slice("_v", 1)),
	}
	var re := RegEx.create_from_string("^(world)_s\\d+_v(\\d+)\\.bin$|^(terrain_mats)_v(\\d+)_s\\d+\\.res$|^(leaf_atlas)_v(\\d+)\\.png$|^(audio)_v(\\d+)$")
	var freed := 0
	var d := DirAccess.open(dir)
	if d == null:
		return 0
	var names := Array(d.get_files()) + Array(d.get_directories())
	for n: String in names:
		var m := re.search(n)
		if m == null:
			continue
		for g in [1, 3, 5, 7]:
			if m.get_string(g) != "" and int(m.get_string(g + 1)) != keep[m.get_string(g)]:
				freed += _remove_tree(dir.path_join(n))
	return freed


static func _remove_tree(path: String) -> int:
	var bytes := 0
	if DirAccess.dir_exists_absolute(path):
		var d := DirAccess.open(path)
		for f in d.get_files():
			bytes += _remove_tree(path.path_join(f))
		for sub in d.get_directories():
			bytes += _remove_tree(path.path_join(sub))
	else:
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			bytes = f.get_length()
			f.close()
	DirAccess.remove_absolute(path)
	return bytes
