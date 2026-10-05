extends Node
## World reactivity, part one: talking to people without a gun in your hand, and people talking about the world.
##
## Social interaction (aim-free) with the townsperson in front of Ruth (within reach, roughly facing):
##   Greet (interact, E / Y)   — the existing greeting bark, then a follow-up by voice and Standing band, or gossip.
##   Antagonize (T / D-pad right) — insult, then a shove, then they draw (armed and brave, or a lawman) or run.
##   Defuse (N / D-pad down, on foot) — calms someone Ruth has riled; a drawn man stands down unless Ruth is wanted
##   or low (then it's too late for sorry). Standing moves a little either way.
## Lines come from design/dialogue/social.json pools: kind -> voice (town, rough, woman, law, child) -> band (high,
## mid, low, wanted), with fallbacks, so the same man answers an honourable Ruth differently from a wanted one.
##
## Gossip and reactive barks: rules in social.json "gossip", each with conditions on story flags and completed
## missions, crimes (robberies, a store's own robberies), kills, bounty/wanted, Standing, weather and the hour, and
## who may say it (lawman, shop, town id). People Ruth walks past speak now and then; lawmen eye a wanted Ruth;
## shop counters greet her by her record. Population/brain can call `Game.get_meta("social").npc_bark(h)` (when Game.has_meta("social")) at their own bark
## points (one call, additive).

const TABLE := "res://design/dialogue/social.json"
const REACH := 4.0
const AMBIENT_R := 6.0
const GLOBAL_GAP := 14.0        # seconds between ambient barks
const NPC_GAP := 120.0          # seconds before the same person speaks again
const SHOP_GAP := 150.0

var pools := {}
var gossip: Array = []
var lines := {}
var rng := RandomNumberGenerator.new()
var anger := {}                 # instance id -> 0..3 (3 = drew or ran)
var _last_bark := -100.0
var _npc_t := {}                # instance id -> time of last bark
var _shop_t := {}
var _recent: Array = []         # gossip ids said lately (not repeated soon)
var _t := 0.0
var _hint: Label
var _target: Node = null
var _greet_pending := {}        # instance id -> time to say the follow-up

func _ready() -> void:
	Game.set_meta("social", self)
	rng.seed = 1899 * 7
	_load()
	_actions()
	if not Game.headless:
		var cl := CanvasLayer.new()
		cl.layer = 5
		add_child(cl)
		_hint = Label.new()
		_hint.add_theme_font_override("font", UITheme.font("caps"))
		_hint.add_theme_font_size_override("font_size", 22)
		_hint.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
		_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		_hint.anchor_left = 0.5
		_hint.anchor_right = 0.5
		_hint.anchor_top = 1.0
		_hint.anchor_bottom = 1.0
		_hint.offset_left = -300
		_hint.offset_right = 300
		_hint.offset_top = -150
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.add_child(_hint)

func _load() -> void:
	if Game.missions:
		Game.missions._load_dialogue(TABLE)
	var f := FileAccess.open(TABLE, FileAccess.READ)
	if f == null:
		return
	var j = JSON.parse_string(f.get_as_text())
	if typeof(j) != TYPE_DICTIONARY:
		return
	pools = j.get("social", {})
	gossip = j.get("gossip", [])
	for l in j.get("lines", []):
		lines[l.id] = l

func _actions() -> void:
	for a in [["antagonize", KEY_T, JOY_BUTTON_DPAD_RIGHT], ["defuse", KEY_N, JOY_BUTTON_DPAD_DOWN]]:
		if InputMap.has_action(a[0]):
			continue
		InputMap.add_action(a[0])
		var k := InputEventKey.new()
		k.physical_keycode = a[1]
		InputMap.action_add_event(a[0], k)
		var b := InputEventJoypadButton.new()
		b.button_index = a[2]
		InputMap.action_add_event(a[0], b)

# ------------------------------------------------------------------ who's talking
static func voice_of(h: Node) -> String:
	var role := str(h.get("role"))
	if role == "lawman" or str(h.get("faction")) == "law":
		return "law"
	if role in ["lady", "woman"]:
		return "woman"
	if role == "child":
		return "child"
	if role in ["drunk", "worker", "rancher", "gunman", "drover", "traveller", "prospector", "hunter", "wagoner", "cowhand"]:
		return "rough"
	return "town"

