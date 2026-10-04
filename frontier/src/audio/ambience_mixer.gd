class_name AmbienceMixer
extends Node
## Ambience: stereo beds blended by biome (sampled around the listener), time of day, weather, altitude and interior
## state; positional loops for the nearest river/creek, the lake shore and towns; creature one-shots (birds by biome
## with a dawn chorus, owls, poorwills, coyotes, wolves, elk, frogs near water) at plausible distances; town life
## (anvil, hammering, church bell on the hour, train whistle, dogs); thunder timed to the sky's lightning by distance.
## Game code can add looping emitters (campfires, wagons, stoves) with add_emitter().

const UPDATE := 0.25
const FADE_PER_SEC := 0.3           # bed volume change per second (linear)

# bed id -> base dB (mix level at full target) and bus
const BEDS := {
	"wind_calm": [-4.0, "Ambience"], "wind_gusty": [-3.0, "Ambience"], "wind_mountain": [-4.0, "Ambience"],
	"wind_trees": [-3.0, "Ambience"], "wind_grass": [-4.0, "Ambience"], "wind_dust": [-2.0, "Ambience"],
	"cicadas_day": [-5.0, "Ambience"], "grasshoppers": [-4.0, "Ambience"], "crickets_night": [-3.0, "Ambience"],
	"frogs_night": [-3.0, "Ambience"], "rain_light": [-2.0, "Ambience"], "rain_heavy": [-1.0, "Ambience"],
	"rain_roof": [-1.0, "AmbInside"], "wind_interior": [-2.0, "AmbInside"], "crowd_saloon": [-2.0, "AmbInside"],
}

# day birds per biome: [id, calls per second at full activity]
const BIRDS_DAY := {
	"plains": [["bird_meadow", 0.05], ["bird_chip", 0.03], ["bird_dove", 0.015], ["bird_hawk", 0.004], ["bird_caw", 0.008]],
	"desert": [["bird_quail", 0.035], ["bird_dove", 0.015], ["bird_hawk", 0.007], ["bird_caw", 0.012], ["bird_chip", 0.015]],
	"forest": [["bird_feebee", 0.035], ["bird_trill", 0.035], ["bird_warble", 0.035], ["bird_woodpecker", 0.012],
		["bird_caw", 0.012], ["bird_chip", 0.025]],
	"mountain": [["bird_hawk", 0.01], ["bird_caw", 0.02], ["bird_trill", 0.02], ["bird_feebee", 0.015]],
	"marsh": [["bird_warble", 0.03], ["bird_chip", 0.03], ["bird_trill", 0.02], ["bullfrog", 0.01]],
}
const NIGHT := {
	"plains": [["owl_hoot", 0.006], ["poorwill", 0.01], ["coyote_chorus", 0.004]],
	"desert": [["poorwill", 0.015], ["coyote_chorus", 0.005], ["owl_hoot", 0.003]],
	"forest": [["owl_hoot", 0.012], ["wolf_howl", 0.002], ["coyote_chorus", 0.002]],
	"mountain": [["wolf_howl", 0.004], ["owl_hoot", 0.006], ["elk_bugle", 0.004]],
	"marsh": [["bullfrog", 0.04], ["owl_hoot", 0.005], ["coyote_chorus", 0.002]],
}
const FAR_CALLS := ["coyote_chorus", "rec_coyote", "wolf_howl", "elk_bugle", "bird_hawk"]
# preferred recordings (CI, Wikimedia Commons CC0/PD) over synthesised fallbacks
const REC := {"dog_bark_synth": "rec_dog_bark", "cattle_moo_synth": "rec_cattle_moo", "horse_whinny_synth": "rec_horse_whinny",
	"horse_snort": "rec_horse_snort", "horse_breath": "rec_horse_breath", "thunder_close": "rec_thunder",
	"thunder_far": "rec_thunder_far", "crowd_saloon": "rec_crowd_indoor", "crowd_street": "rec_crowd_outdoor",
	"rooster": "rec_rooster", "coyote_chorus": "rec_coyote", "train_whistle": "rec_steam_whistle"}

