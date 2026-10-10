# Economy: emeralds and dollars (2026-10-10)

Remington (Quest playtest, Oct 10): "I have a wallet... I guess an emerald would be a dollar."

## The rate
- **1 emerald = $1.** The general store is the exchange. It **buys** emeralds at **$1.00** and **sells** them at
  **$1.20** (`Economy.emeraldSell = 100`, `Economy.emeraldBuy = 120` cents, Wallet.swift). It stocks 12 a day.
- The exchange ignores reputation and the town's mood, so the rate stays put. Hostile towns still refuse to serve you
  (see below).
- The 20c spread stops round trips: emerald -> dollars -> emerald loses 20c each time.

## Why barter and shops can't feed each other
Craftsfolk still barter goods for emeralds, so the emerald has two prices.

**List prices.** TownTests.barter checks both directions at the best shop multipliers:
- **Cheapest emerald made from shop goods: 107c** (9 glass bottles). That is at least the $1.00 the store pays for an
  emerald, so buying goods to barter for emeralds and then selling the emeralds never makes money.
- **Best an emerald fetches through an offer, sold back to a shop: 88c** (3 golden carrots). That is at most the
  $1.20 the store charges, so buying emeralds to barter for goods and then selling the goods never makes money.

**Discounts.** A good reputation, a cure and Friend of the Town take emeralds or goods off barter prices, as in the
reference game. Unchecked, those discounts opened money loops (the 2026-10-10 verifier found bottles -> emerald -> $
and emerald -> golden carrots -> stable). Now every discounted price is held at `Economy.barterFloor` (Wallet.swift),
which applies to offers whose payment can be bought with money and whose goods can be sold for money (an emerald
counts, through the exchange):
- The payment, valued at the cheapest way to buy it (`Economy.cashIn`: the best shop price, an emerald at $1.00, or
  a barter for it at the deepest discount), must be worth at least what the goods sell for (`Economy.cashOut`: the
  best shop price, or $1.00 for an emerald).
- When the list price already sits under that floor, the discount simply doesn't apply to that offer.

Every other offer keeps its discount: 168 of 283 offers get cheaper at maximum standing with Friend of the Town V.
TownLawTests ("economy: no money loop at the deepest discounts") prices every offer through the real trade screen for a
cured villager with maximum gossip and Friend of the Town V. Results:
- an emerald from shop goods costs at least 100c;
- an emerald turned back into money fetches at most 88c;
- emerald -> goods -> emerald at another counter returns at most x1.00.

TownTests.economy still runs the no-arbitrage check for buying, crafting or smelting and then selling.

## Every craftsperson takes money
Before this, only shopkeepers took dollars. Craftsfolk in old or pre-town villages only bartered, which is why "the
rest of them weren't updated". Now every craftsperson with a trade opens a cash counter. Their trade is
`VillagerData.tradeKind`: their own shop, or the shop their profession maps to in `Economy.professionShop`. A
**Barter** button switches to the old emerald trades. Nitwits and unemployed folk don't trade.

## Wallet HUD
The wallet is a small gold `$12.40` in the top-right corner (Wallet.swift, shared by Mac and Quest through
HudExtras). It shows while you're in a town and for 6 s after any change, with a fading green or red +/- delta.
It is hidden behind menus, with the HUD hidden, and after death.

## Theft and prices (TownLaw.swift)
- Theft adds **heat** to a town. It only counts in survival, and only when a townsperson sees it: awake, within 20
  blocks, with a clear line of sight from their eyes to yours (walls hide you, windows don't).
- Only what the town owns counts: blocks inside the village's generated pieces (houses and their lots, farms, the
  square, roads), down to 4 blocks under a lot's floor. Your own build next to a town doesn't count, and neither does
  a dungeon or mineshaft chest under it. Blocks you place in a town are remembered as yours; past 4096 the oldest are
  forgotten first.
- Offences and their heat:
  - Taking from a town chest or barrel: 1 to 3 heat, by how much you take. What you put in that chest yourself is
    tracked per item, so taking it back is free.
  - Breaking a town container: as much as taking what's inside it, at least 1.
  - Breaking a town block or crop: 1.
  - Hurting a townsperson: 2.
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
- Saved per world (`townLaw` in world.json): heat, hostility, your placed blocks, your chest deposits, and each
  town's one sheriff. A second sheriff in the same town serves as a deputy; that covers a cured zombie sheriff, or
  the square's own sheriff loading after a replacement was sent.
- There is no fine yet. You pay through prices and reputation until gossip decays.
