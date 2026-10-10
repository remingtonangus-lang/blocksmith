import Foundation
import simd

// The Meridian frigate (role "capfrigate", the internal key of the frigate encounter; task 23: the frigate is its own
// faction, the Meridian Navy, no longer the Capital's). An original design in the spirit Remington asked for (a
// rugged deep-space navy frigate): a long dark-grey hull, twin lower booms reaching forward at the bow with rows of
// lit portholes and the MAC gun's muzzle between them, a raised bridge with a sensor dome on the spine, a bulky engine
// block aft with four great glowing thrusters; point-defence guns and missile hatches along the spine. 160 blocks
// long, 27 wide. The MAC (magnetic accelerator cannon) fires a slug that blasts a crater (Explosion.crater) able to
// gut a citadel. Fast: 12-22 b/s under its own crew, 42 b/s commandeered. Bow toward -Z at z 0, keel at y 0.
// The Capital's ship palette (capital_plate & co.) below is still used by its dropships and citadels.

extension BlockRegistry {
    // The Meridian Navy's hull palette (warship-grade plate, resistance 9) and its lit portholes and thrusters.
    func registerMeridianBlocks() {
        for (n, disp) in [("frigate_hull", "Meridian Hull Plate"), ("frigate_plate", "Meridian Armour Panel"), ("frigate_trim", "Meridian Dark Trim"),
                          ("frigate_mark", "Meridian Hull Marking")] where !has(n) {
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
    // and between the booms it starts at z 64 (the MAC muzzle).
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
        for z in stride(from: 54, through: 118, by: 3) where !(z >= 98 && z <= 114) { for y in [16, 20] {
            let xe = 9
            if mfSpine(xe, y, z) { hb.set(xe, y, z, port); hb.set(-xe, y, z, port) }
        } }
        // The MAC muzzle between the booms: a dark bore in a trim ring at the spine's lower front.
        for y in 6...13 { for x in -3...3 {
            let r = max(abs(x), abs(y - 9))
            hb.set(x, y, 64, r <= 1 ? AIR : (r <= 2 ? trim : hull))
            if r <= 1 { for z in 65...66 { hb.set(x, y, z, AIR) }; hb.set(x, y, 67, trim) }
        } }
        hb.mainGun = (V3(Float(W) + 0.5, 9.5, 63), V3(0, 0, -1))
        // Decks: the hangar deck (y 8) through the spine, the bridge deck (y 24) under the bridge.
        for z in 65..<128 { for x in -8...8 where mfSpine(x, 8, z) && mfSpine(x + 1, 8, z) && mfSpine(x - 1, 8, z) { hb.set(x, 8, z, trim) } }
        for z in 71...91 { for x in -6...6 where mfBridge(x, 25, z) { hb.set(x, 24, z, plate) } }
        for z in stride(from: 68, through: 124, by: 6) { for x in [-4, 4] { hb.set(x, 23, z, light) } }
        // Flank hangar doors (open), with a lit frame: the way aboard.
        for sx in [-1, 1] { for z in 100...112 { for y in 9...13 { hb.set(sx * 9, y, z, AIR); hb.set(sx * 8, y, z, AIR) } }
            for z in 99...113 { hb.set(sx * 9, 14, z, light); hb.set(sx * 9, 8, z, trim) } }
        // Ladder from the hangar deck up to the bridge (a hole in the bridge deck).
        for y in 9...24 { hb.set(-3, y, 89, ladder + 3); hb.set(-4, y, 89, trim) }
        // Bridge: a glass band across the raked front and down the sides, the helm and consoles.
        for y in 26...28 { for x in -6...6 {
            let z = Int(ceilf(70 + Float(y - 25) * 0.8))
            if mfBridge(x, y, z) { hb.set(x, y, z, glass) }
        } }
        for z in 74...84 { for y in 26...27 { let h = 6 - (y - 25) / 2; hb.set(h, y, z, glass); hb.set(-h, y, z, glass) } }
        hb.set(0, 25, 74, Blocks.id("ship_helm[south]"))
        for x in [-3, -2, 2, 3] { hb.set(x, 25, 73, console) }
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
        // Engines (critical systems) inside the block, four great thrusters and two small ones in the stern.
        for sx in [-1, 1] { hb.fill(sx * 6 - 2, sx * 6 + 2, 8, 12, 132, 150, engine); hb.fill(sx * 6 - 2, sx * 6 + 2, 18, 22, 132, 150, engine) }
        for (nx, ny, rr) in [(-7, 9, 4), (7, 9, 4), (-7, 21, 4), (7, 21, 4), (0, 15, 2)] {
            hb.exhausts.append(V3(Float(nx + W) + 0.5, Float(ny) + 0.5, Float(L) - 0.5))
            for y in (ny - rr - 1)...(ny + rr + 1) { for x in (nx - rr - 1)...(nx + rr + 1) where mfEngine(x, y, L - 1) {
                let d2 = (x - nx) * (x - nx) + (y - ny) * (y - ny)
                if d2 <= (rr - 1) * (rr - 1) { hb.set(x, y, L - 1, AIR); hb.set(x, y, L - 2, thr) }      // recessed glowing core
                else if d2 <= rr * rr + 1 { hb.set(x, y, L - 1, trim) }                                  // nozzle ring
            } }
        }
        // Navigation lights at the boom tips and the engine block's corners.
        for sx in [-1, 1] { hb.set(sx * 5, 7, 1, light); hb.set(sx * 13, 15, 157, light) }
        // Stores: the hangar's hold and the bridge locker.
        hb.chests.append((hb.grid(5, 9, 118), "meridian_hold"))
        hb.set(5, 9, 118, Blocks.id("chest"))
        hb.chests.append((hb.grid(4, 25, 86), "meridian_hold"))
        hb.set(4, 25, 86, Blocks.id("chest"))
        // Crew: the helmsman, a gunner per mount, marines in the hangar.
        hb.post(0, 25, 75, .driver)
        for (x, y, z) in [(2, 25, 96), (2, 29, 126), (-7, 14, 33), (7, 14, 33)] { hb.post(x, y, z, .gunner) }
        for (x, y, z) in [(-4, 9, 104), (4, 9, 108), (-2, 9, 116), (3, 9, 92), (-5, 9, 76), (0, 25, 82)] { hb.post(x, y, z, .troop) }
        return hb
    }
}

// MARK: The MAC gun

extension ShipManager {
    // Fires the Meridian frigate's MAC: a fast, nearly flat slug that craters what it hits (ShipCombat kind 3).
    func fireMAC(_ s: Ship, from mw: V3, dir: V3, game g: Game) {
        let sh = Shell(pos: mw + dir * 3, vel: dir * 420 + s.vel, owner: s.id, power: 12)
        sh.gravity = 0.4
        sh.kind = 3
        sh.life = 3
        shells.append(sh)
        g.sfx(.gun(9), 2.5, at: mw)
        g.sfx(.explodeLarge, 1, at: mw)
        g.particles.explosion(at: mw, power: 3)
        g.addFlash(at: mw, color: V3(2.4, 3.2, 6), radius: 16, life: 0.3)
    }

    // The player at a commandeered Meridian frigate's helm: attack fires the MAC along the bow (raised or lowered
    // with the view, within 30 degrees down and 15 up) when it is charged; 6 s to recharge. False while charging
    // (attack then fires the point-defence guns).
    func playerMAC(_ s: Ship, pitch: Float, game g: Game) -> Bool {
        guard s.role == "capfrigate", let st = capState[s.id], st.mainGunCD <= 0 else { return false }
        st.mainGunCD = 6
        let p = max(-0.52, min(0.26, pitch))
        let fw = s.dirToWorld(V3(0, 0, -1))
        let h = simd_normalize(V2(fw.x, fw.z) + V2(1e-5, 0))
        let dir = simd_normalize(V3(h.x * cosf(p), sinf(p), h.y * cosf(p)))
        fireMAC(s, from: s.toWorld(st.mainGunMuzzle), dir: dir, game: g)
        return true
    }

    // Seconds until the MAC can fire again (nil: not a MAC ship).
    func macCharge(_ s: Ship) -> Float? {
        guard s.role == "capfrigate", let st = capState[s.id] else { return nil }
        return max(0, st.mainGunCD)
    }
}
