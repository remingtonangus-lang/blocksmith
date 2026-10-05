class_name MissionDirector
extends Node
## Runs story missions written as coroutines (src/missions/*/*.gd, extending Mission). Provides the verbs missions
## await: goto, say, spawn, wait_dead, interact, wait, checkpoint, cinematic shots; draws objectives on the HUD and
## mission start markers in the world; handles failure/retry from checkpoints; and has an autopilot used by the
## mission bot (--bot missions) to play every mission end to end headless and catch softlocks.

signal mission_started(id: String)
signal mission_completed(id: String)
signal mission_failed(id: String, reason: String)
signal objective_changed(text: String)

const MISSIONS := [
	"res://src/missions/ch1/rider_from_the_west.gd",
	"res://src/missions/ch1/the_drover.gd",
	"res://src/missions/ch1/inquiries.gd",
	"res://src/missions/ch1/greers_post.gd",
	"res://src/missions/ch1/fire_at_willow_bend.gd",
]

var dialogue := {}              # line id -> {speaker, line, emotion}
var speakers := {}
var active: Mission = null
var objective := ""
var completed: Array[String] = []
var autopilot := false          # bots: teleport to goals, skip dialogue waits, auto-resolve fights
var step_timeout := 240.0       # softlock oracle: any single await longer than this fails the mission
var _abort := false
var _markers := {}
var spawned: Array = []
var cine := false               # cinematic dialogue camera active
var _cine_cam: Camera3D
var _cine_from := Transform3D()
var _cine_to := Transform3D()
var _cine_t := 0.0
var _cine_dur := 1.0
var _bars: Array = []
var _last_speaker: Node3D = null

func _ready() -> void:
	Game.set("missions", self)
	_load_dialogue("res://design/dialogue/ch1.json")

func _load_dialogue(path: String) -> void:
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return
	var j = JSON.parse_string(txt)
	if j == null:
		return
	for k in j.get("speakers", {}).keys():
		speakers[k] = j.speakers[k]
	for l in j.get("lines", []):
		dialogue[l.id] = l

func available() -> Array:
	var out := []
	for path in MISSIONS:
		var m: Mission = load(path).new()
		if completed.has(m.id):
			continue
		var ok := true
		for req in m.requires:
			if not completed.has(req):
				ok = false
		if ok:
			out.append(m)
	return out

func start(m: Mission) -> void:
	if active != null:
		return
	active = m
	_abort = false
	Game.log_event("mission_start", {"id": m.id})
	mission_started.emit(m.id)
	if Game.hud:
		Game.hud.notice(m.title, 5.0)
	var ok: bool = await _run(m)
	_cleanup()
	active = null
	if ok:
		completed.append(m.id)
		Game.log_event("mission_complete", {"id": m.id})
		if Game.state and not autopilot:
			Game.state.save_game("auto")
		mission_completed.emit(m.id)
		if Game.hud:
			Game.hud.notice("%s — complete" % m.title, 5.0)
	set_objective("")

func _run(m: Mission) -> bool:
	var result = await m.run(self)
	return result != false and not _abort

func fail(reason: String) -> void:
	_abort = true
	Game.log_event("mission_fail", {"id": active.id if active else "", "reason": reason})
	mission_failed.emit(active.id if active else "", reason)
	if Game.hud:
		Game.hud.notice("Mission failed: " + reason, 5.0)

func aborted() -> bool:
	return _abort

func set_objective(text: String) -> void:
	objective = text
	objective_changed.emit(text)
	if Game.hud and Game.hud.has_method("prompt"):
		Game.hud.prompt(text)

func _cleanup() -> void:
	cine_end()
	for n in spawned:
		if is_instance_valid(n):
			n.queue_free()
	spawned.clear()

# ------------------------------------------------------------------ verbs (await these)
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds if not autopilot else minf(seconds, 0.2)).timeout

