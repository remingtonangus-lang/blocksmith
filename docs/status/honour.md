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

## Code
Honour.swift (honour, bounties, the revolver drop, HonourHUD), FrontierTown.swift (office, boardwalks), HonourTests.swift.
Edits: TownLaw.swift (saved fields, offence / turnHostile / tick hooks, heat cooling), Townsfolk.swift (pay the law,
keepers refuse while wanted), Shops.swift (ShopPricing honour nudge; gunsmith buys the revolver), Guns.swift +
CapitalArms.swift (gun_revolver, index 7, icon and model; Guns.isHandgun), Game.swift (mobDied hook), Mob.swift
(playerHurtAt), Ballistics.swift, Village.swift / TownBuildings.swift (frontier lots, false front helper),
Structures.swift + World.swift (structure-guard-frontier.txt), HudExtras.swift, Advancements.swift, MilitaryTests.swift.

## Checks (repeatable)
- `questcheck --towns-only` (host, ~2.5 min): TownTests.run including HonourTests: standings; prices inside the shop
  bounds at every honour x reputation x Friend of the Town; unseen theft free, witnessed theft/assault/hostility/murder
  cost; an old hit or a villager killed outside a town is not murder; daily caps on deeds; heat cooling by honour;
  keepers refuse while wanted; the sheriff refuses partial payment, takes full payment, forgives the grudge and the
  shop reopens; outlaw challenged on arrival; bounty lapses on day 7 not 6; save round trip; HUD on screen; revolver
  registered / model / icon / not sold; 5.1% drop over 20,000 rolls, forced drop loaded; 3 towns each with an office,
  jail cell and WANTED board, 24/24 shop fronts with a boardwalk; a guarded (old-save) town has no office.
- Full questcheck also runs all of the above (TownTests.run).
- `questcheck --render R.png --golden DIR`: town_shop.png now shows the general store's covered boardwalk.

## Verifier pass (independent Opus subagent, 2026-10-10) and what changed
- Fixed: MilitaryTests (Mac --mobtests) still expected 7 guns.
- Fixed: after paying, a sheriff with old bad gossip (reputation < -100) turned on you again within 0.5 s; paying now
  clears the town's negative gossip about you (checked with a -250 grudge).
- Fixed: killing a villager at your own base (a made-up town name, no law) cost honour and shut its traders for 7
  days; murder now needs a real town (TownLaw.isTownSpot).
- Fixed: killedByPlayer is never cleared, so a villager punched long ago (or near a missed rocket) dying to a zombie
  counted as murder; murder now needs the player's hit within 10 s (Mob.playerHurtAt).
- Fixed: boardwalk posts could float over a lower street and the clearing could notch a higher street's path; a 5x5
  office's cell door was reachable only diagonally (the shelf moved out of the way).
- Known: the boardwalk posts stand on the street's edge column, narrowing a 3-wide street to 2 at each post (by
  design: the boardwalk is the street's edge). The house turned into the office loses its resident.

## Gap pass (2026-10-11, docs/status/cloud-gap-pass.md area H)
Built what the expanded objectives asked for and #19 left out; checked by HonourGapTests (part of TownTests):
- **Log + meter**: every change is logged ("day|amount|why", last 60, saved; TownLaw.Saved.honourLog). The HUD meter
  swells and brightens for 0.8 s on a change, with a chime (up) or a knell (down), and shows the reason under it.
- **Theft**: unseen theft now costs a third of a witnessed one (0.5 a point of heat).
- **Deeds**: fair trades +0.5 (3 a day); jobs and donations (below); protecting towns as before.
- **Tiers**: Outlaw: refused service in every town, fought on sight (the first to see you cries out, 3 s later the
  armed attack and the rest run), hunted in the wild (bounty hunters); surrender to any sheriff or deputy for a $10
  fine (plus bounties) to drop back to Disreputable. Disreputable: warned off when greeted. Respected: tips about a
  place nearby ("Word is there's an outlaw camp about 300 blocks north-west of here"), greeted by name. Honourable:
  a gift once per town per day.
- **Notice board** (TownBoard.swift; the WANTED board in the sheriff's office, or talking to the law when you owe
  nothing): honour, wanted posters, two jobs a day per town (deliveries paid between shop sell and buy prices, hunts
  near town, a named outlaw with his gang to bring in), a $1 donation (+2 honour, 6 a day), and your name (picked from
  a list: VR friendly, no keyboard).
- **Posters**: a town's WANTED boards show your own poster while you're wanted there or an outlaw.
- **Bounty hunters** (BountyHunters.swift): outlaws or $25+ in bounties, out in the wild: a posse of 2-3 once a day.
- **Sheriff's Revolver**: now 5% of sheriffs *carry* it (rolled once, saved; they shoot straighter and harder with it,
  say so when greeted, and always drop it), as the brief says; before it was a 5% drop from any sheriff.
- New list screen (ListMenu.swift, the shop's look) reused by the board and later screens.
