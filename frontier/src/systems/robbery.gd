extends Node
## Hold-ups and store robberies. Aim a drawn gun at an unarmed civilian for a moment and they put their hands up
## (brandishing is itself a crime if anyone sees it); walk up and rob them for what they carry. Aim at a shop
## counter and the clerk empties the till. Lawmen and armed men answer a pointed gun with theirs. Robberies are
## crimes judged by witnesses (WorldState.crime), cost Standing, and a robbed shop refuses Ruth for three days.

const HOLDUP_TIME := 1.1          # seconds of steady aim before hands go up
const HOLDUP_RANGE := 14.0
const AIM_CONE_DEG := 7.0

var _aim_target: Node = null
var _aim_t := 0.0
var _brandished := {}              # Human -> true (one brandish crime per person)
var robbed_shops := {}             # shop node path -> game day it reopens
var history: Array = []

func _ready() -> void:
	Game.set("robbery", self)

func _physics_process(dt: float) -> void:
	var p = Game.player
	if p == null or not is_instance_valid(p) or not p.get("intent") or not p.intent.get("aim", false):
		_aim_target = null
		_aim_t = 0.0
		return
	var t := _target_in_sights(p)
	if t != _aim_target:
		_aim_target = t
		_aim_t = 0.0
	if t == null:
		return
	_aim_t += dt
	if not _brandished.has(t) and _aim_t > 0.3:
		_brandished[t] = true
		if Game.state:
			Game.state.crime("brandish", t.global_position, t)
	if _aim_t >= HOLDUP_TIME:
		react(t)

## The Human nearest the centre of the aim within the cone and range, or null.
func _target_in_sights(p: Node3D) -> Node:
	var ray: Dictionary = p.aim_ray()
	var o: Vector3 = ray.origin
	var d: Vector3 = ray.dir
	var best: Node = null
	var best_dot := cos(deg_to_rad(AIM_CONE_DEG))
	for h in get_tree().get_nodes_in_group("humans"):
		if not h.alive or h.brain == null:
			continue
		var to: Vector3 = (h.global_position + Vector3(0, 1.3, 0)) - o
		if to.length() > HOLDUP_RANGE + 4.0:
			continue
		var dt := d.dot(to.normalized())
		if dt > best_dot:
			best_dot = dt
			best = h
	return best

## How a person answers a gun pointed at them.
func react(h: Node) -> void:
	var b = h.brain
	if b.state in [b.State.SURRENDER, b.State.COMBAT, b.State.FLEE]:
		return
	var armed: bool = h.get("holder") != null or str(h.role) in ["lawman", "rancher", "gambler", "gunman", "hunter", "drover", "cowhand"]
	if h.faction == "law" or (armed and b.bravery > 0.5):
		b.aggressive = true
		b.target = Game.player
		b.state = b.State.COMBAT
		Game.log_event("holdup_resisted", {"npc": str(h.name)})
		return
	b.state = b.State.SURRENDER
	h.set_meta("held_up", true)
	Game.log_event("holdup", {"npc": str(h.name)})

## Called by Human.interact when Ruth walks up to someone with their hands up.
func rob(h: Node) -> float:
	if not h.has_meta("held_up") or h.has_meta("robbed"):
		return 0.0
	h.set_meta("robbed", true)
	var r := RandomNumberGenerator.new()
	r.seed = int(h.seed) * 31 + 7
	var cash := snappedf(r.randf_range(0.8, 9.0) * (2.5 if h.role in ["gambler", "shopkeeper"] else 1.0), 0.05)
	Game.state.add_money(cash)
	var loot := ""
	if r.randf() < 0.35:
		loot = ["jerky", "coffee", "tonic_health", "pocket_watch"][r.randi() % 4]
		Game.state.add_item(loot)
	Game.state.crime("robbery", h.global_position, h)
	history.append({"kind": "holdup", "cash": cash, "loot": loot})
	if Game.has_meta("news"):
		Game.get_meta("news").record("holdup", {"cash": cash})
	Game.log_event("robbed", {"npc": str(h.name), "cash": cash, "loot": loot})
	Game.say("Took $%.2f%s." % [cash, (" and " + loot.replace("_", " ")) if loot != "" else ""], 3.0)
	# let them go: they run for the law once Ruth turns her back
	h.get_tree().create_timer(2.5).timeout.connect(_let_go.bind(weakref(h)))
	return cash

func _let_go(ref: WeakRef) -> void:
	var h = ref.get_ref()
	if h != null and h.alive and h.brain:
		h.brain.state = h.brain.State.FLEE

func shop_open(shop: Node) -> bool:
	var day: int = Game.sky.day if Game.sky else 0
	return int(robbed_shops.get(str(shop.get_path()), -1)) <= day

## Ruth points a gun over the counter. Returns the take.
func rob_shop(shop: Node) -> float:
	if not shop_open(shop):
		return 0.0
	var r := RandomNumberGenerator.new()
	r.seed = hash(str(shop.get_path())) + (Game.sky.day if Game.sky else 0)
	var take := snappedf(r.randf_range(35.0, 110.0) * (1.4 if shop.kind == "gunsmith" else 1.0), 0.05)
	Game.state.add_money(take)
	Game.state.crime("robbery", shop.global_position, null)
	robbed_shops[str(shop.get_path())] = (Game.sky.day if Game.sky else 0) + 3
	history.append({"kind": "store", "cash": take, "shop": shop.kind})
	if Game.has_meta("news"):
		Game.get_meta("news").record("store_robbery", {"town": shop.town_id, "shop": shop.kind, "take": take})
	Game.log_event("store_robbed", {"shop": shop.kind, "town": shop.town_id, "take": take})
	Game.say("The clerk empties the till: $%.2f. Better ride." % take, 4.0)
	return take
