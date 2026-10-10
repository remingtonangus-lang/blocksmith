# Economy: emeralds and dollars (2026-10-10)

Remington (Quest playtest, Oct 10): "I have a wallet... I guess an emerald would be a dollar."

## The rate
- **1 emerald = $1.** The general store is the exchange. It **buys** emeralds at **$1.00** and **sells** them at
  **$1.20** (`Economy.emeraldSell = 100`, `Economy.emeraldBuy = 120` cents, Wallet.swift). It stocks 12 a day.
- The exchange ignores reputation and the town's mood, so the rate stays put. Hostile towns still refuse to serve you
  (see below).
- The 20c spread stops round trips: emerald -> dollars -> emerald loses 20c each time.

## Why barter and shops can't feed each other
Craftsfolk still barter goods for emeralds, so the emerald has two prices. TownTests.barter checks both directions at
the best multipliers:
- **Cheapest emerald made from shop goods: 107c**, which is at least the $1.00 the store pays for one. Buying goods
  to barter for emeralds and then selling the emeralds never makes money.
- **Best value an emerald fetches through an offer, sold back to a shop: 88c**, which is at most the $1.20 the store
  charges. Buying emeralds to barter for goods and then selling the goods never makes money.
- TownTests.economy keeps the existing no-arbitrage check for buying, crafting or smelting and then selling.

## Every craftsperson takes money
Before this, only shopkeepers took dollars. Craftsfolk in old or pre-town villages only bartered, which is why "the
rest of them weren't updated". Now every craftsperson with a trade (`VillagerData.tradeKind`: their shop, or the shop
their profession maps to in `Economy.professionShop`) opens a cash counter. A **Barter** button switches to the old
emerald trades. Nitwits and unemployed folk don't trade.

## Wallet HUD
The wallet is a small gold `$12.40` in the top-right corner (Wallet.swift, shared by Mac and Quest through
HudExtras). It shows while you're in a town and for 6 s after any change, with a fading green or red +/- delta.
It is hidden behind menus, with the HUD hidden, and after death.

## Theft and prices (TownLaw.swift)
- Theft adds **heat** to a town. The town notices only when one of its townsfolk sees it: within 6 blocks, within 20
  with line of sight, or right at the spot.
  - Taking from a town chest or barrel you didn't place: +1.3.
  - Breaking a town block or crop: +1.
  - Hurting a townsperson: +2.
  - Grass, flowers and blocks you placed yourself don't count.
- Each witnessed offence also lowers your standing with every witness (minor negative gossip: 6, or 12 at heat 2 and
  above). Standing feeds `ShopPricing`, so buy prices rise up to x1.25 and sell prices fall, until shops refuse below
  -100.
- **At heat 2** the sheriff or deputy walks over and challenges you.
- **At heat 4** the town turns hostile for 150 s:
  - everyone within 64 blocks takes a major negative gossip hit;
  - armed townsfolk fight;
  - the unarmed run;
  - shops close to you;
  - the sheriff draws his revolver after his challenge.
- Heat cools by 1 every 90 s. When the hostility runs out, heat drops to 1.
- Heat, hostility and the blocks you placed in towns are saved per world (`townLaw` in world.json).
- There is no fine yet. You pay through prices and reputation until gossip decays.
