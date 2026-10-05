extends Node
## Bounty hunters and county posses. While Ruth carries a bounty above THRESHOLD in the county she is riding through
## (and no mission or encounter is running), a posse of hunters may ride in on her trail: 2-5 riders by the size of
## the bounty. They mean to take her alive: one throws a lasso (a hit drags her down and holds her while the rest
## close in; she can struggle free), the others square up with fists; past ESCALATE dollars, or once she draws blood
## with a gun, it turns to guns ("dead weighs the same on a saddle"). Taken alive: the county collects what she owes
## out of her pocket, a night in the cells, and she walks out of the county seat's jail in the morning. Paying the
## bounty at any sheriff calls them off (the wire reaches them and they ride away). The same riders carry lawmen to
## the scene of a robbery (law_response). Bots: `--bot roam` sends a posse in, ropes, captures and calls one off.

const OUTRIDER = preload("res://src/missions/ch3/outrider.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")
const THRESHOLD := 60.0
const ESCALATE := 300.0
const CHECK_EVERY := 150.0
const LASSO_RANGE := 15.0
const SEAT_OF := {"Sable County": "bitter_spring", "Kestrel County": "coldwater", "Ocotillo County": "mesquite_wells",
	"Linden County": "port_linden"}
const NAMES := ["Abner Coyle", "Silas Penhallow", "Gideon Marsh", "Tobias Rook", "Amos Vickery", "Lemuel Stroud"]

var posse: Array = []              # {o: outrider, man: Human, mode: "ride"|"foot"|"leave", lasso: bool}
var kind := ""                     # "hunters" | "law" | ""
var county := ""
var tier := 1                      # 1 alive (rope + fists), 2 alive but quick to guns, 3 guns
var guns := false
var outcome := ""                  # how the last posse ended: captured / called_off / fought_off / lost
var roped_t := 0.0                 # seconds Ruth is still held by a rope
var struggle := 0.0                # 0..1 to break the rope
var _rope_by: Human = null
var _rope_mesh: MeshInstance3D = null
var _lasso_cd := 2.0
var _capture_t := 0.0
var _leave_t := 0.0
var _t := 90.0
var _cool := 0.0
var rng := RandomNumberGenerator.new()
var enabled := true

func _ready() -> void:
	rng.seed = 1899 * 59
	Game.set_meta("hunters", self)
	if Game.missions:
		Game.missions._load_dialogue("res://design/dialogue/holdups.json")

func bounty_in(c: String) -> float:
	return float(Game.state.bounties.get(c, 0.0)) if Game.state else 0.0

func _process(dt: float) -> void:
	if Game.player == null or Game.state == null or Game.world == null:
		return
	if not posse.is_empty():
		_tick(dt)
		return
	_cool = maxf(_cool - dt, 0.0)
	if not enabled or Game.args.has("bot") or _cool > 0.0:
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = CHECK_EVERY * rng.randf_range(0.7, 1.3)
	var md = Game.missions
	var enc = Game.get("encounters")
	if md == null or md.active != null or (enc != null and str(enc.active) != ""):
		return
	var pp: Vector3 = Game.player.global_position
	var near := Game.world.nearest_settlement(pp.x, pp.z)
	if not near.is_empty() and Vector2(near.x - pp.x, near.z - pp.z).length() < float(near.r) + 120.0:
		return
	var c: String = Game.state.county_at(pp)
	var b := bounty_in(c)
	if b < THRESHOLD:
		return
	if rng.randf() < clampf(b / 400.0, 0.15, 0.8):
		send_hunters(c)

## Size and manner of a posse for a bounty.
static func posse_size(b: float) -> int:
	return clampi(2 + int(b / 150.0), 2, 5)

static func tier_for(b: float) -> int:
	return 3 if b >= ESCALATE * 2.0 else (2 if b >= ESCALATE else 1)

