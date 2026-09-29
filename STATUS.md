# Status

## 2026-09-29 — v0.1 first full draft
- All source files written (Math, Noise, Blocks, Chunk, Textures, WorldGen, Mesher, Save, World, Player, Input, Game, Shaders, Renderer, App, main) + Info.plist, build.sh, snap.sh.
- NEVER COMPILED YET (authored in a Linux sandbox with no Swift toolchain). Expect a round of compile fixes.

## First session checklist
1. `./build.sh debug` → fix errors until clean, then `./build.sh`.
2. `./snap.sh` → view snaps/*.png. Check: terrain visible (not inside-out → if only back faces show, flip setFrontFacing in Renderer), textures upright on side faces, water translucent, HUD hotbar + crosshair, sun position, night darkness, fog blend to sky.
3. Check timings: mesh(1 chunk) should be a few ms; frame well under 16 ms at rd 8.
4. Launch the app only when Remington asks (it takes focus / captures the mouse).

## Known risks / unverified assumptions
- Face winding (.counterClockwise front) — verify in snapshot.
- Swift 6.3 compiler in Swift 5 mode: Sendable/MainActor warnings expected, hopefully not errors.
- Skylight is a heightmap approximation (no propagation) — caves are dark by design, overhangs uniformly shaded.
- Water is static (no flow); placing water isn't in the block cycle.
