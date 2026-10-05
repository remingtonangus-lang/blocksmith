class_name HorseVisual
extends Node3D
## Body of any generated quadruped (tools/animals/quadruped.py -> <species>.glb; the horse and the wildlife share
## one bone layout): coat/hair materials, LOD ranges, an AnimationTree that crossfades the looping cycles (gaits,
## idles) and plays one-shot actions on top, terrain foot IK (HorseIK), hoof/paw sole positions for the gait oracle
## and, for the horse, the saddle seat transform. Falls back to a simple stand-in when the model is missing.
##   Model search order: res://assets/ext/animals/<species>.glb (CI asset pack, tools/fetch_assets.sh animals),
##   res://assets/animals_out/<species>.glb (local `python3 frontier/tools/animals/quadruped.py --species ...`).

const MODEL_PATHS := ["res://assets/ext/animals/horse.glb", "res://assets/animals_out/horse.glb"]
const LOCO_STATES := ["idle", "idle_rest", "graze", "walk", "trot", "canter", "gallop", "canter_r", "gallop_r", "swim",
	"turn", "turn_l", "turn_r", "dead", "fallen"]
const ACTIONS := ["head_shake", "rear", "buck", "jump", "shy", "skid_stop", "stumble", "ear_flick", "tail_swish",
	"refuse", "getup", "fall"]
const SEAT := Vector3(0.0, 1.66, -0.12)       # saddle seat in model space (rest pose, Godot axes)

var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var ik: HorseIK
var body_mat: ShaderMaterial
var fur_mats: Array[ShaderMaterial] = []     # wildlife fur shells (next_pass chain on FurShells)
var fur_node: MeshInstance3D
var under_fur_mat: ShaderMaterial              # LOD0 skin under the shells (matte)
var is_bird := false                           # birds (tools/animals/bird.py): feather cards, no leg IK
var feather_mat: ShaderMaterial
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
var species := "horse"
var loop_states: Array = []        # looping animations available as locomotion states
var size_scale := 1.0              # withers height / horse withers height (LOD distances scale with it)

static func model_path() -> String:
	return model_path_for("horse")

static func model_path_for(sp: String) -> String:
	var order := ["res://assets/ext/animals/%s.glb" % sp, "res://assets/animals_out/%s.glb" % sp]
	if Game.args.has("local_animals"):          # generator work: the local build wins over the fetched release
		order.reverse()
	for p in order:
		if ResourceLoader.exists(p):
			return p
	return ""

func build(coat_in: Dictionary, sp: String = "horse") -> void:
	coat = coat_in
	species = sp
	var path := model_path_for(sp)
	if path != "":
		var ps: PackedScene = load(path)
		if ps != null:
			model = ps.instantiate()
	if model == null:
		_build_fallback()
		return
	has_model = true
	add_child(model)
	var mp := path.get_base_dir().path_join("%s_gaits.json" % sp)
	if FileAccess.file_exists(mp):
		meta = JSON.parse_string(FileAccess.get_file_as_string(mp))
	size_scale = clampf(float(meta.get("rest", {}).get("withers_height", 1.555)) / 1.555, 0.15, 1.5)
	is_bird = str(meta.get("kind", "")) == "bird"
	skeleton = _find(model, "Skeleton3D") as Skeleton3D
	anim_player = _find(model, "AnimationPlayer") as AnimationPlayer
	_setup_materials()
	_setup_lods()
	_setup_fur()
	if anim_player != null:
		_setup_tree()
	if skeleton != null and not is_bird:
		if species == "horse":
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
	if is_bird:
		_setup_bird_materials()
		return
	body_mat = ShaderMaterial.new()
	body_mat.shader = load("res://shaders/horse_coat.gdshader" if species == "horse" else "res://shaders/animal_coat.gdshader")
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
		elif n.begins_with("eye") and species != "horse":
			var am := ShaderMaterial.new()
			am.shader = load("res://shaders/animal_eye.gdshader")
			AnimalCoats.apply_eyes(species, am)
			mi.material_override = am
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
	if species == "horse":
		HorseCoats.apply(coat, body_mat, hair_mat)
	else:
		AnimalCoats.apply(coat, body_mat, meta.get("anchors", {}))

## Birds: plumage body shader on the SDF body, feather shader on the wing and tail cards, eyes as wildlife eyes.
func _setup_bird_materials() -> void:
	body_mat = ShaderMaterial.new()
	body_mat.shader = load("res://shaders/bird_body.gdshader")
	feather_mat = ShaderMaterial.new()
	feather_mat.shader = load("res://shaders/bird_feather.gdshader")
	var tail_mat := ShaderMaterial.new()
	tail_mat.shader = feather_mat.shader
	for mi in meshes:
		var n := String(mi.name).to_lower()
		if n.begins_with("body"):
			mi.material_override = body_mat
		elif n.begins_with("plumage_tail"):
			mi.material_override = tail_mat
		elif n.begins_with("plumage"):
			mi.material_override = feather_mat
		elif n.begins_with("eye"):
			var am := ShaderMaterial.new()
			am.shader = load("res://shaders/animal_eye.gdshader")
			AnimalCoats.apply_eyes(species, am)
			mi.material_override = am
	BirdLooks.apply(species, coat, body_mat, feather_mat, tail_mat, meta.get("anchors", {}))

