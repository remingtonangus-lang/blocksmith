class_name WaterSystem
extends Node3D
## The ocean (a camera-centred radial grid at sea level, dense near the camera, out to the horizon) and the
## rivers (ribbons along WorldGen.rivers with their monotonic surface heights). One water shader for both.

var ocean: MeshInstance3D
var ocean_mat: ShaderMaterial
var river_mat: ShaderMaterial
var sea_state := 0.45


func setup(gen: WorldGen) -> void:
	var shader: Shader = load("res://shaders/water.gdshader")
	ocean_mat = ShaderMaterial.new()
	ocean_mat.shader = shader
	var na := _normal_tex(11, 0.06)
	var nb := _normal_tex(23, 0.025)
	ocean_mat.set_shader_parameter("normal_a", na)
	ocean_mat.set_shader_parameter("normal_b", nb)
	ocean_mat.render_priority = -1
	ocean = MeshInstance3D.new()
	ocean.name = "Ocean"
	ocean.mesh = _radial_mesh()
	ocean.material_override = ocean_mat
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean.extra_cull_margin = 150000.0
	add_child(ocean)
	river_mat = ShaderMaterial.new()
	river_mat.shader = shader
	river_mat.set_shader_parameter("normal_a", na)
	river_mat.set_shader_parameter("normal_b", nb)
	river_mat.set_shader_parameter("is_river", true)
	river_mat.set_shader_parameter("shallow_color", Color(0.09, 0.2, 0.16))
	river_mat.set_shader_parameter("deep_color", Color(0.02, 0.06, 0.05))
	for r in gen.rivers:
		var mi := MeshInstance3D.new()
		mi.name = "River"
		mi.mesh = _river_mesh(r, gen)
		mi.material_override = river_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _normal_tex(seed: int, freq: float) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.seed = seed
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq
	fn.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 6.0
	t.generate_mipmaps = true
	t.noise = fn
	return t


## Rings of quads whose spacing grows with distance: 1.5 m near the camera to ~2 km at 40 km.
func _radial_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var seg := 160
	var radii := PackedFloat32Array([0.0])
	var r := 2.0
	while r < 150000.0:
		radii.append(r)
		r *= 1.045 if r < 2000.0 else 1.12
	for ri in radii.size():
		for s in seg:
			var a := TAU * s / seg
			verts.append(Vector3(cos(a) * radii[ri], 0.0, sin(a) * radii[ri]))
	for ri in radii.size() - 1:
		for s in seg:
			var a := ri * seg + s
			var b := ri * seg + (s + 1) % seg
			var c := (ri + 1) * seg + s
			var d := (ri + 1) * seg + (s + 1) % seg
			idx.append_array([a, c, b, b, c, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _river_mesh(r: Dictionary, gen: WorldGen) -> ArrayMesh:
	var pts: PackedVector3Array = r["pts"]
	var w: PackedFloat32Array = r["w"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var n := pts.size()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var side := Vector3(-dir.z, 0.0, dir.x)
		var hw := w[i] * 0.5 + 6.0
		if i > 0:
			along += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		var y := pts[i].y
		verts.append(pts[i] - side * hw + Vector3(0, 0, 0))
		verts.append(pts[i] + side * hw)
		verts[verts.size() - 2].y = y
		verts[verts.size() - 1].y = y
		uvs.append(Vector2(along / 10.0, 0.0))
		uvs.append(Vector2(along / 10.0, hw * 2.0 / 10.0))
	for i in n - 1:
		if pts[i].y <= 0.05 and pts[i + 1].y <= 0.05:
			continue          # in the sea: the ocean covers it
		var a := i * 2
		for k in [a, a + 2, a + 1, a + 1, a + 2, a + 3]:
			st.set_uv(uvs[k])
			st.set_normal(Vector3.UP)
			st.add_vertex(verts[k])
	return st.commit()


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	ocean.global_position = Vector3(snappedf(c.x, 4.0), 0.0, snappedf(c.z, 4.0))
	ocean_mat.set_shader_parameter("cam_pos", c)
	ocean_mat.set_shader_parameter("sea_state", sea_state)
