# Store trailer and action screenshots (Oct 31)

Remington, Oct 31 16:32: "i want some good videos and stuff for the advertisement page ... they need to understand it
is a mix of [a spy shooter, a frontier western, a block-building sandbox] and a ww2 game ... the videos should kind of
show that." The mix comes across from the footage itself: no other game, name, logo or look is named or shown.

## What the trailer shows (about 60 s, 1920 x 1080, 30 fps, stereo AAC)

| # | Shot | What happens | Caption (captioned cut only) |
|---|---|---|---|
| 1 | town_crane | A frontier village at golden hour, the camera rising over the rooftops | A frontier with towns full of people |
| 2 | town_street | Down the village street, townsfolk about | |
| 3 | capital | The Capital's streets at midday | |
| 4 | train | A passenger train running through the savanna | Ride the rails |
| 5 | build_cabin | A cabin rising block by block, the camera circling it | Build anything, block by block |
| 6 | cave | Down a torch-lit cave with lava pools | Explore the caves below |
| 6 | station_air | A Boreal Station in the snow at night, lit, from over the pines | Slip into a secret base in the snow |
| 7 | station_gate | Up to the floodlit gate, guards inside | |
| 8 | station_corridor | The bunker corridor, a guard turning the corner | |
| 9 | ash_vault | Ashguard troops and a tank at the Ash Vault in the Deep (the game's own faction: no real insignia) | Fight through the last war |
| 9b | war_advance | An Ashguard line with a tank and a halftrack against Capital riflemen, shells landing | |
| 10 | tank_breakup | A Cinder Tank knocked out and coming apart | |
| 11 | frigate_fire | A Meridian frigate over the savanna | Take the helm of a warship |
| 12 | frigate_strike | Its Tidebreaker slug striking the village's stone tower | and bring its main gun to bear |
| 12b | hell | Over the lava rivers of the deepest layer | Then go deeper |
| 13 | finale | Sunset over the village, then the title card | |

Music: the game's own main_title (the frontier half) into ash_vault_battle (from the station on), with the game's own
blast sounds under the explosions. Two cuts: with captions and without (Meta allows either; the clean one also works
as a background loop).

## How it is made (all in the cloud, no headset)

1. `questcheck --cine docs/store/trailer-shots.json --out DIR --w 2560 --h 1440` (quest/src/headless/Cinema.swift):
   each shot builds its world (his seed 7639458412018979794, field ground, headset detail rings), finds its subject,
   warms the game up so townsfolk walk and guards take posts, then plays its events (soldiers and vehicles spawned,
   blasts, a tank breaking up, a frigate and its main gun, a cabin built block by block) while the camera flies its
   keyframes, the game ticking at 72 Hz between frames. About 1 s a frame at 2560 x 1440 on the 4-core cloud host.
   `--still` writes only the middle frame of each shot (docs/store/screenshot-shots.json: the action screenshots,
   rendered at 5120 x 2880 and scaled to 2560 x 1440).
2. `tools/cine.py clips DIR` encodes each shot (scaled to 1920 x 1080), `tools/cine.py cut DIR OUT.mp4 [--captions]`
   cuts the trailer.

Shot format: a JSON list of shots, each with `name`, `seconds`, an `anchor` (`near` a structure kind `from` an x,z;
`find` a biome; `rail` N percent along the nearest railway with a `train`; `station` a Boreal Station camera spot;
`frigate` dx,dz,yaw to spawn a frigate and anchor on it; or `at` a spot), `time` (day fraction), optional `timeRate`,
`rain`, `survival`, `peaceful`, `warm`, `fov` (vertical), `rd`, and `cam` keyframes (`t`, `pos`, `look`, relative to the
anchor; `ground`: y over the ground there; `cut`: a hard cut). Events: `spawn` (mob key, `@ash` for the Ashguard,
`^deg` heading, `n`, `spread`), `vehicle` (ash_tank, ash_halftrack, ...), `wreck`, `explode` (`power`, `fire`),
`fire` (the frigate's main gun, `pitch`), `impact` (a Tidebreaker strike at a spot), `build` (a cabin, `size`, `dur`),
`time`, `rain`, `survival` (turn it on after the warm-up, so no shells land before the shot), `place` (a block such as
torches on the floor round a spot, `n`, `spread`). Anchors also take `cave: true` (an open cave room under the found
spot) and `deep: "vault"|"hell"` with `dim: "deep"`.

Nothing rendered goes into the repo: the clips, the trailer and the stills live in the project files
(store-media/2026-10-31/).

## Known looks

- Far structures past the view distance draw as pale stand-in boxes over the fog: the village shots use rd 18 so the
  real Capital citadel is loaded instead.
- The thin line under the frigate is its boarding ladder.
- The strike is filmed from above: since PR #645 a fresh Tidebreaker crater keeps its floor.
