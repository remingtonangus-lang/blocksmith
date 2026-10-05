extends Node
## The Outfit's camp at Willow Bend: a campfire with light and crackle, the companions who live there once
## recruited (story flags), each with a spot and a day (Hap at the cook pot humming, Doc reading or drinking as his
## arc went, Del dealing solitaire on a crate, Billy at the horse line, Joseph mending tack with a newspaper),
## evenings round the fire and nights in their bedrolls.
##
## Sitting at the fire plays a conversation (two to four lines) chosen from design/dialogue/camp.json by story flags,
## Standing, money, bounties, recent crimes (WorldState.crimes_log), kills, what she's carrying from the hunt and the
## chapter — companions talk about what Ruth actually did. Walking up to someone gets a one-line bark picked the
## same way. Camp activities with small rewards: Hap's stew (heal, once a day), a drink with Doc (whiskey for Nerve,
## or coffee if he's keeping sober), a hand of five-card draw with Del (poker engine), plus sleep, cooking meat and
## the camp ledger. `selftest()` (bot_runner --bot camp) checks the picks for given situations and plays them.

const COMPANIONS := {
	"hap": {"name": "Hap Lindqvist", "flag_mission": "c1_drover", "seed": 7, "weapon": "harlan_carbine", "role": "drover",
		"spot": Vector3(2.2, 0, 1.4), "activity": "cooking"},
	"billy": {"name": "Billy Pruitt", "flag": "billy_joined", "seed": 14, "weapon": "", "role": "child",
		"spot": Vector3(9.0, 0, 5.0), "activity": "horses"},
	"del": {"name": "Del Arceneaux", "flag": "del_joined", "seed": 2201, "weapon": "lockhart_sa", "role": "gambler",
		"spot": Vector3(-2.8, 0, 1.2), "activity": "solitaire"},
	"doc": {"name": "Cornelius Abernathy", "flag": "doc_joined", "seed": 3204, "weapon": "", "role": "townsfolk",
		"spot": Vector3(-1.6, 0, -2.8), "activity": "reading"},
	"joseph": {"name": "Joseph Kehoe", "flag": "joseph_joined", "seed": 4101, "weapon": "bowden_bolt", "role": "hunter",
		"spot": Vector3(4.5, 0, -3.2), "activity": "tack"},
}
const TABLE := "res://design/dialogue/camp.json"

var center := Vector3.ZERO
var fire_light: OmniLight3D
var members := {}            # id -> Human
var ledger := 0.0
var upgrades := {}           # "lodging", "ammo_box", "medicine" ...
var barks: Array = []
var conversations: Array = []
var played := {}             # conversation id -> times played
var recent: Array = []       # last conversation ids, newest last
var crime_cursor := 0        # crimes_log entries before this have been talked about
var stew_day := -1
var drink_day := -1
var sitting := false
var _bark_cd := {}
var _bark_global := 0.0
var _t := 0.0
var _fire: Node3D
var _props: Node3D
var rng := RandomNumberGenerator.new()

## The fire as an interactable: sit down (conversation + the camp menu).
class FireSeat extends Node3D:
	var camp

	func interact_prompt() -> String:
		if camp == null or camp.sitting:
			return ""
		return "Sit at the fire"

	func interact(_who: Node) -> void:
		camp.open_menu()

func _ready() -> void:
	Game.set("camp", self)
	rng.seed = 1899
	var c := Game.world.poi("caddell_camp")
	center = Vector3(c.x, Game.world.height(c.x, c.z), c.z)
	_load_table()
	_build_fire()
	_build_props()
	(func():
		ledger = ledger_funds()
		for k in STOCKS.keys():
			if stock(k) > 0:
				_build_stock_props(k)).call_deferred()

func _load_table() -> void:
	var j = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
	if typeof(j) != TYPE_DICTIONARY:
		push_warning("camp: no camp.json")
		return
	barks = j.get("camp_barks", [])
	conversations = j.get("conversations", [])
	if Game.missions:
		Game.missions._load_dialogue(TABLE)
	else:
		(func(): if Game.missions: Game.missions._load_dialogue(TABLE)).call_deferred()

func _build_fire() -> void:
	_fire = FireSeat.new()
	_fire.name = "Campfire"
	_fire.camp = self
	_fire.add_to_group("interactable")
	add_child(_fire)
	_fire.global_position = center
	if Game.headless:
		return
	# stone ring + logs
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.45
	tm.outer_radius = 0.7
	tm.rings = 16
	ring.mesh = tm
	ring.scale = Vector3(1, 0.5, 1)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.32, 0.3, 0.28)
	sm.roughness = 0.95
	ring.material_override = sm
	_fire.add_child(ring)
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.62, 0.3)
	fire_light.light_energy = 2.6
	fire_light.omni_range = 11.0
	fire_light.shadow_enabled = true
	fire_light.position.y = 0.6
	_fire.add_child(fire_light)
	var flames := CPUParticles3D.new()
	flames.amount = 40
	flames.lifetime = 0.8
	flames.direction = Vector3.UP
	flames.spread = 12.0
	flames.initial_velocity_min = 0.6
	flames.initial_velocity_max = 1.4
	flames.gravity = Vector3(0, 1.2, 0)
	flames.scale_amount_min = 0.15
	flames.scale_amount_max = 0.35
	var q := QuadMesh.new()
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.vertex_color_use_as_albedo = true
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = fm
	flames.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.75, 0.35, 0.9))
	g.set_color(1, Color(0.6, 0.15, 0.05, 0.0))
	flames.color_ramp = g
	flames.position.y = 0.15
	_fire.add_child(flames)

