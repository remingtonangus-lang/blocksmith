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
## Speech:     lip-sync is automatic: when Game.audio.play_voice(line_id, actor) plays on this character (actor is the
##             character or any ancestor, e.g. its Human/Player), the line's viseme events drive the mouth and its
##             emotion tag (warm, amused, angry, afraid, sad, tired, tense, dry, calm) sets an expression for the line.
##             Lines without viseme timing fall back to text-driven visemes. speak(line_id) -> duration plays a line.
##             speaking (bool)   set_mood(emotion, weight)   lid_follow (eyelids follow vertical gaze)
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
var springs: SpringBoneSimulator3D    # skirt / coat-tail / duster chains (bones "<garment>_c<k>_<i>"), legs collide
var face_meshes: Array[MeshInstance3D] = []
var auto_blink := true
var face_smoothing := 18.0

var speaking := false
var lid_follow := true

# audio-director viseme names -> our viseme aliases
const AUDIO_VISEMES := {"sil": "rest", "rest": "rest", "PP": "MBP", "FF": "FV", "TH": "TH", "DD": "DD", "kk": "KK",
	"CH": "CH", "SS": "SS", "nn": "NN", "RR": "RR", "aa": "AA", "E": "E", "ih": "I", "I": "I", "oh": "O", "O": "O",
	"ou": "U", "U": "U"}
# dialogue emotion tags (design/dialogue/*.json) -> expression weights held while the line plays
const MOODS := {"warm": {"smile": 0.35, "brow_inner_up": 0.1}, "amused": {"smile": 0.6, "squint": 0.2},
	"angry": {"brow_furrow": 0.75, "sneer": 0.25, "press": 0.15}, "afraid": {"brow_inner_up": 0.7, "wide": 0.45},
	"sad": {"brow_inner_up": 0.55, "frown": 0.45}, "tired": {"squint": 0.3, "frown": 0.15},
	"tense": {"brow_furrow": 0.35, "press": 0.25}, "dry": {"squint": 0.15, "brow_raise": 0.1},
	"shout": {"brow_raise": 0.45, "wide": 0.3}, "scared": {"brow_inner_up": 0.7, "wide": 0.5},
	"whisper": {"press": 0.15, "brow_inner_up": 0.2}, "calm": {}, "neutral": {}}

var _face_target: Dictionary = {}    # blend shape -> target weight
var _face_now: Dictionary = {}
var _viseme := ""
var _blink_t := 0.0
var _next_blink := 2.0
var _rng := RandomNumberGenerator.new()
var _mood: Dictionary = {}           # blend shape -> weight from the current line's emotion
var _audio_hooked := false
var _voice_line := ""
var _text_visemes: Array = []        # fallback [[t, alias], ...] when a line has no viseme timing
var _text_t := 0.0
var _shape_idx: Dictionary = {}      # mesh instance id -> {shape: index}
var _lid := 0.0                       # vertical gaze, -1 down .. +1 up


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
		_setup_springs()
		look = CharacterLook.new()
		look.name = "Look"
		skeleton.add_child(look)
	_rng.seed = hash(character_id)
	_next_blink = _rng.randf_range(1.0, 4.0)


