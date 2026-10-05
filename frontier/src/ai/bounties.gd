extends Node3D
## Sheriff's bounty board (one per county seat). Posters name an outlaw, his crime, where he was last seen and the
## reward. Accepting sets a waypoint; near the hideout the outlaw and his gang appear. Kill him for the posted
## reward, or break the gang and take him alive (he surrenders when broken: interact to take him into custody)
## for 1.5x and Standing. Turn-in happens automatically on capture/kill (the county wires the money).

const FIRST := ["Jubal", "Lyman", "Cass", "Dutch", "Royal", "Elam", "Virgil", "Hollis", "Mose", "Tate"]
const LAST := ["Ketchum", "Barrow", "Strick", "Pardee", "Voss", "Lacey", "Grigsby", "Kincannon", "Rusk", "Toller"]
const CRIMES := ["horse theft", "the murder of a freight agent", "robbing the Coldwater payroll", "arson at a homestead",
	"cattle rustling", "shooting a deputy", "stage robbery on the Linden road"]

var town_id := ""
var posters: Array = []        # [{name, crime, reward, pos, gang}]
var active: Dictionary = {}
var rng := RandomNumberGenerator.new()

func setup(tid: String) -> void:
	town_id = tid
	rng.seed = hash(tid) + 77
	add_to_group("interactable")
	for i in 3:
		posters.append(_make_poster())

func _make_poster() -> Dictionary:
	var w: WorldData = Game.world
	var p := Vector3.ZERO
	for attempt in 30:
		p = Vector3(rng.randf_range(-3600, 3600), 0, rng.randf_range(-3600, 3600))
		if w.is_water(p.x, p.z) or (1.0 - w.normal(p.x, p.z).y) > 0.35:
			continue
		var near := w.nearest_settlement(p.x, p.z)
		if near.is_empty() or Vector2(near.x - p.x, near.z - p.z).length() > float(near.r) + 500.0:
			break
	p.y = w.height(p.x, p.z)
	return {"name": "%s %s" % [FIRST[rng.randi() % FIRST.size()], LAST[rng.randi() % LAST.size()]],
		"crime": CRIMES[rng.randi() % CRIMES.size()], "reward": float(rng.randi_range(4, 12) * 5),
		"pos": p, "gang": rng.randi_range(1, 4)}

func interact_prompt() -> String:
	if not active.is_empty():
		return "Bounty: %s (in progress)" % active.name
	return "Read the bounty board" if not posters.is_empty() else ""

func interact(_who: Node) -> void:
	if not active.is_empty() or posters.is_empty():
		return
	var menus = Game.get("menus")
	if menus == null:
		accept(0)
		return
	var p: PanelContainer = menus._paper_panel(Vector2(820, 560))
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UITheme.label("WANTED", 64, "poster", UITheme.OXBLOOD, false))
	for i in posters.size():
		var b: Dictionary = posters[i]
		var idx := i
		var btn: Button = menus._button("%s — for %s — $%d" % [b.name, b.crime, int(b.reward)], func():
			accept(idx)
			menus.back())
		btn.add_theme_font_override("font", UITheme.font("body"))
		btn.add_theme_font_size_override("font_size", 28)
		v.add_child(btn)
	v.add_child(menus._button("Leave", menus.back))
	menus._push(p)

func accept(i: int) -> void:
	active = posters.pop_at(i)
	Game.log_event("bounty_accept", {"name": active.name, "reward": active.reward})
	if Game.get("menus"):
		Game.menus.set_waypoint(active.pos)
	Game.say("Bounty accepted: %s, $%d. Last seen marked on your map." % [active.name, int(active.reward)], 5.0)
	_hunt.call_deferred()

func _hunt() -> void:
	var b := active
	while Game.player.global_position.distance_to(b.pos) > 140.0 and not (Game.missions and Game.missions.autopilot):
		await get_tree().create_timer(1.0).timeout
	var md = Game.missions
	var group: Array = md.spawn_group(b.pos, 1 + int(b.gang), {"role": "gunman", "faction": "bandit", "name": "Gang Member",
		"weapon": "merriman_lever", "skill": 0.45, "seed": rng.randi()}, 10.0)
	var target: Human = group[0]
	target.display_name = b.name
	target.brain.bravery = 0.15
	for h in group:
		h.brain.aggressive = true
	md.set_objective("Bring in %s — dead or alive" % b.name)
	while true:
		await get_tree().physics_frame
		if not target.alive:
			_pay(b, false)
			break
		if target.brain.state == target.brain.State.SURRENDER and group.slice(1).all(func(h): return not h.alive or h.brain.state == h.brain.State.SURRENDER):
			if md.autopilot or (Game.player.global_position.distance_to(target.global_position) < 3.0 and Game.player.intent.interact):
				_pay(b, true)
				target.queue_free()
				break
			md.set_objective("[E] Take %s into custody" % b.name)
		if md.autopilot:
			for h in group.slice(1):
				h.damageable.apply_hit({"amount": 999.0, "zone": "chest", "attacker": Game.player})
			target.brain.state = target.brain.State.SURRENDER
	md.set_objective("")
	active = {}
	posters.append(_make_poster())

func _pay(b: Dictionary, alive: bool) -> void:
	var amount: float = b.reward * (1.5 if alive else 1.0)
	Game.state.add_money(amount)
	if alive:
		Game.state.good_deed("bring_alive")
	Game.log_event("bounty_paid", {"name": b.name, "alive": alive, "amount": amount})
	Game.say("Bounty on %s collected: $%d%s" % [b.name, int(amount), " (alive)" if alive else ""], 5.0)
	if Game.get("menus"):
		Game.menus.clear_waypoint()
