class_name WeaponModel
extends Node3D
## The visible firearm for one weapon id (src/combat/weapons.gd). Loads the generated glb
## (assets/ext/weapons/<id>.glb from the frontier-assets release, or assets/weapons_out/<id>.glb from a local
## `tools/weapons/gun_gen.py` run) and animates its named parts; if no glb exists a procedural stand-in with the
## same nodes and markers is built so the game never breaks.
##
## Origin = right-hand grip point; the barrel points along -Z, +Y up, +X the gun's right side.
## Animated parts (glb extras `anim` = {type rot|slide|bolt, axis, open, rot_axis, rot, steps}):
##   hammer/hammer_r/hammer_l, trigger, cylinder, lever, bolt, breech, barrels, loading_gate, pump, ejector_rod,
##   ejector, top_lever. Markers: muzzle, grip_r, grip_l, sight_rear, sight_front, holster_attach, shell_eject.
##
## API: create(id) · fire_anim() · reload_anim(step) (0 = open, 1.. = each round, -1 = close) · cock(bool)
##      muzzle_transform() · grip_transform(name) · marker(name) · set_detail(high)

signal ejected(shell: String, xform: Transform3D)

const SEARCH := ["res://assets/ext/weapons/%s.glb", "res://assets/weapons_out/%s.glb"]
## Casing per ammo type (fed to WeaponFX.casing)
const SHELLS := {"revolver": "pistol", "repeater": "pistol", "rifle": "rifle", "varmint": "rimfire", "shotgun": "shotgun"}

var weapon_id := ""
var def: Dictionary = {}
var action := "single"
var is_standin := false
var high_detail := true
var lod0: Node3D                 # "<id>" node (animated parts + markers)
var lod1: Node3D                 # "<id>_lod1" merged mesh (may be null)
var parts := {}                  # name -> {node, rest: Transform3D, anim: Dictionary}
var markers := {}                # name -> Node3D
var cylinder_index := 0.0        # cumulative cylinder steps (revolvers); the "_cyl" channel follows it
var spent := 0                   # fired cases still in the cylinder (ejected on reload)
var barrel_fired := 0            # break-action: barrels fired since the last reload
var _kick: Node3D                # recoil pivot (at the grip)
var _ch := {}                    # channel -> 0..1
var _tracks: Array = []          # [t0, t1, channel, from(or NAN), to]
var _events: Array = []          # [t, Callable]
var _t := 0.0
var _rec_x := 0.0                # recoil spring state (0..1 scaled by the weapon's recoil)
var _rec_v := 0.0

static var _cache := {}          # path -> PackedScene (runtime glTF loads are cached too)

static func create(id: String, finish := "") -> WeaponModel:
	var m := WeaponModel.new()
	m.name = "Weapon_" + id
	m.setup(id, finish)
	return m

func setup(id: String, finish := "") -> void:
	weapon_id = id
	def = Weapons.get_def(id)
	action = def.get("action", "single")
	_kick = Node3D.new()
	_kick.name = "Kick"
	add_child(_kick)
	var scene := _load_scene(id + ("_" + finish if finish != "" else ""))
	if scene == null and finish != "":
		scene = _load_scene(id)
	var inst: Node3D = null
	if scene != null:
		inst = scene.instantiate()
	if inst == null:
		inst = _build_standin()
		is_standin = true
	_kick.add_child(inst)
	lod0 = inst.find_child(id, true, false) as Node3D
	if lod0 == null:
		lod0 = inst
	lod1 = inst.find_child(id + "_lod1", true, false) as Node3D
	_index(lod0)
	if lod1 != null:
		lod1.visible = false
	for k in parts:
		_ch[k] = 0.0
	_ch["bolt_rot"] = 0.0
	# guns are carried cocked/closed: single actions and lever guns show the hammer back when drawn
	set_process(true)

static func _load_scene(file: String) -> PackedScene:
	for pat in SEARCH:
		var p: String = pat % file
		if _cache.has(p):
			return _cache[p]
		if ResourceLoader.exists(p):
			var ps = load(p)
			if ps is PackedScene:
				_cache[p] = ps
				return ps
		# un-imported glb (e.g. a fresh generator run before the editor imported it): load at runtime
		var abs_path := ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs_path):
			var doc := GLTFDocument.new()
			var st := GLTFState.new()
			if doc.append_from_file(abs_path, st) == OK:
				var root := doc.generate_scene(st)
				if root != null:
					var ps2 := PackedScene.new()
					_own(root, root)
					ps2.pack(root)
					root.free()
					_cache[p] = ps2
					return ps2
	return null

