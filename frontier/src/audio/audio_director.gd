class_name AudioDirector
extends Node
## Frontier's audio director (Game.audio). Owns the bus layout, the sound manifest (assets/ext/audio/manifest.json,
## built by tools/audio/build_all.py), pooled one-shot players with distance attenuation, occlusion low-pass and
## per-play pitch/volume variation, the gunshot model (speed-of-sound delay, close/far/distant/indoor variants,
## slapback echoes off terrain and buildings), Nerve slow-time audio, UI sounds, voiced lines with viseme events,
## volume settings, and three helpers: AudioLocomotion (footsteps/hooves/tack), AmbienceMixer (biome/time/weather/
## water/town beds and creature one-shots) and MusicDirector (adaptive stem score).
## Missing audio never crashes: unknown ids and missing files are skipped silently (logged once per id).
##
## Bus layout (built in code, see _setup_buses):
##   Master <- Music (duck/low-pass for Nerve)    Master <- UI    Master <- Voice
##   Master <- World (Nerve: low-pass + pitch shift; occlusion/underwater) <- SFX (room reverb, wet by interior)
##                                                                     <- Ambience
##                                                                     <- Reverb (100 % wet send for guns/voices)

signal voice_started(line_id: String, actor: Node, duration: float, text: String)
signal voice_finished(line_id: String, actor: Node)
signal viseme(actor: Node, shape: String, weight: float)
signal nerve_changed(on: bool)

const AUDIO_DIR := "res://assets/ext/audio/"
const SPEED_OF_SOUND := 343.0
const POOL_3D := 32
const POOL_2D := 10
const BUSES := ["Music", "UI", "Voice", "World", "SFX", "Ambience", "AmbInside", "Reverb"]
const SETTINGS_PATH := "user://audio_settings.cfg"
const OCCLUSION_MASK := 1           # world geometry (terrain, buildings)

var manifest: Dictionary = {}
var sounds: Dictionary = {}          # id -> manifest entry
var voice_lines: Dictionary = {}     # line id -> {file, duration, speaker, text, visemes}
var music_tracks: Dictionary = {}
var ok := false                      # manifest loaded
var nerve_on := false
var listener_interior := false
var interior_volumes: Array = []     # [{aabb: AABB, surface: String, reverb: float}]
var surface_volumes: Array = []      # [{aabb: AABB, surface: String}]
var settings := {"Master": 1.0, "Music": 0.8, "SFX": 1.0, "Ambience": 0.9, "Voice": 1.0, "UI": 0.8}

var locomotion: AudioLocomotion
var ambience: AmbienceMixer
var music: MusicDirector

var _cache: Dictionary = {}          # path -> AudioStream (or null when missing)
var _warned: Dictionary = {}
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _started: Dictionary = {}        # player -> start time (msec), for voice stealing
var _last_var: Dictionary = {}       # id -> last variation index (avoid repeats)
var _queue: Array = []               # scheduled plays [{t, id, pos, opts}] (game time)
var _game_time := 0.0
var _rng := RandomNumberGenerator.new()
var _heartbeat: AudioStreamPlayer
var _voices: Array = []              # active voice lines [{player, line_id, actor, t, visemes, idx, dur}]
var _bus_fx: Dictionary = {}         # name -> effect object
var _tweens: Dictionary = {}
var recent_shots: Array = []         # [{t, pos, player}] for the music director (combat detection)
var stats := {"played": 0, "missing": 0, "voices": 0, "gunshots": 0, "echoes": 0}

func _ready() -> void:
	Game.audio = self
	name = "AudioDirector"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = int(Game.args.get("seed", 1899)) + 7
	_setup_buses()
	_load_settings()
	_load_manifest()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.name = "OneShot3D_%d" % i
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 1.0
		p.bus = "SFX"
		add_child(p)
		_pool3d.append(p)
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		p2.name = "OneShot2D_%d" % i
		p2.bus = "UI"
		add_child(p2)
		_pool2d.append(p2)
	_heartbeat = AudioStreamPlayer.new()
	_heartbeat.name = "Heartbeat"
	_heartbeat.bus = "UI"
	add_child(_heartbeat)
	locomotion = AudioLocomotion.new()
	locomotion.name = "Locomotion"
	add_child(locomotion)
	ambience = AmbienceMixer.new()
	ambience.name = "Ambience"
	add_child(ambience)
	music = MusicDirector.new()
	music.name = "Music"
	add_child(music)
	print("audio: director ready (%d sounds, %d music tracks, %d voice lines%s)" % [sounds.size(), music_tracks.size(),
		voice_lines.size(), "" if ok else ", NO MANIFEST: running silent"])

