extends Node
## Horse bond and care. Walk up to your horse on foot and "Tend to your horse": brush (clears the dirt and mud the
## coat picks up — HorseVisual.set_care drives the coat shader's dirt/mud), feed oats, an apple or a carrot (from
## the general store), calm her, or pat her neck. Each builds bond (Horse.bond_xp -> levels 1-4: Wary, Trusting,
## Loyal, Devoted). The bond raises stamina (+10% a level), makes her braver (fear fades faster, a rearing horse is
## less likely to throw Ruth when a predator spooks it — Horse.THROW_CHANCE) and lets her hear the whistle further
## off (Horse.WHISTLE_RANGE). The bond is kept in WorldState (flags horse_bond_xp) across saves.

const LEVEL_NAMES := ["Wary", "Trusting", "Loyal", "Devoted"]
const FOOD := {"horse_oats": ["oats", "a nosebag of oats"], "apple": ["apple", "an apple"], "carrot": ["carrot", "a carrot"]}
const PAT_GAP := 30.0

var _spot: Node3D = null
var _horse: Horse = null
var _t := 1.0
var _pat_t := -100.0

func _ready() -> void:
	Game.set_meta("horse_care", self)
	if Game.state:
		Game.state.loaded.connect(_on_loaded)

## A save was loaded: the horse's bond is whatever the save says (up or down).
func _on_loaded() -> void:
	var h := horse()
	if h != null and Game.state:
		h.bond_xp = float(Game.state.flags.get("horse_bond_xp", 0.0))
		h._cores(0.0)

func horse() -> Horse:
	return Horse.player_horse if is_instance_valid(Horse.player_horse) else null

func level_name(h: Horse = null) -> String:
	var hh := h if h != null else horse()
	return LEVEL_NAMES[clampi((hh.bond_level if hh else 1) - 1, 0, 3)]

func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 1.0
	var h := horse()
	if h == null:
		return
	# keep the bond in WorldState both ways (a loaded save brings it back)
	if Game.state:
		var saved := float(Game.state.flags.get("horse_bond_xp", 0.0))
		if saved > h.bond_xp:
			h.bond_xp = saved
		Game.state.flags["horse_bond_xp"] = h.bond_xp
	if h != _horse or _spot == null or not is_instance_valid(_spot):
		_horse = h
		_spot = CareSpot.new()
		_spot.name = "CareSpot"
		h.add_child(_spot)
		_spot.position = Vector3(0, 0.0, 0)

func _bond(amount: float, why: String) -> void:
	var h := horse()
	if h == null:
		return
	var lvl0 := h.bond_level
	h.bond_xp += amount
	h._cores(0.0)              # recompute the level (and stamina bonus) now
	if Game.state:
		Game.state.flags["horse_bond_xp"] = h.bond_xp
	Game.log_event("horse_bond", {"why": why, "xp": h.bond_xp, "level": h.bond_level})
	if h.bond_level > lvl0 and Game.hud:
		Game.hud.notice("Your horse's bond: %s" % level_name(h), 4.0)

func brush() -> float:
	var h := horse()
	if h == null:
		return 0.0
	var before := h.dirt + h.mud
	h.brush()               # clears dirt, mud and sweat; +15 bond
	_bond(0.0, "brush")
	Game.log_event("horse_brushed", {"cleaned": snappedf(before, 0.01)})
	if Game.hud and not Game.headless:
		Game.hud.notice("You brush her down. The coat comes up clean.", 3.0)
	return before

## Feed from the satchel: "horse_oats", "apple" or "carrot". Returns false if there's none.
func feed(item: String) -> bool:
	var h := horse()
	if h == null or not FOOD.has(item) or Game.state == null or not Game.state.use_item(item):
		return false
	h.feed(str(FOOD[item][0]))   # +10 bond; oats fill both cores
	_bond(5.0 if item != "horse_oats" else 0.0, "feed")
	if Game.hud and not Game.headless:
		Game.hud.notice("She takes %s from your hand." % FOOD[item][1], 3.0)
	return true

func calm() -> void:
	var h := horse()
	if h == null:
		return
	h.fear = 0.0
	_bond(5.0, "calm")

func pat() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _pat_t < PAT_GAP:
		return false
	_pat_t = now
	var h := horse()
	if h:
		h._try_action("head_shake")
	_bond(3.0, "pat")
	return true

func open_menu() -> void:
	var h := horse()
	var menus = Game.get("menus")
	if h == null or menus == null:
		return
	var p: PanelContainer = menus._paper_panel(Vector2(640, 0))
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UITheme.label("Your Horse", 44, "display", UITheme.INK, false))
	var nxt: float = h.BOND_XP[mini(h.bond_level, 3)]
	v.add_child(UITheme.label("Bond: %s (%d)   ·   whistle range %d m   ·   stamina %d" % [level_name(h), h.bond_level,
		int(h.WHISTLE_RANGE[h.bond_level - 1]), int(h.stamina_max)], 22, "italic", UITheme.INK_SOFT, false))
	if h.bond_level < 4:
		v.add_child(UITheme.label("%d more care to the next bond" % int(maxf(nxt - h.bond_xp, 0.0)), 20, "italic", UITheme.INK_SOFT, false))
	v.add_child(UITheme.label("Coat: %s" % ("clean" if h.dirt + h.mud < 0.15 else ("dusty" if h.mud < 0.3 else "caked with mud")), 22, "body", UITheme.INK, false))
	v.add_child(HSeparator.new())
	var add := func(text: String, cb: Callable):
		v.add_child(menus._button(text, func():
			menus.back()
			cb.call()))
	add.call("Brush her down", brush)
	for item in FOOD.keys():
		var n := int(Game.state.inventory.get(item, 0)) if Game.state else 0
		if n > 0:
			var it: String = item
			add.call("Feed %s (%d left)" % [FOOD[item][1], n], func(): feed(it))
	add.call("Calm her", calm)
	add.call("Pat her neck", pat)
	v.add_child(menus._button("Leave her be", menus.back))
	menus._push(p)

class CareSpot extends Node3D:
	func _ready() -> void:
		add_to_group("interactable")

	func interact_prompt() -> String:
		var h = get_parent()
		if h == null or h.get("rider") != null or h.state == Horse.State.DEAD:
			return ""
		return "Tend to your horse"

	func interact(_who: Node) -> void:
		if Game.has_meta("horse_care"):
			Game.get_meta("horse_care").open_menu()
