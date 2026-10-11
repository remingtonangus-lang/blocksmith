# Objectives: polygon terrain test (backlog M1, task 25b5a)

Remington's ask: try the polygon (smooth) terrain idea, playable as a world option on Quest so he can walk around in it,
fps measured against blocks (QuestSim and the device if adb sees it), side-by-side shots, a short verdict.

Expanded objectives (ticked with evidence in docs/status/polygon-test.md):
1. World option: Create New World has "Terrain: Blocks / Smooth (Test)"; the choice is saved with the world (WorldMeta
   extra "terrain"), applied before the first meshes on load (Quest and Mac), and shown in the worlds list.
2. Saves: every older world loads as Blocks; switching never changes block data; Quick New World keeps the current
   world's terrain. Test: `--smoothtest` (save/load round trip, older save, create page action).
3. Switch in place: Video > "Smooth Terrain (Test, This World)" flips the open world (remeshes in the background) and
   is saved with it. The create page remembers the last choice (also `smoothTerrain = on` in quest-settings.txt).
4. Feel: natural one-block steps are walked up (no jump) with the eased VR view step; built blocks still need a jump.
5. Shots: the same views in both modes through the Quest renderer (questcheck, lavapipe) side by side.
6. Performance: Quest-proxy bench routes (7, incl. taiga) in both modes: p99, max, load, memory; quads drawn and CPU
   record on the Quest renderer; device numbers when the headset is on adb (device checklist entry).
7. Verdict: what reads better, what breaks, cost, and the recommended next step.
8. M3 (device feel for merged lane A/B features): only with the headset; listed in the device checklist otherwise.
