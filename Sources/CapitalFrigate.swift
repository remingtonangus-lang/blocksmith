import Foundation
import simd

// The Meridian frigate (role "capfrigate", the internal key of the frigate encounter; task 23: the frigate is its own
// faction, the Meridian Navy, no longer the Capital's). An original design in the spirit Remington asked for (a
// rugged deep-space navy frigate) built around its spinal gun, the Tidebreaker: a long dark-grey hull, twin lower booms
// reaching forward at the bow with rows of lit portholes and the gun's 63-block barrel (glowing coil rings, a muzzle
// brake at the bow) running between them, a raised bridge with a sensor dome on the spine, a bulky engine block aft
// with four great glowing thrusters; point-defence guns and missile hatches along the spine. 160 blocks long, 27 wide.
// The Tidebreaker (a spinal coilgun, MainGun.swift) charges, then fires a slug that blasts a crater and a shockwave
// able to gut a citadel. Fast: 12-22 b/s under its own crew, 42 b/s commandeered. Bow toward -Z at z 0, keel at y 0.
// The Capital's ship palette (capital_plate & co.) below is still used by its dropships and citadels.

extension BlockRegistry {
    // The Meridian Navy's hull palette (warship-grade plate, resistance 9) and its lit portholes and thrusters.
    func registerMeridianBlocks() {
        for (n, disp) in [("frigate_hull", "Meridian Hull Plate"), ("frigate_plate", "Meridian Armour Panel"), ("frigate_trim", "Meridian Dark Trim"),
                          ("frigate_mark", "Meridian Hull Marking"), ("frigate_deck", "Meridian Deck Grating"),
                          ("frigate_wall", "Meridian Bulkhead Panel")] where !has(n) {
            var d = BlockDef(n, disp)
            d.tex = [n]
            d.hardness = 8; d.resistance = 9; d.tool = .pickaxe; d.requiresTool = true; d.harvestLevel = 2; d.sound = .metal
            if Armour.skins.contains(n) { Armour.harden(&d) }                 // P476: her skin is armour
            add(d)
        }
        for (n, disp, e) in [("frigate_porthole", "Meridian Porthole", UInt8(11)), ("frigate_thruster", "Meridian Thruster Core", UInt8(15)),
                             ("frigate_porthole_dark", "Unlit Meridian Porthole", UInt8(0))] where !has(n) {
            var d = BlockDef(n, disp)
            d.tex = [n]; d.emit = e
            d.hardness = 6; d.resistance = 9; d.tool = .pickaxe; d.requiresTool = true; d.harvestLevel = 2; d.sound = .metal
            add(d)
        }
    }
}

