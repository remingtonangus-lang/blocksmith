extends Mission
## Companion — Del's Marker (Del). Orrin Tate, the syndicate's money man in Port Linden, holds Del's marker, and his
## collector has been to camp. Del means to take the night boat. Ruth goes with her to the pier, past Tate's men
## (unseen, or a fight), and on the pier Tate is waiting. Pay the forty dollars yourself, or hand Del a paid
## ticket and let her choose (she stays; Tate's men draw). Flag del_marker = "paid" / "ticket".

const ST = preload("res://src/missions/strangers/st.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")

func _init() -> void:
	id = "p_del"
	title = "Del's Marker"
	chapter = 3
	stranger = true
	companion = "del"
	region = "Port Linden"
	requires = ["c3_ranch"]
	needs_flags = {"del_joined": true}
	start_pos = Mission.place("caddell_camp", -3.0, 2.0)

func flags_ok() -> bool:
	return super.flags_ok() and Game.state.flags.get("del_left", false) != true

## The lake shore below Port Linden: the dry point nearest the water toward the lake centre.
static func pier() -> Vector3:
	var town := Mission.place("port_linden")
	var lk = Game.world.features.get("lake", {})
	var c := town + Vector3(60.0, 0, 0)
	if typeof(lk) == TYPE_DICTIONARY and lk.has("u"):
		var sz := float(Game.world.features.get("size_m", 8192.0))
		c = Vector3((float(lk.u) - 0.5) * sz, 0, (float(lk.v) - 0.5) * sz)
	var dir := (c - town)
	dir.y = 0.0
	dir = dir.normalized()
	var p := town
	for i in 60:
		var q := town + dir * float(i) * 8.0
		if Game.world.is_water(q.x, q.z):
			break
		p = q
	return C3.dry(p)

func run(d) -> Variant:
	d.set_time(21.5)
	d.set_weather("clear")
	var camp := C3.dry(Mission.place("caddell_camp", -3.0, 2.0))
	await C3.start_at(d, C2.near(camp, 3.0, 2.0), camp, false)
	var del := ST.person(d, camp, {"role": "gambler", "faction": "outfit", "name": "Del Arceneaux", "seed": 2201, "weapon": "lockhart_sa", "skill": 0.65})
	d.cine_begin()
	await d.say("p_del_01", del)
	await d.say("p_del_02", del)
	await d.say("p_del_03", Game.player)
	await d.say("p_del_04", del)
	d.cine_end()
	d.checkpoint("ride")
	var landing := pier()
	var approach := C2.near(landing, -70.0, 40.0)
	await d.mount_up("Ride for Port Linden")
	if d.aborted(): return false
	await d.goto(approach, 12.0, "Ride to Port Linden with Del", true)
	if d.aborted(): return false
	d.dismount_player()
	d._put_on_ground(del, C2.near(approach, 2.0, 2.0))
	var men: Array = ST.gang(d, C2.near(landing, -30.0, 16.0), 3, "Tate's Man", 9701, "lockhart_sa", 8.0)
	for m in men:
		d.npc_hold(m, approach)
	d.checkpoint("pier")
	if Game.hud and not d.autopilot:
		Game.hud.notice("Crouch (C / B) and keep to the shadows of the warehouses", 5.0)
	d.npc_walk_to(del, C2.near(landing, 2.0, -2.0))
	var quiet: bool = await d.sneak_to(landing, 5.0, "Get Del down to the pier past Tate's men", men)
	if d.aborted(): return false
	if not quiet:
		await d.say("p_del_05", C2.one(men))
		C2.hostile(d, men)
		await d.wait_dead(men, "Tate's men")
		if d.aborted(): return false
	d._put_on_ground(del, C2.near(landing, 2.0, -2.0))
	var tate := ST.person(d, C2.near(landing, 5.0, 3.0), {"role": "gambler", "name": "Orrin Tate", "seed": 9702})
	var guard: Array = ST.gang(d, C2.near(landing, 8.0, 5.0), 2, "Tate's Man", 9703, "lockhart_sa", 2.0)
	d.npc_hold(del, tate.global_position if tate else landing)
	d.checkpoint("tate")
	d.cine_begin()
	await d.say("p_del_06", tate)
	var pick: int = await d.choose("Orrin Tate on the pier with Del's marker in his waistcoat. The night boat's whistle out on the lake.",
		["Pay her marker. Forty dollars.", "Hand Del a paid ticket and let her choose."])
	ST.set_flag("del_marker", "paid" if pick == 0 else "ticket")
	if pick == 0:
		await d.say("p_del_07", Game.player)
		ST.pay(40.0)
		await d.say("p_del_08", tate)
		await d.say("p_del_09", del)
		d.cine_end()
	else:
		await d.say("p_del_10", Game.player)
		await d.say("p_del_11", del)
		await d.say("p_del_12", del)
		await d.say("p_del_13", tate)
		d.cine_end()
		d.npc_release(del)
		C2.hostile(d, guard + [tate])
		await d.wait_dead(guard + [tate], "Tate and his men")
		if d.aborted(): return false
		if del == null or not is_instance_valid(del) or not del.alive:
			d.fail("Del was killed")
			return false
		d.npc_hold(del, Game.player.global_position)
	await d.say("p_del_14", del)
	await d.say("p_del_15", Game.player)
	return true
