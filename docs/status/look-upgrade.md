# L1 look upgrade (Lane C, from 2026-10-11)

Backlog item L1 (docs/roadmap/backlog.md): sky, mob and animal models, the creeper replacement, trees. Quest renderer
first; shared code stays platform-neutral so the Mac build keeps compiling. Shipped as one PR per part.

## Part 1: the sky (PR after #24)

### Objectives (the overseer's list plus our own)
From the backlog: a day gradient that shifts with sun height; real sunrise/sunset colours; moon with phases and stars
at night; 2-3 cloud layers at different speeds following one wind direction; overcast and rain skies darken the world
and the clouds; storms with distant lightning flashes; the sky matches each biome (hazier in desert, cold blue in snow);
cheap on Quest (measured).

Our own additions:
- The Quest had no clouds at all (only the Mac drew its blocky genre clouds). Clouds must look real (soft cumulus
  with lit tops and shaded bases, not boxes) and cost no geometry or CPU time per frame.
- Clouds hide the stars, sun and moon behind them; a clear night still shows full stars.
- No aliasing or stripes toward the horizon; the deck fades into the horizon haze.
- Sunset and sunrise clouds take the gold/pink light; night clouds are dim moon-grey shapes, not glowing blobs.
- Storm flashes light the inside of the clouds around one direction (not a full-screen white flash) and a far thunder
  roll follows a few seconds later.
- Biome air eases in over a few seconds as you travel (no snap at a biome border); desert and badlands also get fewer
  clouds, swamps and jungles more.
- A Clouds on/off option in the Quest settings for anyone who wants the GPU time back.
- Automated checks for every point above; screenshots in docs/status/evidence/look-upgrade/.

### What shipped
- `quest/shaders/clouds.frag` (new pass after the dome, stars, sun and moon; blended at depth 1, so only over open sky):
  a cumulus deck ray-cast onto a plane at internal y 340 (displayed 276, above every peak) and a cirrus deck at y 900,
  both moving with one wind (`SkyState.wind`; cirrus at 0.6 of the cumulus drift, streaks stretched along the wind).
  Cumulus: 4 octaves of value noise cut at a threshold set by the cover, one extra tap toward the sun for
  self-shadowing, a silver lining near the sun, aerial haze and fine-octave fade toward the horizon. 7 value-noise
  taps per sky pixel; nothing below the horizon (discard).
- `Sources/SkyLook.swift` (shared): `SkyState` on `Game.sky` holds the wind and drift (Double, no precision loss over
  long sessions), the biome air (tint, haze, fair-weather cover per biome, eased over ~4 s), and storm flashes
  (`flashAt`, flicker envelope ~0.5 s). Distant flashes every 3-12 s in a full thunderstorm with a far thunder roll
  2.5-7 s later; real strikes (`Game.strike`) flash the clouds toward the bolt. `Game.cloudCover` = biome cover pushed
  to overcast by rain and thunder.
- `Game.skyColor` / `skyZenith` apply the biome air (Mac and Quest): desert/badlands hazy and warm with a paler
  zenith, snow and cold biomes cold blue, swamps damp grey-green.
- `FrameUniforms` gained `clouds`, `cloudFlash`, `wind` (Swift and common.glsl in step).
- Quest Settings: "Clouds: On/Off" (`QuestSettings.clouds`, default on).
- Already there and kept: the dome gradient by sun height, sunrise/sunset glow, the anti-twilight arch, moon phases,
  twinkling stars that fade with the sun and under rain, the night band.

### Checks (questcheck --render; `--sky-only` runs just these; quest/src/test/SkyTest.swift)
Each view is rendered with and without the cloud pass and compared pixel by pixel (left eye, 320x320 on lavapipe):
fair-weather noon cover 12-85 % of an upward view and bright; rain closes the cover and darkens the sky; a
thunderstorm darkens it further; a storm flash lights the clouds; sunset clouds are warm (r > b); night clouds are
dim; 10 s of wind drifts the clouds along the wind; a minute of thunderstorm gives 4-25 distant flashes; desert air is
hazy/warm and snow air cold/clear.

First run (2026-10-11): noon 71 % cover, cloud luma 189; overcast 88 %, sky luma 92 vs 179; storm 46; storm flash 98;
sunset cloud r 173 / b 108; night cloud luma 19; 7 distant flashes a minute.

### Cost
lavapipe (CPU rasteriser, relative only): a sky-filled 2 x 320x320 view 10.9 ms with clouds vs 8.7 ms without. On the
Quest the pass touches only sky pixels above the horizon, 7 value-noise taps (~30 ALU each) plus ~40 ALU of lighting,
fp32. The Clouds option turns it off. Device fps before/after is for lane M (M3) to confirm on the headset.

### Screenshots
docs/status/evidence/look-upgrade/sky_{noon,sunset,overcast,storm_flash,night}.png (after) and `_before.png` (the same
view without clouds, i.e. the Quest before this change).