## Hunters ride in from behind her, 130 m out.
func send_hunters(c: String, dist := 130.0) -> int:
	if not posse.is_empty():
		_disband(false)
	var b := bounty_in(c)
	kind = "hunters"
	county = c
	tier = tier_for(b)
	guns = tier >= 3
	outcome = ""
	var p = Game.player
	var back := Vector3(sin(p.facing), 0, cos(p.facing))
	var n := posse_size(b)
	var base: Vector3 = p.global_position + back * dist
	if Game.roads:
		var rid: int = Game.roads.nearest(base)      # come up the road behind her where there is one
		if rid >= 0 and Game.roads.pts[rid].distance_to(base) < dist * 0.8:
			base = Game.roads.pts[rid]
	for i in n:
		var at: Vector3 = base + Vector3(back.z, 0, -back.x) * (float(i) - float(n - 1) * 0.5) * 4.0
		var nm: String = NAMES[(i + int(b)) % NAMES.size()] if i == 0 else "Bounty Hunter"
		_rider(at, {"seed": rng.randi(), "role": "gunman", "faction": "bounty_hunter", "name": nm, "weapon": "merriman_lever" if i % 2 == 0 else "lockhart_sa",
			"skill": 0.45, "health": 120.0}, i == 0 and tier < 3)
	Game.log_event("hunters_sent", {"county": c, "bounty": b, "size": n, "tier": tier})
	if Game.hud and not Game.headless:
		Game.hud.notice("Riders on your trail — bounty hunters after the %s money" % c, 5.0)
	return n

## Lawmen ride from the county seat to the scene of a crime (stage or train robbery), and on to Ruth if she's there.
func law_response(c: String, site: Vector3) -> int:
	if not posse.is_empty():
		return 0
	kind = "law"
	county = c
	tier = 3
	guns = true
	outcome = ""
	var seat: String = SEAT_OF.get(c, "bitter_spring")
	var town := Mission.place(seat)
	var dir := (site - town)
	dir.y = 0.0
	var start: Vector3 = site - dir.normalized() * minf(dir.length(), 220.0)
	for i in 3:
		_rider(start + Vector3(float(i) * 4.0, 0, float(i % 2) * 3.0), {"seed": rng.randi(), "role": "lawman", "faction": "law",
			"name": "Deputy" if i > 0 else "County Deputy", "weapon": "harlan_carbine" if i == 0 else "lockhart_sa", "skill": 0.5}, false)
	Game.log_event("law_response", {"county": c, "from": seat})
	return 3

func _rider(at: Vector3, opts: Dictionary, lasso: bool) -> void:
	var md = Game.missions
	var q := at
	q.y = Game.world.height(q.x, q.z)
	var o = OUTRIDER.create(md, q, opts)
	o.ride_with(Game.player, Vector3(rng.randf_range(-5.0, 5.0), 0, rng.randf_range(4.0, 8.0)))
	if o.man != null:
		o.man.damageable.damaged.connect(_on_member_hurt.bind(o.man))
	posse.append({"o": o, "man": o.man, "mode": "ride", "lasso": lasso})

func members() -> Array:
	return posse.filter(func(m): return is_instance_valid(m.man) and m.man.alive)

func _tick(dt: float) -> void:
	var p = Game.player
	var pp: Vector3 = p.global_position
	var live := members()
	# paid off: the wire reaches them and they turn for home
	if kind == "hunters" and bounty_in(county) <= 0.0 and outcome == "":
		_call_off()
	if kind == "law" and Game.state.wanted == 0 and outcome == "":
		outcome = "lost"
		_disband(false)
		return
	if outcome == "called_off":
		_leave_t -= dt
		if _leave_t <= 0.0:
			_disband(false)
			return
	if live.is_empty():
		if outcome == "":
			outcome = "fought_off"
		_disband(true)
		return
	for m in live:
		var h: Human = m.man
		var d := h.global_position.distance_to(pp)
		match m.mode:
			"ride":
				if d < 20.0:
					m.o.get_down()
					m.mode = "foot"
					if m == live[0]:
						Game.missions.say_async("bh2_boss_call" if kind == "hunters" else "law_deputy_call", h)
					_engage(h)
				elif d > 900.0:
					outcome = "lost"
			"foot":
				if guns or outcome != "":
					pass
				elif held_now():
					# she's down or roped: the nearest of them walks up to take her
					if m == _nearest(live) or m.lasso:
						Game.missions.npc_walk_to(h, pp, Human.JOG)
						m["reel"] = true
				elif m.get("reel", false) and not m.lasso:
					m["reel"] = false
					Game.missions.npc_release(h)
				elif m.lasso:
					_lasso_ai(h, d, dt)
				elif h.brain.state != h.brain.State.FIST and d < 30.0 and not Melee.is_down(h):
					h.brain.start_fistfight(p)
			"leave":
				if d > 260.0:
					h.queue_free()
	if outcome == "lost":
		_disband(false)
		return
	# a gun drawn on them in earnest: it becomes a gunfight
	if not guns and kind == "hunters":
		for m in live:
			if m.man.get_meta("shot", false):
				_go_guns()
				break
	_rope_tick(dt)
	# taken: held by the rope or knocked flat with a hunter standing over her
	if kind == "hunters" and outcome == "":
		var over := false
		for m in live:
			if m.mode == "foot" and m.man.global_position.distance_to(pp) < 2.6:
				over = true
		var held := held_now()
		_capture_t = _capture_t + dt if over and held else 0.0
		if _capture_t > 1.2:
			capture()

