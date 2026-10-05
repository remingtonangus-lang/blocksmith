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
	_physics_tick_anim(delta)
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


# --- gameplay driver -----------------------------------------------------------------------------------------------
# Humans and the player call these each tick; the first call switches the character from clip playback (look-dev,
# cutscenes) to an AnimationTree: speed-matched locomotion blend space, upper-body aim layer, additive-style hit
# one-shots, then death clips. Far characters update their animation at a reduced rate.
const LOCO_POINTS := [["idle", 0.0], ["walk_brisk", 1.139], ["jog", 2.692], ["run", 3.338], ["sprint", 4.05]]
const LOWER_BODY := ["Root", "Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg",
	"RightLowerLeg", "RightFoot", "RightToes"]

var tree: AnimationTree
var _bs_max := 4.05
var _aim_w := 0.0
var _aim_target := 0.0
var _seat_w := 0.0
var _seat_target := 0.0
var _dead := false
var _lod_acc := 0.0
var _lod_frame := 0
var _game_mode := false

func _ensure_tree() -> void:
	if tree != null or anim == null or skeleton == null:
		return
	_game_mode = true
	model.rotation.y = PI                  # glTF characters face +Z; gameplay forward is -Z
	var ms := motion_scale()
	var root := AnimationNodeBlendTree.new()
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = 8.0
	bs.sync = true
	for p in LOCO_POINTS:
		var a := AnimationNodeAnimation.new()
		a.animation = CharacterFactory.ANIM_LIB_NAME + "/" + str(p[0])
		bs.add_blend_point(a, float(p[1]) * ms, -1, StringName(str(p[0])))
	_bs_max = float(LOCO_POINTS[-1][1]) * ms
	root.add_node("loco", bs, Vector2(0, 0))
	var ts := AnimationNodeTimeScale.new()
	root.add_node("loco_ts", ts, Vector2(200, 0))
	root.connect_node("loco_ts", 0, "loco")
	var aim_p := AnimationNodeAnimation.new()
	aim_p.animation = CharacterFactory.ANIM_LIB_NAME + "/pistol_aim_two_hand"
	var aim_r := AnimationNodeAnimation.new()
	aim_r.animation = CharacterFactory.ANIM_LIB_NAME + "/rifle_aim"
	root.add_node("aim_p", aim_p, Vector2(0, 200))
	root.add_node("aim_r", aim_r, Vector2(0, 300))
	var aim_kind := AnimationNodeBlend2.new()
	root.add_node("aim_kind", aim_kind, Vector2(200, 250))
	root.connect_node("aim_kind", 0, "aim_p")
	root.connect_node("aim_kind", 1, "aim_r")
	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	for b in skeleton.get_bone_count():
		var bn := skeleton.get_bone_name(b)
		if not LOWER_BODY.has(bn):
			upper.set_filter_path(NodePath("Skeleton:" + bn), true)
	root.add_node("upper", upper, Vector2(400, 100))
	var sit := AnimationNodeAnimation.new()
	sit.animation = CharacterFactory.ANIM_LIB_NAME + "/sit_idle"
	root.add_node("sit", sit, Vector2(200, -150))
	var seated := AnimationNodeBlend2.new()
	root.add_node("seated", seated, Vector2(300, -50))
	root.connect_node("seated", 0, "loco_ts")
	root.connect_node("seated", 1, "sit")
	root.connect_node("upper", 0, "seated")
	root.connect_node("upper", 1, "aim_kind")
	var hit_anim := AnimationNodeAnimation.new()
	hit_anim.animation = CharacterFactory.ANIM_LIB_NAME + "/hit_front"
	root.add_node("hit_anim", hit_anim, Vector2(400, 300))
	var hit := AnimationNodeOneShot.new()
	hit.fadein_time = 0.06
	hit.fadeout_time = 0.25
	root.add_node("hit", hit, Vector2(600, 100))
	root.connect_node("hit", 0, "upper")
	root.connect_node("hit", 1, "hit_anim")
	root.connect_node("output", 0, "hit")
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	add_child(tree)
	tree.root_node = tree.get_path_to(skeleton.get_parent())
	tree.add_animation_library(CharacterFactory.ANIM_LIB_NAME, anim.get_animation_library(CharacterFactory.ANIM_LIB_NAME))
	tree.root_motion_track = NodePath("Skeleton:Root")
	tree.tree_root = root
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim.stop()
	tree.active = true