# ------------------------------------------------------------------ cinematics
## Enter a letterboxed dialogue scene: the camera frames each speaker (shot / reverse shot over the listener's
## shoulder) with a slow dolly drift; player control and HUD pause until cine_end().
func cine_begin() -> void:
	if Game.headless or autopilot or cine:
		return
	cine = true
	_cine_cam = Camera3D.new()
	_cine_cam.fov = 40.0
	_cine_cam.attributes = Game.camera.attributes if Game.camera else null
	add_child(_cine_cam)
	_cine_cam.global_transform = Game.camera.global_transform
	_cine_cam.make_current()
	if Game.hud:
		Game.hud.cinematic = true
		var layer := CanvasLayer.new()
		layer.layer = 11
		add_child(layer)
		for top in [true, false]:
			var r := ColorRect.new()
			r.color = Color.BLACK
			r.anchor_right = 1.0
			if top:
				r.anchor_bottom = 0.0
				r.offset_bottom = 0.0
			else:
				r.anchor_top = 1.0
				r.anchor_bottom = 1.0
			layer.add_child(r)
			_bars.append(r)
			var tw := create_tween()
			tw.tween_property(r, "offset_bottom" if top else "offset_top", 120.0 if top else -120.0, 0.6)
		_bars.append(layer)
	if Game.player:
		Game.player.set("bot_driven", true)
		Game.player.intent.move = Vector2.ZERO

func cine_end() -> void:
	if not cine:
		return
	cine = false
	if Game.camera:
		Game.camera.make_current()
	if _cine_cam:
		_cine_cam.queue_free()
	for b in _bars:
		if is_instance_valid(b):
			b.queue_free()
	_bars.clear()
	if Game.hud:
		Game.hud.cinematic = false
	if Game.player and not Game.args.has("bot"):
		Game.player.set("bot_driven", false)

func _frame(speaker: Node3D, listener: Node3D) -> void:
	if not cine or speaker == null or not is_instance_valid(speaker):
		return
	var face := speaker.global_position + Vector3(0, 1.58, 0)
	var other := listener.global_position + Vector3(0, 1.55, 0) if listener != null and is_instance_valid(listener) else face + Vector3(2, 0, 2)
	var axis := (face - other)
	axis.y = 0
	if axis.length() < 0.3:
		axis = Vector3(0, 0, 1)
	axis = axis.normalized()
	var side := axis.cross(Vector3.UP).normalized()
	# over the listener's shoulder, slightly off-axis, at eye height; alternate sides for variety
	var flip := 1.0 if (hash(speaker.name) % 2 == 0) else -1.0
	var cam_pos := other - axis * 0.9 + side * 0.55 * flip + Vector3(0, 0.08, 0)
	var dist := cam_pos.distance_to(face)
	if dist < 1.2:
		cam_pos = face - axis * 2.2 + side * 0.4
	var from := Transform3D(Basis(), cam_pos).looking_at(face, Vector3.UP)
	var to := Transform3D(Basis(), cam_pos + side * 0.12 * flip + axis * 0.15).looking_at(face + Vector3(0, -0.02, 0), Vector3.UP)
	_cine_from = from
	_cine_to = to
	_cine_t = 0.0
	_cine_cam.global_transform = from

func _process(dt: float) -> void:
	if cine and _cine_cam:
		_cine_t += dt
		var f := clampf(_cine_t / maxf(_cine_dur, 0.1), 0.0, 1.0)
		f = f * f * (3.0 - 2.0 * f)
		_cine_cam.global_transform = _cine_from.interpolate_with(_cine_to, f)

## Say a dialogue line: subtitles + voice (if rendered), returns after the line's duration.
func say(line_id: String, speaker_node: Node3D = null) -> void:
	var l: Dictionary = dialogue.get(line_id, {"speaker": "", "line": "[" + line_id + "]"})
	var spk: Dictionary = speakers.get(l.speaker, {"name": l.speaker.capitalize()})
	var dur := clampf(float(str(l.line).length()) * 0.065 + 0.6, 1.4, 9.0)
	if Game.audio and Game.audio.has_method("play_voice"):
		var d = Game.audio.play_voice(line_id, speaker_node)
		if typeof(d) == TYPE_FLOAT and d > 0.0:
			dur = d + 0.25
	if cine and speaker_node != null:
		var listener: Node3D = _last_speaker if _last_speaker != speaker_node else (Game.player if speaker_node != Game.player else null)
		_cine_dur = dur + 0.5
		_frame(speaker_node, listener)
	if speaker_node != null:
		_last_speaker = speaker_node
		if speaker_node is Human:
			speaker_node.intent.face = (_last_speaker if _last_speaker != speaker_node and _last_speaker != null else Game.player).global_position - speaker_node.global_position
	if Game.hud:
		Game.hud.subtitle(spk.get("name", ""), l.line, dur)
	Game.log_event("say", {"id": line_id})
	await wait(dur)

