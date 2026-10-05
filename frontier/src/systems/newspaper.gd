extends Node
## Newspapers. Each town has a paper (the Lantern in Port Linden, the Courier in Bitter Spring, the Miners' Advocate
## in Coldwater, the Ocotillo Star in Mesquite Wells), sold for five cents at a newsstand beside the general store.
## A front page is built from design/dialogue/newspaper.json: stories whose conditions match the story flags,
## completed missions and the news log of Ruth's deeds (store robberies, bounties collected, gunfights in town —
## recorded here by `record()`), plus weather, market prices, advertisements and notices, dated on the story's
## calendar (autumn 1899 to spring 1900). The page is printed in the 1899 manner (Old Standard / IM Fell, rules,
## columns). `edition(context)` is pure, so bots check content for given flags.

const TABLE := "res://design/dialogue/newspaper.json"
const SOCIAL = preload("res://src/systems/social.gd")
const PRICE := 0.05
## The story's calendar: the first day of each chapter (chapter 7 = the epilogue).
const CHAPTER_DATE := {1: [1899, 10, 14], 2: [1899, 10, 30], 3: [1899, 11, 13], 4: [1899, 12, 4], 5: [1900, 1, 16],
	6: [1900, 2, 12], 7: [1900, 4, 9]}
const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
	"November", "December"]
const WEEKDAYS := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
const TOWN_NAMES := {"bitter_spring": "Bitter Spring", "port_linden": "Port Linden", "coldwater": "Coldwater",
	"mesquite_wells": "Mesquite Wells"}

var data := {}
var last_edition := {}
var _stands_done := false
var _stand_t := 1.0
var _shots := {}               # town -> [times]

func _ready() -> void:
	Game.set_meta("news", self)
	var f := FileAccess.open(TABLE, FileAccess.READ)
	if f:
		var j = JSON.parse_string(f.get_as_text())
		if typeof(j) == TYPE_DICTIONARY:
			data = j
	Game.noise.connect(_on_noise)

# ------------------------------------------------------------------ the news log (what Ruth did, for the papers)
func log_list() -> Array:
	if Game.state == null:
		return []
	if not Game.state.flags.has("news_log"):
		Game.state.flags["news_log"] = []
	return Game.state.flags["news_log"]

## Systems report newsworthy deeds: "store_robbery" {town, shop, take}, "bounty" {name, amount, alive},
## "gunfight" {town, shots}, "holdup" {town}.
func record(kind: String, info := {}) -> void:
	var e := info.duplicate()
	e["kind"] = kind
	e["day"] = Game.sky.day if Game.sky else 0
	if not e.has("town") and Game.player:
		e["town"] = _town_at(Game.player.global_position)
	var l := log_list()
	l.append(e)
	while l.size() > 40:
		l.pop_front()
	Game.log_event("news_record", e)

func _town_at(p: Vector3) -> String:
	if Game.world == null:
		return ""
	var t := Game.world.nearest_settlement(p.x, p.z)
	if t.is_empty() or Vector2(t.x - p.x, t.z - p.z).length() > float(t.get("r", 150.0)) + 40.0:
		return ""
	return str(t.id)

## Gunshots inside a town: six within half a minute is a gunfight the papers will print (once a day per town).
func _on_noise(pos: Vector3, radius: float, _source: Node) -> void:
	if radius < 200.0:
		return
	var town := _town_at(pos)
	if town == "" or not TOWN_NAMES.has(town):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var l: Array = _shots.get(town, [])
	l = l.filter(func(t): return now - float(t) < 30.0)
	l.append(now)
	_shots[town] = l
	if l.size() >= 6:
		var day: int = Game.sky.day if Game.sky else 0
		for e in log_list():
			if e.kind == "gunfight" and e.get("town", "") == town and int(e.day) == day:
				return
		record("gunfight", {"town": town, "shots": l.size() * 2})
		_shots[town] = []

# ------------------------------------------------------------------ the front page
## Facts for an edition (bots pass their own).
func context(town := "port_linden") -> Dictionary:
	var c: Dictionary = Game.get_meta("social").context(null, "") if Game.has_meta("social") else {"flags": {}, "completed": [], "wanted": 0,
		"bounty": 0.0, "standing": 0.0, "kills": {}, "robberies": 0, "shop_robberies": 0, "weather": "FAIR", "hour": 12.0, "night": false, "role": "", "town": ""}
	c.town = town
	c["records"] = log_list().duplicate()
	c["day"] = Game.sky.day if Game.sky else 0
	c["county"] = ""
	if Game.state:
		var best := 0.0
		for k in Game.state.bounties:
			if float(Game.state.bounties[k]) > best:
				best = float(Game.state.bounties[k])
				c.county = str(k)
	return c

