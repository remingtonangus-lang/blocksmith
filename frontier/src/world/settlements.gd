extends Node3D
## Settlements of the Sable River country: every town and point of interest in world.features, planned at boot
## (town_layout.gd) and built in full detail by the 1899 kit (building_styles.gd / interiors.gd / structures.gd)
## when the camera comes within ~750 m — on a worker thread, attached on the main thread. See
## design/SETTLEMENTS.md.
##
## Rendering per settlement: exterior geometry merged per 128 m cell into one MeshInstance3D (one surface per
## material, visible to 520 m); interiors (partitions, counters, stairs, goods) per cell to 140 m; Poly Haven
## props as MultiMeshes per cell (interior 140 m, street 200 m); door leaves are MultiMesh instances; a single
## vertex-coloured far shell per settlement from 480 m (always present, 1 draw call at 1 km).
## Night: street lamps, porch lanterns, interior lights and lit windows switch on at dusk (Game.sky); lights are
## culled beyond 140 m and distance-faded; fires flicker.
##
## API for town life / AI (world space):
##   get_town(id) -> {id, name, kind, center, frame, radius, state ("far"|"building"|"built"), buildings: [ids],
##                    doors: [ids], spots: [...], streets, nav_regions, node}
##   get_building(id) -> {id, town, type, name, transform, size, floor_y, doors, spots, rooms, enterable, hours, role}
##   spots(town_id, type := "") -> [{type, transform (stand here, face -Z), building, town, sit_height|work|door...}]
##   nearest_spot(pos, type, max_dist) -> Dictionary;  door(id) -> TownDoor;  nearest_door(pos, max_dist)
##   interact_nearest(pos, max_dist) -> bool;  town_at(pos) -> id;  building_at(pos) -> id
##   ensure_built(town_id) builds a settlement now (blocking); signal town_built(id)
##   bake_navigation(town_id) bakes 64 m NavigationMesh chunks in the background (automatic when the player is
##   within 350 m of a built settlement); navigation_ready(town_id)

signal town_built(id: String)

const CELL := 128.0
const EXT_RANGE := 520.0
const FAR_BEGIN := 480.0
const INT_RANGE := 45.0          # per building (backstop; _interiors() shows them only within INT_NEAR)
const INT_NEAR := 9.0
const OPROP_RANGE := 140.0
const DOOR_RANGE := 120.0         # + town radius (one MultiMesh per door mesh per town)
const LIGHT_CULL := 140.0
const BUILD_DIST := 750.0
const NAV_CHUNK := 64.0
const NAV_AUTO_DIST := 350.0
const NAV_PARALLEL := 3
const UNLOAD_DIST := 1200.0      # beyond radius + this, a built settlement drops its detail (rebuilt on return)

var world: WorldData
var towns := {}
var buildings := {}
var doors := {}
var stats := {"built": 0, "buildings": 0, "ext_tris": 0, "int_tris": 0, "far_tris": 0, "meshes": 0, "multimeshes": 0, "lights": 0, "shapes": 0}
var prof := {}
var _lights: Array = []          # [OmniLight3D, base_energy, kind, phase, always]
var _spinners: Array = []        # [Node3D, axis, speed]
var _night := -1.0
var _timer := 0.0
var _int_timer := 0.0
var _door_meshes := {}
var _door_mutex := Mutex.new()
var _task := -1
var _task_town := ""
var _task_result := {}

func setup(w: WorldData, _b = null) -> void:
	world = w
	if Game.args.has("no_settlements") or Game.disabled("settlements"):        # perf A/B comparisons
		return
	mem("settlements start")
	var t0 := Time.get_ticks_msec()
	TownProps.preload_all()
	TownMats.get_all()
	for fnt in ["Rye", "OldStandard-Bold", "Sancreek-Regular", "OldStandard-Regular"]:
		SignText.atlas(fnt)
	var t1 := Time.get_ticks_msec()
	mem("props+mats+atlases")
	for f in world.features.get("towns", []):
		_plan_settlement(f, true)
	for f in world.features.get("pois", []):
		_plan_settlement(f, false)
	_upload_control()
	mem("plans+far shells")
	var t2 := Time.get_ticks_msec()
	# the player starts at Bitter Spring (or --spawn): have that settlement ready at once
	if not (Game.args.has("shot") or Game.args.has("tour")):
		var sp := Vector3(world.town("bitter_spring").get("x", 0.0), 0.0, world.town("bitter_spring").get("z", 0.0))
		if Game.args.has("spawn"):
			var p: PackedStringArray = str(Game.args["spawn"]).split(",")
			sp = Vector3(float(p[0]), 0.0, float(p[1]))
		for id in towns:
			if _dist_to(towns[id], sp) < 0.0:
				ensure_built(id)
	_update_lights(true)
	# the main line between the settlements (their own station track covers radius + 60 m)
	var skip := []
	for id in towns:
		for spec in towns[id].plan.specs:
			if str(spec.get("type", "")) == "track":
				skip.append({"x": towns[id].center.x, "z": towns[id].center.z, "r": towns[id].radius + 60.0})
				break
	var rl = load("res://src/world/rail_line.gd").new()
	rl.name = "RailLine"
	add_child(rl)
	rl.setup(world, skip)
	print("settlements: %d planned (atlases %d ms, plans %d ms), %d built at boot, %d ms total" % [towns.size(), t1 - t0, t2 - t1,
		stats.built, Time.get_ticks_msec() - t0])
	if Game.args.has("settlements_test"):
		_self_test()
	elif Game.args.has("memtest"):
		_mem_test()

# ------------------------------------------------------------------------------------------------ planning

## Memory probe (--memlog / --memtest): static memory in use.
static func mem(label: String) -> void:
	if not Game.args.has("memlog"):
		return
	print("MEMLOG %-28s static %5d MB" % [label, int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)])

