import Foundation

// P504 (Remington, Nov 1 07:43 and 07:50: "how are the engines floating in space inside the ship? Doesn't make a lick
// of sense. Redesign the engine room so that it literally has block components and... all the [things] needed to run
// a frigate"; "we need a new engine room. One far more complex"): the Meridian frigate's drive hall is machinery made
// of blocks, every part standing on something. Its own design (CapitalFrigate's capitalFrigate builds it):
//   - the reactor: a column from the lower floor to the ceiling, a glowing core seen through a ring of armoured glass
//     banded by field coils, on a plinth, capped and piped to the ceiling, with a gallery round it on the upper deck;
//   - four drive units: long cylinders of engine blocks (the drive's critical systems) with clamp rings, a glowing
//     inspection strip along the top, an intake turbine at the front and an exhaust collar through the aft bulkhead to
//     the nozzles; the lower pair on the floor in cradles, the upper pair on the upper deck, hung from the ceiling;
//   - the upper deck over the lower engines on pillars, open down the middle over the aisle (railed) so the lower
//     engines are seen from above; feed conduits from the reactor to every drive unit, overhead on both levels;
//   - coolant tanks on the lower level, power banks along the upper level's walls, and the engineers' station at the
//     fore bulkhead: consoles facing the reactor under a wall of gauges.
extension BlockRegistry {
    func registerMeridianEngineering() {
        for (n, disp, e) in [("frigate_coil", "Meridian Field Coil", UInt8(12)), ("frigate_reactor", "Meridian Reactor Core", UInt8(15)),
                             ("frigate_conduit", "Meridian Conduit", UInt8(0)), ("frigate_gauge", "Meridian Gauge Panel", UInt8(5))] where !has(n) {
            var d = BlockDef(n, disp)
            d.tex = [n]; d.emit = e
            d.hardness = 6; d.resistance = 9; d.tool = .pickaxe; d.requiresTool = true; d.harvestLevel = 2; d.sound = .metal
            add(d)
        }
    }
}

extension TextureGen {
    static func meridianEngineeringPainters(_ p: inout [String: Painter]) {
        // Field coil: copper windings round a cyan glow, dark collars top and bottom.
        p["frigate_coil"] = { x, y in
            if y <= 1 || y >= 14 { return hex(0x26292D, 0.94 + 0.06 * r(x, y, 2701)) }
            if y % 3 == 0 { return hex(0xB86A2C, 0.9 + 0.1 * r(x, y, 2702)) }
            let k = 0.85 + 0.15 * r(x / 2, y, 2703)
            return V4(0.45 * k, 0.9 * k, 1, 1)
        }
        // Reactor core: white-hot middle, a slow cyan swirl.
        p["frigate_reactor"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            let d = (dx * dx + dy * dy).squareRoot() / 11
            let swirl = 0.12 * r((x + y) / 3, (x - y + 16) / 3, 2704)
            let k = max(0, 1 - d) * 0.6 + 0.4 + swirl
            return V4(min(1, 0.55 + 0.45 * k), min(1, 0.85 + 0.15 * k), 1, 1)
        }
        // Conduit: three steel pipes along the block, shaded round, an amber band on the middle one.
        p["frigate_conduit"] = { x, y in
            let band = y % 5, pipe = y / 5
            if y == 15 { return hex(0x1E2124) }
            if band == 0 { return hex(0x2A2D31) }
            let shade: Float = band == 1 ? 0.75 : (band == 2 ? 1.0 : (band == 3 ? 0.9 : 0.7))
            if pipe == 1 && (x == 6 || x == 7 || x == 8) { return hex(0xD69A2A, shade) }
            return hex(0x7C848C, shade * (0.96 + 0.04 * r(x / 4, pipe, 2705)))
        }
        // Gauge panel: dark plate, two round dials (pale faces, a red needle) and a row of small lamps.
        p["frigate_gauge"] = { x, y in
            for (cx, cy) in [(4, 6), (11, 6)] {
                let dx = x - cx, dy = y - cy, d2 = dx * dx + dy * dy
                if d2 <= 2 * 2 + 1 && (dx == dy || (cx == 11 && dx == -dy)) && dy <= 0 { return hex(0xC8302A) }
                if d2 <= 9 { return hex(d2 >= 8 ? 0x1A1C1F : 0xE4E2D4) }
            }
            if y == 12 && x % 3 == 1 { return hex(x % 2 == 0 ? 0x5AE06A : 0xF0B030) }
            if x == 0 || y == 0 { return hex(0x50555B) }
            if x == 15 || y == 15 { return hex(0x1E2124) }
            return hex(0x34383D, 0.95 + 0.04 * r(x / 3, y / 3, 2706))
        }
    }
}
