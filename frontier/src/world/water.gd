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
	mi.material_override = _material(0.0, 0.25, Color(0.10, 0.14, 0.11), Color(0.02, 0.05, 0.07))
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
	_build_banks(verts, pts, surf, widths)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var main: bool = r.name == "Sable River"
	mi.material_override = _material(0.35 if main else 0.5, 0.9 if main else 0.6,
		Color(0.17, 0.15, 0.10), Color(0.05, 0.06, 0.04))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = str(r.name).replace(" ", "")
	add_child(mi)

## Gravel and wet-mud margins on both sides of a river: a terrain-hugging strip from just under the water line to a
## few metres up the bank, darker and glossier near the water, fading into the terrain outward.
var _bank_mat: ShaderMaterial

func _build_banks(verts: Array, pts: Array, surf: Array, widths: Array) -> void:
	if Game.headless or Game.terrain == null:
		return
	if _bank_mat == null:
		_bank_mat = ShaderMaterial.new()
		_bank_mat.shader = load("res://shaders/river_bank.gdshader")
		_bank_mat.set_shader_parameter("tex_ah", Game.terrain.material.get_shader_parameter("tex_ah"))
		_bank_mat.set_shader_parameter("tex_nr", Game.terrain.material.get_shader_parameter("tex_nr"))
	var w: WorldData = Game.world
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const ACROSS := 5
	var rows: Array = []
	for i in pts.size():
		var p := Vector2(pts[i][0], pts[i][1])
		var a := Vector2(pts[maxi(i - 1, 0)][0], pts[maxi(i - 1, 0)][1])
		var b := Vector2(pts[mini(i + 1, pts.size() - 1)][0], pts[mini(i + 1, pts.size() - 1)][1])
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var y: float = surf[i]
		var row := []
		for side in [1.0, -1.0]:
			var ring := []
			for k in ACROSS:
				var u := float(k) / float(ACROSS - 1)
				var off: float = widths[i] * 0.5 - 1.5 + u * 7.0
				var q: Vector2 = p + nrm * side * off
				var h := maxf(w.height(q.x, q.y), y - 0.6) + 0.03
				ring.append([Vector3(q.x, h, q.y), u, verts[i][2], h - y])
			row.append(ring)
		rows.append(row)
	for i in rows.size() - 1:
		for s_i in 2:
			var r0: Array = rows[i][s_i]
			var r1: Array = rows[i + 1][s_i]
			for k in ACROSS - 1:
				var quad := [r0[k], r1[k], r1[k + 1], r0[k], r1[k + 1], r0[k + 1]] if s_i == 1 else [r0[k], r0[k + 1], r1[k + 1], r0[k], r1[k + 1], r1[k]]
				for e in quad:
					st.set_normal(Vector3.UP)
					st.set_uv(Vector2(e[1], e[2]))
					st.set_uv2(Vector2(e[3], 0.0))
					st.add_vertex(e[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _bank_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "RiverBanks"
	add_child(mi)
