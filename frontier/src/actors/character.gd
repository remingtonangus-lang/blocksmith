class_name FrontierCharacter
extends Node3D
## A generated human (created by CharacterFactory). Child "Model" holds the glTF scene: Skeleton (Godot humanoid
## bone names + LeftEye/RightEye), meshes Body / Head (face blend shapes) / Hair / Hat.
##
## Animation:  play(clip, blend := 0.2, speed := 1.0)   seek(seconds)   current_clip()   anim (AnimationPlayer)
##             clip names: see CharacterFactory.clip_info() / design/CHARACTERS.md ("idle", "walk", "run", ...).
##             Locomotion clips are in place; the Root bone carries the extracted root motion (use
##             anim.root_motion_track = ^"Skeleton:Root" + get_root_motion_position() for root-motion movement).
## Face:       set_viseme(v, weight := 1.0)  v in AA E I O U MBP FV L TH CH SS DD KK RR rest (or raw "vis_aa")
##             set_expression(name, weight)  smile frown brow_raise brow_furrow brow_inner_up sneer squint wide
##                                           jaw_open pucker funnel press cheek_puff (or any raw blend shape name)
##             clear_face()   blink()   auto_blink (bool)   face_smoothing (blend-shape lerp speed, 1/s)
## Gaze:       look_at_point(world_pos, head_weight := 0.6)   look_at_node(node)   clear_look()
## Misc:       head_position() -> Vector3 (world)   skeleton (Skeleton3D)   set_hat_visible(bool)

const VISEMES := {"AA": "vis_aa", "E": "vis_E", "I": "vis_I", "O": "vis_O", "U": "vis_U", "MBP": "vis_PP",
	"FV": "vis_FF", "L": "vis_nn", "TH": "vis_TH", "CH": "vis_CH", "SS": "vis_SS", "DD": "vis_DD", "KK": "vis_kk",
	"RR": "vis_RR", "NN": "vis_nn", "rest": ""}
const EXPRESSIONS := {"smile": ["smile_L", "smile_R"], "frown": ["frown"], "brow_raise": ["brow_raise"],
	"brow_furrow": ["brow_furrow"], "brow_inner_up": ["brow_inner_up"], "sneer": ["sneer_L", "sneer_R"],
	"squint": ["squint_L", "squint_R"], "wide": ["wide_L", "wide_R"], "jaw_open": ["jaw_open"],
	"pucker": ["pucker"], "funnel": ["funnel"], "press": ["press"], "cheek_puff": ["cheek_puff"],
	"blink": ["blink_L", "blink_R"]}

var character_id := ""
var info: Dictionary = {}
var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var look: CharacterLook
var face_meshes: Array[MeshInstance3D] = []
var auto_blink := true
var face_smoothing := 18.0

var _face_target: Dictionary = {}    # blend shape -> target weight
var _face_now: Dictionary = {}
var _viseme := ""
var _blink_t := 0.0
var _next_blink := 2.0
var _rng := RandomNumberGenerator.new()


func setup(m: Node3D, lib: AnimationLibrary, _opts := {}) -> void:
	model = m
	skeleton = _find_skeleton(m)
	if skeleton:
		skeleton.name = "Skeleton"
	_collect_face_meshes(m)
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	add_child(anim)
	if skeleton:
		anim.root_node = anim.get_path_to(skeleton.get_parent())
		# Root bone = extracted root motion: kept out of the pose (clips play in place); read it with
		# anim.get_root_motion_position()/rotation() to drive a CharacterBody3D, or use clip_info().speed.
		anim.root_motion_track = NodePath("Skeleton:Root")
	if lib:
		anim.add_animation_library(CharacterFactory.ANIM_LIB_NAME, lib)
	if skeleton:
		# clips are authored on the canonical rig: scale hips/root translation to this body's leg length
		var ref := float(CharacterFactory.catalog().get("animations", {}).get("rest_hips_height", 0.0))
		var hips := skeleton.find_bone("Hips")
		if ref > 0.0 and hips >= 0:
			skeleton.motion_scale = skeleton.get_bone_global_rest(hips).origin.y / ref
	if skeleton:
		look = CharacterLook.new()
		look.name = "Look"
		skeleton.add_child(look)
	_rng.seed = hash(character_id)
	_next_blink = _rng.randf_range(1.0, 4.0)


