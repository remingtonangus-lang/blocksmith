# P400: cold launch under 15 seconds

Host numbers from `questcheck --launch` / `--launch-prepare` (quest/src/test/QuestLaunch.swift), built with the
headset's compiler setting (`QUEST_OPT=-Ounchecked`), Remington's seed (Stone Gulch's world), view 24, active
distance 8, on the 4-core cloud host with nothing else running. The harness runs the headset's own launch path
(QuestApp.load on the loading thread, then QuestApp.adoptLoaded and the first frame), with lavapipe in place of the
Adreno, from the start of the load to the first world frame the player can move in, then on until every chunk in the
view is meshed (the player standing, looking slowly round). Logs: `/mnt/project-files/p400/` (not in the repo).

Runs, in order: **new cold** (a new world, first launch of a build: the textures are painted), **new warm** (a new
world, textures read from the cache), **prepare** (a new world played until the view is full, then a pit dug, a hut
built and a tunnel carved by the spawn, saved and quit), **saved** (that world opened again).

## Step 1: the split (seconds, host)

| stage | new cold | new warm | saved |
| --- | --- | --- | --- |
| textures (painted / read from the cache) | 1.49 | 0.28 | 0.27 |
| new world made (spawn found) / saved world opened | 0.90 | 0.98 | 0.11 |
| near ring (radius 3, 69 chunks: gen + first meshes) | 1.28 | 1.01 | 1.36 |
| horizon and middle rings (far land) | 1.08 | 1.00 | 0.91 |
| warm-up tables, rails and bases | 0.31 | 0.18 | 0.23 |
| renderer and textures uploaded | 1.12 | 0.73 | 0.83 |
| first world frame | 0.12 | 0.16 | 0.12 |
| **first interactive frame** | **6.41** | **4.31** | **3.84** |

(questcheck's own process start, 0.6 s, is not the app's and is left out; the headset adds its own process and
OpenXR start-up, which the host can't measure.) Three further runs of the same build: new cold 5.37-6.41 s, new warm
4.02-4.41 s, saved 3.84-4.19 s.

## Steps 2-4: what changed

- **Far meshes cached on disk per world** (P376's MeshCache): every save now also writes the meshes of the finished
  chunks past the keep distance that changed since they were last written (`World.saveMeshCache`), so the next launch
  installs the far land straight from the disk. An edit drops only its own chunk's file; the stamp is the mesh
  format, the block and texture registries and (on the headset) a hash of the sources that shape meshes and terrain
  (`QuestBuild.meshHash`, written by build-apk.sh), so an update that leaves those alone keeps every cached chunk.
- **The cache never matched its next launch** (found here): the deep journal items were registered by walking a
  dictionary, whose order changes from run to run, so six texture layers (and the stamp, which hashes the texture
  names) came out in a different order in every process. The items are now registered in key order. (The same
  disorder could also give a warm launch's cached textures the wrong journal icons.) The stamp now hashes the
  registries as start-up leaves them, not as they stand when the cache is first opened.
- **The cache is opened during the load** (one directory read; the file sizes are summed behind the load), not by the
  first far-chunk scan or block change of play.
- **The first ticks' plans moved to the loading thread** (QuestWarmup.world): the rail lines within the trains' reach
  (124-188 ms) and the nearby bases' starts (28-43 ms), which the first once-a-second ticks planned on the frame
  thread (host before: trains 68-167 ms and the Greywall alarm 23-40 ms on one tick).
- **The painted textures are written to the cache behind the load** (the first launch of a build no longer waits for
  the 170 MB write).
- Play starts as soon as the near ring (radius 3) and its collision are in; the far land fills in behind on the
  workers (step 3). No stage of the split is over 1.5 s; the new world's spawn search, the near ring and the
  renderer's upload are each about 1 s.

## Step 5: the saved world's view, with and without the mesh cache (same build; `BS_SAVEMESHES=0` turns it off)

| saved world | first interactive frame | view 24 filled after the first frame | half filled | chunks from the cache |
| --- | --- | --- | --- | --- |
| without (as before) | 4.18 s | 71.9 s | 36.5 s | 0 |
| with | 3.84-4.19 s | 34.7-41.6 s | 16.0-19.3 s | 1,068 of the 1,068 past the keep distance |

While the view fills, 0.3-0.9% of frames go over 13.9 ms on the host (tick + record), with or without the cache;
most are one handed-over result (a chunk's meshes applied, or a chunk installed) taking 18-51 ms on the frame thread
while the four host cores are all busy meshing. New mesh slabs cost under 0.1 ms each.

## Headset estimate

P385's headset log had command recording at 10-12 ms where the host took about 7 ms, so the headset's cores run this
code about 1.4-1.7x slower; at 2x, the host's worst first interactive frame (6.41 s, a new world on the first
launch of a build) is about 12.8 s on the headset, and a saved world (4.19 s) about 8.4 s: under the 15 s target.
The headset's own start-up (Android process, OpenXR session) is not in these numbers.
