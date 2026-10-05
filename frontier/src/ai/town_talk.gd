extends Node
## Ambient conversations between townspeople (design/dialogue/town.json, written by tools/town_dialogue.py).
## Every couple of seconds, near Ruth, a pair of residents settled close together (two at the bar rail, a table, a
## porch, two who stopped in the street) trade a 2-4 line exchange picked by place and by their voices: each line is
## voiced on the speaker (AudioDirector.play_voice; text-timed when the voice pack lacks it), the speaker talks with
## a gesture, both turn their heads to each other, the routine keeps them in place until it's done, and Ruth gets
## subtitles when she's within OVERHEAR m. One conversation at a time; ambient barks hold off meanwhile.

const TABLE := "res://design/dialogue/town.json"
const NEAR_RUTH := 26.0
const OVERHEAR := 8.0
const PAIR_R := 2.8

var pop: Node
var convos: Array = []
var text := {}                    # line id -> {speaker, line, emotion}
var active := {}                  # {conv, a: Human, b: Human, i, t_next}
var recent: Array = []
var rng := RandomNumberGenerator.new()
var _t := 0.0
var _cool := 4.0

func setup(p: Node) -> void:
	pop = p
	rng.randomize()
	if not FileAccess.file_exists(TABLE):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
	if typeof(d) != TYPE_DICTIONARY:
		return
	convos = d.get("conversations", [])
	for l in d.get("lines", []):
		text[l.id] = l

func _process(dt: float) -> void:
	if convos.is_empty() or pop == null:
		return
	if not active.is_empty():
		_run(dt)
		return
	_cool -= dt
	_t -= dt
	if _t > 0.0 or _cool > 0.0:
		return
	_t = 1.5
	_try_start()

static func _sex(voice: String) -> String:
	return "f" if voice.begins_with("woman") else "m"

func _place(h: Human) -> String:
	var rt = h.brain.routine
	if rt.phase == "chat":
		return "street"
	var st: String = rt.spot.get("type", "")
	if st == "bar_patron":
		return "bar"
	if st == "chair" and rt.spot.has("table"):
		return "table"
	if st in ["porch_sit", "bench"]:
		return "porch"
	return "street"

func _eligible(h: Human, running := false) -> bool:
	if not is_instance_valid(h) or not h.alive or h.lying or h.brain.state != h.brain.State.ROUTINE:
		return false
	var rt = h.brain.get("routine")
	if rt == null or not rt.phase in ["at", "chat"]:
		return false
	if rt.block.get("kind", "") in ["passout", "home", "work", "patrol", "play", "stagger", "piano", "school", "church"]:
		return false
	return running or rt.phase == "chat" or rt.dwell - rt.t > 12.0

func _try_start() -> void:
	var ref: Vector3 = pop.ref_pos()
	var cands: Array = []
	for k in pop.residents:
		var h: Human = pop.residents[k]
		if _eligible(h) and h.global_position.distance_to(ref) < NEAR_RUTH:
			cands.append(h)
	cands.shuffle()
	for i in cands.size():
		for j in range(i + 1, cands.size()):
			var a: Human = cands[i]
			var b: Human = cands[j]
			if a.global_position.distance_to(b.global_position) > PAIR_R:
				continue
			var place := _place(a)
			var conv := _pick(a, b, place)
			if conv.is_empty():
				conv = _pick(b, a, place)
				if conv.is_empty():
					continue
				var tmp := a
				a = b
				b = tmp
			_start(conv, a, b)
			return

func _pick(a: Human, b: Human, place: String) -> Dictionary:
	var va := str(a.get_meta("voice_type", "man_town"))
	var vb := str(b.get_meta("voice_type", "man_town"))
	var best: Array = []
	var exact: Array = []
	for c in convos:
		if recent.has(c.id) or not (c.places as Array).has(place):
			continue
		if _sex(c.a) != _sex(va) or _sex(c.b) != _sex(vb):
			continue
		best.append(c)
		if c.a == va and c.b == vb:
			exact.append(c)
	var pool := exact if not exact.is_empty() else best
	return pool[rng.randi() % pool.size()] if not pool.is_empty() else {}