static func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_own(c, owner_node)

func _index(root: Node) -> void:
	for c in root.get_children():
		var n := c as Node3D
		if n == null:
			continue
		var ex = n.get_meta("extras", {}) if n.has_meta("extras") else {}
		if typeof(ex) == TYPE_DICTIONARY and ex.has("anim"):
			parts[String(n.name)] = {"node": n, "rest": n.transform, "anim": ex["anim"]}
			_index(n)                                   # nested parts (e.g. cylinder on a top-break barrel)
		elif String(n.name) in ["muzzle", "grip_r", "grip_l", "sight_rear", "sight_front", "holster_attach", "shell_eject"]:
			markers[String(n.name)] = n
		elif String(n.name) != "body" and _default_anim(String(n.name)).size() > 0:
			parts[String(n.name)] = {"node": n, "rest": n.transform, "anim": _default_anim(String(n.name))}

## Fallback animation parameters when a glb lacks extras (Godot axes).
func _default_anim(part: String) -> Dictionary:
	match part:
		"hammer", "hammer_r", "hammer_l": return {"type": "rot", "axis": [1, 0, 0], "open": 45.0}
		"trigger", "trigger_2": return {"type": "rot", "axis": [1, 0, 0], "open": -12.0}
		"cylinder": return {"type": "rot", "axis": [0, 0, 1], "open": -60.0, "steps": 6}
		"lever": return {"type": "rot", "axis": [1, 0, 0], "open": 48.0}
		"bolt": return {"type": "bolt", "axis": [0, 0, 1], "open": 0.07, "rot_axis": [0, 0, 1], "rot": 80.0}
		"pump": return {"type": "slide", "axis": [0, 0, 1], "open": 0.09}
		"barrels": return {"type": "rot", "axis": [1, 0, 0], "open": -40.0}
		"loading_gate": return {"type": "rot", "axis": [0, 0, 1], "open": -85.0}
	return {}

# ----------------------------------------------------------------------------------------------- queries
func marker(n: String) -> Node3D:
	return markers.get(n)

func muzzle_transform() -> Transform3D:
	var m: Node3D = markers.get("muzzle")
	if m != null and m.is_inside_tree():
		return m.global_transform
	return global_transform.translated_local(Vector3(0, 0.03, -0.3))

## Local (model-space) transform of a marker relative to this node's origin, ignoring recoil.
func marker_local(n: String) -> Transform3D:
	var m: Node3D = markers.get(n)
	if m == null:
		return Transform3D.IDENTITY
	var t := m.transform
	var p := m.get_parent() as Node3D
	while p != null and p != _kick:
		t = p.transform * t
		p = p.get_parent() as Node3D
	return t

func grip_transform(n := "grip_r") -> Transform3D:
	var m: Node3D = markers.get(n)
	return m.global_transform if m != null and m.is_inside_tree() else global_transform

func set_detail(high: bool) -> void:
	if high == high_detail or lod1 == null:
		return
	high_detail = high
	lod1.visible = not high
	for c in lod0.get_children():
		if c is MeshInstance3D:
			c.visible = high

# ----------------------------------------------------------------------------------------------- timeline
func _key(ch: String, t0: float, t1: float, to: float, from := NAN) -> void:
	_tracks.append([_t + t0, _t + maxf(t1, t0 + 0.001), ch, from, to])

func _at(t: float, f: Callable) -> void:
	_events.append([_t + t, f])

func has_part(n: String) -> bool:
	return parts.has(n)

func _process(dt: float) -> void:
	_t += dt
	# tracks
	var i := 0
	while i < _tracks.size():
		var tr: Array = _tracks[i]
		if _t >= tr[0]:
			if is_nan(tr[3]):
				tr[3] = _ch.get(tr[2], 0.0)
			var u := clampf((_t - tr[0]) / (tr[1] - tr[0]), 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			_ch[tr[2]] = lerpf(tr[3], tr[4], u)
			if _t >= tr[1]:
				_tracks.remove_at(i)
				continue
		i += 1
	i = 0
	while i < _events.size():
		if _t >= _events[i][0]:
			var f: Callable = _events[i][1]
			_events.remove_at(i)
			f.call()
			continue
		i += 1
	# recoil spring (stiff, slightly under-damped)
	var k := 520.0
	var c := 2.0 * sqrt(k) * 0.62
	_rec_v += (-k * _rec_x - c * _rec_v) * dt
	_rec_x += _rec_v * dt
	var r: float = def.get("recoil", 4.0)
	var heavy := 1.0 if def.get("slot", "") == "sidearm" else 0.55
	_kick.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(r * 2.6 * heavy) * _rec_x),
		Vector3(0, 0.004 * _rec_x, 0.012 * r * 0.18 * _rec_x))
	_apply()