func _exit_tree() -> void:
	# release everything the AudioServer would otherwise keep alive past the scene (no leaks at exit)
	for t in _tweens.values():
		if is_instance_valid(t):
			(t as Tween).kill()
	_tweens.clear()
	stop_all()
	for b in BUSES + ["Master"]:
		var bi := AudioServer.get_bus_index(b)
		if bi == -1:
			continue
		for i in range(AudioServer.get_bus_effect_count(bi) - 1, -1, -1):
			AudioServer.remove_bus_effect(bi, i)
	_bus_fx.clear()
	_cache.clear()
	_queue.clear()
	if Game.audio == self:
		Game.audio = null

## Stops every player under the director (scene change / quit; playing streams would otherwise leak).
func stop_all() -> void:
	for n in find_children("*", "AudioStreamPlayer", true, false) + find_children("*", "AudioStreamPlayer3D", true, false):
		n.stop()
		n.stream = null

# ------------------------------------------------------------------------------------------------ buses
func _setup_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
	_send("Music", "Master")
	_send("UI", "Master")
	_send("Voice", "Master")
	_send("World", "Master")
	_send("SFX", "World")
	_send("Ambience", "World")
	_send("AmbInside", "World")
	_send("Reverb", "World")
	# World: Nerve/underwater low-pass + pitch shift (both bypassed normally), soft limiter at the end
	var lpf := AudioEffectLowPassFilter.new()
	lpf.cutoff_hz = 20000.0
	lpf.resonance = 0.5
	_add_fx("World", "world_lp", lpf, false)
	var ps := AudioEffectPitchShift.new()
	ps.pitch_scale = 1.0
	ps.oversampling = 4
	_add_fx("World", "world_pitch", ps, false)
	# SFX: room reverb, wet follows interior/exterior
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.35
	rv.damping = 0.6
	rv.spread = 0.8
	rv.hipass = 0.15
	rv.dry = 1.0
	rv.wet = 0.0
	rv.predelay_msec = 12.0
	_add_fx("SFX", "sfx_room", rv, true)
	# Reverb send bus: fully wet, large (canyon/street) or room depending on the listener
	var rs := AudioEffectReverb.new()
	rs.room_size = 0.8
	rs.damping = 0.55
	rs.spread = 1.0
	rs.hipass = 0.2
	rs.dry = 0.0
	rs.wet = 1.0
	rs.predelay_msec = 60.0
	rs.predelay_feedback = 0.35
	_add_fx("Reverb", "send_reverb", rs, true)
	# Music: low-pass for Nerve/indoors
	var mlp := AudioEffectLowPassFilter.new()
	mlp.cutoff_hz = 20000.0
	_add_fx("Music", "music_lp", mlp, false)
	# Master: limiter so stacked gunfights never clip
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	lim.release = 0.12
	_add_fx("Master", "master_limit", lim, true)

func _send(bus: String, to: String) -> void:
	AudioServer.set_bus_send(AudioServer.get_bus_index(bus), to)

func _add_fx(bus: String, key: String, fx: AudioEffect, enabled: bool) -> void:
	var bi := AudioServer.get_bus_index(bus)
	for i in AudioServer.get_bus_effect_count(bi):     # rebuild-safe (scene reloads)
		if AudioServer.get_bus_effect(bi, i).get_class() == fx.get_class():
			_bus_fx[key] = AudioServer.get_bus_effect(bi, i)
			AudioServer.set_bus_effect_enabled(bi, i, enabled)
			return
	AudioServer.add_bus_effect(bi, fx)
	AudioServer.set_bus_effect_enabled(bi, AudioServer.get_bus_effect_count(bi) - 1, enabled)
	_bus_fx[key] = fx

func _fx_enable(bus: String, key: String, on: bool) -> void:
	var bi := AudioServer.get_bus_index(bus)
	for i in AudioServer.get_bus_effect_count(bi):
		if AudioServer.get_bus_effect(bi, i) == _bus_fx.get(key):
			AudioServer.set_bus_effect_enabled(bi, i, on)

