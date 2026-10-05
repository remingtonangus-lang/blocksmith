extends CanvasLayer
## Five-card draw at a saloon table (MissionDirector.minigame("poker", opts)). Ruth against three or four players
## with their own habits (tight, loose, bluffer, a house plant), real hand evaluation and fixed-limit betting from
## poker_engine.gd, stakes drawn from Game.state.money, and a house dealer who can be caught stacking the deck.
## Paper-and-ink table drawn in code: felt, brass rim, name plates, procedurally drawn cards (no art assets).
##
## Controls: mouse; keyboard 1-5 pick discards, F fold, C check/call, B bet/raise, Enter draw, X call the deal,
## L leave; controller: D-pad between cards and buttons, A to press.
##
## opts: players [{name, style, stack (dollars)}], buyin (dollars from Ruth's purse), stake (dollars somebody fronts
##   her, repaid first), hands (max), seed, rig_hands [hand numbers], plant (seat index, Ruth is 0), mark,
##   dealer (name), hint (highlight the dealer's tells), auto (bots: everybody plays by style), can_leave.
## Returns {played, hands, net, stack, caught, accuse_hand, false_accusations, rigged_dealt, rigged_cost, busted,
##   left, biggest_pot, stacks: {name: dollars}}.

const PE = preload("res://src/minigames/poker_engine.gd")
const FELT := Color(0.12, 0.24, 0.17)
const FELT_DARK := Color(0.07, 0.15, 0.10)
const IVORY := Color(0.96, 0.93, 0.84)
const RED_INK := Color(0.62, 0.11, 0.08)
const FLAVOR := ["%s rubs a thumb down the edge of the deck, idle as a cat.", "Somebody upstairs drops a boot.",
	"The piano player starts a waltz and thinks better of it.", "%s counts his money again. It hasn't changed.",
	"A steamboat whistle comes up off the lake and goes on about it.", "%s orders whiskey and doesn't drink it.",
	"%s squints at his cards like they owe him rent.", "The lamp over the table gutters and steadies.",
	"%s taps the table twice for luck. It doesn't seem to hear him."]

var eng
var opts := {}
var auto := false
var result := {}
var dealer_name := "The dealer"
var hint := false
var can_leave := true
var rng := RandomNumberGenerator.new()
var root: Control
var table: Control
var log_box: RichTextLabel
var hold_label: Label
var status_label: Label
var cards_box: HBoxContainer
var card_btns: Array = []
var btns := {}
var waiting := ""                 # "bet", "draw", "next", "close" while Ruth's input is wanted
var _pending := ""
var _accuse_req := false
var accused := false
var accuse_cooldown := 0
var leave_after := false
var _reveal := false
var _we_paused := false
var pace := 1.0                   # scales the table's pauses (tests run it at 0)

