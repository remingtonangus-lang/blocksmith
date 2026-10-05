class_name Backdrop
extends MeshInstance3D
## The country beyond the map: a coarse terrain ring out to 32 km so the horizon is ranges and plains, not a flat
## edge. Heights continue the map's own border and rise into procedural ranges (higher north and west where the
## Kestrel Range runs on, stepped mesas south-west, rolling hills east). Grid spacing grows with distance; the
## inner square sits under the playable terrain. Built on a worker thread; no collision, no shadows.

const OUTER := 32000.0

var _task := -1

func build(world: WorldData) -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/backdrop.gdshader")
	mat.set_shader_parameter("map_half", world.size_m * 0.5)
	material_override = mat
	_task = WorkerThreadPool.add_task(func():
		var arrays := _arrays(world)
		_finish.call_deferred(arrays), false, "backdrop")

func _finish(arrays: Array) -> void:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = am
	custom_aabb = AABB(Vector3(-OUTER, -500, -OUTER), Vector3(OUTER * 2, 4000, OUTER * 2))

static func _coords(half: float) -> PackedFloat32Array:
	var pos: Array[float] = []
	var x := half
	var step := 120.0
	while x < OUTER:
		pos.append(x)
		x += step
		step = minf(step * 1.12, 2200.0)
	pos.append(OUTER)
	var out := PackedFloat32Array()
	for i in range(pos.size() - 1, -1, -1):
		out.append(-pos[i])
	var inner := -half + 1024.0
	while inner < half - 1.0:
		out.append(inner)
		inner += 1024.0
	for v in pos:
		out.append(v)
	return out

func _arrays(world: WorldData) -> Array:
	var half := world.size_m * 0.5
	var cs := _coords(half)
	var n := cs.size()
	var ridges := FastNoiseLite.new()
	ridges.seed = 1899
	ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 5
	ridges.frequency = 0.00011
	var hills := FastNoiseLite.new()
	hills.seed = 77
	hills.fractal_octaves = 4
	hills.frequency = 0.00018
	var verts := PackedVector3Array()
	verts.resize(n * n)
	var outside := PackedByteArray()
	outside.resize(n * n)
	for j in n:
		for i in n:
			var x := cs[i]
			var z := cs[j]
			var dx := maxf(absf(x) - half, 0.0)
			var dz := maxf(absf(z) - half, 0.0)
			var d := sqrt(dx * dx + dz * dz)              # distance outside the map square
			var edge := world.height(clampf(x, -half + 1.0, half - 1.0), clampf(z, -half + 1.0, half - 1.0))
			var h: float
			if d <= 0.0:
				h = edge - 60.0                           # hidden under the playable terrain
			else:
				# regional character: ranges rise north/west, mesas south-west, gentle hills east
				var north := clampf(-z / OUTER * 2.0, 0.0, 1.0)
				var west := clampf(-x / OUTER * 2.0, 0.0, 1.0)
				var sw := clampf((z - x) / OUTER, 0.0, 1.0)
				var r := (ridges.get_noise_2d(x, z) * 0.5 + 0.5)
				var mtn := pow(r, 1.6) * lerpf(350.0, 1700.0, maxf(north, west * 0.8))
				var hl := (hills.get_noise_2d(x, z) * 0.5 + 0.5) * 220.0
				var mesa := (floorf(hl / 45.0) * 45.0 + 30.0) * sw
				var far := hl * (1.0 - sw) + mesa + mtn * (1.0 - sw * 0.6)
				h = lerpf(edge, edge * 0.4 + far + 120.0, smoothstep(0.0, 7000.0, d))
				outside[j * n + i] = 1
			verts[j * n + i] = Vector3(x, h, z)
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			if outside[a] == 0 and outside[a + 1] == 0 and outside[a + n] == 0 and outside[a + n + 1] == 0:
				continue
			var p00 := verts[a]
			var p10 := verts[a + 1]
			var p01 := verts[a + n]
			var p11 := verts[a + n + 1]
			var n1 := (p01 - p00).cross(p10 - p00).normalized()
			var n2 := (p01 - p10).cross(p11 - p10).normalized()
			v.append_array([p00, p10, p01, p10, p11, p01])
			nrm.append_array([n1, n1, n1, n2, n2, n2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	return arr

## A worker still running when the engine tears down aborts the process (seen at exit on CI): wait for it.
func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
