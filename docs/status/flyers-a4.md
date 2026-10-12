# Flyers and the crawler (backlog A4)

Lane A thread, 2026-10-12. Code: Sources/SkySkiff.swift (the kit, blueprint, deploy), SkySkiffTests.swift
(`questcheck --skiff-only`; part of every full questcheck run).

## Building your own
The free-moving block structures engine already flies what players build (Ships.swift, ShipPhysics.swift): a helm is
the control seat; lift balloons hold 2 t each and climb or sink on command; propellers give 120 thrust each, one
engine drives four; wings are airfoils and the rotor flies on the real flight model (FlightModel.swift). Weight is
counted per block (ShipParts.mass), so a heavy hull needs more balloons or wings and more engines.

## The Sky Skiff (ready-made)
- Kit: five lift balloons round a helm, two propellers either side of an engine (crafting grid
  `BBB / BHB / PEP`).
- Use it under open sky and a small airship inflates 9 blocks in front of you, bow the way you look (to the nearest
  quarter turn), keel a step over the ground: a spruce deck with a rail, a mast, a rounded envelope, the helm and
  engine aft, three stern propellers. Under a roof, a hillside or trees it tells you and keeps the kit.
- From then on it is an ordinary vessel: take the helm to fly, build on it, break it up, and it saves with the world.
- Checked: hovers unpiloted, climbs over 4 blocks in 3 s, flies over 10 blocks in 6 s on its propellers, sinks
  with iron on the deck (more mass than its lift), comes back from a save where it was, block for block.

## VR comfort in flight (already in place, checked here)
- The tracking space turns with the vessel's yaw only: the horizon stays level while a hull pitches and rolls
  (QuestControls.afterTick). There is no option to follow the hull's roll; locked is the comfortable choice, so it
  stays fixed (default picked, no question asked).
- The comfort vignette narrows on the ship's turns, speed changes and speed at the helm (ShipComfort), scaled by the
  Comfort Vignette setting; the Ship Deck Ring is the reference frame under the feet; snap or smooth turning applies.

## Deferred (T items)
- The crawler polish (terrain jitter, VR boarding and exit, repair) needs the Mac ride check (`--ridecheck`, Metal
  only) and device testing; logged as a T item rather than changed blind.
