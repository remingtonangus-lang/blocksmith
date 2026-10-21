# IP renames: coined reference-game terms in player-facing text (2026-10-09 PM, task 10)

Not legal advice. This is a best-effort scrub so that nothing the player reads uses a word the reference game coined.
Internal keys (`silk_touch`, `riptide`, `torchflower`, MobKind keys, Dim raw values...) are save IDs and never change; only
display text changed. Earlier sessions had already renamed the big ones (Emberdeep, the Hollow, Hisser, Voidwalker, Blight,
Murk, Sparkstone, Duskium, Titanium, Rustcap/Tealcap, Totem of Rebirth, Deep Stride, Ghost Stride, Ill Omen, Village Hero...);
the selftest naming audit (`--selftest`) and this check keep them out.

## How it is checked
- `python3 tools/namecheck.py --coined` scans every string literal in `Sources/` and `quest/src/` against
  `tools/coined-terms.txt` (internal keys, test/harness files and lines marked `namecheck:ok` are exempt); exit 1 on a hit.
  Runs in `./snap.sh` (the CI heavy checks shard) next to `--coppertest`, no build needed. (A mac.yml fast-lane step would be better; the agent token cannot push workflow files, so Remington can add `python3 tools/namecheck.py --coined` as a first step there.)
- `Blocksmith --snapshot /tmp/n.png --rd 2 --questbugs --only pm9d --namedump /tmp/names.txt` checks every registered
  display name at runtime (blocks, items, mobs, biomes, dimensions, advancements + tabs, enchantments, effects, music, credits:
  ~2,080 strings) against the same list and writes them to the dump; `python3 tools/namecheck.py --coined --dump /tmp/names.txt`
  re-checks the dump. `--docs` also lists (without failing) hits in README / store docs.
- To ban a new word: add it to `tools/coined-terms.txt` (`*Word` = any case, word-start; `Word` = that exact word).

## Renames in this pass (display text only)
| Where | Internal key | Old display | New display |
|---|---|---|---|
| Enchantment | `silk_touch` | Silk Touch | Gentle Touch |
| Enchantment | `bane_of_arthropods` | Bane of Arthropods | Bugbane |
| Enchantment | `frost_walker` | Frost Walker | Rimewalker |
| Enchantment | `swift_sneak` | Swift Sneak | Quiet Step |
| Enchantment | `aqua_affinity` | Aqua Affinity | Tidehand |
| Enchantment | `feather_falling` | Feather Falling | Soft Landing |
| Enchantment | `fire_aspect` | Fire Aspect | Searing Edge |
| Enchantment | `sweeping_edge` | Sweeping Edge | Wide Arc |
| Enchantment | `luck_of_the_sea` | Luck of the Sea | Angler's Luck |
| Enchantment | `riptide` | Riptide | Surge |
| Enchantment | `multishot` | Multishot | Spread Shot |
| Subtitle | `Snd.riptide` | Riptide | Trident surges |
| Effect | `conduitPower` | Conduit Power | Tide Blessing |
| Effect | `dolphinsGrace` | Dolphin's Grace | Swimmer's Grace |
| Potion | `mundane` | Mundane Potion | Plain Potion |
| Potion | `thick` | Thick Potion | Cloudy Potion |
| Potion | `awkward` | Awkward Potion | Base Potion |
| Item | `glistering_melon_slice` | Glistering Melon Slice | Gilded Melon Slice |
| Block | `big_dripleaf` / `big_dripleaf_stem` / `small_dripleaf` | Big / Small Dripleaf (+ Stem) | Big / Small Pondleaf (+ Stem) |
| Block / item | `torchflower`, `torchflower_crop`, `torchflower_seeds` | Torchflower (+ Crop, Seeds) | Flarebloom (+ Crop, Seeds) |
| Music track | `MusicMood.day` / `.night` | Overworld Day / Night | Surface Day / Night |
| Toast | Shortcuts.swift | "Shortcuts work in the overworld" | "Shortcuts work on the Surface" |
| Advancement desc | `root` | The heart and story of the game (verbatim reference tagline) | Every world starts at a workbench |

28 display strings in 23 rename rows.

