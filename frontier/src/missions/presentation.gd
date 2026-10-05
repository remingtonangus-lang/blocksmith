extends Node
## Mission bookends. At the start a title card in the 1899 print manner (chapter, title, region and the date on the
## story's calendar); during the mission a tally (time, shots, hits, headshots, damage taken, civilians killed); at
## the end a results card with the tally and two or three optional objectives per main mission, rated gold / silver
## / bronze and kept in WorldState (flags "medals": {mission id: {...}}), which the journal shows.
## The director calls begin(m) and finish(m); everything else is data and pure functions bots can check.

const NEWS = preload("res://src/systems/newspaper.gd")

const CHAPTER_NAMES := {1: "Chapter One · Willow Bend", 2: "Chapter Two · Paper and Iron", 3: "Chapter Three · Dry Season",
	4: "Chapter Four · Silver and Snow", 5: "Chapter Five · The Meridian Line", 6: "Chapter Six · Long Light", 7: "Epilogue · Spring, 1900"}

## Where each main mission happens (title card).
const REGIONS := {"c1_rider": "The river road to Bitter Spring", "c1_drover": "Willow Bend", "c1_inquiries": "Bitter Spring",
	"c1_greer": "Greer's Post", "c1_fire": "Willow Bend", "c2_lantern": "Port Linden", "c2_cards": "The Corinthian, Port Linden",
	"c2_thornwood": "Thornwood", "c2_exchange": "The Linden Exchange", "c2_terms": "Port Linden", "c3_ranch": "Halvorsen Ranch",
	"c3_doc": "Mesquite Wells", "c3_drive": "The Ocotillo Breaks", "c3_rights": "The Ybarra well", "c3_fork": "The Dry Fork",
	"c4_coldwater": "Coldwater", "c4_mine": "The Kestrel mine", "c4_pass": "The Kestrel Pass", "c4_asa": "Under the Kestrel ridge",
	"c4_strike": "Coldwater", "c5_plan": "Willow Bend", "c5_train": "Kessler's Tank", "c5_owe": "Halvorsen Ranch",
	"c6_warrants": "Willow Bend", "c6_eben": "San Lazaro", "c6_ink": "Port Linden", "c6_spring": "The Sable River country"}

