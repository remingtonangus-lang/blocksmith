extends Node3D
## A shop counter (general store, gunsmith, butcher/trapper). Interact to open a printed-catalogue screen: buy
## goods (prices scale with Standing and town), sell pelts/meat (quality-priced). Settlements place counters at
## their interiors; until then main/population places one per shop type per town.

const CATALOG := {
	"general": [["tonic_health", "Dr. Ambrose's Restorative Tonic", 2.5], ["tonic_nerve", "Steady-Hand Bitters", 3.0],
		["jerky", "Beef Jerky", 0.4], ["fishing_rod", "Split-Cane Fishing Rod & Tackle", 6.0], ["coffee", "Arbuckle-style Coffee, 1 lb", 0.75],
		["horse_oats", "Horse Oats, 5 lb sack", 0.5], ["apple", "Apples (for the horse, or not)", 0.15], ["carrot", "Carrots, a bunch", 0.1],
		["ammo_repeater", "Repeater Cartridges (box of 24)", 1.4], ["ammo_shotgun", "Shotgun Shells (box of 12)", 1.1]],
	"gunsmith": [["ammo_revolver", ".44 Cartridges (box of 24)", 1.0], ["ammo_repeater", "Repeater Cartridges (box of 24)", 1.2],
		["ammo_rifle", "Rifle Cartridges (box of 10)", 1.6], ["ammo_shotgun", "Shotgun Shells (box of 12)", 0.9],
		["ammo_varmint", ".22 Rimfire (box of 50)", 0.6], ["gun_oil", "Gun Oil & Cleaning Rod", 0.75],
		["ammo_revolver_express", "Express .44 Cartridges (box of 12)", 1.6],
		["ammo_repeater_express", "Express Repeater Cartridges (box of 12)", 1.8],
		["ammo_rifle_express", "Express Rifle Cartridges (box of 10)", 2.6],
		["ammo_rifle_split", "Split-Point Rifle Cartridges (box of 10)", 2.2],
		["ammo_shotgun_slug", "Shotgun Slugs (box of 8)", 1.5], ["gun_sheridan_dao", "Sheridan Double Action", 60.0],
		["gun_calder_double", "Calder Double-Barrel", 70.0], ["gun_bowden_bolt", "Bowden Bolt Rifle", 150.0],
		["gun_pellman_varmint", "Pellman .22 Varmint", 40.0], ["gun_brennan_pump", "Brennan Slide-Action", 110.0]],
	"butcher": [],
}

var kind := "general"
var town_id := ""
var title := "General Store"

func setup(k: String, town: String) -> void:
	kind = k
	town_id = town
	title = {"general": "General Store", "gunsmith": "Gunsmith", "butcher": "Butcher & Furs"}.get(k, "Store")
	add_to_group("interactable")

func interact_prompt() -> String:
	var rb = Game.get("robbery")
	if rb and not rb.shop_open(self):
		return "The %s is shut to you" % title.to_lower()
	if rb and Game.player and Game.player.intent.get("aim", false):
		return "Rob the %s" % title.to_lower()
	return "Shop at the %s" % title.to_lower()

func interact(_who: Node) -> void:
	var rb = Game.get("robbery")
	if rb and not rb.shop_open(self):
		Game.say("\"We don't serve you here. Not after last time.\"", 3.0)
		return
	if rb and Game.player and Game.player.intent.get("aim", false):
		rb.rob_shop(self)
		return
	open_ui()

func price(base: float) -> float:
	var f: float = Game.state.price_factor() if Game.state else 1.0
	if town_id == "coldwater":
		f *= 1.15          # mining camp: freight is dear
	return snappedf(base * f, 0.05)

func buy(id: String, base: float) -> bool:
	var st = Game.state
	var p := price(base)
	if st == null or st.money < p:
		Game.say("You can't afford that.", 2.5)
		return false
	st.add_money(-p)
	if id.begins_with("ammo_"):
		var kind_ammo := id.substr(5)
		var n: int = {"revolver": 24, "repeater": 24, "rifle": 10, "shotgun": 12, "varmint": 50, "revolver_express": 12,
			"repeater_express": 12, "rifle_express": 10, "rifle_split": 10, "shotgun_slug": 8}.get(kind_ammo, 12)
		if Game.player and Game.player.gun:
			Game.player.gun.ammo[kind_ammo] = int(Game.player.gun.ammo.get(kind_ammo, 0)) + n
	elif id.begins_with("gun_"):
		var w := id.substr(4)
		if Game.player and Game.player.gun and not Game.player.gun.weapons.has(w):
			Game.player.gun.weapons.append(w)
			Game.player.gun.clip[w] = Weapons.get_def(w).capacity
	else:
		st.add_item(id)
	Game.log_event("buy", {"item": id, "price": p, "shop": kind})
	return true

## Pelts and meat for cash: species base price × quality factor.
func sell_all() -> float:
	var st = Game.state
	if st == null:
		return 0.0
	var total := 0.0
	for k in st.inventory.keys():
		var n := int(st.inventory[k])
		if n <= 0:
			continue
		var key := str(k)
		var value := 0.0
		if key.begins_with("pelt_"):
			var parts := key.substr(5).rsplit("_q", true, 1)
			var sp := parts[0]
			var q := int(parts[1]) if parts.size() > 1 else 1
			if Animal.SPECIES.has(sp):
				value = float(Animal.SPECIES[sp].pelt) * [0.0, 0.4, 0.75, 1.0][clampi(q, 0, 3)]
		elif key.begins_with("fish_"):
			value = load("res://src/systems/fishing.gd").price(key.substr(5)) * 1.5
		elif key.begins_with("meat_"):
			var sp2 := key.substr(5)
			if Animal.SPECIES.has(sp2):
				value = float(Animal.SPECIES[sp2].meat) * 0.5
		if value > 0.0:
			total += value * n / (Game.state.price_factor() if Game.state else 1.0)
			st.inventory[k] = 0
	if total > 0.0:
		st.add_money(total)
		Game.log_event("sell", {"total": snappedf(total, 0.01), "shop": kind})
	return total

# ------------------------------------------------------------------ catalogue screen
func open_ui() -> void:
	var menus = Game.get("menus")
	if menus == null:
		return
	var p: PanelContainer = menus._paper_panel(Vector2(860, 620))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(UITheme.label(title, 46, "display", UITheme.INK, false))
	var money_l := UITheme.label("", 26, "italic", UITheme.INK_SOFT, false)
	v.add_child(money_l)
	var refresh := func(): money_l.text = "Cash on hand: $%.2f" % (Game.state.money if Game.state else 0.0)
	refresh.call()
	v.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true   # D-pad focus scrolls rows below the fold into reach
	scroll.custom_minimum_size = Vector2(800, 400)
	var list := VBoxContainer.new()
	scroll.add_child(list)
	v.add_child(scroll)
	for e in CATALOG.get(kind, []):
		var id: String = e[0]
		var base: float = e[2]
		var b: Button = menus._button("%s  —  $%.2f" % [e[1], price(base)], func():
			if buy(id, base):
				refresh.call())
		b.add_theme_font_override("font", UITheme.font("body"))
		b.add_theme_font_size_override("font_size", 28)
		list.add_child(b)
	if kind in ["butcher", "general"]:
		var sb: Button = menus._button("Sell pelts, meat and fish", func():
			var t := sell_all()
			Game.say("Sold for $%.2f" % t if t > 0.0 else "Nothing to sell.", 3.0)
			refresh.call())
		list.add_child(sb)
	v.add_child(menus._button("Leave", menus.back))
	menus._push(p)
