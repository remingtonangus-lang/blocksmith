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
dim; no stripes in the last ~6 degrees above the horizon (vertical luma roughness vs the cloudless frame, clear and
overcast); from a dark cave the clouds dim with the sky; 10 s of wind drifts the clouds along the wind; a minute of thunderstorm gives 4-25 distant flashes; desert air is
hazier, warmer and less cloudy and snow air colder blue, read from Game.skyColor/skyZenith after the sky state
settles on each biome.

Verifier pass 1 (independent review): FAIL on horizon aliasing, clouds not dimmed from caves, clouds drawn in blind
fog. Fixed: footprint filtering (each octave fades to its mean once its cells shrink under ~2 pixels, rim widened by the
footprint, octaves rotated against each other), u.wind.w carries caveScale, the pass is skipped under blind fog; checks
added for the first two. Also from the review: the silver lining is stronger at dusk, night clouds are more opaque over
the stars, a pending far thunder roll takes the louder of two flashes.

Run 2026-10-11 (after the review fixes): noon 66 % cover, cloud luma 196; overcast 83 %, sky luma 91 vs 184; storm 45;
storm flash 98; sunset cloud r 174 / b 111; night cloud luma 20; horizon roughness 1.62 / 1.66 (0.87 / 0.93 without
clouds); cave cloud luma 19; 8 distant flashes a minute.

### Cost
lavapipe (CPU rasteriser, relative only): a sky-filled 2 x 320x320 view 11.2 ms with clouds vs 8.4 ms without. On the
Quest the pass touches only sky pixels above the horizon, 7 value-noise taps (~30 ALU each) plus ~60 ALU of lighting and filtering,
fp32. The Clouds option turns it off. Device fps before/after is for lane M (M3) to confirm on the headset.

### Screenshots
docs/status/evidence/look-upgrade/sky_{noon,sunset,overcast,storm_flash,night,horizon,horizon_overcast}.png (after) and `_before.png` (the same
view without clouds, i.e. the Quest before this change).

## Part 2: the Powderwight (replaces the Hisser)

### Design note
- **Name**: Powderwight. **Look**: a hunched dead miner, grey-green skin, torn coat with ragged tails, a miner's cap with
  a dead lamp, dim amber eyes, a powder keg (staves, two iron hoops, fuse cord) slung high over its left shoulder so it
  shows beside the head from the front. Uneven silhouette, readable at 20 blocks at night by the amber eyes.
- **Role** (same as the genre mob it replaces): punishes inattention and damages builds. It walks up quietly; within
  3 blocks in sight it strikes the fuse and blows after 1.75 s (power 3; 6 if lightning-charged), unless the target
  gets 7 blocks away or out of sight.
- **Telegraph**: the fuse sizzle (sound, captioned "Powderwight fuse sizzles"), a bright flickering spark on top of the
  keg plus glowing sparks spitting off it, the keg rattling and swelling, the body leaning in with both arms thrown up,
  and a warm blink over its body.
- **Counterplay**: hit it (a hit stops the fuse, as before), back off past 7 blocks or break line of sight, shoot it,
  or douse it: water puts the fuse out and a soaked Powderwight cannot strike again for 4 s; rain makes its fuse burn
  slower (x0.7). Cats still scare it. Putting a lit fuse out with water earns the "Damp Squib" advancement.
- **Drops**: gunpowder 0-2 (unchanged; its keg). Head (by charged blast), banner pattern and music-disc rules unchanged.
- **Saves**: the internal key stays `creeper`, so every existing save's mobs, heads, banners and stats load as the
  Powderwight with no migration; a pre-change mob record is decoded in the checks.

### Checks (questcheck, quest/src/test/PowderwightTest.swift)
Name + key; an old save's record loads as a Powderwight; the lit fuse adds one bright emissive spark part; 1.7-block
model height; strikes its fuse beside the player on dry ground; the fuse spits glowing sparks from the keg; a hit stops
the fuse; water douses it and it stays out while soaked; once dry it strikes again. MobDrawTest still draws every kind.
Portraits: `questcheck --render X --mob-shots DIR --mob-kinds creeper` (day, night, lit, and
night20 / lit_night20 from 20 blocks at night) in docs/status/evidence/look-upgrade/mob_creeper_*.png;
mob_creeper_before.png is the Hisser.

