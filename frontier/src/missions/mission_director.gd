class_name MissionDirector
extends Node
## Runs story missions written as coroutines (src/missions/*/*.gd, extending Mission). Provides the verbs missions
## await: goto, say, spawn, wait_dead, interact, wait, checkpoint, cinematic shots; draws objectives on the HUD and
## mission start markers in the world; handles failure/retry from checkpoints; and has an autopilot used by the
## mission bot (--bot missions) to play every mission end to end headless and catch softlocks.
## Chapter 3 verbs: mount_up, lead (someone follows Ruth), ride_with (escort a rider on horseback), drive (push a
## herd), stampede (turn the leaders), defend (hold a point), track (mission props).
## Story verbs added for chapter 2: choose (dialogue choices; bots follow --choices 0,1,0), follow (escort an NPC),
## sneak_to (reach a point unseen), escape (timed getaway), paper (read a poster / front page), minigame (poker...),
## post_bounty / clear_bounty (story-driven law). `--pokertest` runs the poker self-test at boot and quits.
##
## Failure and retry: when a mission fails (Ruth dies, a softlock, fail()), a paper panel offers Retry from
## checkpoint / Restart mission / Abandon. Missions need no special structure: checkpoint(name) records where Ruth
## stood (time, weather, horse), the world state at mission start is snapshotted, and every decision (choices,
## minigame results, sneak/stampede/defend outcomes) is recorded in order. Retrying restores the snapshot and runs
## the mission again from the top in *resume* mode: verbs return at once and silently, spawn_group re-creates the
## people, choices replay what was chosen, fights resolve without consequences, until the same checkpoint is
## reached; there Ruth is put back where she stood and play continues live. Abandon undoes the mission's effects.

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
	"res://src/missions/ch2/the_lantern.gd",
	"res://src/missions/ch2/a_gentlemans_game.gd",
	"res://src/missions/ch2/thornwood.gd",
	"res://src/missions/ch2/the_exchange.gd",
	"res://src/missions/ch2/terms.gd",
	"res://src/missions/ch3/halvorsen_water.gd",
	"res://src/missions/ch3/a_leg_to_set.gd",
	"res://src/missions/ch3/through_the_breaks.gd",
	"res://src/missions/ch3/water_rights.gd",
	"res://src/missions/ch3/the_dry_fork.gd",
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
var _choice_queue: Array = []   # bots: --choices 0,1,0 answers choose()/auto_choice() in order
var _choice_parsed := false
var _escorted: Array = []       # NPCs whose brain a mission has taken over (follow / npc_walk_to)
var resuming := false            # replaying a mission up to the checkpoint being retried
var _resume_ordinal := 0
var _cp_count := 0               # checkpoints passed this attempt
var _cp := {}                    # last checkpoint reached live: {name, ordinal, decisions, pos, yaw, hours, weather, mounted}
var _decisions: Array = []       # [{v, auto}] in the order the mission asked for them
var _replay: Array = []
var _auto_log: Array = []        # [decision index, value] for every --choices value consumed
var _start_snap := {}            # world state + where Ruth stood when the mission began
var test_fail := ""              # bots: "mission_id:checkpoint" fails the mission right after that checkpoint, once
var _test_fail_done := false
var attempts := 0
var _props: Array = []           # herds, outriders, markers: freed with the mission's people

func _ready() -> void:
	Game.set("missions", self)
	for i in range(1, 10):
		var path := "res://design/dialogue/ch%d.json" % i
		if FileAccess.file_exists(path):
			_load_dialogue(path)
	if Game.args.has("pokertest"):
		_pokertest.call_deferred()

## --pokertest: hand evaluation, betting, side pots and the stacked-deck beat, headless; prints POKERTEST and quits.
func _pokertest() -> void:
	var res: Dictionary = load("res://src/minigames/poker_engine.gd").selftest()
	for l in res.lines:
		print(l)
	print("POKERTEST %s (%d failed)" % ["PASS" if res.ok else "FAIL", res.fails])
	get_tree().quit(0 if res.ok else 1)

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
	_start_snap = _snapshot()
	_decisions = []
	_replay = []
	_auto_log = []
	_cp = {}
	_cp_count = 0
	resuming = false
	attempts = 1
	var ok := false
	while true:
		ok = await _run(active)
		_cleanup()
		if ok:
			break
		var pick: String = await _failure_menu()
		Game.log_event("mission_retry", {"id": active.id, "pick": pick, "checkpoint": _cp.get("name", "")})
		if pick == "abandon":
			_restore_state(_start_snap)
			_place_from(_start_snap)
			if not autopilot and not Game.args.has("bot") and not Game.args.has("free_roam"):
				_continue_story.call_deferred(120.0)     # the story picks itself up again after a while
			break
		attempts += 1
		_restore_state(_start_snap)
		var keep := 0
		if pick == "retry" and not _cp.is_empty():
			keep = int(_cp.decisions)
			resuming = true
			_resume_ordinal = int(_cp.ordinal)
		else:
			resuming = false
			_place_from(_start_snap)
			_cp = {}
		# answers the bot's --choices gave after the retry point are asked again, so give them back
		var back := []
		for e in _auto_log:
			if int(e[0]) >= keep:
				back.append(e[1])
		_choice_queue = back + _choice_queue
		_auto_log = _auto_log.filter(func(e): return int(e[0]) < keep)
		_replay = _decisions.slice(0, keep)
		_decisions = []
		_cp_count = 0
		_abort = false
		active = active.get_script().new()
	resuming = false
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
	if ok and not autopilot and not Game.args.has("bot") and not Game.args.has("free_roam"):
		_continue_story.call_deferred()

