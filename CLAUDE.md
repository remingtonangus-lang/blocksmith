# Blocksmith — agent guide (CLAUDE.md)

Native macOS voxel sandbox game (original Minecraft-style clone) for Remington's M1 MacBook (8 GB RAM, macOS 26, Command Line Tools only — NO full Xcode, no .xcodeproj, no .metal files compiled offline). Original name and procedural assets only: no Minecraft names, textures, sounds, or logos.

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
- Math.swift: V2/V3/V4, IVec3, perspectiveRH (Metal clip z 0..1), translationMatrix, rotationX/Y, Frustum(visible(min:max:)), hash3/hashf, floorDiv, mod.
- Noise.swift: seeded Perlin noise2/noise3/fbm2.
- Blocks.swift: block IDs 0–41 as globals (… BIRCH/SPRUCE logs+leaves, TALL_GRASS, flowers, TORCH, LAMP, WATER_FLOW[1...7] = 33–39, WATER_FALL = 40, APPLE = 41 item), texture layers enum T (46, incl. HUD hearts/food/bubble), BlockKind air/solid/cutout/liquid/plant(cross sprite)/item(hotbar only), BlockTable flat lookup tables (kind/opaque/sky(stops direct skylight)/lightOpaque/emit/fluidLevel/hidden/aoOcc/collide/cullSame/tex[id*6+face]), `let Blocks = BlockTable()`. Face order +X −X +Y −Y +Z −Z.
- Chunk.swift: CS=16, CH=192, SEA=62, ChunkKey, Chunk (blocks index x+z*16+y*256, modified, meshVersion/meshedVersion/meshInFlight, opaqueBuf/opaqueQuads, waterBuf/waterQuads, minY/maxY).
- Textures.swift: TextureGen.base() and mipChain() → RGBA8 16×16 texture-2D-array levels (alpha-weighted mips).
- WorldGen.swift: WorldGen(seed:), column(x,z)->(height,biome), generate(cx:cz:)->[UInt8] (biomes, caves, ores, trees/cacti).
- Mesher.swift: Mesher.build(n9) where n9 = 9 block arrays of the 3×3 chunk neighborhood (index cx+cz*3, center = 4), gathered into one 48×48×192 region; computeLight flood-fills sky + block light over it (nothing stored). Returns MeshData{opaque,water:[UInt32],minY,maxY}. Vertex = 2×UInt32: w0 = x(5) | y(9)<<5 | z(5)<<14 | face(3)<<19 (6 = plant) | corner(2)<<22 | ao(2)<<24 | waterDrop(3)<<26 (eighths) ; w1 = texLayer(8) | sky(4)<<8 | block(4)<<12 (smooth, per vertex). 4 verts per quad in order corners 0..3 (CCW seen from outside); draw with a shared quad index buffer (0,1,2, 0,2,3 per quad). UV from corner index. Plants = 2 diagonal quads × 2 windings.

- Save.swift: SaveManager (~/Library/Application Support/Blocksmith/Worlds/<name>/world.json + chunks/c.X.Z.lz, lzfse, modified chunks only), WorldMeta.
- World.swift: chunk dict, nearest-first gen/mesh scheduling on a concurrent queue (maxJobs = cores−2), unload beyond R+2, block/setBlock (sync remesh of chunk + edge/corner neighbours), raycast (DDA), loadSync, saveAll.
- Player.swift: AABB physics (walk/sprint/sneak/fly/swim, per-axis swept collision with sub-steps, sneak edge guard, unstuck, freeze on unloaded chunk).
- Input.swift: InputState (keys, taps, mouse deltas, clicks, scroll), readPad() → PadSnapshot, stick() deadzone curve, Key codes.
- Game.swift: tick (look, move, fly toggle, hotbar, break/place/pick with 0.25 s repeat, pause, autosave 60 s), day/night (sunDir, daylight, skyColor), findSpawn, WorldMeta apply/save.
- Shaders.swift: MSL source string — chunkVS/chunkFS (cutout discard, face shade, AO, skylight×daylight, fog), waterFS (scrolling, blended), simpleVS/FS (sun/moon, outline), hudVS/FS.
- Renderer.swift: pipelines, texture array upload, shared quad index buffer, camera-relative rendering (per-chunk offset = origin − eye), frustum culling, front-to-back opaque / back-to-front water, HUD (crosshair, hotbar, isometric icons), renderToPNG.
- App.swift: GameView (MTKView subclass: keys, mouse capture, scroll), AppDelegate (window, pause overlay, debug label F3, toasts, menu, occlusion pause), arg().
- main.swift: --snapshot harness (Snapshot.run), --sounds, else NSApplication.
- HudLayout.swift: all HUD pixel geometry (hotbar, inventory grid), shared by Renderer (drawing) and Game (mouse hit-tests).
- Sound.swift: SoundBank (pure DSP synthesis, 3 variants per Snd) + SoundEngine (AVAudioEngine, 12 player nodes, distance/pan). Game.sfx(...).
- Mob.swift: Mob (AABB physics, wander/panic AI), cuboid models written straight into the renderer scratch ring (writeMobVertices), MobManager (spawn/despawn/raycast).
- World.swift also has the fluid sim (fluidPending set, fluidTick every 0.2 s, setBlockAsync for bulk edits). Game.swift also has survival (health/hunger/air), creative inventory, audio hooks.

## Roadmap
Done: tree variety, plants, clouds/stars, block light + torches, flowing water, creative inventory, survival basics, synthesized sounds, passive mobs.
Next: item drops/counts/mining time + crafting, food from animals, greedy meshing, first-person hand, controller-driven pause menu for TV play.
