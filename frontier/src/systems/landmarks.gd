extends Node
## Places with a story: eight spots off the roads, each with something left behind that tells what happened there
## (a note, a log page, a ledger, or the hermit who lives there), a cache to find, a journal page once read, and a
## mark on the map once discovered. Found/read/cache state lives in WorldState.flags ("landmarks"), so it saves.
## Props are built from boxes and cylinders near the player only (headless: interactables alone).
## Bots: `--bot roam` visits every place, reads, opens the caches and talks to the hermit.

const PLACES := [
	{"id": "vale_cabin", "name": "Orrin Vale's Cabin", "kind": "cabin", "at": [-1500.0, 420.0],
		"note_title": "Vale's Daybook", "note": [
			"May 3. Well down to a bucket a day. Corn won't take. Martha says pray. I say dig.",
			"June 11. Dug forty foot. Dry as a sermon.",
			"July 2. Syndicate man rode out again. Two dollars the acre and a ride to the railhead. Said the river's spoken for, upstream.",
			"July 9. Martha and the boy gone to her sister in Port Linden. I told her I'd follow when the corn came in.",
			"August 1. Going to town to sell. Leaving this for whoever comes. The money in the hearth is for Martha, if you're honest. If you're not, it's for you anyway, I suppose."],
		"cache": "Lift the loose hearthstone", "loot": {"cash": 18.0, "items": {"pocket_watch": 1}},
		"journal": "Orrin Vale dug forty feet for water and found none, then sold to the syndicate. He left his wife's money under the hearthstone and a daybook on the table. I've got the money. I haven't decided about Martha."},
	{"id": "echo_hollow", "name": "Echo Hollow", "kind": "cave", "at": [-2380.0, -2760.0],
		"note_title": "Scratched on a Tin Plate", "note": [
			"FOUR WAYS. CALEB, TOBE, ME, AND THE KID.",
			"TOBE TOOK FIVE.",
			"KID WENT FOR WATER. NOT BACK.",
			"IF YOU READ THIS TOBE, THE SADDLEBAG'S WHERE YOU NEVER LOOKED, YOU THIEVING SON OF A BITCH."],
		"cache": "Pull the saddlebag from under the rocks", "loot": {"cash": 64.0, "rounds": 18},
		"journal": "A dead camp in Echo Hollow and an accounting scratched on a tin plate: four partners, one thief, one boy gone for water. Whoever wrote it hid his share where Tobe never looked. Neither did anyone else, till me."},
	{"id": "candelaria", "name": "Candelaria Chapel", "kind": "ruin", "at": [-1420.0, 2620.0],
		"note_title": "Brother Anselm's Account Book", "note": [
			"Received of the faithful at Candelaria this year: eleven hens, a mule (lame), forty pesos, one ring of very bad silver.",
			"Paid out: lamp oil, flour, a coffin for the Ortega child, a second coffin for her mother.",
			"The well has turned bitter. The families go south. I shall keep the lamp lit until the oil is done, and then I shall go too.",
			"The ring and the pesos are in the bell niche, for whoever comes here needing them more than God does."],
		"cache": "Reach into the bell niche", "loot": {"cash": 31.0, "items": {"tonic_health": 1}},
		"journal": "Candelaria chapel stands roofless south of the Mesquite road. Brother Anselm kept the lamp lit until the oil ran out, and left forty pesos and a bad silver ring in the bell niche for whoever came needing them. I suppose that was me."},
	{"id": "doyle_wreck", "name": "Wreck of the Margaret Doyle", "kind": "wreck", "shore": true, "at": [2900.0, 700.0],
		"note_title": "A Page of the Ship's Log", "note": [
			"Margaret Doyle, lake packet, Port Linden for the north landing. Twelve souls, lumber and mail.",
			"Wind backed to the north-east at four bells. Glass falling like a stone.",
			"Mr. Hale says she will not take another sea abeam. I say she will. We shall see which of us is the better liar.",
			"Ran her on the shore to save the people. All twelve ashore. The purser's box I have buried by the bow for the owners, who will not thank me."],
		"cache": "Dig by the bow", "loot": {"cash": 45.0, "items": {"coffee": 2}},
		"journal": "The lake packet Margaret Doyle lies on the shore below Port Linden where her master ran her aground to save twelve people in a north-easter. He buried the purser's box by the bow for owners who would not have thanked him. They will not thank me either."},
	{"id": "fenn_shack", "name": "Absalom Fenn's Shack", "kind": "hermit", "at": [2320.0, -1120.0],
		"note_title": "Fenn's Field Book", "note": [
			"Township 9 north, range 14 west. Corner stone set at the twin pines.",
			"A spring at the head of Juniper Draw, unrecorded. I have left it off the plat. Let them find it themselves, if they can find it at all.",
			"Every line I draw, somebody else fences."],
		"cache": "Take what Fenn offers", "loot": {"cash": 0.0, "rounds": 12, "items": {"jerky": 2}},
		"journal": "Absalom Fenn surveyed the lines the syndicate is fighting over, then quit and went up the hill to grow beans. He gave me his last field book. There's a spring in it that isn't on any plat. I mean to keep it that way."},
	{"id": "whitlock_grave", "name": "Lone Juniper Rise", "kind": "grave", "at": [520.0, -920.0],
		"note_title": "A Letter in a Fruit Jar", "note": [
			"Clara,",
			"Pa sold the place. There's a railroad man's house where the barn was. I told them there was a grave up on the rise and they said they'd mind it. They won't.",
			"I left the locket you liked. I'm going west to work the mines. If I strike anything I'll put a proper stone up. If I don't, this is the stone.",
			"Your brother, Wes."],
		"cache": "Take the locket", "loot": {"cash": 0.0, "items": {"pocket_watch": 1}, "standing": -2.0},
		"journal": "A girl named Clara Whitlock is buried under a juniper on the rise, and her brother left a letter and a locket in a fruit jar when the family sold up. The cross says she liked it here. I can see why."},
	{"id": "ashgrove", "name": "Ashgrove Homestead", "kind": "burned", "at": [1040.0, 2320.0],
		"note_title": "A Notice, Half Burned", "note": [
			"...LAND AND RAIL SYNDICATE, by its agent...",
			"...said occupants having no title recorded in the county...",
			"...to quit the premises within ten days or be removed...",
			"On the back, in pencil, in a child's hand: WE ARE NOT GOING."],
		"cache": "Open the root cellar", "loot": {"cash": 9.0, "items": {"jerky": 3, "tonic_health": 1}},
		"journal": "Ashgrove homestead is a chimney and some black timbers now. An eviction notice from the syndicate, half burned, and on the back a child wrote WE ARE NOT GOING. I hope they went. The cellar was still full."},
	{"id": "widows_reach", "name": "Widow's Reach Mine", "kind": "mine", "at": [-3020.0, -420.0],
		"note_title": "The Foreman's Ledger", "note": [
			"Shift of the 14th: nine men down, eight up. Timbers in the east drift gave at the forty-foot level.",
			"Company says the drift is to be sealed and the matter called a fall of rock. The widow is to have twenty dollars.",
			"I have put the twenty in the tin by the cart and twenty of my own besides. If the company sends somebody else to pay her, they'll pay her short.",
			"Her name is Ada Brandt. She lives on the Coldwater road past the second bridge."],
		"cache": "Open the tin by the ore cart", "loot": {"cash": 40.0, "items": {"tonic_nerve": 1}},
		"journal": "At Widow's Reach the company sealed a drift with a man in it and called it a fall of rock. The foreman left forty dollars in a tin for the widow, Ada Brandt, on the Coldwater road past the second bridge. It's in my satchel now. It shouldn't stay there."},
]