## Normal play: when a mission ends, the next one in the chain that starts by itself (no start_pos) follows after a
## breath, so the story plays through without a menu.
func _continue_story(delay := 6.0) -> void:
	await get_tree().create_timer(delay, false).timeout
	if active != null:
		return
	for m in available():
		if m.start_pos == Vector3.ZERO:
			start(m)
			return

func _run(m: Mission) -> bool:
	var result = await m.run(self)
	if resuming:
		# the mission ended before the checkpoint came round again (a branch changed): play on from here
		resuming = false
	return result != false and not _abort

func _physics_process(_dt: float) -> void:
	# any death during a mission fails it (fights already check; this covers falls, ambushes on the road...)
	if active != null and not _abort and not resuming and Game.player and Game.player.damageable \
			and not Game.player.damageable.alive:
		fail("Ruth died")

# ------------------------------------------------------------------ failure, checkpoints, retry
func _snapshot() -> Dictionary:
	var st = Game.state
	var snap := {}
	if st:
		snap = {"standing": st.standing, "money": st.money, "inventory": st.inventory.duplicate(true),
			"bounties": st.bounties.duplicate(true), "wanted": st.wanted, "wanted_county": st.wanted_county,
			"flags": st.flags.duplicate(true), "kills": st.kills.duplicate(true)}
	snap["where"] = _where()
	return snap

func _where() -> Dictionary:
	var p = Game.player
	return {"pos": p.global_position if p else Vector3.ZERO, "yaw": float(p.facing) if p else 0.0,
		"hours": Game.sky.hours if Game.sky else 12.0, "weather": Game.sky.weather if Game.sky else 1,
		"mounted": p != null and p.get("on_horse") != null}

func _restore_state(snap: Dictionary) -> void:
	var st = Game.state
	if st and snap.has("money"):
		st.standing = snap.standing
		st.money = snap.money
		st.inventory = snap.inventory.duplicate(true)
		st.bounties = snap.bounties.duplicate(true)
		st.wanted = snap.wanted
		st.wanted_county = snap.wanted_county
		st.flags = snap.flags.duplicate(true)
		st.kills = snap.kills.duplicate(true)
		st.money_changed.emit(st.money)
		st.wanted_changed.emit(st.wanted, st.wanted_county)

## Put Ruth back where a snapshot says she stood (healed, on or off her horse as she was), with its time and weather.
func _place_from(snap: Dictionary) -> void:
	var w: Dictionary = snap.get("where", {})
	if w.is_empty() or Game.player == null:
		return
	var p = Game.player
	if p.damageable:
		p.damageable.alive = true
		p.damageable.health = p.damageable.max_health
		p.set("health", p.damageable.max_health)
	var horse = Horse.player_horse if is_instance_valid(Horse.player_horse) else null
	var on = p.get("on_horse")
	if not w.mounted and on != null and on.has_method("dismount"):
		on.dismount()
	_teleport_player(w.pos)
	if w.mounted and p.get("on_horse") == null and horse != null:
		_put_on_ground(horse, w.pos + Vector3(1.5, 0, 0))
		horse.mount(p, 0.0)
	p.facing = w.yaw
	p.cam_yaw = w.yaw
	if Game.sky:
		Game.sky.set_time(w.hours)
		Game.sky.set_weather(w.weather, true)

func _failure_menu() -> String:
	var reason := str(_last_fail)
	# wait for Ruth to get back up if she died (the player respawns on her own after a beat)
	var t := 0.0
	while Game.player and Game.player.damageable and not Game.player.damageable.alive and t < 8.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var opts := []
	var keys := []
	if not _cp.is_empty():
		opts.append("Retry from the last checkpoint")
		keys.append("retry")
	opts.append("Restart the mission")
	keys.append("restart")
	opts.append("Abandon it for now")
	keys.append("abandon")
	var menus = Game.get("menus")
	if autopilot or Game.headless or menus == null:
		# bots: retry from the checkpoint (else restart); give up after three attempts
		return "abandon" if attempts >= 3 else keys[0]
	cine_end()
	while true:
		var p: PanelContainer = load("res://src/missions/choice_panel.gd").new()
		p.build(menus, "Mission failed — %s." % reason, opts)
		menus._push(p)
		var r: int = await p.chosen
		if r >= 0:
			if is_instance_valid(p) and menus.stack.size() > 0 and menus.stack.back() == p:
				menus.back()
			return keys[r]
	return "abandon"