var director: Node
var beds: Dictionary = {}            # id -> {player, cur, target, base}
var room_bed := ""                   # interior bed requested by game code (e.g. crowd_saloon)
var emitters: Array = []             # [{player, node}]
var biome_w: Dictionary = {"plains": 1.0}
var wind_strength := 0.3
var activity := 1.0
var _t := 0.0
var _slow_t := 0.0
var _rng := RandomNumberGenerator.new()
var _river: AudioStreamPlayer3D
var _lake: AudioStreamPlayer3D
var _town: AudioStreamPlayer3D
var _last_lightning := 0.0
var _last_hour := -1
var calls := 0
var water_dist := INF
var town_id := ""

func _ready() -> void:
	director = get_parent()
	_rng.seed = 1899
	if AudioServer.get_bus_index("AmbInside") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "AmbInside")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "World")
	var lpf := AudioEffectLowPassFilter.new()
	lpf.cutoff_hz = 20000.0
	var bi := AudioServer.get_bus_index("Ambience")
	if AudioServer.get_bus_effect_count(bi) == 0:
		AudioServer.add_bus_effect(bi, lpf)
	_river = _loop3d("RiverLoop", 15.0, 260.0)
	_lake = _loop3d("LakeLoop", 12.0, 300.0)
	_town = _loop3d("TownLoop", 25.0, 450.0)