## Each companion's corner: a cook pot on a tripod, a crate table, a log to read on, a picket line, a tack bench.
func _build_props() -> void:
	_props = Node3D.new()
	_props.name = "CampProps"
	add_child(_props)
	if Game.headless:
		return
	var wood := Color(0.36, 0.27, 0.18)
	_prop_box(Vector3(2.2, 0, 1.4) + Vector3(0.6, 0, 0), Vector3(0.45, 0.4, 0.45), Color(0.15, 0.14, 0.13))     # pot
	_prop_box(Vector3(-2.8, 0, 1.2) + Vector3(0.7, 0, 0), Vector3(0.7, 0.55, 0.55), wood)                      # crate
	_prop_box(Vector3(-1.6, 0, -2.8) + Vector3(0, 0, 0.6), Vector3(1.8, 0.35, 0.4), wood.darkened(0.2))       # log
	_prop_box(Vector3(9.0, 0, 5.0) + Vector3(0, 1.0, 1.0), Vector3(6.0, 0.05, 0.05), Color(0.6, 0.5, 0.35))    # picket line
	_prop_box(Vector3(4.5, 0, -3.2) + Vector3(0.7, 0, 0), Vector3(1.4, 0.5, 0.5), wood)                        # tack bench
	_prop_box(Vector3(5.2, 0, 2.8), Vector3(2.2, 1.0, 1.2), Color(0.5, 0.42, 0.3))                              # wagon bed

func _prop_box(off: Vector3, size: Vector3, col: Color) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	m.material_override = mat
	_props.add_child(m)
	var p := center + off
	m.global_position = Vector3(p.x, Game.world.height(p.x, p.z) + off.y + size.y * 0.5, p.z)

func _process(dt: float) -> void:
	if fire_light:
		fire_light.light_energy = 2.4 + sin(Time.get_ticks_msec() * 0.013) * 0.25 + sin(Time.get_ticks_msec() * 0.031) * 0.18
	_bark_global -= dt
	_t -= dt
	if _t > 0.0 or Game.player == null:
		return
	_t = 2.0
	var near := Game.player.global_position.distance_to(center) < 300.0
	var busy_in_mission: bool = Game.missions != null and Game.missions.active != null
	for id in COMPANIONS.keys():
		var c: Dictionary = COMPANIONS[id]
		if joined(id) and near and not busy_in_mission and not members.has(id):
			_spawn_member(id, c)
		elif members.has(id) and (not near or busy_in_mission):
			if is_instance_valid(members[id]):
				members[id].queue_free()
			members.erase(id)
	for id in members.keys():
		var h: Human = members[id]
		if is_instance_valid(h) and h.alive:
			_routine(id, h)
			_maybe_bark(id, h)

func joined(id: String) -> bool:
	var c: Dictionary = COMPANIONS.get(id, {})
	# gone for good: Hap's fate on the Meridian line, Del or Joseph leaving over the money, or the low road's end
	if Game.state:
		var f: Dictionary = Game.state.flags
		if (id == "hap" and f.get("hap_alive", true) == false) or (id == "del" and f.get("del_left", false)) \
				or (id == "joseph" and f.get("joseph_left", false)) or (f.get("ending", "") == "low" and f.get("game_complete", false)):
			return false
	if c.has("flag_mission"):
		return Game.missions != null and Game.missions.completed.has(c.flag_mission)
	return Game.state != null and bool(Game.state.flags.get(c.get("flag", ""), false))

func joined_ids() -> Array:
	return COMPANIONS.keys().filter(func(id): return joined(id))

func _spawn_member(id: String, c: Dictionary) -> void:
	var p := center + Vector3(c.spot)
	p.y = Game.world.height(p.x, p.z) + 0.3
	Game.terrain.ensure_tile(p)
	var h := Human.spawn(Game.main, p, {"seed": c.seed, "role": c.role, "faction": "outfit", "name": c.name, "weapon": c.weapon})
	h.brain.home = center
	members[id] = h

