class_name HorseVisual
extends Node3D
## The horse's body: the generated model (tools/animals/horse_gen.py -> horse.glb), coat/hair materials, an
## AnimationTree that crossfades the gait cycles and plays one-shot actions on top, terrain foot IK (HorseIK) and
## the saddle seat transform for the rider. Falls back to a simple stand-in when the model has not been fetched.
##   Model search order: res://assets/ext/animals/horse.glb (CI asset pack, tools/fetch_assets.sh animals),
##   res://assets/animals_out/horse.glb (local `python3 frontier/tools/animals/horse_gen.py`).

const MODEL_PATHS := ["res://assets/ext/animals/horse.glb", "res://assets/animals_out/horse.glb"]
const LOCO_STATES := ["idle", "idle_rest", "graze", "walk", "trot", "canter", "gallop", "canter_r", "gallop_r", "swim",
	"turn", "dead", "fallen"]
const ACTIONS := ["head_shake", "rear", "buck", "jump", "shy", "skid_stop", "stumble", "ear_flick", "tail_swish",
	"refuse", "getup", "fall"]
const SEAT := Vector3(0.0, 1.66, -0.12)       # saddle seat in model space (rest pose, Godot axes)

var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var ik: HorseIK
var body_mat: ShaderMaterial
var hair_mat: ShaderMaterial
var meshes: Array[MeshInstance3D] = []
var meta: Dictionary = {}
var has_model := false
var coat: Dictionary = {}
var _state := ""
var _seat_bone := -1
var _seat_local := Transform3D.IDENTITY
var _playback: AnimationNodeStateMachinePlayback
var _action_node: AnimationNodeAnimation
var _sole_local := {}             # leg -> Vector3 sole offset in the hoof bone's frame
var _hoof_bone := {}

static func model_path() -> String:
	for p in MODEL_PATHS:
		if ResourceLoader.exists(p):
			return p
	return ""

func build(coat_in: Dictionary) -> void:
	coat = coat_in
	var path := model_path()
	if path != "":
		var ps: PackedScene = load(path)
		if ps != null:
			model = ps.instantiate()
	if model == null:
		_build_fallback()
		return
	has_model = true
	add_child(model)
	var mp := path.get_base_dir().path_join("horse_gaits.json")
	if FileAccess.file_exists(mp):
		meta = JSON.parse_string(FileAccess.get_file_as_string(mp))
	skeleton = _find(model, "Skeleton3D") as Skeleton3D
	anim_player = _find(model, "AnimationPlayer") as AnimationPlayer
	_setup_materials()
	_setup_lods()
	if anim_player != null:
		_setup_tree()
	if skeleton != null:
		_setup_seat()
		_setup_legs()
		ik = HorseIK.new()
		ik.name = "HorseIK"
		skeleton.add_child(ik)
		ik.setup(self)

func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null

func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		meshes.append(n)
	for c in n.get_children():
		_collect_meshes(c)

func _setup_materials() -> void:
	_collect_meshes(model)
	body_mat = ShaderMaterial.new()
	body_mat.shader = load("res://shaders/horse_coat.gdshader")
	hair_mat = ShaderMaterial.new()
	hair_mat.shader = load("res://shaders/horse_hair.gdshader")
	for mi in meshes:
		var n := String(mi.name).to_lower()
		if n.begins_with("body"):
			mi.material_override = body_mat
		elif n.begins_with("mane") or n.begins_with("tail") or n.begins_with("forelock") or n.begins_with("hair"):
			var src := mi.mesh.surface_get_material(0) if mi.mesh.get_surface_count() > 0 else null
			if src is BaseMaterial3D and src.albedo_texture != null:
				hair_mat.set_shader_parameter("strands", src.albedo_texture)
			mi.material_override = hair_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		elif n.begins_with("eye"):
			var em := StandardMaterial3D.new()
			em.albedo_color = Color(0.05, 0.03, 0.02)
			em.roughness = 0.05
			em.metallic_specular = 0.9
			em.clearcoat_enabled = true
			em.clearcoat = 1.0
			mi.material_override = em
		else:
			# tack: keep the exported material, tune for leather/metal
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m is BaseMaterial3D:
					m.roughness = clampf(m.roughness, 0.3, 0.9)
	HorseCoats.apply(coat, body_mat, hair_mat)

