# Tool upgrades replace enchanting (backlog B5, 2026-10-11, Lane B thread)

Remington's intent: enchanting is too similar to the original; make it tool upgrades that still need experience.
Listed: a workbench upgrade tree per tool and weapon (sharper edge, reinforced head, balanced grip, scopes, extended
mags), paid with experience plus materials; visible changes on the model; old enchanted items convert in saves.

## Expanded objectives (written before building)
1. **The Upgrade Bench.** The old enchanting table becomes the Upgrade Bench (same save key, new name). Using it opens
   a list screen, not the spell-table screen:
   - It works on the tools, weapons and armour you carry, including the armour you're wearing. One row picks the
     item; the rows under it are that item's upgrade tree.
   - It runs on the shared ListMenu, so it works the same with a mouse, a pad cursor and the Touch laser.
   - No lapis, no random offers and no bookshelves.
2. **An upgrade tree per kind of item.** Every old enchantment becomes a named physical upgrade on a part of the item:
   - edge, head or bit, grip, limbs or string, lining, plates and soles;
   - the guns' magazine, loader, scope and rounds.
   Examples: Honed Edge (was sharpness), Reinforced Head, Balanced Grip, Stabilising Scope, Extended Magazine.
   Levels and effects stay as they were, so combat and mining balance doesn't move. Parts that conflict still exclude
   each other (one edge metal: honed, silvered or serrated; one bit: fine or prospector's; one lining or plate set). The curses are not upgrades.
3. **Paid with experience plus materials.**
   - Each level costs experience levels (level + 1; advanced parts +3).
   - Each level also costs the item's own material (planks, cobblestone, iron, gold, titanium, copper, steel,
     leather...) and a part-specific one: flint for an edge, lapis for a prospector's bit, blaze powder for a heated
     edge, glass for a scope.
   - Creative mode is free. The row shows the full cost and why a row is unavailable.
4. **Visible on the model.**
   - Guns: a scope on top (Stabilising Scope), a longer magazine (Extended Magazine) and a coloured band on the barrel
     for special rounds. These appear on the screen model and on the Quest's held model.
   - Tools and weapons: coloured accents on the held model (a grip wrap, a bright band on the head, a line along the
     edge in the treatment's colour), on the Mac and the Quest.
   - Inventory icons: small upgrade pips in place of the violet glint.
5. **Old saves convert.**
   - Enchantments load as the matching upgrades (same storage), and curses are dropped.
   - Enchanted books become Upgrade Kits that the anvil fits as before. Loot and trades keep giving pre-upgraded gear
     and kits.
   - No player-facing text says "enchant" any more (the screen, the advancement, the tooltips).
6. **Checks.** Every enchantment that can go on an item has an upgrade line with a name and a cost. Buying a level
   charges the right experience and materials, refuses what you can't afford, respects conflicts and the maximum, and
   works on worn armour. Old-save conversion drops curses. Gun models gain parts with upgrades, and tool accents
   appear. The namecheck stays clean.

## Built (2026-10-11, Lane B thread)
- Sources/Upgrades.swift: the parts and materials per upgrade, costs, `fit`, conversion, model accents, gun parts,
  icon pips and the Upgrade Bench screen (UpgradeBenchMenu, a ListMenu). Enchant.swift keeps the storage and effects;
  its names are now the upgrade names. Loot and librarian kits never roll curses; old curses load stripped.
- Guns.writeFirstPerson takes the upgrades (cached parts per gun and set); the Mac arm buffer and the Quest guard are
  1536 vertices (worst gun with every part ~1340). Held tools draw accent quads on both renderers.
- Renamed player-visible text: Upgrade Bench, Upgrade Kit, Bottle of Experience, Radiant Golden Apple, "Repair &
  Strip Parts", the advancement "Fine Tuned", the sound captions.
- Checks: TownTests "upgrades:" (UpgradesTests.swift), 14 checks.

## Differences
- Upgrade Kits (old enchanted books) are still fitted on the anvil, as books were.
- The bench's model and recipe still look like the old table; a new look belongs to the look owner (lane M).
