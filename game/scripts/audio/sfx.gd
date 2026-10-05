extends Node
## Audio: the procedural bank (Synth, rendered on a worker thread at start and cached in user://audio_v3), a pool
## of 3D voices with distance filtering, the speed of sound for far events (a blast 2 km away is heard 6 s
## later), buses (SFX with outdoor reverb, Ambience, Music), vehicle loops that follow their node with pitch, and
## an ambience director: wind by altitude and weather, rain, the sea near the coast, birds by day and crickets at
## night, the far battle near the front, the city's hum and the Capital's theme in Candor.

const CACHE := "user://audio_v3"
const VOICES := 40
const SOUND := 343.0

var bank := {}                    # name -> AudioStreamWAV
var ready_ := false
var voices: Array[AudioStreamPlayer3D] = []
var _vi := 0
var pending: Array = []           # [time, name, pos, vol_db, pitch]
var amb := {}                     # name -> AudioStreamPlayer (2D ambience)
var music: AudioStreamPlayer
var _task := -1
var _step_i := 0
var _amb_t := 0.0


func _ready() -> void:
	_buses()
	if DisplayServer.get_name() == "headless" and not Settings.has_arg("sounds"):
		return
	_task = WorkerThreadPool.add_task(_build_bank, false, "synth bank")


func _buses() -> void:
	for nm in ["SFX", "Ambience", "Music"]:
		if AudioServer.get_bus_index(nm) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, nm)
			AudioServer.set_bus_send(i, "Master")
	var sfx := AudioServer.get_bus_index("SFX")
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.65
	rev.damping = 0.4
	rev.wet = 0.12
	rev.dry = 1.0
	rev.predelay_msec = 60.0
	AudioServer.add_bus_effect(sfx, rev)
	var lim := AudioEffectHardLimiter.new()
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), lim)
	_volumes()


func _volumes() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(Settings.master_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(Settings.sfx_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(Settings.music_volume * 0.6, 0.0001)))


func _build_bank() -> void:
	if not DirAccess.dir_exists_absolute(CACHE):
		DirAccess.make_dir_recursive_absolute(CACHE)
	var out := {}
	for n in Synth.names():
		var path := CACHE.path_join(n + ".res")
		var s: AudioStreamWAV = null
		if ResourceLoader.exists(path):
			s = load(path) as AudioStreamWAV
		if s == null:
			s = _wav(Synth.render(n), Synth.is_loop(n))
			ResourceSaver.save(s, path)
		out[n] = s
	call_deferred("_bank_ready", out)


func _bank_ready(out: Dictionary) -> void:
	bank = out
	ready_ = true
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 12.0
		p.max_distance = 6000.0
		p.attenuation_filter_cutoff_hz = 3500.0
		p.attenuation_filter_db = -18.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_IDLE_STEP
		add_child(p)
		voices.append(p)
	for n in ["loop_wind", "loop_rain", "loop_sea", "loop_birds", "loop_crickets", "loop_battle_far", "loop_city"]:
		var a := AudioStreamPlayer.new()
		a.stream = bank[n]
		a.bus = "Ambience"
		a.volume_db = -80.0
		add_child(a)
		a.play(randf() * 3.0)
		amb[n] = a
	music = AudioStreamPlayer.new()
	music.stream = bank["music_capital"]
	music.bus = "Music"
	music.volume_db = -80.0
	add_child(music)
	music.play()
	if Settings.has_arg("sounds"):
		_dump(String(Settings.arg("sounds")))


func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = Synth.RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s


