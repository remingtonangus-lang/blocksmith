class_name Roads
extends Node3D
## Road ribbons along WorldGen.roads (paved for the Capital, gravel for the Cinder Pact), bridge decks with
## railings and piers where they cross rivers, and collision for the decks.

const HALF := WorldGen.ROAD_HALF

var mats := {}


func setup(gen: WorldGen) -> void:
	for paved in [true, false]:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/road.gdshader")
		m.set_shader_parameter("paved", paved)
		mats[paved] = m
	var bridge_mat: Material = null
	if G.world and G.world.city_list.size() > 0:
		bridge_mat = G.world.city_list[0].mat
	for road in gen.roads:
		var paved: bool = road["faction"] == "capital"
		var pts: PackedVector3Array = road["pts"]
		var br: PackedByteArray = road["bridge"]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var along := 0.0
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var prev_u := 0.0
		for i in pts.size():
			var a := pts[maxi(i - 1, 0)]
			var b := pts[mini(i + 1, pts.size() - 1)]
			var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
			var side := Vector3(-dir.z, 0.0, dir.x)
			var lift := 0.1 if br[i] == 0 else 0.0
			var c := pts[i] + Vector3(0, lift, 0)
			var l := c - side * HALF
			var r := c + side * HALF
			if i > 0:
				along += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
				for q in [[prev_l, Vector2(prev_u, 0)], [r, Vector2(along, 1)], [prev_r, Vector2(prev_u, 1)],
						[prev_l, Vector2(prev_u, 0)], [l, Vector2(along, 0)], [r, Vector2(along, 1)]]:
					st.set_normal(Vector3.UP)
					st.set_uv(q[1])
					st.add_vertex(q[0])
			prev_l = l
			prev_r = r
			prev_u = along
		var mi := MeshInstance3D.new()
		mi.name = String(road["name"]).replace(" ", "")
		mi.mesh = st.commit()
		mi.material_override = mats[paved]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_bridges(road, bridge_mat)


## Bridge decks: a thick white deck, side railings and piers down to the river bed, with collision.
func _bridges(road: Dictionary, mat: Material) -> void:
	var pts: PackedVector3Array = road["pts"]
	var br: PackedByteArray = road["bridge"]
	var k := Kit.new()
	var any := false
	var body := StaticBody3D.new()
	for i in pts.size() - 1:
		if br[i] == 0 or br[i + 1] == 0:
			continue
		any = true
		var a := pts[i]
		var b := pts[i + 1]
		var mid := (a + b) * 0.5
		var d := b - a
		var len := d.length()
		var yaw := atan2(d.x, d.z)
		var pitch := -atan2(d.y, Vector2(d.x, d.z).length())
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		var xf := Transform3D(basis, mid)
		k.box(xf, Vector3(0, -0.6, 0), Vector3(HALF * 2.0 + 1.6, 1.2, len + 0.2), k.col(Kit.STONE, 0.3, 2.0, false))
		for s in [-1.0, 1.0]:
			k.box(xf, Vector3(s * (HALF + 0.5), 0.55, 0), Vector3(0.35, 1.1, len + 0.2), k.col(Kit.TRIM, 0.3))
		if i % 4 == 0:
			var ground := G.gen.macro_height(mid.x, mid.z)
			if mid.y - ground > 2.0:
				k.box(Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, (mid.y - 1.2 + ground - 2.0) * 0.5, mid.z)), Vector3.ZERO,
					Vector3(HALF * 1.4, mid.y - 1.2 - ground + 2.0, 1.8), k.col(Kit.STONE, 0.3, 2.0, false))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(HALF * 2.0 + 1.6, 1.2, len + 0.3)
		cs.shape = bs
		cs.transform = Transform3D(basis, mid + basis * Vector3(0, -0.6, 0))
		body.add_child(cs)
	if not any:
		body.free()
		return
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	mi.material_override = mat
	add_child(mi)
	add_child(body)
