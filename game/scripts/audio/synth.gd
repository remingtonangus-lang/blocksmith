class_name Synth
## Procedural sound synthesis: every sound in the game is rendered here from noise, oscillators, envelopes and
## filters (no recorded audio). Each render returns a PackedFloat32Array of mono samples at RATE; Sfx turns them
## into AudioStreamWAVs (cached in user://).

const RATE := 22050


static func names() -> Array:
	return ["rifle_capital", "rifle_cinder", "rifle_player", "autocannon", "cannon_heavy", "cannon_medium",
		"explosion", "explosion_far", "thunder", "rocket", "impact_dirt", "impact_metal", "whizz", "footstep_grass",
		"footstep_hard", "reload", "dry", "ui", "grenade_pin", "tree_fall", "loop_rotor", "loop_crawler", "loop_truck",
		"loop_fans", "loop_frigate", "loop_wind", "loop_rain", "loop_sea", "loop_birds", "loop_crickets",
		"loop_battle_far", "loop_city", "music_capital"]


static func is_loop(n: String) -> bool:
	return n.begins_with("loop_") or n.begins_with("music_")


static func render(n: String) -> PackedFloat32Array:
	match n:
		"rifle_capital": return _gunshot(0.32, 2600.0, 160.0, 1.0, 11)
		"rifle_cinder": return _gunshot(0.36, 1700.0, 120.0, 1.1, 12)
		"rifle_player": return _gunshot(0.42, 3200.0, 140.0, 1.25, 13)
		"autocannon": return _gunshot(0.55, 1400.0, 80.0, 1.6, 14)
		"cannon_heavy": return _boom(3.6, 38.0, 1.0, 21, 0.5)
		"cannon_medium": return _boom(2.2, 60.0, 0.8, 22, 0.35)
		"explosion": return _boom(3.0, 45.0, 1.0, 31, 1.0)
		"explosion_far": return _lowpass(_boom(4.0, 30.0, 0.9, 32, 0.6), 400.0)
		"thunder": return _thunder()
		"rocket": return _rocket()
		"impact_dirt": return _impact(0.18, 900.0, 41)
		"impact_metal": return _ping(0.35, 1900.0, 42)
		"whizz": return _whizz()
		"footstep_grass": return _step(0.12, 1800.0, 51)
		"footstep_hard": return _step(0.09, 3200.0, 52)
		"reload": return _reload()
		"dry": return _click(0.05, 2400.0, 61)
		"ui": return _click(0.04, 1200.0, 62)
		"grenade_pin": return _ping(0.15, 3400.0, 63)
		"tree_fall": return _tree_fall()
		"loop_rotor": return _rotor()
		"loop_crawler": return _engine(4.0, 34.0, 0.6, 71)
		"loop_truck": return _engine(4.0, 52.0, 0.5, 72)
		"loop_fans": return _fans()
		"loop_frigate": return _hum()
		"loop_wind": return _wind()
		"loop_rain": return _rain()
		"loop_sea": return _sea()
		"loop_birds": return _birds()
		"loop_crickets": return _crickets()
		"loop_battle_far": return _battle_far()
		"loop_city": return _city()
		"music_capital": return _music()
	return PackedFloat32Array()


# ------------------------------------------------------------------------------------------- building blocks

static func _buf(secs: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(secs * RATE))
	return b


