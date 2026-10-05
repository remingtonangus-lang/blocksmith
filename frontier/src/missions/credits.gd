extends CanvasLayer
## End credits on paper: the story's own credits, then every open licence the game ships under, read from
## LICENSES.md (engine and tools, generated-in-house work, and the CC0 assets grouped by source and author).
## Scrolls slowly; Enter / Esc / A skips. `entries()` is used by the mission bot to check the list is complete.

const LICENSES := "res://LICENSES.md"

static func entries() -> Array:
	var out := []
	var txt := FileAccess.get_file_as_string(LICENSES)
	if txt.is_empty():
		return out
	var section := ""
	for raw in txt.split("\n"):
		var ln := raw.strip_edges()
		if ln.begins_with("## "):
			section = ln.substr(3)
			continue
		if not ln.begins_with("|") or ln.begins_with("|---") or ln.begins_with("| ---"):
			continue
		var cols := []
		for c in ln.trim_prefix("|").trim_suffix("|").split("|"):
			cols.append(c.strip_edges())
		if cols.is_empty() or cols[0] in ["Item", "Asset (dest)", "Asset", "Sound", "Font", "File"]:
			continue
		out.append({"section": section, "cols": cols})
	return out

## The credit roll as lines: [text, style] (style: title, head, body, small, gap).
static func lines() -> Array:
	var l := []
	l.append(["SABLE RIVER", "title"])
	l.append(["An original story of the Sable River country, autumn 1899 to spring 1900", "small"])
	l.append(["", "gap"])
	for row in [["Story, dialogue and missions", "Written for this game; every character and place is invented"],
			["The Sable River country", "Generated from seed 1899: terrain, rivers, roads, rail, towns and interiors"],
			["People and horses", "Procedural characters, animation, and a horse built from its own anatomy"],
			["Firearms", "Ten fictional period designs, modelled and finished procedurally"],
			["Sound and score", "Synthesised effects and ambience, an original adaptive score, synthesised voices"]]:
		l.append([row[0], "head"])
		l.append([row[1], "body"])
	l.append(["", "gap"])
	l.append(["OPEN LICENCES", "title"])
	var by_section := {}
	var order := []
	for e in entries():
		if not by_section.has(e.section):
			by_section[e.section] = []
			order.append(e.section)
		by_section[e.section].append(e.cols)
	for sec in order:
		l.append([sec, "head"])
		var rows: Array = by_section[sec]
		if rows.size() > 0 and rows[0].size() >= 4:
			# assets: group by licence and source site, list authors
			var groups := {}
			for c in rows:
				var site := str(c[1]).replace("https://", "").split("/")[0]
				var key := "%s (%s)" % [site, c[2]]
				if not groups.has(key):
					groups[key] = {"n": 0, "authors": []}
				groups[key].n += 1
				for a in str(c[3]).split(","):
					var aa := a.strip_edges()
					if aa != "" and not groups[key].authors.has(aa):
						groups[key].authors.append(aa)
			for k in groups.keys():
				l.append(["%d assets from %s" % [groups[k].n, k], "body"])
				l.append([", ".join(groups[k].authors), "small"])
		else:
			for c in rows:
				l.append([" — ".join(c.slice(0, mini(c.size(), 3))), "small"])
		l.append(["", "gap"])
	l.append(["Thank you for riding with the Outfit.", "head"])
	return l

var _skip := false

func roll(instant := false) -> void:
	var ls := lines()
	Game.log_event("credits_roll", {"lines": ls.size(), "licences": entries().size()})
	if instant:
		return
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var was_paused := get_tree().paused
	get_tree().paused = true
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.045, 0.035, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(900, 0)
	add_child(col)
	for it in ls:
		var style: String = it[1]
		var lab: Label
		match style:
			"title":
				lab = UITheme.label(it[0], 64, "display", UITheme.PAPER, false)
			"head":
				lab = UITheme.label(it[0], 32, "caps", UITheme.BRASS, false)
			"body":
				lab = UITheme.label(it[0], 26, "body", UITheme.PAPER, false)
			"small":
				lab = UITheme.label(it[0], 20, "italic", Color(UITheme.PAPER, 0.75), false)
			_:
				lab = UITheme.label(" ", 30, "body", UITheme.PAPER, false)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size = Vector2(900, 0)
		col.add_child(lab)
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect().size
	col.position = Vector2((vp.x - 900.0) * 0.5, vp.y)
	var h := col.size.y
	while not _skip and col.position.y > -h:
		await get_tree().process_frame
		col.position.y -= get_process_delta_time() * 55.0
	get_tree().paused = was_paused

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause") or e.is_action_pressed("ui_accept") or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_A):
		_skip = true
		get_viewport().set_input_as_handled()