func _setup_lods() -> void:
	# explicit LODs exported as Body_LOD1 / Body_LOD2: switch by distance
	for mi in meshes:
		var n := String(mi.name)
		if n == "Body":
			mi.visibility_range_end = 22.0
			mi.visibility_range_end_margin = 2.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		elif n == "Body_LOD1":
			mi.visibility_range_begin = 22.0
			mi.visibility_range_end = 70.0
			mi.material_override = body_mat
		elif n == "Body_LOD2":
			mi.visibility_range_begin = 70.0
			mi.visibility_range_end = 900.0
			mi.material_override = body_mat
		elif n.begins_with("Mane") or n.begins_with("Tail") or n.begins_with("Forelock"):
			mi.visibility_range_end = 260.0
		elif not n.begins_with("Body"):
			mi.visibility_range_end = 160.0

func _setup_tree() -> void:
	var lib := anim_player.get_animation_library("")
	for an in lib.get_animation_list():
		var a := lib.get_animation(an)
		var info: Dictionary = meta.get("anims", {}).get(an, {})
		a.loop_mode = Animation.LOOP_LINEAR if info.get("loop", an in LOCO_STATES and an not in ["dead", "fallen"]) else Animation.LOOP_NONE
	var sm := AnimationNodeStateMachine.new()
	var names: Array = []
	for st in LOCO_STATES:
		var src: String = st
		if not anim_player.has_animation(src):
			src = _alias(st)
			if src == "" or not anim_player.has_animation(src):
				continue
		var node := AnimationNodeAnimation.new()
		node.animation = src
		sm.add_node(st, node)
		names.append(st)
	for a in names:
		for b in names:
			if a == b:
				continue
			var tr := AnimationNodeStateMachineTransition.new()
			tr.xfade_time = 0.28 if not (b in ["dead", "fallen"]) else 0.5
			tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			sm.add_transition(a, b, tr)
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("sm", sm)
	var ts := AnimationNodeTimeScale.new()
	bt.add_node("ts", ts)
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.18
	shot.fadeout_time = 0.3
	bt.add_node("shot", shot)
	_action_node = AnimationNodeAnimation.new()
	_action_node.animation = names[0] if names.size() > 0 else &""
	bt.add_node("action", _action_node)
	bt.connect_node("ts", 0, "sm")
	bt.connect_node("shot", 0, "ts")
	bt.connect_node("shot", 1, "action")
	bt.connect_node("output", 0, "shot")
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = bt
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(anim_player)
	tree.active = true
	_playback = tree.get("parameters/sm/playback")
	set_locomotion("idle", 1.0)

func _alias(st: String) -> String:
	match st:
		"canter_r": return "canter"
		"gallop_r": return "gallop"
		"idle_rest", "graze", "turn": return "idle"
		"swim": return "trot"
		"dead", "fallen": return "death"
	return ""

func _setup_seat() -> void:
	_seat_bone = skeleton.find_bone("spine_thorax")
	if _seat_bone >= 0:
		var rest := skeleton.get_bone_global_rest(_seat_bone)
		_seat_local = rest.affine_inverse() * Transform3D(Basis.IDENTITY, SEAT)

func _setup_legs() -> void:
	for leg in ["LF", "RF", "LH", "RH"]:
		var info: Dictionary = meta.get("legs", {}).get(leg, {})
		var bname: String = info.get("hoof_bone", ("fhoof_" if leg.ends_with("F") else "hhoof_") + leg.substr(0, 1))
		var bi := skeleton.find_bone(bname)
		if bi < 0:
			continue
		var sr: Array = info.get("sole_rest", [0.0, 0.0, 0.0])
		var rest := skeleton.get_bone_global_rest(bi)
		_hoof_bone[leg] = bi
		_sole_local[leg] = rest.affine_inverse() * Vector3(sr[0], sr[1], sr[2])