## Camp routine by hour: chores at their own spot by day, the fire in the evening, bedrolls at night.
func _routine(id: String, h: Human) -> void:
	if h.brain.state != h.brain.State.ROUTINE and h.brain.state != h.brain.State.IDLE:
		return
	if sitting:
		h.intent.move_to = null
		h.intent.face = center - h.global_position
		return
	var hour: float = Game.sky.hours if Game.sky else 12.0
	var spot: Vector3 = center + Vector3(COMPANIONS[id].spot)
	if hour > 18.0 or hour < 1.0:
		var a := float(hash(id) % 628) / 100.0
		h.intent.move_to = center + Vector3(cos(a) * 2.3, 0, sin(a) * 2.3)
		h.intent.speed = Human.WALK
		h.intent.face = center - h.global_position
	elif hour < 6.0:
		h.intent.move_to = center + Vector3(-5.0 + float(COMPANIONS.keys().find(id)) * 1.6, 0, 5.5)
	else:
		# the day's chores, at the camp's own spots
		var ch := chore_for(id, hour)
		if ch.is_empty():
			h.intent.move_to = spot
			h.intent.face = (spot + Vector3(0.7, 0, 0)) - h.global_position
		else:
			chore_now[id] = ch
			h.intent.move_to = ch.spot
			if h.global_position.distance_to(ch.spot) < 1.2:
				h.intent.face = ch.face - h.global_position
		h.intent.speed = Human.WALK

func activity(id: String) -> String:
	if id == "doc":
		return "reading" if Game.state and Game.state.flags.get("doc_sober", false) else "drinking"
	return str(COMPANIONS.get(id, {}).get("activity", ""))

func _maybe_bark(id: String, h: Human) -> void:
	if sitting or _bark_global > 0.0 or Game.missions == null or Game.missions.active != null:
		return
	if h.global_position.distance_to(Game.player.global_position) > 5.0:
		return
	if float(_bark_cd.get(id, 0.0)) > Time.get_ticks_msec() / 1000.0:
		return
	var b := pick_bark(id, context())
	if b.is_empty():
		return
	_bark_cd[id] = Time.get_ticks_msec() / 1000.0 + 60.0
	_bark_global = 15.0
	Game.missions.say_async(b.line, h)

# ------------------------------------------------------------------ choosing what gets said
## What camp talk can know: flags, chapter, Standing, money, bounties, kills, crimes since the last time the camp
## talked about one, what she carries, and who's here.
func context() -> Dictionary:
	var st = Game.state
	var crimes := []
	var bounty := 0.0
	if st:
		for i in range(crime_cursor, st.crimes_log.size()):
			crimes.append(str(st.crimes_log[i].kind))
		for k in st.bounties.keys():
			bounty += float(st.bounties[k])
	var present := []
	for id in joined_ids():
		present.append(id)
	return {"flags": st.flags if st else {}, "chapter": chapter(), "standing": st.standing if st else 0.0,
		"money": st.money if st else 0.0, "bounty": bounty, "kills": st.kills if st else {}, "crimes": crimes,
		"items": st.inventory if st else {}, "members": present, "morale": morale()}

func chapter() -> int:
	var c := 0
	if Game.missions:
		for m in Game.missions.completed:
			var s := str(m)
			if s.length() > 2 and s[0] == "c" and s[1].is_valid_int():
				c = maxi(c, int(s[1]))
	return c

func matches(when: Dictionary, ctx: Dictionary) -> bool:
	var flags: Dictionary = ctx.get("flags", {})
	for k in when.keys():
		var v = when[k]
		match k:
			"flag":
				for f in v.keys():
					if not flags.has(f):
						return false
					if typeof(v[f]) == TYPE_BOOL:
						if bool(flags[f]) != bool(v[f]):
							return false
					elif str(flags[f]) != str(v[f]):
						return false
			"flag_set":
				for f in v:
					if not flags.has(f) or not flags[f]:
						return false
			"chapter_min":
				if int(ctx.chapter) < int(v): return false
			"chapter_max":
				if int(ctx.chapter) > int(v): return false
			"standing_min":
				if float(ctx.standing) < float(v): return false
			"standing_max":
				if float(ctx.standing) > float(v): return false
			"money_min":
				if float(ctx.money) < float(v): return false
			"money_max":
				if float(ctx.money) > float(v): return false
			"bounty_min":
				if float(ctx.bounty) < float(v): return false
			"kills_civilian_min":
				if int(ctx.kills.get("civilian", 0)) < int(v): return false
			"kills_outlaw_min":
				if int(ctx.kills.get("outlaw", 0)) < int(v): return false
			"recent_crime":
				if not ctx.crimes.has(str(v)): return false
			"morale_min":
				if float(ctx.get("morale", 50.0)) < float(v): return false
			"morale_max":
				if float(ctx.get("morale", 50.0)) > float(v): return false
			"item_prefix":
				var any := false
				for it in ctx.items.keys():
					if str(it).begins_with(str(v)) and int(ctx.items[it]) > 0:
						any = true
				if not any: return false
	return true

