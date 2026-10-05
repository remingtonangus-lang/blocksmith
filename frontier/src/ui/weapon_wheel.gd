class_name WeaponWheel
extends CanvasLayer
## Hold the wheel button (Tab / LB): time slows to a crawl and a printed-ink wheel opens: weapons around the rim
## (with loaded/carried rounds), satchel items in the inner ring (tonics, food), holster at the top. Point with the
## mouse or right stick; releasing equips or uses the highlighted entry. A quick tap just cycles weapons.

const SLOW := 0.2
const TAP := 0.18

var player: Node
var open := false
var _held := 0.0
var _aim := Vector2.ZERO
var _entries: Array = []          # [{kind: "weapon"/"item"/"holster", id, label, sub, ring: 0 outer/1 inner}]
var _sel := -1
var _ctl: Control

func setup(p: Node) -> void:
	player = p
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ctl = Control.new()
	_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ctl.visible = false
	_ctl.draw.connect(_draw_wheel)
	add_child(_ctl)

func _process(dt: float) -> void:
	if player == null or player.get("bot_driven") or (Game.get("menus") and not Game.menus.stack.is_empty()):
		return
	var real_dt := dt / maxf(Engine.time_scale, 0.01)
	if Input.is_action_pressed("weapon_wheel"):
		_held += real_dt
		if not open and _held > TAP:
			_open()
		if open:
			var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
			if stick.length() > 0.4:
				_aim = stick.normalized() * 120.0
			_pick()
			# Reload while the wheel is open: next loading for the highlighted weapon's calibre (used at next reload)
			if Input.is_action_just_pressed("reload") and _sel >= 0 and _entries[_sel].kind == "weapon":
				var w: String = player.gun.weapons[int(_entries[_sel].idx)]
				var base := str(Weapons.get_def(w).ammo)
				var v: String = player.gun.cycle_ammo_base(base)
				_ammo_note = "Next load: " + (str(player.gun.AMMO_MODS[v].name) if v != "" else "Standard")
			_ctl.queue_redraw()
	elif _held > 0.0:
		if open:
			_close(true)
		else:
			var g = player.gun
			if g and g.weapons.size() > 0:
				g.select((g.current + 1) % g.weapons.size())
		_held = 0.0

var _ammo_note := ""

func _input(event: InputEvent) -> void:
	if open and event is InputEventMouseMotion:
		_aim += event.relative
		_aim = _aim.limit_length(160.0)
		get_viewport().set_input_as_handled()

func _open() -> void:
	_ammo_note = ""
	open = true
	_aim = Vector2.ZERO
	_sel = -1
	_build_entries()
	Engine.time_scale = SLOW
	_ctl.visible = true
	if Game.audio and Game.audio.has_method("ui"):
		Game.audio.ui("wheel_open")

func _close(apply: bool) -> void:
	open = false
	Engine.time_scale = 1.0
	_ctl.visible = false
	if apply and _sel >= 0:
		var e: Dictionary = _entries[_sel]
		match e.kind:
			"weapon":
				player.gun.select(int(e.idx))
				player.gun.drawn = true
			"holster":
				player.gun.drawn = false
			"item":
				if Game.state and Game.state.use_item(e.id):
					Game.say("Used %s." % e.label.to_lower(), 2.0)
		Game.log_event("wheel", {"kind": e.kind, "id": e.get("id", "")})

func _build_entries() -> void:
	_entries.clear()
	_entries.append({"kind": "holster", "id": "holster", "label": "Holster", "sub": "", "ring": 0})
	var g = player.gun
	for i in g.weapons.size():
		var id: String = g.weapons[i]
		var d: Dictionary = Weapons.get_def(id)
		var loaded := int(g.clip.get(id, 0))
		var carried := int(g.ammo.get(str(d.get("ammo", "")), 0))
		_entries.append({"kind": "weapon", "id": id, "idx": i, "label": str(d.get("name", id)), "sub": "%d / %d" % [loaded, carried], "ring": 0})
	var names := {"tonic_health": "Restorative Tonic", "tonic_nerve": "Steady-Hand Bitters", "jerky": "Beef Jerky",
		"coffee": "Coffee", "cooked_meat": "Cooked Meat"}
	for id in names.keys():
		var n := int(Game.state.inventory.get(id, 0)) if Game.state else 0
		if n > 0:
			_entries.append({"kind": "item", "id": id, "label": names[id], "sub": "× %d" % n, "ring": 1})

func _pick() -> void:
	if _aim.length() < 40.0:
		_sel = -1
		return
	var inner := _aim.length() < 100.0
	var ring := 1 if inner else 0
	var cands := []
	for i in _entries.size():
		if _entries[i].ring == ring:
			cands.append(i)
	if cands.is_empty():
		cands = range(_entries.size()).filter(func(i): return _entries[i].ring == 0)
		ring = 0
	var ang := fposmod(atan2(_aim.x, -_aim.y), TAU)        # 0 at top, clockwise
	var k := int(round(ang / TAU * cands.size())) % cands.size()
	_sel = cands[k]

func _draw_wheel() -> void:
	var sz := _ctl.get_viewport_rect().size
	var c := sz * 0.5
	_ctl.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.35))
	_ctl.draw_circle(c, 260.0, Color(UITheme.PAPER, 0.92))
	_ctl.draw_arc(c, 260.0, 0, TAU, 96, UITheme.INK, 3.0)
	_ctl.draw_arc(c, 150.0, 0, TAU, 64, UITheme.INK_SOFT, 1.5)
	var note := _ammo_note if _ammo_note != "" else "[R] change ammunition"
	var nf := UITheme.font("italic")
	var nw := nf.get_string_size(InputGlyphs.sub(note), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	_ctl.draw_string(nf, c + Vector2(-nw * 0.5, 300.0), InputGlyphs.sub(note), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UITheme.PAPER)
	_ctl.draw_arc(c, 252.0, 0, TAU, 96, UITheme.INK_SOFT, 1.0)
	for ring in [0, 1]:
		var idxs := []
		for i in _entries.size():
			if _entries[i].ring == ring:
				idxs.append(i)
		var r := 205.0 if ring == 0 else 105.0
		for j in idxs.size():
			var e: Dictionary = _entries[idxs[j]]
			var a := TAU * j / idxs.size()
			var pos := c + Vector2(sin(a), -cos(a)) * r
			var sel: bool = idxs[j] == _sel
			if sel:
				_ctl.draw_circle(pos, 46.0 if ring == 0 else 36.0, Color(UITheme.OXBLOOD, 0.85))
			var col := UITheme.PAPER if sel else UITheme.INK
			var f := UITheme.font("caps")
			var fs := 20 if ring == 0 else 17
			var tw := f.get_string_size(e.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_ctl.draw_string(f, pos - Vector2(tw * 0.5, 0), e.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			if e.sub != "":
				var f2 := UITheme.font("italic")
				var tw2 := f2.get_string_size(e.sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				_ctl.draw_string(f2, pos + Vector2(-tw2 * 0.5, 20), e.sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
	# pointer
	if _aim.length() > 10.0:
		_ctl.draw_line(c, c + _aim.limit_length(250.0), UITheme.OXBLOOD, 2.0)
	_ctl.draw_circle(c, 6.0, UITheme.INK)
