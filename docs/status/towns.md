# Towns of people, shops and money (2026-10-09, branch claude/towns-of-people-j6qgts)

## What a player sees
- Villages are towns now. Every townsperson has a name ("Virgil Ridley of Dry Springs"), a look (clothes, hats, hair,
  beards by role and trade) and a day: work or mind the shop in shop hours, eat at midday (at the saloon when there is
  one), socialise in the evening, sleep at night. Deputies patrol the square and never take a bed.
- Townsfolk carry swords, pitchforks, hammers, cleavers, axes, shovels or hoes by trade. Armed folk fight monsters
  that come within 14 blocks (and 40 of home); children and the unarmed run. Hurting a townsperson angers the armed
  ones nearby for 30 s; very low standing (reputation below -100) makes them hostile on sight in survival.
- They react to the player: greetings within 4 blocks (at most every 45 s each), hands up when a gun is aimed at them.
- Each town has a general store and a saloon, then the other six trades (gunsmith, butcher, doctor, stable, tailor,
  blacksmith) as lots allow: tall flat false fronts in the shop's colour, an awning, a sign with the shop's name, a
  counter with the keeper behind it. Shops keep hours (saloon until late); talking to a keeper opens the shop.
- Money: dollars and cents (start $5.00, saved). Buy and Sell tabs, x1 / x5 / all, stock that restocks daily, two
  services (the doctor patches you up, the saloon serves a hot meal). Prices follow progression (bread $0.30, iron
  tools a few dollars, titanium and guns far more); standing and Friend of the Town nudge prices within fixed bounds.
- Kept: treasure maps (now also sold by the general store and saloon), the inventory, the old trade screen for
  craftsfolk outside shops.

## Code
Shops.swift (Money, ShopKind, Economy, ShopPricing, ShopMenu, Shop), Townsfolk.swift (names, roles, weapons, defence,
reactions, alarm, talk), TownsfolkModel.swift (looks and models), TownBuildings.swift (shop lots), TownTests.swift.
Edits: Villager.swift (VillagerData fields, all optional/Codable), Mob.swift (AI hooks, model), VillageLife.swift
(eat/social/patrol schedule), Village.swift (shop and saloon lots), Effects.swift (money save), ExplorerMaps.swift.

## Checks (repeatable)
- `questcheck` (Quest host checks) and Mac `Blocksmith --towntests`: TownTests.run - every shop item exists and is
  priced; shop sizes; prices rise with tiers; no buy-craft-sell or buy-smelt-sell profit over every recipe at the price
  bounds; pricing refusal; buy/sell/service round trips; every shop message and name fits its line; nothing drawn
  outside the panel for 8 shops x 2 tabs x every scroll; 60 named townsfolk; a keeper minds the counter in shop hours;
  every role has a full model; no shop -> emerald barter -> shop profit (cheapest emerald from shop goods vs the best
  emerald offer sold back, at the best multipliers, bounded by the general store's emerald exchange: docs/status/economy.md); an armed townsperson fights a zombie; hurting one angers the deputy and the child runs;
  3 generated towns hold all 8 shop kinds, deputies and a sign per shop; every townsperson and keeper spawns on a
  floor with head room; hitting a townsperson already fighting you costs no more standing.
- `questcheck --questsim OUT.png`: talking to a storekeeper opens the shop on the VR panel, B closes it; OUT_shop.png.
- `questcheck --render R.png --golden DIR`: town.png (aerial) and town_shop.png (a general store front).
- Evidence: docs/status/evidence/2026-10-09/towns_sheet.jpg (left eye of the VR shop panel, town_shop, town).

## Pre-mortem (5 ways a player could break or dislike it, and the test for each)
1. Infinite money by buying low and crafting/smelting into something that sells high -> TownTests economy no-arbitrage
   over Recipes.all at the price bounds (minBuyMult vs maxSellMult).
2. Shop text cut or unreadable in the headset -> TownTests shop UI width/overflow checks; sim_shop.png judged by eye.
3. Townsfolk attack the player for nothing, or stand by while monsters kill them -> defence checks (zombie fought,
   anger only after the player hurts someone, and decays).
4. A shop with no keeper, no sign, or a door/counter you cannot reach -> towns check (3 seeds of towns), structcheck
   walkability on Mac CI; keeper sleeps in the shop's own bed.
5. Old saves break (missing fields) -> VillagerData fields optional; money defaults to $5.00 when absent.

## Verifier pass (independent Opus subagent, 2026-10-09) and what changed
- Fixed: emerald barter money loop (9 glass bottles bought for $0.45 bartered for an emerald the general store bought
  at $3.00). Bottles, paper and books repriced; the barter check above guards it. (2026-10-10: the general store trades
  emeralds again at $1.00 buy / $1.20 sell, see economy.md.)
- Fixed: keepers spawned on the back shelves (gunsmith inside iron bars) and the shop bed went through the back wall.
  Counter moved a row forward; keeper row and fittings row are separate; spawn floor/head-room check added.
- Fixed: self-defence against an angry townsperson kept costing standing until the whole town turned hostile; a
  pointed gun now costs standing once a minute per person, not every 2.5 s.
- Fixed: rotten flesh sold for $0.00 at the worst standing (refused now); the shop closes at closing time or when
  the keeper lies down; darker text on the shop panel; the doctor's half bed is a couch; two surnames swapped.
- Known: towns generated in a world before this change keep their old buildings (no shops or deputy); new chunks get
  towns. "Qty: Max" buys up to one stack.