## Optional objectives per main mission: [label, kind, args...]. Kinds: time (seconds), accuracy (fraction; met
## when no shots were fired), headshots (count), unhurt (damage taken at most), no_civilians, flag (key, value).
const OBJECTIVES := {
	"c1_rider": [["Ride in before the light goes (5 min)", "time", 300.0], ["Harm no one", "no_civilians"], ["Take no hurt", "unhurt", 0.0]],
	"c1_drover": [["Two head shots", "headshots", 2], ["Accuracy 60%", "accuracy", 0.6], ["Lose no more than 40 health", "unhurt", 40.0]],
	"c1_inquiries": [["Ask your questions inside 7 minutes", "time", 420.0], ["Harm no one", "no_civilians"]],
	"c1_greer": [["Spare the survivor", "flag", "spared_greer_kid", true], ["Three head shots", "headshots", 3], ["Accuracy 50%", "accuracy", 0.5]],
	"c1_fire": [["Lose no more than 50 health", "unhurt", 50.0], ["Three head shots", "headshots", 3], ["Accuracy 50%", "accuracy", 0.5]],
	"c2_lantern": [["Talk the hired men out of it", "flag", "lantern_talked", true], ["Harm no one", "no_civilians"], ["Done inside 8 minutes", "time", 480.0]],
	"c2_cards": [["Catch the cold deck", "flag", "cheat_caught", true], ["Give back every stake", "flag", "returned_stakes", true], ["Two head shots", "headshots", 2]],
	"c2_thornwood": [["Overhear the paymaster", "flag", "heard_thursday", true], ["Accuracy 55%", "accuracy", 0.55], ["Lose no more than 50 health", "unhurt", 50.0]],
	"c2_exchange": [["Past the watchman unseen", "flag", "bank_quiet", true], ["Leave the bait money", "flag", "took_satchel", false], ["Harm no one", "no_civilians"]],
	"c2_terms": [["Out the back unseen", "flag", "left_linden_quiet", true], ["Keep the deeds", "flag", "deeds_kept", true], ["Done inside 8 minutes", "time", 480.0]],
	"c3_ranch": [["Warn the riders off", "flag", "mill_warned", true], ["Two head shots", "headshots", 2], ["Lose no more than 40 health", "unhurt", 40.0]],
	"c3_doc": [["Keep the bottle from Doc", "flag", "doc_sober", true], ["Set the leg clean", "flag", "ines_leg_clean", true], ["Harm no one", "no_civilians"]],
	"c3_drive": [["Accuracy 50%", "accuracy", 0.5], ["Lose no more than 60 health", "unhurt", 60.0], ["Through the Breaks inside 15 minutes", "time", 900.0]],
	"c3_rights": [["Keep the well sweet", "flag", "well_fouled", false], ["No gunplay in the yard", "flag", "drew_on_cutter", false], ["Three head shots", "headshots", 3]],
	"c3_fork": [["Reach the soddy unseen", "flag", "fork_quiet", true], ["Take Cutter in alive", "flag", "cutter_fate", "jailed"], ["Accuracy 50%", "accuracy", 0.5]],
	"c4_coldwater": [["Stand with the miners", "flag", "stood_with_miners", true], ["Lose no more than 40 health", "unhurt", 40.0], ["Two head shots", "headshots", 2]],
	"c4_mine": [["All four men out alive", "flag", "miners_saved", 4], ["Done inside 10 minutes", "time", 600.0], ["Harm no one", "no_civilians"]],
	"c4_pass": [["Dig Joseph out", "flag", "left_joseph", false], ["Lose no more than 30 health", "unhurt", 30.0], ["Over the pass inside 10 minutes", "time", 600.0]],
	"c4_asa": [["Spare the boy", "flag", "spared_asa", true], ["Two head shots", "headshots", 2], ["Accuracy 50%", "accuracy", 0.5]],
	"c4_strike": [["Save the strike kitchen", "flag", "kitchen_burned", false], ["Let the law have Garrity", "flag", "strike_terms", "inspector"], ["Three head shots", "headshots", 3]],
	"c5_plan": [["The ledger only, nobody fires first", "flag", "train_rules", "ledger"], ["Done inside 5 minutes", "time", 300.0]],
	"c5_train": [["Talk the messenger down", "flag", "messenger_killed", false], ["Leave the payroll", "flag", "payroll_taken", false], ["Accuracy 55%", "accuracy", 0.55]],
	"c5_owe": [["Hap lives", "flag", "hap_alive", true], ["The ledger to Fenn", "flag", "ledger_to_fenn", true]],
	"c6_warrants": [["Hold the camp", "flag", "camp_held", true], ["Three head shots", "headshots", 3], ["Lose no more than 60 health", "unhurt", 60.0]],
	"c6_eben": [["Hear him out", "flag", "heard_eben", true], ["Take Eben alive", "flag", "eben_fate", "jailed"], ["Accuracy 60%", "accuracy", 0.6]],
	"c6_ink": [["Set Tom's watch", "flag", "watch_set", true], ["Harm no one", "no_civilians"], ["Done inside 10 minutes", "time", 600.0]],
	"c6_spring": [["Ride the whole country inside 20 minutes", "time", 1200.0], ["Harm no one", "no_civilians"]],
}

var tally := {}
var _gun = null
var _card: CanvasLayer = null

func _ready() -> void:
	Game.set_meta("presentation", self)

# ------------------------------------------------------------------ the tally
func begin(m: Mission) -> void:
	tally = {"id": m.id, "t0": Time.get_ticks_msec(), "shots": 0, "hits": 0, "headshots": 0, "damage": 0.0,
		"civilians0": int(Game.state.kills.get("civilian", 0)) if Game.state else 0}
	_connect()
	show_title(m)

func _connect() -> void:
	_disconnect()
	var p = Game.player
	if p == null or p.get("gun") == null:
		return
	_gun = p.gun
	_gun.fired.connect(_on_fired)
	_gun.hit_landed.connect(_on_hit)
	if p.damageable:
		p.damageable.damaged.connect(_on_hurt)

func _disconnect() -> void:
	if _gun != null and is_instance_valid(_gun):
		if _gun.fired.is_connected(_on_fired):
			_gun.fired.disconnect(_on_fired)
		if _gun.hit_landed.is_connected(_on_hit):
			_gun.hit_landed.disconnect(_on_hit)
	var p = Game.player
	if p != null and p.damageable and p.damageable.damaged.is_connected(_on_hurt):
		p.damageable.damaged.disconnect(_on_hurt)
	_gun = null

func _on_fired(_w, _o, _d) -> void:
	tally.shots = int(tally.get("shots", 0)) + 1

func _on_hit(info: Dictionary) -> void:
	tally.hits = int(tally.get("hits", 0)) + 1
	if str(info.get("zone", "")) == "head":
		tally.headshots = int(tally.get("headshots", 0)) + 1

func _on_hurt(info: Dictionary) -> void:
	tally.damage = float(tally.get("damage", 0.0)) + float(info.get("final", info.get("amount", 0.0)))

