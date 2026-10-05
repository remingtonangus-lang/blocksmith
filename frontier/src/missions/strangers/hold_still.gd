extends Mission
## Stranger — Hold Still (moral, comic edge). Theodora Lusk, photographic artist, wants a woman with a rifle and a
## cougar on the ledge over Thornwood Creek. The cat wakes; Ruth stands her ground; the plate is the best Theodora
## will ever make — for a dime-novel publisher's "Miss Ruthie Rides Again", Ruth's buried show name. Let her print it
## or break the plate. Flag: posed_for_novel (the astronomer and the medicine-show man have read it).

const ST = preload("res://src/missions/strangers/st.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")

func _init() -> void:
	id = "s_photo"
	title = "Hold Still"
	chapter = 2
	stranger = true
	region = "Thornwood"
	requires = ["c2_thornwood"]
	start_pos = Mission.road_point("dunmore_homestead", "thornwood_logging", 0.55)

## Highest dry ground within r of p (the ledge).
static func high_ground(p: Vector3, r: float) -> Vector3:
	var best := p
	for ring in [0.4, 0.7, 1.0]:
		for k in 12:
			var a := TAU * k / 12.0
			var q := p + Vector3(cos(a), 0, sin(a)) * r * float(ring)
			q.y = Game.world.height(q.x, q.z)
			if q.y > best.y and not Game.world.is_water(q.x, q.z):
				best = q
	return best

func run(d) -> Variant:
	d.set_time(15.0)
	d.set_weather("clear")
	var start := C3.road("dunmore_homestead", "thornwood_logging", 0.55, "thornwood_logging")
	await C3.start_at(d, start, start + Vector3(10, 0, 0), false)
	var theo := ST.person(d, C2.near(start, 3.0, 1.5), {"role": "lady", "name": "Theodora Lusk", "seed": 9301})
	d.cine_begin()
	await d.say("s_photo_01", theo)
	await d.say("s_photo_02", Game.player)
	await d.say("s_photo_03", theo)
	await d.say("s_photo_04", theo)
	await d.say("s_photo_05", Game.player)
	await d.say("s_photo_06", theo)
	d.cine_end()
	d.checkpoint("ledge")
	var ledge := high_ground(start, 160.0)
	d.npc_walk_to(theo, C2.near(ledge, -6.0, -4.0))
	await d.goto(ledge, 6.0, "Climb to the ledge over Thornwood Creek")
	if d.aborted(): return false
	d._put_on_ground(theo, C2.near(ledge, -6.0, -4.0))
	d.npc_hold(theo, ledge)
	var fwd := Vector3(-sin(Game.player.facing), 0, -cos(Game.player.facing))
	d.say_async("s_photo_07", theo)
	await ST.hunt(d, "cougar", ledge + fwd * 28.0, "The cougar's awake. Hold your ground and bring it down", 9302)
	if d.aborted(): return false
	if Game.player.damageable and not Game.player.damageable.alive:
		return false
	d.checkpoint("plate")
	d.npc_hold(theo, Game.player.global_position)
	d.cine_begin()
	await d.say("s_photo_08", theo)
	await d.say("s_photo_09", Game.player)
	await d.say("s_photo_10", theo)
	await d.say("s_photo_11", Game.player)
	var pick: int = await d.choose("Miss Ruthie Rides Again. A dry plate with your face on it, bound for Chicago.",
		["Let her print it.", "Take the plate and break it."])
	ST.set_flag("posed_for_novel", pick == 0)
	if pick == 0:
		await d.say("s_photo_12", Game.player)
		await d.say("s_photo_13", theo)
		ST.earn(5.0)
	else:
		await d.say("s_photo_14", Game.player)
		await d.say("s_photo_15", theo)
		await d.say("s_photo_16", theo)
	d.cine_end()
	return true
