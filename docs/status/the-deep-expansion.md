# The Deep expansion (backlog item 2, 2026-10-10)

Remington's ask: "Nether-sized hell, hard barrier below it that only a rare processed ore from guarded hell strongholds
can break, huge Ash Vault with its own sky and an army harder than the surface bases."

Starting point (task 22, already on claude/quest-port): the Deep (Dim.deep, 384 tall) under the surface. Top-down: upper
crust, a 128-tall hell band (the Emberdeep's own generator, fortresses), lower crust, the Ash Vault (~100-block cavern,
the Ashguard army, the Ash Marshal), molten core. Anyone could dig from the hell band straight into the vault.

## Expanded objectives (written before building)
1. **Nether-sized hell.** The hell band stays the full Emberdeep terrain: 128 blocks tall, unbounded across, all five
   ember biomes, lava sea, fortresses; add the Emberdeep's bastions too so it is the whole thing, not a slice.
   Check: band height 128, the five biomes within 2,000 blocks, fortresses and bastions present.
2. **The barrier: Sealrock.** An 8-layer floor of Sealrock right under the hell band, unbroken across the whole Deep.
   Unbreakable to every pickaxe, explosion (TNT, tank shells, the frigate main gun's crater), piston, mob and fluid.
   Only a Sunderite Pickaxe mines it (a few seconds a block); a Sunder Charge blasts a 3x3 shaft straight through it.
   Saved Deep chunks from before the seal get it stamped in as they load (only chunks with no Sealrock at all, so a shaft
   a player cut legitimately stays open). Chorus fruit can't hop across it. Hitting it with anything else tells the
   player what can break it. Check: every column of sampled chunks sealed; break time infinite for a Duskium pick and
   finite for a Sunderite one; TNT / crater leave it; save migration; charge shaft.
3. **The ore: Sunderite (rare, processed).** Sunderite Ore never generates in open rock: it exists only inside the
   vaults of Brimstone Keeps (plus a little Raw Sunderite in their strongroom chests). Processing: Raw Sunderite x2 +
   Cinderwisp Powder -> Sunderite Flux (crafting) -> Sunderite Ingot (blast furnace only) -> Sunderite Pickaxe
   (Duskium Pickaxe + 3 ingots) or Sunder Charge (ingot + TNT). One keep yields enough for a pick (about 8-12 raw).
   Check: recipes resolve, flux refuses a plain furnace, ore only inside keeps over a large sample.
4. **Guarded hell strongholds: Brimstone Keeps.** Walled castles standing over the hell band's lava sea (one per
   ~512-block region): gatehouses with tunnels out through the rock, corner towers, a central keep, and a sealed
   strongroom under the keep whose walls hold the Sunderite. Garrison: Blight Skeletons, Boarling Brutes, Cinderwisps
   on the towers and an Ashguard detachment (riflemen, a heavy, an officer) guarding the strongroom, all at Deep power;
   Cinderwisp spawners on the towers. In the hell band a compass points to the nearest keep; `/locate brimstone_keep`.
   Check: keeps generate on 3 seeds with walls, ore >= 8 in the strongroom, garrison >= 12, reachable from the gate.
5. **A huge Ash Vault with its own sky.** Raise the roof (ceiling ~168, up from ~134): about 135 blocks floor to roof.
   In the vault the air is a smoky ember haze that swallows the roof, so overhead reads as a sky, with the Cinder Sun (a
   dull molten disc) hanging in it; ambient light up so the vault is readable (scorecard: "very dark"). Quest renderer
   first, Mac matching. Check: vault open floor to roof, haze colour/ambient in the vault differ from the hell band and
   crust, a Quest render of the vault with mean luma above the old shot's.
6. **An army harder than the surface bases.** A garrison-strength metric (sum over units of health x power x armour
   factor, and gun count) over the Ash citadel vs a Capital citadel and a Boreal Station; target: the Ash citadel's
   garrison >= 2x the strongest surface site, and its soldiers individually tougher than Capital ones. Raise Ashguard
   soldier power and the Marshal's health, heavier armour on ranks, more troops at the citadel if needed.
   Check: the metric in a questcheck line with the three numbers.

Out of scope (Mac worker owns): mob/tree/surface-sky looks. No new mob models.

## Defaults picked (no questions asked)
- Names: Sealrock, Sunderite (Ore / Raw / Flux / Ingot / Pickaxe), Sunder Charge, Brimstone Keep, the Cinder Sun.
- Seal at internal y 192-199 (8 layers) directly under the hell band (hellBase 200).
- Vault roof raised for newly generated chunks; chunks a player already modified keep their old roof (seams possible
  only there).

## Results
(filled in as the work lands)
