# C7: sky isles and the Grapple Line (Lane A, 2026-10-12)

What a player sees: now and then, far from spawn, a lens of rock and turf hangs high in the sky (displayed y 236-262)
with a few trees and a broken Skyward Shrine on top. The shrine's chest holds sky loot: lift balloons, propellers, an
engine, sometimes a whole Sky Skiff kit, gold, a Grapple Line. An isle goes on the map (letter K) once a player comes
within 160 blocks of it. The way up is a flyer (the Sky Skiff, A4) or the Grapple Line.

- `Sources/SkyIsle.swift`: the `sky_isle` structure (regions of 40 chunks, 4 in 10 hold one, never within 800 blocks of
  spawn, never over a peak that would reach it), its shape (a lumpy disc, radius 10-17, a dome of turf, an underside
  tapering to a keel 14-27 blocks deep), trees, the shrine and the `sky_isle` loot table; map discovery; the Grapple Line
  (iron ingot + two string; right click casts at a block or a vessel within 24 blocks and reels the holder in at 16
  blocks a second with no fall damage; a hook on a ship follows its deck; sneaking, switching item or arriving lets go).
- Old saves: ground saved before the isles keeps an empty sky (`structure-guard-skyisle.txt`), so no isle is cut off at
  the edge of explored land.
- Checks: `questcheck --skyisle-only` (`Sources/SkyIsleTests.swift`): placement over six seeds, a real isle's chunk
  (turf, rock, shrine chest, open air under the keel), loot, the grapple's recipe and reel through `Game.tick`, the empty
  sky, a hook on a skiff's deck.

Defaults picked (no questions asked, per the standing rules):
- The Capital's armoured airships are the existing flying frigates; no new hull, and they keep their own patrol routes
  (a frigate circling an isle is left for later, see the backlog T item).
- The isles are a sparse sky layer rather than a full dimension: the Deep is a dimension below, but a second sky
  dimension would double world memory on an 8 GB machine and a Quest 3.
