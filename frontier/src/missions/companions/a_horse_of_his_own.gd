extends Mission
## Companion — A Horse of His Own (Billy). Amos Pike, the Thornwood foreman, kept Billy's colt Chance "for board".
## A moonless night: creep into the camp corral past Pike's men, and decide how the colt leaves — fifteen dollars
## under a stone on the gatepost, or taken for three years of unpaid wages (Billy cheers; Standing down). Either way
## Pike wakes and the dogs are up: ride out. Billy learns from what Ruth does. Flag billy_colt = "paid" / "taken".

const ST = preload("res://src/missions/strangers/st.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")

func _init() -> void:
	id = "p_billy"
	title = "A Horse of His Own"
	chapter = 4
	stranger = true
	companion = "billy"
	region = "Thornwood"
	requires = ["c3_fork"]
	needs_flags = {"billy_joined": true}
	start_pos = Mission.place("caddell_camp", 9.0, 5.0)

func run(d) -> Variant:
	d.set_time(22.5)
	d.set_weather("clear")
	var camp := C3.dry(Mission.place("caddell_camp", 9.0, 5.0))
	await C3.start_at(d, C2.near(camp, -3.0, 2.0), camp, false)
	var billy := ST.person(d, camp, {"role": "child", "faction": "outfit", "name": "Billy Pruitt", "seed": 14})
	d.cine_begin()
	await d.say("p_billy_01", billy)
	await d.say("p_billy_02", billy)
	await d.say("p_billy_03", Game.player)
	await d.say("p_billy_04", billy)
	d.cine_end()
	d.checkpoint("ride")
	var corral := C3.dry(Mission.place("thornwood_logging", -26.0, 18.0))
	var edge := C2.near(corral, -80.0, 50.0)
	await d.mount_up("Ride for Thornwood with Billy")
	if d.aborted(): return false
	await d.goto(edge, 12.0, "Ride to the edge of the Thornwood camp", true)
	if d.aborted(): return false
	d.dismount_player()
	d._put_on_ground(billy, C2.near(edge, 2.0, 1.5))
	await d.say("p_billy_05", Game.player)
	var watch: Array = ST.gang(d, C2.near(corral, 10.0, -12.0), 2, "Camp Watchman", 9901, "merriman_lever", 6.0)
	for w in watch:
		d.npc_hold(w, edge)
	d.checkpoint("corral")
	d.npc_walk_to(billy, C2.near(corral, -2.0, 1.0))
	var quiet: bool = await d.sneak_to(corral, 3.5, "Creep to the corral with Billy", watch)
	if d.aborted(): return false
	ST.set_flag("billy_corral_quiet", quiet)
	d._put_on_ground(billy, C2.near(corral, -1.5, 1.0))
	d.npc_hold(billy, corral)
	await d.say("p_billy_06", billy)
	var pick: int = await d.choose("Billy's colt in Amos Pike's corral, and a gatepost with a flat stone on it.",
		["Leave fifteen dollars under the stone.", "Take him. They owe the boy three years of wages."])
	ST.set_flag("billy_colt", "paid" if pick == 0 else "taken")
	if pick == 0:
		await d.say("p_billy_07", Game.player)
		ST.pay(15.0)
		await d.say("p_billy_08", billy)
		await d.say("p_billy_09", Game.player)
	else:
		await d.say("p_billy_10", Game.player)
		await d.say("p_billy_11", billy)
		ST.standing(-1.0, "took a horse by night")
	var pike := ST.person(d, C2.near(corral, 22.0, -10.0), {"role": "worker", "name": "Amos Pike", "seed": 9902, "weapon": "harlan_carbine"})
	await d.say("p_billy_12", pike)
	if not quiet or pick == 1:
		C2.hostile(d, watch)
	await d.mount_up("Get on your horse — Billy has Chance")
	if d.aborted(): return false
	d.checkpoint("away")
	await d.escape(corral, 200.0, "Ride out of Thornwood", 60.0)
	if d.aborted(): return false
	await d.goto(camp, 12.0, "Home to Willow Bend", true)
	if d.aborted(): return false
	d.dismount_player()
	d._put_on_ground(billy, C2.near(camp, 2.0, 1.0))
	d.npc_hold(billy, Game.player.global_position)
	d.cine_begin()
	await d.say("p_billy_13", billy)
	await d.say("p_billy_14", billy)
	await d.say("p_billy_15", Game.player)
	d.cine_end()
	ST.set_flag("billy_has_colt", true)
	return true
