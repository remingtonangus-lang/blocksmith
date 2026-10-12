# Map fog of war and the compass (backlog A5)

Lane A thread, 2026-10-12. Code: Sources/MapFog.swift (MapFog, CompassHUD), WorldMap.swift (MapDraw.terrain draws
the fog, the minimap redraws when it lifts), MapFogTests.swift (`questcheck --mapfog-only`; every full run).

- Map and minimap show only ground a player has been within 96 blocks of (32-block tiles, revealed once a second
  round every split-screen player); the rest is dark. Discovered sites stay marked on the dark map: bases and towns
  you passed, plus what a Radar Set, a taken Greywall map table or a frigate's radar reveals from afar.
- Explored tiles are saved per world and dimension (mapfog.json beside mapmarks.json).
- Creative play shows the whole map (default picked: fog is a survival feature).
- Compass: held in either hand on the surface, a strip across the top shows the heading (N in red) and the
  discovered sites within 120 degrees ahead by their map letters, and names the nearest site with distance and
  direction.
- Bases reveal bases (A1 map tables) and frigates have radar (A3): this item ties them to the map.
