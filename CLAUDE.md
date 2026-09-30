# Blocksmith — agent guide (CLAUDE.md)

Native macOS voxel sandbox game (a feature-parity block-building survival game: mechanics and numbers follow the classic genre reference; every name, text, texture and sound is Blocksmith's own) for Remington's M1 MacBook (8 GB RAM, macOS 26, Command Line Tools only — NO full Xcode, no .xcodeproj, no .metal files compiled offline).

The repo is PUBLIC. Naming rule (Remington, 2026-10): user-facing names of blocks, items, mobs, structures, biomes and dimensions are original Blocksmith names (Emberdeep, the Hollow, Hisser, Voidwalker, Blight, Murk, Sparkstone...). Internal keys (`"creeper"`, `"nether_bricks"`, MobKind.keys, Dim raw values) are save IDs and never change. Never add another game's text, textures, sounds or logos.

Goals: polished, efficient on M1/8 GB, extensible. Later: Xbox controller on a TV (GameController framework) — design input with that in mind from day one.

## Hard rules
- Swift 5 mode, AppKit + MetalKit + Metal + GameController + simd (+ AVFoundation/AVAudioEngine for synthesized sound) only. No third-party packages.
- Shaders live in a Swift string (Shaders.swift) and compile at runtime with `device.makeLibrary(source:options:)`.
- Build ONLY with `./build.sh` (outputs build/Blocksmith.app). Keep it warning-free if practical.
- CI: `.github/workflows/mac.yml` (macos-14 arm64, Xcode 16 / Swift 6.0.3) runs build.sh + snap.sh on every push and force-pushes PNGs, WAVs and logs to the orphan branch `ci-snaps` (README there embeds them). When working without a Mac, push and read `ci-snaps` (git fetch origin ci-snaps) as the compile/test loop.
- NEVER launch the GUI app, `open` anything, or bring windows to the front — the user is using the Mac. Test with the headless harness: `./snap.sh` (default views into snaps/) or `./snap.sh name --seed N --x N --z N --yaw DEG --pitch DEG --time FRAC --up N --rd N --w PX --h PX --slot N`. It renders one frame offscreen (world + HUD), writes a PNG, prints gen/mesh/frame timings, exits. Extra flags: --find <biome> (jump to the middle of a biome), --torches (torch ring + lamp), --flood (water springs + 60 fluid ticks), --mobs (animals in front of the camera), --inventory <cursor>, --survival <hp> (survival HUD), --sim <seconds> (scripted gameplay through Game.tick; prints tick avg/worst ms). `Blocksmith --sounds <dir>` writes every synthesized sound as a WAV. --time is a day fraction: 0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight. Look at the PNGs you produce (you can view images) to judge correctness.
- Commit to git after every working milestone with a clear message. Keep STATUS.md current (what works, what's broken, next steps).
- Performance budget: 60 fps at render distance 8 on M1; chunk gen+mesh off the main thread; no per-frame allocations in hot paths.

## Existing code (Sources/) — reuse, don't rewrite without reason
- Math/Noise: V2/V3/V4, IVec3, matrices, Frustum, hash3/hashf, floorDiv/mod; seeded Perlin noise2/noise3/fbm2.
- Blocks.swift: `BlockID = UInt16` flattened states registered by name (BlockDef: render cube/cross/liquid/model, layer, tex per face, boxes in 1/16, hardness/tool/tier, tint, fluid level, emit…); flat per-state tables (`Blocks.opaque[id]` etc.); `addFacing` for 4-facing blocks; globals like STONE resolved by name. Texture names → layers via `Tex` registry.
- Items.swift / ItemArt.swift: item registry (block items auto-registered per state group, then materials, food, tools, armor) with sprites painted from 16x16 ASCII masks; Inventory.swift: ItemStack (saved by name), ItemContainer, PlayerInventory.
- Textures.swift: named procedural painters (unknown names show magenta); Font.swift: pixel font glyph layers.
- Chunk.swift: CS=16, CH=384 (YOFF=64 → displayed y = y−64), SEA=126, Section (per-16³ buffers, versions), Chunk (blocks, light, heightmap, tints).
- Mesher.swift: `buildSection(n9, h9, sy)` → 48³ region, light flood, vertex format documented in the file (1/16 positions, uv, 10-bit layer, tint, overlay, smooth light).
- World.swift: streaming/scheduling per section, setBlock (sync remesh around the block, async for light radius), lightAt, box collision (`collides`, `sweep`, `moveBody` with step-up), raycast with selection boxes, fluid sim, blockEntities.
- Loot.swift (mining speed/harvest/drops), Recipes.swift (crafting/smelting/fuel), BlockEntities.swift (chest/furnace), Menu.swift (container screens), Entities.swift (dropped items, EntityWriter), Mob.swift (animals), Sound.swift (synth + AVAudioEngine), Player.swift, Game.swift (tick, interaction, survival, menus), Renderer.swift (sections, entities, HUD, menus), Shaders.swift, App.swift, main.swift (snapshot harness).

- Structures.swift: StructureCache (region grid spacing/separation + fixed starts), StructWriter (per-chunk clipped writes, chests with Loot tables, spawners, structure mobs → World.pendingMobs), Piece/StructureStart. Fortress.swift, Bastion.swift, Stronghold.swift, EndCity.swift build on it; generators expose `structures`.
- End.swift: eyes of ender, hollow gate activation/travel, dragon + crystal AI, acid clouds, sentry bolts, gateways, credits. NetherGen.swift also holds EndGen (island, spikes, fountain, outer islands, spiral).

- Later systems (one file each, mostly `extension Game`): Effects, Potions, Enchant, Villager, Raid, Beacon, Weather, GameCombat (shield/crossbow/trident/fishing), Animals + Riding, Boats, Equipment (mob armour, armor stands), Gadgets (FOV, spyglass, leads), Banners (+ loom), Fireworks (also special crafting: Fireworks.craft), Books (+ lecterns), Bundles, Workblocks (composter, bell), WoodBlocks (pillar axes, stripped wood), Shelf (chiseled bookshelf, decorated pot), Crafter, Physics (wind charge, sponge, powder snow), DragonRespawn, MinecartVariants (+ goat horns), Advancements, Decor (signs/hanging signs/frames/paintings), Maps, Jukebox, BigStructures. Sparkstone.swift holds every sparkstone component kind (incl. tripwire, trapped chest, copper bulb, crafter, murk sensor).
- Swift gotchas seen on CI: long float expressions time out the type checker (split them with typed lets); `import simd` in every file that uses simd_*.

## Roadmap
Done: tree variety, plants, clouds/stars, block light + torches, flowing water, creative inventory, survival basics, synthesized sounds, passive mobs.
Next: item drops/counts/mining time + crafting, food from animals, greedy meshing, first-person hand, controller-driven pause menu for TV play.

## Parallel sessions (2026-09-30)
Six other sessions work on branches cut from claude/eloquent-lovelace-bsc5v1 and open PRs into it: (1) End/Blight
completability tests, (2) performance, (3) visuals, (4) audio/music, (5) mobs/villagers/raids, (6) controller/TV/UI.
This branch keeps to blocks, items, enchanting, brewing, sparkstone, structures, world features and bug fixes; don't
merge their PRs.