## One-pole low-pass in place.
static func _lowpass(b: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	for i in b.size():
		y += a * (b[i] - y)
		b[i] = y
	return b


static func _highpass(b: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var lp := 0.0
	for i in b.size():
		lp += a * (b[i] - lp)
		b[i] = b[i] - lp
	return b


static func _normalize(b: PackedFloat32Array, peak: float = 0.95) -> PackedFloat32Array:
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in b.size():
		b[i] *= k
	return b


## Crossfades the end of a buffer into its start so it loops seamlessly.
static func _loopify(b: PackedFloat32Array, fade: float = 0.25) -> PackedFloat32Array:
	var n := int(fade * RATE)
	var size := b.size()
	var out := b.slice(0, size - n)
	for i in n:
		var t := float(i) / n
		out[i] = b[i] * t + b[size - n + i] * (1.0 - t)
	return out


static func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


# ------------------------------------------------------------------------------------------------- weapons

## A rifle report: a sharp supersonic crack (bright noise burst), a muzzle body thump (low sine), a short
## room-less tail of filtered noise (outdoor reflections).
static func _gunshot(secs: float, bright: float, body_hz: float, weight: float, seed: int) -> PackedFloat32Array:
	var r := _rng(seed)
	var b := _buf(secs)
	var lp := 0.0
	var lp2 := 0.0
	var a1 := 1.0 - exp(-TAU * bright / RATE)
	var a2 := 1.0 - exp(-TAU * 500.0 / RATE)
	for i in b.size():
		var t := float(i) / RATE
		var n := r.randf_range(-1.0, 1.0)
		lp += a1 * (n - lp)
		lp2 += a2 * (n - lp2)
		var crack := lp * exp(-t * 90.0) * 1.4
		var body := sin(TAU * body_hz * t * (1.0 - t * 1.5)) * exp(-t * 28.0) * weight
		var tail := lp2 * exp(-t * 9.0) * 0.5 * weight
		b[i] = crack + body + tail
	return _normalize(b)


## A big gun or a blast: an initial pressure kick, a deep decaying rumble, crackling debris.
static func _boom(secs: float, base_hz: float, weight: float, seed: int, crackle: float) -> PackedFloat32Array:
	var r := _rng(seed)
	var b := _buf(secs)
	var lp := 0.0
	var lp_slow := 0.0
	var a := 1.0 - exp(-TAU * 900.0 / RATE)
	var a_slow := 1.0 - exp(-TAU * 120.0 / RATE)
	var burst := 0.0          # falling debris: short decaying noise bursts, not single-sample clicks
	for i in b.size():
		var t := float(i) / RATE
		var n := r.randf_range(-1.0, 1.0)
		lp += a * (n - lp)
		lp_slow += a_slow * (n - lp_slow)
		var kick := sin(TAU * base_hz * 1.6 * t) * exp(-t * 14.0) * 1.0
		var rumble := lp_slow * 7.0 * exp(-t * 1.3) * weight
		var body := sin(TAU * base_hz * t + sin(TAU * 7.0 * t) * 2.0) * exp(-t * 2.8) * 0.9 * weight
		var crack := lp * exp(-t * 26.0) * 1.1
		if crackle > 0.0 and t > 0.2 and r.randf() < 0.0012 * exp(-t * 1.0) * crackle:
			burst = r.randf_range(0.15, 0.35) * exp(-t * 0.8)
		burst *= 0.9965
		b[i] = kick + rumble + body + crack + lp * burst * 3.0
	return _normalize(_lowpass(b, 6000.0))


static func _thunder() -> PackedFloat32Array:
	var r := _rng(81)
	var b := _buf(6.0)
	var lp := 0.0
	var a := 1.0 - exp(-TAU * 160.0 / RATE)
	for i in b.size():
		var t := float(i) / RATE
		var n := r.randf_range(-1.0, 1.0)
		lp += a * (n - lp)
		var env := (1.0 - exp(-t * 8.0)) * exp(-t * 0.7) * (0.6 + 0.4 * sin(t * 5.0 + sin(t * 1.7) * 3.0))
		b[i] = lp * env * 5.0
	return _normalize(b)


static func _rocket() -> PackedFloat32Array:
	var r := _rng(91)
	var b := _buf(1.6)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var cut := 800.0 + 2500.0 * exp(-t * 3.0)
		var a := 1.0 - exp(-TAU * cut / RATE)
		lp += a * (r.randf_range(-1.0, 1.0) - lp)
		var env := minf(t * 40.0, 1.0) * exp(-t * 1.3)
		b[i] = lp * env + sin(TAU * 90.0 * t) * exp(-t * 20.0) * 0.6
	return _normalize(b)


static func _impact(secs: float, cut: float, seed: int) -> PackedFloat32Array:
	var r := _rng(seed)
	var b := _buf(secs)
	var lp := 0.0
	var a := 1.0 - exp(-TAU * cut / RATE)
	for i in b.size():
		var t := float(i) / RATE
		lp += a * (r.randf_range(-1.0, 1.0) - lp)
		b[i] = lp * exp(-t * 35.0)
	return _normalize(b, 0.8)


## A tree pushed over: a splintering crack, a swelling rush of leaves as it falls, and a low thud at 1.9 s.
static func _tree_fall() -> PackedFloat32Array:
	var r := _rng(81)
	var b := _buf(2.6)
	var lp := 0.0
	var lp2 := 0.0
	var a_hi := 1.0 - exp(-TAU * 2600.0 / RATE)
	var a_lo := 1.0 - exp(-TAU * 900.0 / RATE)
	for i in b.size():
		var t := float(i) / RATE
		var n := r.randf_range(-1.0, 1.0)
		# Crack: three splinter bursts in the first 0.3 s.
		var crack := 0.0
		for c in 3:
			var tc := t - c * 0.09
			if tc > 0.0:
				crack += exp(-tc * 60.0) * (1.0 - c * 0.25)
		lp += a_hi * (n - lp)
		# Leaves: band noise rising as the crown speeds up, cut at the landing.
		lp2 += a_lo * (n - lp2)
		var rush := smoothstep(0.2, 1.8, t) * (1.0 - smoothstep(1.85, 2.1, t))
		# Landing thud.
		var tl := t - 1.9
		var thud := 0.0
		if tl > 0.0:
			thud = sin(TAU * 52.0 * tl) * exp(-tl * 9.0) * 1.4 + lp2 * exp(-tl * 6.0)
		b[i] = lp * crack * 1.2 + (n - lp2) * rush * 0.35 + thud
	return _normalize(b, 0.85)


static func _ping(secs: float, hz: float, seed: int) -> PackedFloat32Array:
	var r := _rng(seed)
	var b := _buf(secs)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (sin(TAU * hz * t) * 0.6 + sin(TAU * hz * 2.76 * t) * 0.3 + r.randf_range(-1, 1) * exp(-t * 200.0)) * exp(-t * 18.0)
	return _normalize(b, 0.7)


static func _whizz() -> PackedFloat32Array:
	var r := _rng(93)
	var b := _buf(0.35)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var a := 1.0 - exp(-TAU * (1500.0 + 3000.0 * (1.0 - t / 0.35)) / RATE)
		lp += a * (r.randf_range(-1.0, 1.0) - lp)
		var env := sin(PI * t / 0.35)
		b[i] = lp * env * env
	return _normalize(b, 0.6)


static func _step(secs: float, cut: float, seed: int) -> PackedFloat32Array:
	var r := _rng(seed)
	var b := _buf(secs)
	var lp := 0.0
	var a := 1.0 - exp(-TAU * cut / RATE)
	for i in b.size():
		var t := float(i) / RATE
		lp += a * (r.randf_range(-1.0, 1.0) - lp)
		b[i] = lp * exp(-t * 40.0) + sin(TAU * 70.0 * t) * exp(-t * 60.0) * 0.4
	return _normalize(b, 0.5)


static func _click(secs: float, hz: float, seed: int) -> PackedFloat32Array:
	var r := _rng(seed)
	var b := _buf(secs)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (r.randf_range(-1, 1) * 0.5 + sin(TAU * hz * t)) * exp(-t * 120.0)
	return _normalize(b, 0.6)


static func _reload() -> PackedFloat32Array:
	var b := _buf(1.1)
	for ev in [[0.05, 1800.0], [0.35, 900.0], [0.75, 2600.0], [0.85, 1400.0]]:
		var c := _click(0.08, ev[1], int(ev[1]))
		var o := int(float(ev[0]) * RATE)
		for i in c.size():
			if o + i < b.size():
				b[o + i] += c[i]
	return _normalize(b, 0.6)


# --------------------------------------------------------------------------------------------------- loops

## Helicopter: blade slap pulses at the blade-pass frequency over turbine whine and wash.
static func _rotor() -> PackedFloat32Array:
	var r := _rng(101)
	var b := _buf(2.25)
	var lp := 0.0
	var a := 1.0 - exp(-TAU * 400.0 / RATE)
	var bpf := 1.0 / 0.0625                      # 16 Hz blade pass
	for i in b.size():
		var t := float(i) / RATE
		lp += a * (r.randf_range(-1.0, 1.0) - lp)
		var ph := fmod(t * bpf, 1.0)
		var slap := exp(-ph * 22.0) * 1.6
		var whine := sin(TAU * 1180.0 * t) * 0.05 + sin(TAU * 2360.0 * t) * 0.02
		b[i] = lp * (0.6 + slap) + whine
	return _normalize(_loopify(b, 0.25), 0.8)


static func _engine(secs: float, hz: float, rough: float, seed: int) -> PackedFloat32Array:
	var r := _rng(seed)
	var b := _buf(secs)
	var lp := 0.0
	var a := 1.0 - exp(-TAU * 300.0 / RATE)
	for i in b.size():
		var t := float(i) / RATE
		lp += a * (r.randf_range(-1.0, 1.0) - lp)
		var f := hz * (1.0 + 0.01 * sin(TAU * 0.7 * t))
		var firing := pow(maxf(sin(TAU * f * t), 0.0), 6.0)
		b[i] = firing * 0.8 + sin(TAU * f * 0.5 * t) * 0.35 + lp * rough * 1.5 + sin(TAU * 620.0 * t) * 0.03
	return _normalize(_loopify(_lowpass(b, 2500.0), 0.3), 0.8)


static func _fans() -> PackedFloat32Array:
	var r := _rng(111)
	var b := _buf(3.0)
	var lp := 0.0
	var a := 1.0 - exp(-TAU * 1400.0 / RATE)
	for i in b.size():
		var t := float(i) / RATE
		lp += a * (r.randf_range(-1.0, 1.0) - lp)
		b[i] = lp * 0.9 + sin(TAU * 410.0 * t) * 0.12 + sin(TAU * 823.0 * t) * 0.08 + sin(TAU * 52.0 * t) * 0.2
	return _normalize(_loopify(b, 0.3), 0.7)


static func _hum() -> PackedFloat32Array:
	var b := _buf(4.0)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * 41.0 * t) * 0.6 + sin(TAU * 82.3 * t) * 0.3 + sin(TAU * 123.0 * t) * 0.15 * (0.8 + 0.2 * sin(TAU * 0.25 * t))
	return _normalize(b, 0.7)


static func _wind() -> PackedFloat32Array:
	var r := _rng(121)
	var b := _buf(8.0)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var gust := 0.5 + 0.5 * sin(TAU * 0.11 * t) * sin(TAU * 0.23 * t + 1.0)
		var cut := 250.0 + gust * 700.0
		var a := 1.0 - exp(-TAU * cut / RATE)
		lp += a * (r.randf_range(-1.0, 1.0) - lp)
		lp2 += 0.02 * (lp - lp2)
		b[i] = (lp - lp2) * (0.4 + gust)
	return _normalize(_loopify(b, 1.0), 0.6)


static func _rain() -> PackedFloat32Array:
	var r := _rng(131)
	var b := _buf(4.0)
	var lp := 0.0
	for i in b.size():
		lp += 0.35 * (r.randf_range(-1.0, 1.0) - lp)
		var drop := 0.0
		if r.randf() < 0.003:
			drop = r.randf_range(0.5, 1.0)
		b[i] = lp * 0.5 + drop
	return _normalize(_loopify(_highpass(b, 400.0), 0.5), 0.6)


static func _sea() -> PackedFloat32Array:
	var r := _rng(141)
	var b := _buf(10.0)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var swell := pow(0.5 + 0.5 * sin(TAU * t / 5.0), 2.0)
		var a := 1.0 - exp(-TAU * (300.0 + swell * 900.0) / RATE)
		lp += a * (r.randf_range(-1.0, 1.0) - lp)
		b[i] = lp * (0.25 + swell)
	return _normalize(_loopify(b, 1.0), 0.6)


static func _birds() -> PackedFloat32Array:
	var r := _rng(151)
	var b := _buf(12.0)
	var t0 := 0.3
	while t0 < 11.0:
		var notes := r.randi_range(2, 6)
		var f0 := r.randf_range(2400.0, 4200.0)
		for nn in notes:
			var start := int((t0 + nn * 0.11) * RATE)
			var dur := int(r.randf_range(0.05, 0.09) * RATE)
			var f := f0 * r.randf_range(0.85, 1.2)
			for i in dur:
				if start + i >= b.size():
					break
				var t := float(i) / RATE
				var env := sin(PI * float(i) / dur)
				b[start + i] += sin(TAU * (f + 900.0 * sin(TAU * 18.0 * t)) * t) * env * 0.3
		t0 += r.randf_range(0.6, 2.2)
	return _normalize(b, 0.5)


static func _crickets() -> PackedFloat32Array:
	var b := _buf(6.0)
	for i in b.size():
		var t := float(i) / RATE
		var chirp := pow(maxf(sin(TAU * 2.8 * t), 0.0), 8.0) * (0.5 + 0.5 * sin(TAU * 45.0 * t))
		b[i] = sin(TAU * 4300.0 * t) * chirp * 0.4 + sin(TAU * 3950.0 * t + 1.0) * pow(maxf(sin(TAU * 2.1 * t + 2.0), 0.0), 8.0) * 0.25
	return _normalize(b, 0.4)


## Distant battle: low rolling booms and faint crackle of small arms, lowpassed by distance.
static func _battle_far() -> PackedFloat32Array:
	var r := _rng(161)
	var b := _buf(16.0)
	var t0 := 0.2
	while t0 < 15.0:
		var kind := r.randf()
		var start := int(t0 * RATE)
		if kind < 0.25:
			var e := _boom(2.0, 30.0, 0.8, 300 + int(t0 * 10), 0.3)
			for i in e.size():
				if start + i < b.size():
					b[start + i] += e[i] * 0.5
			t0 += r.randf_range(1.0, 3.0)
		else:
			for k in r.randi_range(3, 9):
				var s := start + int(k * 0.09 * RATE)
				for i in 600:
					if s + i < b.size():
						b[s + i] += r.randf_range(-1, 1) * exp(-float(i) / 120.0) * 0.25
			t0 += r.randf_range(0.3, 1.2)
	return _normalize(_loopify(_lowpass(b, 900.0), 0.5), 0.6)


static func _city() -> PackedFloat32Array:
	var r := _rng(171)
	var b := _buf(10.0)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += 0.03 * (r.randf_range(-1.0, 1.0) - lp)
		b[i] = lp * 2.0 + sin(TAU * 110.0 * t) * 0.04 * (0.5 + 0.5 * sin(TAU * 0.05 * t))
	return _normalize(_loopify(b, 1.0), 0.4)


## The Capital's theme: slow, solemn open-fifth pads over a low pulse, in a minor mode (original).
static func _music() -> PackedFloat32Array:
	var secs := 32.0
	var b := _buf(secs)
	var roots := [55.0, 51.91, 48.99, 51.91]      # A1, G#1/Ab, G1, Ab: a falling, stern progression
	for i in b.size():
		var t := float(i) / RATE
		var bar := int(t / 8.0) % 4
		var tb := fmod(t, 8.0)
		var f: float = roots[bar]
		var env := minf(tb / 2.5, 1.0) * minf((8.0 - tb) / 2.0, 1.0)
		var pad := 0.0
		for h in [1.0, 1.5, 2.0, 3.0, 4.0]:
			pad += sin(TAU * f * h * t + sin(TAU * 0.3 * t) * 0.3) / h
		var pulse := sin(TAU * f * t) * exp(-fmod(t, 2.0) * 3.0) * 0.6
		var bell := 0.0
		if fmod(t, 8.0) > 4.0:
			var tt := fmod(t, 8.0) - 4.0
			bell = sin(TAU * f * 6.0 * t) * exp(-tt * 1.4) * 0.15
		b[i] = pad * env * 0.25 + pulse * 0.2 + bell
	return _normalize(_lowpass(b, 3000.0), 0.5)