Verifier pass (independent review): PASS with four defects, all fixed: the check now forces the state it depends on
(no mobs, not sneaking, no head armour, alive) and restores it; the soaked timer also runs while the mob has no target;
the keg was too small to read at range (now bigger, hoops glow amber and turn orange when lit, a bigger spark); the
command script and snap.sh still used the old mob names. The 20-block night portraits show the amber eyes and the lit
keg reading clearly.

## Part 3: trees

### Objectives (the overseer's list plus our own)
From the backlog: more tree shapes per species, woodland detail, trees that read as natural at a glance. Our own:
- Oak, birch and spruce each grow four distinct shapes; pines two; no two neighbours look stamped from one mould.
- Woodland litter in woods only: dead snags, stumps and fallen trunks (never on plains or in the open).
- A rare ancient oak: a 2x2 trunk 9-12 tall with a flared foot and heavy limbs, the landmark of a wood.
- Root flare on big trunks, only over solid ground (never a root over a drop).
- Every tree stays inside the 7-block placement margin, so a chunk border never cuts one, and grows the same from
  both sides of a border.
- Leaves must read as a canopy at every texture size and distance.

### What shipped
- `Sources/WorldGenTrees.swift`:
  - Oaks: a round dome with a low limb, a tall narrow one, a wide spreading one with three limbs, and a forked twin
    leader. Birches: the classic, a slender tall one, a twin pair from one foot, and one with a kink.
  - Spruces: classic, narrow, wide and ragged, high-crowned with a bare lower trunk. Pines: two tier patterns.
  - New kinds: dead oak and dead spruce snags, oak/spruce/birch stumps (some mossy), fallen oak trunks of
    bark-all-round wood with moss, and the ancient oak.
  - `choose` turns a few of a wood's trees into litter from a second roll of the same position hash (still a pure
    function of position); ancient oaks are about 1 % of forest oaks and 5 % of the lone oaks on plains and meadows.
  - Limbs climb before they step out (no gap under a raised limb); every random draw comes before any chunk-local
    test, so two chunks always agree on a tree.
  - Soil tests for every site run on the bare terrain before any tree is built (a site's test once saw a neighbour's
    root or trunk in one chunk and not the next).
- `Sources/TexturesHD.swift` leafCanopy: the leaf count no longer scales with the texture size. Leaves already scale
  with it, so canopies covered 85 % at 128 px but only 11 % at 32 px: every tree in 32/64 px shots (and on 32/64 px
  settings) was a stick with sparse speckles. Now 85-90 % at every size. The Quest's default 128 px is unchanged.

### Checks
- `questcheck` TreeTest (quest/src/test/TreeTest.swift): each kind grown 40 times into a blank chunk: distinct
  silhouettes (oak 31, birch 22, spruce 16, pine 23 of 40), no log cut off from the ground, no leaf more than 5 from
  wood, nothing past the 7-block margin (grown at both (8,8) and (7,7)); the ancient oak's 2x2 trunk is 9+ tall;
  fallen trunks lie on the ground (never over air); litter only in woods (0 of 4000 plains picks) and ancient oaks
  rare; leaf textures keep at least 50 % cutout cover at every mip.
- `questcheck --gencheck` (288 chunks over 3 seeds), before / after: floating_block 6/6, leak 2/2, leaves_orphan 1/1,
  ore_in_air 3/3, plant_floating 1/1, spring 10/10, trunk_floating 0/1. The one new floating log is a known class
  that predates this change: a cave or pool in the tree's own chunk removed the soil under its trunk, so that chunk
  grows nothing while the neighbour (which can't see the soil) grows its limbs. The old small crowns showed the same
  as an orphan leaf patch; the fix is a soil test that can see carving across chunks (noted in BUGS.md).
- Portraits: `questcheck --render X --tree-shots DIR` writes trees_{oaks,birches,spruces,woodland,ancient}.png
  (each tree grown alone on a floating pad, three-quarter view at noon). In docs/status/evidence/look-upgrade/, with
  trees_world_before.png / trees_world_after.png: the spawn view at 32 px before and after the leaf fix.