# ------------------------------------------------------------------ results
static func objective_met(o: Array, r: Dictionary, flags: Dictionary) -> bool:
	match str(o[1]):
		"time":
			return float(r.time) <= float(o[2])
		"accuracy":
			return int(r.shots) == 0 or float(r.hits) / float(r.shots) >= float(o[2])
		"headshots":
			return int(r.headshots) >= int(o[2])
		"unhurt":
			return float(r.damage) <= float(o[2])
		"no_civilians":
			return int(r.civilians) == 0
		"flag":
			if not flags.has(str(o[2])):
				return false
			var v = flags[str(o[2])]
			if typeof(o[3]) == TYPE_BOOL:
				return bool(v) == bool(o[3])
			if typeof(o[3]) in [TYPE_INT, TYPE_FLOAT]:
				return float(v) == float(o[3])
			return str(v) == str(o[3])
	return false

static func medal_for(met: int, total: int) -> String:
	if total <= 0:
		return ""
	if met >= total:
		return "gold"
	if met * 2 >= total:
		return "silver"
	return "bronze"

## Rate a finished mission from a tally (pure: bots pass their own tally and flags).
static func rate(id: String, r: Dictionary, flags: Dictionary) -> Dictionary:
	var objs := []
	var met := 0
	for o in OBJECTIVES.get(id, []):
		var ok := objective_met(o, r, flags)
		objs.append({"text": str(o[0]), "met": ok})
		if ok:
			met += 1
	return {"time": snappedf(float(r.time), 0.1), "shots": int(r.shots), "hits": int(r.hits), "headshots": int(r.headshots),
		"accuracy": (snappedf(float(r.hits) / float(r.shots), 0.01) if int(r.shots) > 0 else -1.0), "damage": snappedf(float(r.damage), 0.1),
		"objectives": objs, "medal": medal_for(met, objs.size())}

func finish(m: Mission) -> Dictionary:
	_disconnect()
	if tally.is_empty() or str(tally.get("id", "")) != m.id:
		return {}
	var r := tally.duplicate()
	r["time"] = (Time.get_ticks_msec() - int(tally.t0)) / 1000.0
	r["civilians"] = (int(Game.state.kills.get("civilian", 0)) if Game.state else 0) - int(tally.civilians0)
	var flags: Dictionary = Game.state.flags if Game.state else {}
	var res := rate(m.id, r, flags)
	res["title"] = m.title
	if Game.state:
		if not Game.state.flags.has("medals"):
			Game.state.flags["medals"] = {}
		var prev: Dictionary = Game.state.flags["medals"].get(m.id, {})
		var order := {"": 0, "bronze": 1, "silver": 2, "gold": 3}
		# a replay keeps the better medal
		if prev.is_empty() or int(order.get(res.medal, 0)) >= int(order.get(str(prev.get("medal", "")), 0)):
			Game.state.flags["medals"][m.id] = res
	Game.log_event("mission_results", {"id": m.id, "medal": res.medal, "time": res.time, "shots": res.shots, "hits": res.hits,
		"headshots": res.headshots, "met": res.objectives.filter(func(o): return o.met).size(), "of": res.objectives.size()})
	show_results(res)
	tally = {}
	return res

## The journal's line for a mission's medal and objectives ("" if none).
static func medal_text(id: String, flags: Dictionary) -> String:
	var r: Dictionary = flags.get("medals", {}).get(id, {})
	if r.is_empty() or str(r.get("medal", "")) == "":
		return ""
	var t := "[i]%s.[/i]  " % str(r.medal).capitalize()
	var parts := []
	for o in r.get("objectives", []):
		parts.append(("✓ " if o.met else "✗ ") + str(o.text))
	return t + "   ".join(parts)

# ------------------------------------------------------------------ cards
static func chapter_line(m: Mission) -> String:
	if m.companion != "":
		return "The Outfit · %s" % m.companion.capitalize()
	if m.stranger:
		return "A Stranger"
	if m.id == "c6_spring":
		return CHAPTER_NAMES[7]
	return str(CHAPTER_NAMES.get(m.chapter, ""))

static func date_line(m: Mission) -> String:
	var md = Game.missions
	var done: Array = md.completed if md else []
	var ch := NEWS.story_chapter(done)
	if m.id == "c6_spring":
		ch = 7
	var d := NEWS.date_for(ch, int(Game.sky.day) if Game.sky else 0)
	var where: String = m.region if m.region != "" else str(REGIONS.get(m.id, "The Sable River country"))
	return "%s — %s" % [where, d.text]

