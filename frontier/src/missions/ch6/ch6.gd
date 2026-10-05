extends RefCounted
## Chapter 6 (Long Light) helpers: who is still with Ruth after chapter 5, the ending branch, and spawning the
## Outfit as it stands now.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")

const ROSTER := {
	"hap": {"name": "Hap Lindqvist", "seed": 7, "role": "drover", "weapon": "harlan_carbine"},
	"del": {"name": "Del Arceneaux", "seed": 2201, "role": "gambler", "weapon": "lockhart_sa"},
	"doc": {"name": "Cornelius Abernathy", "seed": 3204, "role": "townsfolk", "weapon": "lockhart_sa"},
	"billy": {"name": "Billy Pruitt", "seed": 14, "role": "child", "weapon": ""},
	"joseph": {"name": "Joseph Kehoe", "seed": 4101, "role": "hunter", "weapon": "bowden_bolt"},
}

## Companions still riding with Ruth.
static func outfit() -> Array:
	var out := []
	if C3.flag("hap_alive", true):
		out.append("hap")
	if not C3.flag("del_left", false):
		out.append("del")
	out.append("doc")
	out.append("billy")
	if not C3.flag("joseph_left", false):
		out.append("joseph")
	return out

static func branch() -> String:
	return str(C3.flag("ending", "middle"))

## Spawn the current Outfit around a point, held facing it. Returns {id: Human}.
static func spawn_outfit(d, center: Vector3, armed := false) -> Dictionary:
	var out := {}
	var ids := outfit()
	for i in ids.size():
		var id: String = ids[i]
		var r: Dictionary = ROSTER[id]
		var a := TAU * i / maxf(ids.size(), 1.0)
		var opts := {"role": r.role, "faction": "outfit", "name": r.name, "seed": r.seed, "health": 220.0}
		if armed and r.weapon != "":
			opts["weapon"] = r.weapon
			opts["skill"] = 0.55
		var h: Human = C2.spawn_friend(d, C2.near(center, cos(a) * 2.6, sin(a) * 2.6), opts)
		d.npc_hold(h, center)
		out[id] = h
	return out