## speed in m/s over ground; state "idle"/"walk"/"run"/"sprint"/"mounted"; on_floor false = airborne.
func set_locomotion(speed: float, state := "", _on_floor := true) -> void:
	if _dead:
		return
	_ensure_tree()
	if tree == null:
		return
	var blend := minf(speed, _bs_max)
	tree.set("parameters/loco/blend_position", blend)
	tree.set("parameters/loco_ts/scale", clampf(speed / _bs_max, 1.0, 1.8) if speed > _bs_max else 1.0)
	_seat_target = 1.0 if state == "mounted" else 0.0
	if state == "mounted":
		tree.set("parameters/loco/blend_position", 0.0)

## kind: "" (none), "pistol", "rifle". Raises the upper body into an aim pose over the locomotion.
func set_aim(kind: String) -> void:
	_ensure_tree()
	if tree == null:
		return
	_aim_target = 0.0 if kind == "" else 1.0
	tree.set("parameters/aim_kind/blend_amount", 1.0 if kind in ["rifle", "repeater", "shotgun"] else 0.0)

## A flinch in the direction of the hit (world-space direction the bullet travelled; zone from Damageable).
func hit(info: Dictionary) -> void:
	if _dead:
		return
	_ensure_tree()
	if tree == null:
		return
	var clip := "hit_front"
	if str(info.get("zone", "")) == "head":
		clip = "hit_head"
	else:
		var d: Vector3 = info.get("direction", Vector3.ZERO)
		if d.length() > 0.01:
			var fwd := -global_transform.basis.z
			var right := global_transform.basis.x
			var f := fwd.dot(-d)            # hit coming from the front when the shot travels against our facing
			var r := right.dot(-d)
			if absf(r) > absf(f):
				clip = "hit_right" if r > 0.0 else "hit_left"
			else:
				clip = "hit_front" if f > 0.0 else "hit_back"
	(tree.tree_root as AnimationNodeBlendTree).get_node("hit_anim").animation = CharacterFactory.ANIM_LIB_NAME + "/" + clip
	tree.set("parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func die(info: Dictionary) -> void:
	if _dead:
		return
	_dead = true
	var clip := "death_collapse"
	var d: Vector3 = info.get("direction", Vector3.ZERO)
	if d.length() > 0.01:
		clip = "death_forward" if (-global_transform.basis.z).dot(d) > 0.3 else ("death_back" if (-global_transform.basis.z).dot(d) < -0.3 else "death_collapse")
	if tree:
		tree.active = false
	if anim:
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		play(clip, 0.12)
	auto_blink = false
	clear_look()

func _physics_tick_anim(delta: float) -> void:
	if tree == null or not tree.active:
		return
	_aim_w = move_toward(_aim_w, _aim_target, delta * 6.0)
	tree.set("parameters/upper/blend_amount", _aim_w)
	_seat_w = move_toward(_seat_w, _seat_target, delta * 4.0)
	tree.set("parameters/seated/blend_amount", _seat_w)
	# animation LOD: full rate near the camera, every 3rd/6th frame further out
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var every := 1
	if cam:
		var dist := cam.global_position.distance_to(global_position)
		every = 1 if dist < 35.0 else (3 if dist < 90.0 else 6)
	_lod_acc += delta
	_lod_frame += 1
	if _lod_frame % every == 0:
		tree.advance(_lod_acc)
		_lod_acc = 0.0

func revive() -> void:
	_dead = false
	auto_blink = true
	if anim:
		anim.stop()
	if tree:
		tree.active = true
