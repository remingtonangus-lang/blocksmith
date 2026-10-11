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

- Sunderite Ore drops exactly 1 Raw Sunderite (no Fortune); about 10 ore a keep, so one keep is a pickaxe and a couple
  of charges, not a stockpile.
- Keep causeways run on to 72 blocks with ladders every 8 (down to ground beside the bridge, up out of the rock), so a
  keep can be walked into from the hell band around it.
- Saved Deep worlds: new keeps and Deep bastions stay clear of chunks generated before them
  (structure-guard-deep-keeps.txt); the seal stamp replaces only the band's natural blocks (player builds and chests
  in those 8 layers stay).

## Results
Checks: `questcheck --deep-only` (DeepExpansionTests, part of every full questcheck).
- Hell band: 128 tall, all five ember biomes within 2,000 blocks; fortresses, bastions and keeps in every sampled
  region, no overlaps.
- Seal: every column of sampled chunks sealed in all 8 layers; TNT and a radius-9 main-gun crater leave it; the
  Sunderite Pickaxe takes 3.75 s a block; a Sunder Charge opens a 3x3 shaft through all 8 layers.
- Keeps (seeds 12345 / 777 / 424242): 218-304 blocks from the origin, strongroom ore >= 8, 3 chests, garrison of 14
  monsters + 7-10 Ashguard (strength 1597); walked into on foot from the ground around them.
- Vault: 133-145 blocks floor to roof; ember haze and the Cinder Sun on Quest (Mac: haze colour and the sun; the
  gradient dome is Quest only).
- Army: Ashguard citadel 8695 vs Capital citadel 4127 and Boreal Station 2030; an Ashguard rifleman 58 vs 20.

Independent verifier pass (2026-10-10): no way through the seal found (pickaxes, explosions, fluids, mobs, pistons,
pearls, spiral fruit, portals, ships). Fixed from its findings: wounded Ashguard healed on reload, keeps unreachable
on foot on some seeds, `/locate brimstone_keep`, Sunderite less rare than intended, Silk Touch Sealrock, charges
outside the Deep, the old-save stamp overwriting builds, keeps generating into explored ground.

Known limits:
- The vault sky switches at feet y 128 (fog, ambient and roof cut change together, no easing).
- Burning Sunder Charges are not saved (quitting during the 3 s fuse loses the charge).
- In a pre-expansion save the Marshal loads at his old full health (220 of 380).
- The Mac renderer's vault edits are not compiled on Linux; the Mac CI build covers them.

## Gap pass (2026-10-11, docs/status/cloud-gap-pass.md rows D1-D5, DE1-DE14)
The 2026-10-10 grading found the hell band still 128 tall, no portal-like structure at the keeps, no towns / rail /
airfield / mortars / patrols / alarm in the vault, no time-to-kill run, no perf measurement, and most expanded objectives
partial. Three PRs close it. Expanded objectives, written before building:

**D1, the hell band (PR 1).**
- The band is 176 tall (internal 200-375; upper crust 376-383). EmberGen takes a height: its lower 64 blocks are the
  Emberdeep's exactly (lava sea, shores, the fortresses and keeps on them), everything above is stretched up to the roof,
  so caverns run 100+ blocks floor to roof and lumenstone hangs in a roof far overhead (twice as many clusters).
- Check: band height >= 170; the median open run per column at least 1.5x the Emberdeep's and the tallest tenth 100+;
  the lower 60 blocks >= 97 % identical to the Emberdeep's; the existing biome / fortress / keep / seal checks still pass.
- Old saves: chunks generated before keep their 128 band (a step in the roof where old meets new, as with the vault).

**D2, the Ash Vault world and army (PR 2).**
- Garrison towns (D3b): four Ashguard towns on the ring road's far side (streets of barracks, a mess hall, a radio room,
  a depot, a signal tower, a station), each with soldiers and its story signs.
- Rail (D3b): rail lines on embankments from the citadel to every town and the airfield, stations at both ends.
- Airfield (D3b): a runway with lamps, hangars with parked bombers built of blocks, a control tower, fuel, AA guns.
- Mortars (D3c, DE10): mortar pits at the citadel, towns and outposts; crews lob shells at whatever the Ashguard has
  spotted. Every incoming mortar and field-gun shell is fair: a whistle and a red smoke marker where it will land,
  1.5 s or more before impact.
- Patrols (D3c): foot squads walk the roads between sites (a rifle squad: officer, MG, riflemen, a medic).
- The alarm (D3c, DE8): a vault-wide alarm level (Quiet, Alert, Alarm, Total War) that rises as you are spotted, kill
  units, wreck vehicles and close on the citadel; sirens and radio lines at each step; it falls slowly unseen; saved.
- Reinforcements (D3c, DE11): at Alarm and Total War, squads (and at Total War a half-track and a tank) leave the
  nearest motor pool / citadel for your last known position; officers who see you call the nearest idle tank.
- Squad roles (DE11): medics heal the wounded, MG gunners suppress, officers call armour; difficulty scales squad size,
  reaction and reinforcement count.
- Vehicles (DE9): a wrecked tank or half-track throws debris, burns, and its crew bails out and fights on.
- Story (DE8): signs at every site, field journals in the vault's chests (who the Ashguard are, why they are down
  here), radio chatter at radio rooms and over the alarm.
- Perf (D5, DE14): a unit cap (live Ashguard units near the player, reinforcements and patrols included), the far units'
  AI LOD, and a measured biggest battle (the citadel at Total War) in questcheck: tick ms and units, with the Quest
  renderer's draw time at that moment, numbers written here.

**D3, the Deep's progression and story (PR 3).**
- Ember Gates (D2b, DE4): a ruined gate frame beside every Brimstone Keep, the Deep's stand-in for a portal. Dormant
  until the keep's warden falls; then stepping in carries you to the surface (your bed or world spawn), and a Gate Shard
  (the warden's drop) carries you back down to the last gate you woke. The ways back are one per layer: the gates from
  the hell band, the command-bunker lift (after the Marshal) and a buildable Deep Lift from the vault.
- Keeps (DE7): three layouts (the castle, a ring fort, a terraced citadel), guards with roles (wardens on the walls,
  brutes at the gates, Ashguard at the strongroom), a mini-boss (the Keep Warden, boss bar) and a loot vault.
- Time to kill (D4b): a full-gear run in questcheck (the best armour and weapons a player has at the vault) against
  every Ashguard unit: time for the player to kill each and time for each to kill the player, written in
  docs/status/deep-balance.md with the progression curve (DE1).
- Progression (DE1): gear expected entering the hell band, at the seal and entering the vault; checks that the layers'
  enemies sit on that curve.
- Layer moods (DE2): the vault gets its own ambient bed and music theme (hell and crust already differ).
- Way-back marker (DE3): the compass and the HUD point to the way up: in the hell band the hole you came down, in the
  vault the nearest woken gate shaft / lift.
- Recipe hints (DE5): a Keeper's Journal (fortress chests, and a hint from the first Ashguard officer you kill) names the
  whole Sunderite chain and where the keeps stand; the chain is in the recipe book.
- The seal breaking (DE6): a big moment: a deep boom, a light column, shake, falling debris, an advancement.
- Rewards (DE13): a unique reward per layer (hell: the Warden's Brand trophy and Gate Shard; seal: Sealrock Shard
  blocks; vault: the Marshal's Cap trophy and Ashguard plating) and an advancement per milestone (hell band, a keep
  warden, the seal broken, the vault, the Marshal).