func play(o: Dictionary) -> Dictionary:
	opts = o
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15
	auto = (bool(o.get("auto", false)) or Game.headless) and not bool(o.get("force_ui", false))
	pace = float(o.get("pace", 1.0))
	dealer_name = str(o.get("dealer", "The dealer"))
	hint = bool(o.get("hint", false))
	can_leave = bool(o.get("can_leave", true))
	rng.seed = int(o.get("seed", 1899)) + 5
	var st = Game.state
	var purse: float = float(st.money) if st else 20.0
	var buyin_c := int(round(float(o.get("buyin", 10.0)) * 100.0))
	var from_purse := mini(buyin_c, int(floor(purse * 100.0)))
	var stake_c := int(round(float(o.get("stake", 0.0)) * 100.0))
	var loan := maxi(stake_c - from_purse, 0)
	var players: Array = [{"name": str(o.get("player_name", "Ruth")), "style": "steady", "stack": from_purse + loan, "player": true}]
	for p in o.get("players", []):
		players.append({"name": str(p.get("name", "Stranger")), "style": str(p.get("style", "steady")),
			"stack": int(round(float(p.get("stack", 10.0)) * 100.0))})
	eng = PE.new()
	eng.setup(players, int(o.get("seed", 1899)), {"rig_hands": o.get("rig_hands", []), "plant": int(o.get("plant", -1)),
		"mark": int(o.get("mark", 0)), "button": int(o.get("button", players.size() - 1))})
	result = {"played": true, "hands": 0, "net": 0.0, "stack": 0.0, "caught": false, "accuse_hand": -1,
		"false_accusations": 0, "rigged_dealt": 0, "rigged_cost": 0.0, "busted": false, "left": false, "biggest_pot": 0.0}
	if from_purse + loan <= 0:
		result.played = false
		return result
	if not auto:
		_build_ui()
		_pause(true)
		_log("[i]%s shuffles. Ante a quarter; bets fifty cents before the draw, a dollar after. Three raises.[/i]" % dealer_name)
	var max_hands := int(o.get("hands", 8))
	var auto_accuse_asked := false
	while result.hands < max_hands and not accused and not leave_after:
		var before: int = eng.seats[0].stack
		if not eng.start_hand():
			break
		result.hands += 1
		_reveal = false
		if eng.rigged:
			result.rigged_dealt += 1
		_narrate()
		_refresh()
		if not auto:
			await _sleep(0.6)
		var steps := 0
		while eng.phase != "done" and steps < 500:
			steps += 1
			if _accuse_req:
				_accuse_req = false
				_accuse()
				if accused:
					break
			if auto and eng.rigged and not auto_accuse_asked and accuse_cooldown == 0:
				auto_accuse_asked = true
				var md = Game.get("missions")
				var call_it: bool = md.auto_choice(2) == 0 if md != null else true
				if call_it:
					_accuse()
					break
			if eng.is_player_turn() and not auto:
				await _player_turn()
			else:
				if not auto:
					await _sleep(0.45 + rng.randf() * 0.5)
					if _accuse_req:
						continue
				eng.auto_step()
			_narrate()
			_refresh()
		if accused:
			_refresh()
			break
		var won := 0
		for w in eng.last_result.get("winners", []):
			won += int(w.amount)
		result.biggest_pot = maxf(result.biggest_pot, won / 100.0)
		var after: int = eng.seats[0].stack
		if eng.last_result.get("rigged", false) and after < before:
			result.rigged_cost += (before - after) / 100.0
		_reveal = eng.last_result.get("showdown", false)
		_refresh()
		accuse_cooldown = maxi(accuse_cooldown - 1, 0)
		if eng.seats[0].stack <= 0:
			result.busted = true
			_log("[i]Your last coin goes into the pot and stays there.[/i]")
			break
		if not auto and result.hands < max_hands and not leave_after:
			waiting = "next"
			_update_buttons()
			var t := 0.0
			_pending = ""
			while _pending == "" and t < 6.0 * pace and not _accuse_req:
				await get_tree().process_frame
				t += get_process_delta_time()
			if _pending == "leave":
				leave_after = true
			waiting = ""
	# settle up: the stake is repaid first, the rest goes back in Ruth's purse
	var final: int = eng.seats[0].stack
	var repay := mini(loan, final)
	var net_c := (final - repay) - from_purse
	if st:
		st.add_money(net_c / 100.0)
	result.net = net_c / 100.0
	result.stack = final / 100.0
	result.loan = loan / 100.0
	result.loan_repaid = repay / 100.0
	result.left = leave_after
	var stacks := {}
	for s in eng.seats:
		stacks[s.name] = s.stack / 100.0
	result.stacks = stacks
	if not auto:
		_log("[b]You rise from the table %s.[/b]" % ("$%.2f ahead" % result.net if result.net > 0.005 else ("$%.2f lighter" % -result.net if result.net < -0.005 else "even")))
		waiting = "close"
		_update_buttons()
		_pending = ""
		while _pending == "":
			await get_tree().process_frame
		_pause(false)
	return result

func _sleep(t: float) -> void:
	if pace <= 0.0:
		await get_tree().process_frame
		return
	await get_tree().create_timer(t * pace, true).timeout

func _pause(on: bool) -> void:
	if on:
		_we_paused = not get_tree().paused
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if _we_paused:
			get_tree().paused = false
		if not Game.headless and (Game.get("menus") == null or Game.menus.stack.is_empty()):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(_dt: float) -> void:
	# the pause menu can unpause the tree underneath us: keep the table paused while it's up
	if root and not auto and Game.get("menus") != null and Game.menus.stack.is_empty() and not get_tree().paused:
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _player_turn() -> void:
	waiting = "draw" if eng.phase == "draw" else "bet"
	_pending = ""
	_update_buttons()
	while _pending == "" and not _accuse_req:
		await get_tree().process_frame
	var a := _pending
	_pending = ""
	var was := waiting
	waiting = ""
	if a == "" or _accuse_req:
		return
	if a == "leave":
		leave_after = true
		a = "fold" if was == "bet" else "pat"
	if was == "draw":
		var idx := []
		if a != "pat":
			for k in card_btns.size():
				if card_btns[k].button_pressed:
					idx.append(k)
		eng.draw(0, idx)
		for b in card_btns:
			b.button_pressed = false
	else:
		eng.act(0, a)