func _plan_settlement(f: Dictionary, is_town: bool) -> void:
	var plan: Dictionary = TownLayout.new().make(world, f, is_town)
	var node := Node3D.new()
	node.name = str(f.id)
	add_child(node)
	var town := {"id": f.id, "name": f.name, "kind": f.kind, "center": Vector3(f.x, f.y, f.z), "frame": plan.frame,
		"radius": float(f.r), "buildings": [], "doors": [], "spots": [], "streets": plan.streets, "node": node,
		"nav_regions": [], "nav_state": "none", "is_town": is_town, "state": "far", "plan": plan, "detail": null,
		"specs": plan.specs.size()}
	_paint_ground(plan)
	var far := _far_shell(plan) if not Game.disabled("town_far") else MeshKit.new()
	if not far.is_empty():
		stats.far_tris += far.tris
		var fm := _mesh_node(far.commit(TownMats.get_all(), TownMats.plain_keys() + ["far"]), "Far", FAR_BEGIN, 0.0,
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		fm.visibility_range_begin_margin = 40.0
		node.add_child(fm)
	towns[f.id] = town

## Negative when inside the build radius around a settlement.
func _dist_to(t: Dictionary, p: Vector3) -> float:
	var c: Vector3 = t.center
	return Vector2(p.x - c.x, p.z - c.z).length() - t.radius - BUILD_DIST

## A cheap stand-in for every structure (walls + roof volume, vertex colours) seen from beyond ~480 m.
func _far_shell(plan: Dictionary) -> MeshKit:
	var k := MeshKit.new()
	k.ground = -100.0
	for s in plan.specs:
		var st: String = s.get("style", "")
		var w: float = s.get("w", 6.0)
		var d: float = s.get("d", 6.0)
		k.xf = s.xf
		var g: float = minf(world.height(s.xf.origin.x, s.xf.origin.z) - s.xf.origin.y, 0.0) - 0.3
		var wall: String = s.get("wall", "siding")
		var c: Color = TownMats.FAR_COL.get(wall, Color(0.5, 0.45, 0.4))
		if wall in ["paint", "plaster", "boards_v"]:
			c = s.get("paint", Color(0.85, 0.82, 0.76)) * Color(0.85, 0.85, 0.85)
		var roof: Color = TownMats.FAR_COL.get(s.get("roof", "shingles"), Color(0.32, 0.28, 0.24))
		var h := 3.6
		var ridge := 0.0
		var axis := "z"
		match st:
			"false_front":
				h = 3.6
				ridge = 5.0
				_fbox(k, -w * 0.5, -0.05, w * 0.5, 0.15, 3.6, 5.6, c)
			"two_storey":
				h = 6.9
				_fbox(k, -w * 0.5, -0.05, w * 0.5, 0.15, 6.9, 7.9, c)
				_fbox(k, -w * 0.5, -s.get("porch", 3.0), w * 0.5, 0.0, 3.3, 3.6, roof)
			"brick":
				h = 4.0 + 3.4 * (int(s.get("storeys", 2)) - 1) + 0.9
				c = TownMats.FAR_COL.brick
			"house":
				h = 2.9
				ridge = 2.9 + minf(w, d) * 0.5 * 0.7
				axis = s.get("roof_axis", "x" if w >= d * 0.9 else "z")
			"cabin":
				h = 2.5
				ridge = 2.5 + d * 0.5 * 0.62
				axis = "x"
				c = TownMats.FAR_COL.log
			"church":
				h = 4.8
				ridge = 4.8 + w * 0.5
				c = s.get("paint", Color(0.95, 0.94, 0.9))
				_fbox(k, -1.7, -3.4, 1.7, 0.0, g, 12.5, c)
				k.tint = Color(roof.r, roof.g, roof.b, 1)
				var ap := Vector3(0, 18.5, -1.7)
				k.tri("far", Vector3(1.8, 12.5, -3.5), Vector3(-1.8, 12.5, -3.5), ap)
				k.tri("far", Vector3(1.8, 12.5, 0.1), Vector3(1.8, 12.5, -3.5), ap)
				k.tri("far", Vector3(-1.8, 12.5, 0.1), Vector3(1.8, 12.5, 0.1), ap)
				k.tri("far", Vector3(-1.8, 12.5, -3.5), Vector3(-1.8, 12.5, 0.1), ap)
			"school":
				h = 3.4
				ridge = 3.4 + w * 0.5 * 0.7
			"barn":
				h = s.get("h", 4.4)
				ridge = h + w * 0.5 * 0.84
				c = s.get("paint", c) if wall == "paint" else TownMats.FAR_COL.planks_v
			"smithy", "shed", "outhouse", "sawmill":
				h = s.get("h", 3.0) if st != "outhouse" else 2.1
				if st == "outhouse":
					w = 1.2
					d = 1.3
			"depot":
				h = 3.7
				ridge = 3.7 + d * 0.5 * 0.53
				axis = "x"
			"adobe":
				h = 3.55
			"tent":
				h = s.get("wall_h", 1.3)
				ridge = s.get("ridge_h", 2.7)
				c = TownMats.FAR_COL.canvas
				roof = c
			"water_tower":
				k.tint = Color(0.42, 0.35, 0.28, 1)
				k.cyl("far", Vector3(0, 6.0, 0), Vector3(0, 10.4, 0), 2.9, 10, true)
				k.cyl("far", Vector3(0, 10.4, 0), Vector3(0, 11.8, 0), 3.1, 10, false, 0.1)
				_fbox(k, -2.4, -2.4, 2.4, 2.4, g, 6.0, Color(0.36, 0.3, 0.24))
				continue
			"windmill":
				_fbox(k, -0.7, -0.7, 0.7, 0.7, g, s.get("h", 9.0), Color(0.5, 0.48, 0.45))
				k.cyl("far", Vector3(0, s.get("h", 9.0) + 0.55, -0.8), Vector3(0, s.get("h", 9.0) + 0.55, -0.9), 1.7, 8, true)
				continue
			"headframe":
				_fbox(k, -1.0, -1.0, 1.0, 1.0, g, 14.0, Color(0.45, 0.38, 0.3))
				continue
			"mission_ruin":
				var col := Color(0.72, 0.56, 0.42)
				_fbox(k, -w * 0.5, 0.0, w * 0.5, 0.8, g, 6.5, col)
				_fbox(k, -w * 0.2, 0.0, w * 0.2, 0.8, 6.5, 9.0, col)
				_fbox(k, -w * 0.5, 0.8, -w * 0.5 + 0.8, d, g, 3.0, col)
				_fbox(k, w * 0.5 - 0.8, 0.8, w * 0.5, d, g, 3.0, col)
				continue
			"bridge", "pier":
				_fbox(k, -w * 0.5, 0.0, w * 0.5, s.get("length", 30.0), -0.5, 0.0, Color(0.4, 0.3, 0.22))
				continue
			"wagon":
				_fbox(k, -0.7, -1.6, 0.7, 1.5, g + 0.6, 2.4 if s.get("covered", false) else 1.3, Color(0.8, 0.76, 0.68) if s.get("covered", false) else Color(0.4, 0.3, 0.22))
				continue
			_:
				continue
		_fbox(k, -w * 0.5, 0.0, w * 0.5, d, g, h, c)
		if ridge > h:
			k.tint = Color(roof.r, roof.g, roof.b, 1)
			var oh := 0.3
			if axis == "z":
				k.quad("far", Vector3(-w * 0.5 - oh, h, -oh), Vector3(-w * 0.5 - oh, h, d + oh), Vector3(0, ridge, d + oh), Vector3(0, ridge, -oh))
				k.quad("far", Vector3(w * 0.5 + oh, h, d + oh), Vector3(w * 0.5 + oh, h, -oh), Vector3(0, ridge, -oh), Vector3(0, ridge, d + oh))
				k.tint = Color(c.r, c.g, c.b, 1)
				k.tri("far", Vector3(w * 0.5, h, 0), Vector3(-w * 0.5, h, 0), Vector3(0, ridge, 0))
				k.tri("far", Vector3(-w * 0.5, h, d), Vector3(w * 0.5, h, d), Vector3(0, ridge, d))
			else:
				k.quad("far", Vector3(w * 0.5 + oh, h, -oh), Vector3(-w * 0.5 - oh, h, -oh), Vector3(-w * 0.5 - oh, ridge, d * 0.5), Vector3(w * 0.5 + oh, ridge, d * 0.5))
				k.quad("far", Vector3(-w * 0.5 - oh, h, d + oh), Vector3(w * 0.5 + oh, h, d + oh), Vector3(w * 0.5 + oh, ridge, d * 0.5), Vector3(-w * 0.5 - oh, ridge, d * 0.5))
				k.tint = Color(c.r, c.g, c.b, 1)
				k.tri("far", Vector3(-w * 0.5, h, 0), Vector3(-w * 0.5, h, d), Vector3(-w * 0.5, ridge, d * 0.5))
				k.tri("far", Vector3(w * 0.5, h, d), Vector3(w * 0.5, h, 0), Vector3(w * 0.5, ridge, d * 0.5))
		elif st in ["adobe", "brick", "smithy", "shed", "outhouse", "two_storey", "false_front"]:
			k.tint = Color(roof.r, roof.g, roof.b, 1) * Color(0.9, 0.9, 0.9)
			k.box("far", Vector3(-w * 0.5, h - 0.05, 0), Vector3(w * 0.5, h + 0.02, d), MeshKit.F_PY)
	return k

func _fbox(k: MeshKit, x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, c: Color) -> void:
	k.tint = Color(c.r, c.g, c.b, 1.0)
	k.box("far", Vector3(x0, y0, z0), Vector3(x1, y1, z1), MeshKit.F_ALL & ~MeshKit.F_NY)

# ------------------------------------------------------------------------------------------------ detailed build

func _cell_key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))