## Does this person carry a gun? (GunHandler always lists the default pair, so look at the visible holster or the
## roles the population arms.)
const ARMED_ROLES := ["lawman", "rancher", "gambler", "gunman", "hunter", "drover", "cowhand"]
static func is_armed(h: Node) -> bool:
	return h.get("holder") != null or str(h.get("role")) in ARMED_ROLES

## Ruth's standing band as people see it: wanted beats everything; then high / low / mid.
static func band() -> String:
	var st = Game.state
	if st == null:
		return "mid"
	var bounty := 0.0
	for k in st.bounties:
		bounty += float(st.bounties[k])
	if int(st.wanted) > 0 or bounty >= 25.0:
		return "wanted"
	if st.standing >= 25.0:
		return "high"
	if st.standing <= -15.0:
		return "low"
	return "mid"

## A line id for kind/voice/band with fallbacks (band "wanted" falls back to "low", then "mid"; voice to "town").
func pick(kind: String, voice: String, b: String) -> String:
	var kp: Dictionary = pools.get(kind, {})
	var bands := [b]
	if b == "wanted":
		bands.append("low")
	bands.append("mid")
	for v in [voice, "town", "rough"]:
		var vp: Dictionary = kp.get(v, {})
		for bb in bands:
			var l: Array = vp.get(bb, [])
			if not l.is_empty():
				return l[rng.randi() % l.size()]
		if not vp.is_empty():
			var any: Array = vp.values()[0]
			if not any.is_empty():
				return any[rng.randi() % any.size()]
	return ""

## Speak a line as a person (subtitle with their own name, voice if rendered, logged like mission lines).
func speak(who: Node, line_id: String) -> float:
	if line_id == "":
		return 0.0
	var l: Dictionary = lines.get(line_id, Game.missions.dialogue.get(line_id, {}) if Game.missions else {})
	var text := str(l.get("line", line_id))
	var dur := clampf(text.length() * 0.065 + 0.6, 1.4, 7.0)
	var name := "Ruth Caddell"
	if who != null and who != Game.player:
		name = str(who.get("display_name"))
		if who is Human and Game.player:
			who.intent.face = Game.player.global_position - who.global_position
	if Game.audio and Game.audio.has_method("play_voice"):
		var d = Game.audio.play_voice(line_id, who)
		if typeof(d) == TYPE_FLOAT and d > 0.0:
			dur = d + 0.2
	if Game.hud:
		Game.hud.subtitle(name, text, dur)
	Game.log_event("say", {"id": line_id, "social": true})
	return dur

func _social_ok(h: Node) -> bool:
	return h != null and is_instance_valid(h) and h is Human and h.alive and h.brain != null \
		and str(h.faction) in ["civilian", "law"]

# ------------------------------------------------------------------ greet / antagonize / defuse
## Greet: the person's own greeting (Human.interact) and then a follow-up by voice and band, or a piece of gossip.
func greet(h: Node, immediate := false) -> String:
	if not _social_ok(h):
		return ""
	if immediate:
		h.interact(Game.player)
	var id := ""
	if rng.randf() < 0.45:
		id = gossip_for(h)
	if id == "":
		id = pick("greet", voice_of(h), band())
	if immediate:
		speak(h, id)
	else:
		_greet_pending[h.get_instance_id()] = {"t": Time.get_ticks_msec() + 1700, "id": id, "who": weakref(h)}
	Game.log_event("social", {"act": "greet", "npc": str(h.name), "line": id})
	return id

