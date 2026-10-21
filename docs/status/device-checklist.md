# Headset checklist (Oct 21 2026, for Remington's next Quest 3 session)

Everything here has only been seen in host renders. Say what you see into the voice notes as you go; the lane fixes from them.
Install a default (optimized) build with `tools/quest-local.sh --log 1500 > /tmp/quest-perf.log`, then read it with
`python3 tools/quest_perf_log.py /tmp/quest-perf.log --windows`. If P392 has merged by then, use that build.

## 1. Frame rate (do first, 15 min)
- View 24, about 5 min each: Stone Gulch, a capital city, an Ash Vault battle. Note stutter, hitches, any heat warning.
- Same spots at views 8 and 16 for a minute each.
- Optional: SpaceWarp on at view 24 (off by default, P381). Does moving stuff (mobs, ships, water) smear? Keep it or leave it off.

## 2. Polygon ground (P338, P377, P381, P383; replaces P142/P175)
- Walk meadows, hills, a beach, a cave: any visible grid, stair-steps, seams, gaps at chunk edges.
- See-through spots (P335): cave walls, digging into the Emberdeep's walls.
- Dig and place: does the ground chip off naturally, no cube-shaped holes?

## 3. Feet, aim and placed things (P386, P387, P382)
- Stand on slopes: feet floating or sinking?
- Dig/place aim lands where the ground is drawn.
- Place a block on a slope: gap under the downhill side? Copper wire lies on the ground (not buried or floating)?

## 4. Far land (P339, P375, P376, P384)
- Far land looks like near land (no coarse blocky look), no popping as you move.
- Mobs past the active distance standing frozen: does it look odd?

## 5. Physics (P351, P380, P388, P389, P298)
- Cut a tree at the base: it falls; carry a log.
- Dig under a thin overhang: it breaks off and falls. Ravines: no floating chunks.
- Weight: wool breaks easily, logs hold, a pile of titanium on a wooden house collapses it.
- Hit a lamp post: a chunk flies off where you hit it; keep hitting until it breaks.

## 6. Fluids (P363, P378, P356)
- Lava look. Remove a source: the flow drains away.
- Water clinging to walls? Water settling onto beaches?
- Kelp near and far.

## 7. Railways (P337, P379)
- Rails look right (no gravel over them); lines connect towns, villages and bases with cuttings, bridges, tunnels.
- Ride a train and drive the cab: throttle and brake.

## 8. Content reworked since your Oct 16 notes (never seen)
- Ash Vault redesign (P326): no longer hell-like; the crashed plane (P346); prison camp to raid and liberate (P347);
  German base full of soldiers, workbench crafting tab (P348).
- Frigate: fixed main gun along the keel, narrower real-ship layout (P325, P357).
- Sunken Dreadnought: findable at the locate coordinates, big enough (P349).
- Hell made our own: ghasts/withers/blazes gone, yellow biome replaced (P292, P336); the Emberdeep's own sky (P342).
- Mahlwerk rotary gun on the top troop class (P391).
- Sword fighting: wind-ups, blocks, parries, staggers (P308).
- Difficulty: does Easy still kill you fast? (P358)
- Helicopter at the base (P333).
- 40 music tracks (P359) and ~925 recorded sound effects (P361): anything wrong, missing or annoying.
- No text in play (P300, P328): any leftover toasts or hints? Start a new world: can you work out what to do without text?

## 9. Stability (counts toward Meta's checks)
- One 30-minute session without quitting: any crash?
- Quit and reload a world saved before this build: loads with your edits intact?
- Time a cold launch to playable (store wants under 15 s), into a new world and a saved one.
- Headset temperature after 30 min.

## 10. Older items, only if there's time
- Six-iron aim and recoil; hunting, skinning, the fishing fight; townsfolk melee variety.
- Horse running animation and pace, the whistle call.
- Gun sights line up with the muzzle (P32); falling water seen from the side (P18).