## The conversation to play now: everyone in it is in camp, its conditions hold, a one-off hasn't played; highest
## priority wins, then whichever was heard least recently. {} if nothing fits.
func pick_conversation(ctx: Dictionary) -> Dictionary:
	var best := {}
	var best_key := -INF
	for c in conversations:
		if c.get("once", false) and played.has(c.id):
			continue
		var ok := true
		for w in c.who:
			if not ctx.members.has(w):
				ok = false
		if not ok or not matches(c.get("when", {}), ctx):
			continue
		var age := recent.find(c.id)
		var key := float(c.get("priority", 0)) * 100.0 - (float(age + 1) * 10.0 if age >= 0 else 0.0) - float(played.get(c.id, 0))
		if key > best_key:
			best_key = key
			best = c
	return best

## A bark for this companion: the conditional ones that hold outweigh the everyday ones.
func pick_bark(who: String, ctx: Dictionary) -> Dictionary:
	var cands := []
	var weights := []
	for b in barks:
		if b.who != who or not matches(b.get("when", {}), ctx):
			continue
		cands.append(b)
		weights.append(float(b.get("weight", 1.0)) * (3.0 if not b.get("when", {}).is_empty() else 1.0))
	if cands.is_empty():
		return {}
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	for i in cands.size():
		r -= weights[i]
		if r <= 0.0:
			return cands[i]
	return cands[-1]

# ------------------------------------------------------------------ sitting at the fire
func open_menu() -> void:
	var menus = Game.get("menus")
	if menus == null or Game.headless:
		sit_at_fire()
		return
	var p: PanelContainer = menus._paper_panel(Vector2(620, 0))
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UITheme.label("Willow Bend", 46, "display", UITheme.INK, false))
	v.add_child(UITheme.label("The fire, the Outfit, and whatever's in the pot", 22, "italic", UITheme.INK_SOFT, false))
	v.add_child(HSeparator.new())
	var add := func(text: String, cb: Callable):
		v.add_child(menus._button(text, func():
			menus.back()
			cb.call()))
	add.call("Sit and listen", sit_at_fire)
	if members.has("hap") or joined("hap"):
		add.call("Eat a bowl of Hap's stew", eat_stew)
	if joined("doc"):
		add.call("Have a drink with Doc" if not Game.state.flags.get("doc_sober", false) else "Have coffee with Doc", drink_with_doc)
	if joined("del"):
		add.call("Play a hand with Del ($3 stake)", play_with_del)
	var has_meat := false
	for k in Game.state.inventory.keys():
		if str(k).begins_with("meat_") and int(Game.state.inventory[k]) > 0:
			has_meat = true
	if has_meat:
		add.call("Cook meat at the fire", cook)
	add.call("Sleep until morning", sleep)
	add.call("The camp ledger (%s morale, $%.2f in hand)" % [morale_band(morale()), ledger_funds()], open_ledger)
	v.add_child(menus._button("Get up", menus.back))
	menus._push(p)

## The ledger: give money or food, spend it on the camp's stocks, draw the morning's supplies.
func open_ledger() -> void:
	var menus = Game.get("menus")
	if menus == null:
		return
	var p: PanelContainer = menus._paper_panel(Vector2(700, 0))
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UITheme.label("The Camp Ledger", 44, "display", UITheme.INK, false))
	v.add_child(UITheme.label("In hand $%.2f   ·   morale %d (%s)" % [ledger_funds(), int(morale()), morale_band(morale())], 22, "italic", UITheme.INK_SOFT, false))
	v.add_child(HSeparator.new())
	var add := func(text: String, cb: Callable):
		v.add_child(menus._button(text, func():
			menus.back()
			cb.call()
			open_ledger()))
	add.call("Give $5", func():
		if not contribute(5.0):
			Game.say("You haven't got five dollars to spare.", 3.0))
	add.call("Give $20", func():
		if not contribute(20.0):
			Game.say("You haven't got twenty dollars to spare.", 3.0))
	add.call("Give Hap your meat and fish", donate_food)
	for k in STOCKS.keys():
		var lvl := stock(k)
		var kk: String = k
		if lvl < 3:
			add.call("Stock up %s to level %d ($%d from the ledger)" % [STOCKS[k].label.to_lower(), lvl + 1, int(STOCKS[k].costs[lvl])], func():
				if upgrade(kk) < 0:
					Game.say("The ledger can't cover it yet.", 2.5))
		else:
			v.add_child(UITheme.label("%s: fully stocked" % STOCKS[k].label, 22, "body", UITheme.INK, false))
	if stock("medicine") > 0 or stock("ammo") > 0:
		add.call("Draw today's supplies", take_supplies)
	v.add_child(menus._button("Close the ledger", menus.back))
	menus._push(p)

