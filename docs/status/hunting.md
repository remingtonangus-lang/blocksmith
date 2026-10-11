# Hunting, pelts, legendary animals and fishing (backlog B3, 2026-10-11, Lane B thread)

Remington's intent: hunting like RDR2, with pelts and the rest. Listed: animal quality (poor, good, perfect) shown when
studying an animal; clean kills with the right weapon keep perfect pelts; a skinning animation; pelts, meat, hides and
trophies; a trapper or butcher buys pelts by quality; outfits, saddles and satchels (bigger inventory) crafted from
pelts; legendary animals with map clues and unique pelts; fishing with species, sizes and a minigame that works in VR.

## Expanded objectives (written before building)
1. **Game animals and quality.** Rabbits, foxes, wolves, goats and bears (the polar bear) are game. Each wild adult
   has a quality rolled once and saved with it: poor 30%, good 50%, perfect 20%. Tamed, owned and baby animals are
   not game.
2. **Studying.** Hold your aim on a game animal for 0.4 s, up to 32 blocks away (or 96 while looking through a
   spyglass). A line under the crosshair shows its name, quality as stars, and the weapon that keeps the pelt whole,
   for example "Fox: perfect *** (bow or a pistol)". It is the same line as the townsfolk glance and works with the VR
   aiming hand.
3. **Clean kills.** Every hit you land records the weapon class: arrow, pistol, rifle, shotgun, heavy, spear or melee.
   The pelt loses one or two quality steps for:
   - the wrong weapon for the animal's size (small, medium or large);
   - too many hits for the animal.
   A kill with no hit of yours (an explosion, fire, a fall, your dog) leaves a poor pelt. The right tools are:
   - small game: a bow or a pistol;
   - medium game: a bow, a pistol or a rifle;
   - large game: a bow, a rifle or the Farsight.
