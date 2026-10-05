extends Mission
## Chapter 6, mission 3 — Ink. Port Linden, the morning after. High: Fenn's Lantern has printed Pell's ledger; take
## the territorial marshal to Pell in the Meridian & Western railroad office and watch the lawyer reach for his hat.
## Middle: Pell, untouched, on the depot platform; Ruth leaves with Billy and finally sets Tom's watch. Low: Ruth and
## Eben's old riders rob Pell's own office; the city marshal's men answer; Doc says what the Outfit is thinking.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const C6 = preload("res://src/missions/ch6/ch6.gd")
const P = preload("res://src/missions/places.gd")

func _init() -> void:
	id = "c6_ink"
	title = "Ink"
	chapter = 6
	requires = ["c6_eben"]

func run(d) -> Variant:
	d.set_time(9.2)
	d.set_weather("fair")
	var branch: String = C6.branch()
	var ob := P.building("port_linden", "office")
	var office_fb := C2.spot("port_linden", 40.0, -20.0)
	var front := P.door_out(ob, office_fb)
	var inside := P.inside(ob, 0.55, office_fb)
	await C3.start_at(d, C2.near(front, -60.0, 20.0), front, false)
	d.checkpoint("port_linden")
	match branch:
		"high":
			var nb := P.building("port_linden", "newspaper")
			var fenn: Human = C2.spawn_friend(d, P.door_out(nb, C2.near(front, -30.0, 6.0)), {"role": "townsfolk", "faction": "civilian", "name": "Augustus Fenn", "seed": 2101})
			d.npc_hold(fenn, Game.player.global_position)
			await d.goto(fenn.global_position, 3.0, "Fenn has the morning edition")
			if d.aborted(): return false
			await d.paper("THE LANTERN", ["!THE SYNDICATE'S LEDGER", "Every acre, every forged name, every payment, in Lucius Pell's own hand.",
				"Territorial court issues warrant. Eben Shale held for trial.", "— A. Fenn, editor"], "page", "Fold it under your arm")
			await d.say("c6_ink_01", fenn)
			var marshal: Human = C2.spawn_friend(d, C2.near(front, -6.0, 3.0), {"role": "lawman", "faction": "law", "name": "Marshal Ezra Coyle", "seed": 6301, "weapon": "harlan_carbine"})
			d.npc_hold(marshal, front)
			var pell: Human = d.spawn_at(inside, {"role": "townsfolk", "faction": "civilian", "name": "Lucius Pell", "seed": 2501}, front)
			P.open_doors(ob, front)
			await d.goto(front, 3.0, "Meet the territorial marshal at the railroad office")
			if d.aborted(): return false
			d.npc_walk_to(marshal, inside)
			await d.goto(P.door_in(ob, inside), 2.5, "Go in with the marshal")
			if d.aborted(): return false
			d._put_on_ground(marshal, inside + (front - inside).normalized() * 1.5)
			d.npc_hold(marshal, pell.global_position)
			d.cine_begin()
			await d.say("c6_ink_02", marshal)
			await d.say("c6_ink_03", pell)
			await d.say("c6_ink_04", Game.player)
			await d.say("c6_ink_13", Game.player)
			d.cine_end()
			C3.set_flag("pell_fate", "arrested")
		"middle":
			var db := P.building("port_linden", "depot")
			var platform := P.at(P.spot(db, "platform"), C2.near(front, 30.0, 40.0))
			var pell: Human = C2.spawn_friend(d, platform, {"role": "townsfolk", "faction": "civilian", "name": "Lucius Pell", "seed": 2501})
			var billy: Human = C2.spawn_friend(d, C2.near(platform, -6.0, 3.0), {"role": "child", "faction": "outfit", "name": "Billy Pruitt", "seed": 14})
			d.npc_hold(pell, Game.player.global_position)
			d.npc_hold(billy, Game.player.global_position)
			await d.goto(C2.near(platform, -3.0, 1.0), 3.0, "Walk down to the depot platform")
			if d.aborted(): return false
			d.cine_begin()
			await d.say("c6_ink_05", pell)
			await d.say("c6_ink_06", Game.player)
			await d.say("c6_ink_07", pell)
			await d.say("c6_ink_08", billy)
			await d.say("c6_ink_09", Game.player)
			d.cine_end()
			await d.mount_up("Mount up")
			await d.goto(C2.near(platform, -260.0, 60.0), 20.0, "Ride out of Port Linden with Billy", true)
			if d.aborted(): return false
			await d.say("c6_ink_14", Game.player)
			C3.set_flag("watch_set", true)
			C3.set_flag("pell_fate", "untouched")
		_:
			var pell: Human = d.spawn_at(inside, {"role": "townsfolk", "faction": "civilian", "name": "Lucius Pell", "seed": 2501}, front)
			var doc: Human = C2.spawn_friend(d, C2.near(front, -8.0, 4.0), {"role": "townsfolk", "faction": "outfit", "name": "Cornelius Abernathy", "seed": 3204})
			d.npc_hold(doc, front)
			P.open_doors(ob, front)
			await d.goto(P.door_in(ob, inside), 2.5, "Walk into Pell's office")
			if d.aborted(): return false
			d.cine_begin()
			await d.say("c6_ink_10", pell)
			await d.say("c6_ink_11", Game.player)
			d.cine_end()
			if Game.state:
				Game.state.add_money(900.0)
				Game.state.crime("robbery", inside, pell)
			var marshals: Array = d.spawn_group(C2.near(front, -30.0, 10.0), 4, {"role": "lawman", "faction": "law", "name": "City Marshal's Man",
				"seed": 6320, "weapon": "harlan_carbine", "skill": 0.45}, 5.0)
			for m in marshals:
				m.brain.aggressive = true
				m.brain.share_target(Game.player)
			d.checkpoint("marshals")
			await d.wait_dead(marshals, "Get out of Port Linden")
			if d.aborted(): return false
			d.npc_hold(doc, Game.player.global_position)
			await d.say("c6_ink_12", doc)
			await d.say("c6_ink_15", Game.player)
			C3.set_flag("pell_fate", "robbed")
	return true