func _start(conv: Dictionary, a: Human, b: Human) -> void:
	active = {"conv": conv, "a": a, "b": b, "i": 0, "t_next": 0.0, "speaker": null}
	recent.append(conv.id)
	if recent.size() > 10:
		recent.pop_front()
	# keep both where they are for the whole exchange
	var total := 0.0
	for l in conv.lines:
		total += _dur(str(l[1])) + 0.6
	for h in [a, b]:
		var rt = h.brain.routine
		rt.t = minf(rt.t, rt.dwell - total - 3.0)
		if rt.phase == "chat":
			rt.dwell = maxf(rt.dwell, rt.t + total + 2.0)
		if h.visual.has_method("look_at_node"):
			h.visual.look_at_node(b if h == a else a, 0.7)
	pop.stat("conversations", 1)
	pop._bark_until = Time.get_ticks_msec() * 0.001 + total + 2.0
	Game.log_event("town_talk", {"id": conv.id, "a": str(a.name), "b": str(b.name)})

func _dur(id: String) -> float:
	var d := 0.0
	if Game.audio and Game.audio.has_method("voice_duration"):
		d = float(Game.audio.voice_duration(id))
	if d <= 0.0:
		d = clampf(str(text.get(id, {}).get("line", "")).length() * 0.065 + 0.6, 1.4, 7.0)
	return d

func _run(dt: float) -> void:
	var a: Human = active.a
	var b: Human = active.b
	if not _eligible(a, true) or not _eligible(b, true) or a.global_position.distance_to(b.global_position) > PAIR_R + 1.0:
		_stop()
		return
	active.t_next -= dt
	if active.t_next > 0.0:
		return
	var conv: Dictionary = active.conv
	var i: int = active.i
	if i >= conv.lines.size():
		_stop()
		return
	var side: String = conv.lines[i][0]
	var id: String = conv.lines[i][1]
	var spk := a if side == "a" else b
	var lis := b if side == "a" else a
	var d := _dur(id)
	if Game.audio and Game.audio.has_method("play_voice"):
		var pd = Game.audio.play_voice(id, spk)
		if typeof(pd) == TYPE_FLOAT and pd > 0.0:
			d = pd
	# talk: the speaker gestures (standing) or turns and talks (seated); the listener watches
	var rt = spk.brain.routine
	if spk.visual.has_method("gesture") and not rt.seated:
		spk.visual.gesture(["talk_directions", "shrug", "talk_directions"][i % 3] if d > 2.4 else "shrug")
	spk.intent.face = lis.global_position - spk.global_position
	lis.intent.face = spk.global_position - lis.global_position
	if spk.visual.has_method("look_at_node"):
		spk.visual.look_at_node(lis, 0.75)
		lis.visual.look_at_node(spk, 0.75)
	var emo := str(text.get(id, {}).get("emotion", ""))
	if spk.visual.has_method("set_expression") and emo in ["amused", "warm"]:
		spk.visual.set_expression("smile", 0.5)
	if Game.player and spk.global_position.distance_to(Game.player.global_position) < OVERHEAR:
		if Game.hud and Game.hud.has_method("subtitle"):
			Game.hud.subtitle(spk.display_name, str(text.get(id, {}).get("line", "")), d)
		pop.stat("overheard", 1)
	pop.stat("convo_lines", 1)
	active.i = i + 1
	active.t_next = d + rng.randf_range(0.35, 0.8)

func _stop() -> void:
	for h in [active.get("a"), active.get("b")]:
		if h != null and is_instance_valid(h) and h.visual.has_method("set_expression"):
			h.visual.set_expression("smile", 0.0)
			h.intent.face = null
	active = {}
	_cool = rng.randf_range(5.0, 12.0)
