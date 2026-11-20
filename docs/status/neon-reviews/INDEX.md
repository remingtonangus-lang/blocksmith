# Sunderfall Deep Code Review Index (`origin/claude/quest-port`)

Read-only area-by-area code review targeting real player bugs, crashes, frame-rate hits, half-done features, and Meta Horizon Store VRC compliance. Skips issues already marked fixed in `docs/status/bug-ledger.md` and findings already covered in `docs/status/render-distance-review.md` and `docs/status/neon-review-2.md`.

Base branch reviewed: `origin/claude/quest-port` (`cb7295fb`, Ledger 385; Areas 1–2 reviewed at `89369b4`, Ledger 383).

## Reviews

| # | Area | File | Status | Scope |
|---|---|---|---|---|
| 0 | Nov 20 Playtest Review | `playtest-2026-11-20.md` | **Done** | 38 voice notes + 1664×1760 frames (build 0.995 / `3376e5ab`) |
| 1 | Quest Platform, OpenXR, Vulkan & Shaders | `01-quest-platform-xr-vulkan.md` | **Done** | `quest/src/android/`, `quest/src/xr/`, `quest/src/vk/`, `quest/shaders/`, `quest/src/common/` |
| 2 | VR Controls, Locomotion, HUD & Menus | `02-vr-controls-ui-menus.md` | **Done** | `quest/src/app/`, `Sources/Menu*.swift`, `PauseMenu.swift`, `CombatHUD.swift`, `WorldMap.swift`, `VRMelee.swift` |
| 3 | Save/Load, World Streaming, Meshing & Fluids | `03-save-load-world-streaming.md` | **Done** | `Sources/World.swift`, `Save*.swift`, `Chunk.swift`, `ChunkShells.swift`, `Mesher.swift`, `MeshArena.swift`, `WorldStore.swift`, `TerrainField*.swift`, `FieldTerrain.swift`, `FineField.swift`, `BlockEntities.swift` |
| 4 | Ships, Capital Vessels, Vehicles, Trains & Physics | `04-ships-vehicles-physics.md` | **Done** | `Sources/Ships*.swift`, `Ship*.swift`, `Capital*.swift`, `Vehicle*.swift`, `Trains*.swift`, `MainGun*.swift`, `Felling.swift` |
| 5 | Combat, Guns, Mobs, AI, Bosses & Raids | `05-combat-guns-mobs-bosses.md` | **Done** | `Sources/Guns.swift`, `Ballistics.swift`, `Soldiers.swift`, `Mob*.swift`, `Spawning.swift`, `End.swift`, `Raid*.swift` |
| 6 | Worldgen, Biomes, Structures, Dimensions & Far Scenery | `06-worldgen-structures-biomes.md` | **Done** | `Sources/WorldGen*.swift`, `Structures.swift`, `Deep*.swift`, `NetherGen.swift`, `MilitaryBase.swift`, `Far*.swift` |
| 7 | Core Survival, Crafting, Towns, Economy & Sparkstone | `07-core-gameplay-economy-progression.md` | **In progress** | `Sources/Game.swift`, `Loot.swift`, `Recipes.swift`, `Villager*.swift`, `Town*.swift`, `Economy*.swift`, `Sparkstone.swift` |
| 8 | Audio Engine, 3D Ambience, Music & Soundtrack | `08-audio-music-ambience.md` | Pending | `Sources/Sound*.swift`, `Audio*.swift`, `Music.swift`, `Soundtrack.swift`, `quest/src/common/QuestSound*`, `QuestAudioOutput*`, `QuestTracks*` |

## Current Position
Working on **Area 7 (`07-core-gameplay-economy-progression.md`)**.
