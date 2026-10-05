class_name WeaponHolder
extends Node3D
## Puts an actor's firearms (GunHandler.weapons) into the world as WeaponModels: holstered on the right hip
## (sidearms) and slung across the back (long guns) while not drawn, in the right hand when `gun.drawn`, pointing
## at the aim point while aiming (player: aim_ray(); NPCs: intent.aim_at). Uses a hand bone when the actor's
## visual has a Skeleton3D ("hand.R", "RightHand", "hand_r", ...), else fixed poses for the capsule stand-ins.
## Drives the models from GunHandler: fired -> fire_anim + smoke, reloading/clip changes -> reload_anim steps,
## ejected cases -> WeaponFX.casing. Exposes muzzle_transform() for muzzle-accurate flashes.
## Attach with WeaponHolder.attach(actor, gun) (no-op headless).

const HAND_BONES := ["hand.R", "RightHand", "hand_r", "Hand_R", "hand_R", "mixamorig:RightHand", "DEF-hand.R",
	"R_Hand", "RightHand_jnt", "hand.r"]
const DRAW_TIME := 0.32

var actor: Node3D
var gun: GunHandler
var models := {}                 # weapon id -> WeaponModel
var draw_t := 0.0                # 0 holstered .. 1 in hand (current weapon)
var hand: Node3D                 # BoneAttachment3D when a skeleton is found
var aim_override = null          # Vector3 world aim point set by a caller (else derived from the actor)
var saddle: Node3D = null        # when set (mounted), long guns ride in a scabbard on this node
var snap := false                # skip the draw/holster blend (screenshots, teleports)
var _current := ""
var _was_reloading := false
var _last_clip := -1
var _was_drawn := false
var _detail_t := 0.0
var _skel_checked := false
var _aim_cache := Vector3.ZERO
var _aim_frame := -1

static func attach(a: Node3D, g: GunHandler) -> WeaponHolder:
	if Game.headless or a == null or g == null:
		return null
	var h := WeaponHolder.new()
	h.name = "WeaponHolder"
	a.add_child(h)
	h.actor = a
	h.gun = g
	g.fired.connect(h._on_fired)
	return h

func _ready() -> void:
	process_priority = 50          # after the actor's own _process (camera, facing)

func _visual() -> Node3D:
	var v = actor.get("visual")
	return v if v is Node3D else actor

func _find_hand() -> void:
	_skel_checked = true
	var v := _visual()
	var sk: Skeleton3D = v.find_children("*", "Skeleton3D", true, false).front() if not v.find_children("*", "Skeleton3D", true, false).is_empty() else null
	if sk == null:
		return
	for b in HAND_BONES:
		var i := sk.find_bone(b)
		if i >= 0:
			var ba := BoneAttachment3D.new()
			ba.name = "GunHand"
			ba.bone_name = b
			sk.add_child(ba)
			hand = ba
			return

func _sync() -> void:
	var want := {}
	for w in gun.weapons:
		want[w] = true
	for id in models.keys():
		if not want.has(id):
			models[id].queue_free()
			models.erase(id)
	for id in want:
		if not models.has(id):
			var m := WeaponModel.create(id)
			m.top_level = true
			add_child(m)
			m.ejected.connect(_on_ejected)
			models[id] = m
	if gun.weapon_id() != _current:
		_current = gun.weapon_id()
		draw_t = 0.0
		_last_clip = gun.clip.get(_current, 0)
		_was_reloading = false

func model() -> WeaponModel:
	return models.get(gun.weapon_id())

func muzzle_transform() -> Transform3D:
	var m := model()
	if m != null and gun.drawn and draw_t > 0.5:
		return m.muzzle_transform()
	var v := _visual()
	return Transform3D(v.global_basis, v.global_position + v.global_basis * Vector3(0.12, 1.42, -0.5))

func has_drawn_model() -> bool:
	return model() != null and gun.drawn and draw_t > 0.5