# ------------------------------------------------------------------------------------------------ manifest + streams
func _load_manifest() -> void:
	var path := AUDIO_DIR + "manifest.json"
	var txt := ""
	if FileAccess.file_exists(path):
		txt = FileAccess.get_file_as_string(path)
	if txt.is_empty():
		print("audio: no manifest at %s (run tools/fetch_assets.sh audio or tools/audio/build_all.py)" % path)
		return
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		print("audio: manifest unreadable")
		return
	manifest = data
	sounds = manifest.get("sounds", {})
	voice_lines = manifest.get("voice", {})
	music_tracks = manifest.get("music", {})
	ok = true

func has_sound(id: String) -> bool:
	return sounds.has(id)

func stream_for(rel: String) -> AudioStream:
	if _cache.has(rel):
		return _cache[rel]
	var path := AUDIO_DIR + rel
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	if s == null and FileAccess.file_exists(path):
		# not imported (fresh fetch without an editor import): load the raw file
		var abs_path := ProjectSettings.globalize_path(path)
		if rel.ends_with(".ogg"):
			s = AudioStreamOggVorbis.load_from_file(abs_path)
		elif rel.ends_with(".wav"):
			s = AudioStreamWAV.load_from_file(abs_path)
	if s == null:
		_warn_once(rel, "audio: missing file " + rel)
		stats.missing += 1
	_cache[rel] = s
	return s

func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	if _warned.size() <= 40:
		print(msg)

func _pick_file(id: String) -> String:
	var e: Dictionary = sounds.get(id, {})
	var files: Array = e.get("files", [])
	if files.is_empty():
		return ""
	var i := _rng.randi_range(0, files.size() - 1)
	if files.size() > 1 and i == int(_last_var.get(id, -1)):
		i = (i + 1 + _rng.randi_range(0, files.size() - 2)) % files.size()
	_last_var[id] = i
	return files[i]

## Stream for a sound id with looping set from the manifest (one variation, chosen at random).
func loop_stream(id: String) -> AudioStream:
	var f := _pick_file(id)
	if f.is_empty():
		_warn_once(id, "audio: unknown sound id " + id)
		return null
	var s := stream_for(f)
	if s == null:
		return null
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	return s

# ------------------------------------------------------------------------------------------------ playback
func listener_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		return cam.global_position
	if Game.player != null:
		return Game.player.global_position
	return Vector3.ZERO

## Play a sound id at a world position (3D) or, with pos == null, non-positionally on its bus.
## opts: volume_db, pitch, bus, max_dist, unit_size, delay (s, game time), occlude (bool, default true for 3D),
##       no_var (bool), attach (Node3D to follow)
## Returns the player (or null if nothing played / delayed).
func play(id: String, pos = null, opts: Dictionary = {}) -> Node:
	if not ok:
		return null
	if not sounds.has(id):
		_warn_once(id, "audio: unknown sound id " + id)
		return null
	if float(opts.get("delay", 0.0)) > 0.001:
		var o := opts.duplicate()
		o.erase("delay")
		_queue.append({"t": _game_time + float(opts.delay), "id": id, "pos": pos, "opts": o})
		return null
	var e: Dictionary = sounds[id]
	var f := _pick_file(id)
	var s := stream_for(f)
	if s == null:
		return null
	var vol := float(e.get("gain_db", 0.0)) + float(opts.get("volume_db", 0.0))
	var pitch := float(opts.get("pitch", 1.0))
	if not opts.get("no_var", false):
		var pv := float(e.get("pitch_var", 0.0))
		vol += _rng.randf_range(-1.0, 1.0) * float(e.get("vol_var_db", 0.0)) * 0.5
		pitch *= 1.0 + _rng.randf_range(-pv, pv)
	var bus: String = opts.get("bus", "")
	if bus.is_empty():
		bus = _bus_for(e)
	stats.played += 1
	if pos == null:
		var p2 := _free_2d()
		p2.stream = s
		p2.volume_db = vol
		p2.pitch_scale = pitch
		p2.bus = bus
		p2.play()
		_started[p2] = Time.get_ticks_msec()
		return p2
	var p := _free_3d()
	p.stream = s
	p.volume_db = vol
	p.pitch_scale = pitch
	p.bus = bus
	p.unit_size = float(opts.get("unit_size", e.get("unit_size", 4.0)))
	p.max_distance = float(opts.get("max_dist", e.get("max_dist", 60.0)))
	p.max_db = 3.0
	p.attenuation_filter_cutoff_hz = 20500.0
	p.attenuation_filter_db = -12.0
	if opts.get("occlude", true):
		_apply_occlusion(p, pos as Vector3)
	p.global_position = pos as Vector3
	p.play()
	_started[p] = Time.get_ticks_msec()
	return p

