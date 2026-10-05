extends CanvasLayer
## "Hold her still": a short steadiness minigame on paper (Doc setting the Ybarra girl's leg while Ruth holds her).
## A needle wanders on a ruled bar (the child flinching, plus the doctor's tremor); keep it inside the inked band
## with left/right (A/D, arrows, stick or D-pad) until the count is done. Returns {ok, score} — score is the share
## of the time spent inside the band; ok when it's at least `pass` (default 0.6).
## opts: seconds (8), band (half-width 0..1, default 0.22), tremor (0..1 extra wander), title, auto, pace.

var opts := {}
var _needle := 0.0
var _vel := 0.0
var _t := 0.0
var _inside := 0.0
var _bar: Control
var _label: Label
var _done := false
var _rng := RandomNumberGenerator.new()
var _we_paused := false

func play(o: Dictionary) -> Dictionary:
	opts = o
	var seconds := float(o.get("seconds", 8.0))
	var band := float(o.get("band", 0.22))
	var tremor := float(o.get("tremor", 0.3))
	var pass_at := float(o.get("pass", 0.6))
	_rng.seed = int(o.get("seed", 77))
	if bool(o.get("auto", false)) or Game.headless:
		return {"ok": true, "score": 1.0, "auto": true}
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 16
	_build(str(o.get("title", "Hold her still")))
	_we_paused = not get_tree().paused
	get_tree().paused = true
	while _t < seconds:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		_t += dt
		var push := Input.get_axis("move_left", "move_right")
		# wander: a slow drift that flips, flinches, and the doctor's hands
		_vel += (_rng.randf_range(-1.0, 1.0) * (1.6 + tremor * 3.0) - _needle * 0.6) * dt
		if _rng.randf() < dt * 0.5:
			_vel += _rng.randf_range(-0.9, 0.9)            # a flinch
		_vel += push * 3.2 * dt
		_vel *= 1.0 - minf(dt * 1.8, 0.5)
		_needle = clampf(_needle + _vel * dt, -1.0, 1.0)
		if absf(_needle) <= band:
			_inside += dt
		_label.text = ["One...", "Two...", "Three — now. Hold her."][mini(int(_t / seconds * 3.0), 2)]
		_bar.set_meta("needle", _needle)
		_bar.set_meta("band", band)
		_bar.queue_redraw()
	var score := _inside / maxf(seconds, 0.01)
	if _we_paused:
		get_tree().paused = false
	return {"ok": score >= pass_at, "score": snappedf(score, 0.01)}

func _build(title: String) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.PAPER
	sb.border_color = UITheme.INK
	sb.set_border_width_all(3)
	sb.set_content_margin_all(26)
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.custom_minimum_size = Vector2(720, 0)
	root.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UITheme.label(title, 42, "display", UITheme.INK, false))
	v.add_child(UITheme.label("Keep the needle inside the inked band:  A / D, arrows or the stick.", 22, "italic", UITheme.INK_SOFT, false))
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(660, 90)
	_bar.draw.connect(func():
		var w := _bar.size.x
		var h := _bar.size.y
		var band: float = _bar.get_meta("band", 0.2)
		var nd: float = _bar.get_meta("needle", 0.0)
		_bar.draw_rect(Rect2(0, h * 0.35, w, h * 0.3), Color(UITheme.INK, 0.08))
		_bar.draw_rect(Rect2(w * 0.5 - band * w * 0.5, h * 0.3, band * w, h * 0.4), Color(UITheme.INK, 0.25))
		_bar.draw_rect(Rect2(w * 0.5 - band * w * 0.5, h * 0.3, band * w, h * 0.4), UITheme.INK, false, 2.0)
		for i in 21:
			var x := w * i / 20.0
			_bar.draw_line(Vector2(x, h * 0.66), Vector2(x, h * (0.74 if i % 5 == 0 else 0.7)), UITheme.INK, 1.0)
		var nx := w * 0.5 + nd * w * 0.5
		var col := UITheme.INK if absf(nd) <= band else UITheme.OXBLOOD
		_bar.draw_line(Vector2(nx, h * 0.12), Vector2(nx, h * 0.88), col, 4.0)
		_bar.draw_circle(Vector2(nx, h * 0.12), 7.0, col))
	v.add_child(_bar)
	_label = UITheme.label("", 30, "serif_bold", UITheme.OXBLOOD, false)
	v.add_child(_label)
