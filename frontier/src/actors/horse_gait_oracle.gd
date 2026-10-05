class_name HorseGaitOracle
extends RefCounted
## Gait oracle: records hoof ground contacts, extracts footfall onsets per leg, groups them into beats and checks
## the beat count and order against the reference footfall table; also measures foot slide (cm of hoof travel
## along the ground per stance). Works on the bare animation (model space, in-place cycle moving the ground back
## at the authored speed) or on a horse moving in the world (samples from the controller).

const REF := {
	"walk": [["LH"], ["LF"], ["RH"], ["RF"]],            # 4-beat lateral sequence
	"trot": [["LH", "RF"], ["LF", "RH"]],                # 2-beat diagonal
	"canter": [["RH"], ["LH", "RF"], ["LF"]],            # 3-beat (left lead)
	"canter_r": [["LH"], ["LF", "RH"], ["RF"]],
	"gallop": [["RH"], ["LH"], ["RF"], ["LF"]],          # 4-beat transverse (left lead)
	"gallop_r": [["LH"], ["RH"], ["LF"], ["RF"]],
}
## Reference footfall sequences by gait TYPE (written per gait into <species>_gaits.json by the generator), so
## one oracle checks the horse and every wildlife species: rotary gallops for canids/felids/bears, the half-bound
## of rabbits, the pronk/stot of mule deer.
const REF_TYPES := {
	"walk_lateral": [["LH"], ["LF"], ["RH"], ["RF"]],
	"trot_diagonal": [["LH", "RF"], ["LF", "RH"]],
	"canter": [["RH"], ["LH", "RF"], ["LF"]],
	"gallop_transverse": [["RH"], ["LH"], ["RF"], ["LF"]],
	"gallop_rotary": [["RH"], ["LH"], ["LF"], ["RF"]],
	"bound": [["LF"], ["RF"], ["LH", "RH"]],
	"pronk": [["LF", "LH", "RF", "RH"]],
}
const LEGS := ["LF", "RF", "LH", "RH"]
const CONTACT_H := 0.03
const BEAT_TOL := 0.07

## Animation-only analysis: sample the gait cycle twice in model space.
static func analyse_animation(v: HorseVisual, gait: String, steps := 240) -> Dictionary:
	var ap := v.anim_player
	if ap == null or not ap.has_animation(gait):
		return {"ok": false, "why": "no animation"}
	if v.tree:
		v.tree.active = false
	if v.ik:
		v.ik.enabled = false
	var info := v.gait_info(gait)
	var L: float = ap.get_animation(gait).length
	var speed: float = info.get("speed", 0.0)
	ap.play(gait)
	var samples := []
	for i in steps * 2:
		var t := L * 2.0 * float(i) / float(steps * 2)
		ap.seek(fmod(t, L), true)
		var s := {"t": t, "pos": {}, "ground": {}}
		for leg in LEGS:
			var hb := v.hoof_bone(leg)
			var p := v.skeleton.get_bone_global_pose(hb) * v.sole_local(leg)
			# in-place: the ground moves backward (+Z in model space) at the authored speed
			s.pos[leg] = Vector3(p.x, p.y, p.z - speed * t)
			s.ground[leg] = 0.0
		samples.append(s)
		if Game.args.has("oracle_debug") and i % 12 == 0:
			print("  t=%.3f LF %s  LH %s" % [t, str(s.pos["LF"]), str(s.pos["LH"])])
	ap.stop()
	if v.tree:
		v.tree.active = true
	if v.ik:
		v.ik.enabled = true
	return analyse_samples(samples, gait, L, str(info.get("type", "")), v.size_scale)

