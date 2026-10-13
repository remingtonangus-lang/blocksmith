# C10 legendary weapons and armour (2026-10-13)

What shipped (Sources/Legendaries.swift; check: `questcheck --legends-only`, Sources/LegendariesTests.swift):

- **Eleven legendaries, one each per world.** From the four legendary animals' bodies (Greyfang, Frostjaw Mantle,
  Ramhorn Maul, Ember Hood), from the bosses you bring down (Wyrmbone Blade from the Hollow Wyrm, Blightward Helm from
  the Blight, Hush from the Warden, Tidecaller from the elder guardian, the Marshal's Word from the Ash Marshal, the
  Chancellor's Mandate from the Ash Chancellor) and the Greywall Aegis from the strongbox of the first Command
  Fortress you take.
- **A look and a story.** Each is its base item (sword, coat, revolver...) with its own name in gold, a glint, its perk
  and a two-line story in the tooltip (`ItemStack.legend`, saved with the stack; never stacks).
- **Perks.** Greyfang +30% and heals on each hit; Frostjaw Mantle a quarter less from blows; Ramhorn Maul +25% and
  double knockback; Ember Hood fire resistance; Wyrmbone Blade sets foes alight, +50% on bosses; Blightward Helm night
  vision and no withering; Hush speed; Tidecaller water breathing and swift swimming; the Marshal's Word +40% and no
  recoil; the Chancellor's Mandate +25% and half the recoil; the Aegis 35% less from bullets, shells and blasts.
- **The gallery.** Hang them in item frames: those within 24 blocks of you are your gallery (a toast for each new
  piece, +5 honour when all eleven hang together).

Fixed on the way: the once-a-second hub (TownLaw.tick) ran the nation, seasons and now legendaries every frame; they
now run once a second as intended.

Leftovers (not built): unique models or textures per legendary (they use the base item's art with the glint), a gallery
plaque naming each piece, legendaries that never wear out.