## Sit down at the fire: the camp's conversation for right now (or a bark from whoever's there).
func sit_at_fire() -> String:
	if sitting or Game.missions == null:
		return ""
	var ctx := context()
	var c := pick_conversation(ctx)
	sitting = true
	var md = Game.missions
	var said := ""
	md.cine_begin()
	if not c.is_empty():
		said = c.id
		Game.log_event("camp_talk", {"id": c.id})
		played[c.id] = int(played.get(c.id, 0)) + 1
		recent.append(c.id)
		if recent.size() > 6:
			recent.pop_front()
		if c.get("when", {}).has("recent_crime") and Game.state:
			crime_cursor = Game.state.crimes_log.size()
		for lid in c.lines:
			var spk: String = str(md.dialogue.get(lid, {}).get("speaker", ""))
			var node: Node3D = Game.player if spk == "ruth" else (members.get(spk) if is_instance_valid(members.get(spk)) else null)
			await md.say(lid, node)
	else:
		var ids: Array = ctx.members
		if not ids.is_empty():
			var who: String = ids[rng.randi() % ids.size()]
			var b := pick_bark(who, ctx)
			if not b.is_empty():
				said = b.line
				await md.say(b.line, members.get(who) if is_instance_valid(members.get(who)) else null)
	md.cine_end()
	sitting = false
	return said

# ------------------------------------------------------------------ camp activities
## Hap's stew: heals and fills stamina, once a day.
func eat_stew() -> bool:
	var day: int = Game.sky.day if Game.sky else 0
	if Game.missions == null:
		return false
	if stew_day == day:
		await Game.missions.say("camp_act_stew_again", members.get("hap"))
		return false
	stew_day = day
	if Game.player and Game.player.damageable:
		Game.player.damageable.heal(60.0 + 20.0 * stock("provisions"))
		Game.player.stamina = Game.player.STAMINA_MAX
	Game.log_event("camp_activity", {"what": "stew"})
	await Game.missions.say("camp_act_stew", members.get("hap"))
	return true

## A drink with Doc: whiskey tops up Nerve (and a little Standing with him); coffee if he's keeping sober.
func drink_with_doc() -> String:
	if Game.missions == null:
		return ""
	var day: int = Game.sky.day if Game.sky else 0
	var sober: bool = Game.state.flags.get("doc_sober", false) if Game.state else false
	var what := "coffee" if sober else "whiskey"
	if drink_day != day:
		drink_day = day
		if sober:
			if Game.player:
				Game.player.stamina = Game.player.STAMINA_MAX
		else:
			if Game.player and Game.player.get("nerve") and Game.player.nerve.has_method("reward"):
				Game.player.nerve.reward(50.0)
	Game.log_event("camp_activity", {"what": what})
	await Game.missions.say("camp_act_coffee" if sober else "camp_act_whiskey", members.get("doc"))
	return what

## A hand or three of five-card draw with Del for a small stake (the poker table, no stacked decks).
func play_with_del() -> Dictionary:
	if Game.missions == null:
		return {}
	await Game.missions.say("camp_act_deal", members.get("del"))
	var res: Dictionary = await Game.missions.minigame("poker", {"players": [{"name": "Del Arceneaux", "style": "bluffer", "stack": 8.0}],
		"buyin": 3.0, "hands": 3, "seed": 1899 + (Game.sky.day if Game.sky else 0), "dealer": "Del Arceneaux", "can_leave": true})
	Game.log_event("camp_activity", {"what": "cards", "net": res.get("net", 0.0)})
	await Game.missions.say("camp_act_del_won" if float(res.get("net", 0.0)) > 0.0 else "camp_act_del_lost", members.get("del"))
	return res

## Sleep until morning (or 8 hours), heal, autosave.
func sleep() -> void:
	if Game.sky == null:
		return
	var h: float = Game.sky.hours
	var wake := 6.5 if h > 17.0 or h < 6.0 else fmod(h + 8.0, 24.0)
	if h > 17.0:
		Game.sky.day += 1
	Game.sky.set_time(wake)
	if Game.player and Game.player.damageable:
		Game.player.damageable.health = Game.player.damageable.max_health
		Game.player.stamina = Game.player.STAMINA_MAX
	if Game.state:
		Game.state.save_game("auto")
	Game.say("You slept at Willow Bend.", 3.0)

## Cook any meat in the satchel at the fire: each portion heals and fills stamina.
func cook() -> int:
	if Game.state == null:
		return 0
	var n := 0
	for k in Game.state.inventory.keys():
		if str(k).begins_with("meat_") and int(Game.state.inventory[k]) > 0:
			n += int(Game.state.inventory[k])
			Game.state.inventory[k] = 0
	if n > 0:
		Game.state.add_item("cooked_meat", n)
		Game.say("Cooked %d portions of meat." % n, 3.0)
	return n

func contribute(amount: float) -> bool:
	if Game.state == null or Game.state.money < amount:
		return false
	Game.state.add_money(-amount)
	_set_ledger(ledger_funds() + amount)
	_morale_bump(amount * 0.2)
	Game.state.good_deed("donation")
	if ledger >= 40.0 and not upgrades.has("ammo_box"):
		upgrades["ammo_box"] = true
		Game.say("Hap built an ammunition box. Take what you need.", 4.0)
	return true