## Build a settlement now (blocking). Safe to call for one that is already built or building.
func ensure_built(id: String) -> void:
	var t: Dictionary = towns.get(id, {})
	if t.is_empty() or t.state == "built":
		return
	if t.state == "building":
		_finish_task(true)
		return
	t.state = "building"
	var res := _prepare(t.plan)
	_attach(t, res)

## Worker-thread part: run the kit over every spec, merge geometry per cell, commit meshes and MultiMesh
## resources. No scene-tree access and no physics objects here (those are created in _attach).
func _prepare(plan: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var ext := {}
	var inn := {}
	var props := {}
	var oprops := {}
	var far := MeshKit.new()
	var kit := SettlementKit.new()
	kit.world = world
	var recs := []
	var tp := {}
	for spec in plan.specs:
		var ck := _cell_key(spec.xf.origin)
		if not ext.has(ck):
			ext[ck] = MeshKit.new()
			oprops[ck] = {}
		# interiors per building (culled at INT_RANGE from the building, seen only through doors and windows)
		var bk: String = spec.id
		inn[bk] = MeshKit.new()
		props[bk] = {}
		var t1 := Time.get_ticks_usec()
		var rec: Dictionary = kit.build(spec, {"ext": ext[ck], "inn": inn[bk], "far": far, "props": props[bk], "oprops": oprops[ck]})
		var key := "build:" + str(spec.get("style", ""))
		tp[key] = tp.get(key, 0) + Time.get_ticks_usec() - t1
		rec["cell"] = ck
		recs.append(rec)
	var t2 := Time.get_ticks_usec()
	var mats := TownMats.get_all()
	var plain := TownMats.plain_keys()
	var meshes := []
	var ext_tris := 0
	var int_tris := 0
	for ck in ext:
		var ek: MeshKit = ext[ck]
		if not ek.is_empty():
			ext_tris += ek.tris
			meshes.append(["Ext_%d_%d" % [ck.x, ck.y], ek.commit(mats, plain), 0.0, EXT_RANGE, false])
			meshes.append(["ExtShadow_%d_%d" % [ck.x, ck.y], ek.commit_shadow(["glass", "water", "lamp", "fire"]), 0.0, EXT_RANGE, true])
	for bk in inn:
		var ik: MeshKit = inn[bk]
		if not ik.is_empty():
			int_tris += ik.tris
			meshes.append(["Int_" + str(bk).get_file(), ik.commit(mats, plain), 0.0, INT_RANGE, false])
	var mms := []
	for bk in props:
		_multimesh_list(mms, props[bk], "IP_" + str(bk).get_file(), INT_RANGE, false)
	for ck in oprops:
		_multimesh_list(mms, oprops[ck], "OP_%d_%d" % [ck.x, ck.y], OPROP_RANGE, false)   # small: no shadow passes
	# door leaves: MultiMesh per (cell, mesh)
	var groups := {}
	for rec in recs:
		for dsp in rec.doors:
			for leaf in dsp.leaves:
				var mesh := _door_mesh(dsp.style, leaf.w, dsp.h, leaf.sign, dsp.col)
				var key := str(mesh.get_rid().get_id())       # one MultiMesh per door mesh for the whole town
				if not groups.has(key):
					groups[key] = {"mesh": mesh, "items": []}
				groups[key].items.append([dsp, leaf])
	var door_mms := []
	for key in groups:
		var g: Dictionary = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = g.mesh
		mm.instance_count = g.items.size()
		for i in g.items.size():
			var leaf2: Dictionary = g.items[i][1]
			var hx: Transform3D = leaf2.hinge
			hx.origin.y += g.items[i][0].get("bottom", 0.0)
			mm.set_instance_transform(i, hx)
			var dc: Color = g.items[i][0].col
			var plank: bool = str(g.items[i][0].style) in ["plank", "outhouse"]
			mm.set_instance_custom_data(i, Color(1, 1, 1, 0) if plank else Color(dc.r, dc.g, dc.b, 1.0))
		door_mms.append([mm, g.items])
	var spinners := []
	for rec in recs:
		for sp in rec.get("spinners", []):
			var kk: MeshKit = sp.kit
			spinners.append([kk.commit(mats, plain), sp.xf, sp.axis, sp.speed])
	tp["commit"] = Time.get_ticks_usec() - t2
	tp["total"] = Time.get_ticks_usec() - t0
	return {"recs": recs, "meshes": meshes, "mms": mms, "doors": door_mms, "spinners": spinners, "prof": tp,
		"ext_tris": ext_tris, "int_tris": int_tris}

func _multimesh_list(out: Array, dict: Dictionary, prefix: String, range_end: float, shadows: bool) -> void:
	for name in dict:
		var list: Array = dict[name]
		var mesh := TownProps.mesh(name)
		if mesh == null or list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		out.append([prefix + "_" + name, mm, range_end, shadows])

## Main-thread part: create nodes, collision, doors, lights; register records for the API.
func _attach(t: Dictionary, res: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var root := Node3D.new()
	root.name = "Detail"
	var surfaces := 0
	# kill-switches for GPU bisection (--disable town_interiors,town_props,town_lights,town_signs,town_doors,town_far,
	# town_people,town_probes,town_shadows,town_exterior,rail)
	var no_int := Game.disabled("town_interiors")
	var no_props := Game.disabled("town_props")
	var no_shadow := Game.disabled("town_shadows")
	var no_ext := Game.disabled("town_exterior")
	for m in res.meshes:
		var mesh: ArrayMesh = m[1]
		if mesh.get_surface_count() == 0:
			continue
		var mname := str(m[0])
		if (no_int and mname.begins_with("Int_")) or (no_shadow and m[4]) or (no_ext and mname.begins_with("Ext_")):
			continue
		# shadow casters: one position-only proxy per cell (SHADOWS_ONLY); the detailed mesh casts none
		var mi := _mesh_node(mesh, m[0], m[2], m[3], GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if m[4] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		if m[3] >= EXT_RANGE:
			mi.visibility_range_end_margin = 40.0
		if not m[4]:
			surfaces += mesh.get_surface_count()
		root.add_child(mi)
	for m in res.mms:
		surfaces += (m[1] as MultiMesh).mesh.get_surface_count()
	stats["surfaces"] = stats.get("surfaces", 0) + surfaces
	for m in res.mms:
		if no_props or (no_int and str(m[0]).begins_with("IP_")):
			continue
		var mmi := MultiMeshInstance3D.new()
		mmi.name = m[0]
		mmi.multimesh = m[1]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if m[3] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = m[2]
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mmi)
		stats.multimeshes += 1
	for sp in res.spinners:
		var wmi := MeshInstance3D.new()
		wmi.mesh = sp[0]
		wmi.transform = sp[1]
		wmi.visibility_range_end = 600.0
		wmi.name = "Wheel"
		root.add_child(wmi)
		_spinners.append([wmi, sp[2], sp[3]])
	var light_specs := []
	for rec in res.recs:
		if rec.boxes.size() > 0:
			var body := StaticBody3D.new()
			body.name = "B_" + str(rec.id).get_file()
			body.transform = rec.transform
			body.collision_layer = 1
			body.collision_mask = 0
			body.set_meta("building", rec.id)
			for b in rec.boxes:
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = b[1]
				cs.shape = bs
				cs.transform = b[0]
				body.add_child(cs)
			stats.shapes += rec.boxes.size()
			rec.body = body
			root.add_child(body)
		rec.erase("boxes")
		if rec.has("probe") and not Game.disabled("town_probes") and not no_int:
			var pr := ReflectionProbe.new()
			pr.name = "Probe"
			pr.transform = rec.transform * Transform3D(Basis.IDENTITY, rec.probe.center)
			pr.size = rec.probe.size
			pr.box_projection = true
			pr.interior = true
			pr.ambient_mode = ReflectionProbe.AMBIENT_COLOR
			pr.ambient_color = Color(0.42, 0.34, 0.26)
			pr.ambient_color_energy = 0.35
			pr.update_mode = ReflectionProbe.UPDATE_ONCE
			pr.max_distance = 40.0
			pr.blend_distance = 0.5
			root.add_child(pr)
			stats["probes"] = stats.get("probes", 0) + 1
		for l in rec.lights:
			l["always"] = rec.get("always_lit", false)
			light_specs.append(l)
		rec["door_specs"] = rec.doors
		rec.doors = rec.doors.map(func(x): return x.id)
		buildings[rec.id] = rec
		t.buildings.append(rec.id)
		t.spots.append_array(rec.spots)
		stats.buildings += 1
	for dm in ([] if Game.disabled("town_doors") else res.doors):
		var mm: MultiMesh = dm[0]
		var mmi2 := MultiMeshInstance3D.new()
		mmi2.multimesh = mm
		mmi2.visibility_range_end = DOOR_RANGE + float(t.radius)
		mmi2.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi2.name = "Doors"
		root.add_child(mmi2)
		stats.multimeshes += 1
		var items: Array = dm[1]
		for i in items.size():
			var dsp: Dictionary = items[i][0]
			var leaf: Dictionary = items[i][1]
			var d := TownDoor.new()
			d.door_id = dsp.id + ("" if leaf.sign > 0.0 else "b")
			d.building_id = dsp.building
			d.kind = dsp.kind
			d.hinge_sign = leaf.sign
			d.mm = mm
			d.mm_index = i
			var hx: Transform3D = leaf.hinge
			hx.origin.y += dsp.get("bottom", 0.0)
			d.transform = hx
			d.name = "Door"
			d.setup(leaf.w, dsp.h, dsp.thick, dsp.kind != "batwing")
			root.add_child(d)
			doors[d.door_id] = d
			t.doors.append(d.door_id)
			if dsp.leaves.size() == 2 and leaf.sign < 0.0 and doors.has(dsp.id):
				d.partner = doors[dsp.id]
				doors[dsp.id].partner = d
	if not Game.disabled("town_lights"):
		_make_lights(root, light_specs)
	# hitching rails: markers in the "hitching_post" group (horses auto-hitch within 5 m on dismount)
	for sp in t.spots:
		if sp.type == "hitch":
			var hp := Marker3D.new()
			hp.name = "HitchingPost"
			hp.transform = sp.transform
			hp.add_to_group("hitching_post")
			hp.set_meta("rail", sp.get("rail", sp.transform.origin))
			hp.set_meta("fronts", sp.get("fronts", ""))
			root.add_child(hp)
	# interiors per building: shown only while the camera is inside or within INT_NEAR of the footprint
	var by_num := {}
	for bid0 in t.buildings:
		by_num[str(bid0).get_file().get_slice("_", 0)] = bid0
	for n in root.get_children():
		var nm := str(n.name)
		if nm.begins_with("Int_") or nm.begins_with("IP_"):
			var bid: String = by_num.get(nm.get_slice("_", 1), "")
			if buildings.has(bid):
				if not buildings[bid].has("int_nodes"):
					buildings[bid]["int_nodes"] = []
				buildings[bid].int_nodes.append(n)
				n.visible = false
	t.node.add_child(root)
	t.detail = root
	t.state = "built"
	t["keep_until"] = Time.get_ticks_msec() + 180000     # built on demand (missions, places.gd): keep a while
	stats.built += 1
	stats.ext_tris += res.ext_tris
	stats.int_tris += res.int_tris
	var p: Dictionary = res.prof
	p["attach"] = Time.get_ticks_usec() - t0
	for k in p:
		prof[k] = prof.get(k, 0) + p[k]
	_update_lights(true)
	print("settlements: built %s: %d structures, tris ext %dk int %dk, %d surfaces (meshes + props), %d door meshes, build %d ms (commit %d), attach %d ms" % [t.id, res.recs.size(),
		res.ext_tris / 1000, res.int_tris / 1000, surfaces, res.doors.size(), p.total / 1000, p.commit / 1000, p.attach / 1000])
	mem("built " + str(t.id))
	town_built.emit(str(t.id))

func _mesh_node(mesh: ArrayMesh, nm: String, begin: float, end: float, shadow: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.cast_shadow = shadow
	mi.visibility_range_begin = begin
	mi.visibility_range_end = end
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if end > 0.0:
		mi.visibility_range_end_margin = 12.0
	stats.meshes += 1
	return mi

# ------------------------------------------------------------------------------------------------ streaming

func _stream() -> void:
	if _task >= 0:
		_finish_task(false)
		if _task >= 0:
			return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	for id in towns:
		var tu: Dictionary = towns[id]
		if tu.state == "built" and tu.nav_state != "baking" and _dist_to(tu, cp) > UNLOAD_DIST - BUILD_DIST \
				and Time.get_ticks_msec() > int(tu.get("keep_until", 0)) and not Game.args.has("settlements_test"):
			unload(id)
	var best := ""
	var bd := 0.0
	for id in towns:
		var t: Dictionary = towns[id]
		if t.state != "far":
			continue
		var d := _dist_to(t, cp)
		if d < 0.0 and (best == "" or d < bd):
			best = id
			bd = d
	if best == "":
		return
	var tb: Dictionary = towns[best]
	tb.state = "building"
	_task_town = best
	_task_result = {}
	var plan: Dictionary = tb.plan
	_task = WorkerThreadPool.add_task(func(): _task_result = _prepare(plan), false, "settlement " + best)

func _finish_task(block: bool) -> void:
	if _task < 0:
		return
	if not block and not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var t: Dictionary = towns[_task_town]
	_attach(t, _task_result)
	_task_result = {}

## Drop a built settlement's detail (meshes, props, colliders, doors, lights, navmesh, spot records); the plan,
## far shell and ground paint stay, and the town is rebuilt from the plan when Ruth comes back.
func unload(id: String) -> void:
	var t: Dictionary = towns.get(id, {})
	if t.is_empty() or t.state != "built" or t.detail == null:
		return
	var root: Node3D = t.detail
	_lights = _lights.filter(func(l): return is_instance_valid(l[0]) and not root.is_ancestor_of(l[0]))
	_spinners = _spinners.filter(func(sp): return is_instance_valid(sp[0]) and not root.is_ancestor_of(sp[0]))
	for did in t.doors:
		doors.erase(did)
	for bid in t.buildings:
		buildings.erase(bid)
	for n in t.nav_regions + t.get("nav_links", []):
		if is_instance_valid(n):
			n.queue_free()
	root.queue_free()
	t.detail = null
	t.buildings = []
	t.doors = []
	t.spots = []
	t.nav_regions = []
	t["nav_links"] = []
	t.nav_state = "none"
	t.state = "far"
	stats.built -= 1
	if Game.population and Game.population.has_method("forget_town"):
		Game.population.forget_town(id)
	print("settlements: unloaded %s" % id)

## Screenshot/bot hook: build (blocking) every settlement within range of the current camera.
func settle_now() -> void:
	_finish_task(true)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		for id in towns:
			if _dist_to(towns[id], cam.global_position) < 0.0:
				ensure_built(id)
	_update_lights(true)

# ------------------------------------------------------------------------------------------------ doors

## Door leaf mesh, uncoloured: the paint colour is MultiMesh instance custom data (building.gdshader), so every door
## of a style and size shares one mesh and one MultiMesh per town.
func _door_mesh(style: String, w: float, h: float, sgn: float, _col: Color) -> ArrayMesh:
	var col := Color.WHITE
	var key := "%s_%.2f_%.2f_%d" % [style, snappedf(w, 0.05), snappedf(h, 0.05), int(sgn)]
	_door_mutex.lock()
	var cached = _door_meshes.get(key)
	_door_mutex.unlock()
	if cached != null:
		return cached
	var k := MeshKit.new()
	k.ground = -100.0
	k.tint = Color(col.r, col.g, col.b, 0.3)
	var x0 := 0.0 if sgn > 0.0 else -w
	var x1 := w if sgn > 0.0 else 0.0
	var t := 0.05
	var dark := Color(col.r * 0.8, col.g * 0.8, col.b * 0.8, 0.3)
	match style:
		"plank", "outhouse":
			k.uv_rot = true
			k.tint = Color(0.9, 0.85, 0.8, 0.4)
			k.box("planks_v", Vector3(x0 + 0.01, 0.0, -t * 0.5), Vector3(x1 - 0.01, h, t * 0.5))
			k.uv_rot = false
			for yy: float in [0.25, h - 0.35]:
				k.box("planks_v", Vector3(x0 + 0.06, yy, -t * 0.5 - 0.025), Vector3(x1 - 0.06, yy + 0.14, -t * 0.5))
			k.beam("planks_v", Vector3(x0 + 0.12, 0.35, -t * 0.5 - 0.02), Vector3(x1 - 0.12, h - 0.35, -t * 0.5 - 0.02), 0.11, 0.02, Vector3(0, 0, -1))
			k.tint = Color(1, 1, 1, 0.4)
			for yy: float in [0.3, h - 0.3]:
				k.box("iron", Vector3(x0 + (0.0 if sgn > 0 else w - 0.45), yy - 0.025, -t * 0.5 - 0.035), Vector3(x0 + (0.45 if sgn > 0 else w), yy + 0.025, -t * 0.5 - 0.025))
			k.box("iron", Vector3(x1 - 0.12 if sgn > 0 else x0 + 0.08, 1.0, -t * 0.5 - 0.05), Vector3(x1 - 0.08 if sgn > 0 else x0 + 0.12, 1.12, -t * 0.5))
		"batwing":
			var fw := 0.06
			k.box("paint", Vector3(x0, 0.0, -0.025), Vector3(x0 + fw, h, 0.025))
			k.box("paint", Vector3(x1 - fw, 0.0, -0.025), Vector3(x1, h, 0.025))
			k.box("paint", Vector3(x0, 0.0, -0.025), Vector3(x1, 0.1, 0.025))
			k.box("paint", Vector3(x0, h - 0.12, -0.025), Vector3(x1, h, 0.025))
			k.tint = dark
			for i in 9:
				var yy2 := 0.14 + i * (h - 0.3) / 9.0
				k.obox("paint", Vector3((x0 + x1) * 0.5, yy2 + 0.05, 0.0), Vector3(w - fw * 2.0, 0.07, 0.012), Basis(Vector3.RIGHT, 0.6))
		_:
			var fw2 := 0.11
			k.box("paint", Vector3(x0, 0.0, -t * 0.5), Vector3(x0 + fw2, h, t * 0.5))
			k.box("paint", Vector3(x1 - fw2, 0.0, -t * 0.5), Vector3(x1, h, t * 0.5))
			k.box("paint", Vector3(x0 + fw2, 0.0, -t * 0.5), Vector3(x1 - fw2, 0.22, t * 0.5))
			k.box("paint", Vector3(x0 + fw2, h - 0.14, -t * 0.5), Vector3(x1 - fw2, h, t * 0.5))
			k.box("paint", Vector3(x0 + fw2, h * 0.45, -t * 0.5), Vector3(x1 - fw2, h * 0.45 + 0.14, t * 0.5))
			k.tint = dark
			k.box("paint", Vector3(x0 + fw2, 0.22, -t * 0.3), Vector3(x1 - fw2, h * 0.45, t * 0.3))
			if style == "glazed":
				k.tint = Color(0.5, 0.3, 0.0, 1.0)
				k.face("glass", Vector3(x0 + fw2, h * 0.45 + 0.14, 0.0), Vector3(x1 - x0 - fw2 * 2.0, 0, 0), Vector3(0, h - 0.14 - h * 0.45 - 0.14, 0))
				k.tint = Color(col.r, col.g, col.b, 0.3)
				k.box("paint", Vector3((x0 + x1) * 0.5 - 0.015, h * 0.45 + 0.14, -0.012), Vector3((x0 + x1) * 0.5 + 0.015, h - 0.14, 0.012))
			else:
				k.box("paint", Vector3(x0 + fw2, h * 0.45 + 0.14, -t * 0.3), Vector3(x1 - fw2, h - 0.14, t * 0.3))
				k.tint = Color(col.r, col.g, col.b, 0.3)
				k.box("paint", Vector3((x0 + x1) * 0.5 - 0.05, 0.22, -t * 0.5), Vector3((x0 + x1) * 0.5 + 0.05, h - 0.14, t * 0.5))
			k.tint = Color(1, 1, 1, 0.1)
			var kx := x1 - 0.09 if sgn > 0 else x0 + 0.09
			k.cyl("brass", Vector3(kx, 1.0, -t * 0.5), Vector3(kx, 1.0, -t * 0.5 - 0.06), 0.028, 8, true)
			k.cyl("brass", Vector3(kx, 1.0, t * 0.5), Vector3(kx, 1.0, t * 0.5 + 0.06), 0.028, 8, true)
	var mesh := k.commit(TownMats.get_all(), TownMats.plain_keys())
	_door_mutex.lock()
	_door_meshes[key] = mesh
	_door_mutex.unlock()
	return mesh

# ------------------------------------------------------------------------------------------------ lights

func _make_lights(parent: Node3D, specs: Array) -> void:
	var shadows := 0
	for l in specs:
		var o := OmniLight3D.new()
		o.position = l.pos
		o.omni_range = l.range
		o.light_color = l.color
		o.light_energy = 0.0
		o.light_specular = 0.35
		o.light_size = 0.08
		o.omni_attenuation = 1.4
		o.distance_fade_enabled = true
		o.distance_fade_begin = 45.0 if l.kind in ["interior", "stove"] else 80.0
		o.distance_fade_length = 20.0
		o.shadow_enabled = l.shadow and shadows < 2
		if o.shadow_enabled:
			shadows += 1
			o.distance_fade_shadow = 30.0
			o.shadow_bias = 0.05
		o.visible = false
		parent.add_child(o)
		_lights.append([o, float(l.energy), str(l.kind), randf() * TAU, bool(l.get("always", false))])
		stats.lights += 1

func _process(dt: float) -> void:
	_timer -= dt
	if _timer <= 0.0:
		_timer = 0.5
		_update_lights(false)
		_stream()
		_nav_auto()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_int_timer -= dt
	if _int_timer <= 0.0:
		_int_timer = 0.2
		_interiors(cam.global_position)
	var cp := cam.global_position
	var tt := Time.get_ticks_msec() * 0.001
	for l in _lights:
		var o: OmniLight3D = l[0]
		if not o.visible or (l[2] != "fire" and l[2] != "stove"):
			continue
		var f := 0.82 + 0.1 * sin(tt * 11.0 + l[3]) + 0.08 * sin(tt * 23.0 + l[3] * 2.0)
		o.light_energy = l[1] * f * (1.0 if l[4] else maxf(_night, 0.25))
	for s in _spinners:
		var n: Node3D = s[0]
		if n.global_position.distance_squared_to(cp) < 250000.0:
			n.rotate_object_local(s[1], s[2] * dt)

## Interior meshes and props of a building draw only while the camera is inside it or within INT_NEAR of its
## footprint (looking in through the door or a window); everything else in town is shell only.
func _interiors(cp: Vector3) -> void:
	for id in towns:
		var t: Dictionary = towns[id]
		if t.state != "built":
			continue
		var tc: Vector3 = t.center
		var near_town: bool = Vector2(cp.x - tc.x, cp.z - tc.z).length() < float(t.radius) + 60.0
		for bid in t.buildings:
			var b: Dictionary = buildings[bid]
			if not b.has("int_nodes"):
				continue
			var vis := false
			if near_town:
				var l: Vector3 = b.transform.affine_inverse() * cp
				var sz: Vector3 = b.size
				var dx := maxf(absf(l.x) - sz.x * 0.5, 0.0)
				var dz := maxf(maxf(-l.z, l.z - sz.z), 0.0)
				vis = dx * dx + dz * dz < INT_NEAR * INT_NEAR and absf(l.y) < 12.0
			if b.get("int_vis", false) != vis:
				b["int_vis"] = vis
				for n in b.int_nodes:
					if is_instance_valid(n):
						n.visible = vis

## Never leave a worker task running at teardown (an unwaited task aborts the process on exit).
func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func night_factor() -> float:
	var sky = Game.sky
	if sky == null:
		return 0.0
	var sd: Vector3 = sky.sun_direction()
	var n := clampf((0.07 - sd.y) / 0.12, 0.0, 1.0)
	var dark: float = sky.get("dark") if sky.get("dark") != null else 0.0
	return clampf(n + dark * 0.35, 0.0, 1.0)

func _update_lights(force: bool) -> void:
	var n := night_factor()
	if force or absf(n - _night) > 0.01:
		_night = n
		TownMats.set_lights(n)
	var cam := get_viewport().get_camera_3d()
	var cp := cam.global_position if cam != null else Vector3.ZERO
	for l in _lights:
		var o: OmniLight3D = l[0]
		var kind: String = l[2]
		var on: float
		match kind:
			"interior":
				on = lerpf(0.18, 1.0, n)        # interiors keep a dim fill by day (lamps, doorway bounce)
			"fire", "stove":
				on = 1.0 if l[4] else maxf(n, 0.25)
			_:
				on = n
		var near := o.global_position.distance_squared_to(cp) < LIGHT_CULL * LIGHT_CULL
		o.visible = near and on > 0.02
		if kind != "fire" and kind != "stove":
			o.light_energy = l[1] * on

# ------------------------------------------------------------------------------------------------ ground painting

## Streets, connectors and yards become trampled road dirt on the terrain control map (no grass there, which also
## keeps blades out of raised floors), and the worldgen road traces through the town core are cleared so only the
## planned streets show.
func _paint_ground(plan: Dictionary) -> void:
	var img: Image = world.control_image
	if img == null:
		return
	var res := world.ctrl_res
	var texel := world.size_m / res
	var fr: Transform3D = plan.frame
	var inv := fr.affine_inverse()
	var R: float = plan.radius
	var c := fr.origin
	var half := world.size_m * 0.5
	var x0 := clampi(int((c.x - R - 40.0 + half) / texel), 0, res - 1)
	var x1 := clampi(int((c.x + R + 40.0 + half) / texel), 0, res - 1)
	var z0 := clampi(int((c.z - R - 40.0 + half) / texel), 0, res - 1)
	var z1 := clampi(int((c.z + R + 40.0 + half) / texel), 0, res - 1)
	var streets: Array = plan.streets + plan.get("paint_lines", [])
	var core_out := R * 0.85
	var core_in := R * 0.6
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var lp := inv * Vector3((ix + 0.5) * texel - half, c.y, (iz + 0.5) * texel - half)
			var p := Vector2(lp.x, lp.z)
			var dc := p.length()
			if dc > R + 40.0:
				continue
			var road := 0.0
			for s in streets:
				var dd: float = TownLayout._seg_dist(p, s.a, s.b) - s.w * 0.5
				road = maxf(road, clampf((2.5 - dd) / 4.0, 0.0, 1.0))
			var col := img.get_pixel(ix, iz)
			var core := clampf((core_out - dc) / (core_out - core_in), 0.0, 1.0)
			col.r = maxf(road * 0.95, col.r * (1.0 - core))
			img.set_pixel(ix, iz, col)
	for spec in plan.specs:
		var st: String = spec.get("style", "")
		if st in ["street_kit", "bridge", "pier", "track", "bluff_stair"]:
			continue
		var bx: Transform3D = spec.xf
		var w: float = spec.get("w", 6.0) + 3.0
		var d: float = spec.get("d", 6.0) + 3.0
		var front: float = spec.get("porch", 0.0) + 1.5
		var lo := Vector2(INF, INF)
		var hi := -lo
		for q in [bx * Vector3(-w * 0.5, 0, -front), bx * Vector3(w * 0.5, 0, -front), bx * Vector3(w * 0.5, 0, d), bx * Vector3(-w * 0.5, 0, d)]:
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.z))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.z))
		var bi := bx.affine_inverse()
		for iz2 in range(maxi(int((lo.y + half) / texel), 0), mini(int((hi.y + half) / texel) + 1, res)):
			for ix2 in range(maxi(int((lo.x + half) / texel), 0), mini(int((hi.x + half) / texel) + 1, res)):
				var l2 := bi * Vector3((ix2 + 0.5) * texel - half, bx.origin.y, (iz2 + 0.5) * texel - half)
				if absf(l2.x) <= w * 0.5 + texel * 0.5 and l2.z >= -front - texel * 0.5 and l2.z <= d + texel * 0.5:
					var col2 := img.get_pixel(ix2, iz2)
					col2.r = maxf(col2.r, 0.7)
					img.set_pixel(ix2, iz2, col2)

