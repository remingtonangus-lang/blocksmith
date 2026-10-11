# Frontier feel: what was added and why (brief item A4)

Remington's brief (Oct 9, A4): "Other RDR2-feel features worth it in this game: your call, but list what you added and
why. Don't bloat it. Pick the few that make the world feel alive." Feel and mechanics only; no borrowed names,
characters, art, music or layouts (docs/status/ip-renames.md, `tools/namecheck.py --coined` runs in the Quest checks).

## Added (each one earns its place by giving the player something to do in or between towns)

| Feature | Where | Why it's worth it |
|---|---|---|
| Honour (5 tiers, a log, a HUD and inventory meter) | Honour.swift, docs/status/honour.md | Choices in town carry weight: theft, murder and fair dealing change how every town treats you. |
| Bounties and a wanted level per town; the sheriff and deputies | Honour.swift, TownLaw.swift | Crime has a cost you can pay off; the law is a person you can surrender to, not a rule. |
| Bounty hunters | BountyHunters.swift | Being wanted follows you out of town, so the wilds aren't a free escape. Rare, capped once a day. |
| The notice board: deliveries, monster hunts, outlaws to bring in | TownBoard.swift | A reason to come back to a town and a redemption path (pay, honour) that isn't grinding trades. |
| Wild camps (hunters, prospectors, traders, abandoned, outlaws) | WildCamps.swift | Open country has small finds between towns: loot, a fight, a story told by a few blocks. |
| Horses with bonding, calling and care | docs/status/horses.md | The companion that makes travel between towns part of the game. |
| Night raids on towns | TownRaids.swift | Towns are worth protecting: the townsfolk fight beside you and the town pays and remembers. Every three days at most. |
| The bank (exchange and savings) | TownServices.swift, FrontierTown.bankLot | Money has a safe home (savings shared by every town's bank, paying a little interest) and the emerald exchange lives somewhere that makes sense. |
| Gunsmith upgrades | TownServices.swift | Money buys a better gun (magazine, reload, steadiness, penetration, fire) without the enchanting table. |
| High dice at the saloon | TownServices.swift | One simple game of chance in the saloon: a few dollars at a time, the house's edge built in (44% to win). |
| Town names on signs and the map; three street plans | Village.swift, WorldMap.swift | Towns read as places with names, and no two look laid out alike. |
| Street lamps on frontier streets | Village.swift | Towns glow at night from a distance: somewhere to ride toward. |

## Considered and left out (bloat, or already covered)
- Pelt quality on hunted animals: drops already vary; a quality tier would add inventory clutter for little play.
- Fishing minigame: fishing already exists; a new minigame isn't what makes the world feel alive.
- Card games (poker): too long a UI for VR at arm's length; dice play in two presses.
- Dynamic world events beyond raids, hunters and camps: these three already put something on the road between towns.
