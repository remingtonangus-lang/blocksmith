class_name MusicDirector
extends Node
## Adaptive score. Each track (manifest "music") is a set of equal-length looping stems (e.g. base / rhythm / melody /
## tension) started together and kept in sync; the director fades stems in and out for intensity and crossfades
## between tracks on state changes.
## States (priority high -> low): nerve (duck + stinger), mission (set_mission), combat (gunfire near the listener,
## 3 intensities), tension (set_tension or the cool-down after a fight), town (inside a settlement), explore (biome x
## day/night track; plays in episodes with silences between, like a score that comes and goes).

signal state_changed(state: String, track: String)

const XFADE := 3.0
const COMBAT_HOLD := 14.0            # seconds of quiet before combat ends
const TENSION_HOLD := 12.0

class Track:
	var id: String
	var info: Dictionary
	var players: Dictionary = {}     # stem -> AudioStreamPlayer
	var cur: Dictionary = {}         # stem -> linear level now
	var target: Dictionary = {}      # stem -> linear level target
	var master := 0.0
	var master_target := 0.0
	var fade_rate := 1.0 / 3.0
	var started := false

var director: Node
var state := "silent"
var track_id := ""
var tracks: Dictionary = {}          # id -> Track (live)
var mission_track := ""
var tension := 0.0
var _tension_until := 0.0
var _combat_until := 0.0
var _combat_level := 0
var _explore_left := 0.0             # seconds left of the current exploration episode
var _rest_left := 20.0               # silence before the next episode
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _stinger: AudioStreamPlayer
var _nerve := false
var forced_state := ""               # tests: --music <state>

func _ready() -> void:
	director = get_parent()
	_rng.seed = 99
	_stinger = AudioStreamPlayer.new()
	_stinger.name = "Stinger"
	_stinger.bus = "Music"
	add_child(_stinger)
	if Game.args.has("music"):
		forced_state = str(Game.args["music"])
		_rest_left = 0.0

## Mission music override (track id from the manifest, e.g. "mission_ride", "mission_heist"); "" clears.
func set_mission(id: String) -> void:
	mission_track = id

## Tension from game systems (hostiles nearby, wanted, sneaking): level 0..1 held for `seconds`.
func set_tension(level: float, seconds := 10.0) -> void:
	tension = clampf(level, 0.0, 1.0)
	_tension_until = director.game_time() + seconds

func on_gunshot(origin: Vector3, is_player: bool) -> void:
	var d: float = director.listener_pos().distance_to(origin)
	if is_player or d < 160.0:
		_combat_until = director.game_time() + COMBAT_HOLD

func on_nerve(on: bool) -> void:
	_nerve = on
	if on:
		stinger("stinger_nerve")

## One-shot cue over the score (mission_complete, death, discovery, nerve).
func stinger(id: String) -> void:
	var t: Dictionary = director.music_tracks.get(id, {})
	var stems: Dictionary = t.get("stems", {})
	if stems.is_empty():
		return
	var s: AudioStream = director.stream_for(stems.values()[0])
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = false
	_stinger.stream = s
	_stinger.volume_db = float(t.get("gain_db", 0.0))
	_stinger.play()

func _process(dt: float) -> void:
	for id in tracks.keys():
		_fade_track(tracks[id], dt)
	_t += dt
	if _t < 0.25:
		return
	var step := _t
	_t = 0.0
	if not director.ok or director.music_tracks.is_empty():
		return
	_decide(step)

func _combat_intensity() -> int:
	var now: float = director.game_time()
	var lp: Vector3 = director.listener_pos()
	var n := 0
	for s in director.recent_shots:
		if now - float(s.t) < 8.0 and (s.player or lp.distance_to(s.pos) < 160.0):
			n += 1
	if n >= 9:
		return 3
	if n >= 4:
		return 2
	return 1

func _decide(dt: float) -> void:
	var now: float = director.game_time()
	var want_state := "explore"
	var want_track := ""
	var levels := {}
	if not forced_state.is_empty():
		want_state = forced_state
	elif not mission_track.is_empty():
		want_state = "mission"
	elif now < _combat_until:
		want_state = "combat"
	elif now < _combat_until + TENSION_HOLD and _combat_until > 0.0 or now < _tension_until:
		want_state = "tension"
	elif director.ambience != null and not str(director.ambience.town_id).is_empty():
		want_state = "town"
	match want_state:
		"mission":
			want_track = mission_track if director.music_tracks.has(mission_track) else "main_theme"
			levels = _all_stems(want_track, 1.0)
		"combat":
			_combat_level = _combat_intensity()
			want_track = _first(["combat"])
			levels = _intensity_levels(want_track, ["low", "mid", "high"][_combat_level - 1])
		"tension":
			want_track = _first(["tension"])
			var lv := "high" if tension > 0.6 else "low"
			levels = _intensity_levels(want_track, lv)
		"town":
			want_track = _first(["town"])
			levels = _intensity_levels(want_track, "mid" if _daytime() else "low")
		_:
			# exploration episodes
			if _explore_left > 0.0:
				_explore_left -= dt
				if _explore_left <= 0.0:
					_rest_left = _rng.randf_range(50.0, 150.0)
			elif _rest_left > 0.0:
				_rest_left -= dt
				if _rest_left <= 0.0:
					_explore_left = _rng.randf_range(110.0, 220.0)
			if _explore_left > 0.0 or not forced_state.is_empty():
				want_track = _explore_track()
				levels = _intensity_levels(want_track, _explore_intensity())
			else:
				want_state = "silent"
	if want_track != track_id:
		_switch(want_track, want_state)
	elif want_state != state:
		state = want_state
		state_changed.emit(state, track_id)
	if not track_id.is_empty() and tracks.has(track_id):
		var tr: Track = tracks[track_id]
		for stem in tr.players:
			tr.target[stem] = float(levels.get(stem, 0.0))
		tr.fade_rate = 1.0 / (1.2 if want_state == "combat" else XFADE)

