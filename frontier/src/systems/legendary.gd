extends Node
## Legendary animals: four unique beasts built on the wildlife species (src/actors/animal.gd), each bigger, tougher
## and named, each with a trail of clues. Eli Thackery, a trapper who keeps a stall at Greer's Post, tells their
## stories; ask about one and the first sign goes on the map: tracks, then a kill, then the beast's own mark, each
## pointing to the next, until the animal itself. Its pelt is like no other; Thackery makes it into an outfit item
## (pelt + $10). Flags legend_<id> = "pelt" / "outfit"; gossip, the papers and the journal remember them.

const C3 = preload("res://src/missions/ch3/ch3.gd")

const LEGENDS := [
	{"id": "grey_widow", "name": "The Grey Widow", "species": "wolf", "region": "Kestrel Range", "near": ["trapper_cabin_n", 320.0, -280.0],
		"hp": 5.0, "scale": 1.55, "tint": Color(0.78, 0.78, 0.76), "outfit": "Grey Widow Coat",
		"story": "A she-wolf near the size of a pony, gone grey to white. Took a herder's whole flock in one night last winter and left the dogs alive to tell it.",
		"clues": ["Tracks wide as a saucer in the frost, a long stride. One wolf, alone, going uphill.", "A yearling elk pulled down and opened, and only the heart taken. She's particular.", "Grey hair caught on a juniper at shoulder height. Higher than any wolf has a right to stand."]},
	{"id": "ironhide", "name": "Old Ironhide", "species": "black_bear", "region": "Thornwood", "near": ["thornwood_logging", -400.0, 360.0],
		"hp": 4.0, "scale": 1.7, "tint": Color(0.16, 0.12, 0.1), "outfit": "Ironhide Bearskin Coat",
		"story": "A bear the loggers say has three of their bullets in him and wears them like medals. Tore the door off the cook shack for a sack of sugar.",
		"clues": ["A rotten log torn open like a letter, and prints behind it a man could stand both boots in.", "A pine stripped of bark ten feet up. He's been sharpening himself.", "A cook-shack sugar sack, licked clean, and a smell like a wet church."]},
	{"id": "pale_ghost", "name": "The Pale Ghost", "species": "cougar", "region": "Ocotillo Breaks", "near": ["san_lazaro", 440.0, 400.0],
		"hp": 4.0, "scale": 1.4, "tint": Color(0.92, 0.88, 0.8), "outfit": "Pale Ghost Hat Band and Vest",
		"story": "A cat the colour of bone that the Mexican herders won't name. Seen on the mission wall at dusk, watching the goats like a priest counting the collection.",
		"clues": ["Pale hairs on a cholla, and a pad print in the wash with the claws drawn in.", "A goat carried forty yards up a slope no goat could climb, and laid in a crack of the rock.", "Scratches on a boulder at a man's head height, fresh, and the sand swept by a tail."]},
	{"id": "sable_king", "name": "The Sable King", "species": "elk", "region": "Sable Valley", "near": ["caddell_camp", 660.0, -520.0],
		"hp": 3.5, "scale": 1.45, "tint": Color(0.4, 0.28, 0.18), "outfit": "Sable King Gloves and Riding Hat",
		"story": "A bull elk with fourteen points that every hunter in the county has missed. Comes down to the river in the dry months like he owns the water rights. Maybe he does.",
		"clues": ["Hoof prints as big as a mule's, sunk deep at the river crossing.", "A cottonwood rubbed raw to the wood, and a broken tine left in the bark like a calling card.", "A wallow in the bottom, still muddy, and a smell you could lean on."]},
]

var active := ""
var _trapper: Node3D = null
var _placed := false
var _t := 2.0

func _ready() -> void:
	Game.set_meta("legendary", self)

static func legend(id: String) -> Dictionary:
	for l in LEGENDS:
		if l.id == id:
			return l
	return {}

static func status(id: String) -> String:
	return str(Game.state.flags.get("legend_" + id, "")) if Game.state else ""

