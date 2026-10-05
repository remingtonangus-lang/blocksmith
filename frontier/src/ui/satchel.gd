class_name Satchel
extends RefCounted
## The satchel ledger (I): everything Ruth carries, written up like a page from a dry-goods ledger — provisions and
## remedies with Use buttons, skins and catch with their going price, ammunition, cash and the county's opinion.

const NAMES := {"tonic_health": "Dr. Ambrose's Restorative Tonic", "tonic_nerve": "Steady-Hand Bitters",
	"jerky": "Beef Jerky", "coffee": "Coffee, 1 lb", "cooked_meat": "Cooked Meat", "fishing_rod": "Split-Cane Fishing Rod",
	"pocket_watch": "A stranger's pocket watch", "newspaper": "Newspaper (the last edition you bought)",
	"treasure_map_1": "The Hatcher Map", "treasure_map_2": "The Second Map", "treasure_map_3": "The Last Map",
	"gold_bar": "Gold bar", "pelt_legend_grey_widow": "The Grey Widow's pelt", "pelt_legend_ironhide": "Old Ironhide's hide",
	"pelt_legend_pale_ghost": "The Pale Ghost's pelt", "pelt_legend_sable_king": "The Sable King's hide",
	"outfit_grey_widow": "Grey Widow Coat", "outfit_ironhide": "Ironhide Bearskin Coat",
	"outfit_pale_ghost": "Pale Ghost Hat Band and Vest", "outfit_sable_king": "Sable King Gloves and Riding Hat"}
## Papers and maps open to be read (newspaper: the last edition bought; maps: the hand-drawn sheet).
static func readable(key: String) -> bool:
	return key == "newspaper" or key.begins_with("treasure_map_")

static func read(key: String) -> void:
	if key == "newspaper" and Game.has_meta("news"):
		Game.get_meta("news").open_last()
	elif key.begins_with("treasure_map_") and Game.has_meta("treasure"):
		Game.get_meta("treasure").open_map(int(key.substr(13)))
const USABLE := ["tonic_health", "tonic_nerve", "jerky", "coffee", "cooked_meat"]

static func open() -> void:
	var menus = Game.get("menus")
	if menus == null or Game.state == null:
		return
	var st = Game.state
	var p: PanelContainer = menus._paper_panel(Vector2(900, 640))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	v.add_child(UITheme.label("Satchel", 48, "display", UITheme.INK, false))
	v.add_child(UITheme.label("Cash on hand $%.2f   ·   %s (Standing %+.0f)" % [st.money, st.standing_label(), st.standing], 24, "italic", UITheme.INK_SOFT, false))
	v.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true   # D-pad focus scrolls rows below the fold into reach
	scroll.custom_minimum_size = Vector2(840, 430)
	var list := VBoxContainer.new()
	scroll.add_child(list)
	v.add_child(scroll)
	_section(list, "Provisions & remedies")
	for id in st.inventory.keys():
		var n := int(st.inventory[id])
		var key := str(id)
		if n <= 0 or (key.begins_with("pelt_") and not key.begins_with("pelt_legend_")) or key.begins_with("meat_") or key.begins_with("fish_"):
			continue
		var row := HBoxContainer.new()
		row.add_child(_cell("%s" % NAMES.get(key, key.replace("_", " ").capitalize()), 560))
		row.add_child(_cell("× %d" % n, 90))
		if key in USABLE:
			var b: Button = menus._button("Use", func():
				if st.use_item(key):
					Game.say("Used %s." % NAMES.get(key, key), 2.0)
					menus.back()
					Satchel.open())
			b.custom_minimum_size = Vector2(110, 0)
			row.add_child(b)
		elif readable(key):
			var rb: Button = menus._button("Read", func(): Satchel.read(key))
			rb.custom_minimum_size = Vector2(110, 0)
			row.add_child(rb)
		list.add_child(row)
	_section(list, "Skins, meat & catch")
	var any := false
	for id in st.inventory.keys():
		var key := str(id)
		var n := int(st.inventory[id])
		if n <= 0 or key.begins_with("pelt_legend_") or not (key.begins_with("pelt_") or key.begins_with("meat_") or key.begins_with("fish_")):
			continue
		any = true
		list.add_child(_line("%s" % _skin_name(key), "× %d" % n))
	if not any:
		list.add_child(_cell("Nothing yet.", 560))
	_section(list, "Ammunition")
	if Game.player and Game.player.gun:
		for k in Game.player.gun.ammo.keys():
			list.add_child(_line({"revolver": ".44 cartridges", "repeater": "Repeater cartridges", "rifle": "Rifle cartridges",
				"shotgun": "Shotgun shells", "varmint": ".22 rimfire"}.get(k, str(k)), str(Game.player.gun.ammo[k])))
	v.add_child(menus._button("Close", menus.back))
	menus._push(p)

static func _skin_name(key: String) -> String:
	if key.begins_with("pelt_"):
		var parts := key.substr(5).rsplit("_q", true, 1)
		var q := int(parts[1]) if parts.size() > 1 else 1
		return "%s pelt (%s)" % [parts[0].replace("_", " ").capitalize(), ["ruined", "poor", "good", "perfect"][clampi(q, 0, 3)]]
	if key.begins_with("meat_"):
		return "%s meat" % key.substr(5).replace("_", " ").capitalize()
	return key.substr(5).replace("_", " ").capitalize()

static func _section(list: VBoxContainer, title: String) -> void:
	list.add_child(UITheme.label(title, 28, "caps", UITheme.OXBLOOD, false))

static func _cell(text: String, w: float) -> Label:
	var l := UITheme.label(text, 24, "body", UITheme.INK, false)
	l.custom_minimum_size = Vector2(w, 0)
	return l

static func _line(a: String, b: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_cell(a, 560))
	row.add_child(_cell(b, 120))
	return row