## Push the painted control map to the CPU copy (world.ctrl) and the terrain/grass texture, once.
func _upload_control() -> void:
	var img: Image = world.control_image
	if img == null:
		return
	world.control = img.get_data()
	var tex = null
	if Game.terrain != null and Game.terrain.get("material") != null:
		tex = Game.terrain.material.get_shader_parameter("controlmap")
	if tex is ImageTexture:
		(tex as ImageTexture).update(img)

# ------------------------------------------------------------------------------------------------ API

func get_town(id: String) -> Dictionary:
	return towns.get(id, {})

const SHOP_TYPES := {"general": ["store", "trading_post", "tent_store"], "gunsmith": ["gunsmith"], "butcher": ["butcher"],
	"board": ["sheriff", "post"]}

## Where a shop's customer stands (inside at the counter), for main._place_shops: kind general|gunsmith|butcher.
## Works before the settlement is built (from the plan); returns null when the town has no such shop.
func get_shop_spot(town_id: String, kind: String):
	var t: Dictionary = towns.get(town_id, {})
	if t.is_empty():
		return null
	var types: Array = SHOP_TYPES.get(kind, [kind])
	for spec in t.plan.specs:
		if not str(spec.get("type", "")) in types:
			continue
		var bid: String = spec.id
		if kind == "board":                       # notice board on the boardwalk beside the door
			return spec.xf * Vector3(float(spec.get("w", 8.0)) * 0.5 - 0.8, 0.0, -1.2)
		if buildings.has(bid):
			for sp in buildings[bid].spots:
				if sp.type == "shop_counter":
					return sp.transform.origin
		var w: float = spec.get("w", 8.0)
		var local := Vector3(0.0, 0.0, 2.7)
		if str(spec.type) == "store":
			local = Vector3(w * 0.5 - 2.25, 0.0, 2.75)
		return spec.xf * local
	return null

