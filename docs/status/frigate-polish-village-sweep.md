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

## Results
- PR #12 (the Tidebreaker) rebased on quest-port (one docs conflict in quest-port.md, both sections kept) and merged.
  Its full questcheck had 4 failures, all identical on the base branch (16c360b): also seen by the horses thread, logged in known-test-issues.md.
- Main gun slice (`questcheck --render OUT --no-boreal --maingun-only`): all main gun checks pass. Aim marker: a
  21-puff ring 111 blocks out, predicted in 0.5 ms (-Onone host), the slug landed 0.2 blocks from it. Crater: 253
  blocks burnt (63 of 93 solid bowl tops black, the rest under water from the sea next to it; 105 scorched-earth rim
  columns). Hull hit on a Stormwarden frigate: drive 908 -> 0 engines, a hole torn through the plate (resistance-600
  light panels and resistance-9 plate shrugged off the old power-14 blast: 0 blocks before).
- Renders: evidence/2026-10-10/maingun_blast_polish.jpg (fireball and smoke column) and maingun_crater_polish.jpg.
- Verifier (independent pass) findings, fixed: half-step slabs inside a run of rises left a 1.5-block step (now only
  isolated rises get one); the scorch could blacken trunks, walls and roofs met first and set roofs alight (now
  natural ground only; torches and wire are no longer burnt off); the aim trace over unstreamed country cost 18 ms
  (generator columns), so it now stops at the streamed world's edge and the helm reads "out of sight" (0.7 ms worst).
- Structcheck sweep (`questcheck --structcheck --kinds village,wild_camp,capital_city --dims overworld --seeds
  12345,777,424242,2943808052895834412,1,99,31337,8675309 --per 3`, 72 instances, ~18 min on 4 cores):
  wild camps clean; villages door_needs_jump 7 (of 264 doors); capital cities floating 3.
  - Fixed (Village.swift): a lot's floor now matches the road's own height in front of it (the road's three columns
    share the centre's ground height; the edge column's ground could be a block off), and a road that climbs a block
    from one step to the next gets a half-step slab on the lower step. After: 3 of 264 doors, same 264 doors (a
    variant that also refused 2-block road steps lost 32 houses, so it was dropped).
  - Left: the 3 remaining doors are in one seed-1 village whose houses back onto terraced farm plots (the report's
    7x7 ground grid shows +0.9 farmland steps); 3 floating capital-city walls (seed 31337: 134 columns of trim 3
    blocks over a dip) are for the capital cities PR (#16 rewrites CapitalCity.swift).
  - door_needs_jump now prints a 7x7 grid of feet heights round the door, so the step that needs the jump shows.
