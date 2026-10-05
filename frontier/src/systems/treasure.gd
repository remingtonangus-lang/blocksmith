extends Node
## Treasure maps: a chain of three hand-drawn maps, inked in the journal-sketch manner over the real terrain (contour
## lines sampled from the heightmap, water hatched, roads and the nearest landmarks drawn in, an X where the dirt is
## soft), each with a riddle in the dead man's hand. The first is in Cole Hatcher's saddlebag (bounty board); dig at
## its X for the second, then the third, and at the end of the third, gold bars. Read the maps from the satchel or
## the journal. Flags treasure_<n> = true when each is dug.

const C3 = preload("res://src/missions/ch3/ch3.gd")

const MAPS := [
	{"n": 1, "title": "The Hatcher Map", "riddle": "From Greer's door ride toward the setting sun. Where the land stands highest above the river road, the old stone looks east. Dig on its morning side, a pick's length down.", "place": "greer_post", "kind": "high_west"},
	{"n": 2, "title": "The Second Map", "riddle": "Leave Port Linden by the lake road and walk toward the big water until the boards and the warehouses give out. On the last dry footing before the lake, the tin box waits.", "place": "port_linden", "kind": "shore"},
	{"n": 3, "title": "The Last Map", "riddle": "The padres rang their bell for the last time in sixty-one. Stand in the chapel door and walk sixty paces toward the noon sun. The gold is under the dead mesquite.", "place": "san_lazaro", "kind": "south"},
]
const GOLD_BARS := 3
## Who buys gold: the Linden Exchange (honest price, asks questions: not while Ruth is wanted) and Tobias Greer at
## his trading post (a fence: less, and no questions).
const BUYERS := {"bank": {"town": "port_linden", "building": "bank", "name": "Linden Exchange teller", "price": 180.0, "honest": true},
	"fence": {"town": "greer_post", "building": "trading_post", "name": "Tobias Greer", "price": 125.0, "honest": false}}

var spots: Array = []         # DigSpot nodes, one per map
var _placed := false
var _t := 2.0
var _hinted := {}

func _ready() -> void:
	Game.set_meta("treasure", self)

## Where map n's X is, on the real terrain.
static func target(n: int) -> Vector3:
	var m: Dictionary = MAPS[n - 1]
	var base := Mission.place(str(m.place))
	var w = Game.world
	match str(m.kind):
		"high_west":
			var best := Vector3(base.x - 250.0, 0, base.z)
			best.y = w.height(best.x, best.z)
			for r in [150.0, 220.0, 300.0, 360.0]:
				for k in 9:
					var a := PI * 0.75 + PI * 0.5 * k / 8.0          # the western quarter
					var q := Vector3(base.x + cos(a) * r, 0, base.z + sin(a) * r)
					q.y = w.height(q.x, q.z)
					if q.y > best.y and not w.is_water(q.x, q.z):
						best = q
			return best
		"shore":
			var lk = w.features.get("lake", {})
			var sz := float(w.features.get("size_m", 8192.0))
			var c := Vector3((float(lk.get("u", 0.9)) - 0.5) * sz, 0, (float(lk.get("v", 0.5)) - 0.5) * sz)
			var dir := (c - base)
			dir.y = 0.0
			dir = dir.normalized()
			var p := base
			for i in 400:
				var q := base + dir * float(i) * 6.0
				if w.is_water(q.x, q.z):
					break
				p = q
			p.y = w.height(p.x, p.z)
			return p
		_:
			return C3.dry(base + Vector3(0, 0, 55.0))

func has_map(n: int) -> bool:
	return Game.state != null and int(Game.state.inventory.get("treasure_map_%d" % n, 0)) > 0

static func dug(n: int) -> bool:
	return Game.state != null and bool(Game.state.flags.get("treasure_%d" % n, false))

