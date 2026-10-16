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
            add(d)
        }
        for (n, disp, e) in [("frigate_porthole", "Meridian Porthole", UInt8(11)), ("frigate_thruster", "Meridian Thruster Core", UInt8(15))] where !has(n) {
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
        for z in -3 ... -2 { t.set(0, 1, z, "frigate_trim") }
        t.set(0, 1, -4, "ship_cannon[south]")
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

        // The gun deck (y 9-13, z 64-119) either side of the accelerator: gun crew consoles along the hull, the port
        // hangar (z 97-115, its flank door open to the winch) and the starboard hold, then the breech room.
        for sg in [-1, 1] {
            for z in stride(from: 70, through: 94, by: 8) {
                var ax = 10
                while ax > 3 && !inner(sg * ax, 9, z) { ax -= 1 }
                if ax > 3 { hb.set(sg * ax, 9, z, console); hb.set(sg * ax, 10, z, cabinet) }
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

        // The main deck (y 15-19): a corridor |x| <= 2 from the fire control room forward (z <= 59) to the engine
        // room's bulkhead (z 120), rooms either side behind walls at |x| 3 with a door each.
        for z in 60...119 { for y in 15...19 { put(-3, y, z, wall); put(3, y, z, wall) } }
        for z in stride(from: 60, through: 108, by: 12) { for y in 15...19 { for ax in 4...8 { put(ax, y, z, wall); put(-ax, y, z, wall) } } }
        for z in stride(from: 66, through: 114, by: 12) { doorway(-3, 15, z, 3); doorway(3, 15, z, 2) }
        for z in stride(from: 62, through: 118, by: 6) { put(0, 20, z, light) }
        for z in stride(from: 66, through: 114, by: 12) { put(-6, 20, z, light); put(6, 20, z, light) }
        // Fire control, forward: consoles facing the bow and the plot between them.
        for x in -4...4 where x != 0 { put(x, 15, 51, console) }
        put(0, 15, 54, cabinet)
        put(-5, 20, 54, light); put(5, 20, 54, light)
        // Port: mess (tables down the middle), bunks, infirmary, chart room, stores. Starboard: galley, bunks, armoury,
        // signals, workshop.
        for z in [63, 64, 68, 69] { put(-6, 15, z, slab) }
        for z in [62, 70] { put(4, 15, z, id("furnace")); put(5, 15, z, id("smoker", id("furnace"))) }
        put(8, 15, 62, barrel); put(8, 15, 63, barrel); put(8, 15, 70, barrel)
        for sg in [-1, 1] { for z in stride(from: 74, through: 82, by: 2) { put(sg * 8, 15, z, wool); put(sg * 8, 17, z, wool); put(sg * 8, 16, z, slab) } }
        for z in [86, 88, 92] { put(-8, 15, z, wool) }
        put(-6, 15, 94, id("brewing_stand"))
        for z in 86...94 where z % 2 == 0 { put(8, 15, z, bars); put(8, 16, z, bars) }
        put(6, 15, 94, Blocks.id("chest"))
        hb.chests.append((hb.grid(6, 15, 94), "meridian_hold"))
        put(-6, 15, 101, id("cartography_table")); put(-6, 15, 103, id("lectern"))
        for z in 98...106 where z % 2 == 0 { put(8, 15, z, cabinet); put(8, 16, z, console) }
        for z in 110...118 { put(-8, 15, z, barrel); if z % 2 == 0 { put(-8, 16, z, barrel) } }
        put(8, 15, 110, id("crafting_table")); put(8, 15, 112, id("anvil")); put(8, 15, 114, id("smithing_table"))
        put(6, 15, 118, Blocks.id("chest"))
        hb.chests.append((hb.grid(6, 15, 118), "meridian_hold"))

        // The upper deck (y 21-23): officers' cabins either side of its corridor.
        for z in 56...119 { for y in 21...23 { put(-3, y, z, wall); put(3, y, z, wall) } }
        for z in stride(from: 64, through: 114, by: 10) { for y in 21...23 { for ax in 4...8 { put(ax, y, z, wall); put(-ax, y, z, wall) } } }
        for z in Array(stride(from: 60, through: 110, by: 10)) + [117] { doorway(-3, 21, z, 3); doorway(3, 21, z, 2) }
        for z in stride(from: 62, through: 118, by: 8) { put(-3, 23, z, light); put(3, 23, z, light) }
        for z in stride(from: 61, through: 111, by: 10) { put(-7, 21, z, wool); put(-7, 21, z + 1, wool); put(7, 21, z, wool); put(7, 21, z + 1, wool) }

        // The ladder trunk (x -3, z 89): gun deck, main deck, upper deck and the bridge, one shaft; and the main deck's
        // second ladder up to the upper deck (x 2, z 64).
        for y in 9...24 { hb.set(-3, y, 89, ladder + 3); hb.set(-4, y, 89, trim) }
        ladderUp(2, 15, 20, 64, 2)

        // The engine room (z 121-154): bulkheads fore and aft, the lower level beside the lower engines (floor y 8), a catwalk
        // deck at y 14 (the main deck's level) down the middle, along both flanks and across at both ends and the middle,
        // open over the engines; ladders between the levels at both ends.
        for y in 7...27 { for x in -W...W { put(x, y, 120, wall); put(x, y, 155, wall) } }
        doorway(0, 15, 120, 1)
        doorway(-5, 9, 120, 1); doorway(5, 9, 120, 1)
        hb.set(-5, 8, 120, deck); hb.set(5, 8, 120, deck); hb.set(0, 14, 120, deck)
        for z in 121...154 { for x in -W...W {
            put(x, 8, z, deck)
            if abs(x) <= 2 || abs(x) >= 9 || z <= 123 || z >= 153 || (z >= 140 && z <= 141) { put(x, 14, z, deck) }
        } }
        ladderUp(0, 9, 14, 121, 1); ladderUp(0, 9, 14, 154, 0)
        for z in stride(from: 126, through: 150, by: 8) { for sg in [-1, 1] {
            var ax = W
            while ax > 9 && !inner(sg * ax, 19, z) { ax -= 1 }
            put(sg * ax, 19, z, light); put(sg * ax, 10, z, light)
        } }
        for x in [-10, 10] { put(x, 15, 140, console) }
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
        // Engines (critical systems) in the engine room, four great thrusters and two small ones in the stern.
        for sx in [-1, 1] { hb.fill(sx * 6 - 2, sx * 6 + 2, 8, 12, 132, 150, engine); hb.fill(sx * 6 - 2, sx * 6 + 2, 18, 22, 132, 150, engine) }
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
        // Crew: the helmsman, a gunner per mount, marines in the hangar.
        hb.post(0, 25, 75, .driver)
        for (x, y, z) in [(2, 25, 96), (2, 29, 126), (-7, 14, 33), (7, 14, 33)] { hb.post(x, y, z, .gunner) }
        for (x, y, z) in [(-5, 9, 104), (5, 9, 106), (-6, 9, 80), (6, 9, 90), (0, 15, 100), (0, 25, 82)] { hb.post(x, y, z, .troop) }
        return hb
    }
}