## Kept as ordinary English (decided, not renamed)
Efficiency, Fortune, Unbreaking, Sharpness, Smite, Knockback, Looting, Protection (+ Fire / Blast / Projectile), Thorns,
Respiration, Power, Punch, Flame, Infinity, Lure, Loyalty, Impaling, Channeling, Piercing, Quick Charge, Density, Breach,
Lunge; effects Haste, Mining Fatigue, Slow Falling, Levitation, Glowing, Darkness, Wind Charged, Weaving, Oozing, Infested;
Beacon, Conduit (block), Lodestone, Spyglass, Trident, Mace, Bundle, Crafter, Vault, Smithing Table, Grindstone, Axolotl,
Armadillo, Nautilus Shell, Turtle Scute, Mycelium, Calcite, Tuff, Amethyst, Basalt, Witch, Silverfish, Wandering Trader,
Recovery Compass, Disc Fragment, Pottery Sherd names (Angler, Archer, Heart, Howl...), armor trim names (Coast, Dune, Wild,
Ward, Tide, Wayfinder, Shaper, Raiser, Host, Silence, Snout, Rib, Spire, Flow, Bolt...), Jack o'Lantern, TNT.

## Flag for Remington (unsure; left as they are)
- **Mending**: ordinary word, but the enchantment is very strongly associated with the reference game.
- **Curse of Binding / Curse of Vanishing**: generic fantasy phrasing, but the exact pair is the reference game's.
- **Wind Burst**: generic, but a recent reference-game enchantment name.
- **Deep Stride** (was Depth Strider): an earlier rename that stays close to the original. (Village Hero is now Friend of the Town, below.)
- **Magmastrider**: an earlier rename of the Strider mob; still contains "strider".
- **Iron Golem / Snow Golem**: golems are folklore, but these exact names are the reference game's mobs.
- **Minecart**: one-word spelling popularised by the reference game ("mine cart" is the plain term).
- **Twisting Vines / Weeping Vines**: ordinary words, but the pairing is the reference game's.
- **Guster** (pottery sherd): derived from a reference mob name.
- **Basalt Deltas** (biome): descriptive geology, but the reference biome name.
- **Advancement descriptions** still follow the reference wording closely in places (e.g. "Use a Totem of Rebirth to cheat
  death", "Mine stone with your new pickaxe"); titles are original. A rewrite pass of the ~120 descriptions is cheap if wanted.
- **Item / block names copied as plain descriptions** (Fermented Spider Eye, Rabbit's Foot, Glow Lichen, Spore Blossom,
  Budding Amethyst, Suspicious Sand): kept as descriptive.

## Docs (listed, not rewritten)
`python3 tools/namecheck.py --coined --docs`: README.md is absent; docs/STORE_QUALITY.md:109 mentions "the creeper" in an
internal feedback note; docs/status/store-readiness.md has no hits. STATUS.md and docs/status/quest-port.md use reference
names (nether, shulker, creeper...) as internal shorthand in history notes; they are not player-facing store copy. The PR #9
"what's new" list lives on GitHub, not in the repo; check it before any store submission.

## Towns of people (2026-10-09, branch claude/towns-of-people-j6qgts)
Internal keys unchanged, so old saves load.

| Was (player-visible) | Now | Where | Internal key (unchanged) | Session |
|---|---|---|---|---|
| Villager (mob name, captions) | Townsperson / Townsfolk; each one also has their own name ("Ada Vance") | Mob.swift spec, AudioSubtitles.swift, HudExtras.swift | `villager` | towns of people, 2026-10-09 |
| Zombie Villager | Zombie Townsperson | Mob.swift spec, AudioSubtitles.swift ("Zombie townsperson snuffles") | `zombie_villager` | towns of people |
| "Successfully trade with a Villager" | "Successfully trade with a Townsperson" | Advancements.swift | `adventure/trade` | towns of people |
| "Weaken and then cure a Zombie Villager" | "... a Zombie Townsperson" | Advancements.swift | `cure_zombie_villager` | towns of people |
| Village Hero (effect) | Friend of the Town | Effects.swift | `heroOfTheVillage` | towns of people |

Names chosen for new content (checked against RDR2's cast, gangs and towns: no matches): townsfolk first names and
surnames are common 19th-century American names (Townsfolk.swift); town names are generated from original parts
("Dry Springs", "Juniper Crossing"); shop names are generic trades (General Store, Gunsmith, Butcher, Doctor, Stable,
Tailor, Blacksmith, Saloon). Currency is plain dollars and cents.

## Halo terms (2026-10-09, task 3: frigate main gun)
Standing rule (Remington): borrow the feel of Red Dead Redemption 2, GoldenEye and Halo, never their names. Display text only.
| Where | Internal key | Old display | New display |
|---|---|---|---|
| Frigate spinal gun: helm HUD gauge (CombatHUD), ship status line (ShipPlay), subtitles | `mainGun*`, `Snd.mainGun*` | MAC | Tidebreaker ("Main gun charging / fires" in subtitles) |
| Mac gamepad layout preset: Pause > Controls row, help text, toast (PadMap, PauseMenu) | `padLayout = "halo"`, `PadMap.halo` | Halo | Shooter |
| Injured-horse cure: item name, shop rows, toasts (HorseLife, Items, Shops, Riding; the gap pass) | `saddle_salve` | Horse Reviver (a western game's item) | Saddle Salve |
| Brimstone Keep mini-boss: boss bar, name tag, toast, trophy item, advancement, Keeper's Journal (DeepGates, DeepWayUp, Advancements) | `warden`, `makeKeepWarden`, `warden_brand`, `adventure/keep_warden` | Keep Warden, Warden's Brand, Wardenbreaker (never shipped) | Keep Castellan, Castellan's Brand, Castellan's Fall |
| (none found) | | UNSC | (grep of Sources/, quest/, docs/ on 2026-10-09: no occurrence) |

## The exploding mob replaced (2026-10-11, L1 part 2, Lane C)
The Hisser was the genre's green four-legged exploder under a new name (and its banner charge and firework shape were the
genre's face). It is now the Powderwight, Blocksmith's own mob in that role: a hunched dead miner with a powder keg
slung on its back (look, telegraph and counterplay in docs/status/look-upgrade.md part 2). Internal keys unchanged.
| Was (player-visible) | Now | Where | Internal key (unchanged) |
|---|---|---|---|
| Hisser (mob name, death message) | Powderwight | Mob.swift spec, main.swift | `creeper` |
| "Hisser hisses" (captions) | "Powderwight fuse sizzles" | AudioSubtitles.swift, HudExtras.swift | `creeperHiss` |
| Hisser Head (green, slit eyes, zigzag mouth) | Powderwight Head (cap brim, amber eyes) | BlocksMagic.swift | `creeper_head`, `head_creeper` |
| Hisser Charge (banner; the genre's face picture) | Powder Keg Charge (a keg with a lit fuse) | Banners.swift | `creeper`, `creeper_banner_pattern` |
| Hisser-shaped firework (the genre's face) | Keg-shaped | Fireworks.swift | shape 3 |
| Green spawn egg | Brown spawn egg | SpawnEggs.swift | `creeper` |

## The last war's real names kept out (2026-10-11, B7, Lane B)
The Ashguard is styled on a period army, but every name is invented (Kessel, Hagel, Sturmwind, Ashsaw, Behemoth, the Ash
Chancellor) and the emblem is fictional (a diamond split by a bar on a white disc; LastWarTests checks it is
mirror-symmetric). The period's real names (parties, units, people, arms, vehicles) were added to tools/coined-terms.txt
so the namecheck in every build keeps them out of anything the player reads.

## The last war's arms by their real names (2026-10-16, P326)
Remington (Oct 15 19:04) asked for the Ash Vault's German bases "with their real WWII weapons by name (MP40 and the
rest)". The Ashguard's guns and vehicles now carry their period designations (keys unchanged): gun_kessel Kessel Bolt
Rifle -> Kar98k, gun_sturmwind Sturmwind Carbine -> StG 44, gun_faust Faustrohr -> Panzerfaust (faust_warhead ->
Panzerfaust Warhead), gun_hagel (retired by P217) back as the MP40, ash_tank Cinder Tank -> Tiger Tank, ash_artillery
-> 88 mm Gun, ash_halftrack -> Half-track, ash_truck -> Army Truck. tools/coined-terms.txt drops those words from its
ban; parties, units, people, makers (Mauser, Luger, Messerschmitt) and emblems stay banned, and the Ashguard keeps its
own ember mark.

## Oct 11 evening (P42): potions are frontier tonics
Every "Potion of X" is now "X Tonic" with an original name (keys and effects unchanged): Night Vision -> Owl-Eye,
Invisibility -> Ghostwalk, Leaping -> Jackrabbit, Fire Resistance -> Emberward, Swiftness -> Quickstep, Slowness ->
Molasses, the Tortoise -> Ironhide, Water Breathing -> Gillwater, Healing -> Mending, Harming -> Black Draught, Poison ->
Snakebite, Regeneration -> Second Wind, Strength -> Bull's Blood, Weakness -> Sapping, Slow Falling -> Featherfall,
Luck -> Lucky Penny, Wind Charging -> Gale, Weaving -> Spinner's, Oozing -> Ooze, Infestation -> Swarm.
Splash and lingering forms read "Splash Quickstep Tonic"; tipped arrows "Quickstep Arrow".

## Oct 12 (G20): structures that copied a reference feature whole now have original designs
Proving Halls -> Sealed Armoury (advancement "Proving Run" -> "Under Lock"), Forest Manor -> Brigand Roost (its explorer
map too), Sea Temple -> Sunken Dreadnought (its explorer map: Dreadnought Explorer Map), Cinder Fortress -> Ash Foundry,
Boarling Keep -> Boarling Mound. The Hollow is out of new worlds (strongholds there hold a reliquary). Designs and the
old-save rule: docs/status/ip-content-audit-oct11.md.

## Oct 13 (P125): Glow Berries -> Lumen Pods, Cave Vines -> Lanternvine (teal pods, picked by hand, regrow)

## Oct 14 (P246): spiders are the Gravesworn; Iron Golem -> Iron Sentinel
The spider and cave spider (keys "spider", "cave_spider") are now the Gravesworn Duellist and Gravesworn Squire: dead
men-at-arms in tarnished plate who fight as sword duellists. The village guardian (key "iron_golem") is the Iron
Sentinel, with a riveted ironclad model.

## Oct 18 (P360): store readiness
- Music disc titles (keys unchanged; the old titles echoed the reference names): 13 Hollow Echo -> Dry Creek, cat Paw
  Prints -> Saddle Song, blocks Building Blocks -> Raising the Barn, chirp Morning Chirp -> Tin Star, far Far Hills ->
  Coyote Ridge, mall Market Day -> Boardwalk, mellohi Slow Glow -> Mesa Dusk, stal Stalwart -> Iron Horse, strad
  Strings -> Fiddler's Rest, ward Warding -> Long Watch, 11 Broken Record -> Cracked Shellac, wait Patience ->
  Stagecoach, pigstep Ember March -> Foundry Stomp, otherside Other Shore -> Across the River, 5 Deep Signal ->
  Telegraph, relic Relic -> Prospector's Find, creator Maker -> Smith's Hymn, precipice Cliffside -> Switchback, tears
  Wailer's Lament -> Grey Rain, lava_chicken Hot Coop -> Prairie Fire. Disc lengths are our own, not the reference's.
- The Ashguard's ember mark: was a black diamond split by a bar on a white disc, on red banners and a red armband (the
  layout of a real party flag). Now an ember-orange chevron over a bar on field-grey cloth; the armband is field grey
  with an orange patch; vehicles carry an orange plate with the bar.
- The desert temple (key desert_pyramid): the twin-towered pyramid with the blue-and-orange floor and the shaft over a
  trapped chest room is replaced, in new ground, by the Dust Mission (DustMission.swift).
- The hunger row of drumsticks and the green experience bar with its number are replaced by a slim segmented hunger bar
  and a thin pale-gold experience line with level marks.
- tools/coined-terms.txt also bans Pigstep, Mellohi, Lava Chicken, Pelican Dropship, Warthog Jeep, Mjolnir, Cortana and
  Master Chief; the runtime name dump checks the disc titles.
- P391: the Hannibal trooper's six-barrel rotary gun borrows the feel of the minigun in the open-world crime games (spin-up
  whine, a roar of fire, a slow walk while it's held); it is the Mahlwerk Rotary Gun, an original Capital design with
  its own name, look and synthesized sounds.