extension TextureGen {
    static func meridianPainters(_ p: inout [String: Painter]) {
        // Gunmetal hull plate: big panels, a dark seam on two edges, faint wear.
        p["frigate_hull"] = { x, y in
            if y == 15 || x == 15 { return hex(0x2A2D31) }
            if y == 0 || x == 0 { return hex(0x50555B) }
            return hex(0x41464C, 0.94 + 0.04 * r(x / 5, y / 4, 2601) + 0.025 * r(x, y, 2602))
        }
        // Armour panel: lighter grey with an inset frame and four rivets.
        p["frigate_plate"] = { x, y in
            if y == 15 || x == 15 { return hex(0x34383D) }
            if y == 0 || x == 0 { return hex(0x6E747A) }
            if (x == 2 || x == 13) && (y == 2 || y == 13) { return hex(0x3A3F44) }
            if (x == 1 || x == 14) || (y == 1 || y == 14) { return hex(0x5E6369) }
            return hex(0x585E64, 0.95 + 0.04 * r(x / 3, y / 3, 2603))
        }
        p["frigate_trim"] = { x, y in
            if y == 0 { return hex(0x3A3D41) }
            return hex(0x222428, 0.92 + 0.08 * r(x, y / 2, 2604))
        }
        // Marking: a pale band with a dark pinstripe (no insignia).
        p["frigate_mark"] = { x, y in
            if y == 3 || y == 12 { return hex(0x2C2F33) }
            return hex(0xC4C8CC, 0.95 + 0.04 * r(x / 2, y, 2605))
        }
        // P325 (b): the interior. Deck grating: dark plates crossed by a lighter grid, a rivet at each crossing.
        p["frigate_deck"] = { x, y in
            if (x % 8 == 0) && (y % 8 == 0) { return hex(0x6A7076) }
            if x % 4 == 0 || y % 4 == 0 { return hex(0x45494E, 0.95 + 0.05 * r(x, y, 2607)) }
            return hex(0x2E3236, 0.92 + 0.06 * r(x / 2, y / 2, 2608))
        }
        // Bulkhead panel: pale grey-green with a recessed frame and a dark seam at the block edge.
        p["frigate_wall"] = { x, y in
            if y == 15 || x == 15 { return hex(0x6E7470) }
            if y == 0 || x == 0 { return hex(0xC9CEC8) }
            if (x == 2 || x == 13) && y >= 2 && y <= 13 || (y == 2 || y == 13) && x >= 2 && x <= 13 { return hex(0x8F9690) }
            return hex(0xADB3AC, 0.96 + 0.03 * r(x / 4, y / 4, 2609) + 0.015 * r(x, y, 2610))
        }
        // Porthole: hull plate round a warm lit window with a dark frame.
        p["frigate_porthole"] = { x, y in
            if x >= 4 && x <= 11 && y >= 5 && y <= 10 {
                if x == 4 || x == 11 || y == 5 || y == 10 { return hex(0x1C1E21) }
                return hex(0xFFE7B0, 0.92 + 0.08 * Float(10 - y) / 5)
            }
            if y == 15 || x == 15 { return hex(0x2A2D31) }
            return hex(0x41464C, 0.95 + 0.03 * r(x / 5, y / 4, 2606))
        }
        // P357 (d): a porthole gone dark after a crash: the same frame round black glass with a faint grey sheen.
        p["frigate_porthole_dark"] = { x, y in
            if x >= 4 && x <= 11 && y >= 5 && y <= 10 {
                if x == 4 || x == 11 || y == 5 || y == 10 { return hex(0x1C1E21) }
                return hex(x - y == 0 ? 0x3A4048 : 0x15181C)
            }
            if y == 15 || x == 15 { return hex(0x2A2D31) }
            return hex(0x41464C, 0.95 + 0.03 * r(x / 5, y / 4, 2606))
        }
        // Thruster core: white-hot centre fading to blue.
        p["frigate_thruster"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            let d = (dx * dx + dy * dy).squareRoot() / 10.6
            let k = max(0, 1 - d)
            return V4(0.45 + 0.55 * k, 0.75 + 0.25 * k, 1, 1)
        }
    }
}

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
    static let mfLength = 160
    // Keel height over the highest ground around while cruising.
    static func cruiseClearance(_ role: String) -> Float { role == "capfrigate" ? 40 : 30 }

    // The twin lower booms (|x| 4-11, y 2-13), z 0-84, raked and chamfered at the bow; they reach 46 blocks ahead of
    // the upper hull.
    static func mfBoom(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard z >= 0 && z <= 84 else { return false }
        let ax = abs(x), zf = Float(z), yf = Float(y)
        let outer: Float = 11 - max(0, 10 - zf) * 0.45
        guard ax >= 4 && Float(ax) <= outer else { return false }
        let bot: Float = 2 + max(0, 9 - zf) * 0.45, top: Float = 13 - max(0, 12 - zf) * 0.5
        guard yf >= bot && yf <= top else { return false }
        if Float(ax) >= outer - 0.5 && (yf >= top - 0.5 || yf <= bot + 0.5) { return false }     // chamfered outer edges
        return true
    }
    // The spine: |x| <= 9, y 6-24, z to 128, chamfered top and bottom edges; its prow rakes back above the booms,
    // and between the booms it starts at z 64 (the Tidebreaker's breech).
    static func mfSpine(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard z <= 128 && y >= 6 && y <= 24 else { return false }
        let ax = abs(x)
        guard ax <= 9 else { return false }
        if ax + (y - 21) > 10 { return false }                      // top chamfer
        if ax + (9 - y) > 10 { return false }                       // bottom chamfer
        if y > 13 { return Float(z) >= 46 + Float(y - 13) * 0.9 }
        return z >= 64 || (ax >= 4 && z >= 46)
    }
    // The raised bridge on the spine: tapered sides, a raked front.
    static func mfBridge(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard y >= 25 && y <= 32 && z <= 92 else { return false }
        let t = y - 25
        guard Float(z) >= 70 + Float(t) * 0.8 else { return false }
        return abs(x) <= 6 - t / 2
    }
    // The sensor dome on the bridge roof.
    static func mfDome(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard y >= 33 else { return false }
        let dy = y - 33, dz = z - 85
        return x * x + dy * dy * 2 + dz * dz <= 12
    }
    // The engine block: bulkier than the spine, an octagonal section, z 120-159.
    static func mfEngine(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard z >= 120 && z < mfLength && y >= 3 && y <= 28 else { return false }
        let ax = abs(x)
        guard ax <= 13 else { return false }
        let fy = Float(y) - 15.5
        return Float(ax) + abs(fy) <= 22 - (z < 123 ? Float(123 - z) * 1.5 : 0)
    }

    // A point-defence mount: a squat grey drum with twin barrels.
    static func meridianPD() -> Blueprint {
        let t = Blueprint()
        t.box(-1, 1, 0, 1, -1, 1, "frigate_plate")
        t.set(0, 2, 0, "frigate_trim")
        t.set(0, 1, -1, "ship_cannon[south]")                              // (P477: breech in the face, small-bore barrels)
        for z in -4 ... -2 { t.set(0, 1, z, "gun_barrel_small[south]") }
        return t
    }

    static func capitalFrigate() -> HullBuilder {
        let W = 13, L = mfLength
        let hb = HullBuilder(sx: 2 * W + 1, sy: 40, sz: L, ox: W)
        let hull = id("frigate_hull", id("warship_hull")), plate = id("frigate_plate", hull), trim = id("frigate_trim", hull)
        let mark = id("frigate_mark", plate), port = id("frigate_porthole", id("light_panel")), thr = id("frigate_thruster", id("light_panel"))
        let glass = id("capital_glass", id("armored_glass", GLASS)), light = id("light_panel"), engine = id("ship_engine")
        let console = id("command_console"), ladder = Blocks.id("ladder")
        func solid(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            mfBoom(x, y, z) || mfSpine(x, y, z) || mfBridge(x, y, z) || mfDome(x, y, z) || mfEngine(x, y, z)
        }
        // Skin only (decks and rooms inside), panels in a staggered pattern, dark trim along the chines.
        for z in 0..<L { for y in 0..<40 { for x in -W...W where solid(x, y, z) {
            let edge: Bool = !solid(x + 1, y, z) || !solid(x - 1, y, z) || !solid(x, y + 1, z) || !solid(x, y - 1, z)
                || !solid(x, y, z + 1) || !solid(x, y, z - 1)
            if !edge { continue }
            var b: BlockID = hashf(z / 8, y / 4, x < 0 ? 1 : 0, 77) < 0.16 ? plate : hull      // scattered lighter panels
            if mfDome(x, y, z) { b = trim }
            else if mfBoom(x, y, z) && !mfSpine(x, y, z) && (y == 2 || y == 3) { b = trim }
            else if mfEngine(x, y, z) && (z == 120 || z == L - 1) { b = trim }
            hb.set(x, y, z, b)
        } } }
        // Hull markings: a pale band round each boom near the bow and round the spine ahead of the engines.
        for z in 14...15 { for y in 2...13 { for x in -W...W where mfBoom(x, y, z) && !mfBoom(x + (x > 0 ? 1 : -1), y, z) { hb.set(x, y, z, mark) } } }
        for z in 112...113 { for y in 6...24 { for x in -W...W where hb.get(x, y, z) != AIR { hb.set(x, y, z, mark) } } }
        // Porthole rows: the booms' outer faces (two rows) and the spine's flanks (two rows), lit at night.
        for z in stride(from: 6, through: 82, by: 3) { for y in [6, 10] {
            var xe = 4
            while mfBoom(xe + 1, y, z) { xe += 1 }
            if mfBoom(xe, y, z) { hb.set(xe, y, z, port); hb.set(-xe, y, z, port) }
        } }
        for z in stride(from: 54, through: 118, by: 3) where !(z >= 98 && z <= 114) { for y in [16, 22] {     // (the main and upper decks' eye height)
            let xe = 9
            if mfSpine(xe, y, z) { hb.set(xe, y, z, port); hb.set(-xe, y, z, port) }
        } }
        // P325 (a) (Remington, Oct 15 19:12: "a big gun in the back... fixed, aim by turning the ship"): the Tidebreaker
        // runs the hull's whole length. The barrel between the booms, as before: a dark tube round a bore, glowing coil
        // rings every 6 blocks touching the booms' inner faces, a muzzle brake at z 1-3. Behind it the accelerator: a
        // housing down the middle of the gun deck (z 64-115) banded with coils, a keel fairing under the spine with the
        // same rings glowing below, and the breech in the stern (z 116-119) between two capacitor banks.
        for z in 1...63 { for y in 6...12 { for x in -3...3 {
            let d2 = x * x + (y - 9) * (y - 9)
            let coil = z % 6 == 3 && z > 6, brake = z <= 3
            if d2 <= 1 { hb.set(x, y, z, AIR) }                                                  // the bore
            else if d2 <= 6 { hb.set(x, y, z, coil ? thr : (brake ? hull : trim)) }               // the tube
            else if d2 <= 10 && (coil || brake) { hb.set(x, y, z, coil ? thr : hull) }            // coil rings, brake
        } } }
        for y in [8, 10] { for sx in [-3, 3] { hb.set(sx, y, 2, AIR) } }                        // brake ports
        hb.mainGun = (V3(Float(W) + 0.5, 9.5, 0.5), V3(0, 0, -1))
        hb.mainGunLength = 115
        // The interior: every cell inside the skin as the skin pass left it (air), before anything is built in.
        let skin = hb.blocks
        func inner(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            let gx = x + W
            guard gx >= 0 && gx <= 2 * W && y >= 0 && y < 40 && z >= 0 && z < L else { return false }
            return skin[gx + z * hb.sx + y * hb.sx * hb.sz] == AIR && solid(x, y, z)
        }
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { if inner(x, y, z) { hb.set(x, y, z, b) } }
        let deck = id("frigate_deck", trim), wall = id("frigate_wall", plate), door = id("bulkhead_door", id("iron_door"))
        let wool = id("white_wool"), barrel = id("barrel"), slab = id("smooth_stone_slab", trim), bars = id("iron_bars")
        let cabinet = id("data_cabinet", console)
        // A two-high bulkhead door, closed, in a wall across x (the panel on side `f`: 0 -z, 1 +z) or along z (2 -x, 3 +x).
        func doorway(_ x: Int, _ y: Int, _ z: Int, _ f: Int) {
            hb.set(x, y, z, door + BlockID(f)); hb.set(x, y + 1, z, door + BlockID(f | 8))
        }
        // A ladder from y0 up to y1 (the decks it crosses opened round it) on the face of the block at side `f`.
        func ladderUp(_ x: Int, _ y0: Int, _ y1: Int, _ z: Int, _ f: Int, backing: BlockID? = nil) {
            let back = [IVec3(0, 0, 1), IVec3(0, 0, -1), IVec3(1, 0, 0), IVec3(-1, 0, 0)][f]
            for y in y0...y1 {
                hb.set(x, y, z, ladder + BlockID(f))
                if let b = backing, inner(x + back.x, y, z + back.z) { hb.set(x + back.x, y, z + back.z, b) }
            }
        }

        // Decks: floors at y 8 (the gun deck, and the booms' upper level; their lower level stands on the keel skin), 14
        // (the main deck) and 20 (the upper deck) through the booms and the spine; the bridge deck at 24.
        for z in 2...119 { for y in [8, 14, 20] { for x in -W...W { put(x, y, z, deck) } } }
        for z in 71...91 { for x in -6...6 where mfBridge(x, 25, z) { hb.set(x, 24, z, plate) } }

        // The accelerator: a housing |x| <= 2 from the gun deck's floor to its ceiling, a glowing coil band every 6 blocks.
        for z in 64...115 { for y in 7...13 { for x in -2...2 {
            let face = abs(x) == 2 || y == 13
            hb.set(x, y, z, face && z % 6 == 3 ? thr : (face ? trim : hull))
        } } }
        // The keel fairing under it (y 2-5, |x| <= 3): between the booms from z 64, under the spine to z 118.
        for z in 64...118 { for y in 2...5 { for x in -3...3 where !solid(x, y, z) {
            if y == 2 && (abs(x) == 3 || z >= 116) { continue }                      // (chamfered below and at its tail)
            let face = abs(x) == 3 || y == 2 || (y == 3 && abs(x) == 2 && z >= 116)
            hb.set(x, y, z, face && z % 6 == 3 ? thr : (face ? trim : hull))
        } } }
        // The breech (z 116-119): a block of trim round a glowing core, capacitor banks along both walls.
        for z in 116...119 { for y in 7...13 { for x in -3...3 {
            let core = abs(x) <= 1 && abs(y - 10) <= 1
            hb.set(x, y, z, core || (z == 117 && (abs(x) == 3 || y == 13)) ? thr : trim)
        } } }
        for sg in [-1, 1] { for z in 116...119 { for y in 9...12 { for ax in 7...8 { put(sg * ax, y, z, (y + z) % 2 == 0 ? thr : trim) } } } }

        // The booms (z 12-63): on each level a corridor along the inner side (|x| 5-6), a wall at |x| 7 and cabins
        // (|x| 8-10) between walls every 8 blocks, a door into each; bunks along the porthole side, a chest and lamps.
        for sg in [-1, 1] {
            for z in 12...63 { for y in [3, 4, 5, 6, 7, 9, 10, 11, 12, 13] { put(sg * 7, y, z, wall) } }
            for z in stride(from: 16, through: 56, by: 8) { for y in [3, 4, 5, 6, 7, 9, 10, 11, 12, 13] { for ax in 8...10 { put(sg * ax, y, z, wall) } } }
            for z0 in stride(from: 16, through: 56, by: 8) {
                for yl in [3, 9] {
                    doorway(sg * 7, yl, z0 + 4, sg > 0 ? 2 : 3)
                    put(sg * 10, yl, z0 + 1, wool); put(sg * 10, yl, z0 + 2, wool)              // a bunk under the portholes
                    put(sg * 10, yl, z0 + 6, barrel)
                    hb.set(sg * 7, yl + 3, z0 + 2, light)                                         // a lamp lighting cabin and corridor
                }
            }
            // The forward store (z 12-15) and the lamps along the lower corridor (in the upper level's floor).
            for z in stride(from: 12, through: 60, by: 8) { put(sg * 5, 8, z, light) }
            // Ladders between the levels at both ends of the corridor, on the boom's inner skin.
            for z in [13, 62] { ladderUp(sg * 5, 3, 8, z, sg > 0 ? 3 : 2) }
        }

        let hoist = id(ShipShells.hoistKey, cabinet)
        // The gun deck (y 9-13, z 64-119) either side of the accelerator: gun crew consoles along the hull, the port
        // hangar (z 97-115, its flank door open to the winch) and the starboard hold, then the breech room.
        for sg in [-1, 1] {
            for z in stride(from: 70, through: 94, by: 8) {
                var ax = 10
                while ax > 3 && !inner(sg * ax, 9, z) { ax -= 1 }
                if ax > 3 { hb.set(sg * ax, 9, z, console); hb.set(sg * ax, 10, z, cabinet) }
                // P507: a shell hoist between each gun crew's stations, where the magazine is loaded (ShipShells).
                var hx = 10
                while hx > 3 && !inner(sg * hx, 9, z + 4) { hx -= 1 }
                if hx > 3 && z + 4 < 97 { hb.set(sg * hx, 9, z + 4, hoist) }
            }
            for z in stride(from: 68, through: 116, by: 8) { put(sg * 5, 14, z, light) }
            for x in 3...8 { for y in 9...13 { put(sg * x, y, 115, wall) } }               // the breech room's wall
            doorway(sg * 6, 9, 115, 1)
        }
        for x in 3...8 { for y in 9...13 { put(x, y, 97, wall) } }                         // the hold's wall
        doorway(6, 9, 97, 0)
        for z in 100...106 { for y in 9...10 { put(8, y, z, barrel) } }
        // The port hangar door (open) with a lit frame: the way aboard (the winch, FrigateBoarding).
        for z in 100...112 { for y in 9...13 { hb.set(-9, y, z, AIR); hb.set(-8, y, z, AIR) } }
        for z in 99...113 { hb.set(-9, 14, z, light); hb.set(-9, 8, z, trim) }

        // P357 (Oct 16 20:12 and 21:42: "far more complex inside: many more, smaller rooms, narrower corridors that branch
        // and turn, stairs and ladders between decks; no single big central hallway") and P472 (Oct 26 19:44-20:14: "too
        // plain and boring... just going room to room... Design a ship like a ship would be designed... so if I find the
        // frigate and I want to find the helm, I can fight my way to it"): the main and upper decks are laid out as a
        // warship's are, by deckPlan below. A passage runs fore and aft down the middle of each deck, shut by a pair of
        // watertight doors at each main bulkhead (so it never reads as one long hall), athwartship passages run out to
        // portholes, and the ship's great spaces open off it: the crew's berthing forward (racks of bunks), the stair
        // hall amidships, the mess deck aft of it, and above them the officers' cabins, the wardroom and the captain's
        // cabin. Every other cell is cut into smaller compartments (bulkheads every 3 to 5 blocks), each with a door onto
        // a passage or a hall or onto one that has one, taking the trades in turn (workshops, stores, armoury, medbay...).
        // One stairwell climbs the ship (below): from the boarding hangar to the main deck's stair hall, up to the upper
        // deck's landing, and up again to the bridge, so the way to the helm is always "up the stairs, forward".
        // Fire control, forward (z 48-57): consoles facing the bow and the plot between them.
        for x in -4...4 where x != 0 { put(x, 15, 51, console) }
        put(0, 15, 54, cabinet)
        put(-5, 20, 54, light); put(5, 20, 54, light)
        let stairs = id("polished_andesite_stairs", id("stone_brick_stairs", trim))
        let mainRooms = ["stores", "workshop", "armoury", "heads", "stores", "medbay", "workshop", "engineering", "armoury", "stores",
                         "galley", "stores", "galley", "laundry", "workshop", "stores"]
        let upperRooms = ["officer", "officer", "comms", "officer", "chart", "officer", "stores", "officer", "comms", "officer",
                          "chart", "officer", "stores", "officer"]
        // Main deck (walk level 15). Halls and passages are open floor; a one-cell piece is the doorway that joins one.
        deckPlan(hb, inner: inner, y: 15, h: 5, z0: 58, z1: 119, xr: 8, salt: 3570,
                 corridors: [(-1, 0, 58, 87),                                   // the main passage (doors across at z 73)
                             (-8, -3, 59, 71), (-2, -2, 65, 65),                 // port berthing, its door
                             (2, 8, 59, 71), (1, 1, 65, 65),                     // starboard berthing
                             (-8, 8, 81, 81),                                    // a cross passage out to the portholes
                             (-8, 3, 88, 99),                                    // the stair hall
                             (-1, 0, 100, 100), (-8, 8, 101, 111),               // its doors, the mess deck
                             (-1, 0, 112, 119)],                                 // aft to the engine room
                 kinds: mainRooms, wall: wall, door: door, light: light, ceilingLight: true, furnish: { x, z, k, i in
                     furnish(hb, x, 15, z, k, i, put: put, console: console, cabinet: cabinet, barrel: barrel, wool: wool, slab: slab, bars: bars)
                 })
        // Upper deck (walk level 21, low headroom).
        deckPlan(hb, inner: inner, y: 21, h: 3, z0: 58, z1: 119, xr: 8, salt: 3571,
                 corridors: [(-1, 0, 58, 85),                                   // officers' passage (doors across at z 74)
                             (-8, 8, 66, 66), (-8, 8, 81, 81),                   // cross passages to the portholes
                             (-4, 1, 86, 99),                                    // the landing: stair up from below, stair to the bridge
                             (-1, 0, 100, 100), (-8, 8, 101, 108),               // the wardroom
                             (-1, 0, 109, 119),                                  // aft passage
                             (2, 8, 111, 119), (1, 1, 115, 115)],                // the captain's cabin, its door
                 kinds: upperRooms, wall: wall, door: door, light: light, ceilingLight: false, furnish: { x, z, k, i in
                     furnish(hb, x, 21, z, k, i, put: put, console: console, cabinet: cabinet, barrel: barrel, wool: wool, slab: slab, bars: bars)
                 })
        // Watertight doors across the passages (a pair, the passage being two wide) and in the halls' doorways.
        func pairDoor(_ y: Int, _ h: Int, _ z: Int) {
            for x in -1...0 { doorway(x, y, z, 1); for dy in 2..<h { hb.set(x, y + dy, z, wall) } }
        }
        pairDoor(15, 5, 73); pairDoor(15, 5, 100); pairDoor(15, 5, 112)
        pairDoor(21, 3, 74); pairDoor(21, 3, 100); pairDoor(21, 3, 109)
        doorway(-2, 15, 65, 3); doorway(1, 15, 65, 2); doorway(1, 21, 115, 2)
        for y in 17...19 { hb.set(-2, y, 65, wall); hb.set(1, y, 65, wall) }
        hb.set(1, 23, 115, wall)
        // The outermost cell inside the hull along x on the side `sg` at (y, z), no nearer the middle than `least`.
        func outer(_ sg: Int, _ y: Int, _ z: Int, _ least: Int) -> Int? {
            var ax = 8
            while ax > least && !inner(sg * ax, y, z) { ax -= 1 }
            return ax > least ? sg * ax : nil
        }
        // Berthing: racks of three bunks along the hull and down the middle in pairs, lockers by the door, a chest each.
        var fit = 0
        for sg in [-1, 1] {
            for z in 59...71 where z != 65 { if let x = outer(sg, 15, z, 3) { furnish(hb, x, 15, z, "bunks", fit, put: put, console: console, cabinet: cabinet, barrel: barrel, wool: wool, slab: slab, bars: bars); fit += 1 } }
            for z in [60, 61, 62, 68, 69, 70] { furnish(hb, sg * 5, 15, z, "bunks", fit, put: put, console: console, cabinet: cabinet, barrel: barrel, wool: wool, slab: slab, bars: bars); fit += 1 }
            put(sg * 3, 15, 59, barrel); put(sg * 3, 15, 71, barrel); put(sg * 3, 16, 71, barrel)
            furnish(hb, sg * 3, 15, 60, "stores", 1, put: put, console: console, cabinet: cabinet, barrel: barrel, wool: wool, slab: slab, bars: bars)
        }
        // The stair hall: a rack of rifles (bars) and lockers on the port side, a lamp over each flight.
        for z in [89, 90, 91] { if let x = outer(-1, 15, z, 5) { put(x, 15, z, bars); put(x, 16, z, bars) } }
        if let x = outer(-1, 15, 96, 6) { furnish(hb, x, 15, 96, "armoury", 1, put: put, console: console, cabinet: cabinet, barrel: barrel, wool: wool, slab: slab, bars: bars) }
        // The mess deck: two long tables with benches, the serving counter along the aft bulkhead.
        for z in 103...109 { for tx in [-5, 4] {
            put(tx, 15, z, slab)
            put(tx - 1, 15, z, stairs + 3); put(tx + 1, 15, z, stairs + 2)
        } }
        for x in -6...6 where abs(x) > 1 && Blocks.shape[Int(hb.get(x, 15, 112))] != "door" {        // (clear of a door aft)
            put(x, 15, 111, x % 3 == 0 ? id("smoker", barrel) : slab)
        }
        // The wardroom: one long table (benches either side) under the lamps, a sideboard of lecterns and cabinets.
        for z in 102...107 { put(4, 21, z, slab); put(3, 21, z, stairs + 3); put(5, 21, z, stairs + 2) }
        for z in [102, 104, 106] { if let x = outer(-1, 21, z, 3) { put(x, 21, z, z == 104 ? id("lectern", cabinet) : cabinet) } }
        // The captain's cabin: a bunk under the porthole, a desk, the chart table, his own chest.
        if let x = outer(1, 21, 118, 3) { put(x, 21, 118, wool); put(x, 21, 117, wool) }
        if let x = outer(1, 21, 113, 3) { put(x, 21, 113, id("lectern", cabinet)); put(x, 21, 112, cabinet) }
        put(4, 21, 119, id("cartography_table", cabinet))
        put(4, 21, 112, Blocks.id("chest"))
        if hb.get(4, 21, 112) == Blocks.id("chest") { hb.chests.append((hb.grid(4, 21, 112), "meridian_hold")) }
        // Lamps in the upper deck's halls (its ceiling is the skin or the bridge's floor: lamps go in the walls).
        // (each in the first wall outward from the given cell; never in a door)
        for (x, z) in [(-5, 92), (2, 88), (2, 97), (-8, 104), (8, 104), (8, 116), (-8, 66), (8, 66), (-8, 81), (8, 81)] {
            var ax = x
            let sg = x < 0 ? -1 : 1
            while abs(ax) < 13 && hb.get(ax, 23, z) == AIR { ax += sg }
            let b = hb.get(ax, 23, z)
            if b != AIR && Blocks.shape[Int(b)] != "door" { hb.set(ax, 23, z, light) }
        }
        // Between the decks: a stair up the main deck's corridor (x -2, z 92-96, the upper deck's floor open over it) and a
        // ladder at the forward end (x -1, z 60), besides the trunk below.
        // P472 (Oct 26 19:45): six steps, the last in the upper deck's floor (five left a full block to climb at the top).
        for k in 0...5 {
            hb.set(-2, 15 + k, 92 + k, stairs + 1)
            for y in stride(from: 16 + k, through: 20, by: 1) { hb.set(-2, y, 92 + k, AIR) }
        }
        hb.set(-2, 14, 92, deck)
        ladderUp(-1, 15, 20, 60, 3, backing: wall)
        // P472: the stairwell's first flight, two wide, from the boarding hangar's forward end on the gun deck (x -5...-4,
        // rising forward over z 98-93) into the main deck's stair hall, where it comes up beside the flight to the upper
        // deck (a switchback). Rails round both openings.
        for k in 0...5 { for x in [-5, -4] {
            hb.set(x, 9 + k, 98 - k, stairs)
            if k < 5 { for y in (10 + k)...14 { hb.set(x, y, 98 - k, AIR) } }
        } }
        for z in 94...98 { hb.set(-6, 15, z, bars); hb.set(-3, 15, z, bars) }
        for x in [-5, -4] { hb.set(x, 15, 99, bars) }
        for z in 92...96 { hb.set(-3, 21, z, bars); hb.set(-1, 21, z, bars) }
        hb.set(-4, 14, 99, light)                                                // (over the flight's foot)

        // The ladder trunk (x -3, z 89): gun deck, main deck and upper deck, one shaft.
        for y in 9...20 { hb.set(-3, y, 89, ladder + 3); hb.set(-4, y, 89, trim) }
        // P434 (c) (Oct 24 15:30-15:31, "how do I even get to the helm?... there's a ladder... such an unintuitive way to
        // get there"): the bridge is reached by a stair, two wide, up from the upper deck's corridor (x -3...-2, rising
        // forward over z 90-87) through a well in the bridge floor, lit at its head, instead of the trunk's last ladder.
        for k in 0...3 {
            for x in [-3, -2] {
                hb.set(x, 21 + k, 90 - k, stairs)
                for y in stride(from: 22 + k, through: 24, by: 1) { hb.set(x, y, 90 - k, AIR) }
            }
        }
        for x in [-3, -2] { hb.set(x, 24, 91, AIR) }
        hb.set(-4, 26, 88, light)

        // The engine room (z 121-154): bulkheads fore and aft, the lower level (floor y 8) and the upper deck (y 14, the
        // main deck's level) over it, ladders between them at both ends. P504: its machinery (FrigateEngineRoom.swift).
        for y in 7...27 { for x in -W...W { put(x, y, 120, wall); put(x, y, 155, wall) } }
        doorway(0, 15, 120, 1)
        doorway(-5, 9, 120, 1); doorway(5, 9, 120, 1)
        hb.set(-5, 8, 120, deck); hb.set(5, 8, 120, deck); hb.set(0, 14, 120, deck)
        let coil = id("frigate_coil", thr), core = id("frigate_reactor", thr), conduit = id("frigate_conduit", trim)
        let gauge = id("frigate_gauge", console), vent = id("generator_vent", trim), rail = id("station_railing", bars)
        let rz = 128                                                   // the reactor's axis (x 0)
        func r2(_ x: Int, _ z: Int) -> Int { x * x + (z - rz) * (z - rz) }
        for z in 121...154 { for x in -W...W {
            put(x, 8, z, deck)
            // The upper deck, open down the middle between the drive units (the well, railed) and round the reactor.
            if !(abs(x) <= 2 && z >= 137 && z <= 151) && r2(x, z) > 4 { put(x, 14, z, deck) }
        } }
        ladderUp(0, 9, 14, 121, 1); ladderUp(0, 9, 14, 154, 0)
        for z in stride(from: 126, through: 150, by: 8) { for sg in [-1, 1] {
            var ax = W
            while ax > 9 && !inner(sg * ax, 19, z) { ax -= 1 }
            put(sg * ax, 19, z, light); put(sg * ax, 10, z, light)
        } }
        // The reactor: a plinth on the lower floor, the core (y 10-24) behind a ring of armoured glass with three field
        // coil bands, a cap at the ceiling with conduits up into the hull.
        for z in (rz - 3)...(rz + 3) { for x in -3...3 {
            let d = r2(x, z)
            if d <= 8 { put(x, 9, z, trim) }
            if d <= 1 { for y in 10...24 { put(x, y, z, core) } }
            else if d <= 4 { for y in 10...24 { put(x, y, z, [12, 17, 22].contains(y) ? coil : glass) } }
            if d <= 8 { put(x, 25, z, d <= 4 ? plate : trim) }
            if d <= 2 { for y in 26...27 { put(x, y, z, conduit) } }
        } }
        // Railings: round the well and the reactor's gallery on the upper deck.
        for z in 136...152 { put(-3, 15, z, rail); put(3, 15, z, rail) }
        for x in -2...2 { put(x, 15, 136, rail); put(x, 15, 152, rail) }
        // The four drive units (x +-7; the lower pair's axis y 11 on the floor, the upper pair's y 17 on the deck), z 136-153.
        for sx in [-7, 7] { for ay in [11, 17] {
            for z in 134...154 { for dy in -3...3 { for dx in -3...3 {
                let x = sx + dx, y = ay + dy, d = dx * dx + dy * dy
                if z >= 136 && z <= 153 {
                    if d <= 5 { put(x, y, z, (dx == 0 && dy == 2 && z % 2 == 0) ? coil : engine) }      // body, glowing strip on top
                    else if d <= 10 && (z - 137) % 5 == 0 && y != 8 && y != 14 { put(x, y, z, trim) }    // clamp rings
                } else if z == 135 {
                    if d <= 5 { put(x, y, z, d <= 1 ? trim : vent) }                                      // intake turbine
                } else if z == 134 {
                    if d <= 1 { put(x, y, z, trim) }                                                      // its hub
                } else if d <= 8 { put(x, y, z, trim) }                                                   // exhaust collar
            } } }
            // Cradles under the body at every clamp, and the upper units hung from the ceiling.
            for z in stride(from: 137, through: 152, by: 5) {
                for dx in [-3, -2, 2, 3] { put(sx + dx, ay - 2, z, trim) }
                if ay == 17 { for y in 20...27 { put(sx, y, z, trim) } }
            }
            // The exhaust ducts through the aft bulkhead to the nozzles.
            for dy in -2...2 { for dx in -2...2 where dx * dx + dy * dy <= 5 { put(sx + dx, ay + dy, 155, trim) } }
        } }
        // Pillars under the upper deck beside the aisle.
        for z in stride(from: 134, through: 152, by: 6) { for x in [-4, 4] { for y in 9...13 { put(x, y, z, trim) } } }
        // Feed conduits from the reactor to every drive unit: under the upper deck (y 13) and over it (y 21), out from the
        // reactor's sides to the units' line, then aft to their intakes.
        for sg in [-1, 1] { for y in [13, 21] {
            for k in 3...7 { put(sg * k, y, rz, conduit) }
            for z in (rz + 1)...134 { put(sg * 7, y, z, conduit) }
            put(sg * 7, y, rz, light)
            if y == 21 { for yy in 19...20 { put(sg * 7, yy, 134, conduit) } }
        } }
        // Coolant tanks on the lower level against the flanks (plate, a marked band, dark trim at foot and head).
        for sg in [-1, 1] { for cz in [123, 128] {
            for z in (cz - 1)...(cz + 1) { for x in 9...11 { for y in 9...13 {
                put(sg * x, y, z, y == 9 || y == 13 ? trim : (y == 11 ? mark : plate))
            } } }
        } }
        // Power banks along the upper level's flanks: cabinets and gauges, three high.
        for sg in [-1, 1] { for z in 122...131 { for y in 15...17 {
            var ax = W
            while ax > 9 && !inner(sg * ax, y, z) { ax -= 1 }
            put(sg * ax, y, z, (z + y) % 3 == 0 ? gauge : cabinet)
        } } }
        // The engineers' station: consoles facing the reactor under a wall of gauges on the fore bulkhead.
        for x in [-4, -3, 3, 4] { put(x, 15, 123, console) }
        for x in -6...6 where abs(x) >= 2 { for y in 16...17 { hb.set(x, y, 120, gauge) } }
        put(0, 20, 155, light); put(-6, 24, 155, light); put(6, 24, 155, light)
        // Bridge: a glass band across the raked front and down the sides, the helm and consoles.
        for y in 26...28 { for x in -6...6 {
            let z = Int(ceilf(70 + Float(y - 25) * 0.8))
            if mfBridge(x, y, z) { hb.set(x, y, z, glass) }
        } }
        for z in 74...84 { for y in 26...27 { let h = 6 - (y - 25) / 2; hb.set(h, y, z, glass); hb.set(-h, y, z, glass) } }
        hb.set(0, 25, 74, Blocks.id("ship_helm[south]"))
        for x in [-3, -2, 2, 3] { hb.set(x, 25, 73, console) }
        for z in [78, 81, 84] { hb.set(-5, 25, z, console); hb.set(5, 25, z, console) }        // P325 (b): stations under the side windows
        hb.set(2, 25, 86, id("data_cabinet", console))                                          // ... and the plot table
        hb.set(0, 31, 80, light); hb.set(0, 31, 86, light)
        // Sensor dome and an antenna mast with a beacon.
        for y in 36...37 { hb.set(0, y, 85, trim) }
        hb.set(0, 38, 85, light)
        // Spine: missile hatches (pods) and point-defence mounts; two more mounts on the boom tops.
        for z in stride(from: 96, through: 116, by: 4) { for x in [-4, 4] {
            hb.set(x, 24, z, trim)
            hb.pods.append((V3(Float(x + W) + 0.5, 25.5, Float(z) + 0.5), simd_normalize(V3(0, 1, -0.2))))
        } }
        for (x, y, z) in [(0, 25, 98), (0, 29, 128), (-8, 14, 30), (8, 14, 30)] {
            hb.set(x, y, z, Blocks.id("ship_turret_ring"))
            hb.turrets.append((hb.grid(x, y, z), meridianPD(), auto))
        }
        // The stern's nozzles: four great thrusters and a small one (the drive units in the engine room feed them).
        for (nx, ny, rr) in [(-7, 9, 4), (7, 9, 4), (-7, 21, 4), (7, 21, 4), (0, 15, 2)] {
            hb.exhausts.append(V3(Float(nx + W) + 0.5, Float(ny) + 0.5, Float(L) - 0.5))
            for y in (ny - rr - 1)...(ny + rr + 1) { for x in (nx - rr - 1)...(nx + rr + 1) where mfEngine(x, y, L - 1) {
                let d2 = (x - nx) * (x - nx) + (y - ny) * (y - ny)
                // The glowing core fills the whole nozzle (G8: it was a radius smaller, "two small points at night").
                if d2 <= rr * rr { hb.set(x, y, L - 1, AIR); hb.set(x, y, L - 2, thr) }                    // recessed glowing core
                else if d2 <= (rr + 1) * (rr + 1) { hb.set(x, y, L - 1, trim) }                          // nozzle ring
            } }
        }
        // Navigation lights at the boom tips and the engine block's corners.
        for sx in [-1, 1] { hb.set(sx * 5, 7, 1, light); hb.set(sx * 13, 15, 157, light) }
        // Stores: the hangar's hold and the bridge locker.
        hb.chests.append((hb.grid(7, 9, 110), "meridian_hold"))
        hb.set(7, 9, 110, Blocks.id("chest"))
        hb.chests.append((hb.grid(4, 25, 86), "meridian_hold"))
        hb.set(4, 25, 86, Blocks.id("chest"))
        // P434 (c) ("why is there a door right above a ladder?"): a door the deck plans set where a ladder comes up is
        // left an open doorway (the ladder's head opens onto it).
        do {
            let ladderBase = Blocks.groupBase[Int(ladder)], doorBase = Blocks.groupBase[Int(door)]
            for y in 1..<(hb.sy - 2) { for z in 0..<hb.sz { for gx in 0..<hb.sx {
                let x = gx - hb.ox
                guard Blocks.groupBase[Int(hb.get(x, y, z))] == ladderBase else { continue }
                if Blocks.groupBase[Int(hb.get(x, y + 1, z))] == doorBase { hb.set(x, y + 1, z, AIR); hb.set(x, y + 2, z, AIR) }
            } } }
        }
        // P472 (Oct 26 19:44-20:14: "a hallway that doesn't connect to anything else... I had to break through a wall to
        // find other hallways"): walked from the boarding hangar (FrigateLayoutCheck), every room and passage left out of
        // reach gets a door through its bulkhead onto one that is reached, until the whole ship is walkable.
        connectInterior(hb, from: IVec3(-6, 9, 106), wall: wall, door: door)
        // Crew: the helmsman, a gunner per mount, marines in the hangar.
        hb.post(0, 25, 75, .driver)
        for (x, y, z) in [(2, 25, 96), (2, 29, 126), (-7, 14, 33), (7, 14, 33)] { hb.post(x, y, z, .gunner) }
        for (x, y, z) in [(-5, 9, 104), (5, 9, 106), (-6, 9, 80), (6, 9, 90), (1, 15, 95), (0, 25, 82)] { hb.post(x, y, z, .troop) }
        // P472 (19:46, "Engine room, nice. Should be like engineer troops in here too... Engineering troops with guns").
        for (x, y, z) in [(-3, 9, 127), (3, 9, 146), (4, 15, 139), (-10, 15, 124)] { hb.post(x, y, z, .troop) }   // (P504: off the well)
        // P476 (Oct 27 19:03: "There used to be more troops on the frigate... let's say 50 troops on here. It should be a
        // pain to take... the guys just storm you"): marines through the whole ship, up to fifty aboard, each post a
        // standing cell walked from the hangar at least five blocks from any other (picked in a fixed shuffled order).
        do {
            var taken: [V3] = hb.crew.map { V3($0.x - Float(hb.ox), $0.y, $0.z) }
            let cells = walkable(hb, from: IVec3(-6, 9, 106)).sorted {
                hash3($0.x, $0.y, $0.z, 0x476) < hash3($1.x, $1.y, $1.z, 0x476)
            }
            for c in cells where hb.crew.count < 50 {
                let at = V3(Float(c.x) + 0.5, Float(c.y), Float(c.z) + 0.5)
                guard !taken.contains(where: { simd_length_squared($0 - at) < 25 }) else { continue }
                taken.append(at)
                hb.post(c.x, c.y, c.z, .troop)
            }
        }
        return hb
    }

    // Every standing cell (feet) reachable on foot from `start` (doors open, ladders and stairs climbed, never through a
    // wall), in builder coordinates (x relative to the centreline).
    // (ladders: false walks stairs and doors only, a ladder as good as a wall: P472's "up the stairs" way to the helm)
    static func walkable(_ hb: HullBuilder, from start: IVec3, ladders: Bool = true) -> Set<IVec3> {
        let ladderBase = Blocks.groupBase[Int(Blocks.id("ladder"))]
        func ladder(_ x: Int, _ y: Int, _ z: Int) -> Bool { ladders && Blocks.groupBase[Int(hb.get(x, y, z))] == ladderBase }
        func pass(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            let b = Int(hb.get(x, y, z))
            return !Blocks.collide[b] || Blocks.shape[b] == "door" || Blocks.shape[b] == "trapdoor" || (ladders && Blocks.groupBase[b] == ladderBase)
        }
        func fits(_ c: IVec3) -> Bool { pass(c.x, c.y, c.z) && pass(c.x, c.y + 1, c.z) }
        func held(_ c: IVec3) -> Bool { !pass(c.x, c.y - 1, c.z) || ladder(c.x, c.y, c.z) || ladder(c.x, c.y - 1, c.z) }
        func step(_ c: IVec3) -> Bool { let s = Blocks.shape[Int(hb.get(c.x, c.y, c.z))]; return s == "stairs" || s == "slab" }
        let up = IVec3(0, 1, 0), down = IVec3(0, -1, 0)
        var seen: Set<IVec3> = [start]
        var queue = [start], head = 0
        while head < queue.count {
            let c = queue[head]; head += 1
            var next: [IVec3] = []
            if ladder(c.x, c.y, c.z) || ladder(c.x, c.y + 1, c.z) { next.append(c + up) }
            if ladder(c.x, c.y - 1, c.z) || ladder(c.x, c.y, c.z) { next.append(c + down) }
            for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] {
                var n = c + d
                if !fits(n) {
                    guard step(n), fits(n + up), pass(c.x, c.y + 2, c.z) else { continue }       // a stair or slab, headroom over both
                    n = n + up
                }
                var drop = 0
                while !held(n) && drop < 24 { n = n + down; drop += 1 }
                next.append(n)
            }
            for n in next where fits(n) && held(n) && !seen.contains(n) { seen.insert(n); queue.append(n) }
        }
        return seen
    }

    // P472: doors through the interior bulkheads (`wall`, two high): each piece of standing room out of reach gets one onto
    // a reached cell beyond, then the ship is walked again, until nothing inside is left out or no bulkhead joins them.
    static func connectInterior(_ hb: HullBuilder, from start: IVec3, wall: BlockID, door: BlockID) {
        let wallBase = Blocks.groupBase[Int(wall)]
        func isWall(_ x: Int, _ y: Int, _ z: Int) -> Bool { Blocks.groupBase[Int(hb.get(x, y, z))] == wallBase }
        let dirs = [(IVec3(0, 0, -1), 0), (IVec3(0, 0, 1), 1), (IVec3(-1, 0, 0), 2), (IVec3(1, 0, 0), 3)]
        for _ in 0..<8 {
            let reached = walkable(hb, from: start)
            var left: Set<IVec3> = []
            for y in [3, 9, 15, 21, 25] { for z in 0..<hb.sz { for gx in 0..<hb.sx {
                let x = gx - hb.ox
                if hb.get(x, y, z) == AIR && hb.get(x, y + 1, z) == AIR && Blocks.collide[Int(hb.get(x, y - 1, z))]
                    && !reached.contains(IVec3(x, y, z)) { left.insert(IVec3(x, y, z)) }
            } } }
            var made = 0
            while let s0 = left.first {
                // One piece: its cells, and the first bulkhead between it and the reached ship.
                left.remove(s0)
                var q = [s0], i = 0
                var cut: (IVec3, Int)?
                while i < q.count {
                    let c = q[i]; i += 1
                    for (d, f) in dirs {
                        let n = c + d
                        if left.contains(n) { left.remove(n); q.append(n); continue }
                        let o = n + d
                        if cut == nil && isWall(n.x, n.y, n.z) && isWall(n.x, n.y + 1, n.z) && reached.contains(o) { cut = (n, f) }
                    }
                }
                guard let (w, f) = cut, q.count >= 2 else { continue }
                hb.set(w.x, w.y, w.z, door + BlockID(f)); hb.set(w.x, w.y + 1, w.z, door + BlockID(f | 8))
                made += 1
            }
            if made == 0 { return }
        }
    }
}

