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
   each other (one edge treatment, one bit, one lining). The curses are not upgrades.
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