func _apply() -> void:
	for n in parts:
		var p: Dictionary = parts[n]
		var a: Dictionary = p.anim
		var node: Node3D = p.node
		var v: float = _ch.get(n, 0.0)
		var ax := _v3(a.get("axis", [1, 0, 0]))
		match String(a.get("type", "rot")):
			"rot":
				var ang := float(a.get("open", 0.0)) * v
				if n == "cylinder":
					ang = float(a.get("open", 60.0)) * float(_ch.get("_cyl", 0.0))
				node.transform = p.rest * Transform3D(Basis(ax, deg_to_rad(ang)), Vector3.ZERO)
			"slide":
				node.transform = p.rest.translated_local(ax * float(a.get("open", 0.0)) * v)
			"bolt":
				var rax := _v3(a.get("rot_axis", [0, 0, 1]))
				var rot := float(a.get("rot", 80.0)) * float(_ch.get("bolt_rot", 0.0))
				node.transform = p.rest.translated_local(ax * float(a.get("open", 0.07)) * v) * Transform3D(Basis(rax, deg_to_rad(rot)), Vector3.ZERO)

## Set channels directly (0..1 per part name, plus "bolt_rot") and apply — for previews and VR hands.
func pose(ch: Dictionary) -> void:
	for k in ch:
		_ch[k] = float(ch[k])
	_apply()

## Everything open/cocked (action study pose).
func pose_open() -> void:
	var ch := {"bolt_rot": 1.0}
	for k in parts:
		if k != "cylinder" and k != "trigger" and k != "trigger_2":
			ch[k] = 1.0
	pose(ch)

static func _v3(a) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), float(a[1]), float(a[2])).normalized()

func _hammers() -> Array:
	var out := []
	for h in ["hammer", "hammer_r", "hammer_l"]:
		if parts.has(h):
			out.append(h)
	return out

# ----------------------------------------------------------------------------------------------- actions
## Show the gun ready to fire (hammer back on single actions / lever guns / exposed hammers) or relaxed.
func cock(ready: bool) -> void:
	for h in _hammers():
		if action in ["single", "lever", "pump", "break"]:
			_key(h, 0.0, 0.18, 1.0 if ready else 0.0)

## One shot: trigger, hammer fall, recoil kick, then the action cycles with the weapon's cock_time.
func fire_anim() -> void:
	var ct: float = def.get("cock_time", 0.5)
	_rec_v += 9.0
	var trig := "trigger"
	if action == "break":
		trig = "trigger" if barrel_fired % 2 == 0 else ("trigger_2" if parts.has("trigger_2") else "trigger")
	_key(trig, 0.0, 0.03, 1.0, 0.0)
	_key(trig, 0.08, 0.08 + ct * 0.4, 0.0)
	var hs := _hammers()
	match action:
		"single":
			if hs.size() > 0:
				_key(hs[0], 0.0, 0.025, 0.0, 1.0)
			spent += 1
			if parts.has("breech"):
				pass                                  # rolling block: hammer stays down until reload
			elif hs.size() > 0:
				_key(hs[0], ct * 0.25, ct * 0.8, 1.0)  # thumb the hammer back...
				_cyl_step(ct * 0.25, ct * 0.8)         # ...which turns the cylinder
		"double":
			if hs.size() > 0:
				_key(hs[0], 0.0, 0.025, 0.0, 1.0)
			spent += 1
			_cyl_step(0.06, ct * 0.7)
		"lever":
			if hs.size() > 0:
				_key(hs[0], 0.0, 0.025, 0.0, 1.0)
			_cycle_lever(ct * 0.15, ct)
		"bolt":
			_cycle_bolt(ct * 0.12, ct)
		"pump":
			if hs.size() > 0:
				_key(hs[0], 0.0, 0.025, 0.0, 1.0)
			_cycle_pump(ct * 0.18, ct)
		"break":
			var h := "hammer_r" if barrel_fired % 2 == 0 else "hammer_l"
			if parts.has(h):
				_key(h, 0.0, 0.025, 0.0, 1.0)
			elif hs.size() > 0:
				_key(hs[0], 0.0, 0.025, 0.0, 1.0)
			barrel_fired += 1

func _cyl_step(t0: float, t1: float) -> void:
	if not parts.has("cylinder"):
		return
	cylinder_index += 1.0                        # target; the "_cyl" channel animates toward it
	_key("_cyl", t0, t1, cylinder_index)

