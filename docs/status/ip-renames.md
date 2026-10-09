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
- **Deep Stride** (was Depth Strider) and **Village Hero** (was Hero of the Village): earlier renames that stay close to the originals.
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