## Ruth is down (a blow or the rope) or near done in.
func held_now() -> bool:
	var p = Game.player
	return roped_t > 0.0 or Melee.is_down(p) or (p.damageable != null and p.damageable.health < p.damageable.max_health * 0.15)

func _nearest(live: Array) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for m in live:
		if m.mode != "foot":
			continue
		var d: float = m.man.global_position.distance_to(Game.player.global_position)
		if d < bd:
			bd = d
			best = m
	return best

func _engage(h: Human) -> void:
	h.brain.group = members().map(func(m): return m.man)
	if guns:
		C2.hostile(Game.missions, [h])
		if kind == "law":
			h.faction = "law"

func _on_member_hurt(info: Dictionary, h: Human) -> void:
	if is_instance_valid(h) and info.get("attacker") == Game.player and not bool(info.get("melee", false)) \
			and float(info.get("amount", 0.0)) > 15.0:
		h.set_meta("shot", true)

func _go_guns() -> void:
	if guns:
		return
	guns = true
	var live := members()
	if not live.is_empty():
		Game.missions.say_async("bh2_boss_guns", live[0].man)
	for m in live:
		if m.mode == "foot":
			m.man.set_meta("blocking", false)
			C2.hostile(Game.missions, [m.man])          # (npc_release inside: the roper too)
	_free_rope()
	Game.log_event("hunters_guns", {"county": county})

# ------------------------------------------------------------------ the lasso
func _lasso_ai(h: Human, d: float, dt: float) -> void:
	var p = Game.player
	if d > LASSO_RANGE * 0.8:
		Game.missions.npc_walk_to(h, p.global_position, Human.JOG)     # the roper works off his own head
		return
	Game.missions.npc_hold(h, p.global_position)
	h.intent.face = p.global_position - h.global_position
	_lasso_cd -= dt
	if _lasso_cd > 0.0:
		return
	_lasso_cd = 2.6
	var odds := 0.55 - (0.25 if p.get("on_horse") != null else 0.0) - d * 0.012
	throw_lasso(h, rng.randf() < odds)

## A throw: on a hit Ruth is pulled down (off her horse) and held for a few seconds.
func throw_lasso(h: Human, hit: bool) -> bool:
	Game.log_event("lasso", {"by": str(h.name), "hit": hit})
	if not hit:
		return false
	Game.missions.say_async("bh2_boss_rope", h)
	Game.missions.dismount_player()
	roped_t = 6.0
	struggle = 0.0
	_rope_by = h
	Melee.knock_down(Game.player, h)
	if not Game.headless:
		_rope_mesh = MeshInstance3D.new()
		_rope_mesh.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.62, 0.52, 0.34)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_rope_mesh.material_override = m
		Game.main.add_child(_rope_mesh)
	return true

## Press [E] to fight the rope (bots call struggle_once).
func struggle_once() -> void:
	if roped_t <= 0.0:
		return
	struggle += 0.18
	if struggle >= 1.0:
		_free_rope()
		Game.missions.say_async("bh2_ruth_free", Game.player)
		Game.log_event("lasso_broken", {})

func _rope_tick(dt: float) -> void:
	if roped_t <= 0.0:
		return
	roped_t -= dt
	if Input.is_action_just_pressed("interact"):
		struggle_once()
	var p = Game.player
	if roped_t > 0.0 and is_instance_valid(_rope_by) and _rope_by.alive:
		p.set_meta("knocked_down", true)      # held on the ground while the rope's tight
		if Game.hud and not Game.headless:
			Game.hud.prompt("[E]  Struggle against the rope")
		if _rope_mesh:
			var im: ImmediateMesh = _rope_mesh.mesh
			im.clear_surfaces()
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			im.surface_add_vertex(_rope_by.global_position + Vector3(0, 1.3, 0))
			im.surface_add_vertex(p.global_position + Vector3(0, 0.4, 0))
			im.surface_end()
	else:
		_free_rope()