const SEE_R := 75.0
const BUILD_R := 300.0
const FREE_R := 420.0

var spots := {}                 # id -> Vector3 (snapped to dry, level ground)
var built := {}                 # id -> Node3D (props + interactables)
var hermit: Human = null
var _t := 0.0

func _ready() -> void:
	Game.set_meta("landmarks", self)
	if Game.missions:
		Game.missions._load_dialogue("res://design/dialogue/landmarks.json")
	for p in PLACES:
		spots[p.id] = _snap(p)

static func place_def(id: String) -> Dictionary:
	for p in PLACES:
		if p.id == id:
			return p
	return {}

func state() -> Dictionary:
	if not Game.state.flags.has("landmarks"):
		Game.state.flags["landmarks"] = {}
	return Game.state.flags["landmarks"]

func found(id: String) -> bool:
	return bool(state().get(id, {}).get("found", false))

func _mark(id: String, key: String) -> void:
	var s := state()
	var e: Dictionary = s.get(id, {})
	e[key] = true
	s[id] = e

## Dry, gentle ground near the anchor (the lake shore for the wreck).
func _snap(p: Dictionary) -> Vector3:
	var w: WorldData = Game.world
	var a := Vector3(float(p.at[0]), 0, float(p.at[1]))
	if p.get("shore", false):
		# walk along x from the anchor to the waterline (west out of the lake, or east to it); the wreck lies a few
		# metres up the beach
		var q := a
		var step := -6.0 if w.is_water(q.x, q.z) else 6.0
		for i in 400:
			var wet_here := w.is_water(q.x, q.z)
			var wet_next := w.is_water(q.x + step, q.z)
			if not wet_here and wet_next:
				a = q
				break
			if wet_here and not wet_next:
				a = Vector3(q.x + step * 2.0, 0, q.z)
				break
			q.x += step
	var best := a
	var bs := INF
	for r: float in [0.0, 12.0, 25.0, 45.0, 70.0]:
		for k in (1 if r == 0.0 else 10):
			var c := a + Vector3(cos(TAU * k / 10.0) * r, 0, sin(TAU * k / 10.0) * r)
			if w.is_water(c.x, c.z):
				continue
			var h0 := w.height(c.x, c.z)
			var slope := absf(w.height(c.x + 4.0, c.z) - h0) + absf(w.height(c.x, c.z + 4.0) - h0)
			var score: float = slope + float(r) * 0.01
			if score < bs:
				bs = score
				best = c
	best.y = w.height(best.x, best.z)
	return best