func _bus_for(e: Dictionary) -> String:
	var b: String = e.get("bus", "SFX")
	return b if AudioServer.get_bus_index(b) != -1 else "SFX"

func _free_3d() -> AudioStreamPlayer3D:
	var oldest: AudioStreamPlayer3D = _pool3d[0]
	var ot := INF
	for p in _pool3d:
		if not p.playing:
			return p
		var t: float = _started.get(p, 0)
		if t < ot:
			ot = t
			oldest = p
	oldest.stop()
	return oldest

func _free_2d() -> AudioStreamPlayer:
	var oldest: AudioStreamPlayer = _pool2d[0]
	var ot := INF
	for p in _pool2d:
		if not p.playing:
			return p
		var t: float = _started.get(p, 0)
		if t < ot:
			ot = t
			oldest = p
	oldest.stop()
	return oldest

## Occlusion: a ray from the listener to the source; blocked by world geometry -> muffle (low-pass + quieter).
## Also muffles everything outside when the listener is inside (and vice versa).
func _apply_occlusion(p: AudioStreamPlayer3D, pos: Vector3) -> void:
	var lp := listener_pos()
	var blocked := false
	if lp.distance_to(pos) > 1.5 and lp.distance_to(pos) < 400.0:
		var w := get_viewport().world_3d if is_inside_tree() else null
		if w != null:
			var q := PhysicsRayQueryParameters3D.create(lp, pos + Vector3.UP * 0.3, OCCLUSION_MASK)
			q.collide_with_areas = false
			var hit := w.direct_space_state.intersect_ray(q)
			blocked = not hit.is_empty() and (hit.position as Vector3).distance_to(pos) > 1.0
	if is_interior(pos) != listener_interior:
		blocked = true
	if blocked:
		p.attenuation_filter_cutoff_hz = 900.0
		p.attenuation_filter_db = -30.0
		p.volume_db -= 5.0

# ------------------------------------------------------------------------------------------------ interiors and surfaces
## Building generators register interior volumes (AABB, world space): reverb, occlusion and floor surface.
func register_interior(aabb: AABB, floor_surface := "wood", reverb := 0.25) -> void:
	interior_volumes.append({"aabb": aabb, "surface": floor_surface, "reverb": reverb})

## Floors/boardwalks/bridges that are not interiors (e.g. a boardwalk in front of the saloon).
func register_surface(aabb: AABB, surface: String) -> void:
	surface_volumes.append({"aabb": aabb, "surface": surface})

func is_interior(pos: Vector3) -> bool:
	for v in interior_volumes:
		if (v.aabb as AABB).has_point(pos):
			return true
	return false

func surface_at(pos: Vector3) -> String:
	return AudioSurfaces.surface_at(pos, self)

## Footstep for any actor (surface "" = detect from the world). gait: walk / run / land / scuff.
func footstep(pos: Vector3, surface := "", gait := "walk", volume_db := 0.0) -> void:
	if locomotion != null:
		locomotion.footstep(pos, surface, gait, volume_db)

## Single hoof contact (force soft/hard); horses registered with track_horse() are handled automatically.
func hoof(pos: Vector3, surface := "", force := "soft", volume_db := 0.0) -> void:
	if locomotion != null:
		locomotion.hoof(pos, surface, force, volume_db)

func track_horse(node: Node3D) -> void:
	if locomotion != null:
		locomotion.track_horse(node)

