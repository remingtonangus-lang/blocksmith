extends SceneTree
## Fast stand-alone run of the poker self-test (no world boot), plus a smoke test of the table UI driven by
## simulated button presses (builds every control, draws the table, plays three hands, calls the stacked deck):
##   godot --headless --path frontier --script res://src/minigames/poker_selftest.gd
## The in-game path is `godot --headless --path frontier -- --pokertest` (hooked in MissionDirector._ready).

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var script = load("res://src/minigames/poker_engine.gd")
	if script == null or not script.can_instantiate():
		print("POKERTEST FAIL (engine script did not load)")
		quit(1)
		return
	var res: Dictionary = script.selftest()
	for l in res.lines:
		print(l)
	var ok: bool = res.ok
	# --- UI smoke: the real table, Ruth's turns answered by "clicking" buttons
	var pk = load("res://src/minigames/poker.gd").new()
	root.add_child(pk)
	var opts := {"force_ui": true, "players": [{"name": "Del Arceneaux", "style": "bluffer", "stack": 14.0},
		{"name": "Lyle Hask", "style": "plant", "stack": 25.0}, {"name": "Josiah Merrow", "style": "tight", "stack": 18.0}],
		"buyin": 10.0, "hands": 3, "seed": 42, "rig_hands": [2], "plant": 2, "dealer": "Abel Stroud", "hint": true,
		"pace": 0.0}
	var done := [false, {}]
	var runner := func():
		done[1] = await pk.play(opts)
		done[0] = true
	runner.call()
	var frames := 0
	var presses := 0
	while not done[0] and frames < 20000:
		await process_frame
		frames += 1
		if pk.eng != null and pk.eng.rigged and pk.eng.phase in ["bet1", "draw", "bet2"] and not pk.accused:
			pk._press("accuse")
		match pk.waiting:
			"bet":
				pk._press("check" if pk.btns.check.visible else "call")
				presses += 1
			"draw":
				pk.card_btns[0].button_pressed = true
				pk._press("draw")
				presses += 1
			"next":
				pk._press("next")
			"close":
				pk._press("close")
	var r: Dictionary = done[1]
	var ui_ok: bool = done[0] and r.get("caught", false) and r.get("hands", 0) == 2 and presses > 0 and pk.table != null
	print(("  ok    " if ui_ok else "  FAIL  ") + "table UI: %d presses over %d frames, result %s" % [presses, frames, JSON.stringify(r)])
	ok = ok and ui_ok
	print("POKERTEST %s (%d failed)" % ["PASS" if ok else "FAIL", res.fails + (0 if ui_ok else 1)])
	quit(0 if ok else 1)
