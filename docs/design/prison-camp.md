# The Ash Vault prison camp (P347): content notes

Remington's ask (Oct 16 19:53): a camp in the Ash Vault he can raid and liberate, freeing the prisoners. Code:
Sources/PrisonCamp.swift (prisoners, liberation), Sources/AshSites.swift case "prisoncamp" (the camp).

## What is in it
- A walled camp south-east of the citadel (x 160, z 300): a double wire fence with one gate, four watchtowers, a
  gatehouse, the guards' block with the commandant's papers, a bare roll-call ground and four long plank huts with
  two tiers of bare bunks.
- Prisoners: civilians in worn, patched clothes, gaunt, some sitting on the bunks and some standing. They turn their
  heads toward the player when he is near.
- Liberation: when no Ashguard soldier is left alive inside the wire and the player is there, the camp is free
  (saved: TownLaw vaultObj "prisoncamp"). The prisoners rise, walk out through the gate and up the road, and are gone
  once out of sight.

## Store content rules (Meta Quest content guidelines) and how the camp keeps to them
- Fictional army: the Ashguard is Blocksmith's own. No real camp, no real people, no swastika or other Nazi symbol, no
  SS runes, no real unit marks. The camp has no sign board and no text.
- No depiction of killing, torture or cruelty to prisoners. No gas chambers, ovens, mass graves or bodies anywhere in
  the camp. No striped uniforms, numbers or badges.
- Prisoners can never be harmed: every hit on them is ignored (Mob.hit), they belong to no side (factionValue .none),
  so no soldier aims at them and no reward exists for harming them.
- The focus is liberation: the only thing the player does with the prisoners is set them free.
- Nothing is played for comedy.
