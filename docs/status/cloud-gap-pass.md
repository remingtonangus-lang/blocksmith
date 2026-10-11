# Cloud gap pass (2026-10-10/11)

Remington's ask (2026-10-10 23:49): grade the cloud threads' merged work (#17 horses, #19 honour/frontier towns,
#20 Tidebreaker polish + village sweep, #22 the Deep expansion; plus the older PRs those briefs build on: #11 towns,
#12 main gun, #13/#15 Boreal Station) line by line against `docs/objectives/towns-horses-honour.md` and
`docs/objectives/deep-expansion.md`, harshly (scale words count), then build every PARTIAL / MISSING item, one PR per
area, and stop when the table is all MET.

Grading rule: **MET** only when the code does what the line says at the scale it says, with an automated check.
**PARTIAL**: something real exists but a stated part, the scale, or the check is missing. **MISSING**: nothing.
The "Fix" column names the PR area that closes the line; the "After" column is filled in as each PR merges.

PR areas: **H** honour, **T** towns, **R** horses, **F** frigate gun, **D1** hell band, **D2** Ash Vault world and army,
**D3** Deep progression and story, **IP** IP check.

## Towns, horses, honour, frigate gun (`docs/objectives/towns-horses-honour.md`)

### Remington's brief
| # | Line | Before | Evidence (code at quest-port 2026-10-10 23:45) | Fix | After |
|---|------|--------|-----------|-----|-------|
| A1a | Horse call/whistle reliable at range, horse pathfinds to you | PARTIAL | Riding.swift callHorse: >64 blocks it is teleported behind you; within 64 it walks straight at you (`face` + speed, no path), so it sticks on walls/rivers | R | MET: a called horse paths round walls (160 blocks, 1500 nodes); stuck 6 s, brought round on your level; HorseGapTests |
| A1b | Bonding levels unlock things: tighter turning, calmer under fire, tricks | PARTIAL | HorseFeel bond 1-4 gives stamina and nerves; no turning bonus, no tricks | R | MET: tighter turns per level, a level-3 rear on command, a level-4 sliding stop and calm under gunfire; HorseGapTests |
| A1c | Brushing / feeding / patting | MET | HorseFeel care, HorseTests | - | MET |
| A1d | The horse remembers you | PARTIAL | one bonded horse id; any other horse forgets you the moment you ride another | R | MET: every horse you have ridden keeps its own bond; the last one ridden comes when called; HorseGapTests |
| A1e | A stable to keep and swap horses | MISSING | stable shop sells tack only; no keeping, storing or swapping horses | R | MET: the stable keeps up to six horses (any town) and swaps them; HorseGapTests |
| A1f | Saddlebags as storage | MET | 9 slots at bond 2 (HorseFeel) | - | MET |
| A1g | Stamina and health with care | MET | HorseFeel stamina, brushing heals | - | MET |
| A1h | Weighty gaits, smooth on slopes | MET | HorseTests gaits / staircase | - | MET |
| A2 | Towns of named people with routines, armed, defend, react | MET | Townsfolk.swift, VillageLife, TownTests (#11) | - | MET |
| A3 | 8 shop types, currency, VR-readable shop UI, prices vs progression | MET | Shops.swift, TownTests no-arbitrage + overflow (#11) | - | MET |
| A4 | Other RDR-feel features, listed with reasons | PARTIAL | bounties/honour (#19), camps exist; no single list of what was added and why | T | MET: docs/status/frontier-feel.md lists what was added and why, and what was left out |
| B | Military base look (Siberia feel) | MET | Boreal Station (#13, #15), BorealTests, golden shots | - | MET |
| C | Main gun: barrel, charge-up (sound, glow, shake, haptics), devastating shot, crater, shockwave, rumble, slow reload, blast frame time on Quest | MET | MainGun.swift, MainGunTests, MainGunPerf line | - | MET |
| D | Rename UNSC / MAC in player-visible text, ip-renames.md | MET | coined-terms.txt has both; namecheck 0 hits | - | MET |
| HON1 | Honour saved per world, shown subtly in HUD | MET | Honour.swift, HonourHUD | - | MET |
| HON2 | Stealing loses honour, more if seen | PARTIAL | only witnessed theft costs anything; unseen theft is free (HonourTests asserts it) | H | MET: unseen theft costs a third (capped 10/day); HonourTests, HonourGapTests |
| HON3 | Fair trades, helping, protecting regain it | PARTIAL | protecting yes; fair trades and helping give nothing | H | MET: fair trades +0.5 (3/day), jobs, donations; HonourGapTests |
| HON4 | Low honour: villages hostile automatically; villagers flee or warn, sheriff and armed attack on sight | PARTIAL | an outlaw is only *challenged*; townsfolk turn hostile only on reputation < -100 or a crime | H | MET: outlaws fought on sight after a 3 s warning, unarmed run, refused service; disreputable warned; HonourGapTests |
| HON5 | Sheriff ~5% gun chance (5% of sheriffs *carry* a gun) | PARTIAL | Honour.sheriffDrops, 5.1% over 20,000 rolls. but the brief says 5% of sheriffs carry it; #19 made it a 5% drop and the sheriff never shoots it | H | MET: ~5% of sheriffs carry (and shoot) the revolver, the rest a sword; TownLawTests, HonourTests |
| HON6 | Village errors in Quest build: walk villages, fix, list | MET | #20 structcheck sweep, frigate-polish-village-sweep.md | - | MET |

### Expanded objectives
| # | Line | Before | Evidence | Fix | After |
|---|------|--------|----------|-----|-------|
| EH1 | Meter pulses with a sound when honour changes and shows the reason | PARTIAL | HUD shows the delta; toast with reason (throttled 8 s); no pulse, no sound | H | MET: meter pulse + chime, reason line, log; HonourGapTests |
| EH2 | 5 tiers with real consequences: prices, greetings | MET | standing(), ShopPricing nudge | - | MET |
| EH3 | Tips and gifts at high honour | MISSING | none | H | MET: tips (respected), one gift a town a day (honourable); HonourGapTests |
| EH4 | Refused service at very low honour | PARTIAL | refused only while a bounty is out in that town | H | MET: outlaws refused service everywhere; HonourGapTests |
| EH5 | Posters at very low honour | PARTIAL | the WANTED board is a static block in the sheriff's office; nothing shows the player | H | MET: town WANTED boards show your poster (bounty + fine); HonourGapTests |
| EH6 | Bounty hunters at very low honour | MISSING | none | H | MET: bounty hunters out of town, once a day, leave when you pay; HonourGapTests |
| EH7 | Redemption path: jobs, donations, protecting towns | PARTIAL | protecting yes; no jobs, no donations | H/T | MET: notice-board jobs, donations, protecting towns; HonourGapTests |
| EH8 | Per-world save with migration | MET | optional fields in TownLaw.Saved | - | MET |
| EH9 | Honour actions logged so tests can prove each rule | MISSING | no log | H | MET: every change logged (day, amount, reason), saved; HonourGapTests |
| ER1 | Name your horse (VR-friendly) | MISSING | none | R | MET: named when it becomes yours; rename at the stable from a list (no typing); HorseGapTests |
| ER2 | Breeds with different speed, stamina, courage, looks | MISSING | random speed per horse only | R | MET: five breeds with their own speed, stamina, courage, jump and coats; HorseGapTests |
| ER3 | Taming wild horses with a calm-down minigame | MISSING | random temper roll while bucking | R | MET: the calm-down minigame (sit still through bucks, pat as it settles); HorseGapTests |
| ER4 | Fears predators and gunfire until bonded | PARTIAL | spooks at gunfire/explosions; predators only when "a hostile monster" is adjacent; no wolves etc. | R | MET: predators and monsters within 6 blocks frighten it below level 3, gunfire below level 4; HorseGapTests |
| ER5 | Horse armour | MET | vanilla armour slot, stable sells it | - | MET |
| ER6 | Injured horse revivable with a reviver item; death permanent only if left | MISSING | horses die outright | R | MET: down for 5 minutes, a Horse Reviver saves it, left too long it dies; HorseGapTests |
| ER7 | Stable UI: buy, sell, store, swap | MISSING | stable shop has tack only | R | MET: the stablehand's Horses menu: buy, stable, take out, sell, rename; HorseGapTests |
| ER8 | Saddlebags reachable in VR by reaching to the horse's side | MISSING | menu only | R | MET: grip with a hand at the horse's flank behind the saddle opens the bags (QuestControls); HorseGapTests |
| ER9 | VR comfort while riding: vignette, smooth vs snap turn, horizon-locked option | PARTIAL | vignette + turn modes exist globally; no horizon lock; vignette not driven by the horse | R | MET: horse-driven vignette (turns, speed changes) and Steady Saddle on the VR comfort page; HorseGapTests |
| ER10 | Hooves sound per surface | MISSING | generic step sound | R | MET: six hoof sounds by the ground underfoot, rhythm by gait; HorseGapTests |
| ER11 | Horse waits, grazes and wanders a little when left | PARTIAL | bonded horse follows within 10 blocks; no "stay", no grazing | R | MET: left alone it waits, grazes and wanders a few blocks; HorseGapTests |
| ET1 | Every town has a name on a sign and on the map | PARTIAL | name in greetings; no sign at the edge, not on the map | T | MET: "Welcome to <name>" sign at each main-street end; named on the map when found; TownGapTests |
| ET2 | Notice board with bounties and jobs | MISSING | none | T | MET: TownBoard (deliveries, monster hunts, outlaws with a spawned boss); HonourGapTests |
| ET3 | Doctor heals and sells tonics | MET | Shops .doctor treatment + potions | - | MET |
| ET4 | Bank for the emerald exchange | PARTIAL | the general store buys/sells emeralds; no bank | T | MET: a bank in every frontier town (banker, counter, strongroom): emerald exchange + savings with interest; TownGapTests |
| ET5 | Gunsmith upgrades | MISSING | gunsmith sells/buys only | T | MET: gunsmith "Upgrade": magazine, reload, stability, penetration, incendiary, priced per level; TownGapTests |
| ET6 | Saloon with one simple game (cards or dice) | MISSING | none | T | MET: saloon "Dice": high dice for $1/$5/$10, house wins ties (44%); TownGapTests |
| ET7 | Street lamps at night | PARTIAL | old village lamp posts only along some roads; no lamps on frontier streets that light at night | T | MET: lamp posts every 8 blocks on frontier streets, lit at night; TownGapTests |
| ET8 | Town defence events (raids at night), townsfolk fight beside you | PARTIAL | omen raids exist (player-triggered); no night raid events; townsfolk defend vs monsters | T | MET: night raids (2 waves, at most every 3 days) with armed townsfolk fighting; purse + honour on a win; TownGapTests |
| ET9 | People remember you (greet by name at high honour) | PARTIAL | they say *their* name; never yours | T | MET: respected and honourable are greeted by the name you pick on the board; HonourGapTests |
| ET10 | Shopkeepers restock over days | MET | restockShop(day:) | - | MET |
| ET11 | At least 3 town layouts per biome style | MISSING | one radial-plaza generator | T | MET: three street plans (crossroads, main street, grid) chosen per town in every style; TownGapTests |
| EF1 | Gunner seat/console: aiming reticle, charge meter, cooldown display | MET | helm aim ring + mainGunStatus gauge (CombatHUD) | - | MET |
| EF2 | Targets worth hitting: enemy ships, the Capital, military bases | PARTIAL | ships yes; bases/Capital take the crater but nothing reacts (no garrison loss, no objective) | F | |
| EF3 | Damage interacts with structures sensibly | MET | crater carving, hull hit tears plate | - | MET |
| EF4 | Camera-shake comfort toggle for VR | PARTIAL | tied to Screen Effects (a general toggle); no own option on the VR comfort page | F | |
| EF5 | The shot recorded as a video-like screenshot sequence | PARTIAL | single stills only | F | |
| EB | Military base look (snow, blue lights, corridors, doors with sounds, red alarms, rooms, loot) | MET | Boreal Station, BorealTests | - | MET |
| EIP | Grep-based test fails on UNSC / MAC / flagged names; ip-renames complete | PARTIAL | tools/namecheck.py exists but runs only in the Mac snap shard, not in the Quest checks threads run | IP | MET: namecheck --coined runs in quest/tools/linux-check.sh (every Quest check) |
| EV | Village bugs written with seed + coords, regression test | MET | #20 doc + structcheck baseline | - | MET |

## The Deep (`docs/objectives/deep-expansion.md`)

### Remington's brief
| # | Line | Before | Evidence | Fix | After |
|---|------|--------|----------|-----|-------|
| D1 | Hell as big as the Nether: **much taller** open space, sky/ceiling far overhead, varied biomes, lava seas, fortresses | PARTIAL | band still 128 tall (the brief names "only 128" as the problem); biomes, lava sea, fortresses, bastions yes | D1 | |
| D2a | Hard barrier normal tools can't break | MET | Sealrock, DeepExpansionTests | - | MET |
| D2b | Rare ore in guarded bastion strongholds **next to a portal-replacement structure** | PARTIAL | Brimstone Keeps hold Sunderite; no portal-like structure beside them | D3 | |
| D2c | Ore processed (smelt + craft) into a tool or charge | MET | flux -> blast furnace ingot -> pick / charge | - | MET |
| D3a | Ash Vault huge with its own sky | MET | 133-145 tall, haze + Cinder Sun | - | MET |
| D3b | Towns, bunkers, rail lines, airfields | PARTIAL | HQ bunker, outposts and camps; no towns, no rail, no airfield | D2 | |
| D3c | Tanks, halftracks, rifles, MGs, mortars, artillery, officers, patrols, alarms, reinforcements | PARTIAL | no mortars, no foot patrols moving between sites, no vault-wide alarm; reinforcements only the Marshal's guard | D2 | |
| D4a | Harder than surface bases (more units, armour needing explosives, squads, flanking, cover) | MET | army metric 8695 vs 4127; Soldier AI cover/flank/retreat | - | MET |
| D4b | Full-gear test run with time-to-kill numbers documented | MISSING | none | D3 | |
| D5 | 72 fps on Quest 3 (LOD, unit caps, fog); test Mac and Quest | PARTIAL | no unit cap or measurement in the biggest battle | D2 | |

### Expanded objectives
| # | Line | Before | Evidence | Fix | After |
|---|------|--------|----------|-----|-------|
| DE1 | Progression curve written down; enemies and loot tuned to it | MISSING | none | D3 | |
| DE2 | Each layer's own ambient sound, music and lighting mood | PARTIAL | hell vs crust ambience differ; the vault has no own bed or music | D3 | |
| DE3 | Compass/map works underground; markers for the way back up | PARTIAL | compass points to keeps/citadel; no way-back marker | D3 | |
| DE4 | Ways back: lifts/shafts to build or unlock; beds/respawn rules documented | PARTIAL | lift only after the Marshal falls; respawn rules undocumented | D3 | |
| DE5 | Barrier ore chain in the recipe book with hints (journal or hell NPC) | PARTIAL | recipes exist; no hint journal/NPC | D3 | |
| DE6 | Barrier break is a big moment (sound, light, falling debris) | PARTIAL | a charge opens the shaft with an explosion; no special moment | D3 | |
| DE7 | Bastion strongholds: 3+ layouts, guard roles, mini-boss, loot vaults | PARTIAL | one keep layout, no mini-boss | D3 | |
| DE8 | Ash Vault story: journals, signs, radio chatter; rising alarm level | MISSING | none | D2 | |
| DE9 | Vehicles destructible with debris and fire, crew bail out | PARTIAL | brew-up blast + smoke; no crew | D2 | |
| DE10 | Mortars and artillery with audible incoming warnings | PARTIAL | the Marshal's barrage has a flare; batteries' shells have no warning | D2 | |
| DE11 | Squads with roles (rifle, MG, officer, medic), cover, flanking, retreat, calling armour; difficulty scales it | PARTIAL | no medic, no armour call | D2 | |
| DE12 | Ash Marshal: phases, arena, victory changes the Vault for good | MET | guard calls at 2/3 and 1/3, barrages, bunker; army stands down, lift | - | MET |
| DE13 | Rewards unique to each layer; advancements for each milestone | PARTIAL | advancements for vault/tank/victory/sunderite; no hell-band or seal milestone, no layer trophies | D3 | |
| DE14 | Perf: unit caps, LOD, fog budgets measured in the biggest battle | MISSING | none | D2 | |
