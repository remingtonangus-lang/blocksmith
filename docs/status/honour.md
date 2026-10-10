# Frontier towns, honour and the sheriff's revolver (2026-10-10, branch claude/project-thread-dkuflx)

Backlog item 1 (Remington, 2026-10-10 20:36): "RDR towns, ... honour system, sheriff 5% gun chance". This thread owns
the frontier-town look, honour and the sheriff's gun; horses and the frigate gun / village bug sweep are sibling
threads. Builds on PR #11 (towns of people) and PR #16 (capital markets, merged into this branch).

## Expanded objectives (written before building)
1. **Honour** (one per-world score, -100 to +100, saved): what you do in the open changes it, the way a frontier
   reputation should. Lose it for theft and vandalism in towns (scaled by the town's heat), assaulting townsfolk, a town
   turning on you, killing townsfolk (more for a deputy, most for the sheriff). Earn it by killing monsters in or near a
   town (raiders count double), killing outlaws (Brigands and raiders' crossbowmen away from raids), and owning up to a
   bounty. Daily caps on the gains so grinding zombies can't max it. Five standings: Outlaw, Disreputable, Neutral,
   Respected, Honourable.
2. **What honour does**: shop prices (up to 5% better for the honourable, up to 10% worse for outlaws, always inside
   the shop price bounds so no money loop opens), how townsfolk greet you, how fast a town's heat cools (twice as fast
   when honourable, half as fast for an outlaw), and the law: an outlaw is challenged by the sheriff on arrival in
   any town.
3. **Bounties**: a town that turns on you puts a price on your head; killing its people raises it. While a bounty is
   out in a town its keepers won't serve you and the law challenges you there. Pay it by talking to the sheriff or a
   deputy (also mid-fight: that's surrendering), which ends the town's hostility, cools its heat and gives a little
   honour back. A bounty lapses after 7 days with no new crime there (no soft lock when you can't pay and the
   sheriff is dead).
4. **The sheriff's revolver ("5% gun chance")**: a new six-shot gun, the Sheriff's Revolver, that only a sheriff
   carries. Killing a sheriff drops it 5% of the time (he always drops a few cartridges). Never sold in shops (gunsmiths
   do buy it). Its own icon and held model, one-handed like the sidearm.
5. **Frontier towns** (new towns only; ground a save already generated keeps its old buildings via a structure
   guard): a sheriff's office near the square (stone front, a desk, a jail cell behind iron bars, a WANTED board),
   covered plank boardwalks with posts along every shop front, and the shops' awning run the full width.
6. **HUD**: the honour standing under the wallet (shown in towns and for 6 s after a change, with the change).

## Defaults picked (no questions asked, per the autonomy rule)
- "Sheriff 5% gun chance" read as: a killed sheriff drops his revolver 5% of the time.
- Honour is per world (like the wallet), not per town; per-town standing stays the townsfolk's gossip reputation.
- Spelling "Honour" (British, matches the rest of the game's text, e.g. "colour"). A generic word, not an IP term.

## Pre-mortem (how a player could break or dislike it, and the check for each)
1. Grinding honour by farming zombies at night -> daily cap per source (HonourTests).
2. Money loop from honour discounts -> ShopPricing still clamps to the bounds TownTests' no-arbitrage check uses;
   HonourTests checks every honour value stays inside them.
3. Soft lock: a bounty you can't pay with the sheriff dead -> deputies take payment; bounties lapse after 7 days.
4. Revolver drop rate wrong or never seen in tests -> 20,000 rolls land within 4-6%; a forced kill drops it.
5. Old saves: towns half-generated get a mismatched office or half boardwalks -> structure guard file
   (structure-guard-frontier.txt); HonourTests checks a guarded town builds exactly the old layout.