func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0 or Game.player == null or Game.state == null:
		return
	_t = 1.0
	var pp: Vector3 = Game.player.global_position
	for p in PLACES:
		var at: Vector3 = spots[p.id]
		var d := Vector2(at.x - pp.x, at.z - pp.z).length()
		if d < SEE_R and not found(p.id):
			discover(p.id)
		if d < BUILD_R and not built.has(p.id):
			_build(p)
		elif d > FREE_R and built.has(p.id):
			if is_instance_valid(built[p.id]):
				built[p.id].queue_free()
			built.erase(p.id)
			if p.kind == "hermit" and is_instance_valid(hermit):
				hermit.queue_free()
				hermit = null

func discover(id: String) -> void:
	if found(id):
		return
	_mark(id, "found")
	var p := place_def(id)
	Game.log_event("landmark_found", {"id": id})
	if Game.hud and not Game.headless:
		Game.hud.notice("Discovered: %s" % p.name, 3.5)

## Read what was left there (a paper; the hermit's book comes from talking to him). Returns the journal text.
func read(id: String) -> String:
	var p := place_def(id)
	if p.is_empty():
		return ""
	discover(id)
	_mark(id, "read")
	Game.log_event("landmark_read", {"id": id})
	if Game.missions:
		await Game.missions.paper(str(p.note_title), p.note)
	return str(p.journal)