static func story_chapter(completed: Array) -> int:
	var ch := 1
	for id in completed:
		var s := str(id)
		if s == "c6_spring":
			return 7
		if s.length() > 2 and s[0] == "c" and s[1].is_valid_int():
			ch = maxi(ch, int(s[1]) + (1 if s in ["c1_fire", "c2_terms", "c3_fork", "c4_strike", "c5_owe"] else 0))
	return mini(ch, 6)

static func _days(y: int, m: int, d: int) -> int:
	# days since 1 March 1600 (proleptic Gregorian), for weekdays and date arithmetic
	var yy := y - (1 if m <= 2 else 0)
	var era := floori(yy / 400.0)
	var yoe := yy - era * 400
	var mp := (m + 9) % 12
	var doy := (153 * mp + 2) / 5 + d - 1
	var doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe

static func date_for(chapter: int, day: int) -> Dictionary:
	var b: Array = CHAPTER_DATE.get(chapter, CHAPTER_DATE[1])
	var y: int = b[0]
	var m: int = b[1]
	var d: int = b[2] + (day % 6)
	var mlen := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	while d > int(mlen[m - 1]):
		d -= int(mlen[m - 1])
		m += 1
		if m > 12:
			m = 1
			y += 1
	var wd := (_days(y, m, d) + 2) % 7          # 1 March 1600 was a Wednesday
	return {"y": y, "m": m, "d": d, "weekday": WEEKDAYS[wd], "text": "%s, %s %d, %d" % [WEEKDAYS[wd], MONTHS[m - 1], d, y]}

func _sub(text: String, c: Dictionary, rec: Dictionary) -> String:
	var t := text
	var subs: Dictionary = data.get("subs", {})
	for key in subs.keys():
		var tag := "{%s}" % key
		if t.contains(tag):
			var rep := ""
			for opt in subs[key]:
				if _flag_match(c.flags, str(opt[0]), opt[1]):
					rep = str(opt[2])
					break
			t = t.replace(tag, rep)
	var town: String = str(rec.get("town", c.get("town", "")))
	var tname: String = TOWN_NAMES.get(town, town.capitalize().replace("_", " "))
	var shop_names := {"general": "general store", "gunsmith": "gunsmith's", "butcher": "butcher's"}
	t = t.replace("{town}", tname).replace("{town_upper}", tname.to_upper())
	t = t.replace("{shop}", str(shop_names.get(str(rec.get("shop", "general")), "store")))
	t = t.replace("{take}", "%.2f" % float(rec.get("take", 0.0)))
	t = t.replace("{name}", str(rec.get("name", "The outlaw"))).replace("{name_upper}", str(rec.get("name", "")).to_upper())
	t = t.replace("{amount}", str(int(rec.get("amount", 0))))
	t = t.replace("{how}", "taken alive and delivered to the county" if bool(rec.get("alive", false)) else "killed resisting capture")
	t = t.replace("{shots}", str(int(rec.get("shots", 12))))
	t = t.replace("{weekday}", str(c.get("weekday", "Saturday")))
	t = t.replace("{count}", str(int(c.get("_count", 0))))
	t = t.replace("{bounty}", str(int(c.get("bounty", 0.0))))
	var county: String = str(c.get("county", ""))
	var cname := str(WorldState.COUNTIES.get(county, county)) if county != "" else "the county"
	t = t.replace("{county}", cname)
	return t

static func _flag_match(flags: Dictionary, key: String, want) -> bool:
	if not flags.has(key):
		return false
	var v = flags[key]
	if typeof(want) == TYPE_STRING:
		var w: String = want
		if w.begins_with(">="):
			return float(v) >= float(w.substr(2))
		if w.begins_with("<"):
			return float(v) < float(w.substr(1))
		return str(v) == w
	if typeof(want) == TYPE_BOOL:
		return bool(v) == want
	return v == want