func _accuse() -> void:
	if eng.phase == "done" or eng.phase == "idle" or accuse_cooldown > 0:
		return
	if eng.rigged:
		result.caught = true
		result.accuse_hand = eng.hand_no
		accused = true
		eng.void_hand()
		_log("[color=#%s][b]You lay your hand flat on the felt and call the deal.[/b] %s goes still, the deck cupped in a hand that won't open.[/color]" % [RED_INK.to_html(false), dealer_name])
	else:
		result.false_accusations += 1
		accuse_cooldown = 2
		_log("[i]You call the deal. %s turns the deck over, slow, card by card. Nothing. The table goes quiet and stays that way.[/i]" % dealer_name)
	_refresh()

# ------------------------------------------------------------------ narration
func _money(c: int) -> String:
	return "$%.2f" % (c / 100.0)

func _narrate() -> void:
	for ev in eng.events:
		var who: String = eng.seats[ev.seat].name if ev.seat >= 0 and ev.seat < eng.seats.size() else ""
		var you: bool = ev.seat == 0
		match ev.kind:
			"deal":
				_log("[color=#%s]— Hand %d —[/color]  %s deals." % [UITheme.INK_SOFT.to_html(false), eng.hand_no, dealer_name])
			"tell_deal":
				var t := "%s squares the deck twice against the felt before he deals, neat as a bank clerk." % dealer_name
				_log(("[color=#%s][b]%s[/b][/color]" % [RED_INK.to_html(false), t]) if hint else t)
			"tell_draw":
				var t2 := "%s's left hand stays low on the deck while he gives %s his cards." % [dealer_name, who]
				_log(("[color=#%s][b]%s[/b][/color]" % [RED_INK.to_html(false), t2]) if hint else t2)
			"flavor":
				var f: String = FLAVOR[rng.randi() % FLAVOR.size()]
				if f.contains("%s"):
					var others := []
					for i in range(1, eng.seats.size()):
						if not eng.seats[i].out:
							others.append(eng.seats[i].name)
					f = f % (dealer_name if f.begins_with("%s rubs") else (others[rng.randi() % others.size()] if others.size() > 0 else dealer_name))
				_log("[i]%s[/i]" % f)
			"fold":
				_log("%s fold%s." % ["You" if you else who, "" if you else "s"])
			"check":
				_log("%s check%s." % ["You" if you else who, "" if you else "s"])
			"call":
				_log("%s call%s, %s." % ["You" if you else who, "" if you else "s", _money(int(ev.text))])
			"bet":
				_log("%s bet%s %s." % ["You" if you else who, "" if you else "s", _money(int(ev.text))])
			"raise":
				_log("%s raise%s — %s in." % ["You" if you else who, "" if you else "s", _money(int(ev.text))])
			"draw":
				var n := int(ev.text)
				if n == 0:
					_log("%s stand%s pat." % ["You" if you else who, "" if you else "s"])
				else:
					_log("%s draw%s %s." % ["You" if you else who, "" if you else "s", ["", "one", "two", "three", "four"][n]])
			"result":
				var r: Dictionary = eng.last_result
				var ws: Array = r.get("winners", [])
				if ws.is_empty():
					continue
				for w in ws:
					var nm: String = "You take" if w.seat == 0 else "%s takes" % eng.seats[w.seat].name
					if r.showdown:
						_log("[b]%s %s[/b] with %s." % [nm, _money(w.amount), w.hand])
					else:
						_log("[b]%s %s.[/b] Nobody calls." % [nm, _money(w.amount)])
	eng.events.clear()

func _log(text: String) -> void:
	if log_box == null:
		return
	log_box.append_text(text + "\n")