## Reach a point (optionally mounted). Shows the objective and a world marker; returns when within radius.
func goto(pos: Vector3, radius: float, text: String, mounted := false) -> void:
	set_objective(text)
	var marker := _marker(pos)
	var t := 0.0
	while not _abort:
		var p: Vector3 = Game.player.global_position
		if autopilot and t > 0.3:
			_teleport_player(pos + Vector3(1.0, 0, 1.0))
		if Vector2(p.x - pos.x, p.z - pos.z).length() < radius and (not mounted or Game.player.get("on_horse") != null or autopilot):
			break
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > step_timeout:
			fail("softlock: never reached '%s'" % text)
	marker.queue_free()

## Spawn a group of hostile/neutral people around a point. Returns the Human nodes.
func spawn_group(center: Vector3, count: int, opts: Dictionary, spread := 6.0) -> Array:
	var out := []
	var r := RandomNumberGenerator.new()
	r.seed = hash(center) ^ count
	for i in count:
		var p := center + Vector3(r.randf_range(-spread, spread), 0, r.randf_range(-spread, spread))
		p.y = Game.world.height(p.x, p.z) + 0.3
		Game.terrain.ensure_collision_at(p)
		var o := opts.duplicate()
		o["seed"] = int(opts.get("seed", 100)) + i
		var h := Human.spawn(Game.main, p, o)
		out.append(h)
		spawned.append(h)
	for h in out:
		h.brain.group = out
	return out

## Wait until every Human in the group is dead or surrendered.
func wait_dead(group: Array, text: String) -> void:
	set_objective(text)
	var t := 0.0
	while not _abort:
		var left := group.filter(func(h): return is_instance_valid(h) and h.alive and h.brain.state != h.brain.State.SURRENDER)
		if left.is_empty():
			break
		if autopilot and t > 1.0:
			for h in left:
				h.damageable.apply_hit({"amount": 999.0, "zone": "chest", "attacker": Game.player})
		if Game.player.damageable and not Game.player.damageable.alive:
			fail("Ruth died")
			return
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > step_timeout:
			fail("softlock: fight '%s' never resolved" % text)

## Wait for the player to press interact near a point.
func interact(pos: Vector3, prompt: String) -> void:
	set_objective(prompt)
	var marker := _marker(pos)
	var t := 0.0
	while not _abort:
		var near := Game.player.global_position.distance_to(pos) < 2.5
		if Game.hud:
			Game.hud.prompt(("[E]  " + prompt) if near else prompt)
		if (near and (Input.is_action_just_pressed("interact") or Game.player.intent.get("interact", false))) or autopilot:
			if autopilot:
				_teleport_player(pos)
			break
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > step_timeout:
			fail("softlock: never interacted '%s'" % prompt)
	marker.queue_free()

func checkpoint(name: String) -> void:
	Game.log_event("checkpoint", {"mission": active.id if active else "", "name": name})

func set_time(hours: float) -> void:
	if Game.sky:
		Game.sky.set_time(hours)

func set_weather(w: String) -> void:
	if Game.sky:
		Game.sky.set_weather(SkySystem.Weather.get(w.to_upper(), SkySystem.Weather.FAIR), false)

func place_player(pos: Vector3, yaw: float) -> void:
	_teleport_player(pos)
	Game.player.cam_yaw = yaw
	Game.player.facing = yaw

func _teleport_player(pos: Vector3) -> void:
	var p := pos
	p.y = Game.world.height(p.x, p.z) + 0.6
	Game.terrain.ensure_collision_at(p)
	var horse = Game.player.get("on_horse")
	if horse != null and horse is Node3D and horse != self:
		horse.global_position = p
	else:
		Game.player.global_position = p
		Game.player.velocity = Vector3.ZERO

## A column of light marking the goal (visible from afar, fades up close).
func _marker(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	if Game.headless:
		return n
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = 40.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	m.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.5, 0.18)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 6.0
	mat.distance_fade_max_distance = 30.0
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(m)
	var y := Game.world.height(pos.x, pos.z)
	n.global_position = Vector3(pos.x, y + 20.0, pos.z)
	return n
