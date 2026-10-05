extends Node
## Travel. Train tickets (Meridian & Western) from the station agents at the Bitter Spring, Mesquite Wells and
## Port Linden depots (the settlements' ticket_agent spots), stage tickets (Sable Valley Stage Line) at the livery
## or trading post of each stop, and fast travel from the map table at Willow Bend to any place Ruth has been.
## A short fade with a ticket card (or the paper she reads on the way) and the hours pass; her horse comes along.
## Discovered places are kept in WorldState (flags "discovered"); tickets refused while she's wanted.

const P = preload("res://src/missions/places.gd")
const NEWS = preload("res://src/systems/newspaper.gd")

const TRAIN_STOPS := ["bitter_spring", "mesquite_wells", "port_linden"]
const STAGE_STOPS := ["bitter_spring", "coldwater", "mesquite_wells", "port_linden", "greer_post"]
const MODES := {
	"train": {"line": "MERIDIAN & WESTERN RAILROAD", "per_km": 0.55, "kmh": 38.0, "board": 0.4},
	"stage": {"line": "SABLE VALLEY STAGE LINE", "per_km": 0.35, "kmh": 11.0, "board": 0.25},
	"ride": {"line": "", "per_km": 0.0, "kmh": 9.0, "board": 0.0},
}

var counters: Array = []
var _placed := false
var _t := 2.0
var _card: CanvasLayer = null

func _ready() -> void:
	Game.set_meta("travel", self)

static func place_name(id: String) -> String:
	var t: Dictionary = Game.world.town(id)
	if t.is_empty():
		t = Game.world.poi(id)
	return str(t.get("name", id.replace("_", " ").capitalize()))

static func discovered() -> Dictionary:
	if Game.state == null:
		return {}
	if not Game.state.flags.has("discovered"):
		Game.state.flags["discovered"] = {"caddell_camp": true}
	return Game.state.flags["discovered"]

func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0 or Game.player == null or Game.world == null:
		return
	_t = 2.0
	if not _placed:
		_place_counters()
	# places Ruth has been
	var pp: Vector3 = Game.player.global_position
	# a town's interior comes in near its buildings: move the clerk to the depot's ticket window once it exists
	for c in counters:
		if is_instance_valid(c) and c.global_position.distance_to(pp) < 90.0:
			var want := counter_pos(c.mode, c.town)
			if want.distance_to(c.global_position) > 0.5:
				c.global_position = want
	var d := discovered()
	for list in [Game.world.features.towns, Game.world.features.pois]:
		for t in list:
			if not d.has(t.id) and Vector2(float(t.x) - pp.x, float(t.z) - pp.z).length() < float(t.get("r", 80.0)) + 40.0:
				d[t.id] = true
				Game.log_event("discovered", {"id": t.id})
				if Game.hud and not Game.headless:
					Game.hud.notice("Discovered: %s" % place_name(t.id), 3.0)

func _place_counters() -> void:
	_placed = true
	for town in TRAIN_STOPS:
		_counter("train", town)
	for town in STAGE_STOPS:
		_counter("stage", town)
	var table := MapTable.new()
	table.name = "MapTable"
	var c: Dictionary = Game.world.poi("caddell_camp")
	var p := Vector3(float(c.x) + 3.2, 0, float(c.z) - 2.4)
	p.y = Game.world.height(p.x, p.z)
	table.position = p
	Game.main.add_child(table)

## Where the agent stands: the depot's ticket_agent spot (train), the livery or trading post door (stage).
static func counter_pos(mode: String, town: String) -> Vector3:
	var fallback := Mission.place(town, -10.0 if mode == "train" else 12.0, 8.0)
	if mode == "train":
		var b := P.building(town, "depot")
		if b.is_empty():
			b = any_building(town, "depot")         # a depot without a furnished interior: the platform window
		var sp := P.spot(b, "ticket_agent")
		if not sp.is_empty():
			return P.at(sp, fallback)
		if b.is_empty():
			b = any_building(town, "post")          # no depot built: the telegraph office sells the tickets
		if b.is_empty():
			b = any_building(town, "water_tower")   # a flag stop: the agent waits by the water tower
		return P.door_out(b, fallback)
	for kind in ["livery", "trading_post", "depot"]:
		var b2 := P.building(town, kind)
		if not b2.is_empty():
			return P.door_out(b2, fallback) + Vector3(0.0, 0, 1.2 if kind == "depot" else 0.0)
	return fallback

## First building of a type in a town, furnished or not ({} if none).
static func any_building(town: String, type: String) -> Dictionary:
	var s = P.kit()
	if s == null:
		return {}
	s.ensure_built(town)
	for bid in s.get_town(town).get("buildings", []):
		var b: Dictionary = s.get_building(bid)
		if str(b.get("type", "")) == type:
			return b
	return {}

