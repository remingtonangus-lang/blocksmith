# World fx: material damage and weather (session H, branch claude/bs-world-fx)

Owner: session H. Scope: STATUS Future ideas #4 (material-aware damage) and #6 (weather with teeth). Other streams:
A integration (claude/blocksmith-playtest), B destruction physics + wrecks + the shared BlockMaterial table, D
soldiers / reactive bases / aircraft, E Quest port, a local Mac session for the controller driver.

## How it works

- **Material kinds** (`Wear.kind`, Wear.swift): stone, wood, glass, metal per block state. A stopgap derived from sound
  materials and names until B's shared `BlockMaterial` table lands; then `Wear.kind` reads its kind (one place).
- **Damage stages** reuse `World.damage` (face << 5 | level 1-7). `Wear.chipVisual` maps a level to the geometry the
  mesher and collision see: stone levels 1-3 stay whole and show crack decals, 4-7 chip; metal never chips (dent
  decals); glass shows cracks and shatters at the third (shard particles); wood chips as before.
- **Scorch** (`World.scorch`, stages 1-3): fire next to a full wooden block scorches it stage by stage, then it chars
  through into `smoldering_charcoal` (glows, light 7, cools to `charcoal_block` in a few fire ticks, can flare up in a
  wind) or burns away. Blasts leave soot (stage 1-2) on the crater rim.
- **Decals** (`WearDecals`): world-space quads on every exposed face of a damaged / scorched block within 64 blocks,
  rebuilt when `World.wearVersion` changes or the camera moves 16 blocks, drawn in the blended entity pass
  (crackFS). Textures (WearArt.swift): wear_crack_1-4, wear_scorch_1-3, wear_dent_1-3, fx_shard, charcoal blocks,
  painted at 16 px and 128 px from the same patterns.
- **Hooks**: mining (Game.swift, `wearHit`), bullets (Ballistics.impactBlock: player rounds shatter glass, every round
  may add a stage), explosions (`blastWear`; incendiary blasts now light a third of the crater).
- **Fire** (Fire.swift, moved out of World.swift): wind bias (downwind neighbours catch up to 2.5x sooner, embers jump
  up to 4 blocks downwind in a gale), `World.fireCap` = 1500 burning cells, every tick timed (`World.fireStats`).
- **Wind** (Storms.swift `stormTick`): one vector for ships (sails, storm windage), fire, rain slant and snow drift.
  Same slow turning as the old ship wind, plus storm gusts.
- **Storm sea** (`Waves`): three travelling swells (15 / 9 blocks, a cross swell) up to 1.3 blocks on open ocean
  (0.3 on rivers, 0.2 on lakes), sampled by ship buoyancy, so hulls roll and pitch; storm windage heels them. The
  Fancy water shader draws the same swell and whitecaps (dimTint.w = direction degrees + sea state).
- **Floods** (Flood.swift): a 64 x 64 grid of 4 x 4-block cells (+-128 blocks) with ground, natural water (base level)
  and sea sinks; rain adds depth, soil soaks the first half block, level-driven flow between cells, evaporation.
  Written to the world as `flood_water` sources (its own block, so a flood saved mid-storm is found and drained after a
  reload), at most 320 block writes per 0.5 s step, drained top-down as the level falls.
- **Lightning**: picks the tallest of a few nearby columns, lights fires round flammable targets, strikes in dry country
  too (dry lightning), bursts on ship hulls (ShipManager.blast). Rain puts out exposed fires 1 in 4 per tick (was 1 in 3).
- **Snow** (`snowTick`): chunk passes (one remesh per chunk, the ring round the player every 25 s); while it snows
  layers pile up to a depth that grows with the snowfall (up to 7, drifting per column; leaves hold one), then melt back
  to one layer (faster in sun; block light 12+ melts everything). New blocks `snow_layers_2...7`.

## Checks

`Blocksmith --snapshot snaps/fx_end.png --seed 12345 --time 0.3 --rd 8 --fxtest cracks,fire,flood,snow,storm --out snaps`
(snap.sh checks shard; focused runs via `[fast: ...]` in a commit message). Report: snaps/fxtest.md; shots
fx_cracks, fx_shatter, fx_blast, fx_fire_0-3, fx_flood_0-3, fx_snow_0-2, fx_storm_ship.

## State / next

- First version pushed; waiting for CI to compile and run the checks.