func town_ids() -> Array:
	return towns.keys()

func get_building(id: String) -> Dictionary:
	return buildings.get(id, {})

func door(id: String) -> TownDoor:
	return doors.get(id)

func spots(town_id: String, type := "") -> Array:
	var t: Dictionary = towns.get(town_id, {})
	if t.is_empty():
		return []
	if type == "":
		return t.spots
	return t.spots.filter(func(s): return s.type == type)

func nearest_spot(pos: Vector3, type: String, max_dist := 60.0) -> Dictionary:
	var best := {}
	var bd := max_dist * max_dist
	var tid := town_at(pos, 200.0)
	var pool: Array = spots(tid) if tid != "" else []
	for s in pool:
		if type != "" and s.type != type:
			continue
		var d: float = s.transform.origin.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = s
	return best

func nearest_door(pos: Vector3, max_dist := 2.5) -> TownDoor:
	var best: TownDoor = null
	var bd := max_dist * max_dist
	var tid := town_at(pos, 200.0)
	if tid == "":
		return null
	for id in towns[tid].doors:
		var d: TownDoor = doors[id]
		var c := d.global_transform * Vector3(d.width * 0.5 * d.hinge_sign, 1.0, 0.0)
		var dist := c.distance_squared_to(pos)
		if dist < bd:
			bd = dist
			best = d
	return best