# ------------------------------------------------------------------------------------------------ guns
## Called by GunHandler.fire for every shot. sound_id: revolver_heavy, revolver_light, rifle_lever, rifle_bolt,
## rifle_small, rifle_heavy, shotgun.
func gunshot(sound_id: String, origin: Vector3, is_player := false) -> void:
	stats.gunshots += 1
	recent_shots.append({"t": _game_time, "pos": origin, "player": is_player})
	if recent_shots.size() > 40:
		recent_shots.pop_front()
	if music != null:
		music.on_gunshot(origin, is_player)
	if not ok:
		return
	var lp := listener_pos()
	var d := lp.distance_to(origin)
	var inside := is_interior(origin)
	var base := "gun_" + sound_id
	if not sounds.has(base):
		base = "gun_revolver_heavy"
	var travel := 0.0 if is_player else d / SPEED_OF_SOUND
	if inside:
		if is_player or d < 3.0:
			play(base + "_indoor", null, {"bus": "SFX", "no_var": false})
		else:
			play(base + "_indoor", origin, {"delay": travel})
		# heard from outside: muffled close shot is handled by occlusion in play()
		_send_reverb(base + "_indoor", origin, -10.0, travel)
		return
	if is_player:
		play(base, null, {"bus": "SFX"})
		_send_reverb(base, origin, -14.0, 0.0)
	elif d < 140.0:
		play(base, origin, {"delay": travel})
		if d > 60.0:
			play(base + "_far", origin, {"delay": travel, "volume_db": lerpf(-12.0, -3.0, (d - 60.0) / 80.0)})
	elif d < 900.0:
		play(base + "_far", origin, {"delay": travel})
	else:
		play(base + "_distant", origin, {"delay": travel})
	_echoes(sound_id, origin, lp, d)

func _send_reverb(id: String, pos: Vector3, vol: float, delay: float) -> void:
	if sounds.has(id):
		play(id, pos, {"bus": "Reverb", "volume_db": vol, "delay": delay, "occlude": false})

func _echo_size(sound_id: String) -> String:
	if sound_id.begins_with("revolver"):
		return "pistol"
	if sound_id == "shotgun":
		return "shotgun"
	if sound_id == "rifle_small":
		return "small"
	return "rifle"

## Slapback/echo model: terrain faces (from the heightfield) and building faces in settlements. For each reflector,
## path = shooter->reflector->listener; the echo plays from the reflector position after (path / c) s, its level
## falling with path length and growing with the face's height/steepness.
func _echoes(sound_id: String, origin: Vector3, lp: Vector3, direct: float) -> void:
	var echo_id := "gun_echo_" + _echo_size(sound_id)
	if not sounds.has(echo_id):
		return
	var refl := find_reflectors(origin)
	var n := 0
	for r in refl:
		var rp: Vector3 = r.pos
		var path := origin.distance_to(rp) + rp.distance_to(lp)
		if path - direct < 15.0:
			continue
		var delay := path / SPEED_OF_SOUND
		var gain_db := -6.0 - 20.0 * log(maxf(path, 20.0) / 40.0) / log(10.0) + float(r.strength) * 6.0
		if gain_db < -40.0:
			continue
		play(echo_id, rp, {"delay": delay, "volume_db": gain_db, "occlude": false, "unit_size": 400.0,
			"max_dist": 4000.0})
		stats.echoes += 1
		n += 1
		if n >= 5:
			break

## Reflecting faces around a point: [{pos, strength 0..1, kind}] sorted strongest first.
func find_reflectors(origin: Vector3) -> Array:
	var out := []
	var w: WorldData = Game.world
	if w != null and w.ok:
		var h0 := origin.y
		for k in 12:
			var a := TAU * k / 12.0
			var dir := Vector3(cos(a), 0, sin(a))
			var prev := w.height(origin.x, origin.z)
			var step := 12.0
			var dist := step
			while dist < 700.0:
				var p := origin + dir * dist
				if not w.in_bounds(p.x, p.z):
					break
				var hh := w.height(p.x, p.z)
				var rise := hh - prev
				var above := hh - h0
				# a face: steep rise (>= ~35 deg over the step) that stands above the shooter
				if rise > step * 0.7 and above > 6.0:
					out.append({"pos": Vector3(p.x, hh - rise * 0.5, p.z), "strength": clampf(above / 60.0, 0.15, 1.0),
						"kind": "terrain"})
					break
				prev = hh
				dist += step
				step = minf(step * 1.15, 40.0)
		# buildings: in a settlement, facades along the street return short slaps
		var town := w.nearest_settlement(origin.x, origin.z)
		if not town.is_empty():
			var td := Vector2(float(town.x) - origin.x, float(town.z) - origin.z).length()
			var tr := float(town.get("r", 120.0))
			if td < tr * 0.8:
				var ang := deg_to_rad(float(town.get("angle", 0.0)))
				var street := Vector3(cos(ang), 0, sin(ang))
				var across := Vector3(-street.z, 0, street.x)
				for s in [-1.0, 1.0]:
					var dd := _rng.randf_range(9.0, 16.0)
					out.append({"pos": origin + across * s * dd + Vector3.UP * 3.0, "strength": 0.45, "kind": "building"})
				out.append({"pos": origin + street * _rng.randf_range(60.0, 120.0) + Vector3.UP * 3.0, "strength": 0.3,
					"kind": "building"})
	out.sort_custom(func(a, b): return a.strength > b.strength)
	return out