func _process(dt: float) -> void:
	if actor == null or gun == null or not is_instance_valid(actor):
		return
	if not _skel_checked:
		_find_hand()
	_sync()
	var drawn: bool = gun.drawn and actor.get("alive") != false
	draw_t = move_toward(draw_t, 1.0 if drawn else 0.0, 1.0 if snap else dt / DRAW_TIME)
	var m := model()
	if m != null:
		if drawn and not _was_drawn:
			m.cock(true)
		elif not drawn and _was_drawn:
			m.cock(false)
	_was_drawn = drawn
	_reload_watch(m)
	var v := _visual()
	var ref := v.global_transform
	for id in models:
		var wm: WeaponModel = models[id]
		var hol := ref * _holster_local(wm)
		if id == gun.weapon_id() and draw_t > 0.0:
			var hand_x := _hand_global(wm, ref)
			var u := draw_t * draw_t * (3.0 - 2.0 * draw_t)
			wm.global_transform = hol.interpolate_with(hand_x, u)
		else:
			wm.global_transform = hol
	_standin_arms(m, ref)
	_detail_t -= dt
	if _detail_t <= 0.0:
		_detail_t = 0.5
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		var near := cam == null or cam.global_position.distance_to(actor.global_position) < 9.0
		for id in models:
			models[id].set_detail(near or actor == Game.player)

## Capsule stand-in bodies have no arms: while a gun is in hand, draw simple sleeves + hands from the shoulders to
## the gun's grip_r / grip_l markers so the hold reads. Skipped when a real skeleton drives the hand.
var _arms: Array = []            # [upper sleeve R, hand R, sleeve L, hand L]

func _standin_arms(m: WeaponModel, ref: Transform3D) -> void:
	var show := hand == null and m != null and draw_t > 0.6 and _visual().find_children("*", "Skeleton3D", true, false).is_empty()
	if not show:
		for a in _arms:
			a.visible = false
		return
	if _arms.is_empty():
		var coat := Color(0.3, 0.24, 0.19)
		for mi in _visual().find_children("*", "MeshInstance3D", true, false):
			if mi.material_override is StandardMaterial3D:
				coat = (mi.material_override as StandardMaterial3D).albedo_color
				break
		var cloth := StandardMaterial3D.new()
		cloth.albedo_color = coat
		cloth.roughness = 0.9
		var skin := StandardMaterial3D.new()
		skin.albedo_color = Color(0.72, 0.55, 0.45)
		skin.roughness = 0.6
		for i in 4:
			var mi := MeshInstance3D.new()
			if i % 2 == 0:
				var cm := CapsuleMesh.new()
				cm.radius = 0.042
				cm.height = 1.0
				mi.mesh = cm
				mi.material_override = cloth
			else:
				var sm := SphereMesh.new()
				sm.radius = 0.042
				sm.height = 0.075
				mi.mesh = sm
				mi.material_override = skin
			mi.top_level = true
			add_child(mi)
			_arms.append(mi)
	var pistol := _is_pistol(m)
	var aiming: bool = _aim_point() != null
	var targets := [["grip_r", Vector3(0.19, 1.42, -0.02)]]
	if not pistol or aiming:
		targets.append(["grip_l", Vector3(-0.19, 1.42, -0.02)])
	for i in 2:
		var sleeve: MeshInstance3D = _arms[i * 2]
		var hnd: MeshInstance3D = _arms[i * 2 + 1]
		if i >= targets.size():
			sleeve.visible = false
			hnd.visible = false
			continue
		var g := m.grip_transform(targets[i][0])
		var a: Vector3 = ref * targets[i][1]
		var b: Vector3 = g.origin
		if i == 1 and pistol:
			b = g.origin + g.basis.x * -0.015
		var d := b - a
		var ln := maxf(d.length() - 0.03, 0.05)
		var y := d.normalized()
		var x := y.cross(Vector3.UP)
		if x.length() < 0.1:
			x = Vector3.RIGHT
		x = x.normalized()
		var z := x.cross(y)
		sleeve.global_transform = Transform3D(Basis(x, y * ln, z), a + y * ln * 0.5)
		hnd.global_transform = Transform3D(Basis(x, y, z), b)
		sleeve.visible = true
		hnd.visible = true

func _is_pistol(wm: WeaponModel) -> bool:
	return wm.def.get("slot", "sidearm") == "sidearm"