## Open the cache. Returns what was in it {cash, items, rounds}; {} when already taken.
func open_cache(id: String) -> Dictionary:
	var p := place_def(id)
	if p.is_empty() or bool(state().get(id, {}).get("cache", false)):
		return {}
	discover(id)
	_mark(id, "cache")
	var l: Dictionary = p.loot
	var st = Game.state
	if float(l.get("cash", 0.0)) > 0.0:
		st.add_money(float(l.cash))
	for it in l.get("items", {}).keys():
		st.add_item(it, int(l.items[it]))
	if int(l.get("rounds", 0)) > 0 and Game.player.get("gun") != null:
		Game.player.gun.ammo["revolver"] = int(Game.player.gun.ammo.get("revolver", 0)) + int(l.rounds)
	if float(l.get("standing", 0.0)) != 0.0:
		st.change_standing(float(l.standing), "took from a grave")
	var bits := []
	if float(l.get("cash", 0.0)) > 0.0:
		bits.append("$%.2f" % float(l.cash))
	for it in l.get("items", {}).keys():
		bits.append(Satchel.NAMES.get(it, str(it).replace("_", " ")).to_lower())
	if int(l.get("rounds", 0)) > 0:
		bits.append("%d cartridges" % int(l.rounds))
	Game.say("Found %s." % ", ".join(bits), 3.5)
	Game.log_event("landmark_cache", {"id": id, "loot": l})
	return l

## Talk to the hermit (the conversation camera; Ruth answers). Gives the field book (read) afterwards.
func talk_to_hermit() -> bool:
	var md = Game.missions
	if md == null:
		return false
	discover("fenn_shack")
	var h: Node3D = hermit if is_instance_valid(hermit) else null
	md.cine_begin()
	for lid in ["lm_fenn_1", "lm_ruth_fenn_1", "lm_fenn_2", "lm_fenn_3", "lm_fenn_4", "lm_ruth_fenn_2"]:
		var spk: String = str(md.dialogue.get(lid, {}).get("speaker", ""))
		await md.say(lid, Game.player if spk == "ruth" else h)
	md.cine_end()
	_mark("fenn_shack", "talked")
	Game.log_event("landmark_talk", {"id": "fenn_shack"})
	return true

## Map marks for the places found so far: [{pos, label, done}] (done once read and the cache taken).
func map_marks() -> Array:
	var out := []
	for p in PLACES:
		if found(p.id):
			var e: Dictionary = state().get(p.id, {})
			out.append({"pos": spots[p.id], "label": p.name, "done": bool(e.get("read", false)) and bool(e.get("cache", false))})
	return out

## Journal pages for the places read (journal.gd extra_entries).
static func journal_pages(flags: Dictionary) -> Array:
	var out := []
	var s: Dictionary = flags.get("landmarks", {})
	for p in PLACES:
		var e: Dictionary = s.get(p.id, {})
		if bool(e.get("read", false)) or bool(e.get("talked", false)):
			out.append({"title": str(p.name), "sub": "A place with a story", "text": str(p.journal), "sketch": "hills", "map": 0})
	return out