extension Capital {
    // P357: one deck's plan. Cells (x in -xr...xr, z in z0...z1) inside the hull at walk level y: the corridors (rects
    // x0, x1, z0, z1), a bulkhead round them, a bulkhead across the deck's forward row, more every 3 to 5 blocks along
    // (hashed per deck) and through the middle of any run wider than 6; what is left is rooms. A room gets a door onto
    // the corridor if it touches it, else onto a room that already has a way out; a room with none, or under 4 cells, is
    // a locker (solid). Bulkheads are h high; each room is lit (a ceiling panel, or a lamp high in its wall) and
    // furnished along its walls, away from its door, by `kinds` in turn.
    static func deckPlan(_ hb: HullBuilder, inner: (Int, Int, Int) -> Bool, y: Int, h: Int, z0: Int, z1: Int, xr: Int, salt: Int,
                         corridors: [(Int, Int, Int, Int)], kinds: [String], wall: BlockID, door: BlockID, light: BlockID, ceilingLight: Bool,
                         furnish: (Int, Int, String, Int) -> Void) {
        let W = 2 * xr + 1, D = z1 - z0 + 1
        // 0 outside, 1 free, 2 corridor, 3 bulkhead, 4 door
        var t = [UInt8](repeating: 0, count: W * D)
        func ix(_ x: Int, _ z: Int) -> Int { (x + xr) + (z - z0) * W }
        func at(_ x: Int, _ z: Int) -> UInt8 { x < -xr || x > xr || z < z0 || z > z1 ? 0 : t[ix(x, z)] }
        for z in z0...z1 { for x in -xr...xr where inner(x, y, z) && inner(x, y + 1, z) { t[ix(x, z)] = 1 } }
        for (xa, xb, za, zb) in corridors { for z in max(z0, za)...min(z1, zb) { for x in xa...xb where at(x, z) == 1 { t[ix(x, z)] = 2 } } }
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        for z in z0...z1 { for x in -xr...xr where at(x, z) == 1 {
            if z == z0 || dirs.contains(where: { at(x + $0.0, z + $0.1) == 2 }) { t[ix(x, z)] = 3 }
        } }
        // Bulkheads across, every 3 to 5 rooms' depth.
        var zc = z0
        var n = 0
        while true {
            zc += 4 + Int(hash3(salt, n, 0, 77) % 3)
            n += 1
            if zc >= z1 - 2 { break }
            for x in -xr...xr where at(x, zc) == 1 { t[ix(x, zc)] = 3 }
        }
        // A wall down the middle of a wide run.
        for z in z0...z1 {
            var x = -xr
            while x <= xr {
                guard at(x, z) == 1 else { x += 1; continue }
                var e = x
                while e + 1 <= xr && at(e + 1, z) == 1 { e += 1 }
                if e - x + 1 >= 7 { t[ix((x + e) / 2, z)] = 3 }
                x = e + 1
            }
        }
        // Rooms: the free cells' 4-connected pieces.
        var room = [Int](repeating: -1, count: W * D)
        var rooms: [[(Int, Int)]] = []
        for z in z0...z1 { for x in -xr...xr where at(x, z) == 1 && room[ix(x, z)] < 0 {
            var cells: [(Int, Int)] = [(x, z)]
            room[ix(x, z)] = rooms.count
            var i = 0
            while i < cells.count {
                let (cx, cz) = cells[i]; i += 1
                for (dx, dz) in dirs where at(cx + dx, cz + dz) == 1 && room[ix(cx + dx, cz + dz)] < 0 {
                    room[ix(cx + dx, cz + dz)] = rooms.count
                    cells.append((cx + dx, cz + dz))
                }
            }
            rooms.append(cells)
        } }
        // Doors: onto the corridor first, then onto rooms with a way out, until nothing changes.
        var out = [Bool](repeating: false, count: rooms.count)
        var doors: [(Int, Int, Int)] = []                       // x, z, panel side
        var changed = true
        while changed {
            changed = false
            for r in rooms.indices where !out[r] && rooms[r].count >= 4 {
                var cands: [(Int, Int, Int)] = []
                for (cx, cz) in rooms[r] { for (k, (dx, dz)) in dirs.enumerated() {
                    let wx = cx + dx, wz = cz + dz
                    guard at(wx, wz) == 3 else { continue }
                    let o = at(wx + dx, wz + dz)
                    let other = o == 2 || (o == 1 && room[ix(wx + dx, wz + dz)] != r && out[room[ix(wx + dx, wz + dz)]])
                    guard other else { continue }
                    // In a straight wall: the cells beside the doorway are bulkhead or hull.
                    let px = dz, pz = dx
                    guard [at(wx + px, wz + pz), at(wx - px, wz - pz)].allSatisfy({ $0 == 3 || $0 == 0 }) else { continue }
                    cands.append((wx, wz, [3, 2, 1, 0][k]))     // the panel on the far side (toward the way out)
                } }
                guard !cands.isEmpty else { continue }
                let d = cands[cands.count / 2]
                t[ix(d.0, d.1)] = 4
                doors.append(d)
                out[r] = true
                changed = true
            }
        }
        // Build: bulkheads, doors, lockers.
        for z in z0...z1 { for x in -xr...xr {
            switch at(x, z) {
            case 3: for dy in 0..<h { hb.set(x, y + dy, z, wall) }
            case 1 where !out[room[ix(x, z)]]: for dy in 0..<h { hb.set(x, y + dy, z, wall) }
            default: break
            }
        } }
        for (x, z, f) in doors {
            hb.set(x, y, z, door + BlockID(f)); hb.set(x, y + 1, z, door + BlockID(f | 8))
            for dy in 2..<h { hb.set(x, y + dy, z, wall) }
        }
        // Light: rooms and every fifth corridor cell.
        func lamp(_ cells: [(Int, Int)]) {
            let (cx, cz) = cells[cells.count / 2]
            if ceilingLight { if inner(cx, y + h, cz) { hb.set(cx, y + h, cz, light) }; return }
            for (dx, dz) in dirs where at(cx + dx, cz + dz) == 3 { hb.set(cx + dx, y + h - 1, cz + dz, light); return }
            for (x, z) in cells { for (dx, dz) in dirs where at(x + dx, z + dz) == 3 { hb.set(x + dx, y + h - 1, z + dz, light); return } }
        }
        var corr: [(Int, Int)] = []
        for z in z0...z1 { for x in -xr...xr where at(x, z) == 2 { corr.append((x, z)) } }
        for i in stride(from: 2, to: corr.count, by: 10) { lamp([corr[i]]) }
        var k = 0
        for r in rooms.indices where out[r] {
            lamp(rooms[r])
            let kind = kinds[k % kinds.count]
            k += 1
            // Along the walls, clear of the doorway.
            let nearDoor = { (x: Int, z: Int) in dirs.contains { at(x + $0.0, z + $0.1) == 4 } }
            let spots = rooms[r].filter { c in !nearDoor(c.0, c.1) && dirs.contains { [0, 3].contains(at(c.0 + $0.0, c.1 + $0.1)) } }
            let most = max(1, rooms[r].count / 3)
            for (i, c) in spots.prefix(most).enumerated() { furnish(c.0, c.1, kind, i) }
        }
    }