## Firearm mechanics (cocking, cycling, reloading): convenience wrappers for the gun handler / animations.
func gun_mech(kind: String, pos = null) -> void:
	var map := {"cock": "revolver_cock", "dry": "revolver_dryfire", "gate": "revolver_gate", "round": "revolver_round_in",
		"eject": "revolver_eject", "lever": "lever_cycle", "bolt": "bolt_cycle", "pump": "pump_cycle",
		"break_open": "break_open", "break_close": "break_close", "shell": "shell_insert", "draw": "gun_draw",
		"holster": "gun_holster", "casing": "casing_drop"}
	play(map.get(kind, kind), pos)

## Bullet impact by material (dirt, wood, metal, flesh, stone, water) at a world position.
func impact(material: String, pos: Vector3) -> void:
	var id := "bullet_" + material
	if not sounds.has(id):
		id = "bullet_dirt"
	play(id, pos)

## A bullet passing near the listener (rifles crack, others whizz); call with the closest point of the trajectory.
func bullet_pass(pos: Vector3, supersonic: bool) -> void:
	if listener_pos().distance_to(pos) < 10.0:
		play("crack_by" if supersonic else "whizz", pos, {"occlude": false})

func ricochet(pos: Vector3) -> void:
	play("ricochet", pos)

# ------------------------------------------------------------------------------------------------ Nerve
func set_nerve(on: bool) -> void:
	if on == nerve_on:
		return
	nerve_on = on
	nerve_changed.emit(on)
	var quest := Game.quality_name == "quest"
	if on:
		play("nerve_in", null, {"bus": "UI", "no_var": true})
		var hb := loop_stream("nerve_heartbeat")
		if hb != null:
			_heartbeat.stream = hb
			_heartbeat.pitch_scale = 1.3          # ~78 bpm
			_heartbeat.volume_db = -2.0
			_heartbeat.play()
		_fx_enable("World", "world_lp", true)
		if not quest:
			_fx_enable("World", "world_pitch", true)
		_fx_enable("Music", "music_lp", true)
		_tween_fx("world_lp", "cutoff_hz", 20000.0, 1100.0, 0.35)
		_tween_fx("music_lp", "cutoff_hz", 20000.0, 700.0, 0.35)
		if not quest:
			_tween_fx("world_pitch", "pitch_scale", 1.0, 0.78, 0.3)
		_tween_bus("Music", -7.0, 0.4)
		if music != null:
			music.on_nerve(true)
	else:
		play("nerve_out", null, {"bus": "UI", "no_var": true})
		_heartbeat.stop()
		_tween_fx("world_lp", "cutoff_hz", 1100.0, 20000.0, 0.3, func(): _fx_enable("World", "world_lp", false))
		_tween_fx("music_lp", "cutoff_hz", 700.0, 20000.0, 0.5, func(): _fx_enable("Music", "music_lp", false))
		if not quest:
			_tween_fx("world_pitch", "pitch_scale", 0.78, 1.0, 0.25, func(): _fx_enable("World", "world_pitch", false))
		_tween_bus("Music", 0.0, 0.8)
		if music != null:
			music.on_nerve(false)

func _tween_fx(key: String, prop: String, from: float, to: float, secs: float, done: Callable = Callable()) -> void:
	var fx = _bus_fx.get(key)
	if fx == null:
		return
	if _tweens.has(key) and is_instance_valid(_tweens[key]):
		(_tweens[key] as Tween).kill()
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	fx.set(prop, from)
	tw.tween_property(fx, prop, to, secs).set_trans(Tween.TRANS_SINE)
	if done.is_valid():
		tw.tween_callback(done)
	_tweens[key] = tw