# ------------------------------------------------------------------ UI
func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.045, 0.035, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	table = TableView.new()
	table.game = self
	table.anchor_right = 0.72
	table.anchor_bottom = 1.0
	table.offset_bottom = -170
	root.add_child(table)
	# observations: what Ruth notices at the table
	var side: PanelContainer = _paper(Vector2.ZERO)
	side.anchor_left = 0.72
	side.anchor_right = 1.0
	side.anchor_bottom = 1.0
	side.offset_left = 8
	side.offset_right = -16
	side.offset_top = 16
	side.offset_bottom = -16
	root.add_child(side)
	var sv := VBoxContainer.new()
	side.add_child(sv)
	sv.add_child(UITheme.label("At the Table", 34, "display", UITheme.INK, false))
	var sub := UITheme.label("What you notice, hand by hand", 20, "italic", UITheme.INK_SOFT, false)
	sv.add_child(sub)
	sv.add_child(HSeparator.new())
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.add_theme_font_override("normal_font", UITheme.font("body"))
	log_box.add_theme_font_override("italics_font", UITheme.font("italic"))
	log_box.add_theme_font_override("bold_font", UITheme.font("serif_bold"))
	for k in ["normal_font_size", "italics_font_size", "bold_font_size"]:
		log_box.add_theme_font_size_override(k, 20)
	log_box.add_theme_color_override("default_color", UITheme.INK)
	sv.add_child(log_box)
	# Ruth's hand and the actions
	var bar: PanelContainer = _paper(Vector2.ZERO)
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.anchor_right = 0.72
	bar.offset_top = -166
	bar.offset_left = 16
	bar.offset_bottom = -16
	root.add_child(bar)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 18)
	bar.add_child(bh)
	var left := VBoxContainer.new()
	bh.add_child(left)
	hold_label = UITheme.label("", 22, "italic", UITheme.INK, false)
	left.add_child(hold_label)
	cards_box = HBoxContainer.new()
	cards_box.add_theme_constant_override("separation", 6)
	left.add_child(cards_box)
	for k in 5:
		var cb := CardButton.new()
		cb.game = self
		cb.idx = k
		cb.custom_minimum_size = Vector2(66, 98)
		cb.toggle_mode = true
		cb.flat = true
		cb.focus_mode = Control.FOCUS_ALL
		cb.toggled.connect(func(_on): cb.queue_redraw())
		cards_box.add_child(cb)
		card_btns.append(cb)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(right)
	status_label = UITheme.label("", 22, "body", UITheme.INK_SOFT, false)
	right.add_child(status_label)
	var row1 := HFlowContainer.new()
	row1.add_theme_constant_override("h_separation", 4)
	right.add_child(row1)
	for spec in [["fold", "Fold  [F]"], ["check", "Check  [C]"], ["call", "Call  [C]"], ["bet", "Bet  [B]"],
			["raise", "Raise  [B]"], ["draw", "Draw  [Enter]"], ["pat", "Stand pat  [Enter]"], ["next", "Next hand  [Enter]"],
			["accuse", "Call the deal  [X]"], ["leave", "Leave  [L]"], ["close", "Rise from the table  [Enter]"]]:
		var key: String = spec[0]
		var b := Button.new()
		b.text = spec[1]
		b.flat = true
		b.add_theme_font_override("font", UITheme.font("caps"))
		b.add_theme_font_size_override("font_size", 24)
		b.add_theme_color_override("font_color", UITheme.INK)
		b.add_theme_color_override("font_hover_color", UITheme.OXBLOOD)
		b.add_theme_color_override("font_focus_color", UITheme.OXBLOOD)
		b.add_theme_color_override("font_disabled_color", Color(UITheme.INK, 0.3))
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color(UITheme.OXBLOOD, 0.1)
		focus.border_color = UITheme.OXBLOOD
		focus.border_width_bottom = 3
		b.add_theme_stylebox_override("focus", focus)
		b.pressed.connect(func(): _press(key))
		row1.add_child(b)
		btns[key] = b
	_update_buttons()

