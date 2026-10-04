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

## CI (heavy run 456 on cf2b180)
- Green: build, smoke, perf, checks (structcheck: 9 citadels, 99 POIs, 333 mobs, no issues), shots (mobtests clean once
  the stationed frigate was leashed to its citadel), tours (physicstest passes with the Capital frigate encounter).
- play: one playthrough FAIL (back through the Emberdeep arrival portal: the idle player was pushed out of it); fixed in
  15bc483 by holding the player in the portal. Verify on the next heavy run.
- --ridetest (not gating) now measures the real bug for stream B: on a crawler driving S-turns at 6 b/s the bot drifts
  154 blocks relative to the deck while standing still and falls off (5064 of 10800 frames off the deck); the sheep
  (Mob.deck in the ship frame) stays aboard except 197 frames. Riding the player is task 3 (stream B).

## Controller (usb-gip)
Compiles on CI since 627d256 (IOUSBHost refined names: __configure(withValue:matchInterfaces:),
__sendIORequest(with:bytesTransferred:completionTimeout:), plain enqueueIORequest(with:completionTimeout:)). Needs the
hardware check on Remington's Mac: run the built app from Terminal with the PowerA pad plugged in and read the
"usb-gip:" lines (found / step ... / opened / first input report). Owned by the Mac session.

## Standing order (Remington, 2026-10-04): never stop
Streams: B destruction physics + wrecks (plus riding), D reactive bases then pilotable aircraft/helicopters (plus
soldiers), H claude/bs-world-fx material damage + weather, Mac session usb-gip. This stream after the Capital rebuild,
in order: Future ideas #9 Big landmarks (volcanoes with bounded flowing lava, deep canyons, huge rare ruins seen from
far away via a landmark LOD / impostors past the render distance), #5 photo / cinematic camera (spline paths, depth of
field from the depth copy, hidden HUD), #10 split-screen couch co-op (after a perf pass: 60 fps at rd 8 per view).
Then bug hunting and measured improvements. Stays integration owner: branch green, PR #9 what's-new current.
.claude/ALLOW_STOP removed (the Stop hook keeps sessions working).

## Next
- Shots looked right in run 450 (frigate bow/side/top; citadel far/gate/top). Check the new citadel_turret,
  citadel_plaza and ship_frigate_deck angles and the flight-deck markings.
- structcheck / fortresstest on the new citadel (walkability: ladders, doors, pad, skyways; mobs not in blocks).
- Make --ridetest gating once it passes (or hand it to stream B).