var _bus_offsets: Dictionary = {}    # bus -> dB offset on top of the user volume (ducking)

func _tween_bus(bus: String, to_db: float, secs: float) -> void:
	var key := "bus_" + bus
	if _tweens.has(key) and is_instance_valid(_tweens[key]):
		(_tweens[key] as Tween).kill()
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_method(_set_bus_offset.bind(bus), float(_bus_offsets.get(bus, 0.0)), to_db, secs)
	_tweens[key] = tw

func _set_bus_offset(v: float, bus: String) -> void:
	_bus_offsets[bus] = v
	_apply_volume(bus)

## Low-health heartbeat (0 = off .. 1 = critical).
func set_low_health(amount: float) -> void:
	if nerve_on:
		return
	if amount <= 0.01:
		if _heartbeat.playing:
			_heartbeat.stop()
		return
	if not _heartbeat.playing:
		var hb := loop_stream("low_health_heartbeat")
		if hb == null:
			return
		_heartbeat.stream = hb
		_heartbeat.play()
	_heartbeat.pitch_scale = lerpf(1.1, 1.8, amount)
	_heartbeat.volume_db = lerpf(-14.0, -2.0, amount)

# ------------------------------------------------------------------------------------------------ UI
const UI_ALIASES := {"tick": "ui_tick", "select": "ui_select", "back": "ui_back", "error": "ui_error", "page": "ui_page",
	"map": "ui_map_open", "pencil": "ui_pencil", "notify": "ui_notify", "reward": "ui_reward", "coins": "coins_jingle"}

func ui(id: String) -> void:
	var sid: String = UI_ALIASES.get(id, id)
	if not sounds.has(sid) and sounds.has("ui_" + id):
		sid = "ui_" + id
	play(sid, null, {"bus": "UI"})

# ------------------------------------------------------------------------------------------------ voice
## Play a voiced line (manifest "voice" table, built from design/dialogue/*.json) on an actor (Node3D, 3D) or
## non-positionally (actor null / the player). Returns the line's duration in seconds (estimated from the text if
## the audio is missing, so subtitles and scripted scenes keep their timing). Emits voice_started, viseme (if the
## line has viseme timing), voice_finished.
func play_voice(line_id: String, actor: Node = null) -> float:
	var v: Dictionary = voice_lines.get(line_id, {})
	var text: String = v.get("text", "")
	var dur := float(v.get("duration", 0.0))
	if dur <= 0.0:
		dur = maxf(0.8, text.split(" ").size() / 2.6 + 0.3)
	var s: AudioStream = null
	if v.has("file"):
		s = stream_for(v.file)
	if v.is_empty():
		_warn_once("voice:" + line_id, "audio: unknown voice line " + line_id)
	var player: Node = null
	if s != null:
		stats.voices += 1
		if actor is Node3D and actor != Game.player:
			var p := _free_3d()
			p.stream = s
			p.bus = "Voice"
			p.volume_db = float(v.get("gain_db", 0.0))
			p.pitch_scale = 1.0
			p.unit_size = 3.0
			p.max_distance = 60.0
			p.attenuation_filter_cutoff_hz = 20500.0
			p.global_position = (actor as Node3D).global_position + Vector3.UP * 1.6
			p.play()
			_started[p] = Time.get_ticks_msec() + 100000   # voices are stolen last
			player = p
		else:
			var p2 := _free_2d()
			p2.stream = s
			p2.bus = "Voice"
			p2.volume_db = float(v.get("gain_db", 0.0))
			p2.pitch_scale = 1.0
			p2.play()
			_started[p2] = Time.get_ticks_msec() + 100000
			player = p2
	_voices.append({"player": player, "line_id": line_id, "actor": actor, "t": 0.0, "dur": dur,
		"visemes": v.get("visemes", []), "idx": 0})
	voice_started.emit(line_id, actor, dur, text)
	return dur