## Build a front page. Returns {masthead, motto, editor, date, volume, lead: {head, deck, body}, items: [...],
## weather, prices: [...], ads: [...], notices: [...], story_ids: [...]}.
func edition(c: Dictionary) -> Dictionary:
	var town: String = str(c.get("town", "port_linden"))
	var mh: Dictionary = data.get("mastheads", {}).get(town, data.get("mastheads", {}).get("port_linden", {}))
	var ch := story_chapter(c.completed)
	var dt := date_for(ch, int(c.get("day", 0)))
	c["weekday"] = dt.weekday
	var cands: Array = []
	for s in data.get("stories", []):
		var when: Dictionary = s.get("when", {}).duplicate()
		var rec := {}
		var ri := -1
		if when.has("record"):
			var kind: String = when.record
			var recs: Array = c.get("records", []).filter(func(e): return str(e.get("kind", "")) == kind)
			if recs.size() < int(when.get("record_min", 1)):
				continue
			rec = recs.back()
			ri = c.get("records", []).find(rec)
			c["_count"] = recs.size()
			# old news isn't news: a deed is printed for a week
			if int(c.get("day", 0)) - int(rec.get("day", 0)) > 7:
				continue
			when.erase("record")
			when.erase("record_min")
		if not SOCIAL.matches(when, [], c):
			continue
		cands.append({"s": s, "rec": rec, "p": int(s.get("priority", 1)), "count": int(c.get("_count", 0)), "ri": ri})
	# by priority; among equals, the newest deed first
	cands.sort_custom(func(a, b): return a.p > b.p or (a.p == b.p and a.ri > b.ri))
	var out := {"masthead": str(mh.get("name", "The Lantern")), "motto": str(mh.get("motto", "")), "editor": str(mh.get("editor", "")),
		"date": dt.text, "price": float(mh.get("price", PRICE)), "items": [], "story_ids": [],
		"volume": "Vol. %s — No. %d" % [["XVIII", "XIX"][0 if dt.y == 1899 else 1], (_days(dt.y, dt.m, dt.d) - _days(dt.y, 1, 1)) / 7 + 1]}
	for i in cands.size():
		var e: Dictionary = cands[i]
		c["_count"] = e.count
		var item := {"id": e.s.id, "head": _sub(str(e.s.head), c, e.rec), "deck": _sub(str(e.s.deck), c, e.rec), "body": _sub(str(e.s.body), c, e.rec)}
		if i == 0:
			out["lead"] = item
		elif out.items.size() < 3:
			out.items.append(item)
		else:
			break
		out.story_ids.append(e.s.id)
	var fl: Dictionary = data.get("filler", {})
	var wkey: String = str(c.get("weather", "FAIR"))
	if ch in [4, 5, 6] and wkey in ["OVERCAST", "FAIR", "CLEAR"]:
		wkey = "SNOW"
	out["weather"] = str(fl.get("weather", {}).get(wkey, fl.get("weather", {}).get("FAIR", "")))
	var r := RandomNumberGenerator.new()
	r.seed = hash(town) + _days(dt.y, dt.m, dt.d)
	out["prices"] = _some(fl.get("prices", []), 3, r)
	out["ads"] = _some(fl.get("ads", []), 3, r)
	out["notices"] = _some(fl.get("notices", []), 2, r)
	return out

static func _some(l: Array, n: int, r: RandomNumberGenerator) -> Array:
	var pool := l.duplicate()
	var o := []
	while o.size() < n and not pool.is_empty():
		o.append(pool.pop_at(r.randi() % pool.size()))
	return o

# ------------------------------------------------------------------ newsstands and buying
func _process(dt: float) -> void:
	if _stands_done:
		return
	_stand_t -= dt
	if _stand_t > 0.0:
		return
	_stand_t = 2.0
	var shops := get_tree().get_nodes_in_group("interactable").filter(func(n): return n.has_method("sell_all") and str(n.get("kind")) == "general")
	if shops.is_empty():
		return
	_stands_done = true
	for s in shops:
		var stand = Stand.new()
		stand.town_id = str(s.get("town_id"))
		stand.name = "Newsstand_%s" % stand.town_id
		Game.main.add_child(stand)
		var off := Vector3(2.6, 0, 1.2)
		var p: Vector3 = s.global_position + off
		p.y = s.global_position.y
		stand.global_position = p

## Five cents, and the page opens.
func buy(town: String) -> Dictionary:
	var st = Game.state
	if st == null or st.money < PRICE:
		Game.say("You haven't five cents.", 2.5)
		return {}
	st.add_money(-PRICE)
	st.add_item("newspaper")
	last_edition = edition(context(town))
	st.flags["news_last"] = last_edition
	Game.log_event("newspaper", {"town": town, "lead": last_edition.get("lead", {}).get("id", ""), "date": last_edition.date})
	open_paper(last_edition)
	return last_edition

func has_paper() -> bool:
	return Game.state != null and Game.state.flags.has("news_last")

func open_last() -> void:
	if has_paper():
		open_paper(Game.state.flags["news_last"])

