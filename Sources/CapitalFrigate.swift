import Foundation
import simd

// The Capital's frigate (role "capfrigate"). An original far-future warship (Remington 2026-10-05: frigates are
// space-navy warships of around 2500 AD, not ships of the sea, with hallways and rooms like the citadel): 200 blocks
// long, white and light-grey armour with graphite, a tall armoured prow wedge round the spinal gun's muzzle, a slimmer
// midsection with a dorsal spine, a raked bridge tower set aft, a wider engine block with drive nacelles and six
// glowing nozzles, a hangar open through both flanks, and inside two decks of corridors and rooms over the hangar and
// the hold (ShipInteriors.swift), an engine room with a gallery, ladders between them and a dorsal hatch.
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
    static let capFrigateLength = 200
    // Keel height over the highest ground around: the Capital frigate cruises above its citadels' towers (72 high).
    static func cruiseClearance(_ role: String) -> Float { role == "capfrigate" ? 78 : 30 }

    // Hull section at z (bow at z 0, toward -Z): half-width, bottom, top. A far-future warship's lines: a tall
    // armoured prow wedge round the spinal gun's muzzle, a slimmer neck and midsection with the habitation decks, and a
    // wider, taller engine block aft (Remington 2026-10-05: frigates are space-navy warships, not ships of the sea).
    static func cfSection(_ z: Int) -> (Float, Float, Float) {
        let zf = Float(z)
        func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * max(0, min(1, t)) }
        if z < 44 {
            let hw: Float = lerp(9, 15, zf / 12), yb: Float = lerp(8, 2, zf / 20), yt: Float = lerp(17, 24, zf / 30)
            return (hw, yb, yt)
        }
        if z < 60 {
            let t: Float = (zf - 44) / 16
            return (lerp(15, 12, t), lerp(2, 3, t), lerp(24, 22, t))
        }
        if z < 140 { return (12, 3, 22) }
        let t: Float = (zf - 140) / 12
        return (lerp(12, 16, t), lerp(3, 1, t), lerp(22, 26, t))
    }

    // Inside the main hull: the section with chamfered upper and lower edges.
    static func cfHull(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard z >= 0 && z < capFrigateLength else { return false }
        let ax = Float(abs(x)), yf = Float(y)
        let (hw, yb, yt) = cfSection(z)
        guard ax <= hw && yf >= yb && yf <= yt else { return false }
        let topC: Float = (ax - (hw - 5)) + (yf - (yt - 5))
        let botC: Float = (ax - (hw - 4)) + ((yb + 4) - yf)
        return topC <= 5 && botC <= 4
    }
    // The bridge tower: raked front, set aft on the dorsal line.
    static func cfTower(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard z >= 108 && z <= 136 && y >= 22 && y <= 31 else { return false }
        let half: Float = 7 - Float(y - 22) * 0.25
        guard Float(abs(x)) <= half else { return false }
        return Float(z - 108) >= Float(y - 22) * 1.2
    }
    // The dorsal spine ridge.
    static func cfSpine(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard z >= 40 && z <= 107 && abs(x) <= 2 else { return false }
        let (_, _, yt) = cfSection(z)
        let yf = Float(y)
        return yf > yt - 1 && yf <= yt + 2 - Float(abs(x))
    }
    // Drive nacelles on the engine block's flanks.
    static func cfNacelle(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard z >= 150 && z < capFrigateLength else { return false }
        let dx = Float(abs(x) - 17), dy = Float(y - 12)
        let r: Float = z < 156 ? Float(z - 150) * 0.85 : 5
        return dx * dx + dy * dy <= r * r
    }
    static func cfSolid(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        cfHull(x, y, z) || cfTower(x, y, z) || cfSpine(x, y, z) || cfNacelle(x, y, z)
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
        let W = 23, L = capFrigateLength, H = 36
        let hb = HullBuilder(sx: 2 * W + 1, sy: H, sz: L, ox: W)
        let plate = id("capital_plate", id("white_concrete")), panel = id("capital_panel", plate), trim = id("capital_trim", plate)
        let graphite = id("capital_graphite", id("warship_hull")), glass = id("capital_glass", id("armored_glass", GLASS))
        let light = id("light_panel"), engine = id("ship_engine"), console = id("command_console")
        let deck = id("steel_grating", trim), iron = id("iron_block")
        // Shell: only the outer skin (the inside is decks and rooms).
        for z in 0..<L { for y in 0..<H { for x in -W...W where cfSolid(x, y, z) {
            let edge: Bool = !cfSolid(x + 1, y, z) || !cfSolid(x - 1, y, z) || !cfSolid(x, y + 1, z) || !cfSolid(x, y - 1, z)
                || !cfSolid(x, y, z + 1) || !cfSolid(x, y, z - 1)
            if !edge { continue }
            let main = cfHull(x, y, z)
            let (hw, _, yt) = cfSection(z)
            let flank: Bool = main && Float(abs(x)) >= hw - 0.5
            var b: BlockID = ((z / 8) + (y / 6)) % 5 == 0 ? panel : plate
            if main && y <= 4 { b = graphite }                                  // ventral armour
            if flank && y == Int(yt) - 8 { b = trim }                            // the flank stripe
            if cfNacelle(x, y, z) && !main { b = z % 6 == 0 ? trim : panel }
            // Lit windows only where people live: the two habitation decks midships.
            let deckRow: Bool = y == 15 || y == 20
            if flank && deckRow && z > 50 && z < 138 && z % 8 == 1 { b = light }
            // Graphite armour bands across the top every 16 blocks (a white hull read as one flat slab from above).
            let roof: Bool = main && Float(y) >= yt - 1 && !flank
            if roof && z % 16 < 2 && z > 4 { b = graphite }
            hb.set(x, y, z, b)
        } } }
        // The spinal gun: a tube through the prow, its muzzle open in the bow, the breech at the neck.
        let gy = 12
        for z in 0...44 { for y in (gy - 3)...(gy + 3) { for x in -3...3 {
            let r: Float = sqrtf(Float(x * x + (y - gy) * (y - gy)))
            if r >= 1.8 && r < 3 { hb.set(x, y, z, iron) } else if r < 1.8 && z < 2 { hb.set(x, y, z, AIR) }
        } } }
        hb.fill(-3, 3, gy - 3, gy + 3, 41, 45, iron)
        hb.mainGun = (V3(Float(W) + 0.5, Float(gy) + 0.5, -1), V3(0, 0, -1))
        // The hangar: open through both flanks amidships, its deck at 4, the crew deck over it.
        hb.fill(-12, 12, 4, 4, 66, 104, deck)
        for z in 72...98 { for y in 5...10 { for sx in [-1, 1] {
            var xe = 0
            while cfHull(sx * (xe + 1), y, z) { xe += 1 }
            hb.set(sx * xe, y, z, AIR)
        } } }
        for x in [-12, 12] { for z in [71, 99] { for y in 5...10 { hb.set(x, y, z, trim) } } }
        for z in stride(from: 70, through: 102, by: 8) { for x in [-6, 0, 6] { hb.set(x, 11, z, light) } }
        // The hold aft of the hangar and the engine room: one deck at 4 to the stern, a gallery at 14 along the sides.
        for z in 105...197 { for x in -15...15 where cfHull(x, 4, z) && cfHull(x, 6, z) && hb.get(x, 4, z) == AIR { hb.set(x, 4, z, deck) } }
        for z in 144...196 { for x in -15...15 where abs(x) >= 10 && cfHull(x, 14, z) && cfHull(x, 16, z) && hb.get(x, 14, z) == AIR { hb.set(x, 14, z, deck) } }
        for sx in [-1, 1] { hb.fill(sx * 5, sx * 9, 6, 8, 168, 182, engine) }
        for z in stride(from: 148, through: 196, by: 8) { for x in [-12, 0, 12] where hb.get(x, 24, z) == AIR && cfHull(x, 24, z) { hb.set(x, 24, z, light) } }
        hb.ladderWell(x: 11, z: 145, y0: 4, y1: 14, back: 1)
        hb.ladderWell(x: -11, z: 195, y0: 4, y1: 14, back: -1)
        // Two decks of corridors and rooms over the hangar and the hold (the citadel's comforts, a warship's rooms).
        let style = InteriorStyle(floor: deck, wall: panel, trim: trim, light: light, bed: "white",
                                  armoryLoot: "steelhold_armory", supplyLoot: "steelhold_supply")
        let inside: (Int, Int, Int) -> Bool = { x, y, z in Capital.cfHull(x, y, z) }
        hb.interiorDeck(y: 12, h: 4, hw: 12, z0: 46, z1: 140, rooms: [.mess, .quarters, .armory, .quarters, .medbay, .storage, .quarters, .brig],
                        style: style, seed: 0xCF01, inside: inside)
        hb.interiorDeck(y: 17, h: 4, hw: 12, z0: 50, z1: 138, rooms: [.briefing, .quarters, .engineering, .quarters, .armory, .storage],
                        style: style, seed: 0xCF02, inside: inside)
        // Ladders: hangar and hold up to the crew deck, crew deck to the upper deck at both ends, up to the bridge,
        // and a dorsal hatch from the upper deck onto the hull (boarding from above).
        hb.ladderWell(x: -1, z: 107, y0: 4, y1: 12, back: -1)
        hb.ladderWell(x: 1, z: 52, y0: 12, y1: 17, back: 1)
        hb.ladderWell(x: -1, z: 136, y0: 12, y1: 17, back: -1)
        hb.ladderWell(x: 4, z: 128, y0: 17, y1: 22, back: 1)
        hb.ladderWell(x: 5, z: 62, y0: 17, y1: 22, back: 1)
        // Bridge in the tower: its floor (the hull's top and the tower share their inside cells), then a smoked-glass
        // band round the raked front and the sides, the helm, consoles.
        for z in 108...136 { for x in -7...7 where cfTower(x, 23, z) && hb.get(x, 22, z) == AIR { hb.set(x, 22, z, deck) } }
        for y in 26...28 { for x in -7...7 {
            let z = 108 + Int(ceilf(Float(y - 22) * 1.2))
            if cfTower(x, y, z) { hb.set(x, y, z, glass) }
        } }
        for z in 114...132 { for y in 26...27 {
            let half = Int(7 - Float(y - 22) * 0.25)
            hb.set(half, y, z, glass); hb.set(-half, y, z, glass)
        } }
        hb.set(0, 23, 113, Blocks.id("ship_helm[south]"))
        for x in [-4, -2, 2, 4] { hb.set(x, 23, 112, console) }
        for z in [118, 126] { hb.set(0, 30, z, light) }
        // Weapons: the bow gun over the prow, a second gun on the engine block, close-in guns on the bridge roof and
        // the engine block's shoulders; launch cells along the spine.
        hb.set(0, 25, 30, Blocks.id("ship_turret_ring"))
        hb.turrets.append((hb.grid(0, 25, 30), capitalGun(), naval))
        hb.set(0, 27, 156, Blocks.id("ship_turret_ring"))
        hb.turrets.append((hb.grid(0, 27, 156), capitalGun(), naval))
        hb.set(0, 32, 124, Blocks.id("ship_turret_ring"))
        hb.turrets.append((hb.grid(0, 32, 124), capitalCIWS(), auto))
        for sx in [-1, 1] {
            var top = 30
            while top > 20 && !cfHull(sx * 9, top, 172) { top -= 1 }
            hb.set(sx * 9, top + 1, 172, Blocks.id("ship_turret_ring"))
            hb.turrets.append((hb.grid(sx * 9, top + 1, 172), capitalCIWS(), auto))
        }
        for z in stride(from: 48, through: 100, by: 6) { for sx in [-1, 1] {
            let (_, _, yt) = cfSection(z)
            hb.set(sx * 4, Int(yt), z, graphite)
            if z % 12 == 0 { hb.pods.append((V3(Float(sx * 4 + W) + 0.5, yt + 1.5, Float(z) + 0.5), simd_normalize(V3(0, 1, -0.15)))) }
        } }
        // Drive: four nozzles in the stern face and one in each nacelle, glowing while the engines run.
        for (nx, ny, nr) in [(-7, 9, 3), (7, 9, 3), (-7, 19, 3), (7, 19, 3), (-17, 12, 3), (17, 12, 3)] {
            hb.exhausts.append(V3(Float(nx + W) + 0.5, Float(ny) + 0.5, Float(L) - 0.5))
            for y in (ny - nr - 1)...(ny + nr + 1) { for x in (nx - nr - 1)...(nx + nr + 1) where cfSolid(x, y, L - 1) {
                let rr = Float((x - nx) * (x - nx) + (y - ny) * (y - ny))
                if rr < Float(nr * nr) { hb.set(x, y, L - 1, light); hb.set(x, y, L - 2, light) }
                else if rr < Float((nr + 1) * (nr + 1)) { hb.set(x, y, L - 1, graphite) }
            } }
        }
        // The Capital chevron on both flanks of the prow, navigation lights.
        let chevron = ["X.....X", ".X...X.", "..X.X..", "...X..."]
        for (row, line) in chevron.enumerated() { for (k, ch) in line.enumerated() where ch == "X" {
            let y = 19 - row, z = 22 + k
            var xe = 0
            while cfHull(xe + 1, y, z) { xe += 1 }
            hb.set(xe, y, z, graphite); hb.set(-xe, y, z, graphite)
        } }
        hb.set(0, 17, 0, light)
        for z in stride(from: 40, through: 190, by: 15) { for x in [-3, 3] where cfHull(x, 1, z) || cfHull(x, 2, z) || cfHull(x, 3, z) {
            var b = 0
            while b < 6 && !cfHull(x, b, z) { b += 1 }
            hb.set(x, b, z, light)
        } }
        // Stores: supplies in the hangar, the captain's chest on the bridge.
        hb.set(9, 5, 90, Blocks.id("chest")); hb.chests.append((hb.grid(9, 5, 90), "steelhold_supply"))
        hb.set(3, 23, 131, Blocks.id("chest")); hb.chests.append((hb.grid(3, 23, 131), "steelhold_vault"))
        // Crew: the helmsman, a gunner per gun group, and a security detail in the hangar, the hold and the crew deck.
        hb.post(0, 23, 115, .driver)
        for (x, y, z) in [(0, 18, 58), (2, 23, 126), (0, 5, 150)] { hb.post(x, y, z, .gunner) }
        for (x, y, z) in [(-6, 5, 80), (6, 5, 94), (-4, 5, 100), (0, 5, 120), (0, 13, 90)] { hb.post(x, y, z, .troop) }
        return hb
    }
}
