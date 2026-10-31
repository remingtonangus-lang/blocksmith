# Store art candidates, Oct 31 (none final until picked)

Rendered by the game's own renderer (questcheck --view: the headset's Vulkan renderer, shaders and meshes; field
world, headset detail, view 16, fov 80), left eye, drawn at twice the size and scaled down (smooth edges). No text,
logos or HUD. World seed 7639458412018979794 (his world's seed).

| File | Size | What |
|---|---|---|
| hero_sunset_village.png | 2560 x 1440 | Hero: a frontier village at sunset, a Greywall tower and mountains behind |
| small_landscape_sunset_village.png | 1280 x 720 | The hero scaled down |
| square_sunset_village.png | 1024 x 1024 | Square: the same village and tower under the sunset sky |
| portrait_sunset_village.png | 1440 x 2560 | Portrait: the same, closer |
| shot_capital_streets.png | 2560 x 1440 | The Capital's streets at noon |
| shot_passenger_train.png | 2560 x 1440 | A passenger train at a plains town |
| shot_snowy_village.png | 2560 x 1440 | A village in snowy pines |
| shot_greywall_base.png | 2560 x 1440 | A Greywall base in the snow |
| shot_savanna_village.png | 2560 x 1440 | A savanna village |
| shot_river_village.png | 2560 x 1440 | A village by a river, the Capital's skyline far off |

Remake one (from the repo dir, cloud-setup env): `questcheck --view OUT.png --field --questlod --seed 7639458412018979794
--rd 16 --w 5120 --h 2880 --fov 80` plus:
- hero / small: `--at 3000,200,0 --near village --off 60 --up 22 --look 0,-12 --time 0.48`
- square (`--w 2048 --h 2048`): `--at 3000,200,0 --near village --off 60 --up 22 --look 0,-4 --time 0.48`
- portrait (`--w 2880 --h 5120`): `--at 3000,200,0 --near village --off 45 --up 18 --look 0,-14 --time 0.48`
- capital: `--at 0,200,0 --near capital_city --off 60 --up 12 --look 10,2 --time 0.22`
- train: `--at -1500,200,1500 --rail 50 --train passenger --railoff 14,4,10 --look 60,-6 --time 0.45`
- snowy: `--at 1500,200,-1500 --near village --off 60 --up 22 --look 0,-12 --time 0.3`
- base: `--at 0,200,0 --near military_base --off 110 --up 35 --look 0,-10 --time 0.3`
- savanna: `--at 0,200,3000 --near village --off 60 --up 22 --look 0,-12 --time 0.4`
- river: `--at -1500,200,1500 --near village --off 60 --up 22 --look 0,-12 --time 0.4`
Keep the left half, scale to the store size. About 30 s a shot on the cloud host.

Known looks in these frames: far buildings past the view show as pale boxes over the fog (river, snowy); the views
have no people, hands or guns (those need the headset).