## --sounds DIR: writes every sound as a WAV for listening checks, then quits.
func _dump(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	for n in bank:
		(bank[n] as AudioStreamWAV).save_to_wav(dir.path_join(n + ".wav"))
	print("sounds: wrote %d WAVs to %s" % [bank.size(), dir])
	get_tree().quit(0)


# ----------------------------------------------------------------------------------------------- one-shots

## Plays a sound at a world position; far sounds arrive late (speed of sound) and quieter.
func play_at(n: String, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if not ready_ or not bank.has(n):
		return
	var cam := get_viewport().get_camera_3d()
	var d := cam.global_position.distance_to(pos) if cam else 0.0
	if d > 120.0:
		pending.append([Time.get_ticks_msec() / 1000.0 + d / SOUND, n, pos, vol_db, pitch])
	else:
		_play_now(n, pos, vol_db, pitch)


func _play_now(n: String, pos: Vector3, vol_db: float, pitch: float) -> void:
	var p := voices[_vi % voices.size()]
	_vi += 1
	p.stream = bank[n]
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.play()


func play_ui(n: String = "ui") -> void:
	if not ready_:
		return
	var a := AudioStreamPlayer.new()
	a.stream = bank[n]
	a.bus = "SFX"
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


func footstep(pos: Vector3, speed: float) -> void:
	var hard: bool = G.world != null and G.world.city_list.size() > 0 and G.world.city_list[0].in_city(pos.x, pos.z)
	if ready_:
		_play_now("footstep_hard" if hard else "footstep_grass", pos, -14.0 + speed, 1.0)


func gunshot(pos: Vector3, faction: int) -> void:
	play_at("rifle_capital" if faction == 0 else "rifle_cinder", pos, -2.0)


func player_shot(pos: Vector3) -> void:
	if ready_:
		_play_now("rifle_player", pos, 2.0, 1.0)


func explosion(pos: Vector3, power: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var d := cam.global_position.distance_to(pos) if cam else 0.0
	play_at("explosion" if d < 1500.0 else "explosion_far", pos, 6.0 + power * 4.0, 1.15 - minf(power, 2.0) * 0.12)


func cannon(pos: Vector3, power: float) -> void:
	play_at("cannon_heavy" if power > 1.0 else ("cannon_medium" if power > 0.5 else "autocannon"), pos, 4.0 + power * 3.0)


func rocket(pos: Vector3) -> void:
	play_at("rocket", pos, 0.0)


func thunder(pos: Vector3) -> void:
	play_at("thunder", pos, 10.0, randf_range(0.8, 1.1))


func distant_guns(pos: Vector3) -> void:
	play_at("cannon_heavy", pos, 6.0, 0.8)


func impact(pos: Vector3, metal: bool) -> void:
	play_at("impact_metal" if metal else "impact_dirt", pos, -8.0)


## A looping sound that follows a node (engines, rotors); returns the player so the vehicle can set its pitch.
func attach_loop(node: Node3D, n: String, vol_db: float = 0.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.unit_size = 14.0
	p.max_distance = 2500.0
	p.volume_db = vol_db
	p.attenuation_filter_cutoff_hz = 4000.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	node.add_child(p)
	if ready_ and bank.has(n):
		p.stream = bank[n]
		p.play(randf() * 1.0)
	else:
		_late_loops.append([p, n])
	return p


var _late_loops: Array = []


# ------------------------------------------------------------------------------------------------- update

func _process(delta: float) -> void:
	if not ready_:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var keep := []
	for e in pending:
		if now >= e[0]:
			_play_now(e[1], e[2], e[3], e[4])
		else:
			keep.append(e)
	pending = keep
	for l in _late_loops:
		var p: AudioStreamPlayer3D = l[0]
		if is_instance_valid(p):
			p.stream = bank[l[1]]
			p.play(randf())
	_late_loops.clear()
	_amb_t += delta
	if _amb_t > 0.25:
		_ambience(_amb_t)
		_amb_t = 0.0


func _set_amb(n: String, target_db: float, dt: float) -> void:
	var a: AudioStreamPlayer = amb[n]
	a.volume_db = move_toward(a.volume_db, target_db, dt * 20.0)


func _ambience(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or G.world == null:
		return
	var p := cam.global_position
	var ground := G.world.ground_at(p.x, p.z)
	var alt := p.y - ground
	var night: float = 1.0 - G.sky.daylight if G.sky else 0.0
	var w: WeatherSystem = G.weather as WeatherSystem
	var wind_k: float = (w.cur.get("wind", 0.3) if w else 0.3)
	var rain_k: float = (w.cur.get("rain", 0.0) if w else 0.0)
	var forest := G.gen.forest_at(p.x, p.z) if G.gen else 0.0
	var sea_d := 1e9
	if G.gen:
		for k in 8:
			var a := TAU * k / 8.0
			if G.gen.water_at(p.x + cos(a) * 300.0, p.z + sin(a) * 300.0) == 0.0:
				sea_d = 300.0
	var in_city: bool = G.world.city_list.size() > 0 and G.world.city_list[0].in_city(p.x, p.z, -400.0)
	var front_d: float = p.distance_to(G.battle.front) if G.battle else 1e9
	_set_amb("loop_wind", lerpf(-30.0, -8.0, clampf(wind_k * 0.7 + alt / 400.0, 0.0, 1.0)), dt)
	_set_amb("loop_rain", -80.0 if rain_k < 0.05 else lerpf(-24.0, -6.0, rain_k), dt)
	_set_amb("loop_sea", -14.0 if sea_d < 400.0 and alt < 120.0 else -80.0, dt)
	_set_amb("loop_birds", lerpf(-80.0, -16.0, clampf(forest * 2.0, 0.0, 1.0) * (1.0 - night) * (1.0 - rain_k)) if alt < 60.0 else -80.0, dt)
	_set_amb("loop_crickets", lerpf(-80.0, -18.0, night * (1.0 - rain_k)) if alt < 60.0 and not in_city else -80.0, dt)
	_set_amb("loop_battle_far", -80.0 if front_d > 6000.0 or front_d < 500.0 else lerpf(-6.0, -30.0, clampf((front_d - 500.0) / 5500.0, 0.0, 1.0)), dt)
	_set_amb("loop_city", -14.0 if in_city else -80.0, dt)
	var music_target := -12.0 if (in_city or (G.gen and p.distance_to(G.gen.sites["citadel"]) < 600.0)) else -40.0
	music.volume_db = move_toward(music.volume_db, music_target, dt * 4.0)