func _paper(min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.PAPER
	sb.border_color = UITheme.INK
	sb.set_border_width_all(3)
	sb.set_content_margin_all(16)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 12
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = min_size
	return p

func _press(key: String) -> void:
	if key == "accuse":
		if eng.phase not in ["done", "idle"] and accuse_cooldown == 0:
			_accuse_req = true
		return
	if key == "leave" and not can_leave:
		return
	if waiting == "":
		return
	if Game.audio and Game.audio.has_method("ui"):
		Game.audio.ui("tick")
	_pending = key

func _unhandled_input(e: InputEvent) -> void:
	if root == null or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: int = e.physical_keycode
	var handled := true
	if k >= KEY_1 and k <= KEY_5 and waiting == "draw":
		var b: Button = card_btns[k - KEY_1]
		b.button_pressed = not b.button_pressed
	elif k == KEY_F and waiting == "bet" and btns.fold.visible:
		_press("fold")
	elif k == KEY_C and waiting == "bet":
		_press("check" if btns.check.visible else "call")
	elif k == KEY_B and waiting == "bet":
		if btns.bet.visible and not btns.bet.disabled:
			_press("bet")
		elif btns.raise.visible and not btns.raise.disabled:
			_press("raise")
	elif (k == KEY_ENTER or k == KEY_KP_ENTER) and waiting in ["draw", "next", "close"]:
		if waiting == "draw":
			var any := card_btns.any(func(b): return b.button_pressed)
			_press("draw" if any else "pat")
		else:
			_press(waiting)
	elif k == KEY_X:
		_press("accuse")
	elif k == KEY_L and waiting in ["bet", "draw", "next"]:
		_press("leave")
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()

func _update_buttons() -> void:
	if root == null:
		return
	var lg: Dictionary = eng.legal(0) if waiting == "bet" else {}
	for key in btns.keys():
		btns[key].visible = false
		btns[key].disabled = false
	if waiting == "bet":
		for a in ["fold", "check", "call", "bet", "raise"]:
			if lg.has(a):
				btns[a].visible = true
				if a in ["call", "bet", "raise"]:
					btns[a].text = "%s %s  [%s]" % [a.capitalize(), _money(int(lg[a])), "C" if a == "call" else "B"]
	elif waiting == "draw":
		btns.draw.visible = true
		btns.pat.visible = true
	elif waiting == "next":
		btns.next.visible = true
	elif waiting == "close":
		btns.close.visible = true
	btns.accuse.visible = waiting != "close"
	btns.accuse.disabled = accuse_cooldown > 0 or eng.phase in ["done", "idle"]
	btns.leave.visible = can_leave and waiting in ["bet", "draw", "next"]
	for cb in card_btns:
		cb.disabled = waiting != "draw"
		cb.focus_mode = Control.FOCUS_ALL if waiting == "draw" else Control.FOCUS_NONE
	var first: Control = null
	if waiting == "draw":
		first = card_btns[0]
	else:
		for key in ["check", "call", "next", "close", "fold"]:
			if btns[key].visible:
				first = btns[key]
				break
	if first and first.is_inside_tree():
		first.grab_focus.call_deferred()
	_refresh()

func _refresh() -> void:
	if root == null:
		return
	table.queue_redraw()
	for cb in card_btns:
		cb.queue_redraw()
	var me: Dictionary = eng.seats[0]
	if me.hand.size() == 5:
		hold_label.text = "You hold %s." % PE.hand_name(PE.eval5(me.hand))
	match waiting:
		"bet":
			var lg: Dictionary = eng.legal(0)
			status_label.text = ("%s to you." % _money(int(lg.call))) if lg.has("call") else "Your turn."
		"draw":
			status_label.text = "Choose cards to throw away (up to three; four if you keep an ace)."
		"next":
			status_label.text = "Next hand in a moment."
		"close":
			status_label.text = "The game breaks up."
		_:
			status_label.text = "Purse at the table: %s" % _money(int(me.stack))

## Cards are drawn, not loaded: an ivory face with corner indices and pips, or a back in oxblood lattice.
func draw_card(ci: CanvasItem, r: Rect2, c: int, face_up: bool, dim := false) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(r.size.x * 0.1))
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 3
	sb.border_color = UITheme.INK
	sb.set_border_width_all(1)
	if not face_up:
		sb.bg_color = UITheme.OXBLOOD
		ci.draw_style_box(sb, r)
		var inner := r.grow(-r.size.x * 0.1)
		ci.draw_rect(inner, UITheme.BRASS, false, 1.0)
		var step := r.size.x * 0.16
		var y := inner.position.y + step * 0.5
		var row := 0
		while y < inner.end.y - step * 0.3:
			var x := inner.position.x + step * (0.5 if row % 2 == 0 else 1.0)
			while x < inner.end.x - step * 0.3:
				var d := step * 0.32
				ci.draw_colored_polygon(PackedVector2Array([Vector2(x, y - d), Vector2(x + d, y), Vector2(x, y + d), Vector2(x - d, y)]), Color(UITheme.BRASS, 0.55))
				x += step
			y += step * 0.6
			row += 1
		return
	sb.bg_color = IVORY.darkened(0.25) if dim else IVORY
	ci.draw_style_box(sb, r)
	var rk := PE.rank(c)
	var su := PE.suit(c)
	var col := RED_INK if su in [1, 2] else UITheme.INK
	if dim:
		col = Color(col, 0.55)
	var f := UITheme.font("serif_bold")
	var fs := int(r.size.x * 0.26)
	var label: String = PE.RANK_LABEL[rk]
	ci.draw_string(f, r.position + Vector2(r.size.x * 0.08, fs * 1.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_suit(ci, r.position + Vector2(r.size.x * 0.17, fs * 1.45), r.size.x * 0.14, su, col)
	ci.draw_string(f, r.end - Vector2(r.size.x * 0.08 + f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, r.size.x * 0.08), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	var mid := r.get_center() + Vector2(0, r.size.y * 0.04)
	if rk >= 9 and rk <= 11:
		# court cards: a ruled frame, the letter in display type, pips at the corners of the frame
		var fr := Rect2(r.position + r.size * Vector2(0.24, 0.2), r.size * Vector2(0.52, 0.6))
		ci.draw_rect(fr, Color(col, 0.7), false, 1.5)
		ci.draw_rect(fr.grow(-3), Color(UITheme.BRASS, 0.5), false, 1.0)
		var df := UITheme.font("display")
		var dfs := int(r.size.x * 0.42)
		var letter: String = ["J", "Q", "K"][rk - 9]
		var ls := df.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, dfs)
		ci.draw_string(df, mid + Vector2(-ls.x * 0.5, dfs * 0.32), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, dfs, col)
		draw_suit(ci, fr.position + Vector2(fr.size.x - 7, 8), r.size.x * 0.09, su, col)
		draw_suit(ci, fr.end - Vector2(fr.size.x - 7, 8), r.size.x * 0.09, su, col)
	else:
		draw_suit(ci, mid, r.size.x * (0.5 if rk == 12 else 0.34), su, col)

## Suit marks from circles and polygons (no font glyphs needed).
func draw_suit(ci: CanvasItem, c: Vector2, s: float, su: int, col: Color) -> void:
	match su:
		1:   # hearts
			ci.draw_circle(c + Vector2(-s * 0.25, -s * 0.12), s * 0.28, col)
			ci.draw_circle(c + Vector2(s * 0.25, -s * 0.12), s * 0.28, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.52, -s * 0.04), c + Vector2(s * 0.52, -s * 0.04), c + Vector2(0, s * 0.55)]), col)
		2:   # diamonds
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.55), c + Vector2(s * 0.4, 0), c + Vector2(0, s * 0.55), c + Vector2(-s * 0.4, 0)]), col)
		0:   # spades
			ci.draw_circle(c + Vector2(-s * 0.25, s * 0.1), s * 0.27, col)
			ci.draw_circle(c + Vector2(s * 0.25, s * 0.1), s * 0.27, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.51, s * 0.04), c + Vector2(s * 0.51, s * 0.04), c + Vector2(0, -s * 0.55)]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, s * 0.1), c + Vector2(-s * 0.18, s * 0.58), c + Vector2(s * 0.18, s * 0.58)]), col)
		3:   # clubs
			ci.draw_circle(c + Vector2(0, -s * 0.24), s * 0.24, col)
			ci.draw_circle(c + Vector2(-s * 0.26, s * 0.1), s * 0.24, col)
			ci.draw_circle(c + Vector2(s * 0.26, s * 0.1), s * 0.24, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, s * 0.05), c + Vector2(-s * 0.18, s * 0.58), c + Vector2(s * 0.18, s * 0.58)]), col)

