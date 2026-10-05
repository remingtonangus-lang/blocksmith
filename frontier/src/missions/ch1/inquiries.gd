extends Mission
## Chapter 1, mission 3 — Inquiries. The saloon, a cheating card player, the sheriff's warning, and a fresh grave.

func _init() -> void:
	id = "c1_inquiries"
	title = "Inquiries"
	chapter = 1
	requires = ["c1_drover"]

func run(d) -> Variant:
	d.set_time(20.3)
	var saloon := Mission.place("bitter_spring", 12.0, -8.0)
	await d.goto(saloon, 6.0, "Go to the Gilded Spur saloon")
	if d.aborted(): return false
	var bar: Array = d.spawn_group(saloon + Vector3(2.0, 0, -2.0), 1, {"role": "bartender", "faction": "civilian", "name": "Bartender", "seed": 501}, 0.3)
	var cards: Array = d.spawn_group(saloon + Vector3(-3.0, 0, 1.5), 1, {"role": "gambler", "faction": "civilian", "name": "Card Player", "seed": 502}, 0.3)
	await d.interact(saloon + Vector3(2.0, 0, -2.0), "Talk to the bartender")
	if d.aborted(): return false
	d.cine_begin()
	var b = bar[0] if bar.size() > 0 else null
	for id in ["c1_inq_01", "c1_inq_02", "c1_inq_03", "c1_inq_04", "c1_inq_05"]:
		await d.say(id, Game.player if id in ["c1_inq_02", "c1_inq_04"] else b)
	await d.say("c1_inq_06", cards[0] if cards.size() > 0 else null)
	await d.say("c1_inq_07", Game.player)
	d.cine_end()
	d.checkpoint("saloon")
	var office := Mission.place("bitter_spring", -20.0, 14.0)
	var sheriff: Array = d.spawn_group(office, 1, {"role": "lawman", "faction": "law", "name": "Sheriff Mabry", "seed": 503, "weapon": "lockhart_sa"}, 0.3)
	await d.goto(office, 5.0, "The sheriff wants a word")
	if d.aborted(): return false
	d.cine_begin()
	var m = sheriff[0] if sheriff.size() > 0 else null
	for id in ["c1_inq_08", "c1_inq_09", "c1_inq_10", "c1_inq_11", "c1_inq_12"]:
		await d.say(id, Game.player if id in ["c1_inq_09", "c1_inq_11"] else m)
	d.cine_end()
	var grave := Mission.place("bitter_spring", -110.0, -95.0)
	await d.interact(grave, "Find Arliss Doane's grave on the hill")
	if d.aborted(): return false
	await d.say("c1_inq_13", Game.player)
	return true