## Antagonize: each press escalates. Returns the step: "insult", "shove", "draw", "fists", "flee" ("" if nobody to rile).
func antagonize(h: Node) -> String:
	if not _social_ok(h) or str(h.role) == "child":
		return ""
	var k := h.get_instance_id()
	var a: int = anger.get(k, 0)
	var voice := voice_of(h)
	var b := band()
	var step := ""
	if a == 0:
		step = "insult"
		speak(Game.player, pick("r_insult", "ruth", "low" if b in ["low", "wanted"] else "mid"))
		speak(h, pick("insult", voice, b))
		_standing(-0.3, "insulted a stranger")
		if voice == "law":
			misdemeanour(h, "insulting an officer", 5.0)
	elif a == 1:
		step = "shove"
		speak(Game.player, pick("r_shove", "ruth", "mid"))
		var dir: Vector3 = h.global_position - Game.player.global_position
		dir.y = 0.0
		h.velocity += dir.normalized() * 4.5
		speak(h, pick("shove", voice, b))
		_standing(-0.6, "shoved a stranger")
		if voice == "law":
			misdemeanour(h, "laying hands on an officer", 10.0)
	else:
		var armed: bool = is_armed(h)
		var brave: bool = float(h.brain.bravery) >= 0.5 or voice == "law"
		if armed and brave:
			step = "draw"
			speak(h, pick("draw", voice, b))
			h.set_meta("provoked", true)
			h.brain.aggressive = true
			h.brain.share_target(Game.player)
			_standing(-1.0, "picked a gunfight")
		elif not armed and float(h.brain.bravery) >= 0.7 and voice in ["town", "rough"]:
			# an unarmed hard case puts his fists up instead of running (src/combat/melee.gd)
			step = "fists"
			var line := pick("fists", voice, b)
			speak(h, line if line != "" else pick("shove", voice, b))
			h.set_meta("provoked", true)
			h.brain.start_fistfight(Game.player)
			_standing(-0.6, "started a fistfight")
		else:
			step = "flee"
			speak(h, pick("flee", voice, b))
			h.brain.target = Game.player
			h.brain.target_last_seen = Game.player.global_position
			h.brain.state = h.brain.State.FLEE
			_standing(-0.5, "ran a man off")
	anger[k] = mini(a + 1, 3)
	Game.log_event("social", {"act": "antagonize", "npc": str(h.name), "step": step})
	return step

## Defuse: "calmed", "stood_down" (a drawn man holsters), "failed" (too late), or "" (nothing to calm).
func defuse(h: Node) -> String:
	if not _social_ok(h):
		return ""
	var k := h.get_instance_id()
	var a: int = anger.get(k, 0)
	var drawn: bool = h.has_meta("provoked") and h.brain.aggressive
	if a == 0 and not drawn:
		return ""
	var voice := voice_of(h)
	var b := band()
	var res := "calmed"
	speak(Game.player, pick("r_defuse", "ruth", "low" if drawn else "mid"))
	if drawn:
		var hurt: bool = h.damageable.health < h.damageable.max_health
		if b in ["low", "wanted"] or hurt:
			res = "failed"
			speak(h, pick("defuse_fail", voice, b))
		else:
			res = "stood_down"
			h.brain.aggressive = false
			h.brain.target = null
			h.brain.state = h.brain.State.ROUTINE
			h.gun.drawn = false
			h.intent.aim_at = null
			h.remove_meta("provoked")
			speak(h, pick("defuse_ok", voice, b))
			_standing(0.6, "talked a man out of a gunfight")
	else:
		speak(h, pick("defuse_ok", voice, b))
		_standing(0.2, "made amends")
	if res != "failed":
		anger.erase(k)
	Game.log_event("social", {"act": "defuse", "npc": str(h.name), "result": res})
	return res

## A misdemeanour against the law: a fine on the county's books (wanted level 1 until it's paid at any sheriff's
## board), logged as a crime. No witnesses needed: the officer is the witness.
func misdemeanour(h: Node, what: String, fine: float) -> void:
	var st = Game.state
	if st == null:
		return
	var county: String = st.county_at(h.global_position)
	st.bounties[county] = float(st.bounties.get(county, 0.0)) + fine
	st.crimes_log.append({"kind": "misdemeanour", "pos": [h.global_position.x, h.global_position.z], "t": Time.get_unix_time_from_system()})
	if st.wanted < 1:
		st.wanted = 1
		st.wanted_county = county
		st.wanted_changed.emit(1, county)
	st.wanted_t = maxf(st.wanted_t, 45.0)
	st.flags["fined_once"] = true
	Game.log_event("misdemeanour", {"what": what, "fine": fine, "county": county})
	if Game.hud:
		Game.hud.notice("Fined $%d for %s — pay it at any sheriff's board" % [int(fine), what], 4.0)

func _standing(d: float, why: String) -> void:
	if Game.state:
		Game.state.change_standing(d, why)

