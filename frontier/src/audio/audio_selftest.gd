extends Node
## Audio self-test (`--audiotest`, headless OK): exercises every director API against the real world and manifest and
## prints AUDIOTEST lines + a PASS/FAIL verdict; quits with 0/1. Used by CI and the local loop.
##   godot --headless --path frontier -- --audiotest

var director: AudioDirector
var fails: PackedStringArray = []
var visemes := 0
var voice_done := 0

func run(d: AudioDirector) -> void:
	director = d
	director.viseme.connect(func(_a, _s, _w): visemes += 1)
	director.voice_finished.connect(func(_l, _a): voice_done += 1)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(director.ok, "manifest loaded")
	# every weapon sound id from weapons.gd has close/indoor/far/distant variants
	for w in Weapons.DEFS:
		var sid: String = Weapons.DEFS[w].sound
		for v in ["", "_indoor", "_far", "_distant"]:
			_check(director.has_sound("gun_" + sid + v), "gun_%s%s exists" % [sid, v])
	for s in AudioSurfaces.SURFACES:
		for g in ["walk", "run", "land"]:
			_check(director.has_sound("step_%s_%s" % [s, g]), "step_%s_%s" % [s, g])
		_check(director.has_sound("hoof_%s_hard" % s), "hoof_%s_hard" % s)
	for id in ["nerve_in", "nerve_out", "nerve_heartbeat", "nerve_mark", "ui_tick", "ui_page", "wind_calm", "crickets_night",
			"river", "rain_heavy", "thunder_close", "bullet_dirt", "ricochet", "whizz"]:
		_check(director.has_sound(id), id + " exists")
	# surfaces across the map
	var hist := {}
	var w: WorldData = Game.world
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 400:
		var x := rng.randf_range(-3800, 3800)
		var z := rng.randf_range(-3800, 3800)
		var p := Vector3(x, w.height(x, z) + 0.05, z)
		var s := director.surface_at(p)
		hist[s] = int(hist.get(s, 0)) + 1
	print("AUDIOTEST surfaces ", hist)
	_check(hist.size() >= 4, "at least 4 surface kinds across the map")
	var biomes := {}
	for i in 200:
		var x2 := rng.randf_range(-3800, 3800)
		var z2 := rng.randf_range(-3800, 3800)
		var b := AudioSurfaces.biome_at(Vector3(x2, 0, z2))
		biomes[b] = int(biomes.get(b, 0)) + 1
	print("AUDIOTEST biomes ", biomes)
	# gunshots at several distances (echo model too)
	var lp := director.listener_pos()
	var t0 := Time.get_ticks_usec()
	for dist in [0.0, 30.0, 120.0, 400.0, 1500.0]:
		director.gunshot("rifle_lever", lp + Vector3(dist, 0, 0), dist == 0.0)
	var refl := director.find_reflectors(lp)
	print("AUDIOTEST reflectors near listener: %d, gunshot calls %.2f ms" % [refl.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	director.impact("metal", lp + Vector3(5, 0, 0))
	director.ricochet(lp + Vector3(3, 1, 0))
	director.bullet_pass(lp + Vector3(1, 0, 0), true)
	director.gun_mech("lever", lp)
	# footsteps / hooves
	for s in ["dirt", "wood", "gravel", "water"]:
		director.footstep(lp, s, "run")
		director.hoof(lp, s, "hard")
	# pool stress: 200 one-shots in one frame
	t0 = Time.get_ticks_usec()
	for i in 200:
		director.play("bird_chip", lp + Vector3(rng.randf_range(-50, 50), 5, rng.randf_range(-50, 50)))
	print("AUDIOTEST 200 one-shots %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	# Nerve
	director.set_nerve(true)
	director.ui("nerve_mark")
	await get_tree().create_timer(0.5, true, false, true).timeout
	director.set_nerve(false)
	_check(not director.nerve_on, "nerve off")
	# music: forced explore, then combat from gunfire, then tension
	var ms: MusicDirector = director.music
	ms.forced_state = ""
	ms._rest_left = 0.0
	await get_tree().create_timer(1.0, true, false, true).timeout
	print("AUDIOTEST music ", ms.describe())
	for i in 10:
		director.gunshot("revolver_heavy", lp + Vector3(20, 0, 0), false)
	await get_tree().create_timer(0.6, true, false, true).timeout
	print("AUDIOTEST music after gunfire ", ms.describe())
	_check(director.music_tracks.is_empty() or ms.state == "combat", "combat music after gunfire")
	ms.set_mission("mission_ride")
	await get_tree().create_timer(0.6, true, false, true).timeout
	_check(director.music_tracks.is_empty() or ms.track_id == "mission_ride", "mission override")
	ms.set_mission("")
	ms.stinger("stinger_discovery")
	# voice
	var line := "ruth_hands_up"
	var dur := director.play_voice(line, null)
	print("AUDIOTEST voice %s %.2f s (%s)" % [line, dur, "audio" if director.voice_lines.has(line) else "estimated"])
	_check(dur > 0.3, "voice duration")
	var bd := director.bark("greeting", null, "man_rough")
	print("AUDIOTEST bark greeting %.2f s" % bd)
	await get_tree().create_timer(dur + 0.3, true, false, true).timeout
	_check(voice_done >= 1, "voice_finished emitted")
	if director.voice_lines.has(line):
		_check(visemes > 3, "viseme events emitted")
	# missing ids must not crash
	director.play("no_such_sound", lp)
	director.play_voice("no_such_line", null)
	director.ui("no_such_ui")
	# weather + ambience a few seconds
	if Game.sky != null:
		Game.sky.set_weather(SkySystem.Weather.STORM, true)
	await get_tree().create_timer(2.0, true, false, true).timeout
	print("AUDIOTEST ambience ", director.ambience.describe())
	print("AUDIOTEST stats ", director.stats)
	var errs := Game.error_logger.take()
	_check(errs.is_empty(), "no engine/script errors (%d)" % errs.size())
	if not errs.is_empty():
		print("AUDIOTEST first error ", errs[0])
	print("AUDIOTEST %s (%d checks failed)" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	for f in fails:
		print("AUDIOTEST FAIL ", f)
	get_tree().quit(0 if fails.is_empty() else 1)

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