## Record a decision (live) or hand back the recorded one (resume). auto: it came from the bots' --choices.
func _decide(live_value, auto := false):
	if resuming and not _replay.is_empty():
		var e: Dictionary = _replay.pop_front()
		_decisions.append(e)
		return e.v
	_decisions.append({"v": live_value, "auto": auto})
	return live_value

func _replaying() -> bool:
	return resuming and not _replay.is_empty()

var _last_fail := ""

func fail(reason: String) -> void:
	if _abort:
		return
	_abort = true
	_last_fail = reason
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
	for n in _escorted.duplicate():
		npc_release(n)
	_escorted.clear()
	for n in spawned:
		if is_instance_valid(n):
			n.queue_free()
	spawned.clear()
	_free_props()

# ------------------------------------------------------------------ verbs (await these)
func wait(seconds: float) -> void:
	if _abort or resuming:
		return
	await get_tree().create_timer(seconds if not autopilot else minf(seconds, 0.2)).timeout

# ------------------------------------------------------------------ cinematics
## Enter a letterboxed dialogue scene: the camera frames each speaker (shot / reverse shot over the listener's
## shoulder) with a slow dolly drift; player control and HUD pause until cine_end().
func cine_begin() -> void:
	if Game.headless or autopilot or cine or resuming or _abort:
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
	if _abort or resuming:
		return
	var dur := say_async(line_id, speaker_node)
	await wait(dur)

## Start a line without waiting for it (walk-and-talk); returns its duration in seconds.
func say_async(line_id: String, speaker_node: Node3D = null) -> float:
	if _abort or resuming:
		return 0.0
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
	return dur

## Reach a point (optionally mounted). Shows the objective and a world marker; returns when within radius.
func goto(pos: Vector3, radius: float, text: String, mounted := false) -> void:
	if _abort:
		return
	if resuming:
		_teleport_player(pos + Vector3(1.0, 0, 1.0))
		return
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
	if _abort:
		return
	if resuming:
		# already fought on the first attempt: settle it quietly (no attacker, so no crimes or Standing)
		for h in group:
			if is_instance_valid(h) and h.alive and h.brain.state != h.brain.State.SURRENDER:
				h.damageable.apply_hit({"amount": 999.0, "zone": "chest"})
		return
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
	if _abort:
		return
	if resuming:
		_teleport_player(pos)
		return
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
	if _abort:
		return
	_cp_count += 1
	var mid: String = active.id if active else ""
	if resuming:
		if _cp_count < _resume_ordinal:
			return
		# back at the checkpoint being retried: put Ruth where she stood and play on live
		resuming = false
		_replay.clear()
		_place_from({"where": _cp.where})
		Game.log_event("checkpoint_resumed", {"mission": mid, "name": name, "attempt": attempts})
		if Game.hud:
			Game.hud.notice("Checkpoint — %s" % name.capitalize().replace("_", " "), 3.0)
		return
	_cp = {"name": name, "ordinal": _cp_count, "decisions": _decisions.size(), "where": _where()}
	Game.log_event("checkpoint", {"mission": mid, "name": name})
	if test_fail != "" and not _test_fail_done and test_fail == "%s:%s" % [mid, name]:
		_test_fail_done = true
		(func(): fail("forced failure (bot test) after '%s'" % name)).call_deferred()

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

# ------------------------------------------------------------------ chapter 2 verbs
## Bots answer choices deterministically: --choices 0,1,0 is consumed in order (choose, auto_choice), then 0.
func auto_choice(n: int) -> int:
	if not _choice_parsed:
		_choice_parsed = true
		for t in str(Game.args.get("choices", "")).split(",", false):
			if t.strip_edges().is_valid_int():
				_choice_queue.append(int(t.strip_edges()))
	var v := 0
	if not _choice_queue.is_empty():
		v = int(_choice_queue.pop_front())
		_auto_log.append([_decisions.size(), v])
	return clampi(v, 0, maxi(n - 1, 0))