## samples: [{t, pos: {leg: Vector3 world/model}, ground: {leg: float}}]; cycle: expected period (s) or 0.
static func analyse_samples(samples: Array, gait: String, cycle := 0.0, gait_type := "", size := 1.0) -> Dictionary:
	var contact_h := maxf(CONTACT_H * clampf(size, 0.2, 1.5), 0.012)
	var planted_h := maxf(0.012 * clampf(size, 0.2, 1.5), 0.005)
	var onsets := {}
	var slides := []
	var contact_frac := {}
	var min_len := maxf(cycle * 0.06, minf(0.04, cycle * 0.1)) if cycle > 0.0 else 0.05   # short cycles: short stances
	for leg in LEGS:
		onsets[leg] = []
		# contact segments (h < CONTACT_H), debounced: short dips/lifts are ignored
		var segs := []
		var cur := []
		for s in samples:
			var p: Vector3 = s.pos[leg]
			var h: float = p.y - float(s.ground[leg])
			if h < contact_h:
				cur.append([float(s.t), p, h])
			elif cur.size() > 0:
				segs.append(cur)
				cur = []
		if cur.size() > 0:
			segs.append(cur)
		var n_c := 0
		for seg in segs:
			var t0: float = seg[0][0]
			var t1: float = seg[seg.size() - 1][0]
			if t1 - t0 < min_len:
				continue
			n_c += seg.size()
			if seg[0][0] > float(samples[0].t) + 1e-6:
				onsets[leg].append(t0)
			# slide: horizontal drift while planted (h < 1.2 cm, i.e. bearing weight)
			var anchor = null
			var worst := 0.0
			for e in seg:
				if e[2] < planted_h:
					var p: Vector3 = e[1]
					if anchor == null:
						anchor = p
					worst = maxf(worst, Vector2(p.x - anchor.x, p.z - anchor.z).length())
			if anchor != null and seg[seg.size() - 1][0] < float(samples[samples.size() - 1].t) - 1e-6:
				slides.append(worst)
		contact_frac[leg] = float(n_c) / maxf(samples.size(), 1)
	# period: median interval between onsets of the same leg
	var ints := []
	for leg in LEGS:
		var o: Array = onsets[leg]
		for i in range(1, o.size()):
			ints.append(o[i] - o[i - 1])
	ints.sort()
	var T := cycle
	if ints.size() > 0:
		T = ints[ints.size() / 2]
	var res := {"ok": true, "gait": gait, "period": T, "failures": [], "contact": contact_frac}
	var ref: Array = REF_TYPES.get(gait_type, REF.get(gait, []))
	res.type = gait_type
	if T <= 0.0 or ref.is_empty():
		res.ok = false
		res.failures.append("no periodic contacts")
		return res
	var lead: String = ref[0][0]
	if (onsets[lead] as Array).is_empty():
		res.ok = false
		res.failures.append("lead leg %s never lands" % lead)
		return res
	# phase of each leg relative to the lead leg: circular mean over every onset (robust to a stray contact)
	var lead_on: Array = onsets[lead]
	var ph := {}
	for leg in LEGS:
		var sx := 0.0
		var sy := 0.0
		var nn := 0
		for t in onsets[leg]:
			# nearest lead onset (either side: the phase is taken modulo T, and a leg that lands with the lead can
			# cross the contact height a sample earlier than the lead's first counted onset)
			var t0 := -INF
			for tl in lead_on:
				if t0 == -INF or absf(tl - t) < absf(t0 - t):
					t0 = tl
			if t0 == -INF:
				continue
			var a := TAU * fposmod(t - t0, T) / T
			sx += cos(a)
			sy += sin(a)
			nn += 1
		ph[leg] = fposmod(atan2(sy, sx), TAU) / TAU if nn > 0 else -1.0
		if leg == lead:
			ph[leg] = 0.0
	res.phases = ph
	var beats := group_beats(ph)
	res.beats = beats
	res.beat_count = beats.size()
	var want := []
	for b in ref:
		var bb: Array = b.duplicate()
		bb.sort()
		want.append(bb)
	if beats != want:
		res.ok = false
		res.failures.append("footfalls %s, expected %s" % [str(beats), str(want)])
	slides.sort()
	var tot := 0.0
	for d in slides:
		tot += d
	res.slide_cm_avg = 100.0 * tot / maxf(slides.size(), 1)
	res.slide_cm_max = 100.0 * (slides[slides.size() - 1] if slides.size() > 0 else 0.0)
	res.stances = slides.size()
	return res

static func group_beats(ph: Dictionary) -> Array:
	var items := []
	for leg in ph:
		if ph[leg] >= 0.0:
			items.append([ph[leg], leg])
	items.sort_custom(func(a, b): return a[0] < b[0])
	var beats := []
	var last := -10.0
	for it in items:
		if beats.size() > 0 and it[0] - last <= BEAT_TOL:
			beats[beats.size() - 1].append(it[1])
		else:
			beats.append([it[1]])
		last = it[0]
	if beats.size() > 1 and (1.0 - last + items[0][0]) <= BEAT_TOL:
		var tail: Array = beats.pop_back()
		beats[0].append_array(tail)
	for b in beats:
		b.sort()
	return beats

static func format_line(gait: String, r: Dictionary) -> String:
	if not r.has("beats"):
		return "GAIT %s: FAIL %s" % [gait, str(r.get("failures", r.get("why", "")))]
	var order := []
	for b in r.beats:
		order.append("+".join(b))
	return "GAIT %-7s %s  beats=%d  order=%s  period=%.2fs  slide=%.1f cm/stance (max %.1f, %d stances)%s" % [gait,
		"PASS" if r.ok else "FAIL", r.beat_count, " ".join(order), r.period, r.slide_cm_avg, r.slide_cm_max, r.stances,
		"" if r.ok else "  " + str(r.failures)]