## The table: felt oval with a brass rim, a name plate per seat, face-down hands (face up at a showdown), the pot.
class TableView extends Control:
	var game

	func _draw() -> void:
		if game == null or game.eng == null:
			return
		var eng = game.eng
		var sz := size
		var c := sz * 0.5 + Vector2(0, 10)
		var rx := sz.x * 0.38
		var ry := sz.y * 0.34
		var rim := PackedVector2Array()
		var felt := PackedVector2Array()
		for i in 64:
			var a := TAU * i / 64.0
			rim.append(c + Vector2(cos(a) * (rx + 22), sin(a) * (ry + 22)))
			felt.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(rim, Color(0.30, 0.19, 0.10))
		draw_polyline(rim + PackedVector2Array([rim[0]]), UITheme.BRASS, 2.0, true)
		draw_colored_polygon(felt, FELT)
		draw_polyline(felt + PackedVector2Array([felt[0]]), FELT_DARK, 4.0, true)
		var f := UITheme.font("caps")
		var fb := UITheme.font("serif_bold")
		# the house
		var house := "Dealt by %s" % game.dealer_name
		var hs := f.get_string_size(house, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		draw_string(f, c + Vector2(-hs.x * 0.5, -ry + 40), house, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(UITheme.PAPER, 0.8))
		# the pot
		var pot: int = eng.pot()
		if pot > 0:
			var chips := mini(pot / 25, 24)
			for k in chips:
				var off := Vector2((k % 6) * 12 - 30, -(k / 6) * 6)
				draw_circle(c + off + Vector2(0, 30), 9, UITheme.OXBLOOD if k % 3 == 0 else (UITheme.PAPER if k % 3 == 1 else UITheme.SLATE))
				draw_arc(c + off + Vector2(0, 30), 9, 0, TAU, 16, UITheme.INK, 1.0)
			var pt := "Pot  $%.2f" % (pot / 100.0)
			var ps := fb.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30)
			draw_string(fb, c + Vector2(-ps.x * 0.5, -6), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UITheme.PAPER)
		var n: int = eng.seats.size()
		for i in n:
			var s: Dictionary = eng.seats[i]
			var a := PI * 0.5 + TAU * i / n
			var dir := Vector2(cos(a), sin(a))
			var plate_c := c + Vector2(dir.x * (rx + 20), dir.y * (ry + 30))
			var pr := Rect2(plate_c - Vector2(120, 34), Vector2(240, 68))
			if i == 0:
				pr.position.y = sz.y - 76
			var paper := UITheme.PAPER if not s.out else UITheme.PAPER.darkened(0.4)
			draw_rect(pr, paper)
			draw_rect(pr, UITheme.OXBLOOD if eng.to_act == i else UITheme.INK, false, 3.0 if eng.to_act == i else 1.5)
			draw_string(fb, pr.position + Vector2(10, 26), s.name, HORIZONTAL_ALIGNMENT_LEFT, 220, 22, UITheme.INK)
			var sub := "$%.2f" % (s.stack / 100.0)
			if s.out:
				sub = "out of money"
			elif s.folded:
				sub += "  · folded"
			elif s.all_in:
				sub += "  · all in"
			elif s.last != "":
				sub += "  · " + s.last
			draw_string(UITheme.font("italic"), pr.position + Vector2(10, 54), sub, HORIZONTAL_ALIGNMENT_LEFT, 220, 19, UITheme.INK_SOFT)
			if eng.button == i:
				var bc := pr.position + Vector2(pr.size.x + 16, 20)
				draw_circle(bc, 13, UITheme.PAPER)
				draw_arc(bc, 13, 0, TAU, 20, UITheme.INK, 1.5)
				draw_string(fb, bc + Vector2(-6, 7), "D", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UITheme.INK)
			if i == 0 or s.out or s.hand.size() < 5:
				continue
			# hands toward the middle of the table
			var hc := c + Vector2(dir.x * rx * 0.62, dir.y * ry * 0.55)
			var cw := 44.0
			var show: bool = game._reveal and not s.folded
			for k in 5:
				var cr := Rect2(hc + Vector2((k - 2.5) * (cw * 0.62), -cw * 0.7), Vector2(cw, cw * 1.45))
				game.draw_card(self, cr, s.hand[k], show, s.folded)

## One of Ruth's five cards: click / A / number key to mark it for the draw (it stands up, stamped DISCARD).
class CardButton extends Button:
	var game
	var idx := 0

	func _draw() -> void:
		if game == null or game.eng == null:
			return
		var s: Dictionary = game.eng.seats[0]
		if s.hand.size() < 5:
			return
		var lift := 0.0 if button_pressed else 12.0
		var r := Rect2(Vector2(2, lift), Vector2(size.x - 4, size.y - 14))
		game.draw_card(self, r, s.hand[idx], true, s.folded)
		if button_pressed:
			var f := UITheme.font("caps")
			draw_string(f, r.position + Vector2(4, r.size.y * 0.62), "DISCARD", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8, 13, RED_INK)
		if has_focus():
			draw_rect(r.grow(2), UITheme.OXBLOOD, false, 2.0)