func show_title(m: Mission) -> void:
	Game.log_event("title_card", {"id": m.id, "chapter": chapter_line(m), "line": date_line(m)})
	if Game.headless or (Game.missions and Game.missions.autopilot) or Game.missions.resuming:
		return
	var cl := _layer()
	var p := _paper(Vector2(820, 0))
	p.anchor_top = 0.18
	p.anchor_bottom = 0.18
	cl.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(_centered(chapter_line(m).to_upper(), 20, "caps", UITheme.OXBLOOD))
	v.add_child(_rule())
	v.add_child(_centered(m.title, 56, "serif_bold", UITheme.INK))
	v.add_child(_rule())
	v.add_child(_centered(date_line(m), 22, "italic", UITheme.INK_SOFT))
	_fade(cl, p, 4.5)

func show_results(r: Dictionary) -> void:
	if Game.headless or (Game.missions and Game.missions.autopilot):
		return
	var cl := _layer()
	var p := results_panel(r)
	cl.add_child(p)
	_fade(cl, p, 8.0)

## The results card itself (also used by the evidence shots).
func results_panel(r: Dictionary) -> PanelContainer:
	var p := _paper(Vector2(760, 0))
	p.anchor_top = 0.2
	p.anchor_bottom = 0.2
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(_centered("MISSION COMPLETE", 20, "caps", UITheme.OXBLOOD))
	v.add_child(_centered(str(r.get("title", "")), 46, "serif_bold", UITheme.INK))
	v.add_child(_rule())
	var t := float(r.get("time", 0.0))
	var acc := float(r.get("accuracy", -1.0))
	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 48)
	for pair in [["TIME", "%d:%02d" % [int(t) / 60, int(t) % 60]], ["ACCURACY", ("%d%%" % int(round(acc * 100.0))) if acc >= 0.0 else "—"],
			["HEAD SHOTS", str(int(r.get("headshots", 0)))]]:
		var col := VBoxContainer.new()
		col.add_child(_centered(pair[0], 16, "caps", UITheme.INK_SOFT))
		col.add_child(_centered(pair[1], 34, "serif_bold", UITheme.INK))
		stats.add_child(col)
	v.add_child(stats)
	v.add_child(_rule())
	for o in r.get("objectives", []):
		var row := Label.new()
		row.text = ("✓  " if o.met else "✗  ") + str(o.text)
		row.add_theme_font_override("font", UITheme.font("body"))
		row.add_theme_font_size_override("font_size", 24)
		row.add_theme_color_override("font_color", UITheme.INK if o.met else Color(UITheme.INK, 0.45))
		v.add_child(row)
	var medal := str(r.get("medal", ""))
	if medal != "":
		var mrow := HBoxContainer.new()
		mrow.alignment = BoxContainer.ALIGNMENT_CENTER
		var disc := Medal.new()
		disc.kind = medal
		disc.custom_minimum_size = Vector2(56, 56)
		mrow.add_child(disc)
		var ml := UITheme.label("  %s" % medal.capitalize(), 34, "display", UITheme.INK, false)
		mrow.add_child(ml)
		v.add_child(mrow)
	return p

func _layer() -> CanvasLayer:
	if _card and is_instance_valid(_card):
		_card.queue_free()
	var cl := CanvasLayer.new()
	cl.layer = 14
	add_child(cl)
	_card = cl
	return cl

func _paper(min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.89, 0.79, 0.96)
	sb.border_color = UITheme.INK
	sb.set_border_width_all(2)
	sb.set_content_margin_all(26)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 14
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = min_size
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_END
	return p

func _centered(t: String, size: int, font: String, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UITheme.font(font))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(UITheme.INK, 0.7)
	r.custom_minimum_size = Vector2(0, 2)
	return r

func _fade(cl: CanvasLayer, p: Control, hold: float) -> void:
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.6)
	tw.tween_interval(hold)
	tw.tween_property(p, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func():
		if is_instance_valid(cl):
			cl.queue_free())

class Medal extends Control:
	var kind := "bronze"

	func _draw() -> void:
		var c := {"gold": Color(0.83, 0.66, 0.24), "silver": Color(0.72, 0.72, 0.74), "bronze": Color(0.6, 0.38, 0.2)}.get(kind, Color.GRAY)
		var ctr := size * 0.5
		var r := minf(size.x, size.y) * 0.45
		draw_circle(ctr, r, c)
		draw_arc(ctr, r, 0, TAU, 40, Color(0.2, 0.14, 0.08), 2.0, true)
		draw_arc(ctr, r * 0.72, 0, TAU, 40, Color(0.2, 0.14, 0.08, 0.6), 1.5, true)
		# a five-point star
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI / 2 + i * PI / 5.0
			var rr := r * (0.55 if i % 2 == 0 else 0.24)
			pts.append(ctr + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(pts, Color(0.2, 0.14, 0.08, 0.75))
