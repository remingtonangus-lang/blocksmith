import Foundation
import simd

// The Capital's frigate (role "capfrigate"; replaces the Skyward Frigate's airship look, Future ideas #1 and
// Remington's 2026-10-04 list). An original design: a sleek, modern flying warship at true frigate scale (142 blocks
// = 142 m long, 27 wide), white and light-grey armour in faceted, chined planes: a V hull widening to a hard chine,
// tumblehome sides up to the deck, an enclosed faceted deckhouse with an integrated pyramid mast and flat radar faces
// (no masts, sails, rigging or wooden-ship shapes), a stealth-shaped bow gun, vertical launch cells, two close-in
// gun mounts, a hangar and flight deck aft, and four drive nozzles in the transom with lift strips under the keel.
// Bow toward -Z at z 0, keel at y 0, centreline x 0. Kinematic like the other capital ships (CapitalShips.swift).

extension BlockRegistry {
    // The Capital's palette: white armour plate, light-grey trim, graphite for sensor faces and the boot-top, smoked
    // glass. Ship plate takes damage like warship plate (resistance 9).
    func registerCapitalFactionBlocks() {
        for (n, disp) in [("capital_plate", "Capital Armour Plate"), ("capital_panel", "Capital Hull Panel"), ("capital_trim", "Capital Trim"),
                          ("capital_graphite", "Capital Graphite Plate")] where !has(n) {
            var d = BlockDef(n, disp)
            d.tex = [n]
            d.hardness = 8; d.resistance = 9; d.tool = .pickaxe; d.requiresTool = true; d.harvestLevel = 2; d.sound = .stone
            add(d)
        }
        if !has("capital_glass") {
            var d = BlockDef("capital_glass", "Capital Smoked Glass")
            d.tex = ["capital_glass"]; d.opaque = false; d.layer = .cutout; d.cullSame = true
            d.hardness = 10; d.resistance = 9; d.tool = .pickaxe; d.requiresTool = true; d.harvestLevel = 2; d.sound = .glass
            add(d)
        }
    }
}

extension TextureGen {
    static func capitalFactionPainters(_ p: inout [String: Painter]) {
        // White plate: large clean panels, a faint seam at the block edge, soft shading so big faces aren't flat.
        p["capital_plate"] = { x, y in
            if y == 15 || x == 15 { return hex(0xB8BEC4) }
            if y == 0 || x == 0 { return hex(0xF4F6F8) }
            return hex(0xE6EAEE, 0.97 + 0.02 * r(x / 8, y / 8, 2301) + 0.012 * r(x, y, 2302))
        }
        // Hull panel: the same white with a chamfered inset panel and two flush fasteners.
        p["capital_panel"] = { x, y in
            if y == 15 || x == 15 { return hex(0xB4BAC0) }
            if y == 0 || x == 0 { return hex(0xF6F8FA) }
            if (x == 2 || x == 13) && y >= 2 && y <= 13 { return hex(x == 2 ? 0xF8FAFC : 0xC4CAD0) }
            if (y == 2 || y == 13) && x >= 2 && x <= 13 { return hex(y == 2 ? 0xF8FAFC : 0xC4CAD0) }
            if (x == 4 || x == 11) && y == 7 { return hex(0xAEB4BA) }
            return hex(0xE2E6EA, 0.98 + 0.015 * r(x, y, 2303))
        }
        // Trim: light grey with a fine horizontal brushed grain.
        p["capital_trim"] = { x, y in
            if y == 0 { return hex(0xD4D8DC) }
            if y == 15 { return hex(0x8E949A) }
            return hex(0xB2B8BE, 0.96 + 0.04 * r(0, y, 2304) + 0.02 * r(x, y, 2305))
        }
        // Graphite: dark grey composite for radar faces, sensors and the boot-top; a faint hex grid.
        p["capital_graphite"] = { x, y in
            if x == 0 || y == 0 { return hex(0x4A5056) }
            if (x + 2 * y) % 8 == 0 || (x - 2 * y + 32) % 8 == 0 { return hex(0x2C3035) }
            return hex(0x383D42, 0.95 + 0.05 * r(x, y, 2306))
        }
        // Smoked glass: dark blue-grey, mostly see-through, a soft diagonal sheen and a thin white frame.
        p["capital_glass"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0xD8DCE0) }
            if abs(x - y - 3) <= 1 { return hex(0x9AB0C4, 1, 0.55) }
            return V4(0.16, 0.22, 0.30, 0.35)
        }
    }
}

extension Capital {
    static let capFrigateLength = 142

    // Hull half-width at deck level along the length: a long fine bow, parallel midbody, slight taper at the transom.
    static func cfHalf(_ z: Int) -> Float {
        let zf = Float(z)
        if zf < 52 { return max(1, 13.5 * powf(zf / 52, 0.62)) }
        if zf > 128 { return 13.5 - (zf - 128) * 0.12 }
        return 13.5
    }
    // Keel height: the forefoot rises toward the bow.
    static func cfKeel(_ z: Int) -> Float { z < 34 ? 2 + Float(34 - z) * 0.22 : 2 }