# ------------------------------------------------------------------ the camp ledger, stocks, chores, morale
## Three stocks the ledger buys: provisions (Hap's stew heals more), medicine (Doc leaves tonics in his chest each
## morning) and ammunition (the ammo crate refills each morning). Each level adds props by the chuck wagon.
const STOCKS := {
	"provisions": {"label": "Provisions", "costs": [20.0, 45.0, 80.0], "at": Vector3(-4.0, 0, 7.6)},
	"medicine": {"label": "Medicine", "costs": [25.0, 50.0, 90.0], "at": Vector3(-1.6, 0, -4.2)},
	"ammo": {"label": "Ammunition", "costs": [30.0, 60.0, 100.0], "at": Vector3(4.2, 0, 4.6)},
}
const FOOD_VALUE := {"meat_": 1.5, "fish_": 1.0, "cooked_meat": 2.0}
## Who does what, by the hour: [from hour, spot type, activity] (spot types from the camp's settlement spots).
const CHORES := {
	"hap": [[5.0, "campfire", "cook"], [10.0, "work", "chop"], [14.0, "campfire", "cook"]],
	"billy": [[5.5, "trough", "water the horses"], [9.0, "corral", "work the horses"], [15.0, "hitch", "tack"]],
	"del": [[7.0, "wagon_seat", "accounts"], [11.0, "campfire_seat", "solitaire"], [16.0, "campfire_seat", "solitaire"]],
	"doc": [[6.0, "campfire_seat", "coffee"], [9.0, "wagon_seat", "reading"], [14.0, "campfire_seat", "mending"]],
	"joseph": [[5.0, "corral", "horses"], [8.0, "work", "chop"], [13.0, "hitch", "tack"]],
}

var _stock_props := {}          # stock -> [MeshInstance3D]
var _spots_cache: Array = []
var chore_now := {}             # companion -> {spot, activity}

func stock(kind: String) -> int:
	return int(Game.state.flags.get("camp_stock", {}).get(kind, 0)) if Game.state else 0

func ledger_funds() -> float:
	return float(Game.state.flags.get("camp_ledger", ledger)) if Game.state else ledger

func _set_ledger(v: float) -> void:
	ledger = v
	if Game.state:
		Game.state.flags["camp_ledger"] = v

## Donate food from the satchel: meat, fish and cooked portions go into provisions (their worth into the ledger).
func donate_food() -> float:
	if Game.state == null:
		return 0.0
	var worth := 0.0
	for k in Game.state.inventory.keys():
		var key := str(k)
		var n := int(Game.state.inventory[k])
		if n <= 0:
			continue
		for pre in FOOD_VALUE.keys():
			if key.begins_with(pre):
				worth += float(FOOD_VALUE[pre]) * n
				Game.state.inventory[k] = 0
				break
	if worth > 0.0:
		_set_ledger(ledger_funds() + worth)
		_morale_bump(3.0)
		Game.log_event("camp_donation", {"food": worth})
		Game.say("Hap takes the food into the chuck wagon. The ledger says $%.2f." % worth, 3.0)
	return worth

## Spend the ledger on the next level of a stock. Returns the new level (or -1 if the ledger can't cover it).
func upgrade(kind: String) -> int:
	var s: Dictionary = STOCKS.get(kind, {})
	var lvl := stock(kind)
	if s.is_empty() or lvl >= 3:
		return -1
	var cost: float = s.costs[lvl]
	if ledger_funds() < cost:
		return -1
	_set_ledger(ledger_funds() - cost)
	var all: Dictionary = Game.state.flags.get("camp_stock", {})
	all[kind] = lvl + 1
	Game.state.flags["camp_stock"] = all
	_morale_bump(8.0)
	_build_stock_props(kind)
	Game.log_event("camp_upgrade", {"stock": kind, "level": lvl + 1})
	Game.say("%s stocked up (level %d)." % [s.label, lvl + 1], 3.0)
	return lvl + 1

## Morning issue: Doc's chest gives tonics, the ammo crate refills (once a day each).
func take_supplies() -> Dictionary:
	var got := {}
	var day: int = Game.sky.day if Game.sky else 0
	if Game.state == null or int(Game.state.flags.get("camp_issue_day", -1)) == day:
		return got
	Game.state.flags["camp_issue_day"] = day
	if stock("medicine") > 0:
		Game.state.add_item("tonic_health", stock("medicine"))
		got["tonic_health"] = stock("medicine")
	if stock("ammo") > 0 and Game.player and Game.player.get("gun"):
		for k in ["revolver", "repeater"]:
			Game.player.gun.ammo[k] = int(Game.player.gun.ammo.get(k, 0)) + 12 * stock("ammo")
		got["rounds"] = 24 * stock("ammo")
	Game.log_event("camp_supplies", got)
	return got

