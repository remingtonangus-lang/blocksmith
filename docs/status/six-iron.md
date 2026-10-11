# The sheriff's six-iron, the iron rule and taking a town (backlog B1, 2026-10-11, Lane B thread)

Remington's intent: the sheriff carries a six-shooter that one-shots you in anything below iron armour, is a middle
ground in iron, and hardly hurts diamond (titanium) and above. You play by the rules until you have titanium or at
least iron, then you can take a village.

## Expanded objectives (written before building; the backlog's listed ones plus mine)
1. **Every sheriff carries the six-iron** (replaces the 5% gun chance). The old saved per-sheriff roll is read but
   ignored. Player-visible name "Six-Iron" (was "Sheriff's Revolver").
2. **The iron rule, as a table in code** (`SixIron.damage`, quoted in the tests' output): an armour score where a full
   iron set is 1.0 (each piece's points against iron's in the same slot, plus half its toughness, weighted by body
   coverage), so any armour lands where it belongs without a lookup list. Below 0.9: one round kills, on every
   difficulty but peaceful. Iron: 8 -> 3 half-hearts across the band (3 shots in iron, 5 in steel). 1.9 and up
   (titanium, Duskium): 1 (2 on hard).
3. **A readable, fair duel in VR**: his challenge draws the gun (hammer click, gun out) and he fights 2.5 s later; the
   first round of a fight is a warning over your head with a line; every shot is telegraphed (arm level at you + a
   click, 0.65 s) and fires at where you were when he took aim, so stepping aside, dropping low or ducking behind
   cover dodges it, and standing still gets you hit. Spread grows with range (tight at 10 blocks, looser at 22).
   Reach 22 blocks (deadly at range). Six rounds, then a 2.4 s reload: the window to close in.
4. **Shield and armour**: a raised shield still blocks a round (and wears); worn armour takes 2 wear a round.
5. **Taking a village**: the sheriff falls to you and no deputy of that town is left standing (within 10 min) -> the
   town surrenders: hands up, hostility, heat and the bounty there end, old grudges dropped, -10 honour on top of the
   killings. Then it is yours: keepers always serve you at their best price (inside the shop bounds), its beds and
   chests are yours (no theft counts there, outlaw status ignored there), townsfolk call you boss, tribute $6 a day
   (up to 7 days) paid when you walk in, a sheriff sent later works for you.
6. **Nearby towns react**: for 10 days, towns within 2000 blocks of one you took call you out on arrival, start on
   edge (heat 2: one more crime turns them) and charge 10% more.
7. **Saves**: owned towns persist (TownLaw.Saved.owned); old saves load (field optional).

## Defaults picked (no questions, per the autonomy rule)
- "Six-iron" as the gun's player-visible name (a generic frontier term).
- A killed sheriff drops his six-iron 25% of the time (was 5%): killing one now needs iron or better, so the trophy
  is worth more, and a sheriff only returns three days later.
- Lethal stays lethal on easy (the iron rule is the game's spine); peaceful does no harm.
- "A bed and storage" read as: the town's own beds and chests become yours (no theft, keepers serve you), instead of
  placing new blocks into a town that may not have room.
- Capitals (Capital cities with soldiers) can't be taken this way; only frontier towns (villages) with a sheriff.

## Damage table (normal difficulty, from the test output)
| armour | score | half-hearts a round | rounds to kill from 20 |
|---|---|---|---|
| none, leather, golden, chainmail, copper | 0-0.81 | lethal | 1 |
| iron | 1.00 | 8 | 3 |
| steel | 1.62 | 5 | 4 |
| titanium (diamond tier) | 2.35 | 1 | 20 |
| Duskium | 2.85 | 1 | 20 |
Easy x0.65 in the iron band, hard x1.35; titanium 2 on hard. Iron with leather boots counts as iron (0.93); iron
with bare feet doesn't (0.85).

## Code
SixIron.swift (the rule, the duel, `Game.sixIronHit`), TownConquest.swift (surrender, ownership, tribute,
neighbours), SixIronTests.swift. Edits: Townsfolk.swift (TownState aim/reload/warned/drawn; every sheriff carries
it; townDefend hands the player duel to SixIron; keepers serve you in your town), TownLaw.swift (Saved.owned, the
draw on the challenge, monsters-only `shoot`, offences in your own town ignored, TownConquest.tick), Honour.swift
(drop chance, lawFell hook, no challenge in your town), TownsfolkModel.swift (aim and recoil poses), Shops.swift
(ShopPricing town standing), Guns.swift (name).

## Checks
`questcheck --towns-only` (part of the full questcheck): SixIronTests (iron rule table, real rounds against worn sets,
the duel: draw, warning, telegraph, 10/10 hits standing, 0/10 when stepping aside or crawling, reload; conquest:
deputy alone changes nothing, surrender, honour, free theft, pricing, keeper serves despite a grudge, boss greeting,
tribute and its cap, wary neighbours and expiry, save round trip, old save). TownLawTests' "shoots an outlaw player"
now wears iron (in leather the round killed the test player and cascaded into later checks).