# ------------------------------------------------------------------ dig spots
func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0 or Game.player == null or Game.world == null:
		return
	_t = 1.0
	if not _placed:
		_placed = true
		for k in BUYERS.keys():
			var g := GoldBuyer.new()
			g.kind = k
			g.name = "GoldBuyer_%s" % k
			g.position = buyer_pos(k)
			Game.main.add_child(g)
		for m in MAPS:
			var d := DigSpot.new()
			d.n = int(m.n)
			d.name = "TreasureDig_%d" % d.n
			Game.main.add_child(d)
			d.global_position = target(d.n)
			spots.append(d)
	# a word to the wise when Ruth is near an X she has the map for
	for d in spots:
		if has_map(d.n) and not dug(d.n) and not _hinted.has(d.n) and Game.player.global_position.distance_to(d.global_position) < 14.0:
			_hinted[d.n] = true
			if Game.hud:
				Game.hud.notice("The earth here has been turned once, long ago", 4.0)

## Dig at map n's X: the next map, or the gold. Returns what was found ("treasure_map_2", "gold", or "").
func dig(n: int) -> String:
	if not has_map(n) or dug(n):
		return ""
	var st = Game.state
	st.flags["treasure_%d" % n] = true
	st.inventory["treasure_map_%d" % n] = int(st.inventory["treasure_map_%d" % n]) - 1
	var found := ""
	if n < MAPS.size():
		found = "treasure_map_%d" % (n + 1)
		st.add_item(found)
		Game.say("A rusted tin box. Inside, another map in the same cramped hand.", 4.0)
	else:
		found = "gold"
		st.add_item("gold_bar", GOLD_BARS)
		st.flags["treasure_found"] = true
		Game.say("Three bars of gold, wrapped in an old cavalry guidon gone to lace. Somebody waited a long time for these.", 6.0)
		if Game.has_meta("news"):
			Game.get_meta("news").record("treasure", {})
	Game.log_event("treasure_dug", {"n": n, "found": found})
	return found

static func buyer_pos(kind: String) -> Vector3:
	var P = load("res://src/missions/places.gd")
	var bi: Dictionary = BUYERS[kind]
	var fallback := Mission.place(str(bi.town), 6.0, -4.0)
	var b: Dictionary = P.building(str(bi.town), str(bi.building))
	for sp in ["teller", "shop_counter", "bartender"]:
		var s: Dictionary = P.spot(b, sp)
		if not s.is_empty():
			return P.at(s, fallback)
	return P.door_out(b, fallback)

## Sell every gold bar to a buyer ("bank" or "fence"). Returns the money paid (0 if refused or nothing to sell).
func sell_gold(kind: String) -> float:
	var st = Game.state
	var bi: Dictionary = BUYERS.get(kind, {})
	var n := int(st.inventory.get("gold_bar", 0)) if st else 0
	if bi.is_empty() or n <= 0:
		return 0.0
	if bool(bi.honest) and (int(st.wanted) > 0 or st.standing <= -40.0):
		Game.say("\"The Exchange doesn't buy from people on posters, madam.\"", 3.0)
		Game.log_event("gold_refused", {"buyer": kind})
		return 0.0
	var paid := float(bi.price) * n
	st.inventory["gold_bar"] = 0
	st.add_money(paid)
	Game.log_event("gold_sold", {"buyer": kind, "bars": n, "paid": paid})
	Game.say("%s pays $%d for %d bar%s of gold." % [bi.name, int(paid), n, "" if n == 1 else "s"], 4.0)
	return paid

## The map, on paper.
func open_map(n: int) -> void:
	var menus = Game.get("menus")
	if menus == null:
		return
	var m: Dictionary = MAPS[n - 1]
	var p: PanelContainer = menus._paper_panel(Vector2(980, 700))
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UITheme.label(str(m.title), 40, "display", UITheme.INK, false))
	var sk := MapSketch.new()
	sk.custom_minimum_size = Vector2(920, 470)
	sk.setup(target(n), n)
	v.add_child(sk)
	var r := UITheme.label(str(m.riddle), 22, "italic", UITheme.INK, false)
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(920, 0)
	v.add_child(r)
	v.add_child(menus._button("Fold it away", menus.back))
	menus._push(p)