func _build_stock_props(kind: String) -> void:
	var old: Array = _stock_props.get(kind, [])
	for m in old:
		if is_instance_valid(m):
			m.queue_free()
	var made := []
	var s: Dictionary = STOCKS[kind]
	var col: Color = {"provisions": Color(0.72, 0.62, 0.45), "medicine": Color(0.9, 0.88, 0.82), "ammo": Color(0.32, 0.36, 0.26)}[kind]
	for i in stock(kind) * 2:
		var off: Vector3 = s.at + Vector3((i % 3) * 0.7, floorf(i / 3.0) * 0.5, 0.0)
		if Game.headless:
			made.append(null)
			continue
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.6, 0.45, 0.45) if kind != "provisions" else Vector3(0.55, 0.6, 0.55)
		m.mesh = b
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col.darkened(0.08 * (i % 2))
		mat.roughness = 0.9
		m.material_override = mat
		_props.add_child(m)
		var p := center + off
		m.global_position = Vector3(p.x, Game.world.height(p.x, p.z) + off.y + b.size.y * 0.5, p.z)
		made.append(m)
	_stock_props[kind] = made

func stock_prop_count(kind: String) -> int:
	return (_stock_props.get(kind, []) as Array).size()

# morale: 0..100 from what the camp has, who's still in it, and how Ruth stands
func _morale_bump(v: float) -> void:
	if Game.state:
		Game.state.flags["camp_morale_bonus"] = clampf(float(Game.state.flags.get("camp_morale_bonus", 0.0)) + v, -30.0, 30.0)

func morale() -> float:
	if Game.state == null:
		return 50.0
	var f: Dictionary = Game.state.flags
	var m := 45.0
	for k in STOCKS.keys():
		m += 4.0 * stock(k)
	m += clampf(float(Game.state.standing) * 0.2, -15.0, 15.0)
	m += float(f.get("camp_morale_bonus", 0.0))
	if f.get("hap_alive", true) == false:
		m -= 20.0
	if f.get("del_left", false):
		m -= 8.0
	if f.get("joseph_left", false):
		m -= 8.0
	var day: int = Game.sky.day if Game.sky else 0
	if stew_day == day:
		m += 5.0
	return clampf(m, 0.0, 100.0)

static func morale_band(m: float) -> String:
	return "low" if m < 35.0 else ("high" if m >= 70.0 else "fair")

## The settlement's camp spots (campfire, campfire_seat, work/chop, corral, hitch, trough, wagon_seat).
func camp_spots() -> Array:
	if _spots_cache.is_empty() and Game.main and Game.main.get("settlements") and Game.main.settlements.has_method("get_town"):
		var t: Dictionary = Game.main.settlements.get_town("caddell_camp")
		_spots_cache = t.get("spots", [])
	return _spots_cache

## Where a companion's chore puts them now: {spot: Vector3, face: Vector3, activity}.
func chore_for(id: String, hour: float) -> Dictionary:
	var plan: Array = CHORES.get(id, [])
	var cur: Array = []
	for c in plan:
		if hour >= float(c[0]):
			cur = c
	if cur.is_empty():
		return {}
	var want := str(cur[1])
	var nth := COMPANIONS.keys().find(id)
	var cands := camp_spots().filter(func(sp): return str(sp.type) == want)
	if cands.is_empty():
		var fb: Vector3 = center + Vector3(COMPANIONS[id].spot)
		return {"spot": fb, "face": fb + Vector3(0.7, 0, 0), "activity": str(cur[2]), "from_spot": false}
	var sp: Dictionary = cands[nth % cands.size()]
	var tr: Transform3D = sp.transform
	return {"spot": tr.origin, "face": tr.origin - tr.basis.z * 2.0, "activity": str(cur[2]), "from_spot": true}

