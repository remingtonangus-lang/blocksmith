# Frigate gun polish and village bug sweep (Oct 10, backlog item 1)

## Objectives (written before building)
Tidebreaker (the Meridian frigate's main gun, landed as PR #12):
1. **Fireball that reads as fire.** The big glow puffs used the `smoke` sprite, whose holes looked like eyes on a 6-10
   block puff (a jack-o'-lantern in `maingun_blast.png`). A solid `puff` sprite (lumpy rim, shaded, lit from the upper
   left) for every big gun particle; a white-hot heart fading to deep orange at the edge, dark soot round the skirt.
2. **A crater that reads as a blast, not a dig.** Bowl floor burnt to blackstone / basalt with a few glowing magma
   blocks; scorched earth (coarse dirt) and a few fires in a ring fading out to 1.5 radii; plants and snow burnt off.
   Sliced over frames with the carving (no new frame spikes).
3. **Know where the shot lands.** At the helm, a ring the size of the crater on the ground where the slug would land
   now (the slug's real flight: speed, hull drift, gravity, the generator's ground past the streamed world, other
   hulls), blue when loaded or charging, dim amber while reloading, scaled with distance; predicted 10 times a second.
4. **A hull hit is devastating.** A slug into another ship's hull knocked nothing out (the crater blast ran, but the
   drive kept going). Now it knocks out the drive (as a 42 cm shell does) and tears the hull open, also when the ground
   under it is not loaded.
Checks (questcheck `--maingun-only`, part of the full questcheck): ring drawn and predicted in < 4 ms; slug lands
within 6 blocks of the marker; crater scorched (bowl black, rim scorched); a Stormwarden frigate hit loses its drive
and 50+ blocks.

Village bug sweep:
5. **Structure walkability on the Quest build.** `questcheck --structcheck` (the Mac's StructCheck, shared code) on
   villages, wild camps and capital cities across 8 seeds (incl. Remington's 2943808052895834412): doors, steps,
   POIs, mobs in blocks, floating, torches. Fix every issue class it finds at the cause; the sweep's numbers go below.
6. TownTests (towns, shops, townsfolk) stay green.

Defaults picked: voice-note items (wallet HUD, more voice lines, angry townsfolk, sheriff) are owned by the towns
thread / Mac lane and are not touched here.
