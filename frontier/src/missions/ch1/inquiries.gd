extends Mission
## Chapter 1, mission 3 — Inquiries. The saloon, a cheating card player, the sheriff's warning, and a fresh grave.

const P = preload("res://src/missions/places.gd")

func _init() -> void:
	id = "c1_inquiries"
	title = "Inquiries"
	chapter = 1
	requires = ["c1_drover"]

func run(d) -> Variant:
	d.set_time(20.3)
	var saloon := Mission.place("bitter_spring", 12.0, -8.0)
	var sb := P.building("bitter_spring", "saloon")
	await d.goto(P.door_out(sb, saloon), 4.0, "Go to the Gilded Spur saloon")
	if d.aborted(): return false
	var bt := P.spot(sb, "bartender")
	var ch := P.spot(sb, "chair", 1)
	var bar: Array = [d.spawn_at(P.at(bt, saloon + Vector3(2.0, 0, -2.0)), {"role": "bartender", "faction": "civilian", "name": "Bartender", "seed": 501}, P.look(bt, saloon))]
	var cards: Array = [d.spawn_at(P.at(ch, saloon + Vector3(-3.0, 0, 1.5)), {"role": "gambler", "faction": "civilian", "name": "Card Player", "seed": 502}, P.look(ch, saloon))]
	await d.interact(P.at(P.spot(sb, "bar_patron"), saloon + Vector3(2.0, 0, -2.0)), "Talk to the bartender")
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
	var shb := P.building("bitter_spring", "sheriff")
	var desk := P.spot(shb, "sheriff_desk")
	var sheriff: Array = [d.spawn_at(P.at(desk, office), {"role": "lawman", "faction": "law", "name": "Sheriff Mabry", "seed": 503, "weapon": "lockhart_sa"}, P.look(desk, office))]
	await d.goto(P.door_in(shb, office), 2.5, "The sheriff wants a word at his office")
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