## Holster pose in the visual's local frame (forward -Z, right +X), aligned on the model's holster_attach marker.
func _holster_local(wm: WeaponModel) -> Transform3D:
	var anchor := wm.marker_local("holster_attach")
	var t: Transform3D
	if _is_pistol(wm):
		# right hip, muzzle down, butt to the rear, gun's right side out
		var b := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))       # columns: x, y, z
		b = Basis(Vector3.RIGHT, deg_to_rad(-12.0)) * b
		t = Transform3D(b, Vector3(0.235, 0.9, 0.02))
	elif saddle != null:
		return actor.global_transform.affine_inverse() * saddle.global_transform * anchor.affine_inverse()
	else:
		# slung across the back, muzzle up over the left shoulder, top of the gun facing away from the back
		var f := Vector3(-0.42, 0.9, 0.0).normalized()
		var b2 := Basis.looking_at(f, Vector3.BACK)
		t = Transform3D(b2, Vector3(0.0, 1.16, 0.19))
	return t * anchor.affine_inverse()

func _aim_point() -> Variant:
	if aim_override != null:
		return aim_override
	var intent = actor.get("intent")
	if typeof(intent) != TYPE_DICTIONARY:
		return null
	if intent.has("aim") and intent.aim and actor.has_method("aim_ray"):
		var f := Engine.get_process_frames()
		if f != _aim_frame:
			_aim_frame = f
			_aim_cache = actor.aim_ray().point
		return _aim_cache
	if intent.has("aim_at") and intent.aim_at != null:
		return intent.aim_at
	return null

## Hand pose (global): grip point from the hand bone or a fixed stand-in offset, orientation toward the aim point.
func _hand_global(wm: WeaponModel, ref: Transform3D) -> Transform3D:
	var pistol := _is_pistol(wm)
	var aim = _aim_point()
	var aiming: bool = aim != null
	var local_pos: Vector3
	var down := 0.0
	if pistol:
		local_pos = Vector3(0.13, 1.43, -0.5) if aiming else Vector3(0.2, 1.06, -0.24)
		down = 38.0
	else:
		local_pos = Vector3(0.15, 1.39, -0.2) if aiming else Vector3(0.2, 1.05, -0.12)
		down = 22.0
	var pos := ref * local_pos
	if hand != null and hand.is_inside_tree():
		pos = hand.global_position
	var fwd := -ref.basis.z
	var b: Basis
	if aiming:
		var d: Vector3 = (aim as Vector3) - pos
		if d.length() < 0.5 or d.normalized().dot(fwd) < 0.2:
			d = fwd
		b = Basis.looking_at(d.normalized(), Vector3.UP)
	else:
		b = Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.RIGHT, deg_to_rad(-down))
	return Transform3D(b, pos)

func _reload_watch(m: WeaponModel) -> void:
	if m == null:
		return
	var id := gun.weapon_id()
	var c: int = gun.clip.get(id, 0)
	if gun.reloading and not _was_reloading:
		m.reload_anim(0)
	elif gun.reloading and c > _last_clip:
		m.reload_anim(c)
	elif not gun.reloading and _was_reloading:
		if c > _last_clip:
			m.reload_anim(c)
		m.reload_anim(-1)
	_was_reloading = gun.reloading
	_last_clip = c

func _on_fired(id: String, _origin: Vector3, dir: Vector3) -> void:
	var m: WeaponModel = models.get(id)
	if m == null:
		return
	m.fire_anim()
	_last_clip = gun.clip.get(id, 0)
	var mt := m.muzzle_transform()
	var amount := 1.0
	match String(m.def.get("kind", "pistol")):
		"shotgun": amount = 1.6
		"rifle": amount = 1.25
	var mdir := -mt.basis.z if draw_t > 0.5 else dir
	WeaponFX.smoke(get_tree().current_scene, mt.origin, mdir, amount)

func _on_ejected(shell: String, xform: Transform3D) -> void:
	var v := Vector3.ZERO
	if actor is CharacterBody3D:
		v = (actor as CharacterBody3D).velocity
	WeaponFX.casing(get_tree().current_scene, shell, xform, v)