    // Inside the hull: a V below the hard chine (y 8), tumblehome above it up to the deck (y 14).
    static func cfHull(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard z >= 0 && z < capFrigateLength && y <= 14 else { return false }
        let k = cfKeel(z)
        let yf = Float(y)
        guard yf >= k else { return false }
        let h = cfHalf(z)
        let w: Float
        if yf <= 8 { w = h * (0.32 + 0.68 * (yf - k) / max(1, 8 - k)) } else { w = h * (1 - 0.13 * (yf - 8) / 6) }
        return Float(abs(x)) <= w
    }
    // The deckhouse: tumblehome sides, a raked front, a square aft end over the hangar.
    static func cfHouse(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard y >= 15 && y <= 26 && z <= 102 else { return false }
        let yf = Float(y - 15)
        let front: Float = 46 + yf * 0.7
        guard Float(z) >= front else { return false }
        let half: Float = 10 - yf * 0.32
        return Float(abs(x)) <= half
    }
    // The integrated mast: a faceted pyramid rising from the deckhouse roof.
    static func cfMast(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard y >= 27 && y <= 37 else { return false }
        let t = Float(y - 27)
        let half: Float = 5.5 - t * 0.42
        let z0: Float = 58 + t * 0.55, z1: Float = 74 - t * 0.55
        return Float(abs(x)) <= half && Float(z) >= z0 && Float(z) <= z1
    }

    // A stealth-shaped gunhouse with one long barrel.
    static func capitalGun() -> Blueprint {
        let t = Blueprint()
        t.box(-2, 2, 0, 1, -2, 3, "capital_plate", hollow: true)
        t.box(-1, 1, 2, 2, -1, 2, "capital_panel")
        for x in [-2, 2] { t.clear(x, 1, -2) }              // chamfered front corners
        t.set(0, 2, 3, "capital_graphite")
        for z in -9 ... -3 { t.set(0, 1, z, "capital_trim") }
        t.set(0, 1, -10, "ship_cannon[south]")
        return t
    }
    // Close-in gun mount: a white drum with a graphite sensor cap.
    static func capitalCIWS() -> Blueprint {
        let t = Blueprint()
        t.box(-1, 1, 0, 1, -1, 1, "capital_plate")
        t.set(0, 2, 0, "capital_graphite")
        for z in -3 ... -2 { t.set(0, 1, z, "capital_trim") }
        t.set(0, 1, -4, "ship_cannon[south]")
        return t
    }

