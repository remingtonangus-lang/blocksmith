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