func _cycle_lever(t0: float, ct: float) -> void:
	var d := (ct - t0)
	_key("lever", t0, t0 + d * 0.38, 1.0)
	_key("bolt", t0, t0 + d * 0.38, 1.0)
	for h in _hammers():
		_key(h, t0 + d * 0.05, t0 + d * 0.38, 1.0)
	_at(t0 + d * 0.34, _eject)
	_key("lever", t0 + d * 0.5, t0 + d * 0.88, 0.0)
	_key("bolt", t0 + d * 0.5, t0 + d * 0.88, 0.0)

func _cycle_bolt(t0: float, ct: float) -> void:
	var d := (ct - t0)
	_key("bolt_rot", t0, t0 + d * 0.16, 1.0)
	_key("bolt", t0 + d * 0.18, t0 + d * 0.42, 1.0)
	_at(t0 + d * 0.4, _eject)
	_key("bolt", t0 + d * 0.55, t0 + d * 0.78, 0.0)
	_key("bolt_rot", t0 + d * 0.8, t0 + d * 0.94, 0.0)

func _cycle_pump(t0: float, ct: float) -> void:
	var d := (ct - t0)
	_key("pump", t0, t0 + d * 0.36, 1.0)
	_key("bolt", t0, t0 + d * 0.36, 1.0)
	_key("bolt", t0 + d * 0.5, t0 + d * 0.85, 0.0)
	for h in _hammers():
		_key(h, t0 + d * 0.05, t0 + d * 0.36, 1.0)
	_at(t0 + d * 0.32, _eject)
	_key("pump", t0 + d * 0.5, t0 + d * 0.85, 0.0)

func _eject() -> void:
	var m: Node3D = markers.get("shell_eject")
	if m != null and m.is_inside_tree():
		ejected.emit(SHELLS.get(def.get("ammo", "revolver"), "pistol"), m.global_transform)

## Reload choreography per action. step 0 = start (open), n >= 1 = round n loaded, -1 = finished (close).
func reload_anim(step: int) -> void:
	var each: float = def.get("reload_each", def.get("reload_all", 0.6))
	match action:
		"single", "double":
			if parts.has("barrels"):                       # top-break: open, auto-eject all, close at the end
				if step == 0:
					_key("barrels", 0.0, 0.28, 1.0)
					if parts.has("ejector"):
						_key("ejector", 0.22, 0.32, 1.0)
						_key("ejector", 0.36, 0.5, 0.0)
					for i in maxi(spent, 1):
						_at(0.25 + i * 0.015, _eject)
					spent = 0
				elif step < 0:
					_key("barrels", 0.0, 0.22, 0.0)
				return
			if parts.has("breech"):                        # rolling block
				if step == 0:
					for h in _hammers():
						_key(h, 0.0, 0.25, 1.0)
					_key("breech", 0.28, 0.45, 1.0)
					_at(0.42, _eject)
				elif step < 0:
					_key("breech", 0.0, 0.18, 0.0)
				return
			# loading gate revolvers: gate open + half cock, punch out each spent case, turn, load, close
			if step == 0:
				_key("loading_gate", 0.0, 0.2, 1.0)
				for h in _hammers():
					var half: float = float(parts[h].anim.get("half", 20.0)) / maxf(float(parts[h].anim.get("open", 50.0)), 1.0)
					_key(h, 0.0, 0.15, half)
			elif step > 0:
				if spent > 0 and parts.has("ejector_rod"):
					_key("ejector_rod", 0.0, each * 0.22, 1.0)
					_at(each * 0.2, _eject)
					_key("ejector_rod", each * 0.25, each * 0.45, 0.0)
					spent -= 1
				_cyl_step(each * 0.5, each * 0.85)
			else:
				_key("loading_gate", 0.0, 0.15, 0.0)
				for h in _hammers():
					_key(h, 0.15, 0.35, 1.0)
		"lever":
			if step > 0 and parts.has("loading_gate"):
				_key("loading_gate", 0.0, each * 0.25, 1.0)
				_key("loading_gate", each * 0.35, each * 0.55, 0.0)
		"bolt":
			if step == 0:
				_key("bolt_rot", 0.0, 0.12, 1.0)
				_key("bolt", 0.14, 0.3, 1.0)
			elif step < 0:
				_key("bolt", 0.0, 0.16, 0.0)
				_key("bolt_rot", 0.18, 0.3, 0.0)
		"pump":
			if step < 0 and parts.has("pump"):
				_cycle_pump(0.0, 0.6)
		"break":
			if step == 0:
				if parts.has("top_lever"):
					_key("top_lever", 0.0, 0.1, 1.0)
				_key("barrels", 0.08, 0.35, 1.0)
				if parts.has("extractor"):
					_key("extractor", 0.3, 0.38, 1.0)
				for i in maxi(barrel_fired, 1):
					_at(0.36 + i * 0.03, _eject)
				barrel_fired = 0
			elif step < 0:
				_key("barrels", 0.0, 0.2, 0.0)
				if parts.has("extractor"):
					_key("extractor", 0.0, 0.1, 0.0)
				if parts.has("top_lever"):
					_key("top_lever", 0.18, 0.26, 0.0)
				for h in _hammers():
					_key(h, 0.3, 0.5, 1.0)

