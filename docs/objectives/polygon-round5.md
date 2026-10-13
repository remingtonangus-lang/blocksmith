# Polygon round 5 (P175)

Remington, Oct 13 13:02-13:21, after playing round 3 (build 448c3de) on the headset: "it doesn't feel built from the
ground up yet." The caves are the winner, so they stay as they are.

## Expanded objectives (written before building)
1. **Things sit on the polygons.** Grass, flowers, ferns, saplings, mushrooms and other plants stand on the drawn smooth
   ground, not on the block top it was rounded from, so they don't float over a dip or sink into a bump. The height
   comes from the very surface vertices the mesher draws. Animals and people do the same (World.smoothGroundOffset,
   PR #89). Ragdolls are P171's job (another thread).
2. **Water meets the shore naturally.** In polygon worlds the water plane carries on under the shore's smooth ground,
   so the waterline is wherever the ground crosses the water level, a curve and not a block outline. There are no
   vertical water walls against natural ground, and stepped rivers ramp (PR #87).
3. **The pickaxe mines what it touches.** In polygon worlds the crosshair or hand ray hits the drawn surface (the
   smooth solidity field over the blocks), and the block mined is the solid block nearest that point. Air that looks
   like ground is ground, ground that looks like air is air.
4. **Real shapes for natural things.** Tree trunks are round (an octagonal-or-better prism with bark wrapped round it,
   ends capped with rings), and they taper a little toward the top. Branches are round limbs that meet the trunk. The
   leaf crowns stay the rounded blobs from PR #85. Pumpkins and melons are ribbed round gourds. Collision, chopping and
   saves still use the blocks.
5. **Procedural fracture.** A hit (pickaxe, hand, bullet) breaks polygon pieces off at the point it actually struck:
   the surface dents there, not toward the block's centre, and irregular shards with the block's texture fly off and
   fall, a little different on every hit. The block still breaks when its damage is complete, so mining times don't
   change.
6. **More blocks blend in.** Every natural block that lines caves and the surface (including the custom rocks) is part
   of the smooth surface.
7. **Lag.** Render distance 16 holds 72 fps on the Quest: smooth meshing gets cheaper, and far sections don't pay
   for detail nobody can see. (Device fps is measured on the Mac lane; here the mesh cost per section is measured.)
8. Ship each piece as its own PR into claude/quest-port as soon as it plays; one and done.
