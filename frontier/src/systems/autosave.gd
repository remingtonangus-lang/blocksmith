extends Node
## Saving: an autosave every five minutes of play, on fast travel and when a mission ends (MissionDirector), each one
## skipped (and retried a little later) while there's shooting or the law is hunting her; manual saves from the
## pause menu anywhere outside combat, refused with a reason while in a fight or wanted at level 2 or more.
## The new world state rides in WorldState.flags (horse bond, camp ledger and stock, discovered places, found
## story places, hold-up counts); WorldState.loaded tells the live systems to pick it back up.

const EVERY := 300.0
const RETRY := 30.0

var _t := EVERY
var last_slot := ""
var last_reason := ""
var count := 0

func _ready() -> void:
	Game.set_meta("autosave", self)

var _hurt_at := -100.0
var _shot_at := -100.0
var _hooked: Node = null

## Hurt by someone or fired her gun lately (weather and hunger don't count).
func _hook() -> void:
	var p = Game.player
	if p == null or _hooked == p:
		return
	_hooked = p
	if p.damageable:
		p.damageable.damaged.connect(func(info):
			if info.get("attacker") != null:
				_hurt_at = Time.get_ticks_msec() / 1000.0)
	if p.get("gun") != null:
		p.gun.fired.connect(func(_w, _o, _d): _shot_at = Time.get_ticks_msec() / 1000.0)

func _process(dt: float) -> void:
	_hook()
	if Game.state == null or Game.player == null or Game.args.has("bot"):
		return
	_t -= dt
	if _t <= 0.0:
		_t = EVERY if autosave("timer") else RETRY

## Why Ruth can't save right now ("" when she can).
func refusal() -> String:
	var st = Game.state
	if st == null:
		return "Nothing to save."
	if int(st.wanted) >= 2:
		return "Not with the law on your trail. Lose them first."
	if in_combat():
		return "Not while there's shooting."
	return ""

## A fight is on: someone hostile is after her nearby, she was hurt or fired lately, or a posse has closed in.
func in_combat() -> bool:
	var p = Game.player
	if p == null:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - _hurt_at < 8.0 or now - _shot_at < 5.0:
		return true
	for h in p.get_tree().get_nodes_in_group("humans"):
		if not h.alive or h.brain == null:
			continue
		if h.brain.state in [h.brain.State.COMBAT, h.brain.State.FIST] and h.brain.target == p \
				and h.global_position.distance_to(p.global_position) < 150.0:
			return true
	if Game.has_meta("hunters"):
		var hu = Game.get_meta("hunters")
		for m in hu.members():
			if m.mode == "foot":
				return true
	return false

## The autosave slot; returns true when it saved.
func autosave(why: String) -> bool:
	var r := refusal()
	if r != "":
		last_reason = r
		Game.log_event("autosave_skipped", {"why": why, "reason": r})
		return false
	if Game.state.save_game("auto"):
		count += 1
		last_slot = "auto"
		Game.log_event("autosave", {"why": why})
		if Game.hud and not Game.headless and why != "mission":
			Game.hud.notice("Saved", 1.5)
		return true
	return false

## The pause menu's Save Game. Returns true when it saved; otherwise says why.
func manual_save(slot := "manual") -> bool:
	var r := refusal()
	if r != "":
		last_reason = r
		Game.say(r, 3.0)
		Game.log_event("save_refused", {"reason": r})
		return false
	var ok: bool = Game.state.save_game(slot)
	if ok:
		last_slot = slot
		Game.say("Game saved", 2.5)
	return ok