## Ambient bark by kind (greeting, insult, alarm, hands_up, shop, ...) for an actor with a voice type
## (actor.get_meta("voice_type") or "man_rough"). Returns duration (0 if no line).
func bark(kind: String, actor: Node = null, voice_type := "") -> float:
	var vt := voice_type
	if vt.is_empty() and actor != null and actor.has_meta("voice_type"):
		vt = str(actor.get_meta("voice_type"))
	var pool := []
	var any := []
	for id in voice_lines:
		var v: Dictionary = voice_lines[id]
		if v.get("kind", "") == kind:
			any.append(id)
			if vt.is_empty() or v.get("speaker", "") == vt:
				pool.append(id)
	if pool.is_empty():
		pool = any
	if pool.is_empty():
		return 0.0
	return play_voice(pool[_rng.randi_range(0, pool.size() - 1)], actor)

func _update_voices(dt: float) -> void:
	var i := 0
	while i < _voices.size():
		var v: Dictionary = _voices[i]
		v.t += dt
		var vis: Array = v.visemes
		while v.idx < vis.size() and float(vis[v.idx][0]) <= v.t:
			var e: Array = vis[v.idx]
			viseme.emit(v.actor, str(e[1]), float(e[2]) if e.size() > 2 else 1.0)
			v.idx += 1
		var p = v.player
		if p is AudioStreamPlayer3D and v.actor is Node3D and is_instance_valid(v.actor):
			(p as AudioStreamPlayer3D).global_position = (v.actor as Node3D).global_position + Vector3.UP * 1.6
		if v.t >= v.dur:
			viseme.emit(v.actor, "rest", 0.0)
			voice_finished.emit(v.line_id, v.actor)
			_voices.remove_at(i)
		else:
			i += 1

func voice_duration(line_id: String) -> float:
	return float(voice_lines.get(line_id, {}).get("duration", 0.0))

# ------------------------------------------------------------------------------------------------ settings
func set_volume(bus: String, linear: float) -> void:
	settings[bus] = clampf(linear, 0.0, 1.0)
	_apply_volume(bus)
	_save_settings()

func get_volume(bus: String) -> float:
	return float(settings.get(bus, 1.0))

func _apply_volume(bus: String) -> void:
	var bi := AudioServer.get_bus_index(bus)
	if bi == -1:
		return
	var lin := float(settings.get(bus, 1.0))
	if bus == "SFX":       # the SFX slider drives everything in the world
		var wi := AudioServer.get_bus_index("World")
		AudioServer.set_bus_volume_db(wi, linear_to_db(maxf(lin, 0.0001)) + float(_bus_offsets.get("World", 0.0)))
		return
	AudioServer.set_bus_volume_db(bi, linear_to_db(maxf(lin, 0.0001)) + float(_bus_offsets.get(bus, 0.0)))

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in settings:
			settings[k] = float(cf.get_value("volume", k, settings[k]))
	if Game.args.has("mute"):
		settings["Master"] = 0.0
	for k in settings:
		_apply_volume(k)

func _save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("volume", k, settings[k])
	cf.save(SETTINGS_PATH)

# ------------------------------------------------------------------------------------------------ frame
func _process(dt: float) -> void:
	_game_time += dt
	if not _queue.is_empty():
		var i := 0
		while i < _queue.size():
			var q: Dictionary = _queue[i]
			if q.t <= _game_time:
				_queue.remove_at(i)
				play(q.id, q.pos, q.opts)
			else:
				i += 1
	_update_voices(dt)
	# interior state of the listener drives the room reverb on SFX
	var inside := is_interior(listener_pos())
	if inside != listener_interior:
		listener_interior = inside
		var rv = _bus_fx.get("sfx_room")
		if rv != null:
			rv.wet = 0.22 if inside else 0.0
			rv.room_size = 0.35 if inside else 0.6
		var rs = _bus_fx.get("send_reverb")
		if rs != null:
			rs.room_size = 0.45 if inside else 0.8
			rs.predelay_msec = 15.0 if inside else 60.0

func game_time() -> float:
	return _game_time

## Debug/test summary (bots and the audio test print it).
func describe() -> Dictionary:
	return {"ok": ok, "sounds": sounds.size(), "music": music_tracks.size(), "voice": voice_lines.size(),
		"stats": stats, "ambience": ambience.describe() if ambience else {}, "music_state": music.describe() if music else {},
		"surface": surface_at(Game.player.global_position) if Game.player else ""}