func _setup_springs() -> void:
	## Garment spring chains from the generator: one SpringBoneSimulator3D setting per chain, thigh/calf capsules.
	var re := RegEx.new()
	re.compile("^(.+)_c(\\d+)_(\\d+)$")
	var chains := {}
	for i in skeleton.get_bone_count():
		var m := re.search(skeleton.get_bone_name(i))
		if m:
			var key := m.get_string(1) + "_c" + m.get_string(2)
			if not chains.has(key):
				chains[key] = []
			chains[key].append([int(m.get_string(3)), i])
	if chains.is_empty():
		return
	springs = SpringBoneSimulator3D.new()
	springs.name = "ClothSprings"
	skeleton.add_child(springs)
	springs.setting_count = chains.size()
	var idx := 0
	for key in chains:
		var bones: Array = chains[key]
		bones.sort()
		var first: int = bones[0][1]
		var last: int = bones[bones.size() - 1][1]
		var tails := String(key).begins_with("coattails") or String(key).begins_with("dustertails")
		springs.set_root_bone(idx, first)
		springs.set_end_bone(idx, last)
		springs.set_extend_end_bone(idx, true)
		springs.set_end_bone_direction(idx, SkeletonModifier3D.BONE_DIRECTION_FROM_PARENT)
		springs.set_end_bone_length(idx, skeleton.get_bone_rest(last).origin.length())
		springs.set_stiffness(idx, 1.6 if tails else 2.2)
		springs.set_drag(idx, 0.55)
		springs.set_gravity(idx, 0.8)
		springs.set_radius(idx, 0.025)
		springs.set_enable_all_child_collisions(idx, true)
		idx += 1
	for bn in ["LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg"]:
		var b := skeleton.find_bone(bn)
		if b < 0:
			continue
		var child := -1
		for c in skeleton.get_bone_children(b):
			child = c
			break
		var length := skeleton.get_bone_rest(child).origin.length() if child >= 0 else 0.4
		var cap := SpringBoneCollisionCapsule3D.new()
		cap.bone_name = bn
		cap.radius = 0.085 if bn.ends_with("UpperLeg") else 0.06
		cap.height = length + cap.radius * 2.0
		cap.position_offset = Vector3(0, length * 0.5, 0)
		springs.add_child(cap)


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


# --- speech --------------------------------------------------------------------------------------------------------
func speak(line_id: String) -> float:
	## Plays a voiced line positioned on this character; lip-sync and mood follow automatically.
	_hook_audio()
	if Game.audio and Game.audio.has_method("play_voice"):
		return Game.audio.play_voice(line_id, self)
	return 0.0


func set_mood(emotion: String, weight := 1.0) -> void:
	for k in _mood.keys():
		_mood[k] = 0.0
	for e in MOODS.get(emotion, {}):
		for shape in EXPRESSIONS.get(e, [e]):
			_mood[shape] = float(MOODS[emotion][e]) * weight


func _hook_audio() -> void:
	if _audio_hooked or Game == null or Game.audio == null:
		return
	var a = Game.audio
	if a.has_signal("viseme") and a.has_signal("voice_started"):
		a.viseme.connect(_on_audio_viseme)
		a.voice_started.connect(_on_voice_started)
		a.voice_finished.connect(_on_voice_finished)
		_audio_hooked = true


func _is_me(actor) -> bool:
	return actor != null and is_instance_valid(actor) and actor is Node and (actor == self or (actor as Node).is_ancestor_of(self))


func _on_voice_started(line_id: String, actor, dur: float, text: String) -> void:
	if not _is_me(actor):
		return
	speaking = true
	_voice_line = line_id
	var v: Dictionary = Game.audio.voice_lines.get(line_id, {}) if "voice_lines" in Game.audio else {}
	set_mood(str(v.get("emotion", "neutral")))
	_text_visemes.clear()
	_text_t = 0.0
	if (v.get("visemes", []) as Array).is_empty():
		_text_visemes = _visemes_from_text(text if text != "" else str(v.get("text", "")), dur)


func _on_voice_finished(line_id: String, actor) -> void:
	if not _is_me(actor) or line_id != _voice_line:
		return
	speaking = false
	_text_visemes.clear()
	set_viseme("rest", 0.0)
	set_mood("neutral")


func _on_audio_viseme(actor, shape: String, weight: float) -> void:
	if not _is_me(actor):
		return
	var alias: String = AUDIO_VISEMES.get(shape, shape)
	set_viseme(alias, clampf(weight, 0.0, 1.0) * 0.9)