func _free_rope() -> void:
	if roped_t > 0.0 or _rope_by != null:
		Game.player.set_meta("knocked_down", false)
	roped_t = 0.0
	_rope_by = null
	if _rope_mesh and is_instance_valid(_rope_mesh):
		_rope_mesh.queue_free()
	_rope_mesh = null

# ------------------------------------------------------------------ endings
## Taken alive: the county takes what she owes from her pocket, a night in the cells, out in the morning.
func capture() -> void:
	if outcome != "":
		return
	outcome = "captured"
	var st = Game.state
	st.flags["captured_by_hunters"] = true
	var owed := bounty_in(county)
	var paid := minf(owed, st.money)
	st.add_money(-paid)
	st.bounties[county] = 0.0
	if st.wanted_county == county or st.wanted > 0:
		st.wanted = 0
		st.wanted_t = 0.0
		st.wanted_changed.emit(0, county)
	var live := members()
	if not live.is_empty():
		Game.missions.say_async("bh2_boss_capture", live[0].man)
	Game.missions.say_async("bh2_ruth_caught", Game.player)
	_free_rope()
	var seat: String = SEAT_OF.get(county, "bitter_spring")
	if Game.has_meta("news"):
		Game.get_meta("news").record("captured", {"town": seat, "amount": owed})
	Game.log_event("captured", {"county": county, "owed": owed, "paid": paid, "seat": seat})
	if Game.has_meta("travel") and not (Game.headless or (Game.missions and Game.missions.autopilot)):
		await Game.get_meta("travel")._fade_card("jail", "", seat, {"hours": 14.0, "price": paid, "km": 0.0})
	if Game.sky:
		var t: float = Game.sky.hours + 14.0
		if t >= 24.0:
			t -= 24.0
			Game.sky.day += 1
		Game.sky.set_time(t)
	var P = load("res://src/missions/places.gd")
	var b: Dictionary = P.building(seat, "sheriff")
	var out: Vector3 = P.door_out(b, Mission.place(seat, 6.0, 6.0))
	Game.missions._teleport_player(out)
	if Game.player.damageable:
		Game.player.damageable.health = maxf(Game.player.damageable.health, Game.player.damageable.max_health * 0.6)
	Game.say("A night in the %s cells. The county kept $%.2f of what you owed." % [town_name(seat), paid], 5.0)
	_disband(false)

static func town_name(seat: String) -> String:
	return {"bitter_spring": "Bitter Spring", "coldwater": "Coldwater", "mesquite_wells": "Mesquite Wells", "port_linden": "Port Linden"}.get(seat, seat.capitalize())

func _call_off() -> void:
	outcome = "called_off"
	var live := members()
	if not live.is_empty():
		Game.missions.say_async("bh2_boss_calloff", live[0].man)
	_free_rope()
	for m in live:
		var h: Human = m.man
		h.brain.aggressive = false
		h.brain.target = null
		h.brain.state = h.brain.State.ROUTINE
		h.faction = "civilian"
		m.mode = "leave"
		var away: Vector3 = h.global_position + (h.global_position - Game.player.global_position).normalized() * 300.0
		Game.missions.npc_walk_to(h, away, Human.JOG)
	Game.log_event("hunters_end", {"outcome": outcome, "kind": kind})
	_leave_t = 25.0                    # seen riding off, then gone

## Clear the posse (now, or after `delay` seconds so they can be seen riding off).
func _disband(dead_ok: bool, delay := 0.0) -> void:
	var gone := posse.duplicate()
	posse.clear()
	_capture_t = 0.0
	_free_rope()
	_cool = 360.0
	if outcome != "captured" and outcome != "called_off" and outcome != "":
		Game.log_event("hunters_end", {"outcome": outcome, "kind": kind})
	var k := kind
	kind = ""
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	for m in gone:
		if is_instance_valid(m.o):
			if is_instance_valid(m.man) and (m.man.alive or not dead_ok):
				m.man.queue_free()
			m.o.queue_free()
	Game.log_event("posse_cleared", {"kind": k})
