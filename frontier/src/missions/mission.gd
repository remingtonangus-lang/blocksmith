class_name Mission
extends RefCounted
## Base for story missions: set id/title/chapter/requires in _init, write run(d: MissionDirector) as a coroutine
## using the director's verbs. Return false (or let the director fail) to fail; anything else completes.

var id := ""
var title := ""
var chapter := 1
var requires: Array[String] = []
var start_pos := Vector3.ZERO      # where the mission marker sits in the world (empty = starts automatically)
var stranger := false              # a side story: never chained, started at its marker
var region := ""                   # where it happens (journal)
var needs_flags := {}              # story flags that must hold too (a companion recruited and alive): {flag: value}
var companion := ""                # a companion's personal mission (camp marker, journal)

func flags_ok() -> bool:
	for k in needs_flags.keys():
		var v = Game.state.flags.get(k) if Game.state else null
		if v == null or v != needs_flags[k]:
			return false
	return true

func run(_d) -> Variant:
	return true

## Helpers shared by missions
static func road_point(a: String, b: String, frac: float) -> Vector3:
	for r in Game.world.features.roads:
		var fwd: bool = r.a == a and r.b == b
		var rev: bool = r.a == b and r.b == a
		if fwd or rev:
			var pts: Array = r.points
			var f := frac if fwd else 1.0 - frac
			var i := clampi(int(f * (pts.size() - 1)), 0, pts.size() - 1)
			return Vector3(pts[i][0], pts[i][2], pts[i][1])
	return Vector3.ZERO

static func place(id: String, dx := 0.0, dz := 0.0) -> Vector3:
	var t := Game.world.town(id)
	if t.is_empty():
		t = Game.world.poi(id)
	var p := Vector3(t.x + dx, 0, t.z + dz)
	p.y = Game.world.height(p.x, p.z)
	return p