func interact_nearest(pos: Vector3, max_dist := 2.5) -> bool:
	var d := nearest_door(pos, max_dist)
	if d == null:
		return false
	d.interact(pos)
	return true

func town_at(pos: Vector3, margin := 30.0) -> String:
	for id in towns:
		var t: Dictionary = towns[id]
		var c: Vector3 = t.center
		if Vector2(pos.x - c.x, pos.z - c.z).length() < t.radius + margin:
			return id
	return ""

func building_at(pos: Vector3) -> String:
	var tid := town_at(pos, 20.0)
	if tid == "":
		return ""
	for bid in towns[tid].buildings:
		var b: Dictionary = buildings[bid]
		if not b.enterable:
			continue
		var l: Vector3 = b.transform.affine_inverse() * pos
		var s: Vector3 = b.size
		if absf(l.x) < s.x * 0.5 and l.z > 0.0 and l.z < s.z and l.y > -0.5 and l.y < 12.0:
			return bid
	return ""

# ------------------------------------------------------------------------------------------------ navigation

func navigation_ready(town_id: String) -> bool:
	return towns.get(town_id, {}).get("nav_state", "") == "ready"

func _nav_auto() -> void:
	var p: Node3D = Game.player
	if p == null:
		return
	var tid := town_at(p.global_position, NAV_AUTO_DIST)
	if tid != "" and towns[tid].nav_state == "none" and towns[tid].state == "built":
		bake_navigation(tid)