static func _visemes_from_text(text: String, dur: float) -> Array:
	## Crude grapheme -> viseme timeline (only used when the manifest has no viseme timing for a line).
	var map := {"a": "AA", "e": "E", "i": "I", "y": "I", "o": "O", "u": "U", "w": "U", "m": "MBP", "b": "MBP",
		"p": "MBP", "f": "FV", "v": "FV", "l": "L", "t": "DD", "d": "DD", "n": "NN", "s": "SS", "z": "SS",
		"c": "KK", "k": "KK", "g": "KK", "q": "KK", "r": "RR", "j": "CH", "h": "rest", "x": "KK"}
	var t := text.to_lower()
	var letters := 0
	for ch in t:
		if map.has(ch):
			letters += 1
	var out := []
	if letters == 0:
		return out
	var step := clampf(dur * 0.92 / letters, 0.045, 0.16)
	var time := 0.05
	var prev := ""
	for ch in t:
		if ch == " " or ch == "," or ch == "." or ch == "?" or ch == "!":
			if ch != " ":
				out.append([time, "rest"])
				time += step * 2.0
			continue
		if not map.has(ch):
			continue
		var al: String = map[ch]
		if t.substr(t.find(ch), 2) == "th":
			al = "TH"
		if al != prev:
			out.append([time, al])
			prev = al
		time += step
	out.append([time, "rest"])
	return out


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
	var i := GunHands.bone_index(skeleton, "Head")
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
	var _pt0 := Time.get_ticks_usec()
	_physics_tick_anim(delta)
	Game.acc("charanim", _pt0)
	if not _audio_hooked:
		_hook_audio()
	if not _text_visemes.is_empty():
		_text_t += delta
		while not _text_visemes.is_empty() and float(_text_visemes[0][0]) <= _text_t:
			var e: Array = _text_visemes.pop_front()
			set_viseme(str(e[1]), 0.0 if str(e[1]) == "rest" else 0.85)
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
	var km := 1.0 - exp(-4.0 * delta)
	for s in _mood.keys():
		var cur: float = _face_now.get("~" + s, 0.0)
		_face_now["~" + s] = lerpf(cur, _mood[s], km)
	for s in _face_target.keys():
		_face_now[s] = lerpf(_face_now.get(s, 0.0), _face_target[s], k)
	_face_now["blink_L"] = maxf(_face_target.get("blink_L", 0.0), bl)
	_face_now["blink_R"] = maxf(_face_target.get("blink_R", 0.0), bl)
	if lid_follow and look:
		_lid = lerpf(_lid, look.eye_pitch if look.enabled else 0.0, 1.0 - exp(-12.0 * delta))
	_apply_face()


func _apply_face() -> void:
	# final weight = max(explicit target, mood) per shape; eyelids track vertical gaze (look_up/look_down shapes)
	var w: Dictionary = {}
	for s in _face_now.keys():
		if s.begins_with("~"):
			var base: String = s.substr(1)
			w[base] = maxf(w.get(base, 0.0), _face_now[s])
		else:
			w[s] = maxf(w.get(s, 0.0), _face_now[s])
	if lid_follow:
		var up := clampf(_lid, 0.0, 1.0)
		var dn := clampf(-_lid, 0.0, 1.0)
		for side in ["L", "R"]:
			w["look_up_" + side] = up
			w["look_down_" + side] = dn
	for mi in face_meshes:
		var key := mi.get_instance_id()
		if not _shape_idx.has(key):
			var d := {}
			for i in mi.mesh.get_blend_shape_count():
				d[str(mi.mesh.get_blend_shape_name(i))] = i
			_shape_idx[key] = d
		var idx: Dictionary = _shape_idx[key]
		for s in w.keys():
			if idx.has(s):
				mi.set_blend_shape_value(idx[s], w[s])


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
# riding seat clips by horse speed (horse.gd DEFAULT_SPEEDS: walk 1.67, trot 3.75, canter 6.36, gallop 12.8)
const RIDE_POINTS := [["ride_idle", 0.0], ["ride_walk", 1.67], ["ride_trot", 3.75], ["ride_canter", 6.36], ["ride_gallop", 11.0]]
## Ride clips put the hips at the saddle seat (character origin = seat). horse.gd places the rider's origin this far
## below the seat, so the visual is raised by it while riding. Set to 0 if the rider is parented to the seat point.
var ride_seat_drop := 0.78
const LOWER_BODY := ["Root", "Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg",
	"RightLowerLeg", "RightFoot", "RightToes"]