## The den and the three clue sites, from the place near which the beast lives.
static func sites(l: Dictionary) -> Array:
	var n: Array = l.near
	var base := Mission.place(str(n[0]))
	var den := C3.dry(Vector3(base.x + float(n[1]), 0, base.z + float(n[2])))
	var start := C3.dry(base.lerp(den, 0.35))
	var out := []
	var dir := (den - start)
	dir.y = 0.0
	var perp := dir.normalized().cross(Vector3.UP)
	for i in 3:
		var f := (i + 1) / 4.0
		out.append(C3.dry(start.lerp(den, f) + perp * (40.0 if i % 2 == 0 else -40.0)))
	out.append(den)
	return out

# ------------------------------------------------------------------ the trapper at Greer's Post
func _process(dt: float) -> void:
	if _placed:
		return
	_t -= dt
	if _t > 0.0 or Game.player == null:
		return
	_t = 2.0
	var post := Mission.place("greer_post", 9.0, 6.0)
	if post == Vector3.ZERO:
		return
	_placed = true
	_trapper = Stall.new()
	_trapper.name = "TrapperStall"
	_trapper.position = C3.dry(post)          # before entering the tree: the stall spawns Thackery beside itself in _ready
	Game.main.add_child(_trapper)

## What Thackery says about a legend, and whether there's anything to do with it right now.
func options() -> Array:
	var o := []
	for l in LEGENDS:
		var s := status(l.id)
		if s == "":
			o.append({"id": l.id, "label": "Ask about %s" % l.name, "act": "hunt"})
		elif s == "pelt":
			o.append({"id": l.id, "label": "Have the %s made from the %s pelt ($10)" % [l.outfit, l.name], "act": "outfit"})
	return o

func talk() -> void:
	var menus = Game.get("menus")
	if menus == null:
		return
	var p: PanelContainer = menus._paper_panel(Vector2(860, 560))
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UITheme.label("Eli Thackery, Trapper", 44, "display", UITheme.INK, false))
	v.add_child(UITheme.label("\"Furs bought, tales told, coats made. The tales are free, and worth it.\"", 20, "italic", UITheme.INK_SOFT, false))
	v.add_child(HSeparator.new())
	for o in options():
		var oo: Dictionary = o
		var l := legend(oo.id)
		if oo.act == "hunt":
			v.add_child(UITheme.label(str(l.story), 20, "body", UITheme.INK, false))
		v.add_child(menus._button(str(oo.label), func():
			menus.back()
			if oo.act == "hunt":
				begin(oo.id)
			else:
				make_outfit(oo.id)))
	if options().is_empty():
		v.add_child(UITheme.label("\"You've had every beast I know of. I'll have to start lying.\"", 22, "body", UITheme.INK, false))
	v.add_child(menus._button("Leave", menus.back))
	menus._push(p)

# ------------------------------------------------------------------ the hunt
func begin(id: String) -> void:
	if active != "":
		Game.say("One legend at a time.", 2.5)
		return
	hunt(id)

## The whole trail: three clues, the beast, the pelt. Returns true when the pelt is in the satchel.
func hunt(id: String) -> bool:
	var l := legend(id)
	if l.is_empty() or active != "":
		return false
	active = id
	var md = Game.missions
	var s := sites(l)
	Game.log_event("legend_start", {"id": id})
	for i in 3:
		if Game.get("menus"):
			Game.menus.set_waypoint(s[i])
		await md.interact(s[i], "Read the sign (%d/3) — %s" % [i + 1, l.name])
		if md.aborted():
			break
		Game.log_event("legend_clue", {"id": id, "n": i + 1})
		if Game.hud:
			Game.hud.notice(str(l.clues[i]), 6.0)
	if md.aborted():
		active = ""
		if md.active == null:
			md._abort = false
		return false
	if Game.get("menus"):
		Game.menus.set_waypoint(s[3])
	var a := spawn_beast(l, s[3])
	md.set_objective("%s — bring it down" % l.name)
	var t := 0.0
	while is_instance_valid(a) and a.alive:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if md.autopilot and t > 0.5:
			a.damageable.apply_hit({"amount": 99999.0, "zone": "head", "attacker": Game.player})
		if Game.player.damageable and not Game.player.damageable.alive:
			active = ""
			md.set_objective("")
			return false
	Game.log_event("legend_killed", {"id": id})
	await md.interact(a.global_position if is_instance_valid(a) else s[3], "Skin %s" % l.name)
	if is_instance_valid(a):
		a.skinned = true
		get_tree().create_timer(5.0 if md.autopilot else 120.0).timeout.connect(func():
			if is_instance_valid(a):
				a.queue_free())
	Game.state.add_item("pelt_legend_" + id)
	Game.state.flags["legend_" + id] = "pelt"
	if Game.has_meta("news"):
		Game.get_meta("news").record("legend", {"id": id, "name": l.name})
	if Game.hud:
		Game.hud.notice("The %s pelt — there isn't another like it" % l.name, 5.0)
	md.set_objective("")
	if Game.get("menus"):
		Game.menus.clear_waypoint()
	active = ""
	return true

