# Integration stream (claude/blocksmith-playtest)

Owner: the integration session. Owns tasks 4 (Capital frigate), 5 (twin 42 cm turrets) and 6 (Capital citadels) of
Remington's 2026-10-04 list, plus merging the other streams. Other streams: (B) claude/bs-vehicle-riding (riding moving
vehicles, crews aboard), (D) claude/bs-capital-soldiers (soldier models, dress uniforms, arms bug, ranks/gear), and a
local Claude Code on Remington's Mac (USB GIP controller driver, hardware tests).

## Done in this stretch (2026-10-04)
- (0) Fast flight: sprint while flying ~8x (87 b/s), V toggles it (Key Bindings > Toggle Fast Flight).
- (1) Halo Infinite-style controller defaults: R3 melee, B crouch, sensitivity 1-10 per axis (default 3), power curve,
  look acceleration 0-5 (default 3), centre dead zone + max input threshold per stick; all in Options > Controller.
- (1b) usb-gip driver (USBGamepad.swift) - now owned by the Mac session. The integration session only fixed its
  IOUSBHost Swift names so the branch compiles (refined-for-Swift methods are imported as __configure,
  __sendIORequest, __enqueueIORequest). NEEDS A HARDWARE CHECK on Remington's Mac.
- (2) Capital vehicles are machines with components (helm, engines, per-wheel tracking) and crews (driver, gunners,
  troops); disabled not despawned. (3) first pass: Mob.deck riders walk in the ship frame; --ridetest added
  (reported, not gating). Stream B continues both.
- (4) Capital frigate: CapitalFrigate.swift (role "capfrigate", 142 blocks, kinematic). Replaces the Skyward Frigate
  in "frigate" encounters, /vessel frigate and the ship_frigate shots (bow/side/top/deck views added).
- (5) HeavyTurret (Soldiers.swift): the deck_gun mob is a true-scale twin 42 cm turret; shells burst like TNT
  (power 2.4, breaks blocks: Slug.breaks).
- (6) CapitalBase.swift: citadels replace the Steelhold fortresses (key military_base, mob keys and steelhold_* loot
  tables kept). A Capital frigate is stationed over each citadel (ShipManager.stationFrigates, key citadel:x,z).

## Next
- Read the CI shots: ship_frigate*, citadel_far/gate/top/plaza; fix what looks wrong (proportions, glass, gardens).
- structcheck / fortresstest on the new citadel (walkability: ladders, doors, pad, skyways; mobs not in blocks).
- Make --ridetest gating once it passes (or hand it to stream B).