# ------------------------------------------------------------------ self-test (bot_runner --bot camp)
## Picks the right talk for staged situations, then sits at the fire and does each activity for real.
func selftest() -> Dictionary:
	var lines := []
	var fails := 0
	var base := func(members_in: Array, extra := {}) -> Dictionary:
		var ctx := {"flags": {}, "chapter": 2, "standing": 0.0, "money": 20.0, "bounty": 0.0,
			"kills": {"civilian": 0, "outlaw": 3, "law": 0}, "crimes": [], "items": {}, "members": members_in}
		for k in extra.keys():
			ctx[k] = extra[k]
		return ctx
	var played0 := played.duplicate()
	played.clear()
	var cases := [
		["first night (chapter 1)", base.call(["hap", "billy"], {"chapter": 1}), "first_night"],
		["a hold-up on the road", base.call(["hap", "billy", "del"], {"crimes": ["robbery"]}), "robbery"],
		["a murder, Doc in camp", base.call(["hap", "doc"], {"crimes": ["murder"]}), "murder"],
		["a murder, no Doc", base.call(["hap", "billy"], {"crimes": ["murder"]}), "murder_hap"],
		["a $200 poster", base.call(["hap", "del"], {"bounty": 200.0}), "poster"],
		["low Standing", base.call(["del", "doc", "hap"], {"standing": -45.0}), "notorious"],
		["high Standing with Joseph", base.call(["hap", "joseph"], {"standing": 70.0}), "respected"],
		["Cutter jailed", base.call(["hap", "del"], {"chapter": 3, "flags": {"cutter_fate": "jailed"}}), "cutter_jailed"],
		["Cutter dead", base.call(["doc", "billy"], {"chapter": 3, "flags": {"cutter_fate": "dead"}}), "cutter_dead"],
		["Doc sober", base.call(["doc", "del"], {"flags": {"doc_sober": true}}), "doc_sober"],
		["Doc drinking", base.call(["doc", "hap"], {"flags": {"doc_sober": false}}), "doc_drink"],
		["Asa spared", base.call(["joseph", "hap"], {"chapter": 4, "flags": {"spared_asa": true, "joseph_joined": true}}), "asa_spared"],
		["Asa killed", base.call(["joseph", "doc"], {"chapter": 4, "flags": {"asa_killed": true}}), "asa_killed"],
		["a pelt in the satchel", base.call(["billy", "hap"], {"items": {"pelt_mule_deer": 1}}), "hunting"],
		["nothing special", base.call(["hap"], {}), "tom"],
		["stayed for the comet", base.call(["joseph", "hap"], {"chapter": 4, "flags": {"stayed_for_comet": true}}), "comet"],
		["paid Pip's debt", base.call(["billy", "hap"], {"flags": {"paid_pip_debt": true}}), "pip"],
		["faced Rourke down", base.call(["billy", "del"], {"flags": {"paid_pip_debt": false}}), "pip_rourke"],
		["a share in the Locomobile", base.call(["billy", "hap"], {"flags": {"invested_pettigrew": true}}), "locomobile"],
		["Del stayed", base.call(["del", "billy"], {"flags": {"del_marker": "ticket"}}), "del_stays"],
		["Doc answered the letter", base.call(["doc", "hap"], {"flags": {"doc_letter": "answered"}}), "doc_letter"],
		["Joseph said his piece", base.call(["joseph"], {"chapter": 4, "flags": {"joseph_trail": "refused"}}), "joseph_own"],
		["Billy's colt", base.call(["billy", "hap"], {"flags": {"billy_colt": "taken"}}), "billy_example"],
	]
	for cs in cases:
		var got: Dictionary = pick_conversation(cs[1])
		var ok: bool = got.get("id", "") == cs[2]
		if not ok:
			fails += 1
		lines.append("  %s  %-26s -> %s" % ["ok  " if ok else "FAIL", cs[0], got.get("id", "(none)")])
	# once-only talk doesn't repeat
	played["first_night"] = 1
	var again: Dictionary = pick_conversation(base.call(["hap", "billy"], {"chapter": 1}))
	var once_ok: bool = again.get("id", "") != "first_night"
	if not once_ok:
		fails += 1
	lines.append("  %s  one-off talk plays once (then: %s)" % ["ok  " if once_ok else "FAIL", again.get("id", "")])
	played = played0
	# barks follow the facts
	var bark_cases := [
		["doc", {"flags": {"doc_sober": true}}, "camp_doc_reading"],
		["doc", {"flags": {"doc_sober": false}}, "camp_doc_drinking"],
		["del", {"crimes": ["robbery"]}, "camp_del_robbery"],
		["hap", {"items": {"meat_elk": 2}}, "camp_hap_meat"],
		["joseph", {"standing": -60.0}, "camp_joseph_name"],
		["doc", {"flags": {"smashed_barrels": true, "doc_sober": false}}, "camp_doc_barrels"],
		["del", {"flags": {"protected_crane": true}}, "camp_del_crane"],
		["billy", {"flags": {"posed_for_novel": true}}, "camp_billy_novel"],
		["hap", {"flags": {"spared_partner": false}}, "camp_hap_widow_alone"],
		["joseph", {"flags": {"field_book_to_fenn": true}}, "camp_joseph_map"],
		["hap", {"flags": {"hap_crew": "sang"}}, "camp_hap_crew_sang"],
		["hap", {"flags": {"hap_crew": "wire"}}, "camp_hap_crew_wire"],
		["joseph", {"flags": {"joseph_trail": "false"}}, "camp_joseph_false"],
		["billy", {"flags": {"billy_colt": "paid"}}, "camp_billy_paid"],
		["del", {"flags": {"del_marker": "paid"}}, "camp_del_paid"],
		["doc", {"flags": {"doc_letter": "burned", "doc_sober": true}}, "camp_doc_burned"],
	]
	for bc in bark_cases:
		var seen := false
		for i in 40:
			if pick_bark(bc[0], base.call([bc[0]], bc[1])).get("line", "") == bc[2]:
				seen = true
				break
		if not seen:
			fails += 1
		lines.append("  %s  %s's bark for the situation: %s" % ["ok  " if seen else "FAIL", bc[0], bc[2]])
	var never := true
	for i in 60:
		if pick_bark("doc", base.call(["doc"], {"flags": {"doc_sober": true}})).get("line", "") == "camp_doc_drinking":
			never = false
	if not never:
		fails += 1
	lines.append("  %s  a sober Doc never brags about drinking" % ("ok  " if never else "FAIL"))
	return {"ok": fails == 0, "fails": fails, "lines": lines}