## The beast: the species, made bigger, tougher, paler or darker, and set on Ruth if it hunts.
func spawn_beast(l: Dictionary, p: Vector3) -> Animal:
	Game.terrain.ensure_tile(p)
	var a: Animal = Animal.spawn(Game.main, p + Vector3(0, 0.5, 0), str(l.species), hash(str(l.id)))
	a.spec = a.spec.duplicate()
	a.spec["name"] = l.name
	a.spec["pelt"] = float(a.spec.get("pelt", 5.0)) * 6.0
	a.name = "Legend_" + str(l.id)
	a.damageable.max_health = float(a.spec.hp) * float(l.hp)
	a.damageable.health = a.damageable.max_health
	if a.visual:
		# bigger: scale the drawn parts, not the visual root (its hit-zone areas stay unscaled for the physics engine)
		var sc := float(l.scale)
		for c in a.visual.get_children():
			if c is Node3D and not (c is CollisionObject3D):
				(c as Node3D).scale *= sc
				(c as Node3D).position *= sc
		if Game.headless == false:
			for m in a.visual.find_children("*", "MeshInstance3D", true, false):
				var mat := StandardMaterial3D.new()
				mat.albedo_color = l.tint
				mat.roughness = 0.9
				if (m as MeshInstance3D).mesh is BoxMesh:
					(m as MeshInstance3D).material_override = mat
	if str(a.spec.get("diet", "")) == "predator" or l.species == "black_bear":
		a.prey = Game.player
		a.state = Animal.State.STALK
	a.set_meta("legend", l.id)
	Game.log_event("legend_spawned", {"id": l.id, "hp": a.damageable.max_health})
	return a

## Thackery makes the outfit: pelt + $10 -> outfit item.
func make_outfit(id: String) -> bool:
	var l := legend(id)
	var st = Game.state
	if l.is_empty() or st == null or int(st.inventory.get("pelt_legend_" + id, 0)) <= 0:
		return false
	if st.money < 10.0:
		Game.say("\"Ten dollars for the work, Mrs. Caddell. I don't sew for love.\"", 3.0)
		return false
	st.add_money(-10.0)
	st.inventory["pelt_legend_" + id] = int(st.inventory["pelt_legend_" + id]) - 1
	st.add_item("outfit_" + id)
	st.flags["legend_" + id] = "outfit"
	Game.log_event("legend_outfit", {"id": id, "item": l.outfit})
	Game.say("\"There. The %s. Nobody else in the territory will have one, because there was only one.\"" % l.outfit, 5.0)
	return true

class Stall extends Node3D:
	## Thackery's stall: a fur-hung frame and the man himself.
	var man: Node3D

	func _ready() -> void:
		add_to_group("interactable")
		var h := Human.spawn(Game.main, global_position + Vector3(0.8, 0.3, 0.0), {"seed": 7313, "role": "hunter", "faction": "civilian", "name": "Eli Thackery"})
		man = h
		if Game.headless:
			return
		var frame := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.0, 0.1, 0.1)
		frame.mesh = bm
		frame.position = Vector3(0, 1.9, -0.6)
		add_child(frame)
		for i in 3:
			var fur := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(0.5, 0.9, 0.05)
			fur.mesh = fm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = [Color(0.45, 0.33, 0.22), Color(0.6, 0.55, 0.5), Color(0.3, 0.22, 0.15)][i]
			fur.material_override = mat
			fur.position = Vector3(-0.7 + 0.7 * i, 1.4, -0.6)
			add_child(fur)

	func interact_prompt() -> String:
		return "Talk to Eli Thackery, trapper"

	func interact(_who: Node) -> void:
		if Game.has_meta("legendary"):
			Game.get_meta("legendary").talk()