var tree: AnimationTree
var _bs_max := 4.05
var _aim_w := 0.0
var _aim_target := 0.0
var _dead := false
var _lod_acc := 0.0
var _lod_frame := 0
var _game_mode := false
var _ride_w := 0.0
var _ride_target := 0.0

const TREE_CLIPS := ["ride_idle", "ride_walk", "ride_trot", "ride_canter", "ride_gallop", "revolver_reload",
	"lever_reload", "holster", "unholster", "mount_left", "dismount_left",
	"idle", "walk_brisk", "jog", "run", "sprint", "sit_idle", "pistol_aim_two_hand", "rifle_aim",
	"hit_front", "hit_back", "hit_left", "hit_right", "hit_head"]
static var _tree_lib: AnimationLibrary
static var _tree_frame := -1

## Only the clips the gameplay tree uses: AnimationMixer binds every track of every clip it holds, per instance.
static func _gameplay_library(full: AnimationLibrary) -> AnimationLibrary:
	if _tree_lib == null:
		_tree_lib = AnimationLibrary.new()
		for c in TREE_CLIPS:
			if full.has_animation(c):
				_tree_lib.add_animation(c, full.get_animation(c))
	return _tree_lib

func _ensure_tree() -> void:
	if tree != null or anim == null or skeleton == null:
		return
	# one tree build per frame across all characters (a crowd entering view would otherwise build them all at once)
	var f := Engine.get_process_frames()
	if _tree_frame == f:
		return
	_tree_frame = f
	var t0 := Time.get_ticks_usec()
	_build_tree()
	Game.prof("AnimationTree build", t0)

func _build_tree() -> void:
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
	var rbs := AnimationNodeBlendSpace1D.new()
	rbs.min_space = 0.0
	rbs.max_space = 16.0
	rbs.sync = false
	for p in RIDE_POINTS:
		if anim.has_animation(CharacterFactory.ANIM_LIB_NAME + "/" + str(p[0])):
			var ra := AnimationNodeAnimation.new()
			ra.animation = CharacterFactory.ANIM_LIB_NAME + "/" + str(p[0])
			rbs.add_blend_point(ra, float(p[1]), -1, StringName(str(p[0])))
	root.add_node("ride", rbs, Vector2(0, -150))
	var ride_mix := AnimationNodeBlend2.new()
	root.add_node("ride_mix", ride_mix, Vector2(300, -50))
	root.connect_node("ride_mix", 0, "loco_ts")
	root.connect_node("ride_mix", 1, "ride")
	root.connect_node("upper", 0, "ride_mix")
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
	# one-shot actions: full body (mount/dismount, sit...) and upper body (reloads, holstering) over everything else
	var act_up_anim := AnimationNodeAnimation.new()
	act_up_anim.animation = CharacterFactory.ANIM_LIB_NAME + "/holster"
	root.add_node("act_up_anim", act_up_anim, Vector2(600, 300))
	var act_up := AnimationNodeOneShot.new()
	act_up.fadein_time = 0.12
	act_up.fadeout_time = 0.2
	act_up.filter_enabled = true
	for b in skeleton.get_bone_count():
		var bn := skeleton.get_bone_name(b)
		if not LOWER_BODY.has(bn):
			act_up.set_filter_path(NodePath("Skeleton:" + bn), true)
	root.add_node("act_up", act_up, Vector2(800, 100))
	root.connect_node("act_up", 0, "hit")
	root.connect_node("act_up", 1, "act_up_anim")
	var act_anim := AnimationNodeAnimation.new()
	act_anim.animation = CharacterFactory.ANIM_LIB_NAME + "/mount_left"
	root.add_node("act_anim", act_anim, Vector2(800, 300))
	var act := AnimationNodeOneShot.new()
	act.fadein_time = 0.15
	act.fadeout_time = 0.2
	root.add_node("act", act, Vector2(1000, 100))
	root.connect_node("act", 0, "act_up")
	root.connect_node("act", 1, "act_anim")
	root.connect_node("output", 0, "act")
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	add_child(tree)
	tree.root_node = tree.get_path_to(skeleton.get_parent())
	tree.add_animation_library(CharacterFactory.ANIM_LIB_NAME, _gameplay_library(anim.get_animation_library(CharacterFactory.ANIM_LIB_NAME)))
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
	var riding := state == "mounted" or state == "ride"
	if riding:
		tree.set("parameters/loco/blend_position", 0.0)
		tree.set("parameters/ride/blend_position", clampf(speed, 0.0, 16.0))
	_ride_target = 1.0 if riding else 0.0

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