    static func capitalFrigate() -> HullBuilder {
        let W = 15, L = capFrigateLength
        let hb = HullBuilder(sx: 2 * W + 1, sy: 40, sz: L, ox: W)
        let plate = id("capital_plate", id("white_concrete")), panel = id("capital_panel", plate), trim = id("capital_trim", plate)
        let graphite = id("capital_graphite", id("warship_hull")), glass = id("capital_glass", id("armored_glass", GLASS))
        let light = id("light_panel"), engine = id("ship_engine"), console = id("command_console")
        func solid(_ x: Int, _ y: Int, _ z: Int) -> Bool { cfHull(x, y, z) || cfHouse(x, y, z) || cfMast(x, y, z) }
        // Shell: only the outer skin is built (the inside is decks and rooms), coloured by height.
        for z in 0..<L { for y in 0..<40 { for x in -W...W where solid(x, y, z) {
            let edge: Bool = !solid(x + 1, y, z) || !solid(x - 1, y, z) || !solid(x, y + 1, z) || !solid(x, y - 1, z)
                || !solid(x, y, z + 1) || !solid(x, y, z - 1)
            if !edge { continue }
            var b: BlockID = ((z / 6) + (y / 5)) % 4 == 0 ? panel : plate
            if y <= 3 { b = graphite }                              // boot-top along the keel
            if y == 8 && cfHull(x, y, z) { b = trim }                // the chine line
            if y == 14 && cfHull(x, y, z) && !cfHouse(x, 15, z) { b = trim }   // weather deck
            hb.set(x, y, z, b)
        } } }
        // Lower deck inside the hull, and the deck under the deckhouse (inner cells, not part of the skin).
        for z in 18..<128 { for x in -W...W where cfHull(x, 8, z) && cfHull(x + 1, 8, z) && cfHull(x - 1, 8, z) { hb.set(x, 8, z, trim) } }
        for z in 46...102 { for x in -W...W where cfHull(x, 14, z) && cfHouse(x, 15, z) { hb.set(x, 14, z, trim) } }
        // Radar faces: flat graphite arrays on the mast's four sides.
        for y in 29...33 {
            let t = Float(y - 27)
            let half = Int(5.5 - t * 0.42)
            let z0 = Int(ceilf(58 + t * 0.55)), z1 = Int(74 - t * 0.55)
            for x in -max(0, half - 1)...max(0, half - 1) { hb.set(x, y, z0, graphite); hb.set(x, y, z1, graphite) }
            for z in (z0 + 2)...(z1 - 2) { hb.set(half, y, z, graphite); hb.set(-half, y, z, graphite) }
        }
        hb.set(0, 38, 66, graphite); hb.set(0, 39, 66, light)       // sensor dome and masthead light
        // Bridge: a smoked-glass band across the raked front and the forward sides, the helm, consoles.
        for y in 22...24 { for x in -9...9 {
            let z = Int(ceilf(46 + Float(y - 15) * 0.7))
            if cfHouse(x, y, z) { hb.set(x, y, z, glass) }
        } }
        for z in 54...62 { for y in 22...23 {
            let half = Int(10 - Float(y - 15) * 0.32)
            hb.set(half, y, z, glass); hb.set(-half, y, z, glass)
        } }
        hb.fill(-6, 6, 21, 21, 53, 64, trim)                        // bridge deck
        hb.set(0, 22, 55, Blocks.id("ship_helm[south]"))
        for x in [-4, -2, 2, 4] { hb.set(x, 22, 54, console) }
        hb.set(0, 25, 60, light); hb.set(0, 25, 64, light)
        let ladder = Blocks.id("ladder")
        for y in 15...21 { hb.set(-7, y, 66, trim); hb.set(-6, y, 66, ladder + 3) }
        hb.set(-6, 21, 66, AIR)
        // Side doors from the weather deck into the deckhouse.
        for sx in [-1, 1] { for y in 15...16 { for k in 9...10 { hb.set(sx * k, y, 80, AIR); hb.set(sx * k, y, 81, AIR) } } }
        // Forward: vertical launch cells (graphite hatches) ahead of the deckhouse, the bow gun before them.
        for z in stride(from: 31, through: 41, by: 2) { for x in stride(from: -4, through: 4, by: 2) { hb.set(x, 14, z, graphite) } }
        for z in stride(from: 31, through: 41, by: 4) { for x in [-3, 3] {
            hb.pods.append((V3(Float(x + W) + 0.5, 15.5, Float(z) + 0.5), simd_normalize(V3(0, 1, -0.15))))
        } }
        hb.set(0, 15, 22, Blocks.id("ship_turret_ring"))
        hb.turrets.append((hb.grid(0, 15, 22), capitalGun(), naval))
        hb.mainGun = (V3(Float(W) + 0.5, 16.5, 10), V3(0, 0, -1))
        // Close-in guns on the deckhouse roof, fore and aft.
        for z in [52, 96] {
            var top = 26
            while top > 15 && !cfHouse(0, top, z) { top -= 1 }
            hb.set(0, top + 1, z, Blocks.id("ship_turret_ring"))
            hb.turrets.append((hb.grid(0, top + 1, z), capitalCIWS(), auto))
        }
        // Hangar open aft onto the flight deck; landing markings and edge lights.
        for y in 15...22 { for x in -6...6 { hb.set(x, y, 102, AIR) } }
        for z in 104..<136 where z % 4 == 0 { hb.set(0, 14, z, panel) }
        for z in stride(from: 106, through: 134, by: 7) { for sx in [-1, 1] {
            let e = Int(cfHalf(z) * 0.87) - 1
            hb.set(sx * e, 14, z, light)
        } }
        for x in -5...5 { hb.set(x, 14, 118, graphite) }
        // Drive: an engine room aft (critical systems), four nozzles in the transom, lift strips under the keel.
        for sx in [-1, 1] { hb.fill(sx * 5 - 2, sx * 5 + 2, 5, 7, 118, 132, engine) }
        for nx in [-7, 7] { for ny in [7, 11] {
            for y in (ny - 3)...(ny + 3) { for x in (nx - 3)...(nx + 3) where cfHull(x, y, L - 1) {
                let rr = Float((x - nx) * (x - nx) + (y - ny) * (y - ny))
                if rr < 5 { hb.set(x, y, L - 1, light); hb.set(x, y, L - 2, light) }
                else if rr < 10 { hb.set(x, y, L - 1, trim) }
            } }
        } }
        for z in stride(from: 40, through: 124, by: 12) { for x in [-2, 2] { hb.set(x, 2, z, light) } }
        // Navigation lights on the bow and the stern quarters.
        hb.set(0, 13, 1, light)
        hb.chests.append((hb.grid(0, 15, 92), "steelhold_supply"))
        hb.set(0, 15, 92, Blocks.id("chest"))
        hb.chests.append((hb.grid(3, 22, 63), "steelhold_vault"))
        hb.set(3, 22, 63, Blocks.id("chest"))
        // Crew: the helmsman, a gunner for the bow gun and one per close-in mount, and a security detail in the hangar.
        hb.post(0, 22, 56, .driver)
        for (x, y, z) in [(3, 15, 28), (2, 22, 60), (4, 15, 96)] { hb.post(x, y, z, .gunner) }
        for (x, y, z) in [(-4, 15, 92), (4, 15, 90), (-3, 15, 98), (0, 9, 70), (-6, 9, 100)] { hb.post(x, y, z, .troop) }
        return hb
    }
}