4. **Carcass and skinning.** An animal you kill leaves its body lying on its side for 3 minutes instead of dropping
   loot. Aim at it and hold use (left trigger in VR) to skin it: 0.8 s for small game, 1.2 s for medium, 1.8 s for
   large, with knife sounds, bits flying and a progress line, cancelled if you let go or look away. You get:
   - the pelt at its quality;
   - meat (1, 2 or 3 by quality);
   - sometimes a trophy (a wolf fang, a bear claw, a rabbit's foot).
   Animals killed by anything else drop what they always did.
5. **Pelts as items.** One item per species and quality (Poor / Good / Perfect Rabbit Pelt, Fox Pelt, Wolf Pelt, Goat
   Hide, Bear Pelt). They stack (16 small, 8 medium, 4 bear) and work in bundles, chests and every inventory. Gamey
   Meat cooks into Cooked Game Meat.
6. **Selling.** The butcher buys every pelt, fang, claw and fish, priced by quality (poor about 0.3x, perfect about
   2.5x good), through the usual shop pricing (reputation, honour, owned towns).
7. **Crafting from pelts.**
   - A fur set (hood, coat, trousers, boots) from good or perfect pelts. It sits between leather and chainmail and
     keeps the cold out like leather (powder snow); fur boots walk on powder snow.
   - A Hunter's Satchel: a carry-all bundle with 4x a bundle's room, crafted from a perfect pelt, leather and string.
     A Legend's Satchel from a legendary pelt holds 8x.
   - A saddle from two good pelts, leather and iron (saddles otherwise come only from loot).
8. **Legendary animals.**
   - Four per world, each with a den at a seeded spot 700-1600 blocks from spawn in a fitting biome where one is found:
     the Ashen Wolf, Old Frostjaw (a bear), the Crag Ram (a goat) and the Ember Fox.
   - Each is bigger (x1.4-1.6) and much tougher. The wolf and the bear charge you, the ram rams, and the fox runs.
   - Each is named, appears only at its den, and is gone for good once killed (saved).
   - The butcher sells a Hunter's Map ($40). Using it marks the next legend's den on the world map, with its name.
   - Skinning a legend always gives its unique pelt (it sells high and makes the Legend's Satchel) and its trophy.
9. **Fishing.**
   - Each catch is a species and a weight, by water and biome:
     - rivers, swamps and lakes: Yellow Perch, Rainbow Trout, Northern Pike, Channel Catfish and Salmon;
     - oceans: Cod, Salmon (cold), Pufferfish and Tropical Fish (warm).
   - Hooking a fish starts a fight that works the same on a pad, a mouse and the Touch controllers:
     - hold use to reel; let go when the line is too tight;
     - the fish makes runs (strong pulls, more for heavy fish) and tires between them;
     - too much tension snaps the line, and too much slack lets it get away.
     - A tension bar under the crosshair, rumble on runs and the bobber thrashing show it.
   - Records per species are kept (saved), with a toast for a new record. Heavy fish (the top fifth of the range)
     give two fish.
   - Junk and treasure still come in at once, as before.
10. **Saves and performance.**
    - Quality and legend status are saved in the mob's extra record. Legends killed, dens revealed and fish records
      are saved in the world meta. Old saves load.
    - No per-frame allocation. The study scan runs only while the aim lingers, carcasses are capped at 12, and the
      legend check runs once a second.

## Defaults picked (no questions, per the autonomy rule)
- No new animal models (mob looks belong to the Mac worker). The carcass is the animal's own model rolled on its
  side, and legends are the existing animals, bigger and named.
- Domestic animals (cows, pigs, sheep, chickens, horses) keep their usual drops; hunting is for wild game.
- The butcher is the trapper: every town already has one, so no new shop kind and no town-generation change.
- Arrows hitting after you switch weapons count as the weapon in hand when they land (the hit hook sees the held
  item).

## Checks
`questcheck --towns-only` (part of the full questcheck), HuntingTests via TownTests.run:
- items and prices: poor < good < perfect < legendary, and the butcher buys them all;
- the quality roll (30/50/20);
- the weapon-fit table;
- clean kills: an arrow keeps a perfect fox; a shotgun, a sword, a sprayed rifle and no hit of yours each cost
  quality, while 2 Farsight rounds keep a perfect bear; tamed and baby animals aren't game;
- the body drawn on its side, resting on the ground;
- skinning by holding use (timing, yield, letting go resets);
- sale prices, the fur and satchel recipes with their tag, satchel room and the fur look;
- the study line after a steady aim;
- legendary dens (seeded, distinct, 300-2000 blocks out), the Hunter's Map, a legend's stats and loot, save round
  trips;
- fishing: species by water, weights, and bot anglers. One who eases off lands a big pike, one who reels non-stop
  snaps it, an idle one loses it, and a small perch reels straight in.
- a hooked fish fought on the real rod until it comes in.

## Verifier pass (independent Opus subagent, 2026-10-11) and what changed
- Blocker fixed (VR): with a bow in hand the left trigger was taken by the bow's nock, so a bow hunter couldn't skin;
  aimed at a body, the trigger now skins (QuestControls).
- Fixed:
  - Skinning state is per co-op seat, so the other seat no longer resets it. The skinning and fish-fight lines show
    for either seat, ahead of a townsperson's glance.
  - A legend counts as gone only once it's skinned or its body's loot drops. A legend body left to rot drops its pelt
    and trophy instead of vanishing. Bodies last until you're 160 blocks off (was 96, closer than a Farsight shot).
  - Bodies belong to their dimension. A new world drops the old world's hunting state (it carries its seed).
  - A Hunter's Map read away from the surface world does nothing.
  - Legends can't be tamed.
  - A fish fight near full line no longer ends silently.
- Noted: the spear counts as a clean weapon on medium game (a default, beside the listed tools).
- Re-verify: the per-second upkeep restarts with a new world's clock (so the new-world reset really runs), and a legend's
  body waits for its ground to be loaded before its loot drops.