    // P357: a room's fitting at (x, y, z) by its trade; i counts the room's fittings.
    static func furnish(_ hb: HullBuilder, _ x: Int, _ y: Int, _ z: Int, _ kind: String, _ i: Int, put: (Int, Int, Int, BlockID) -> Void,
                        console: BlockID, cabinet: BlockID, barrel: BlockID, wool: BlockID, slab: BlockID, bars: BlockID) {
        let g = { (n: String, f: BlockID) in id(n, f) }
        func chest() {
            put(x, y, z, Blocks.id("chest"))
            if hb.get(x, y, z) == Blocks.id("chest") { hb.chests.append((hb.grid(x, y, z), "meridian_hold")) }
        }
        switch kind {
        case "bunks":
            put(x, y, z, wool); put(x, y + 1, z, slab); put(x, y + 2, z, wool)
        case "mess": put(x, y, z, slab)
        case "galley": put(x, y, z, [g("furnace", barrel), g("smoker", barrel), barrel, barrel][i % 4])
        case "armoury":
            if i % 3 == 1 { chest() } else { put(x, y, z, bars); put(x, y + 1, z, bars) }
        case "medbay": put(x, y, z, [wool, g("brewing_stand", cabinet), wool, cabinet][i % 4])
        case "workshop": put(x, y, z, [g("crafting_table", barrel), g("anvil", barrel), g("smithing_table", barrel), barrel][i % 4])
        case "stores":
            if i % 3 == 1 { chest() } else { put(x, y, z, barrel); put(x, y + 1, z, barrel) }
        case "quarters": put(x, y, z, [wool, barrel, wool, g("lectern", cabinet)][i % 4])
        case "officer":
            if i % 4 == 2 { chest() } else { put(x, y, z, [wool, g("lectern", cabinet), wool, wool][i % 4]) }
        case "comms": put(x, y, z, i % 2 == 0 ? console : cabinet)
        case "engineering": put(x, y, z, [cabinet, console, g("cauldron", barrel), barrel][i % 4])
        case "chart": put(x, y, z, [g("cartography_table", cabinet), g("lectern", cabinet), cabinet][i % 3])
        case "heads": put(x, y, z, [g("cauldron", barrel), barrel][i % 2])
        case "laundry": put(x, y, z, [g("cauldron", barrel), wool, barrel][i % 3])
        default: put(x, y, z, barrel)
        }
    }
}