# ------------------------------------------------------------------ gossip
## The facts a speaker might know (one dictionary; bots build their own to test picks).
func context(h: Node = null, role := "") -> Dictionary:
	var st = Game.state
	var md = Game.missions
	var c := {"flags": st.flags if st else {}, "completed": md.completed if md else [], "wanted": int(st.wanted) if st else 0,
		"bounty": 0.0, "standing": float(st.standing) if st else 0.0, "kills": st.kills if st else {},
		"robberies": 0, "shop_robberies": 0, "weather": "", "hour": 12.0, "night": false, "role": role, "town": ""}
	if st:
		for k in st.bounties:
			c.bounty += float(st.bounties[k])
		for cr in st.crimes_log:
			if cr.kind == "robbery":
				c.robberies += 1
	if Game.sky:
		c.weather = str(SkySystem.Weather.keys()[Game.sky.weather])
		c.hour = float(Game.sky.hours)
		c.night = Game.sky.is_night()
	if h != null and is_instance_valid(h):
		if role == "":
			c.role = str(h.get("role"))
		if h.has_meta("home_town"):
			c.town = str(h.get_meta("home_town"))
		elif h.get("town_id") != null:
			c.town = str(h.get("town_id"))
		if st and h is Node3D:
			var p: Vector3 = h.global_position
			for cr in st.crimes_log:
				if cr.kind == "robbery" and Vector2(float(cr.pos[0]) - p.x, float(cr.pos[1]) - p.z).length() < 60.0:
					c.shop_robberies += 1
	return c

static func matches(when: Dictionary, who: Array, c: Dictionary) -> bool:
	if not who.is_empty():
		var ok := false
		for w in who:
			if w == c.role or w == c.town or (w == "shop" and c.role in ["shop", "shopkeeper"]):
				ok = true
		if not ok:
			return false
	for k in when.keys():
		var v = when[k]
		match k:
			"flag":
				for f in v.keys():
					if not c.flags.has(f) or c.flags[f] != v[f]:
						if not (typeof(v[f]) == TYPE_STRING and str(c.flags.get(f, "")) == v[f]):
							return false
			"flag_set":
				for f in v:
					if not c.flags.has(f):
						return false
			"completed":
				for m in v:
					if not c.completed.has(m):
						return false
			"not_completed":
				for m in v:
					if c.completed.has(m):
						return false
			"wanted_min":
				if c.wanted < int(v):
					return false
			"bounty_min":
				if c.bounty < float(v):
					return false
			"robberies_min":
				if c.robberies < int(v):
					return false
			"shop_robberies_min":
				if c.shop_robberies < int(v):
					return false
			"kills_civilian_min":
				if int(c.kills.get("civilian", 0)) < int(v):
					return false
			"kills_outlaw_min":
				if int(c.kills.get("outlaw", 0)) < int(v):
					return false
			"standing_min":
				if c.standing < float(v):
					return false
			"standing_max":
				if c.standing > float(v):
					return false
			"weather":
				if not (c.weather in v):
					return false
			"night":
				if bool(c.night) != bool(v):
					return false
			"hour_min":
				if c.hour < float(v):
					return false
			"hour_max":
				if c.hour > float(v):
					return false
	return true

## The best gossip line for a context: highest priority among matches, random among equals, not one said lately.
func pick_gossip(c: Dictionary, avoid_recent := true) -> String:
	var best := -1000
	var pool: Array = []
	for g in gossip:
		if avoid_recent and _recent.has(g.id):
			continue
		var who: Array = g.get("who", [])
		# lawman and shop lines are only theirs; everyone else's lines are for anyone but those two
		if who.is_empty() and c.role in ["lawman", "shop", "child"]:
			continue
		if not matches(g.get("when", {}), who, c):
			continue
		var p := int(g.get("priority", 1))
		if p > best:
			best = p
			pool = [g.id]
		elif p == best:
			pool.append(g.id)
	if pool.is_empty():
		return ""
	return pool[rng.randi() % pool.size()]

func gossip_for(h: Node) -> String:
	var role := "lawman" if voice_of(h) == "law" else ("child" if str(h.get("role")) == "child" else str(h.get("role")))
	if role == "shopkeeper":
		role = "shop"
	var id := pick_gossip(context(h, role))
	if id != "":
		_recent.append(id)
		if _recent.size() > 12:
			_recent.pop_front()
	return id

## Hook for population / brain bark points: let this person say something about the world (or nothing).
## Returns the line id said. Honours the global and per-person cooldowns.
func npc_bark(h: Node, force := false) -> String:
	if not _social_ok(h):
		return ""
	var now := Time.get_ticks_msec() / 1000.0
	var k := h.get_instance_id()
	if not force and (now - _last_bark < GLOBAL_GAP or now - float(_npc_t.get(k, -1000.0)) < NPC_GAP):
		return ""
	var id := gossip_for(h)
	if id == "":
		return ""
	_last_bark = now
	_npc_t[k] = now
	speak(h, id)
	Game.log_event("gossip", {"npc": str(h.name), "id": id})
	return id