func _setup_lods() -> void:
	# explicit LODs exported as Body_LOD1 / Body_LOD2: switch by distance
	for mi in meshes:
		var n := String(mi.name)
		var k := maxf(size_scale, 0.35)
		if n == "Body":
			mi.visibility_range_end = 23.0 * k
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		elif n == "Body_LOD1":
			mi.visibility_range_begin = 22.0 * k
			mi.visibility_range_end = 71.0 * k
			mi.material_override = body_mat
		elif n == "Body_LOD2":
			mi.visibility_range_begin = 70.0 * k
			mi.visibility_range_end = 900.0 * k
			mi.material_override = body_mat
		elif n.begins_with("Mane") or n.begins_with("Tail") or n.begins_with("Forelock"):
			mi.visibility_range_end = 260.0
		elif n.begins_with("Plumage"):
			mi.visibility_range_end = 700.0               # the wings are the bird's silhouette in the sky
		elif n.begins_with("Antler") or n.begins_with("Horn"):
			mi.visibility_range_end = 400.0 * k
		elif not n.begins_with("Body"):
			mi.visibility_range_end = 160.0 * k

## Fur shells on the LOD0 body: one extra skinned instance of the Body mesh (no shadow casting) whose material
## is a next_pass chain of N shells (quality preset "fur_shells"; 0 on the quest preset). It shares Body's
## visibility range, and the shells thin out over the last 40 % of it.
func _setup_fur() -> void:
	if species == "horse" or not AnimalCoats.FUR.has(species):
		return
	var n := int(Game.quality.get("fur_shells", 8))
	if Game.args.has("fur_shells"):
		n = int(Game.args["fur_shells"])
	if n <= 0:
		return
	var body0: MeshInstance3D = null
	var body1: MeshInstance3D = null
	for mi in meshes:
		if String(mi.name) == "Body":
			body0 = mi
		elif String(mi.name) == "Body_LOD1":
			body1 = mi
	if body0 == null or body0.mesh == null:
		return
	# the shells only need the silhouette: they use the LOD1 mesh (about 30 % of the triangles) when there is one
	var src: MeshInstance3D = body1 if body1 != null and body1.mesh != null else body0
	fur_node = MeshInstance3D.new()
	fur_node.name = "FurShells"
	fur_node.mesh = src.mesh
	fur_node.skin = src.skin
	body0.get_parent().add_child(fur_node)
	fur_node.transform = src.transform
	fur_node.skeleton = fur_node.get_path_to(src.get_node(src.skeleton))
	fur_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fur_node.visibility_range_end = body0.visibility_range_end
	under_fur_mat = body_mat.duplicate() as ShaderMaterial
	under_fur_mat.set_shader_parameter("under_fur", 1.0)
	body0.material_override = under_fur_mat
	var shader: Shader = load("res://shaders/animal_fur_shell.gdshader")
	var prev: ShaderMaterial = null
	for i in n:
		var sm := ShaderMaterial.new()
		sm.shader = shader
		AnimalCoats.apply(coat, sm, meta.get("anchors", {}))
		AnimalCoats.apply_fur(species, sm)
		sm.set_shader_parameter("shell_h", float(i + 1) / float(n))
		sm.set_shader_parameter("fade_end", body0.visibility_range_end)
		sm.set_shader_parameter("fade_start", body0.visibility_range_end * 0.6)
		if prev == null:
			fur_node.material_override = sm
		else:
			prev.next_pass = sm
		prev = sm
		fur_mats.append(sm)

## Set a coat shader parameter on the skin and every fur shell (state: wet, mud, blood, skinned...).
func set_coat(param: String, value: Variant) -> void:
	if body_mat:
		body_mat.set_shader_parameter(param, value)
	if under_fur_mat:
		under_fur_mat.set_shader_parameter(param, value)
	for m in fur_mats:
		m.set_shader_parameter(param, value)
	if param == "skinned" and fur_node:
		fur_node.visible = float(value) < 0.5

func _setup_tree() -> void:
	var lib := anim_player.get_animation_library("")
	for an in lib.get_animation_list():
		var a := lib.get_animation(an)
		var info: Dictionary = meta.get("anims", {}).get(an, {})
		a.loop_mode = Animation.LOOP_LINEAR if info.get("loop", an in LOCO_STATES and an not in ["dead", "fallen"]) else Animation.LOOP_NONE
	var sm := AnimationNodeStateMachine.new()
	var names: Array = []
	var states: Array = LOCO_STATES
	if species != "horse":
		states = []
		for an in lib.get_animation_list():
			if meta.get("anims", {}).get(an, {}).get("loop", false):
				states.append(String(an))
		states.append_array(["dead", "carcass_pose"])
	loop_states = states
	for st in states:
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
			tr.xfade_time = 0.28 if not (b in ["dead", "fallen", "carcass_pose"]) else (0.5 if b != "carcass_pose" else 0.05)
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
		"turn_l", "turn_r": return "turn" if anim_player.has_animation("turn") else "idle"
		"idle_rest", "graze", "turn": return "idle"
		"swim": return "trot"
		"dead", "fallen": return "death"
		"carcass_pose": return "carcass"
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

const TACK := ["saddle", "blanket", "bridle", "reins", "bags", "saddlebags", "stirrup", "bedroll", "cinch", "bit", "tack", "fender"]

## Hide a model part by mesh-name prefix (e.g. "Antlers" for does / cows).
func hide_part(prefix: String) -> void:
	for mi in meshes:
		if String(mi.name).begins_with(prefix):
			mi.visible = false

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
