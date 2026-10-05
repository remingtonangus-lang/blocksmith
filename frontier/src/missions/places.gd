extends RefCounted
## Story places inside the real settlements (Game.main.settlements, design/SETTLEMENTS.md): find a building of a type
## in a town, its spots (bartender, chair, teller, sheriff_desk, cell_bunk, ticket_agent...), its door, a point inside.
## Every call falls back to the old open-ground position when settlements are off (--no_settlements) or a town
## lacks that building, so missions never depend on the town kit being present.

static func kit():
	if Game.main == null or not ("settlements" in Game.main):
		return null
	var s = Game.main.settlements
	if s == null or not s.has_method("get_building"):
		return null
	return s

## First building of `type` in a town (built on demand). {} when there is none.
static func building(town: String, type: String, nth := 0) -> Dictionary:
	var s = kit()
	if s == null:
		return {}
	s.ensure_built(town)
	var t: Dictionary = s.get_town(town)
	if t.is_empty():
		return {}
	var n := 0
	for bid in t.get("buildings", []):
		var b: Dictionary = s.get_building(bid)
		if str(b.get("type", "")) == type and b.get("enterable", true):
			if n == nth:
				return b
			n += 1
	return {}

## The i-th spot of a type in a building ({} if none; wraps round when there are fewer).
static func spot(b: Dictionary, type: String, i := 0) -> Dictionary:
	if b.is_empty():
		return {}
	var l: Array = b.get("spots", []).filter(func(sp): return sp.type == type)
	if l.is_empty():
		return {}
	return l[i % l.size()]

static func spot_count(b: Dictionary, type: String) -> int:
	if b.is_empty():
		return 0
	return b.get("spots", []).filter(func(sp): return sp.type == type).size()

## Where an actor stands for a spot, or the fallback.
static func at(sp: Dictionary, fallback: Vector3) -> Vector3:
	if sp.is_empty():
		return fallback
	return sp.transform.origin

## A point a few metres in front of the spot (what the actor looks at).
static func look(sp: Dictionary, fallback: Vector3) -> Vector3:
	if sp.is_empty():
		return fallback
	var t: Transform3D = sp.transform
	return t.origin - t.basis.z * 2.0

## Outside the front door (street side), or the fallback.
static func door_out(b: Dictionary, fallback: Vector3) -> Vector3:
	var sp := spot(b, "door_out")
	if not sp.is_empty():
		return sp.transform.origin
	if b.is_empty():
		return fallback
	var t: Transform3D = b.transform
	return t * Vector3(0.0, 0.0, -2.0)

## Just inside the front door.
static func door_in(b: Dictionary, fallback: Vector3) -> Vector3:
	var sp := spot(b, "door_in")
	if not sp.is_empty():
		return sp.transform.origin
	return inside(b, 0.2, fallback)

## A point inside on the floor, `frac` of the way from the front wall to the back.
static func inside(b: Dictionary, frac: float, fallback: Vector3, dx := 0.0) -> Vector3:
	if b.is_empty():
		return fallback
	var t: Transform3D = b.transform
	var s: Vector3 = b.size
	return t * Vector3(dx, 0.05, clampf(frac, 0.05, 0.95) * s.z)

## In front of the bank vault at the back of a bank.
static func vault(b: Dictionary, fallback: Vector3) -> Vector3:
	if b.is_empty():
		return fallback
	var s: Vector3 = b.size
	return b.transform * Vector3(0.0, 0.05, s.z - 2.6)

## Swing a building's doors open (people walk through on scripted beats) and hold them for a while.
static func open_doors(b: Dictionary, from: Vector3, hold := 90.0) -> void:
	var s = kit()
	if s == null or b.is_empty():
		return
	for id in b.get("doors", []):
		var dr = s.door(id)
		if dr != null and is_instance_valid(dr):
			dr.open_from(from, hold)

## Chairs round one table of a saloon (the chairs sharing a `table`), most chairs first.
static func table_chairs(b: Dictionary, min_n := 4) -> Array:
	var tables := {}
	for sp in b.get("spots", []):
		if sp.type == "chair" and sp.has("table"):
			var k := str(sp.table)
			if not tables.has(k):
				tables[k] = []
			tables[k].append(sp)
	var best: Array = []
	for k in tables.keys():
		if tables[k].size() > best.size():
			best = tables[k]
	return best if best.size() >= min_n else best