func _daytime() -> bool:
	return Game.sky == null or not Game.sky.is_night()

func _explore_track() -> String:
	var lp: Vector3 = director.listener_pos()
	var b := AudioSurfaces.biome_at(lp)
	var flavour: String = {"desert": "desert", "plains": "plains", "marsh": "plains", "forest": "mountains", "mountain": "mountains"}[b]
	var tod := "day" if _daytime() else "night"
	return _first(["explore_%s_%s" % [flavour, tod], "explore_%s" % flavour, "explore_" + tod, "explore_plains_day", "main_theme"])

func _explore_intensity() -> String:
	var pl = Game.player
	if pl != null and pl.get("on_horse") != null:
		var h = pl.on_horse
		if h != null and h.get("speed") != null and float(h.get("speed")) > 7.0:
			return "high"
		return "mid"
	if pl != null and pl.get("speed") != null and float(pl.get("speed")) > 5.0:
		return "mid"
	return "low"

func _first(ids: Array) -> String:
	for id in ids:
		if director.music_tracks.has(id):
			return id
	return ""

func _all_stems(id: String, v: float) -> Dictionary:
	var out := {}
	for stem in director.music_tracks.get(id, {}).get("stems", {}):
		out[stem] = v
	return out

## manifest track "intensity": {"low": ["base"], "mid": ["base", "rhythm"], "high": [...]}; stems not listed are 0.
func _intensity_levels(id: String, lv: String) -> Dictionary:
	var t: Dictionary = director.music_tracks.get(id, {})
	var inten: Dictionary = t.get("intensity", {})
	if inten.is_empty():
		return _all_stems(id, 1.0)
	var out := {}
	for stem in inten.get(lv, inten.get("mid", [])):
		out[stem] = 1.0
	return out

func _switch(id: String, new_state: String) -> void:
	if tracks.has(track_id):
		var old: Track = tracks[track_id]
		old.master_target = 0.0
		old.fade_rate = 1.0 / (1.0 if new_state == "combat" else XFADE)
	track_id = id
	state = new_state
	state_changed.emit(state, track_id)
	Game.log_event("music", {"state": state, "track": track_id})
	if id.is_empty():
		return
	if not tracks.has(id):
		var tr := Track.new()
		tr.id = id
		tr.info = director.music_tracks[id]
		for stem in tr.info.get("stems", {}):
			var s: AudioStream = director.stream_for(tr.info.stems[stem])
			if s == null:
				continue
			if s is AudioStreamOggVorbis:
				(s as AudioStreamOggVorbis).loop = bool(tr.info.get("loop", true))
			var p := AudioStreamPlayer.new()
			p.name = "%s_%s" % [id, stem]
			p.bus = "Music"
			p.stream = s
			p.volume_db = -80.0
			add_child(p)
			tr.players[stem] = p
			tr.cur[stem] = 0.0
			tr.target[stem] = 0.0
		tracks[id] = tr
	var t: Track = tracks[id]
	t.master_target = 1.0
	if not t.started or not _any_playing(t):
		for stem in t.players:
			(t.players[stem] as AudioStreamPlayer).play()       # same frame -> same mix block: stems stay locked
		t.started = true

func _any_playing(t: Track) -> bool:
	for stem in t.players:
		if (t.players[stem] as AudioStreamPlayer).playing:
			return true
	return false

func _fade_track(t: Track, dt: float) -> void:
	var real_dt := dt / maxf(Engine.time_scale, 0.01)
	t.master = move_toward(t.master, t.master_target, t.fade_rate * real_dt)
	var gain := float(t.info.get("gain_db", 0.0))
	for stem in t.players:
		t.cur[stem] = move_toward(float(t.cur[stem]), float(t.target.get(stem, 0.0)), t.fade_rate * 0.8 * real_dt)
		var p: AudioStreamPlayer = t.players[stem]
		var lin := float(t.cur[stem]) * t.master
		p.volume_db = gain + linear_to_db(maxf(lin, 0.00001))
	if t.master <= 0.0005 and t.master_target == 0.0 and _any_playing(t):
		for stem in t.players:
			(t.players[stem] as AudioStreamPlayer).stop()
		t.started = false

func describe() -> Dictionary:
	var lv := {}
	if tracks.has(track_id):
		var t: Track = tracks[track_id]
		for s in t.cur:
			lv[s] = snappedf(float(t.cur[s]) * t.master, 0.01)
	return {"state": state, "track": track_id, "stems": lv, "combat_level": _combat_level,
		"explore_left": snappedf(_explore_left, 1.0), "rest_left": snappedf(_rest_left, 1.0)}