## A dialogue choice on a paper panel (mouse, number keys 1-9, controller). Returns the chosen index. Under
## autopilot (or headless) the answer comes from --choices.
func choose(prompt: String, options: Array) -> int:
	if options.is_empty() or _abort:
		return 0
	if _replaying():
		var was: int = clampi(int(_decide(0)), 0, options.size() - 1)
		Game.log_event("choice_replayed", {"mission": active.id if active else "", "index": was})
		return was
	var idx := 0
	var auto := false
	var menus = Game.get("menus")
	if autopilot or Game.headless or menus == null:
		idx = auto_choice(options.size())
		auto = true
	else:
		var hint := objective
		set_objective("")
		while not _abort:
			var p: PanelContainer = load("res://src/missions/choice_panel.gd").new()
			p.build(menus, prompt, options)
			menus._push(p)
			var r: int = await p.chosen
			if r >= 0:
				idx = r
				if is_instance_valid(p) and menus.stack.size() > 0 and menus.stack.back() == p:
					menus.back()
				break
		set_objective(hint)
	if Game.audio and Game.audio.has_method("ui"):
		Game.audio.ui("select")
	if _abort:
		return 0
	_decide(idx, auto)
	Game.log_event("choice", {"mission": active.id if active else "", "prompt": prompt, "index": idx, "option": str(options[idx])})
	return idx

## Take an NPC off its brain and walk it to a point (missions only; npc_release gives it back).
func npc_walk_to(npc, dest: Vector3, speed := Human.WALK) -> void:
	if npc == null or not is_instance_valid(npc) or not (npc is Human):
		return
	var h: Human = npc
	if h.brain:
		h.brain.set_physics_process(false)
	if not _escorted.has(h):
		_escorted.append(h)
	h.intent.move_to = dest
	h.intent.speed = speed
	h.intent.aim_at = null
	h.intent.crouch = false
	h.intent.face = null

## Take an NPC off its brain and keep it standing still, looking at a point (watchmen, card players, sentries).
func npc_hold(npc, look_at: Vector3) -> void:
	if npc == null or not is_instance_valid(npc) or not (npc is Human):
		return
	npc_walk_to(npc, npc.global_position)
	var h: Human = npc
	h.intent.move_to = null
	var d := look_at - h.global_position
	h.intent.face = d
	h.facing = atan2(-d.x, -d.z)

func npc_release(npc) -> void:
	_escorted.erase(npc)
	if npc == null or not is_instance_valid(npc) or not (npc is Human):
		return
	var h: Human = npc
	h.intent.move_to = null
	h.intent.speed = Human.WALK
	if h.brain:
		h.brain.set_physics_process(true)
		h.brain.home = h.global_position

func _put_on_ground(n: Node3D, pos: Vector3) -> void:
	var p := pos
	p.y = Game.world.height(p.x, p.z) + 0.3
	Game.terrain.ensure_collision_at(p)
	n.global_position = p
	if n is CharacterBody3D:
		(n as CharacterBody3D).velocity = Vector3.ZERO

## Escort / follow an NPC who walks to dest. The NPC waits when Ruth falls behind; the mission fails if she strays
## more than 120 m or the NPC dies. `lines` are said along the way (walk-and-talk): line ids, spoken by Ruth when
## the line's speaker is "ruth", else by the NPC.
func follow(npc: Node3D, text: String, dest: Vector3, radius := 6.0, lines: Array = []) -> void:
	if _abort:
		return
	if resuming and npc != null and is_instance_valid(npc):
		_put_on_ground(npc, dest)
		npc_release(npc)
		return
	if npc == null or not is_instance_valid(npc):
		fail("nobody to follow for '%s'" % text)
		return
	set_objective(text)
	var marker := _marker(dest)
	var who := str(npc.get("display_name")) if npc.get("display_name") != null else "them"
	npc_walk_to(npc, dest)
	var talk := lines.duplicate()
	var talk_t := 1.0
	var t := 0.0
	var anchor := npc.global_position
	var still_t := 0.0
	var limit := maxf(step_timeout, Vector2(dest.x - anchor.x, dest.z - anchor.z).length() / Human.WALK * 2.5 + 60.0)
	while not _abort:
		if not is_instance_valid(npc) or (npc.get("alive") == false):
			fail("%s was killed" % who)
			break
		var np := npc.global_position
		if autopilot and t > 0.3:
			_put_on_ground(npc, dest)
			_teleport_player(dest + Vector3(1.5, 0, 1.5))
			np = npc.global_position
		if Vector2(np.x - dest.x, np.z - dest.z).length() < radius:
			break
		var pd: float = Game.player.global_position.distance_to(np)
		if pd > 120.0:
			fail("You lost %s" % who)
			break
		var h: Human = npc as Human
		if h != null:
			if pd > 16.0:
				h.intent.move_to = null
				h.intent.face = Game.player.global_position - np
			else:
				h.intent.move_to = dest
				h.intent.face = null
				h.intent.speed = Human.JOG if Game.player.get("on_horse") != null else Human.WALK
			# walked into something: hop a few metres along the way rather than stand there forever
			if h.intent.move_to != null:
				still_t += get_physics_process_delta_time()
				if still_t > 5.0:
					if np.distance_to(anchor) < 0.8:
						var dir := Vector3(dest.x - np.x, 0, dest.z - np.z).normalized()
						_put_on_ground(npc, np + dir * 3.0)
						Game.log_event("follow_unstick", {"npc": str(npc.name)})
					still_t = 0.0
					anchor = npc.global_position
			else:
				still_t = 0.0
				anchor = np
		talk_t -= get_physics_process_delta_time()
		if not talk.is_empty() and (talk_t <= 0.0 or autopilot):
			var id: String = talk.pop_front()
			var spk: String = str(dialogue.get(id, {}).get("speaker", ""))
			talk_t = say_async(id, Game.player if spk == "ruth" else npc) + 0.4
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > limit:
			fail("softlock: never arrived '%s'" % text)
	for id in talk:
		Game.log_event("say", {"id": id, "skipped": true})
	marker.queue_free()
	npc_release(npc)

