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

- **Plumes**: big fires send up large dark smoke puffs seen from 128 blocks (fireSmoke), smoke and flames lean with
  the wind (ParticleManager.drift); smouldering charcoal smokes and sheds embers.
- **Stars** follow the sun alone and hide behind rain clouds (they shone through a noon thunderstorm).
- **Flood vs the fluid sim**: flood_water never flows, feeds or becomes ordinary water (World.fluidTick skips it).
- **Idle cost**: on dry days the flood model only trickle-samples (16 cells a step, to find flood water from a save).

## Checks

`Blocksmith --snapshot snaps/fx_end.png --seed 12345 --time 0.3 --rd 8 --fxtest cracks,fire,flood,snow,storm,wildfire --out snaps`
(snap.sh checks shard; focused runs via a `[fast: <args>]` marker in the head commit message: the workflow takes the
FIRST `[fast: ` in the message, so never quote the marker literally elsewhere in it - run 471 ran `Blocksmith ARGS`). Report: snaps/fxtest.md; shots
fx_cracks, fx_shatter, fx_blast, fx_fire_0-3, fx_flood_0-3, fx_snow_0-2, fx_storm_ship.

## Item art (Remington's TV playtest, 2026-10-05)

- **Icons** (ItemHD.swift): every `item_` layer at the GPU resolution. Vector designs for tools (7 tiers x 6 kinds),
  armour (7 x 4) and ~40 common items; Scale2x x3 + bevel light + drop shadow for the rest. Licences:
  docs/qa/items/LICENSES.md (all procedural). Before/after sheets: docs/qa/items/{before,after}, harness
  `--itemsheet tools|items|blocks|enchanted[:scale[:page]]`.
- **Models** (ItemModels.swift): every sprite item extruded from its icon (32 x 32 mask captured at texture build):
  first person (grip, sway, chop, bow draw, eating), third person (right hand, own F5 view and co-op seats), dropped
  (upright, turning, nearest 32 within 24 blocks).
- **Glint**: a violet band sweeping across the item's shape (hudFS layer + 8192, entityFS uv.w).
- **Water plants** carry the water's surface (Mesher): seagrass, kelp and coral no longer cut holes in shallow water.

## Measured (fast lane, release build, macos-14 runner; runs 472-473)

| Check | Result |
|---|---|
| decals | 130 quads on the crack wall; frame 4.0 ms (1280 x 800) |
| burning house, wind 13 b/s | peak 186 burning, 82 charred, spreads downwind 242 / upwind 64; fire tick mean 0.02 ms, worst 0.95 ms; frame 4.3 ms |
| fire cap (plank field lit all over) | 1500 burning (cap), tick mean 1.6 ms, worst 1.9 ms |
| flood, 10 min heavy rain on a river valley | 9,145 flood blocks (3,955 shoreline), 740 of 4,096 cells, model step worst 2.5 ms; frame 5.3 ms; recedes to 652 after 15 min, 264 after 30 |
| snow, 4 min snowstorm then 10 min sun | mean depth 0.98 -> 4.34 -> 0.99 layers; chunk pass mean 0.04-0.07 ms, p95 0.06-0.14 ms (World.bulkSet) |
| gunboat in a full storm | max tilt 11.4 deg (1.2 calm), afloat and upright; lightning on it 129 -> 126 hull blocks; frame 5.9 ms |
| wildfire (dry thunderstorm over savanna, gale) | 20 strikes in 4 min, peak 1,138 burning, 4,049 burned, out 10 min after; tick p95 0.8 ms |

Bench scene `weather` (bench.sh, perf shard): 8 s of whole game ticks in a thunderstorm over a burning plank field with
400 damaged blocks: weather.tick_ms p50/p95/max, fire / flood / storm worst, decal quads. Not gated.

## State / next

- Rebased on playtest 983ea14; heavy lane ([full]) running on 71cfc20 before the first fast-forward into playtest.
- Waiting on session B's BlockMaterial table: switch `Wear.kind` to it. Coordination points for B: `World.wind` /
  `Game.fx.storm` (a wind load for their support analysis: a storm could bring down weak spans), `World.scorch` and
  charcoal (burnt blocks could count as weak), `Waves.height` (wrecks afloat).
- Next: bug hunting in this area (flood edge cases: villages in valleys, caves, saves mid-flood; snow on stairs/slabs;
  fire in structures), a storm-at-sea shot of the Capital frigate (kinematic: does not roll; stream D/B own it).