## Bake the town's navigation mesh in 64 m chunks (one NavigationRegion3D each; edges merge in the map) from the
## settlement colliders and the terrain inside the town disc, on the NavigationServer worker threads.
func bake_navigation(town_id: String) -> void:
	var t: Dictionary = towns.get(town_id, {})
	if t.is_empty() or t.nav_state != "none":
		return
	ensure_built(town_id)
	t.nav_state = "baking"
	var src := NavigationMeshSourceGeometryData3D.new()
	_nav_ground(src, t)
	for bid in t.buildings:
		var body: StaticBody3D = buildings[bid].body
		if body == null:
			continue
		for cs in body.get_children():
			if cs is CollisionShape3D and cs.shape is BoxShape3D:
				src.add_faces(_box_faces((cs.shape as BoxShape3D).size), body.transform * cs.transform)
	var c: Vector3 = t.center
	var R: float = t.radius + 20.0
	var n := int(ceil(R * 2.0 / NAV_CHUNK))
	var jobs := []
	for i in n:
		for j in n:
			var x0: float = floorf(c.x - R) + i * NAV_CHUNK
			var z0: float = floorf(c.z - R) + j * NAV_CHUNK
			if Vector2(x0 + NAV_CHUNK * 0.5 - c.x, z0 + NAV_CHUNK * 0.5 - c.z).length() > R + NAV_CHUNK * 0.7:
				continue
			# the bake area includes the border that Recast trims, so neighbouring chunks meet edge to edge
			jobs.append(AABB(Vector3(x0 - 1.0, c.y - 40.0, z0 - 1.0), Vector3(NAV_CHUNK + 2.0, 80.0, NAV_CHUNK + 2.0)))
	# doorways: a two-way NavigationLink3D from 0.9 m outside to 0.9 m inside every door (narrow, often oblique
	# openings don't survive voxelisation at agent radius 0.25 reliably; links make every room reachable)
	var links := 0
	for bid in t.buildings:
		var b: Dictionary = buildings[bid]
		if str(b.type) == "outhouse":
			continue
		for dsp in b.get("door_specs", []):
			if not dsp.has("outside"):
				continue
			var ln := NavigationLink3D.new()
			ln.name = "DoorLink"
			ln.bidirectional = true
			ln.start_position = dsp.outside + Vector3(0, 0.05, 0)
			ln.end_position = dsp.inside + Vector3(0, 0.05, 0)
			t.node.add_child(ln)
			t["nav_links"] = t.get("nav_links", []) + [ln]
			links += 1
	t["links"] = links
	t["nav_jobs"] = jobs.size()
	t["nav_done"] = 0
	t["nav_t0"] = Time.get_ticks_msec()
	# at most NAV_PARALLEL chunks in flight (each bake holds its own voxel field: memory, and cores for the game)
	t["nav_queue"] = jobs
	t["nav_src"] = src
	for i in mini(NAV_PARALLEL, jobs.size()):
		_nav_next(t)

## Blocking bake of a town's navmesh on the calling thread (screenshots with a slow frame rate, tests).
func bake_navigation_now(town_id: String) -> void:
	var t: Dictionary = towns.get(town_id, {})
	if t.is_empty():
		return
	if t.nav_state == "none":
		bake_navigation(town_id)
	var q: Array = t.get("nav_queue", [])
	t["nav_sync"] = true
	while not q.is_empty():
		var nm := _nav_mesh_for(q.pop_front())
		NavigationServer3D.bake_from_source_geometry_data(nm, t.nav_src)
		_nav_chunk_done(t, nm)
	t["nav_sync"] = false

func _nav_mesh_for(box: AABB) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.25
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 38.0
	nm.border_size = 1.0
	nm.filter_baking_aabb = box
	nm.region_min_size = 4.0
	return nm

func _nav_next(t: Dictionary) -> void:
	var q: Array = t.get("nav_queue", [])
	if q.is_empty() or t.state != "built":
		return
	var box: AABB = q.pop_front()
	var src: NavigationMeshSourceGeometryData3D = t.nav_src
	if true:
		var nm := _nav_mesh_for(box)
		NavigationServer3D.bake_from_source_geometry_data_async(nm, src, func(): _nav_chunk_done.call_deferred(t, nm))

func _nav_chunk_done(t: Dictionary, nm: NavigationMesh) -> void:
	if t.state != "built":
		return
	if not t.get("nav_sync", false):
		_nav_next(t)
	if nm.get_polygon_count() > 0:
		var reg := NavigationRegion3D.new()
		reg.name = "Nav"
		reg.navigation_mesh = nm
		t.node.add_child(reg)
		t.nav_regions.append(reg)
	t.nav_done += 1
	if t.nav_done >= t.nav_jobs:
		t.nav_state = "ready"
		t.erase("nav_src")
		mem("navmesh " + str(t.id))
		print("settlements: navigation for %s baked in %d chunks, %d ms" % [t.id, t.nav_jobs, Time.get_ticks_msec() - t.nav_t0])

func _nav_ground(src: NavigationMeshSourceGeometryData3D, t: Dictionary) -> void:
	var c: Vector3 = t.center
	var R: float = t.radius + 20.0
	var step := 2.0
	var n := int(R * 2.0 / step)
	var faces := PackedVector3Array()
	for i in n:
		for j in n:
			var x := c.x - R + i * step
			var z := c.z - R + j * step
			if Vector2(x + step * 0.5 - c.x, z + step * 0.5 - c.z).length() > R:
				continue
			if world.is_water(x + step * 0.5, z + step * 0.5):
				continue
			var a := Vector3(x, world.height(x, z), z)
			var b := Vector3(x + step, world.height(x + step, z), z)
			var cc := Vector3(x + step, world.height(x + step, z + step), z + step)
			var d := Vector3(x, world.height(x, z + step), z + step)
			faces.append_array(PackedVector3Array([a, b, cc, a, cc, d]))     # Godot winding (clockwise from above)
	src.add_faces(faces, Transform3D.IDENTITY)