func shop_bark(shop: Node, force := false) -> String:
	var now := Time.get_ticks_msec() / 1000.0
	var k := shop.get_instance_id()
	if not force and now - float(_shop_t.get(k, -1000.0)) < SHOP_GAP:
		return ""
	var c := context(shop, "shop")
	c.town = str(shop.get("town_id"))
	var id := pick_gossip(c, false)
	if id == "":
		return ""
	_shop_t[k] = now
	var l: Dictionary = lines.get(id, {})
	if Game.hud:
		Game.hud.subtitle("%s clerk" % str(shop.get("title")), str(l.get("line", "")), 4.0)
	Game.log_event("say", {"id": id, "social": true})
	Game.log_event("gossip", {"shop": str(shop.get("kind")), "id": id})
	return id

# ------------------------------------------------------------------ per frame: input, hint, ambient talk
func _process(dt: float) -> void:
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return
	_flush_greetings()
	var menus = Game.get("menus")
	var blocked: bool = (menus != null and not menus.stack.is_empty()) or (Game.missions != null and Game.missions.cine) \
		or p.get("on_horse") != null or p.get("busy") != null or bool(p.get("bot_driven"))
	_target = null if blocked else _find_target(p)
	if _hint:
		var txt := ""
		if _target != null:
			txt = "[T] Antagonize"
			if anger.get(_target.get_instance_id(), 0) > 0 or _target.has_meta("provoked"):
				txt += "     [N] Defuse"
		_hint.text = txt
	if _target != null:
		if Input.is_action_just_pressed("antagonize"):
			antagonize(_target)
		elif Input.is_action_just_pressed("defuse"):
			defuse(_target)
		elif Input.is_action_just_pressed("interact") and p.get("_interact_target") == _target and not _target.has_meta("held_up"):
			greet(_target)
	# provoked men who drew on her: defuse is allowed from further off
	_t -= dt
	if _t > 0.0 or blocked:
		return
	_t = 0.5
	_ambient(p)

func _flush_greetings() -> void:
	if _greet_pending.is_empty():
		return
	var now := Time.get_ticks_msec()
	for k in _greet_pending.keys():
		var e: Dictionary = _greet_pending[k]
		if now >= int(e.t):
			var h = e.who.get_ref()
			if h != null and is_instance_valid(h) and h.alive:
				speak(h, str(e.id))
			_greet_pending.erase(k)

func _find_target(p: Node3D) -> Node:
	var fwd := Vector3(-sin(p.facing), 0, -cos(p.facing))
	var best: Node = null
	var bd := REACH
	for h in get_tree().get_nodes_in_group("humans"):
		if not _social_ok(h):
			continue
		var to: Vector3 = h.global_position - p.global_position
		to.y = 0.0
		var d := to.length()
		if d < bd and (d < 1.2 or fwd.dot(to / maxf(d, 0.01)) > 0.45):
			bd = d
			best = h
	if best == null:
		# someone Ruth provoked, gun out, a little further off: still talk-downable
		for h in get_tree().get_nodes_in_group("humans"):
			if _social_ok(h) and h.has_meta("provoked") and h.global_position.distance_to(p.global_position) < 12.0:
				return h
	return best

func _ambient(p: Node3D) -> void:
	if Game.missions and Game.missions.active != null and Game.missions.objective != "" and Game.missions.cine:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_bark < GLOBAL_GAP:
		return
	var w := band()
	for h in get_tree().get_nodes_in_group("humans"):
		if not _social_ok(h) or h.brain.state not in [h.brain.State.IDLE, h.brain.State.ROUTINE]:
			continue
		var d: float = h.global_position.distance_to(p.global_position)
		var lawman_eye: bool = voice_of(h) == "law" and w == "wanted" and d < 16.0
		if d > AMBIENT_R and not lawman_eye:
			continue
		if lawman_eye:
			h.intent.face = p.global_position - h.global_position
		if npc_bark(h) != "":
			return
	for s in get_tree().get_nodes_in_group("interactable"):
		if s is Node3D and s.has_method("sell_all") and (s as Node3D).global_position.distance_to(p.global_position) < 3.5:
			if shop_bark(s) != "":
				_last_bark = now
				return
