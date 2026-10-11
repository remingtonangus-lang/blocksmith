# Horses with a frontier-western feel (2026-10-10, thread "Horses")

Backlog item 1 slice: horses that ride like a ranch horse in an open-world western. Feel borrowed, nothing else (rule G:
no names, terms, art or layouts from any other game). Horse looks (models, colours, poses) stay with the Mac worker; this
work is handling, stamina, bond, care and safety only.

## Expanded objectives (written before building)

1. **Gaits and momentum.** Ridden horses (also donkeys, mules, skeleton and zombie horses) move in four gaits: walk,
   trot, canter, gallop (about 1/4, 1/2, 3/4 and all of the horse's own top speed). A light push walks (analog), a full
   push trots, each spur (the sprint button: Quest left-stick click while pushed, pad L3, keyboard sprint key) steps up
   to canter, then gallop. Letting the stick go slows the horse down through the gaits instead of stopping dead.
   Speed builds over about 1.5-2 s and a gallop stops in about 1.3 s (no instant start/stop). The horse turns toward
   where the rider steers at a limited rate that falls with speed, so a gallop carves wide arcs and a walk turns on the
   spot. Measured by: speeds per gait, time to gallop, stopping time, turn rate at walk vs gallop, max acceleration.
2. **Stamina.** Each horse has stamina (100, more with bond). Gallop drains it, canter drains less, trot/walk/standing
   refill it. An exhausted horse can't hold a canter or gallop (it drops to a trot) and spurring it anyway makes it rear.
   Treats refill stamina. Jumps cost a little. HUD: a stamina bar over the horse's hearts while riding (red when spent).
3. **Bond.** The bonded horse earns bond points from distance ridden, being fed, brushed, patted and calmed. Levels 1-4
   (0, 100, 300, 700 points), saved with the horse. Each level: more stamina (100/115/130/150), slower drain, faster
   refill, steadier nerves (less chance to throw the rider when spooked: 45/20/5/0 %). Level 2 adds saddlebags (9 slots
   in the horse's menu). A toast announces each level. HUD shows the level beside the stamina bar.
4. **Care.** While riding, using an empty hand pats the horse (bond, calms a rearing horse); a brush in hand brushes it
   (on foot or mounted: bond, a little health, cooldown); a treat in hand while riding feeds it (stamina, bond).
   Feeding a full-health tamed horse no longer does nothing: it refills stamina.
5. **Nerves (spooking).** Explosions, cannon fire, other people's gunshots close by and a hostile monster right beside
   the horse make it rear: it stops, rears and may throw a low-bond rider. The rider's own gunfire never spooks it
   (mounted shooting works). Patting while it rears calms it (no throw).
6. **Sure-footed.** A ridden horse refuses to run off a drop of 4+ blocks or into lava: it brakes in time and stops at the
   edge (a toast says so the first time). Normal hills and 1-3 block steps down are untouched; jumping (in the air) is
   untouched. Water counts as ground (horses swim).
7. **Crashes.** Galloping flat out (gallop gait, over 11 b/s) into a wall or trunk makes the horse stumble: it stops, loses stamina,
   takes a little damage; a level-1 bond horse throws its rider. Slower bumps are just stops.
8. **No regressions.** Taming, saddles, armour, the bonded-horse call, camels, pigs, magmastriders, llamas and boats ride
   as before; Quest sprint on foot unchanged; no new input conflicts (spur = sprint, pat = use with an empty hand).

## Pre-mortem (5 ways a player could break or dislike it, and the check for each)
1. The horse feels sluggish or won't stop when needed -> HorseTests: time to gallop <= 2.2 s, gallop stop <= 1.6 s.
2. Refusal blocks normal riding down hills -> HorseTests: a 1-block staircase down 8 blocks is ridden at a gallop.
3. Stamina runs out instantly / never -> HorseTests: a full gallop lasts 10-25 s on a level-1 horse; refills at walk.
4. Spooks throw the player constantly -> own gunfire never spooks; level 4 never throws; spook cooldown 4 s.
5. Old saves / other mounts break -> bond points saved in the mob's extra dictionary (absent = 0); camel, pig, llama
   checked by HorseTests to keep their old speeds.

## Checks
`questcheck` runs HorseTests (Sources/HorseTests.swift); Mac: `Blocksmith --horsetests`.

## Results (questcheck --horse-only, 2026-10-10)
Gaits 1.7 / 8.0 / 16.0 b/s (walk / trot / gallop, top-16 horse); standstill to gallop 1.6 s; gallop to stop 1.5 s;
worst ground acceleration 12.0 b/s^2; turning 3.9 rad/s at a walk, 1.5 at a gallop; a level-1 gallop lasts 15.6 s;
refuses the cliff and lava 0.3 blocks short; staircase + 3-block step ridden at >= 10 b/s; frights throw 14-17 of 40
at level 1, 0 at level 4, 0 when patted.

Also fixed: the first tamed horse a player ever rode never bonded (the game's bonded-horse id and the horse's bond were
both 0, so `bond != horseBond` was false and the call/whistle never worked until a second horse).

## Verifier pass 1 (independent Opus subagent) and what changed
FAIL with 2 blockers and 4 should-fix, all fixed with a HorseTests check each: a fright's hop carried a galloping
horse over the cliff it was braking for (rearing now checks speed, footing runs while rearing/slowing); treats and an
empty hand while riding took over eating, placing and levers (care now needs the aim on the horse itself); backing up
walked off cliffs (footing checks behind); a dead pack animal's cargo could be taken twice (duplicate drop removed);
drawing a bow stalled a gallop (no item-use slow-down on a horse); most guns (sheriff, soldiers, ships) never reached
the horse (every gun / blast sound now does); care cooldowns only ran while ridden and weren't saved.

## Not covered / for others
- Device feel (Quest) not tested here: the Mac worker owns device testing.
- Gait sounds (hoof rhythm per gait) and a rearing pose are looks/audio work for the Mac lane.
- Town stables selling horses: towns thread.

## Gap pass (2026-10-11, cloud gap pass area R; docs/status/cloud-gap-pass.md)

Expanded objectives written before building (each is a row of the gap table: A1a, A1b, A1d, A1e, ER1-ER4, ER6-ER11):
- Breeds (HorseLife.swift, HorseBreed): Plains Mustang, Sandrunner, Mountain Pony, Draft Horse, Saddlebred, each with
  its own speed range, stamina, courage (fright and throw odds), jump and coats. Every new horse rolls one; an old
  save's horse gets the breed its speed fits. The Saddlebred is the baseline (stamina and nerve as before).
- Names (ER1, VR-friendly): your horse is named from a list when it first becomes yours; the stable renames it from
  the list (one press each, no typing).
- Taming (ER3): a calm-down minigame instead of a dice roll. The wild horse bucks in bursts; sit still through a
  buck and pat it (use, empty hand) as it settles; steering or patting mid-buck frightens it. Calm full: tamed.
  Calm gone at the end of a buck: thrown.
- Fear (ER4): until bond level 3 a horse is frightened by predators (wolves, bears, big cats) and monsters within 6
  blocks, not only a monster beside it; until level 4, by other people's gunfire.
- Bond unlocks (A1b): tighter turning at each level (+12% a level); level 3, a rear on command (spur standing still,
  never a throw); level 4, a sliding stop (twice the braking with the stick let go) and calm under gunfire.
- The horse remembers you (A1d): every horse you have ridden keeps its own bond and id; the one ridden last comes
  when called.
- Calling (A1a): a called horse paths to you (round walls and rivers, up to 160 blocks, 1500-node searches); stuck
  for 6 s, it is brought round behind you on your own level (never off a cliff edge onto the ground below).
- Left alone (ER11): a horse of yours that isn't called waits where you left it, grazing and wandering a few blocks.
- Injured (ER6): a horse of yours that would die goes down for 5 minutes; a Saddle Salve (stable, doctor) brings
  it back; left that long, it dies for good. Wild horses just die.
- The stable (A1e, ER7): the stablehand's counter has a Horses button: buy any breed (saddled, tamed, yours),
  stable a horse standing nearby (up to six, in any town; the whole horse is kept: name, breed, bond, gear, bags),
  take one out (free here, $2 to bring one over from another town's stable), sell (half the breed's price plus a
  little per bond level), rename. Calling a stabled horse says which stable it's in.
- Saddlebags in VR (ER8): reach down to the horse's flank behind the saddle with either hand and grip: the bags
  open (a short buzz) instead of stepping the hotbar.
- VR comfort (ER9): the comfort vignette on a horse follows its turns and speed changes (a steady run is light,
  wheeling round and pulling up darken more); Steady Saddle (VR Comfort page, on by default) eases the view over
  jumps, bucks and hops (a 1.2-block lift moves the eye 0.04). Snap or smooth turning is the global setting.
- Hooves (ER10): hoof falls by the ground underfoot (stone, wood, earth, sand and gravel, snow, water), synthesized,
  their rhythm following the gait.

Checks: HorseGapTests.swift (36 checks, end of `--horse-only` and every questcheck). HorseTests' test horse is pinned
to the Saddlebred so the older gait, stamina and nerve numbers hold; the gunshot check now expects level 3 to rear and
level 4 not to.

### Gap pass verifier (independent Opus subagent) and what changed
- A horse walked back to an old wait spot after you rode it somewhere else: it now forgets the spot whenever it is
  ridden, so it waits where you get off. The test rides it away after a call before leaving it.
- "Horse Reviver" is another western game's item name: it is now the Saddle Salve (ip-renames.md). Both names are
  in tools/coined-terms.txt so namecheck catches them.
- Taming had no skill (sitting still always tamed it): each buck now takes more calm than a quiet spell gives back,
  so only pats timed to the quiet spells fill it. Test: sitting still without patting gets you thrown (about 10 s).
- Money: a stable buys one horse a day from you.
- A downed horse could still be finished off by damage that skips hit() (instant damage, a hull): now it stays down
  until its own time runs out, and it falls to the ground instead of hanging where it went down.
- Steady Saddle lagged on long climbs: it now uses a second-order follower (its climb rate eased, then its position),
  so it trails a 3 b/s climb by 0.04 blocks and still absorbs a 1.2-block jump to 0.04.
- The vignette on a horse is RideComfort's alone (the walking speed term no longer adds 0.5 at any gallop). Turning
  and braking are capped below full black.
- A horse left waiting bolts from a wolf (below bond level 3), not only a ridden one.
- Sandstone sounds hard, not loose. Concrete powder no longer sounds like snow.
- Old stabled horses show the breed their speed fits.
- A downed horse in unloaded ground is no longer pulled into the world by a call.
