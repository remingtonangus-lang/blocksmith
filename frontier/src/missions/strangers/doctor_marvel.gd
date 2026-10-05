extends Mission
## Stranger — Doctor Marvel's Elixir (comic, then sour). A medicine show at the Thornwood logging camp: half-price
## Kestrel Elixir to anyone who outshoots Miss Pearl at glass balls. Ruth shoots (a glass-ball exhibition), and the
## "Professor" knows that shooting: he barked for Colonel Brady's show the season "Miss Ruthie, the Ozark Wonder"
## joined. Reads posed_for_novel (he sells the dime novel). The elixir is laudanum: tell the loggers, or let an old
## acquaintance pack up and go. Flag: exposed_marvel.

const ST = preload("res://src/missions/strangers/st.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")

func _init() -> void:
	id = "s_marvel"
	title = "Doctor Marvel's Elixir"
	chapter = 3
	stranger = true
	region = "Thornwood"
	requires = ["c3_fork"]
	start_pos = Mission.place("thornwood_logging", 22.0, 16.0)

func run(d) -> Variant:
	d.set_time(16.5)
	d.set_weather("clear")
	var wagon := C3.dry(Mission.place("thornwood_logging", 22.0, 16.0))
	await C3.start_at(d, C2.near(wagon, -5.0, 3.0), wagon, false)
	var marvel := ST.person(d, wagon, {"role": "gambler", "name": "Professor Cassius Marvel", "seed": 9951})
	var pearl := ST.person(d, C2.near(wagon, 2.0, 1.0), {"role": "lady", "name": "Miss Pearl", "seed": 9952})
	var crowd: Array = d.spawn_group(C2.near(wagon, -6.0, 6.0), 4, {"role": "worker", "faction": "civilian", "name": "Logger", "seed": 9953}, 3.0)
	for h in crowd:
		d.npc_hold(h, wagon)
	var ned = C2.one(crowd)
	if ned:
		ned.display_name = "Ned Harkey"
	d.cine_begin()
	await d.say("s_marvel_01", marvel)
	await d.say("s_marvel_02", pearl)
	await d.say("s_marvel_03", Game.player)
	d.cine_end()
	d.checkpoint("glass")
	var res: Dictionary = await d.minigame("glass_balls", {"count": 8, "need": 6, "interval": 1.5, "distance": 10.0, "seed": 9954})
	if d.aborted(): return false
	var won: bool = res.get("ok", false)
	ST.set_flag("outshot_pearl", won)
	d.checkpoint("marvel")
	d.cine_begin()
	if won:
		await d.say("s_marvel_04", marvel)
		ST.earn(2.0)
	else:
		await d.say("s_marvel_15", pearl)
	await d.say("s_marvel_05", marvel)
	if ST.flag("posed_for_novel"):
		await d.say("s_marvel_06", marvel)
	await d.say("s_marvel_07", Game.player)
	await d.say("s_marvel_08", marvel)
	await d.say("s_marvel_09", ned)
	var pick: int = await d.choose("Laudanum and molasses at a dollar a bottle, sold to men who swing axes for a living.",
		["Tell the loggers what's in the bottles.", "Let Cassius pack up and go."])
	ST.set_flag("exposed_marvel", pick == 0)
	if pick == 0:
		await d.say("s_marvel_10", Game.player)
		await d.say("s_marvel_11", marvel)
		ST.deed("help_stranger")
	else:
		await d.say("s_marvel_12", Game.player)
		await d.say("s_marvel_13", marvel)
		await d.say("s_marvel_14", pearl)
		ST.standing(-0.5, "let a laudanum seller go")
	d.cine_end()
	return true
