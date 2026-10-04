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
	for n in spawned:
		if is_instance_valid(n):
			n.queue_free()
	spawned.clear()

# ------------------------------------------------------------------ verbs (await these)
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds if not autopilot else minf(seconds, 0.2)).timeout

## Say a dialogue line: subtitles + voice (if rendered), returns after the line's duration.
func say(line_id: String, speaker_node: Node3D = null) -> void:
	var l: Dictionary = dialogue.get(line_id, {"speaker": "", "line": "[" + line_id + "]"})
	var spk: Dictionary = speakers.get(l.speaker, {"name": l.speaker.capitalize()})
	var dur := clampf(float(str(l.line).length()) * 0.065 + 0.6, 1.4, 9.0)
	if Game.audio and Game.audio.has_method("play_voice"):
		var d = Game.audio.play_voice(line_id, speaker_node)
		if typeof(d) == TYPE_FLOAT and d > 0.0:
			dur = d + 0.25
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