func _loop3d(nm: String, unit: float, maxd: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = nm
	p.bus = "Ambience"
	p.unit_size = unit
	p.max_distance = maxd
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.panning_strength = 0.7
	add_child(p)
	return p

func rec_or(id: String) -> String:
	var r: String = REC.get(id, "")
	if not r.is_empty() and director.has_sound(r):
		return r
	return id

## A looping positional emitter (campfire, wagon, stove, mill) following `target` (Node3D) or fixed at a Vector3.
func add_emitter(id: String, target, volume_db := 0.0) -> AudioStreamPlayer3D:
	var s: AudioStream = director.loop_stream(id)
	var p := AudioStreamPlayer3D.new()
	p.bus = "Ambience"
	var e: Dictionary = director.sounds.get(id, {})
	p.unit_size = float(e.get("unit_size", 3.0))
	p.max_distance = float(e.get("max_dist", 40.0))
	p.volume_db = volume_db + float(e.get("gain_db", 0.0))
	p.stream = s
	add_child(p)
	if target is Vector3:
		p.global_position = target
	emitters.append({"player": p, "node": target if target is Node3D else null})
	if s != null:
		p.play()
	return p

func remove_emitter(p: AudioStreamPlayer3D) -> void:
	emitters = emitters.filter(func(e): return e.player != p)
	if is_instance_valid(p):
		p.queue_free()

func set_room_bed(id: String) -> void:
	room_bed = id

func _process(dt: float) -> void:
	for e in emitters:
		if e.node != null and is_instance_valid(e.node):
			(e.player as AudioStreamPlayer3D).global_position = (e.node as Node3D).global_position
	for id in beds:
		_fade_bed(beds[id], dt)
	_t += dt
	if _t < UPDATE:
		return
	var step := _t
	_t = 0.0
	if not director.ok:
		return
	var lp: Vector3 = director.listener_pos()
	_slow_t -= step
	if _slow_t <= 0.0:
		_slow_t = 1.0
		_sample_biomes(lp)
		_place_water(lp)
		_place_town(lp)
	_update_beds(lp)
	_spawn_calls(lp, step)
	_weather_events(lp)

func _sample_biomes(lp: Vector3) -> void:
	var w := {}
	var pts := [lp]
	for k in 6:
		var a := TAU * k / 6.0
		pts.append(lp + Vector3(cos(a), 0, sin(a)) * 70.0)
	for p in pts:
		var b := AudioSurfaces.biome_at(p)
		w[b] = float(w.get(b, 0.0)) + 1.0 / pts.size()
	biome_w = w

func _bw(b: String) -> float:
	return float(biome_w.get(b, 0.0))

func _sky(prop: String, def := 0.0) -> float:
	if Game.sky == null:
		return def
	var v = Game.sky.get(prop)
	return float(v) if v != null else def

func _hours() -> float:
	return _sky("hours", 10.0)

func _daylight() -> float:
	# 0 night .. 1 day, smooth over dawn (5-7) and dusk (18-20)
	var h := _hours()
	return clampf(smoothstep(5.0, 7.0, h) - smoothstep(18.0, 20.0, h), 0.0, 1.0)

func _update_beds(lp: Vector3) -> void:
	var w: WorldData = Game.world
	var alt := w.height(lp.x, lp.z) if w != null and w.ok else 300.0
	var rain := _sky("rain")
	var dust := _sky("dust")
	var cover := _sky("cover", 0.3)
	var day := _daylight()
	var night := 1.0 - day
	var inside: bool = director.listener_interior
	wind_strength = clampf(0.15 + cover * 0.3 + rain * 0.35 + dust * 0.8 + clampf((alt - 500.0) / 1100.0, 0.0, 0.5), 0.0, 1.0)
	var ws := wind_strength
	activity = (1.0 - rain * 0.85) * (1.0 - ws * 0.5)
	var t := {}
	var outside := 0.0 if inside else 1.0
	t["wind_calm"] = (1.0 - ws) * 0.9 * outside + 0.1
	t["wind_gusty"] = clampf((ws - 0.45) * 1.8, 0.0, 1.0) * outside
	t["wind_mountain"] = clampf((alt - 750.0) / 400.0, 0.0, 1.0) * (0.4 + ws * 0.6) * outside
	t["wind_trees"] = _bw("forest") * (0.35 + ws * 0.65) * outside
	t["wind_grass"] = (_bw("plains") + _bw("marsh") * 0.5) * (0.3 + ws * 0.7) * outside
	t["wind_dust"] = dust * outside
	var h := _hours()
	var midday := clampf(smoothstep(9.0, 11.5, h) - smoothstep(17.0, 19.0, h), 0.0, 1.0)
	var warm := (_bw("plains") + _bw("desert") + _bw("forest") * 0.6 + _bw("marsh")) * (1.0 - clampf((alt - 900.0) / 300.0, 0.0, 1.0))
	t["cicadas_day"] = midday * warm * activity * outside
	t["grasshoppers"] = midday * (_bw("plains") + _bw("desert")) * activity * outside
	t["crickets_night"] = night * (1.0 - clampf((alt - 1100.0) / 200.0, 0.0, 1.0)) * activity * (0.4 + 0.6 * outside)
	var near_water := clampf(1.0 - water_dist / 220.0, 0.0, 1.0)
	t["frogs_night"] = night * maxf(near_water, _bw("marsh")) * activity * outside
	t["rain_light"] = clampf(rain * 2.0, 0.0, 1.0) * (1.0 - clampf((rain - 0.5) * 2.0, 0.0, 0.7)) * outside
	t["rain_heavy"] = clampf((rain - 0.4) * 1.7, 0.0, 1.0) * outside
	t["rain_roof"] = clampf(rain * 1.5, 0.0, 1.0) * (1.0 - outside)
	t["wind_interior"] = ws * (1.0 - outside)
	if not room_bed.is_empty():
		t[room_bed] = 1.0 - outside
	for id in BEDS:
		_set_bed(id, float(t.get(id, 0.0)))
	if not room_bed.is_empty() and not BEDS.has(room_bed):
		_set_bed(room_bed, 1.0 - outside)
	# outdoor beds heard from inside are muffled by the Ambience low-pass
	var bi := AudioServer.get_bus_index("Ambience")
	if AudioServer.get_bus_effect_count(bi) > 0:
		var fx := AudioServer.get_bus_effect(bi, 0) as AudioEffectLowPassFilter
		if fx != null:
			fx.cutoff_hz = 900.0 if inside else 20000.0
	# positional loops level with day/night (river never sleeps)
	_town.volume_db = -3.0 + linear_to_db(maxf(0.05, 0.3 + 0.7 * day))

func _set_bed(id: String, target: float) -> void:
	if not beds.has(id):
		if target < 0.01:
			return
		var base: Array = BEDS.get(id, [-3.0, "Ambience"])
		var sid := rec_or(id)
		var s: AudioStream = director.loop_stream(sid)
		var p := AudioStreamPlayer.new()
		p.name = "Bed_" + id
		p.bus = base[1]
		p.stream = s
		p.volume_db = -80.0
		add_child(p)
		beds[id] = {"player": p, "cur": 0.0, "target": 0.0, "base": float(base[0]), "ok": s != null}
	beds[id].target = clampf(target, 0.0, 1.0)

func _fade_bed(b: Dictionary, dt: float) -> void:
	var p: AudioStreamPlayer = b.player
	if not b.ok:
		return
	b.cur = move_toward(float(b.cur), float(b.target), FADE_PER_SEC * dt)
	if b.cur > 0.002:
		if not p.playing:
			p.play(_rng.randf() * maxf(p.stream.get_length() - 1.0, 0.0))
		p.volume_db = float(b.base) + linear_to_db(float(b.cur))
	elif p.playing:
		p.stop()

func _place_water(lp: Vector3) -> void:
	var w: WorldData = Game.world
	if w == null or not w.ok:
		return
	water_dist = INF
	var r := w.river_at(lp.x, lp.z)
	if not r.is_empty():
		water_dist = float(r.dist)
		var d: Vector2 = r.dir
		# nearest point on the river line: step from the listener toward the river centre
		var to := Vector2(-d.y, d.x)
		var p2 := Vector2(lp.x, lp.z)
		var c1 := p2 + to * float(r.dist)
		var c2 := p2 - to * float(r.dist)
		var r1 := w.river_at(c1.x, c1.y)
		var c := c1 if (not r1.is_empty() and float(r1.dist) < 3.0) else c2
		var id := "river" if float(r.width) >= 12.0 else "creek"
		_ensure_loop(_river, id)
		_river.global_position = Vector3(c.x, float(r.surface) + 0.5, c.y)
	elif _river.playing:
		_river.stop()
	# lake shore: nearest lake cell within ~320 m (coarse radial search)
	var best := INF
	var bp := Vector3.ZERO
	if w.height(lp.x, lp.z) < w.lake_level + 60.0:
		for k in 16:
			var a := TAU * k / 16.0
			var dir := Vector3(cos(a), 0, sin(a))
			var dist := 0.0
			while dist < 320.0:
				var p := lp + dir * dist
				if w.height(p.x, p.z) < w.lake_level:
					if dist < best:
						best = dist
						bp = Vector3(p.x, w.lake_level + 0.3, p.z)
					break
				dist += 16.0
	if best < INF:
		water_dist = minf(water_dist, best)
		_ensure_loop(_lake, "lake_shore")
		_lake.global_position = bp
	elif _lake.playing:
		_lake.stop()

func _ensure_loop(p: AudioStreamPlayer3D, id: String) -> void:
	if p.has_meta("id") and p.get_meta("id") == id and p.playing:
		return
	var s: AudioStream = director.loop_stream(rec_or(id))
	if s == null:
		return
	p.set_meta("id", id)
	p.stream = s
	p.play(_rng.randf() * maxf(s.get_length() - 1.0, 0.0))

func _place_town(lp: Vector3) -> void:
	var w: WorldData = Game.world
	if w == null or not w.ok:
		return
	town_id = ""
	for t in w.features.get("towns", []):
		var d := Vector2(float(t.x) - lp.x, float(t.z) - lp.z).length()
		if d < float(t.r) * 2.2:
			town_id = t.id
			_ensure_loop(_town, "crowd_street")
			_town.global_position = Vector3(float(t.x), float(t.y) + 2.0, float(t.z))
			return
	if _town.playing:
		_town.stop()

func _spawn_calls(lp: Vector3, dt: float) -> void:
	var day := _daylight()
	var h := _hours()
	var chorus := 1.0 + 1.6 * clampf(1.0 - absf(h - 6.8) / 1.8, 0.0, 1.0) + 0.6 * clampf(1.0 - absf(h - 18.0) / 1.2, 0.0, 1.0)
	var inside: bool = director.listener_interior
	var act := activity * (0.25 if inside else 1.0)
	for b in biome_w:
		var bw := float(biome_w[b])
		if day > 0.2:
			for c in BIRDS_DAY.get(b, []):
				if _rng.randf() < float(c[1]) * bw * day * chorus * act * dt:
					_call(c[0], lp)
		if day < 0.6:
			for c in NIGHT.get(b, []):
				var rate := float(c[1])
				if c[0] == "bullfrog" or c[0] == "frog":
					rate *= clampf(1.0 - water_dist / 200.0, 0.0, 1.0) + float(b == "marsh")
				if c[0] == "coyote_chorus":
					rate *= 1.0 + 2.0 * clampf(1.0 - absf(h - 20.0) / 1.5, 0.0, 1.0)     # they sing at dusk
				if _rng.randf() < rate * bw * (1.0 - day) * act * dt:
					_call(rec_or(c[0]), lp)
	if not town_id.is_empty() and not inside:
		if day > 0.5 and _rng.randf() < 0.05 * dt:
			_town_burst("anvil", lp, int(_rng.randi_range(3, 8)), 0.55)
		if day > 0.5 and _rng.randf() < 0.025 * dt:
			_town_burst("hammer_wood", lp, int(_rng.randi_range(2, 6)), 0.45)
		if _rng.randf() < 0.012 * dt:
			_call(rec_or("dog_bark_synth"), lp, 40.0, 160.0)
		if day > 0.3 and _rng.randf() < 0.02 * dt:
			_call(rec_or("horse_snort"), lp, 10.0, 50.0)
	var hr := int(h)
	if hr != _last_hour:
		if _last_hour != -1 and not town_id.is_empty() and hr in [7, 12, 18]:
			_bell(hr)
		if _last_hour != -1 and (town_id == "bitter_spring" or town_id == "mesquite_wells") and _rng.randf() < 0.5:
			director.play(rec_or("train_whistle"), lp + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * 900.0,
				{"delay": _rng.randf_range(5.0, 50.0), "occlude": false})
		if _last_hour != -1 and hr >= 5 and hr <= 7 and _near_poi(lp, ["ranch", "homestead"]) and director.has_sound("rooster"):
			_call(rec_or("rooster"), lp, 60.0, 250.0)
		_last_hour = hr
	if _near_poi(lp, ["ranch"]) and day > 0.2 and _rng.randf() < 0.02 * dt:
		_call(rec_or("cattle_moo_synth"), lp, 60.0, 400.0)

func _near_poi(lp: Vector3, kinds: Array) -> bool:
	var w: WorldData = Game.world
	if w == null:
		return false
	for p in w.features.get("pois", []):
		if str(p.get("kind", "")) in kinds and Vector2(float(p.x) - lp.x, float(p.z) - lp.z).length() < 600.0:
			return true
	return false

func _call(id: String, lp: Vector3, dmin := -1.0, dmax := -1.0) -> void:
	if not director.has_sound(id):
		return
	var far := id in FAR_CALLS
	if dmin < 0.0:
		dmin = 400.0 if far else 15.0
		dmax = 1400.0 if far else 90.0
		if id == "bird_hawk":
			dmin = 60.0
			dmax = 300.0
	var a := _rng.randf() * TAU
	var d := _rng.randf_range(dmin, dmax)
	var p := lp + Vector3(cos(a) * d, _rng.randf_range(2.0, 12.0) if not far else 20.0, sin(a) * d)
	director.play(id, p, {"occlude": false})
	calls += 1

func _town_burst(id: String, lp: Vector3, count: int, gap: float) -> void:
	var w: WorldData = Game.world
	var t := w.town(town_id) if w != null else {}
	if t.is_empty():
		return
	var at := Vector3(float(t.x) + _rng.randf_range(-40, 40), float(t.y) + 1.0, float(t.z) + _rng.randf_range(-40, 40))
	for i in count:
		director.play(id, at, {"delay": i * gap * _rng.randf_range(0.85, 1.15)})

func _bell(hr: int) -> void:
	var w: WorldData = Game.world
	var t := w.town(town_id)
	if t.is_empty():
		return
	var at := Vector3(float(t.x), float(t.y) + 12.0, float(t.z))
	var n := 3 if hr != 12 else 6
	for i in n:
		director.play("church_bell", at, {"delay": i * 2.2, "occlude": false})

func _weather_events(lp: Vector3) -> void:
	var l := _sky("lightning")
	if l > 0.9 and _last_lightning < 0.5:
		var d := _rng.randf_range(300.0, 5000.0)
		var id := rec_or("thunder_close" if d < 1500.0 else "thunder_far")
		director.play(id, null, {"bus": "Ambience", "delay": d / 343.0, "volume_db": -20.0 * log(d / 300.0) / log(10.0) * 0.5})
	_last_lightning = l

func describe() -> Dictionary:
	var active := {}
	for id in beds:
		if beds[id].cur > 0.01:
			active[id] = snappedf(float(beds[id].cur), 0.01)
	return {"beds": active, "biomes": biome_w, "wind": snappedf(wind_strength, 0.01), "calls": calls,
		"water_dist": snappedf(water_dist, 1.0) if water_dist < INF else -1, "town": town_id,
		"river": _river.playing, "lake": _lake.playing}