## Can this watcher see Ruth right now? Short sight at night, shorter when she's crouched, a 110 degree cone, line
## of sight, and he hears her running close by.
func sees_player(w: Node3D) -> bool:
	if w == null or not is_instance_valid(w) or w.get("alive") == false or Game.player == null:
		return false
	var eye := w.global_position + Vector3(0, 1.6, 0)
	var tp: Vector3 = Game.player.global_position + Vector3(0, 1.1, 0)
	var to := tp - eye
	var dist := to.length()
	var crouched: bool = Game.player.intent.get("crouch", false)
	var reach := 8.0 if crouched else 18.0
	if Game.sky and Game.sky.is_night():
		reach *= 0.6
	var pv: Vector3 = Game.player.velocity
	var running: bool = Game.player.intent.get("sprint", false) and Vector2(pv.x, pv.z).length() > 2.0
	if running and dist < 10.0:
		return true
	if dist > reach:
		return false
	var f: float = float(w.get("facing")) if w.get("facing") != null else 0.0
	var fwd := Vector3(-sin(f), 0, -cos(f))
	var flat := Vector3(to.x, 0, to.z).normalized()
	if fwd.dot(flat) < cos(deg_to_rad(55.0)) and dist > 2.5:
		return false
	var q := PhysicsRayQueryParameters3D.create(eye, tp, 1)
	if w is CollisionObject3D:
		q.exclude = [(w as CollisionObject3D).get_rid()]
	return w.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## Reach a point without being seen by any of the watchers. Returns true if she made it unseen, false the moment
## one of them spots her (the mission decides what that costs). Bots: --choices decides (0 unseen, 1 spotted).
func sneak_to(pos: Vector3, radius: float, text: String, watchers: Array) -> bool:
	if _abort:
		return true
	if _replaying():
		var unseen: bool = _decide(true)
		if unseen:
			_teleport_player(pos)
		return unseen
	set_objective(text)
	var marker := _marker(pos)
	var auto_spotted := autopilot and auto_choice(2) == 1
	var t := 0.0
	var seen := false
	while not _abort:
		if autopilot and t > 0.3:
			if auto_spotted:
				seen = true
				break
			_teleport_player(pos)
		var p: Vector3 = Game.player.global_position
		if Vector2(p.x - pos.x, p.z - pos.z).length() < radius:
			break
		for w in watchers:
			if sees_player(w):
				seen = true
				break
		if seen:
			break
		if Game.player.damageable and not Game.player.damageable.alive:
			fail("Ruth died")
			break
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > step_timeout * 2.0:
			fail("softlock: never reached '%s'" % text)
	marker.queue_free()
	Game.log_event("sneak", {"text": text, "spotted": seen})
	if _abort:
		return true
	if seen and Game.hud:
		Game.hud.notice("Spotted", 2.5)
	_decide(not seen, autopilot)
	return not seen

## Get at least `distance` metres from center before the clock runs out; fails the mission if she doesn't.
func escape(center: Vector3, distance: float, text: String, seconds: float) -> void:
	if _abort or resuming:
		return
	var t := 0.0
	var shown := -1
	while not _abort:
		var left := seconds - t
		if int(ceil(left)) != shown:
			shown = int(ceil(left))
			set_objective("%s — %d" % [text, maxi(shown, 0)])
		var p: Vector3 = Game.player.global_position
		if autopilot and t > 0.3:
			var away := Vector3(p.x - center.x, 0, p.z - center.z)
			if away.length() < 0.5:
				away = Vector3(-1, 0, 0)
			var target := center + away.normalized() * (distance + 15.0)
			for k in 8:
				if not Game.world.is_water(target.x, target.z):
					break
				target = center + away.normalized().rotated(Vector3.UP, 0.8 * (k + 1)) * (distance + 15.0)
			_teleport_player(target)
			p = Game.player.global_position
		if Vector2(p.x - center.x, p.z - center.z).length() >= distance:
			break
		if Game.player.damageable and not Game.player.damageable.alive:
			fail("Ruth died")
			break
		if left <= 0.0:
			fail("They caught up with you")
			break
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	Game.log_event("escape", {"text": text, "seconds": snappedf(t, 0.1), "ok": not _abort})