# ------------------------------------------------------------------ props
func _build(p: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Landmark_" + str(p.id)
	Game.main.add_child(root)
	var at: Vector3 = spots[p.id]
	root.global_position = at
	root.rotation.y = float(hash(p.id) % 628) / 100.0
	built[p.id] = root
	var note_at := Vector3(1.2, 0.0, 0.8)
	var cache_at := Vector3(-1.6, 0.0, -1.2)
	var K := Kit.new(root)
	match str(p.kind):
		"cabin":
			K.walls(5.0, 4.0, 2.3, Color(0.4, 0.3, 0.2))
			K.box(Vector3(5.6, 0.12, 2.6), Vector3(0, 2.6, -0.9), Color(0.3, 0.24, 0.18), Vector3(0.25, 0, 0))   # roof half, fallen in
			K.box(Vector3(1.2, 0.75, 0.8), Vector3(1.0, 0.38, 0.6), Color(0.45, 0.33, 0.22))                    # table
			K.box(Vector3(1.0, 1.6, 0.6), Vector3(-1.9, 0.8, -1.5), Color(0.5, 0.48, 0.45))                      # hearth
			note_at = Vector3(1.0, 0.0, 0.6)
			cache_at = Vector3(-1.9, 0.0, -1.0)
		"cave":
			for r in 7:
				var a := -0.6 + float(r) * 0.2
				K.box(Vector3(2.4, 2.0 + float(r % 3), 2.2), Vector3(sin(a) * 4.0, 1.0 + float(r % 3) * 0.5, -cos(a) * 4.0), Color(0.42, 0.38, 0.33), Vector3(0, a, 0.1 * float(r % 2)), true)
			K.box(Vector3(3.6, 1.2, 2.8), Vector3(0, 3.2, -4.0), Color(0.38, 0.34, 0.3), Vector3.ZERO, true)
			K.box(Vector3(2.8, 2.6, 0.4), Vector3(0, 1.3, -5.2), Color(0.04, 0.04, 0.05))                       # the dark
			K.box(Vector3(0.7, 0.12, 1.9), Vector3(1.2, 0.06, -2.0), Color(0.35, 0.28, 0.22))                   # bedroll
			K.ring(Vector3(-0.6, 0, -1.6), Color(0.15, 0.13, 0.12))                                               # cold fire
			note_at = Vector3(-0.6, 0.0, -1.2)
			cache_at = Vector3(-1.8, 0.0, -3.4)
		"ruin":
			K.box(Vector3(0.7, 3.2, 9.0), Vector3(-3.0, 1.6, 0), Color(0.78, 0.68, 0.55), Vector3.ZERO, true)
			K.box(Vector3(0.7, 1.8, 6.0), Vector3(3.0, 0.9, 1.5), Color(0.76, 0.66, 0.53), Vector3.ZERO, true)
			K.box(Vector3(6.7, 4.2, 0.7), Vector3(0, 2.1, -4.5), Color(0.8, 0.7, 0.57), Vector3.ZERO, true)       # facade
			K.box(Vector3(2.2, 1.6, 0.75), Vector3(0, 5.0, -4.5), Color(0.8, 0.7, 0.57))                         # espadaña
			K.box(Vector3(0.9, 1.0, 0.8), Vector3(0, 4.9, -4.5), Color(0.2, 0.17, 0.14))                         # bell niche
			K.box(Vector3(0.12, 1.6, 0.12), Vector3(1.2, 0.1, 1.4), Color(0.35, 0.25, 0.16), Vector3(0, 0, 1.45)) # fallen cross
			note_at = Vector3(0.8, 0.0, -2.8)
			cache_at = Vector3(0.0, 0.0, -3.7)
		"wreck":
			K.box(Vector3(3.6, 2.4, 13.0), Vector3(0, 1.0, 0), Color(0.3, 0.24, 0.18), Vector3(0.05, 0, 0.32), true)   # hull, heeled over
			for z in [-4.5, -1.5, 1.5, 4.5]:
				K.box(Vector3(0.2, 2.8, 0.25), Vector3(1.6, 1.7, z), Color(0.25, 0.2, 0.15), Vector3(0, 0, 0.5))       # ribs
			K.cyl(0.18, 6.0, Vector3(-0.8, 3.4, -1.0), Color(0.36, 0.28, 0.2), Vector3(0, 0, 0.9))                   # mast
			K.box(Vector3(0.8, 0.6, 0.8), Vector3(-3.2, 0.3, 3.0), Color(0.5, 0.4, 0.28))                          # crates
			K.box(Vector3(0.7, 0.5, 0.7), Vector3(-3.6, 0.25, 4.1), Color(0.45, 0.36, 0.25))
			note_at = Vector3(-2.8, 0.0, 2.0)
			cache_at = Vector3(-1.6, 0.0, -6.8)
		"hermit":
			K.walls(3.2, 2.8, 2.1, Color(0.46, 0.36, 0.25))
			K.box(Vector3(3.6, 0.1, 3.2), Vector3(0, 2.3, 0), Color(0.32, 0.27, 0.2), Vector3(0.12, 0, 0))
			for r in 4:
				K.box(Vector3(4.0, 0.25, 0.35), Vector3(4.5, 0.12, -1.5 + float(r) * 1.0), Color(0.28, 0.42, 0.2))     # bean rows
			note_at = Vector3.INF
			cache_at = Vector3(0.9, 0.0, 1.9)
			if not is_instance_valid(hermit):
				var hp: Vector3 = root.global_transform * Vector3(2.2, 0, 2.0)
				hermit = Human.spawn(Game.main, Vector3(hp.x, Game.world.height(hp.x, hp.z) + 0.3, hp.z),
					{"seed": 4471, "role": "elder", "faction": "civilian", "name": "Absalom Fenn"})
				hermit.brain.home = hermit.global_position
				var talk := Talk.new()
				talk.name = "FennTalk"
				root.add_child(talk)
				talk.position = Vector3(2.2, 0, 2.0)
		"grave":
			K.box(Vector3(1.0, 0.35, 2.0), Vector3(0, 0.15, 0), Color(0.36, 0.3, 0.22))                        # mound
			K.box(Vector3(0.1, 1.2, 0.1), Vector3(0, 0.6, -1.1), Color(0.55, 0.48, 0.38))
			K.box(Vector3(0.6, 0.1, 0.1), Vector3(0, 0.95, -1.1), Color(0.55, 0.48, 0.38))
			K.cyl(0.25, 3.2, Vector3(2.4, 1.6, -1.6), Color(0.3, 0.22, 0.16))                                     # the juniper
			K.box(Vector3(2.6, 2.4, 2.6), Vector3(2.4, 3.8, -1.6), Color(0.2, 0.3, 0.2))
			note_at = Vector3(0.5, 0.0, -1.3)
			cache_at = Vector3(-0.5, 0.0, -1.3)
		"burned":
			K.box(Vector3(1.4, 4.6, 1.2), Vector3(-2.4, 2.3, -2.0), Color(0.48, 0.45, 0.42), Vector3.ZERO, true)  # chimney
			for i in 6:
				K.box(Vector3(0.25, 0.25, 3.5), Vector3(-1.0 + float(i) * 0.5, 0.15, float(i % 3) - 0.5), Color(0.08, 0.07, 0.06), Vector3(0, float(i) * 0.5, 0.1))
			K.cyl(0.62, 0.12, Vector3(2.0, 0.62, 1.2), Color(0.3, 0.24, 0.18), Vector3(0, 0, PI * 0.5))           # wagon wheel
			K.box(Vector3(1.4, 0.1, 1.2), Vector3(1.6, 0.05, -2.0), Color(0.35, 0.28, 0.2))                       # cellar door
			note_at = Vector3(-1.2, 0.0, -1.2)
			cache_at = Vector3(1.6, 0.0, -1.4)
		"mine":
			K.box(Vector3(5.0, 4.0, 3.0), Vector3(0, 2.0, -3.0), Color(0.45, 0.4, 0.34), Vector3.ZERO, true)       # hillside
			K.box(Vector3(2.0, 2.4, 0.2), Vector3(0, 1.2, -1.45), Color(0.03, 0.03, 0.03))                        # adit
			for sx in [-1.15, 1.15]:
				K.box(Vector3(0.25, 2.7, 0.25), Vector3(sx, 1.35, -1.3), Color(0.4, 0.3, 0.2))
			K.box(Vector3(2.8, 0.3, 0.3), Vector3(0, 2.75, -1.3), Color(0.4, 0.3, 0.2))
			K.box(Vector3(1.0, 0.7, 1.4), Vector3(1.8, 0.55, 1.0), Color(0.3, 0.28, 0.26))                       # ore cart
			for sx in [-0.35, 0.35]:
				K.box(Vector3(0.06, 0.06, 6.0), Vector3(sx, 0.05, 1.5), Color(0.25, 0.22, 0.2))                   # rails
			note_at = Vector3(-1.4, 0.0, 0.6)
			cache_at = Vector3(1.8, 0.0, 2.0)
	if note_at != Vector3.INF:
		var n := Spot.new()
		n.place_id = p.id
		n.what = "note"
		n.name = "Note"
		root.add_child(n)
		n.position = note_at
	var c := Spot.new()
	c.place_id = p.id
	c.what = "cache"
	c.name = "Cache"
	root.add_child(c)
	c.position = cache_at
	Game.log_event("landmark_built", {"id": p.id})

class Spot extends Node3D:
	var place_id := ""
	var what := "note"

	func _ready() -> void:
		add_to_group("interactable")

	func interact_prompt() -> String:
		var lm = Game.get_meta("landmarks") if Game.has_meta("landmarks") else null
		if lm == null:
			return ""
		var p: Dictionary = lm.place_def(place_id)
		var e: Dictionary = lm.state().get(place_id, {})
		if what == "note":
			return "Read: %s" % p.note_title
		if place_id == "fenn_shack" and not bool(e.get("talked", false)):
			return ""
		return "" if bool(e.get("cache", false)) else str(p.cache)

	func interact(_who: Node) -> void:
		var lm = Game.get_meta("landmarks")
		if what == "note":
			lm.read(place_id)
		else:
			lm.open_cache(place_id)
			if place_id == "fenn_shack":
				lm.read(place_id)

class Talk extends Node3D:
	func _ready() -> void:
		add_to_group("interactable")

	func interact_prompt() -> String:
		var lm = Game.get_meta("landmarks")
		return "Talk to the old man" if lm != null and is_instance_valid(lm.hermit) and lm.hermit.alive else ""

	func interact(_who: Node) -> void:
		Game.get_meta("landmarks").talk_to_hermit()

## A few boxes and cylinders under a root node (collision on the big pieces).
class Kit extends RefCounted:
	var root: Node3D

	func _init(r: Node3D) -> void:
		root = r

	func box(size: Vector3, pos: Vector3, col: Color, rot := Vector3.ZERO, solid := false) -> void:
		if solid:
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = size
			cs.shape = bs
			body.add_child(cs)
			body.position = pos
			body.rotation = rot
			root.add_child(body)
		if Game.headless:
			return
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = size
		m.mesh = b
		m.material_override = _mat(col)
		m.position = pos
		m.rotation = rot
		m.visibility_range_end = 320.0
		root.add_child(m)

	func cyl(r: float, h: float, pos: Vector3, col: Color, rot := Vector3.ZERO) -> void:
		if Game.headless:
			return
		var m := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = r
		c.bottom_radius = r
		c.height = h
		c.radial_segments = 10
		m.mesh = c
		m.material_override = _mat(col)
		m.position = pos
		m.rotation = rot
		m.visibility_range_end = 320.0
		root.add_child(m)

	func walls(w: float, d: float, h: float, col: Color) -> void:
		box(Vector3(w, h, 0.25), Vector3(0, h * 0.5, -d * 0.5), col, Vector3.ZERO, true)
		box(Vector3(0.25, h, d), Vector3(-w * 0.5, h * 0.5, 0), col, Vector3.ZERO, true)
		box(Vector3(0.25, h, d), Vector3(w * 0.5, h * 0.5, 0), col, Vector3.ZERO, true)
		box(Vector3(w * 0.3, h, 0.25), Vector3(-w * 0.35, h * 0.5, d * 0.5), col, Vector3.ZERO, true)        # door gap
		box(Vector3(w * 0.3, h, 0.25), Vector3(w * 0.35, h * 0.5, d * 0.5), col, Vector3.ZERO, true)

	func ring(at: Vector3, col: Color) -> void:
		for k in 7:
			var a := TAU * float(k) / 7.0
			box(Vector3(0.25, 0.18, 0.25), at + Vector3(cos(a) * 0.45, 0.09, sin(a) * 0.45), col)

	func _mat(col: Color) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.92
		return m