func _counter(mode: String, town: String) -> void:
	var c := Counter.new()
	c.mode = mode
	c.town = town
	c.name = "Tickets_%s_%s" % [mode, town]
	c.position = counter_pos(mode, town)
	Game.main.add_child(c)
	counters.append(c)

## Price, hours and distance of a trip.
static func fare(mode: String, from: String, to: String) -> Dictionary:
	var a := Mission.place(from)
	var b := Mission.place(to)
	var km := Vector2(a.x - b.x, a.z - b.z).length() / 1000.0 * 1.25     # roads wind
	var m: Dictionary = MODES[mode]
	return {"km": snappedf(km, 0.1), "price": snappedf(maxf(km * float(m.per_km), 0.5 if mode != "ride" else 0.0), 0.05),
		"hours": snappedf(km / float(m.kmh) + float(m.board), 0.1)}

static func refused(mode: String) -> String:
	if Game.state == null or mode == "ride":
		return ""
	if int(Game.state.wanted) >= 2:
		return "\"Not with your face on the wall by the window, madam.\""
	return ""

## Go: pay, fade with a card, pass the hours, arrive (horse too). Returns true if Ruth went.
func travel(mode: String, from: String, to: String) -> bool:
	if from == to:
		return false
	var why := refused(mode)
	if why != "":
		Game.say(why, 3.0)
		Game.log_event("travel_refused", {"mode": mode, "to": to})
		return false
	var f := fare(mode, from, to)
	var st = Game.state
	if mode != "ride":
		if st.money < float(f.price):
			Game.say("The fare is $%.2f. You haven't got it." % float(f.price), 3.0)
			return false
		st.add_money(-float(f.price))
	var dest := arrival(mode, to)
	await _fade_card(mode, from, to, f)
	_pass_hours(float(f.hours))
	var md = Game.missions
	if Game.player.get("on_horse") != null and md:
		md.dismount_player()
	md._teleport_player(dest)
	var horse = Horse.player_horse if is_instance_valid(Horse.player_horse) else null
	if horse != null and horse.rider == null:
		md._put_on_ground(horse, dest + Vector3(3.0, 0, 2.0))
	Game.log_event("travel", {"mode": mode, "from": from, "to": to, "price": f.price, "hours": f.hours})
	if Game.has_meta("autosave"):
		Game.get_meta("autosave").autosave("travel")
	if Game.hud and not Game.headless:
		Game.hud.notice("%s — %d hours later" % [place_name(to), int(round(float(f.hours)))], 4.0)
	return true

static func arrival(mode: String, to: String) -> Vector3:
	if mode == "ride":
		var c := Mission.place(to, 14.0, 10.0)
		return c
	return counter_pos(mode, to) + Vector3(2.0, 0, 2.0)

func _pass_hours(h: float) -> void:
	if Game.sky == null:
		return
	var t: float = Game.sky.hours + h
	while t >= 24.0:
		t -= 24.0
		Game.sky.day += 1
	Game.sky.set_time(t)

func _fade_card(mode: String, from: String, to: String, f: Dictionary) -> void:
	Game.log_event("travel_card", {"mode": mode, "to": to})
	if Game.headless or (Game.missions and Game.missions.autopilot):
		return
	if _card and is_instance_valid(_card):
		_card.queue_free()
	var cl := CanvasLayer.new()
	cl.layer = 18
	add_child(cl)
	_card = cl
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(black)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.92, 0.87, 0.74) if mode != "ride" else Color(0.9, 0.84, 0.7)
	sb.border_color = UITheme.INK
	sb.set_border_width_all(3)
	sb.set_content_margin_all(24)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(620, 0)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.3
	card.anchor_bottom = 0.3
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.modulate.a = 0.0
	cl.add_child(card)
	var v := VBoxContainer.new()
	card.add_child(v)
	var done: Array = Game.missions.completed if Game.missions else []
	var date: Dictionary = NEWS.date_for(NEWS.story_chapter(done), int(Game.sky.day) if Game.sky else 0)
	var lines := []
	if mode == "jail":
		lines = [["THE COUNTY JAIL", 20, "caps"], ["%s" % place_name(to), 40, "serif_bold"],
			["A night in the cells. Released at first light; $%.2f paid toward the bounty." % float(f.price), 22, "italic"], [str(date.text), 18, "caps"]]
	elif mode == "ride":
		lines = [["ON THE TRAIL", 20, "caps"], ["To %s" % place_name(to), 40, "serif_bold"],
			["%d miles, about %d hours in the saddle" % [int(float(f.km) * 0.62), int(round(float(f.hours)))], 22, "italic"], [str(date.text), 18, "caps"]]
	else:
		lines = [[str(MODES[mode].line), 20, "caps"], ["ADMIT ONE · %s CLASS" % ("SECOND" if mode == "train" else "INSIDE"), 16, "caps"],
			["%s  to  %s" % [place_name(from), place_name(to)], 34, "serif_bold"],
			["Fare $%.2f  ·  about %d hours" % [float(f.price), int(round(float(f.hours)))], 22, "italic"], [str(date.text), 18, "caps"]]
		var last: Dictionary = Game.state.flags.get("news_last", {}) if Game.state else {}
		if mode == "train" and not last.is_empty():
			lines.append(["On the way you read: %s" % str(last.get("lead", {}).get("head", "")).capitalize(), 18, "italic"])
	for l in lines:
		var lab := Label.new()
		lab.text = str(l[0])
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.add_theme_font_override("font", UITheme.font(str(l[2])))
		lab.add_theme_font_size_override("font_size", int(l[1]))
		lab.add_theme_color_override("font_color", UITheme.INK)
		v.add_child(lab)
	var tw := create_tween()
	tw.tween_property(black, "color:a", 1.0, 0.6)
	tw.parallel().tween_property(card, "modulate:a", 1.0, 0.6)
	await tw.finished
	await get_tree().create_timer(2.2).timeout
	var tw2 := create_tween()
	tw2.tween_property(black, "color:a", 0.0, 0.8)
	tw2.parallel().tween_property(card, "modulate:a", 0.0, 0.6)
	tw2.finished.connect(func():
		if is_instance_valid(cl):
			cl.queue_free())

