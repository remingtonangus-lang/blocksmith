extends Mission
## Chapter 3, mission 3 — Through the Breaks. The drive: Ruth rides drag behind twenty-four head of Ingrid's
## cattle (ch3/herd.gd) with Teodoro on point and Billy on swing, turning back strays. At the fork: the Narrows
## (fast; Shale's rustlers shoot from the rim and stampede the herd, then a fight) or round the mesa (slower, a dry
## camp, dry lightning stampedes them at night). Turn the leaders or lose head in the rocks. Whatever reaches the
## Ybarra well is Ingrid's new start (and, if Ruth asked, her pay: a dollar a head).

const C3 = preload("res://src/missions/ch3/ch3.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")

func _init() -> void:
	id = "c3_drive"
	title = "Through the Breaks"
	chapter = 3
	requires = ["c3_doc"]

func run(d) -> Variant:
	d.set_time(7.0)
	d.set_weather("clear")
	var a := "windmill_flats"
	var b := "mesquite_wells"
	var herd_at := C3.road(a, b, 0.6, b)
	var behind := C3.road(a, b, 0.575, b)
	var fork := C3.road(a, b, 0.67, b)
	var well := C3.road(a, b, 0.93, b)
	await C3.start_at(d, behind, herd_at, true)
	var herd = C3.herd(d, herd_at, 24, 1899)
	var dir := Vector3(fork.x - herd_at.x, 0, fork.z - herd_at.z).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var teo = C3.rider(d, herd_at + dir * 28.0, {"role": "worker", "faction": "outfit", "name": "Teodoro Baca", "seed": 3301, "weapon": "harlan_carbine"})
	var billy = C3.rider(d, herd_at + side * 16.0, {"role": "child", "faction": "outfit", "name": "Billy Pruitt", "seed": 14, "health": 160.0}, "paint")
	teo.ride_with(herd.center_node, dir * 26.0)
	billy.ride_with(herd.center_node, side * 15.0)
	d.cine_begin()
	await d.say("c3_drive_01", billy.man)
	await d.say("c3_drive_02", teo.man)
	await d.say("c3_drive_03", Game.player)
	d.cine_end()
	if Game.hud and not d.autopilot:
		Game.hud.notice("Ride behind the herd to push it; ride round a stray to turn it back", 6.0)
	d.checkpoint("trail")
	var head: int = await d.drive(herd, fork, 16.0, "Drive the herd toward the fork", 2, 8, "c3_drive_04")
	if d.aborted(): return false
	d.checkpoint("fork")
	d.cine_begin()
	await d.say("c3_drive_05", teo.man)
	await d.say("c3_drive_06", billy.man)
	var route: int = await d.choose("The Narrows or the long way round the mesa?",
		["Take the Narrows. Faster's kinder when they're this dry.", "Go round the mesa. Longer, but I can see who's coming."])
	C3.set_flag("drive_route", "narrows" if route == 0 else "mesa")
	if route == 0:
		await d.say("c3_drive_07", Game.player)
		d.cine_end()
		var narrows := C3.road(a, b, 0.74, b)
		head = await d.drive(herd, narrows, 16.0, "Drive the herd into the Narrows", 0, 8)
		if d.aborted(): return false
		# rustlers on the rim
		var rim: Vector3 = C2.near(herd.center(), side.x * 45.0 + dir.x * 10.0, side.z * 45.0 + dir.z * 10.0)
		var rustlers: Array = d.spawn_group(rim, 4, {"role": "gunman", "faction": "syndicate", "name": "Rustler", "seed": 3310,
			"weapon": "merriman_lever", "skill": 0.35, "aggressive": false}, 5.0)
		if rustlers.size() > 0:
			rustlers[0].display_name = "Harl Dunphy"
		for r in rustlers:
			d.npc_hold(r, herd.center())
		await d.say("c3_drive_09", teo.man)
		if not d.autopilot:
			Horse.alarm(herd.center(), 60.0, 0.6, "gunfire")
		await d.say("c3_drive_10", billy.man)
		await d.say("c3_drive_11", teo.man)
		d.checkpoint("stampede")
		var turned: bool = await d.stampede(herd, dir.rotated(Vector3.UP, 0.8), "Turn the leaders", 40.0, 5)
		if d.aborted(): return false
		await d.say("c3_drive_16" if turned else "c3_drive_17", billy.man if turned else teo.man)
		C2.hostile(d, rustlers)
		await d.say("c3_drive_18", C2.one(rustlers))
		await d.say("c3_drive_19", Game.player)
		await d.wait_dead(rustlers, "Drive off the rustlers")
		if d.aborted(): return false
	else:
		await d.say("c3_drive_08", Game.player)
		d.cine_end()
		var mesa: Vector3 = C3.dry(fork + side * 140.0 + dir * 90.0)
		head = await d.drive(herd, mesa, 18.0, "Drive the herd round the mesa", 2, 8, "c3_drive_04")
		if d.aborted(): return false
		d.set_time(21.6)
		d.cine_begin()
		await d.say("c3_drive_28", Game.player)
		await d.say("c3_drive_29", billy.man)
		await d.say("c3_drive_13", billy.man)
		await d.say("c3_drive_14", Game.player)
		d.cine_end()
		d.checkpoint("dry_camp")
		await d.say("c3_drive_12", teo.man)
		await d.say("c3_drive_15", billy.man)
		var turned2: bool = await d.stampede(herd, side, "Turn the leaders in the dark", 45.0, 4)
		if d.aborted(): return false
		await d.say("c3_drive_16" if turned2 else "c3_drive_17", billy.man if turned2 else teo.man)
		d.set_time(6.4)
	d.checkpoint("last_leg")
	teo.ride_with(herd.center_node, (well - herd.center()).normalized() * 26.0)
	head = await d.drive(herd, well, 18.0, "Bring the herd to the Ybarra well", 0, 6)
	if d.aborted(): return false
	var mateo := C2.spawn_friend(d, C2.near(well, 3.0, -2.0), {"role": "rancher", "faction": "civilian", "name": "Mateo Ybarra", "seed": 3202})
	d.npc_hold(mateo, Game.player.global_position)
	d.cine_begin()
	await d.say("c3_drive_20", teo.man)
	await d.say("c3_drive_21", mateo)
	await d.say("c3_drive_22", billy.man)
	await d.say("c3_drive_23" if head >= 20 else "c3_drive_24", Game.player)
	await d.say("c3_drive_25", teo.man)
	await d.say("c3_drive_26", billy.man)
	await d.say("c3_drive_27", Game.player)
	if C3.flag("ingrid_pays"):
		await d.say("c3_drive_30", Game.player)
		if Game.state:
			Game.state.add_money(float(head))
	d.cine_end()
	C3.set_flag("cattle_delivered", head)
	if Game.state and head >= 20:
		Game.state.good_deed("help_stranger")
	d.dismount_player()
	return true