class GoldBuyer extends Node3D:
	var kind := "bank"

	func _ready() -> void:
		add_to_group("interactable")

	func interact_prompt() -> String:
		if Game.state == null or int(Game.state.inventory.get("gold_bar", 0)) <= 0:
			return ""
		var bi: Dictionary = BUYERS[kind]
		return "Sell your gold to the %s ($%d a bar)" % [bi.name, int(bi.price)]

	func interact(_who: Node) -> void:
		if Game.has_meta("treasure"):
			Game.get_meta("treasure").sell_gold(kind)

class DigSpot extends Node3D:
	var n := 1

	func _ready() -> void:
		add_to_group("interactable")

	func interact_prompt() -> String:
		var tr = Game.get_meta("treasure") if Game.has_meta("treasure") else null
		if tr == null or not tr.has_map(n) or tr.dug(n):
			return ""
		return "Dig where the map's X is"

	func interact(_who: Node) -> void:
		if Game.has_meta("treasure"):
			Game.get_meta("treasure").dig(n)

class MapSketch extends Control:
	## A hand-drawn map over the real ground: contours from the heightmap, hatched water, roads, landmarks, an X.
	var center := Vector3.ZERO
	var x_world := Vector3.ZERO
	var span := 900.0                  # metres across
	var seed_value := 1
	var ink := Color(0.2, 0.13, 0.08, 0.9)
	var _rng := RandomNumberGenerator.new()
	var _grid: PackedFloat32Array
	var _water: PackedByteArray
	const GW := 64
	const GH := 34

	func setup(c: Vector3, n: int) -> void:
		center = c
		seed_value = n * 977
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# the X is not quite in the middle: dead men didn't draw to scale
		var off := Vector3(float((n * 37) % 120) - 60.0, 0, float((n * 53) % 90) - 45.0)
		x_world = c
		center = c + off
		_sample()

	func _sample() -> void:
		_grid.resize(GW * GH)
		_water.resize(GW * GH)
		var w = Game.world
		for j in GH:
			for i in GW:
				var p := _world(i, j)
				_grid[j * GW + i] = w.height(p.x, p.z)
				_water[j * GW + i] = 1 if w.is_water(p.x, p.z) else 0

	func _world(i: int, j: int) -> Vector3:
		var sx := span
		var sz := span * float(GH) / float(GW)
		return center + Vector3((float(i) / (GW - 1) - 0.5) * sx, 0, (float(j) / (GH - 1) - 0.5) * sz)

	func _to_px(p: Vector3) -> Vector2:
		var sz := span * float(GH) / float(GW)
		return Vector2(((p.x - center.x) / span + 0.5) * size.x, ((p.z - center.z) / sz + 0.5) * size.y)

	func _wob(a: Vector2, b: Vector2, wdt := 1.3) -> void:
		var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * _rng.randf_range(-0.8, 0.8)
		draw_line(a, mid, ink, wdt, true)
		draw_line(mid, b, ink, wdt, true)

	func _draw() -> void:
		_rng.seed = seed_value
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.88, 0.8, 0.62, 0.6), true)
		var cw := size.x / (GW - 1)
		var ch := size.y / (GH - 1)
		# contours (marching squares) every 12 m
		var lo := INF
		var hi := -INF
		for v in _grid:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		var step := 12.0
		var level := ceilf(lo / step) * step
		while level < hi:
			var heavy := int(level / step) % 5 == 0
			for j in GH - 1:
				for i in GW - 1:
					var a := _grid[j * GW + i]
					var b := _grid[j * GW + i + 1]
					var c := _grid[(j + 1) * GW + i + 1]
					var d := _grid[(j + 1) * GW + i]
					var pts: Array = []
					var x0 := i * cw
					var y0 := j * ch
					if (a < level) != (b < level):
						pts.append(Vector2(x0 + cw * (level - a) / (b - a), y0))
					if (b < level) != (c < level):
						pts.append(Vector2(x0 + cw, y0 + ch * (level - b) / (c - b)))
					if (d < level) != (c < level):
						pts.append(Vector2(x0 + cw * (level - d) / (c - d), y0 + ch))
					if (a < level) != (d < level):
						pts.append(Vector2(x0, y0 + ch * (level - a) / (d - a)))
					if pts.size() >= 2:
						draw_line(pts[0], pts[1], Color(ink, 0.55 if heavy else 0.3), 1.3 if heavy else 0.8, true)
					if pts.size() == 4:
						draw_line(pts[2], pts[3], Color(ink, 0.55 if heavy else 0.3), 1.3 if heavy else 0.8, true)
			level += step
		# water: hatched
		for j in GH:
			for i in GW:
				if _water[j * GW + i] == 1:
					var p := Vector2(i * cw, j * ch)
					draw_line(p + Vector2(-cw * 0.4, ch * 0.2), p + Vector2(cw * 0.4, -ch * 0.2), Color(0.18, 0.25, 0.35, 0.6), 1.0, true)
		# roads: dashed double line
		for r in Game.world.features.roads:
			var prev := Vector2.INF
			var k := 0
			for pt in r.points:
				var q := _to_px(Vector3(float(pt[0]), 0, float(pt[1])))
				var sheet := Rect2(Vector2(4, 4), size - Vector2(8, 8))
				if prev != Vector2.INF and sheet.has_point(q) and sheet.has_point(prev):
					if k % 2 == 0:
						_wob(prev, q, 1.6)
				prev = q
				k += 1
		# landmarks within the sheet
		var font := UITheme.font("italic")
		for list in [Game.world.features.towns, Game.world.features.pois]:
			for t in list:
				var q := _to_px(Vector3(float(t.x), 0, float(t.z)))
				if Rect2(Vector2(10, 10), size - Vector2(20, 20)).has_point(q):
					draw_rect(Rect2(q - Vector2(5, 5), Vector2(10, 10)), ink, false, 1.5)
					draw_string(font, q + Vector2(9, 5), str(t.get("name", t.id)).replace("_", " ").capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)
		# the X, a little blotted
		var x := _to_px(x_world)
		draw_line(x + Vector2(-12, -12), x + Vector2(12, 12), Color(0.5, 0.1, 0.07), 3.5, true)
		draw_line(x + Vector2(-12, 12), x + Vector2(12, -12), Color(0.5, 0.1, 0.07), 3.5, true)
		# compass
		var cp := Vector2(size.x - 50, 52)
		_wob(cp + Vector2(0, 28), cp + Vector2(0, -28), 1.6)
		_wob(cp + Vector2(-18, 0), cp + Vector2(18, 0), 1.2)
		draw_colored_polygon(PackedVector2Array([cp + Vector2(0, -30), cp + Vector2(-6, -16), cp + Vector2(6, -16)]), ink)
		draw_string(UITheme.font("caps"), cp + Vector2(-6, -36), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
		# a torn, foxed border
		var pts2 := PackedVector2Array()
		for i in 41:
			pts2.append(Vector2(size.x * i / 40.0, _rng.randf_range(0, 4)))
		for i in 41:
			pts2.append(Vector2(size.x - _rng.randf_range(0, 4), size.y * i / 40.0))
		for i in 41:
			pts2.append(Vector2(size.x * (1.0 - i / 40.0), size.y - _rng.randf_range(0, 4)))
		for i in 41:
			pts2.append(Vector2(_rng.randf_range(0, 4), size.y * (1.0 - i / 40.0)))
		draw_polyline(pts2, Color(ink, 0.7), 1.6, true)