## World position of a hoof's sole centre (current pose, after IK).
func sole_world(leg: String) -> Vector3:
	if not _hoof_bone.has(leg):
		var off := {"LF": Vector3(-0.14, 0, -0.57), "RF": Vector3(0.14, 0, -0.57), "LH": Vector3(-0.14, 0, 0.68), "RH": Vector3(0.14, 0, 0.68)}
		return global_transform * off.get(leg, Vector3.ZERO)
	var t := skeleton.get_bone_global_pose(_hoof_bone[leg])
	return skeleton.global_transform * (t * _sole_local[leg])

func hoof_bone(leg: String) -> int:
	return _hoof_bone.get(leg, -1)

func sole_local(leg: String) -> Vector3:
	return _sole_local.get(leg, Vector3.ZERO)

func seat_transform() -> Transform3D:
	if skeleton == null or _seat_bone < 0:
		return global_transform * Transform3D(Basis.IDENTITY, SEAT)
	return skeleton.global_transform * skeleton.get_bone_global_pose(_seat_bone) * _seat_local

## Locomotion state (looping) and playback speed.
func set_locomotion(state: String, time_scale: float) -> void:
	if tree == null:
		return
	if state != _state:
		if _playback != null:
			if _state == "":
				_playback.start(state)
			else:
				_playback.travel(state)
		_state = state
	tree.set("parameters/ts/scale", time_scale)

func locomotion_state() -> String:
	return _state

func play_action(action: String, speed := 1.0) -> bool:
	if tree == null or anim_player == null or not anim_player.has_animation(action):
		return false
	_action_node.animation = action
	tree.set("parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return true

func action_playing() -> bool:
	return tree != null and bool(tree.get("parameters/shot/active"))

func action_length(action: String) -> float:
	if anim_player == null or not anim_player.has_animation(action):
		return 0.0
	return anim_player.get_animation(action).length

func gait_info(gait: String) -> Dictionary:
	return meta.get("gaits", {}).get(gait, {})

func set_care(dirt: float, mud: float, wet: float, sweat: float) -> void:
	if body_mat:
		body_mat.set_shader_parameter("dirt", dirt)
		body_mat.set_shader_parameter("mud", mud)
		body_mat.set_shader_parameter("wet", wet)
		body_mat.set_shader_parameter("sweat", sweat)
	if hair_mat:
		hair_mat.set_shader_parameter("dirt", dirt)
		hair_mat.set_shader_parameter("wet", wet)

const TACK := ["saddle", "blanket", "bridle", "reins", "bags", "saddlebags", "stirrup", "bedroll", "cinch", "bit", "tack"]

func set_tack_visible(on: bool) -> void:
	for mi in meshes:
		var n := String(mi.name).to_lower()
		for t in TACK:
			if n.begins_with(t):
				mi.visible = on

func set_motion_amount(m: float) -> void:
	if hair_mat:
		hair_mat.set_shader_parameter("motion", m)

# ------------------------------------------------------------------ fallback (no model fetched/built)
func _build_fallback() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = coat.get("body", Color(0.4, 0.2, 0.1))
	mat.roughness = 0.6
	var parts := [
		[Vector3(0, 1.15, 0.0), Vector3(0.55, 0.62, 1.55), 0.0],     # barrel
		[Vector3(0, 1.55, -0.95), Vector3(0.28, 0.75, 0.32), -0.6],   # neck
		[Vector3(0, 1.72, -1.30), Vector3(0.2, 0.25, 0.6), 0.9],      # head
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[1]
		mi.mesh = bm
		mi.position = p[0]
		mi.rotation.x = p[2]
		mi.material_override = mat
		add_child(mi)
	for off in [Vector3(-0.14, 0.45, -0.55), Vector3(0.14, 0.45, -0.55), Vector3(-0.14, 0.45, 0.65), Vector3(0.14, 0.45, 0.65)]:
		var leg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.045
		cm.height = 0.9
		leg.mesh = cm
		leg.position = off
		leg.material_override = mat
		add_child(leg)