## --memtest: clean before/after memory deltas for building, baking and unloading Bitter Spring, then quit.
func _mem_test() -> void:
	Game.args["memlog"] = true
	for i in 240:
		await get_tree().process_frame
	mem("idle after boot")
	for id in towns.keys():
		if towns[id].state == "built":
			unload(id)
	for i in 30:
		await get_tree().process_frame
	mem("all unloaded")
	ensure_built("bitter_spring")
	for i in 30:
		await get_tree().process_frame
	mem("bitter_spring built")
	bake_navigation("bitter_spring")
	while towns["bitter_spring"].nav_state != "ready":
		await get_tree().process_frame
	for i in 30:
		await get_tree().process_frame
	mem("bitter_spring navmesh")
	unload("bitter_spring")
	for i in 60:
		await get_tree().process_frame
	mem("bitter_spring unloaded")
	ensure_built("bitter_spring")
	for i in 30:
		await get_tree().process_frame
	mem("bitter_spring rebuilt")
	get_tree().quit(0)

## --navcheck: every standing spot of the town must be on the navmesh and reachable from the main street.
func _nav_check(tid: String, map_rid: RID) -> void:
	var t: Dictionary = towns[tid]
	var start := NavigationServer3D.map_get_closest_point(map_rid, t.center + Vector3(0, 2, 0))
	var bad := {}
	var total := 0
	for sp in t.spots:
		if sp.has("lie_height") or str(sp.type) in ["hitch", "trough", "corral", "stall", "water_tower", "balcony", "balcony_door"]:
			continue
		var o: Vector3 = sp.transform.origin
		if o.y - buildings[sp.building].floor_y > 1.2:
			continue
		total += 1
		var cp := NavigationServer3D.map_get_closest_point(map_rid, o + Vector3(0, 0.3, 0))
		var path := NavigationServer3D.map_get_path(map_rid, start, o, true)
		var end_d: float = path[path.size() - 1].distance_to(o) if path.size() > 0 else 99.0
		var off := Vector2(cp.x - o.x, cp.z - o.z).length()
		if off > 0.35 or end_d > 0.6:
			var k := "%s/%s" % [str(sp.building).get_file(), sp.type]
			bad[k] = "off %.2f end %.2f" % [off, end_d]
	print("navcheck %s: %d of %d ground-floor spots unreachable" % [tid, bad.size(), total])
	for k in bad:
		print("  ", k, " ", bad[k])

static func _box_faces(s: Vector3) -> PackedVector3Array:
	var h := s * 0.5
	var v := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var idx := [4, 5, 6, 4, 6, 7, 0, 2, 1, 0, 3, 2, 0, 1, 5, 0, 5, 4, 2, 3, 7, 2, 7, 6, 1, 2, 6, 1, 6, 5, 3, 0, 4, 3, 4, 7]
	var out := PackedVector3Array()
	for i in idx:
		out.append(v[i])
	return out

# ------------------------------------------------------------------------------------------------ self test

## --settlements_test [--build all|<id>] [--nav <town>]: build, print per-settlement summaries and the profile,
## optionally bake a navmesh and path from a door to the bartender, then quit.
func _self_test() -> void:
	var which := str(Game.args.get("build", "all"))
	var t0 := Time.get_ticks_msec()
	for id in towns:
		if which == "all" or which.split(",").has(id):
			ensure_built(id)
	print("settlements: test build %d ms; %d buildings, %d meshes, %d multimeshes, %d lights, %d shapes, tris ext %d int %d far %d" % [
		Time.get_ticks_msec() - t0, stats.buildings, stats.meshes, stats.multimeshes, stats.lights, stats.shapes, stats.ext_tris, stats.int_tris, stats.far_tris])
	var keys := prof.keys()
	keys.sort_custom(func(a, b): return prof[a] > prof[b])
	var parts := []
	for k in keys:
		parts.append("%s %d" % [k, prof[k] / 1000])
	print("settlements: profile ms: ", ", ".join(parts), "; prop loading %d ms" % (TownProps.load_usec / 1000))
	for id in towns:
		var t: Dictionary = towns[id]
		if t.state != "built":
			continue
		var types := {}
		for bid in t.buildings:
			var ty: String = buildings[bid].type
			types[ty] = types.get(ty, 0) + 1
		var st := {}
		for s in t.spots:
			st[s.type] = st.get(s.type, 0) + 1
		print("town %s: %d structures %s, %d doors, %d spots %s" % [id, t.buildings.size(), str(types), t.doors.size(), t.spots.size(), str(st)])
		var fronted := {}
		for sp in t.spots:
			if sp.type == "hitch" and str(sp.get("fronts", "")) != "":
				fronted[sp.fronts] = true
		var unhitched := []
		for bid in t.buildings:
			if str(buildings[bid].type) in ["saloon", "store", "cantina"] and not fronted.has(bid):
				unhitched.append(str(bid).get_file())
		print("  hitching rails: %d saloons/stores served, without one: %s; depot: %s" % [fronted.size(), str(unhitched),
			str(types.has("depot"))])
		if Game.args.has("list"):
			for bid in t.buildings:
				var b: Dictionary = buildings[bid]
				var o: Vector3 = b.transform.origin
				var fwd: Vector3 = -b.transform.basis.z
				print("  %-34s %8.1f %6.1f %8.1f  faces yaw %4.0f  w %.1f d %.1f" % [bid, o.x, o.y, o.z, rad_to_deg(atan2(fwd.x, -fwd.z)), b.size.x, b.size.z])
				var sts := {}
				for s in b.spots:
					sts[s.type] = sts.get(s.type, 0) + 1
				print("      role %s hours %s rooms %d spots %s" % [b.role, str(b.hours), b.rooms.size(), str(sts)])
	var nav_town := str(Game.args.get("nav", ""))
	if nav_town != "" and towns.has(nav_town):
		bake_navigation(nav_town)
		var t1 := Time.get_ticks_msec()
		while towns[nav_town].nav_state != "ready" and Time.get_ticks_msec() - t1 < 300000:
			await get_tree().process_frame
		var polys := 0
		for reg in towns[nav_town].nav_regions:
			polys += reg.navigation_mesh.get_polygon_count()
		print("nav %s: %s, %d polygons" % [nav_town, towns[nav_town].nav_state, polys])
		var map_rid := get_world_3d().navigation_map
		var it0 := NavigationServer3D.map_get_iteration_id(map_rid)
		for i in 120:
			await get_tree().physics_frame
			if i > 10 and NavigationServer3D.map_get_iteration_id(map_rid) != it0:
				break
		for i in 10:
			await get_tree().physics_frame
		print("nav map: %d regions, iteration %d" % [NavigationServer3D.map_get_regions(map_rid).size(), NavigationServer3D.map_get_iteration_id(map_rid)])
		if Game.args.has("navcheck"):
			_nav_check(nav_town, map_rid)
		var bl := spots(nav_town, "bartender")
		var dd := spots(nav_town, "door_out")
		if bl.size() > 0 and dd.size() > 0:
			for k in [0, dd.size() / 2, dd.size() - 1]:
				var a: Vector3 = dd[k].transform.origin
				var b: Vector3 = bl[0].transform.origin
				var path := NavigationServer3D.map_get_path(map_rid, a, b, true)
				var L := 0.0
				for i in range(1, path.size()):
					L += path[i].distance_to(path[i - 1])
				print("nav path %s -> bartender: %d points, %.1f m, ends %.2f m from goal" % [dd[k].building, path.size(), L,
					path[path.size() - 1].distance_to(b) if path.size() > 0 else -1.0])
	get_tree().quit(0)
