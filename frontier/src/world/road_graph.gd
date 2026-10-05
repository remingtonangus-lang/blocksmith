class_name RoadGraph
extends RefCounted
## Graph over the road network (worldgen polylines): nodes every ~16 m, roads joined where their ends meet (towns,
## junctions). route(a, b) returns a polyline following roads from the road point nearest a to the one nearest b
## (A*), with straight legs to/from the roads. Used for the map route, horse auto-ride and NPC travel.

var pts: PackedVector3Array = []
var adj: Array = []              # per node: Array[int]
var _grid := {}                  # Vector2i(64 m) -> Array[int] for nearest lookups

func build(world: WorldData) -> void:
	for r in world.features.get("roads", []):
		var prev := -1
		var poly: Array = r.points
		var step := maxi(1, int(16.0 / 8.0))
		for i in range(0, poly.size(), step):
			var p := Vector3(poly[i][0], poly[i][2], poly[i][1])
			var id := _node_at(p, 6.0)
			if id < 0:
				id = pts.size()
				pts.append(p)
				adj.append([])
				var k := Vector2i(floori(p.x / 64.0), floori(p.z / 64.0))
				if not _grid.has(k):
					_grid[k] = []
				_grid[k].append(id)
			if prev >= 0 and prev != id:
				if not adj[prev].has(id):
					adj[prev].append(id)
				if not adj[id].has(prev):
					adj[id].append(prev)
			prev = id

func _node_at(p: Vector3, tol: float) -> int:
	var k := Vector2i(floori(p.x / 64.0), floori(p.z / 64.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for id in _grid.get(k + Vector2i(dx, dz), []):
				if Vector2(pts[id].x - p.x, pts[id].z - p.z).length() < tol:
					return id
	return -1

func nearest(p: Vector3) -> int:
	var best := -1
	var bd := INF
	for r in [1, 3, 8, 20]:
		var k := Vector2i(floori(p.x / 64.0), floori(p.z / 64.0))
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				for id in _grid.get(k + Vector2i(dx, dz), []):
					var d := Vector2(pts[id].x - p.x, pts[id].z - p.z).length()
					if d < bd:
						bd = d
						best = id
		if best >= 0:
			return best
	return best

func route(a: Vector3, b: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var s := nearest(a)
	var g := nearest(b)
	if s < 0 or g < 0:
		return PackedVector3Array([a, b])
	# A*
	var came := {}
	var gs := {s: 0.0}
	var open: Array = []
	_push(open, pts[s].distance_to(pts[g]), s)
	var closed := {}
	while not open.is_empty():
		var cur: int = _pop(open)
		if cur == g:
			break
		if closed.has(cur):
			continue
		closed[cur] = true
		for n in adj[cur]:
			var ng: float = gs[cur] + pts[cur].distance_to(pts[n])
			if ng < gs.get(n, INF):
				gs[n] = ng
				came[n] = cur
				_push(open, ng + pts[n].distance_to(pts[g]), n)
	if not came.has(g) and s != g:
		return PackedVector3Array([a, b])
	var chain: Array[int] = [g]
	while chain[-1] != s:
		chain.append(came[chain[-1]])
	chain.reverse()
	out.append(a)
	for id in chain:
		out.append(pts[id])
	out.append(b)
	return out

# binary min-heap of [priority, node]
static func _push(h: Array, pri: float, v: int) -> void:
	h.append([pri, v])
	var i := h.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if h[parent][0] <= h[i][0]:
			break
		var t = h[parent]
		h[parent] = h[i]
		h[i] = t
		i = parent

static func _pop(h: Array) -> int:
	var top: int = h[0][1]
	var last = h.pop_back()
	if h.is_empty():
		return top
	h[0] = last
	var i := 0
	var n := h.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < n and h[l][0] < h[m][0]:
			m = l
		if r < n and h[r][0] < h[m][0]:
			m = r
		if m == i:
			break
		var t = h[m]
		h[m] = h[i]
		h[i] = t
		i = m
	return top