func play(clip: String, blend := 0.2, speed := 1.0) -> void:
	if anim == null:
		return
	var full := clip if clip.contains("/") else CharacterFactory.ANIM_LIB_NAME + "/" + clip
	if not anim.has_animation(full):
		push_warning("FrontierCharacter: no clip " + clip)
		return
	anim.play(full, blend, speed)


func seek(t: float) -> void:
	if anim and anim.current_animation != "":
		anim.seek(t, true)


func motion_scale() -> float:
	## Multiply CharacterFactory.clip_info(clip).speed by this for this body's walking speed.
	return skeleton.motion_scale if skeleton else 1.0


func current_clip() -> String:
	return anim.current_animation.get_file() if anim else ""


# --- face ----------------------------------------------------------------------------------------------------------
func set_viseme(v: String, weight := 1.0) -> void:
	var shape: String = VISEMES.get(v, VISEMES.get(v.to_upper(), v))
	if _viseme != "" and _viseme != shape:
		_face_target[_viseme] = 0.0
	_viseme = shape
	if shape != "":
		_face_target[shape] = clampf(weight, 0.0, 1.0)


func set_expression(expr: String, weight := 1.0) -> void:
	if VISEMES.has(expr) or VISEMES.has(expr.to_upper()):
		set_viseme(expr, weight)
		return
	for s in EXPRESSIONS.get(expr, [expr]):
		_face_target[s] = clampf(weight, 0.0, 1.0)


func clear_face() -> void:
	for k in _face_target.keys():
		_face_target[k] = 0.0
	_viseme = ""


func blink() -> void:
	_blink_t = 0.16


func set_face_immediate() -> void:
	## Apply targets without smoothing (screenshots, cut-ins).
	for k in _face_target.keys():
		_face_now[k] = _face_target[k]
	_apply_face()


# --- gaze ----------------------------------------------------------------------------------------------------------
func look_at_point(p: Vector3, head_weight := 0.6) -> void:
	if look:
		look.target_position = p
		look.target_node = null
		look.head_weight = head_weight
		look.enabled = true


func look_at_node(n: Node3D, head_weight := 0.6) -> void:
	if look:
		look.target_node = n
		look.head_weight = head_weight
		look.enabled = true


func clear_look() -> void:
	if look:
		look.enabled = false


func head_position() -> Vector3:
	if skeleton == null:
		return global_position + Vector3(0, 1.6, 0)
	var i := skeleton.find_bone("Head")
	var le := skeleton.find_bone("LeftEye")
	var re := skeleton.find_bone("RightEye")
	if le >= 0 and re >= 0:
		var a := skeleton.get_bone_global_pose(le).origin
		var b := skeleton.get_bone_global_pose(re).origin
		return skeleton.global_transform * ((a + b) * 0.5)
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin


func set_hat_visible(v: bool) -> void:
	var hat := model.find_child("Hat", true, false)
	if hat:
		hat.visible = v


# --- internals -----------------------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if auto_blink:
		_next_blink -= delta
		if _next_blink <= 0.0:
			blink()
			_next_blink = _rng.randf_range(2.0, 6.0) if _rng.randf() > 0.15 else 0.35
	var bl := 0.0
	if _blink_t > 0.0:
		_blink_t -= delta
		bl = sin(clampf(1.0 - _blink_t / 0.16, 0.0, 1.0) * PI)
	var k := 1.0 - exp(-face_smoothing * delta)
	for s in _face_target.keys():
		_face_now[s] = lerpf(_face_now.get(s, 0.0), _face_target[s], k)
	_face_now["blink_L"] = maxf(_face_target.get("blink_L", 0.0), bl)
	_face_now["blink_R"] = maxf(_face_target.get("blink_R", 0.0), bl)
	_apply_face()


func _apply_face() -> void:
	for mi in face_meshes:
		for s in _face_now.keys():
			var idx := mi.find_blend_shape_by_name(s)
			if idx >= 0:
				mi.set_blend_shape_value(idx, _face_now[s])


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null


func _collect_face_meshes(n: Node) -> void:
	if n is MeshInstance3D and n.mesh and n.mesh.get_blend_shape_count() > 0:
		face_meshes.append(n)
	for c in n.get_children():
		_collect_face_meshes(c)