## Show a printed page (wanted poster, front page, letter) on paper and wait until it's put away.
## style: "poster" (big display type) or "page" (newsprint). Lines starting with "!" are set large.
func paper(title: String, lines: Array, style := "page", button := "Fold it away") -> void:
	if _abort or resuming:
		return
	Game.log_event("paper", {"title": title})
	var menus = Game.get("menus")
	if autopilot or Game.headless or menus == null:
		await wait(0.2)
		return
	var p: PanelContainer = menus._paper_panel(Vector2(760, 0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var head := UITheme.label(title, 72 if style == "poster" else 46, "poster" if style == "poster" else "display",
		UITheme.OXBLOOD if style == "poster" else UITheme.INK, false)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	v.add_child(HSeparator.new())
	for ln in lines:
		var s := str(ln)
		var big := s.begins_with("!")
		var l := UITheme.label(s.trim_prefix("!"), 40 if big else 26, "serif_bold" if big else "body", UITheme.INK, false)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(700, 0)
		v.add_child(l)
	v.add_child(HSeparator.new())
	var closed := [false]
	var btn: Button = menus._button(button, func():
		closed[0] = true
		menus.back())
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(btn)
	p.tree_exiting.connect(func(): closed[0] = true)
	if Game.audio and Game.audio.has_method("ui"):
		Game.audio.ui("page")
	menus._push(p)
	while not closed[0] and not _abort:
		await get_tree().process_frame

## Run a minigame (src/minigames/<name>.gd, a node with `play(opts) -> Dictionary`) and return its result.
func minigame(game_name: String, opts: Dictionary = {}) -> Dictionary:
	var path := "res://src/minigames/%s.gd" % game_name
	if not ResourceLoader.exists(path):
		push_warning("minigame %s missing" % game_name)
		return {}
	if _abort:
		return {}
	if _replaying():
		# played on an earlier attempt: same result, same money changing hands
		var e = _decide(null)
		if typeof(e) == TYPE_DICTIONARY:
			if Game.state and float(e.get("money", 0.0)) != 0.0:
				Game.state.add_money(float(e.money))
			Game.log_event("minigame_replayed", {"name": game_name})
			return e.get("res", {})
		return {}
	var o := opts.duplicate()
	o["auto"] = bool(o.get("auto", false)) or autopilot or Game.headless
	var money0: float = float(Game.state.money) if Game.state else 0.0
	var mg: Node = load(path).new()
	mg.name = "Minigame_" + game_name
	add_child(mg)
	Game.log_event("minigame_start", {"name": game_name})
	var res: Dictionary = await mg.play(o)
	if is_instance_valid(mg):
		mg.queue_free()
	var brief := {"name": game_name}
	for k in res.keys():
		if typeof(res[k]) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			brief[k] = res[k]
	Game.log_event("minigame_end", brief)
	var delta: float = (float(Game.state.money) - money0) if Game.state else 0.0
	_decide({"res": res, "money": delta})
	return res

## Story law: put a price on Ruth's head in a county (a poster somebody arranged, not a crime anyone saw).
func post_bounty(county: String, dollars: float, level := 1, reason := "") -> void:
	var st = Game.state
	if st == null:
		return
	st.bounties[county] = float(st.bounties.get(county, 0.0)) + dollars
	if level > st.wanted:
		st.wanted = level
		st.wanted_county = county
		st.wanted_changed.emit(st.wanted, county)
	st.wanted_t = maxf(st.wanted_t, [0.0, 60.0, 120.0, 240.0][clampi(level, 0, 3)])
	Game.log_event("bounty_posted", {"county": county, "amount": dollars, "reason": reason})
	if Game.hud:
		Game.hud.notice("A price on your head — $%d in %s" % [int(dollars), county], 5.0)

func clear_bounty(county: String, dollars: float) -> void:
	var st = Game.state
	if st == null:
		return
	st.bounties[county] = maxf(float(st.bounties.get(county, 0.0)) - dollars, 0.0)
	if st.wanted_county == county and float(st.bounties[county]) <= 0.0:
		st.wanted = 0
		st.wanted_t = 0.0
		st.wanted_changed.emit(0, county)
	Game.log_event("bounty_withdrawn", {"county": county, "amount": dollars})

# ------------------------------------------------------------------ chapter 3 verbs (horseback, herds, defence)
## Keep a mission prop (herd, outrider, marker) until the mission ends or is retried.
func track(n: Node) -> Node:
	_props.append(n)
	return n

func _free_props() -> void:
	for n in _props:
		if is_instance_valid(n):
			n.queue_free()
	_props.clear()

## Ruth on her horse: waits until she's mounted (the horse is called over if it's far). Bots and resume mount her.
func mount_up(text := "Mount your horse") -> void:
	if _abort or Game.player == null or Game.player.get("on_horse") != null:
		return
	var horse = Horse.player_horse if is_instance_valid(Horse.player_horse) else null
	if horse == null:
		return
	if autopilot or resuming:
		if horse.rider != null:
			return
		_put_on_ground(horse, Game.player.global_position + Vector3(1.4, 0, 0))
		horse.mount(Game.player, 0.0)
		return
	set_objective(text + "  (F / Y)")
	if horse.global_position.distance_to(Game.player.global_position) > 25.0:
		horse.call_to(Game.player)
		Game.say("Ruth whistles for her horse.", 2.5)
	var t := 0.0
	while not _abort and Game.player.get("on_horse") == null:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > step_timeout * 2.0:
			fail("softlock: never mounted")
	set_objective("")

func dismount_player() -> void:
	var on = Game.player.get("on_horse") if Game.player else null
	if on != null and on.has_method("dismount"):
		on.dismount()

## Lead someone who follows Ruth (a drunk doctor, a prisoner on a rope) to dest. They keep a few metres behind and
## stop when she gets more than 25 m ahead ("go back for him"); fails if they die.
func lead(npc: Node3D, text: String, dest: Vector3, radius := 6.0, lines: Array = []) -> void:
	if _abort:
		return
	if npc == null or not is_instance_valid(npc):
		fail("nobody to lead for '%s'" % text)
		return
	var who := str(npc.get("display_name"))
	if resuming:
		_teleport_player(dest)
		_put_on_ground(npc, dest + Vector3(2, 0, 1))
		npc_release(npc)
		return
	var marker := _marker(dest)
	npc_walk_to(npc, npc.global_position)
	var t := 0.0
	var talk := lines.duplicate()
	var talk_t := 2.0
	var limit := maxf(step_timeout, npc.global_position.distance_to(dest) / Human.WALK * 3.0 + 90.0)
	while not _abort:
		if not is_instance_valid(npc) or npc.get("alive") == false:
			fail("%s was killed" % who)
			break
		if autopilot and t > 0.3:
			_teleport_player(dest)
			_put_on_ground(npc, dest + Vector3(2, 0, 1))
		var np := npc.global_position
		if Vector2(np.x - dest.x, np.z - dest.z).length() < radius:
			break
		var pp: Vector3 = Game.player.global_position
		var gap := np.distance_to(pp)
		var h := npc as Human
		if gap > 25.0:
			set_objective("%s has stopped. Go back for him." % who)
			if h:
				h.intent.move_to = null
				h.intent.face = pp - np
		else:
			set_objective(text)
			if h:
				h.intent.move_to = pp if gap > 3.0 else null
				h.intent.speed = Human.JOG if gap > 9.0 else Human.WALK
		talk_t -= get_physics_process_delta_time()
		if not talk.is_empty() and (talk_t <= 0.0 or autopilot) and gap < 12.0:
			var id: String = talk.pop_front()
			var spk: String = str(dialogue.get(id, {}).get("speaker", ""))
			talk_t = say_async(id, Game.player if spk == "ruth" else npc) + 3.0
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > limit:
			fail("softlock: never arrived '%s'" % text)
	marker.queue_free()
	npc_release(npc)

## Escort a mission rider (Outrider) on horseback to dest. The rider waits when Ruth falls more than 40 m behind;
## fails if she gets 220 m away or the rider is killed.
func ride_with(rider, text: String, dest: Vector3, radius := 10.0) -> void:
	if _abort or rider == null:
		return
	if resuming or autopilot:
		rider.teleport(dest)
		_teleport_player(dest + Vector3(4, 0, 3))
		await get_tree().physics_frame
		return
	set_objective(text)
	var marker := _marker(dest)
	rider.ride_to(dest)
	var t := 0.0
	var limit := maxf(step_timeout, rider.horse.global_position.distance_to(dest) / 3.0 + 120.0)
	while not _abort:
		var hp: Vector3 = rider.horse.global_position
		if rider.man == null or not is_instance_valid(rider.man) or not rider.man.alive:
			fail("%s was killed" % (rider.man.display_name if rider.man else "Your companion"))
			break
		if Vector2(hp.x - dest.x, hp.z - dest.z).length() < radius:
			break
		var gap: float = hp.distance_to(Game.player.global_position)
		if gap > 220.0:
			fail("You lost %s" % rider.man.display_name)
			break
		if gap > 40.0 and not rider.halted:
			rider.halt()
		elif gap < 25.0 and rider.halted:
			rider.ride_to(dest)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > limit:
			fail("softlock: never arrived '%s'" % text)
	marker.queue_free()
	rider.halt()

## Drive a herd (ch3/herd.gd) to dest: Ruth (and any outriders) push from behind. `strays` steers break off along
## the way (with `stray_line` said each time). Fails if the herd drops below min_head or Ruth abandons it.
## Returns the head of cattle still with the herd.
func drive(herd, dest: Vector3, radius: float, text: String, strays := 0, min_head := 6, stray_line := "") -> int:
	if _abort or herd == null:
		return 0
	herd.goal = dest
	if not herd.pushers.has(Game.player):
		herd.pushers.append(Game.player)
	if resuming or autopilot:
		herd.teleport_to(dest)
		if autopilot and not resuming:
			for i in strays:
				herd.make_stray()
			await get_tree().physics_frame
			herd.teleport_to(dest)
		return herd.head()
	var marker := _marker(dest)
	var start: Vector3 = herd.center()
	var total := Vector2(dest.x - start.x, dest.z - start.z).length()
	var made := 0
	var t := 0.0
	var limit := maxf(step_timeout, total / 0.9 + 240.0)
	var shown := ""
	while not _abort:
		var cen: Vector3 = herd.center()
		var left := Vector2(dest.x - cen.x, dest.z - cen.z).length()
		if left < radius:
			break
		# strays break off at even points along the way
		if made < strays and 1.0 - left / maxf(total, 1.0) > float(made + 1) / float(strays + 1):
			made += 1
			herd.make_stray()
			if stray_line != "":
				say_async(stray_line, null)
		var sts: Array = herd.strays()
		var txt := "%s — %d head" % [text, herd.head()]
		if not sts.is_empty():
			txt = "A steer has broken off — ride round it and turn it back  (%d head)" % herd.head()
		if txt != shown:
			shown = txt
			set_objective(txt)
		if herd.head() < min_head:
			fail("Too many cattle lost")
			break
		if Game.player.global_position.distance_to(cen) > 250.0:
			fail("You left the herd")
			break
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > limit:
			fail("softlock: the herd never reached '%s'" % text)
	marker.queue_free()
	return herd.head()

## A stampede: the herd runs; Ruth must ride up on the leaders' flank and turn them within `seconds`. Returns true
## if she turned them (the herd mills and stops); false if it ran on (some head scatter into the rocks).
## Bots: --choices decides (0 turned, 1 not).
func stampede(herd, dir: Vector3, text: String, seconds := 40.0, scatter := 5) -> bool:
	if _abort or herd == null:
		return true
	if _replaying():
		var was: bool = _decide(true)
		if not was:
			herd.scatter(scatter)
		herd.calm()
		return was
	herd.stampede(dir)
	if not herd.pushers.has(Game.player):
		herd.pushers.append(Game.player)
	var turned := false
	if autopilot:
		turned = auto_choice(2) == 0
		await get_tree().physics_frame
	else:
		var t := 0.0
		var shown := -1
		while not _abort and t < seconds:
			if int(ceil(seconds - t)) != shown:
				shown = int(ceil(seconds - t))
				set_objective("%s — %d" % [text, shown])
			if herd.mill_t > 5.0:
				turned = true
				break
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
	if _abort:
		return true
	if not turned:
		herd.scatter(scatter)
	herd.calm()
	_decide(turned, autopilot)
	Game.log_event("stampede", {"turned": turned, "head": herd.head()})
	return turned

## Hold a point against a group: fight them all; returns false if any one of them spent `hold` seconds within
## `radius` of the point (the thing being defended is lost, the mission decides what that costs). Bots: --choices
## decides (0 held, 1 lost).
func defend(pos: Vector3, radius: float, group: Array, text: String, hold := 7.0) -> bool:
	if _abort:
		return true
	if _replaying():
		var was: bool = _decide(true)
		await wait_dead(group, text)
		return was
	if autopilot:
		var held := auto_choice(2) == 0
		await wait_dead(group, text)
		if _abort:
			return true
		_decide(held, true)
		Game.log_event("defend", {"held": held})
		return held
	set_objective(text)
	var marker := _marker(pos)
	var near_t := 0.0
	var held2 := true
	var t := 0.0
	while not _abort:
		var left := group.filter(func(h): return is_instance_valid(h) and h.alive and h.brain.state != h.brain.State.SURRENDER)
		if left.is_empty():
			break
		var inside := left.any(func(h): return Vector2(h.global_position.x - pos.x, h.global_position.z - pos.z).length() < radius)
		near_t = near_t + get_physics_process_delta_time() if inside else maxf(near_t - get_physics_process_delta_time(), 0.0)
		if near_t > hold and held2:
			held2 = false
			if Game.hud:
				Game.hud.notice("They reached it", 3.0)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > step_timeout * 2.0:
			fail("softlock: fight '%s' never resolved" % text)
	marker.queue_free()
	if _abort:
		return true
	_decide(held2)
	Game.log_event("defend", {"held": held2})
	return held2