## The printed page.
func open_paper(ed: Dictionary) -> void:
	var menus = Game.get("menus")
	if menus == null or ed.is_empty():
		return
	var ink := Color(0.1, 0.08, 0.07)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.9, 0.82)
	sb.border_color = Color(0.55, 0.5, 0.4)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(30)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(1280, 760)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var top := HBoxContainer.new()
	top.add_child(_lbl(str(ed.get("volume", "")), 16, "caps", ink))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(_lbl("Price Five Cents", 16, "caps", ink))
	v.add_child(top)
	var mh := _lbl(str(ed.masthead), 64, "serif_bold", ink)
	mh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(mh)
	var motto := _lbl(str(ed.get("motto", "")), 18, "italic", ink)
	motto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(motto)
	v.add_child(_rule(ink, 3))
	var dl := HBoxContainer.new()
	dl.add_child(_lbl(str(ed.get("editor", "")), 16, "caps", ink))
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dl.add_child(sp2)
	dl.add_child(_lbl(str(ed.date), 16, "caps", ink))
	v.add_child(dl)
	v.add_child(_rule(ink, 1))
	var lead: Dictionary = ed.get("lead", {})
	if not lead.is_empty():
		var h := _lbl(str(lead.head), 40, "serif_bold", ink)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(h)
		var dk := _lbl(str(lead.deck), 22, "italic", ink)
		dk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(dk)
		var body := _para(str(lead.body), 20, ink, 1200)
		v.add_child(body)
	v.add_child(_rule(ink, 2))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	v.add_child(cols)
	var c1 := _col(cols, 520)
	for it in ed.get("items", []):
		c1.add_child(_lbl(str(it.head), 22, "serif_bold", ink, true, 520))
		c1.add_child(_lbl(str(it.deck), 16, "italic", ink, true, 520))
		c1.add_child(_para(str(it.body), 16, ink, 520))
		c1.add_child(_rule(Color(ink, 0.5), 1))
	cols.add_child(VSeparator.new())
	var c2 := _col(cols, 300)
	c2.add_child(_lbl("THE WEATHER", 18, "serif_bold", ink))
	c2.add_child(_para(str(ed.get("weather", "")), 15, ink, 300))
	c2.add_child(_rule(Color(ink, 0.5), 1))
	c2.add_child(_lbl("MARKETS", 18, "serif_bold", ink))
	for pr in ed.get("prices", []):
		c2.add_child(_para(str(pr), 15, ink, 300))
	c2.add_child(_rule(Color(ink, 0.5), 1))
	c2.add_child(_lbl("NOTICES", 18, "serif_bold", ink))
	for n in ed.get("notices", []):
		c2.add_child(_para(str(n), 15, ink, 300))
	cols.add_child(VSeparator.new())
	var c3 := _col(cols, 330)
	for ad in ed.get("ads", []):
		var box := PanelContainer.new()
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(0, 0, 0, 0)
		bs.border_color = ink
		bs.set_border_width_all(2)
		bs.set_content_margin_all(8)
		box.add_theme_stylebox_override("panel", bs)
		var txt := str(ad)
		var cut := txt.find(".")
		var bv := VBoxContainer.new()
		box.add_child(bv)
		var hl := _lbl(txt.substr(0, cut + 1) if cut > 0 else txt, 17, "serif_bold", ink, true, 310)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bv.add_child(hl)
		if cut > 0:
			var bl := _lbl(txt.substr(cut + 1).strip_edges(), 14, "body", ink, true, 310)
			bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bv.add_child(bl)
		c3.add_child(box)
	v.add_child(menus._button("Fold it away", menus.back))
	menus._push(p)

func _lbl(t: String, size: int, font: String, col: Color, wrap := false, width := 0) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", UITheme.font(font))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(width, 0)
	return l

func _para(t: String, size: int, col: Color, width: int) -> Label:
	var l := _lbl(t, size, "serif", col, true, width)
	return l

func _rule(col: Color, w: int) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.custom_minimum_size = Vector2(0, w)
	return r

func _col(parent: Control, width: int) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.custom_minimum_size = Vector2(width, 0)
	c.add_theme_constant_override("separation", 4)
	parent.add_child(c)
	return c

class Stand extends Node3D:
	## A newsstand: a crate of today's paper beside the general store.
	var town_id := ""

	func _ready() -> void:
		add_to_group("interactable")
		if Game.headless:
			return
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.8, 0.9, 0.5)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.42, 0.3, 0.18)
		mi.material_override = m
		mi.position = Vector3(0, 0.45, 0)
		add_child(mi)
		var pile := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.6, 0.12, 0.4)
		pile.mesh = pm
		var m2 := StandardMaterial3D.new()
		m2.albedo_color = Color(0.88, 0.85, 0.76)
		pile.material_override = m2
		pile.position = Vector3(0, 0.96, 0)
		add_child(pile)

	func interact_prompt() -> String:
		var mh = Game.get_meta("news").data.get("mastheads", {}).get(town_id, {}) if Game.has_meta("news") else {}
		return "Buy %s — 5¢" % str(mh.get("name", "a newspaper"))

	func interact(_who: Node) -> void:
		if Game.has_meta("news"):
			Game.get_meta("news").buy(town_id)