## One-shot action over the current state: full body ("mount_left", "dismount_left", "sit_down", "stand_up",
## "pick_up", ...) or upper body only ("revolver_reload", "lever_reload", "holster", "unholster", "drink", "wave").
## Returns the clip length (0 if missing).
func play_action(clip: String, upper_body := false) -> float:
	if _dead:
		return 0.0
	_ensure_tree()
	if tree == null or not anim.has_animation(CharacterFactory.ANIM_LIB_NAME + "/" + clip):
		return 0.0
	if _tree_lib and not _tree_lib.has_animation(clip):
		# rarely used clips join the shared gameplay library the first time anyone needs them
		_tree_lib.add_animation(clip, anim.get_animation(CharacterFactory.ANIM_LIB_NAME + "/" + clip))
	var node := "act_up" if upper_body else "act"
	(tree.tree_root as AnimationNodeBlendTree).get_node(node + "_anim").animation = CharacterFactory.ANIM_LIB_NAME + "/" + clip
	tree.set("parameters/%s/request" % node, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return anim.get_animation(CharacterFactory.ANIM_LIB_NAME + "/" + clip).length

## kind "revolver"/"pistol" or "rifle"/"repeater" -> reload clip (upper body).
func reload(kind := "revolver") -> float:
	return play_action("lever_reload" if kind in ["rifle", "repeater", "carbine"] else "revolver_reload", true)

func holster() -> float:
	return play_action("holster", true)

func unholster() -> float:
	return play_action("unholster", true)

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
	# the clip starts the fall, then physics takes over (src/combat/ragdoll.gd; LOD-limited, settles and freezes)
	Ragdoll.begin(self, info, 0.28)

func _physics_tick_anim(delta: float) -> void:
	if tree == null or not tree.active:
		return
	_aim_w = move_toward(_aim_w, _aim_target, delta * 6.0)
	tree.set("parameters/upper/blend_amount", _aim_w)
	_ride_w = move_toward(_ride_w, _ride_target, delta * 4.0)
	tree.set("parameters/ride_mix/blend_amount", _ride_w)
	if model:
		model.position.y = ride_seat_drop * _ride_w
	# animation LOD: full rate near the camera, every 3rd/6th frame further out
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var every := 1
	if cam:
		var dist := cam.global_position.distance_to(global_position)
		every = 1 if dist < 35.0 else (3 if dist < 90.0 else 6)
		if springs:
			springs.active = dist < 30.0
	_lod_acc += delta
	_lod_frame += 1
	if _lod_frame % every == 0:
		tree.advance(_lod_acc)
		_lod_acc = 0.0

func revive() -> void:
	Ragdoll.cancel(self)
	_dead = false
	auto_blink = true
	if anim:
		anim.stop()
	if tree:
		tree.active = true
