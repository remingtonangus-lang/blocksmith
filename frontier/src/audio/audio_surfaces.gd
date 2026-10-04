class_name AudioSurfaces
extends RefCounted
## Ground surface under a point for footsteps and hooves: registered floors/interiors first (boardwalks, saloon
## floors), then water, snow line, rock (steep slopes, red-rock breaks), roads (packed dirt; gravel in the mountains),
## mud (wet bottoms or after rain), sand (desert with sediment), grass, forest floor (dirt + needles).
## Control map channels (WorldData.ctrl): r road, g moisture, b biome (0 desert .. 0.5 grass .. 1 forest), a sediment.

const SURFACES := ["dirt", "grass", "gravel", "stone", "wood", "mud", "water", "sand", "snow"]
const SNOW_LINE := 1150.0

static func surface_at(pos: Vector3, director: Node = null) -> String:
	if director != null:
		for v in director.surface_volumes:
			if (v.aabb as AABB).grow(0.3).has_point(pos):
				return v.surface
		for v in director.interior_volumes:
			if (v.aabb as AABB).has_point(pos):
				return v.surface
	var w: WorldData = Game.world
	if w == null or not w.ok:
		return "dirt"
	var ground := w.height(pos.x, pos.z)
	# shallow water (fords, lake shore)
	var wl := w.water_level(pos.x, pos.z)
	if wl > ground + 0.05 and pos.y < wl + 0.6:
		return "water"
	# standing clearly above the terrain on something solid inside a settlement: a boardwalk, porch or floor
	if pos.y > ground + 0.25:
		var town := w.nearest_settlement(pos.x, pos.z)
		if not town.is_empty() and Vector2(float(town.x) - pos.x, float(town.z) - pos.z).length() < float(town.get("r", 100.0)):
			return "wood"
		return "stone"       # rocks, ledges
	if ground > SNOW_LINE + _snow_noise(pos):
		return "snow"
	var c := w.ctrl(pos.x, pos.z)
	var n := w.normal(pos.x, pos.z)
	var wet := 0.0
	if Game.sky != null:
		wet = float(Game.sky.get("wet"))
	if c.r > 0.45:
		if ground > 900.0:
			return "gravel"
		if wet > 0.55 or c.g > 0.85:
			return "mud"
		return "dirt"
	if n.y < 0.78:
		return "stone"
	if c.b < 0.22:
		if c.a > 0.45:
			return "sand"
		return "gravel" if c.a > 0.2 else "stone"
	if c.g > 0.8 and (wet > 0.35 or c.a > 0.6):
		return "mud"
	if c.b > 0.75:
		return "dirt" if fposmod(pos.x * 0.37 + pos.z * 0.21, 1.0) < 0.4 else "grass"    # needles and duff
	if wet > 0.7 and c.b < 0.45:
		return "mud"
	return "grass"

static func _snow_noise(pos: Vector3) -> float:
	return sin(pos.x * 0.013) * 40.0 + cos(pos.z * 0.011) * 40.0

## Biome summary for ambience/music: "desert", "plains", "forest", "mountain", "marsh", "river".
static func biome_at(pos: Vector3) -> String:
	var w: WorldData = Game.world
	if w == null or not w.ok:
		return "plains"
	var ground := w.height(pos.x, pos.z)
	var c := w.ctrl(pos.x, pos.z)
	if ground > 950.0:
		return "mountain"
	if c.g > 0.8 and ground < w.lake_level + 25.0:
		return "marsh"
	if c.b < 0.25:
		return "desert"
	if c.b > 0.7:
		return "forest"
	return "plains"
