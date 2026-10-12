# C8: submarines, sea mines and sonar (Lane A, 2026-10-12)

What a player sees: a Submarine Kit (iron, glass, a helm, an engine, a propeller, three ballast tanks) used at the
water's edge floats a small plank-hulled boat with ports along its sides and an open hatch on top. Climb in, take the helm:
sneak-down dives, jump climbs, and let go of both and it holds its depth. Its bow cannon, under water, looses torpedoes
that run level and fast. Horned sea mines on chains guard the Sunken Dreadnought wrecks and go off when a swimmer or a
moving hull comes within two blocks. The navy's frigates listen: run fast (over 3 blocks a second) or fire within 140
blocks of one and it pings you and drops depth charges that sink to your depth and burst; creep slowly and you are not
heard.

- `Sources/Submarines.swift`: the kit, its blueprint and deploy, mines, sonar, depth charges.
- Ballast tanks (`ship_ballast`, two from iron, glass and a bucket) work in any built hull: under water the tanks flood
  or blow (`ShipPhysics`, after the balloons) to follow the helm's climb or hold the depth it left.
- `ShipCombat`: a cannon whose muzzle is under water fires a torpedo (shell kind 4); depth charges are kind 5 with a
  fuse depth. Both trail bubbles under water.
- `OriginalSites.swift`: eight mines on chains round each Sunken Dreadnought.
- Checks: `questcheck --submarine-only` (`Sources/SubmarineTests.swift`): the recipe, deploy in a walled pool, dive,
  hold and surface, a torpedo from a bow cannon, sonar quiet vs loud with both charges bursting at depth, a mine.

Defaults picked (no questions asked, per the standing rules):
- Mines don't go off for creative players (vessels still set them off), so building near a wreck in creative is safe.
- Sonar listens only to a piloted submarine; an empty boat parked under water is not hunted.
- Leftovers (T13): enemy submarines to capture, the pinging frigate steering to the last ping, a Submarine Kit icon of
  its own (it borrows the airship's), generated mines that sit in their own dry cell inside the water.
