extends Node3D
## Lake Agnes surface and river ribbons built from worldgen features (surface heights per sample).

var world: WorldData

func setup(w: WorldData, _b = null) -> void:
	world = w
	_build_lake()
	for r in world.features.get("rivers", []):
		_build_river(r)

func _material(flow: float, murk: float, shallow: Color, deep: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("flow_speed", flow)
	m.set_shader_parameter("murk", murk)
	m.set_shader_parameter("shallow_color", shallow)
	m.set_shader_parameter("deep_color", deep)
	return m

func _build_lake() -> void:
	var lk: Dictionary = world.features.get("lake", {})
	if lk.is_empty():
		return
	var cx: float = lk.u * world.size_m - world.size_m * 0.5
	var cz: float = lk.v * world.size_m - world.size_m * 0.5
	var sx: float = lk.ru * world.size_m * 2.6
	var sz: float = lk.rv * world.size_m * 2.6
	var pm := PlaneMesh.new()
	pm.size = Vector2(sx, sz)
	pm.subdivide_width = 96
	pm.subdivide_depth = 96
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position = Vector3(cx, world.lake_level, cz)
	mi.material_override = _material(0.0, 0.25, Color(0.30, 0.38, 0.30), Color(0.03, 0.10, 0.13))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "LakeAgnes"
	add_child(mi)

func _build_river(r: Dictionary) -> void:
	var pts: Array = r.points
	var surf: Array = r.surface
	var widths: Array = r.width
	if pts.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var prev := Vector2(pts[0][0], pts[0][1])
	var verts := []
	for i in pts.size():
		var p := Vector2(pts[i][0], pts[i][1])
		along += p.distance_to(prev)
		prev = p
		var a := Vector2(pts[maxi(i - 1, 0)][0], pts[maxi(i - 1, 0)][1])
		var b := Vector2(pts[mini(i + 1, pts.size() - 1)][0], pts[mini(i + 1, pts.size() - 1)][1])
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var hw: float = widths[i] * 0.5 + 2.5     # overlap banks; terrain hides the excess
		var y: float = surf[i]
		var l := p + nrm * hw
		var rr := p - nrm * hw
		verts.append([Vector3(l.x, y, l.y), Vector3(rr.x, y, rr.y), along])
	for i in verts.size() - 1:
		var v0 = verts[i]
		var v1 = verts[i + 1]
		var w0: float = widths[i]
		var w1: float = widths[i + 1]
		var uv0: float = v0[2] / maxf(w0, 4.0)
		var uv1: float = v1[2] / maxf(w1, 4.0)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0, uv0)); st.add_vertex(v0[0])
		st.set_uv(Vector2(1, uv0)); st.add_vertex(v0[1])
		st.set_uv(Vector2(1, uv1)); st.add_vertex(v1[1])
		st.set_uv(Vector2(0, uv0)); st.add_vertex(v0[0])
		st.set_uv(Vector2(1, uv1)); st.add_vertex(v1[1])
		st.set_uv(Vector2(0, uv1)); st.add_vertex(v1[0])
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var main: bool = r.name == "Sable River"
	mi.material_override = _material(0.35 if main else 0.5, 0.9 if main else 0.6,
		Color(0.36, 0.34, 0.24), Color(0.10, 0.11, 0.08))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = str(r.name).replace(" ", "")
	add_child(mi)