# ----------------------------------------------------------------------------------------------- stand-in
## Simple procedural gun with the same node names/markers (used when no glb is available).
func _build_standin() -> Node3D:
	var root := Node3D.new()
	root.name = weapon_id + "_standin"
	var g := Node3D.new()
	g.name = weapon_id
	root.add_child(g)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.08, 0.085, 0.1)
	steel.metallic = 1.0
	steel.roughness = 0.35
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.28, 0.14, 0.07)
	wood.roughness = 0.55
	var pistol: bool = def.get("slot", "") == "sidearm"
	var blen := 0.19 if pistol else (0.5 if action == "lever" else 0.7)
	if weapon_id == "talbot_pocket":
		blen = 0.065
	var body := MeshInstance3D.new()
	body.name = "body"
	g.add_child(body)
	var add_box := func(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = body) -> void:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = size
		mi.mesh = b
		mi.material_override = mat
		mi.position = pos
		parent.add_child(mi)
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.008 if pistol else 0.01
	cm.bottom_radius = cm.top_radius
	cm.height = blen
	barrel.mesh = cm
	barrel.material_override = steel
	barrel.rotation.x = PI / 2
	if pistol:
		barrel.position = Vector3(0, 0.072, -0.06 - blen * 0.5)
		add_box.call(Vector3(0.024, 0.05, 0.065), Vector3(0, 0.062, -0.03), steel)
		add_box.call(Vector3(0.028, 0.09, 0.03), Vector3(0, -0.005, 0.01), wood)
		var cyl := MeshInstance3D.new()
		cyl.name = "cylinder"
		var cc := CylinderMesh.new()
		cc.top_radius = 0.02
		cc.bottom_radius = 0.02
		cc.height = 0.04
		cyl.mesh = cc
		cyl.material_override = steel
		var holder := Node3D.new()
		holder.name = "cylinder"
		holder.position = Vector3(0, 0.059, -0.05)
		cyl.rotation.x = PI / 2
		holder.add_child(cyl)
		g.add_child(holder)
		_mk(g, "muzzle", Vector3(0, 0.072, -0.06 - blen))
		_mk(g, "sight_front", Vector3(0, 0.085, -0.05 - blen))
		_mk(g, "sight_rear", Vector3(0, 0.085, -0.02))
		_mk(g, "grip_l", Vector3(-0.013, -0.018, 0.0))
		_mk(g, "holster_attach", Vector3(0, 0.06, -0.05))
		_mk(g, "shell_eject", Vector3(0.015, 0.06, -0.03))
	else:
		barrel.position = Vector3(0, 0.035, -0.17 - blen * 0.5)
		add_box.call(Vector3(0.026, 0.05, 0.17), Vector3(0, 0.025, -0.085), steel)
		add_box.call(Vector3(0.04, 0.11, 0.3), Vector3(0, -0.03, 0.17), wood)
		add_box.call(Vector3(0.03, 0.035, 0.25), Vector3(0, 0.01, -0.3), wood)
		_mk(g, "muzzle", Vector3(0, 0.035, -0.17 - blen))
		_mk(g, "sight_front", Vector3(0, 0.05, -0.16 - blen))
		_mk(g, "sight_rear", Vector3(0, 0.052, -0.25))
		_mk(g, "grip_l", Vector3(0, 0.0, -0.35))
		_mk(g, "holster_attach", Vector3(0, 0.02, -0.2))
		_mk(g, "shell_eject", Vector3(0.0, 0.06, -0.08))
	body.add_child(barrel)
	_mk(g, "grip_r", Vector3.ZERO)
	return root

func _mk(parent: Node3D, n: String, p: Vector3) -> void:
	var m := Node3D.new()
	m.name = n
	m.position = p
	parent.add_child(m)
