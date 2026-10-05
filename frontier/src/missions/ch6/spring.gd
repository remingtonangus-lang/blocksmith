extends Mission
## Epilogue — Spring, 1900. The snow is off, the cottonwoods are green, the creeks run. Ride the Sable River
## country and see what the story left behind, read from every flag set along the way: Willow Bend (the Outfit
## breaking camp, Billy with the horses packed, or a note and an empty fire), Halvorsen Ranch (calves on the south
## section if the herd came through), Mesquite Wells (Inés running or walking with a hitch; the old well clean or
## bitter), Coldwater (the strike's contract or the inspector's justice), Bitter Spring (Mabry with Eben's trial or
## Pell's new depot), and a letter from California if Asa was spared. Then the credits; free roam goes on.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const C6 = preload("res://src/missions/ch6/ch6.gd")
const P = preload("res://src/missions/places.gd")

func _init() -> void:
	id = "c6_spring"
	title = "Spring, 1900"
	chapter = 6
	requires = ["c6_ink"]

func run(d) -> Variant:
	if Game.sky:
		Game.sky.day += 150
	d.set_time(10.0)
	d.set_weather("fair")
	d.set_snow(0.0)
	var branch: String = C6.branch()
	var camp := Mission.place("caddell_camp")
	await C3.start_at(d, C2.near(camp, -30.0, 20.0), camp, true)
	await d.say("c6_spring_01", Game.player)
	d.checkpoint("spring")
	# --- Willow Bend
	d.dismount_player()
	match branch:
		"high":
			var who: Human
			if C3.flag("hap_alive", false):
				who = C2.spawn_friend(d, C2.near(camp, 2.0, 1.0), {"role": "drover", "faction": "outfit", "name": "Hap Lindqvist", "seed": 7})
			else:
				who = C2.spawn_friend(d, C2.near(camp, 2.0, 1.0), {"role": "child", "faction": "outfit", "name": "Billy Pruitt", "seed": 14})
			d.npc_hold(who, Game.player.global_position)
			await d.goto(C2.near(camp, -2.0, 2.0), 4.0, "Willow Bend")
			if d.aborted(): return false
			await d.say("c6_spring_02" if C3.flag("hap_alive", false) else "c6_spring_12", who)
		"middle":
			var billy: Human = C2.spawn_friend(d, C2.near(camp, 2.0, 1.0), {"role": "child", "faction": "outfit", "name": "Billy Pruitt", "seed": 14})
			d.npc_hold(billy, Game.player.global_position)
			await d.goto(C2.near(camp, -2.0, 2.0), 4.0, "Willow Bend")
			if d.aborted(): return false
			await d.say("c6_spring_03", billy)
		_:
			await d.interact(C2.near(camp, 0.5, 0.5), "A note weighted with a stone by the cold fire")
			if d.aborted(): return false
			await d.paper("To R.", ["We've gone. Don't follow.", "Doc took the medicine chest. Billy took his horse. We left you the wagon.",
				"— the Outfit"], "page", "Put it in your coat")
			await d.say("c6_spring_04", Game.player)
	var visited := 1
	# --- Halvorsen Ranch: calves if the herd came through
	var ranch := Mission.place("halvorsen_ranch")
	var ingrid: Human = C2.spawn_friend(d, C2.near(ranch, -4.0, 2.0), {"role": "rancher", "faction": "civilian", "name": "Ingrid Halvorsen", "seed": 3101})
	d.npc_hold(ingrid, ranch)
	if int(C3.flag("cattle_delivered", 0)) >= 12:
		C3.herd(d, C2.near(ranch, 30.0, 40.0), mini(int(C3.flag("cattle_delivered", 12)), 16), 1900)
	await d.mount_up("Mount up")
	await d.goto(C2.near(ingrid.global_position, -3.0, 0.0), 6.0, "Ride to the Halvorsen Ranch", true)
	if d.aborted(): return false
	await d.say("c6_spring_05", ingrid)
	visited += 1
	d.checkpoint("ranch")
	# --- Mesquite Wells
	var well := C3.road("windmill_flats", "mesquite_wells", 0.93, "mesquite_wells")
	var ines: Human = C2.spawn_friend(d, C2.near(well, 3.0, -2.0), {"role": "child", "faction": "civilian", "name": "Inés Ybarra", "seed": 3203})
	var rosa: Human = C2.spawn_friend(d, C2.near(well, 5.0, 1.0), {"role": "lady", "faction": "civilian", "name": "Rosa Ybarra", "seed": 3201})
	d.npc_hold(rosa, well)
	if C3.flag("ines_leg_clean", true):
		d.npc_walk_to(ines, C2.near(well, -20.0, 6.0), Human.JOG)
	else:
		d.npc_walk_to(ines, C2.near(well, -10.0, 4.0), Human.WALK)
	await d.goto(C2.near(well, -4.0, 2.0), 8.0, "Ride to Mesquite Wells", true)
	if d.aborted(): return false
	await d.say("c6_spring_06", ines)
	if C3.flag("well_fouled", false):
		await d.say("c6_spring_07", rosa)
	visited += 1
	# --- Coldwater
	var cw := C2.spot("coldwater", 22.0, -16.0)
	var signed: bool = C3.flag("strike_terms", "inspector") == "signed"
	var speaker: Human = C2.spawn_friend(d, cw, {"role": "lady" if signed else "worker", "faction": "civilian",
		"name": "Nora Kilbride" if signed else "Dai Pritchard", "seed": 4102 if signed else 4103})
	d.npc_hold(speaker, Game.player.global_position)
	await d.goto(C2.near(cw, -4.0, 2.0), 8.0, "Ride up to Coldwater", true)
	if d.aborted(): return false
	await d.say("c6_spring_08" if signed else "c6_spring_09", speaker)
	visited += 1
	# --- Bitter Spring: Mabry at his desk
	var shb := P.building("bitter_spring", "sheriff")
	var office := P.door_out(shb, Mission.place("bitter_spring", -20.0, 14.0))
	var mabry: Human = d.spawn_at(P.at(P.spot(shb, "sheriff_desk"), C2.near(office, 2.0, 0.0)), {"role": "lawman", "faction": "law",
		"name": "Sheriff Mabry", "seed": 503}, office)
	if C3.flag("eben_fate", "") == "jailed":
		d.spawn_at(P.at(P.spot(shb, "cell_bunk"), C2.near(office, 3.0, 3.0)), {"role": "gunman", "faction": "civilian", "name": "Eben Shale", "seed": 6201}, office)
	P.open_doors(shb, office)
	await d.goto(office, 6.0, "Ride into Bitter Spring", true)
	if d.aborted(): return false
	d.dismount_player()
	await d.goto(P.door_in(shb, office), 2.5, "Look in on Sheriff Mabry")
	if d.aborted(): return false
	await d.say("c6_spring_10" if branch == "high" else "c6_spring_11", mabry)
	visited += 1
	if C3.flag("spared_asa", false):
		await d.paper("A letter, postmarked Sonoma", ["Mrs. Caddell —", "I work horses on a ranch near Sonoma under a name you don't know.",
			"I hold them for the right people now.", "— A."], "page", "Fold it away")
	if branch != "low":
		await d.say("c6_spring_13", Game.player)
	C3.set_flag("epilogue_visited", visited)
	C3.set_flag("game_complete", true)
	await d.credits()
	return true
