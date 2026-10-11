# Tidebreaker gaps (Lane A) (Lane A, 2026-10-11)

## G1: the live helm shot never fired (done audit 25b6)
Objectives (backlog + Lane A's own):
1. Find why the g.tick path never finished the charge on the Mac harness, and fix the class, not the instance.
2. The helm shot through Game.tick charges for 2.6 s, fires one slug, lands where the marker shows and digs a crater of
   thousands of blocks, every run (no landing in water, no drift).
3. FactionTests fires a real slug at a citadel through the game loop (was Explosion.crater called directly), and the
   check gates questcheck.
4. The impact frame holds the Quest budget: the gun's biggest moment must not hitch.

Results:
- Cause: a fresh Game starts paused (Game.swift `paused = true`) and a paused Game.tick returns before advance(), so on
  the Mac harness (`--questbugs`) the shot charged for 400 empty frames (5.56 s). questcheck unpaused, so it passed.
  QuestBugTests.run and MainGunTests now unpause; every other g.tick test already did.
- FactionTests.frigate: a commandeered Meridian frigate 180 blocks off a citadel fires from its helm through Game.tick;
  the slug lands about 9 blocks from the citadel's centre and empties the inner bowl. Runs in questcheck after the main
  gun checks.
- Impact frame (host, -Onone): first frame 82-125 ms, worst 159 ms before; first frame 9 ms, worst 23 ms (water filling
  the bowl 2.5 s later) after. Causes: the structure lookup of what the slug hit planned a structure region (76 ms; now
  planned on a worker during the charge, MainGunStrikes.prewarm); a power-8 blast that breaks no blocks still cast its
  1,352 rays (17 ms; skipped); every crater cell marked ~40 circuit neighbours (7 ms a slice; skipped when no circuit
  part is within reach, World.circuitQuiet, scan spread over the first frames). New check: the impact's own work < 12 ms.

- Verifier pass (independent): the root cause, the FactionTests rewrite, thread safety and the circuit skip held up.
  It found a crash for a slug bursting above y 215 (the crater's circuit scan had an empty y range; fixed) and the
  test firing into a swamp in the full questcheck (the site is now chosen from the world spawn, in open country, and
  the test fails loudly when no dry landing exists). Full questcheck: every maingun and factions check passes; the
  12 failures left are the base's (town law/honour/bounty/six-iron/countries, the Marshal's barrage).