func open_tickets(mode: String, from: String) -> void:
	var menus = Game.get("menus")
	if menus == null:
		return
	var p: PanelContainer = menus._paper_panel(Vector2(680, 0))
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UITheme.label(str(MODES[mode].line).capitalize(), 40, "display", UITheme.INK, false))
	v.add_child(UITheme.label("From %s" % place_name(from), 22, "italic", UITheme.INK_SOFT, false))
	v.add_child(HSeparator.new())
	var stops: Array = TRAIN_STOPS if mode == "train" else STAGE_STOPS
	for to in stops:
		if to == from:
			continue
		var f := fare(mode, from, to)
		var dest: String = to
		v.add_child(menus._button("%s — $%.2f, %d hours" % [place_name(to), float(f.price), int(round(float(f.hours)))], func():
			menus.close_all()
			travel(mode, from, dest)))
	v.add_child(menus._button("Not today", menus.back))
	menus._push(p)

func open_map_table() -> void:
	var menus = Game.get("menus")
	if menus == null:
		return
	var p: PanelContainer = menus._paper_panel(Vector2(680, 0))
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UITheme.label("The Map Table", 40, "display", UITheme.INK, false))
	v.add_child(UITheme.label("Ride out to somewhere you've been", 22, "italic", UITheme.INK_SOFT, false))
	v.add_child(HSeparator.new())
	for id in destinations():
		var f := fare("ride", "caddell_camp", id)
		var dest: String = id
		v.add_child(menus._button("%s — %d hours" % [place_name(id), int(round(float(f.hours)))], func():
			menus.close_all()
			travel("ride", "caddell_camp", dest)))
	v.add_child(menus._button("Stay in camp", menus.back))
	menus._push(p)

## Places the map table can send Ruth to: discovered, not the camp itself.
func destinations() -> Array:
	return discovered().keys().filter(func(id): return str(id) != "caddell_camp")

class Counter extends Node3D:
	var mode := "train"
	var town := ""

	func _ready() -> void:
		add_to_group("interactable")

	func interact_prompt() -> String:
		return "Buy a train ticket" if mode == "train" else "Buy a stage ticket"

	func interact(_who: Node) -> void:
		if Game.has_meta("travel"):
			Game.get_meta("travel").open_tickets(mode, town)

class MapTable extends Node3D:
	func _ready() -> void:
		add_to_group("interactable")
		if Game.headless:
			return
		var top := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.4, 0.06, 0.9)
		top.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.45, 0.33, 0.22)
		top.material_override = m
		top.position.y = 0.82
		add_child(top)
		var sheet := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(1.1, 0.01, 0.7)
		sheet.mesh = sm
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.88, 0.82, 0.66)
		sheet.material_override = pm
		sheet.position.y = 0.86
		add_child(sheet)
		for x in [-0.6, 0.6]:
			for z in [-0.35, 0.35]:
				var leg := MeshInstance3D.new()
				var lm := BoxMesh.new()
				lm.size = Vector3(0.06, 0.8, 0.06)
				leg.mesh = lm
				leg.material_override = m
				leg.position = Vector3(x, 0.4, z)
				add_child(leg)

	func interact_prompt() -> String:
		return "Look at the map table"

	func interact(_who: Node) -> void:
		if Game.has_meta("travel"):
			Game.get_meta("travel").open_map_table()
