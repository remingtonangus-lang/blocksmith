import Foundation
import simd

// The Ashguard's sites in the Ash Vault (task 22), laid out like a field army's rear area around its headquarters:
// the citadel (HQ) at x 0, z 0 where the roads meet; a tank column staged on the east road; motor pools, fuel depots,
// supply hubs and artillery batteries in a ring around it; pillbox outposts further out; small patrol camps everywhere
// else in the vault. Everything black, marked in red with the Ashguard's own ember mark (a red diamond split by a black
// bar). Units arrive as structure mobs ("key[@ash][:variant][^heading]", AshWar.spawnPending).

extension BlockRegistry {
    func registerAshguardBlocks() {
        func block(_ n: String, _ disp: String, side: String? = nil, top: String? = nil, h: Float, emit: UInt8 = 0, snd: SoundMat = .stone) {
            guard !has(n) else { return }
            var d = BlockDef(n, disp)
            let s = side ?? n
            d.tex = [s, s, top ?? s, top ?? s, s, s]
            d.hardness = h; d.resistance = 30; d.tool = .pickaxe; d.requiresTool = true; d.sound = snd; d.emit = emit
            add(d)
        }
        block("ash_concrete", "Ashcrete", h: 4)
        block("ash_plating", "Ash Plating", h: 6)
        block("ash_mark", "Ember Mark Plate", h: 3)
        block("ash_lamp", "Red Signal Lamp", h: 1, emit: 13, snd: .glass)
        block("ash_crate", "Ashguard Crate", side: "ash_crate", top: "ash_crate_top", h: 2, snd: .wood)
        block("ash_sandbags", "Sandbags", h: 1, snd: .sand)
        block("ash_lift", "Lift Plate", h: -1, emit: 15)
        if !has("ash_drum") {
            var d = BlockDef("ash_drum", "Fuel Drum")
            d.tex = ["ash_drum_side", "ash_drum_side", "ash_drum_top", "ash_drum_top", "ash_drum_side", "ash_drum_side"]
            d.render = .model; d.opaque = false; d.boxes = [Box(2, 0, 2, 14, 15, 14)]
            d.hardness = 2; d.tool = .pickaxe; d.sound = .stone
            add(d)
        }
    }
}

extension TextureGen {
    static func ashPainters(_ p: inout [String: Painter]) {
        // Ashcrete: black cast concrete, faint form-board lines.
        p["ash_concrete"] = { x, y in
            var k: Float = 0.96 + 0.06 * r(x / 3, y / 3, 3301) + 0.03 * r(x, y, 3302)
            if y % 8 == 7 { k *= 0.82 }
            return hex(0x26262A, k)
        }
        // Ash plating: black steel panels, rivets at the seams.
        p["ash_plating"] = { x, y in
            if x == 0 || y == 0 { return hex(0x121214) }
            if (x == 2 || x == 13) && (y == 2 || y == 13) { return hex(0x4A4A50) }
            return hex(0x222226, 0.95 + 0.08 * r(x / 4, y / 2, 3303))
        }
        // The ember mark: a red plate with a black-edged diamond split by a black bar (the Ashguard's own sign).
        p["ash_mark"] = { x, y in
            let cx = Float(x) - 7.5, cy = Float(y) - 7.5
            let d = abs(cx) + abs(cy)
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x1A1A1C) }
            if d < 6.6 && abs(cx) < 1 { return hex(0x101012) }
            if d < 6.6 { return hex(0xC81E1E, 0.95 + 0.05 * r(x, y, 3304)) }
            if d < 7.6 { return hex(0x101012) }
            return hex(0x9E1616, 0.95 + 0.05 * r(x, y, 3305))
        }
        p["ash_lamp"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x18181A) }
            if x == 8 || y == 8 { return hex(0x2A1010) }
            let c = Float(abs(x - 8) + abs(y - 8))
            return hex(0xFF5A3C, 1.05 - c * 0.04)
        }
        // The lift home (after victory): a glowing plate in a red ring.
        p["ash_lift"] = { x, y in
            let d = max(abs(Float(x) - 7.5), abs(Float(y) - 7.5))
            if d > 6.5 { return hex(0x1A1A1C) }
            if d > 5 { return hex(0xD02A1E) }
            return hex(0xFFD9A0, 0.9 + 0.1 * r(x, y, 3311))
        }
        p["ash_crate"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x2A2018) }
            if y == 7 || y == 8 { return hex(0xA81C1C, 0.95 + 0.05 * r(x, y, 3306)) }
            return hex(0x3A2E22, 0.92 + 0.1 * r(x, y / 4, 3307))
        }
        p["ash_crate_top"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x2A2018) }
            return hex(0x3A2E22, 0.92 + 0.1 * r(x / 4, y, 3308))
        }
        p["ash_sandbags"] = { x, y in
            let row = y / 4, off = row % 2 == 0 ? 0 : 4
            if y % 4 == 3 || (x + off) % 8 == 7 { return hex(0x2E2A24) }
            return hex(0x4E483E, 0.9 + 0.1 * r(x / 2, y, 3309) + 0.05 * Float(y % 4 == 0 ? 1 : 0))
        }
        p["ash_drum_side"] = { x, y in
            if y >= 6 && y <= 8 { return hex(0xB81E1E) }
            if y == 2 || y == 12 { return hex(0x101012) }
            return hex(0x242428, 0.9 + 0.12 * Float(abs(x - 8)) / 8)
        }
        p["ash_drum_top"] = { x, y in
            if (x - 10) * (x - 10) + (y - 5) * (y - 5) < 3 { return hex(0x48484E) }
            return hex(0x1C1C1E, 0.95 + 0.05 * r(x, y, 3310))
        }
    }
}

struct AshSite {
    let kind: String          // hq, staging, motorpool, fueldepot, supply, battery, outpost, camp
    let x: Int, z: Int
    let r: Int                // footprint half-size (square)
    let face: Int             // heading (degrees, 0 = toward -z, 90 = toward +x) the site faces (away from the HQ)
}

extension AshWar {
    static let ground = DeepGen.floorBase      // sites stand on the levelled vault floor
    static let ringRoad = 230
    static let campSpacing = 20                // chunks
    static let campInner = 560                 // camps only beyond the ring of outposts

    // The fixed layout around the HQ (same in every world: the citadel always stands at 0, 0).
    static let sites: [AshSite] = {
        var s: [AshSite] = [AshSite(kind: "hq", x: 0, z: 0, r: 46, face: 0),
                            AshSite(kind: "staging", x: 104, z: 13, r: 32, face: 90),
                            AshSite(kind: "motorpool", x: 150, z: -112, r: 32, face: 90),
                            AshSite(kind: "motorpool", x: -128, z: 152, r: 32, face: 270),
                            AshSite(kind: "fueldepot", x: -168, z: -118, r: 28, face: 0),
                            AshSite(kind: "fueldepot", x: 186, z: 144, r: 28, face: 180),
                            AshSite(kind: "supply", x: 262, z: -42, r: 26, face: 90),
                            AshSite(kind: "supply", x: -58, z: 268, r: 26, face: 180),
                            AshSite(kind: "battery", x: 44, z: -300, r: 22, face: 0),
                            AshSite(kind: "battery", x: -300, z: 46, r: 22, face: 270),
                            AshSite(kind: "battery", x: 236, z: 262, r: 22, face: 135)]
        for k in 0..<8 {
            let a = (Float(k) * 45 + 22.5) * .pi / 180
            s.append(AshSite(kind: "outpost", x: Int(sinf(a) * 470), z: Int(-cosf(a) * 470), r: 16, face: k * 45 + 22))
        }
        return s
    }()

    // A patrol camp in this 20-chunk region, if any (beyond the outposts, off the roads).
    static func camp(regionX rx: Int, regionZ rz: Int) -> AshSite? {
        let h = hash3(rx, 13, rz, 0xA5C4)
        guard h % 4 != 0 else { return nil }
        let span = campSpacing * CS
        let x = rx * span + 40 + Int(h >> 4 % UInt32(span - 80)), z = rz * span + 40 + Int(h >> 14 % UInt32(span - 80))
        guard x * x + z * z > campInner * campInner, abs(x) > 24, abs(z) > 24 else { return nil }
        let face = Int(atan2f(Float(x), -Float(z)) * 180 / .pi)
        return AshSite(kind: "camp", x: x, z: z, r: 12, face: face)
    }

    // Roads: the two axes through the HQ (they run on through the whole vault, so following one always leads to the
    // citadel) and the ring road joining the sites.
    @inline(__always) static func roadDistance(_ x: Int, _ z: Int) -> Float {
        let axis = Float(min(abs(x), abs(z)))
        let d = sqrtf(Float(x * x + z * z))
        return min(axis, abs(d - Float(ringRoad)))
    }
    static func isRoad(_ x: Int, _ z: Int) -> Bool { roadDistance(x, z) < 2.6 }

    // Distance to the nearest site footprint or road: the vault floor flattens and keeps pillars and lava away.
    static func clearance(_ x: Int, _ z: Int) -> Float {
        var best = roadDistance(x, z) - 3
        for s in sites {
            let dx = max(0, abs(x - s.x) - s.r), dz = max(0, abs(z - s.z) - s.r)
            best = min(best, sqrtf(Float(dx * dx + dz * dz)))
            if best <= 0 { return 0 }
        }
        let span = campSpacing * CS
        let rx = floorDiv(x, span), rz = floorDiv(z, span)
        for oz in -1...1 { for ox in -1...1 {
            guard let c = camp(regionX: rx + ox, regionZ: rz + oz) else { continue }
            let dx = max(0, abs(x - c.x) - c.r), dz = max(0, abs(z - c.z) - c.r)
            best = min(best, sqrtf(Float(dx * dx + dz * dz)))
        } }
        return max(0, best)
    }

    static func starts(seed: UInt64) -> [StructureStart] { sites.map { start($0, seed: seed) } }

    static let campType = StructureType(name: "ash_camp", spacing: campSpacing, separation: 0, salt: 0, reach: 1) { seed, cx, cz in
        let span = campSpacing
        guard let c = camp(regionX: floorDiv(cx, span), regionZ: floorDiv(cz, span)) else { return nil }
        return start(c, seed: seed)
    }
    static var types: [StructureType] { [campType] }

    static func start(_ s: AshSite, seed: UInt64) -> StructureStart {
        let pseed = seed ^ UInt64(UInt32(bitPattern: Int32(truncatingIfNeeded: s.x &* 7919 &+ s.z &* 104729)))
        let lo = IVec3(s.x - s.r - 2, ground - 6, s.z - s.r - 2), hi = IVec3(s.x + s.r + 2, ground + 30, s.z + s.r + 2)
        return StructureStart(kind: "ash_" + s.kind, pieces: [Piece(min: lo, max: hi) { w in AshWar.build(&w, s, pseed) }],
                              anchor: IVec3(s.x, ground + 1, s.z))
    }
}

// MARK: Builders

private struct AshKit {
    let concrete = Blocks.id("ash_concrete"), plating = Blocks.id("ash_plating"), mark = Blocks.id("ash_mark")
    let lamp = Blocks.id("ash_lamp"), crate = Blocks.id("ash_crate"), bags = Blocks.id("ash_sandbags"), drum = Blocks.id("ash_drum")
    let bars = Blocks.has("iron_bars") ? Blocks.id("iron_bars") : AIR
    let chain = Blocks.has("chain") ? Blocks.id("chain") : AIR
    let floor = Blocks.id("polished_blackstone"), basalt = Blocks.id("smooth_basalt"), black = Blocks.id("blackstone")
    let blackWool = Blocks.has("black_wool") ? Blocks.id("black_wool") : Blocks.id("blackstone")
    let redWool = Blocks.has("red_wool") ? Blocks.id("red_wool") : Blocks.id("ash_mark")
    let fire = Blocks.has("campfire") ? Blocks.id("campfire") : Blocks.id("ash_lamp")
    let console = Blocks.has("command_console") ? Blocks.id("command_console") : Blocks.id("ash_plating")
    let table = Blocks.id("crafting_table")
}

extension AshWar {
    // Local frame: (u, v) with v pointing the way the site faces; the writer clips to the chunk being generated.
    fileprivate struct Frame {
        let s: AshSite
        let fx: Int, fz: Int            // facing unit vector (rounded to the nearest axis)
        init(_ s: AshSite) {
            self.s = s
            let f = ((s.face % 360) + 360 + 45) % 360 / 90
            (fx, fz) = [(0, -1), (1, 0), (0, 1), (-1, 0)][f]
        }
        // u to the right of the facing, v forward.
        func x(_ u: Int, _ v: Int) -> Int { s.x + u * (-fz) + v * fx }
        func z(_ u: Int, _ v: Int) -> Int { s.z + u * fx + v * fz }
        var heading: Int { fx == 1 ? 90 : (fx == -1 ? 270 : (fz == 1 ? 180 : 0)) }
    }

    static func build(_ w: inout StructWriter, _ s: AshSite, _ seed: UInt64) {
        var rng = SRng(seed | 1)
        let k = AshKit()
        let f = Frame(s)
        let y0 = ground
        func put(_ u: Int, _ y: Int, _ v: Int, _ b: BlockID) { w.set(f.x(u, v), y, f.z(u, v), b) }
        func box(_ u0: Int, _ y0: Int, _ v0: Int, _ u1: Int, _ y1: Int, _ v1: Int, _ b: BlockID) {
            let xa = f.x(u0, v0), xb = f.x(u1, v1), za = f.z(u0, v0), zb = f.z(u1, v1)
            w.fill(min(xa, xb), y0, min(za, zb), max(xa, xb), y1, max(za, zb), b)
        }
        func unit(_ name: String, _ u: Float, _ v: Float, heading: Int? = nil, y: Int = y0 + 1) {
            let x = Float(s.x) + u * Float(-f.fz) + v * Float(f.fx) + 0.5, z = Float(s.z) + u * Float(f.fx) + v * Float(f.fz) + 0.5
            let hd = ((heading ?? 0) + f.heading) % 360
            w.mob(name + "^\(hd)", V3(x, Float(y), z))
        }
        func soldier(_ rank: String, _ u: Float, _ v: Float, y: Int = y0 + 1) { unit("soldier_\(rank)@ash", u, v, y: y) }
        // A walled building: walls of `wall`, flat roof, doorway in the front (v1) wall, slit windows.
        func building(_ u0: Int, _ v0: Int, _ u1: Int, _ v1: Int, h: Int, wall: BlockID, roof: BlockID, door: Int = 0) {
            box(u0, y0 + 1, v0, u1, y0 + h, v1, wall)
            box(u0 + 1, y0 + 1, v0 + 1, u1 - 1, y0 + h - 1, v1 - 1, AIR)
            box(u0, y0 + h, v0, u1, y0 + h, v1, roof)
            box(u0 + 1, y0, v0 + 1, u1 - 1, y0, v1 - 1, k.floor)
            let mid = (u0 + u1) / 2 + door
            box(mid - 1, y0 + 1, v1, mid + 1, y0 + 3, v1, AIR)
            put(mid - 2, y0 + 3, v1 + 1, k.lamp); put(mid + 2, y0 + 3, v1 + 1, k.lamp)
            for u in stride(from: u0 + 3, to: u1 - 1, by: 4) where abs(u - mid) > 2 {
                put(u, y0 + 3, v0, k.bars); put(u, y0 + 3, v1, k.bars)
            }
            for v in stride(from: v0 + 3, to: v1 - 1, by: 4) { put(u0, y0 + 3, v, k.bars); put(u1, y0 + 3, v, k.bars) }
            put((u0 + u1) / 2, y0 + h - 1, (v0 + v1) / 2, k.lamp)
        }
        // A roofed shed open at the front, for parked vehicles.
        func shed(_ u0: Int, _ v0: Int, _ u1: Int, _ v1: Int, h: Int) {
            box(u0, y0 + 1, v0, u1, y0 + h - 1, v0, k.plating)
            for u in stride(from: u0, through: u1, by: 6) { box(u, y0 + 1, v1, u, y0 + h - 1, v1, k.plating) }
            box(u0, y0 + 1, v0, u0, y0 + h - 1, v1, k.plating); box(u1, y0 + 1, v0, u1, y0 + h - 1, v1, k.plating)
            box(u0, y0 + h, v0, u1, y0 + h, v1, k.plating)
            for u in stride(from: u0 + 3, to: u1, by: 6) { put(u, y0 + h - 1, (v0 + v1) / 2, k.lamp) }
        }
        func sandbagRing(_ u: Int, _ v: Int, _ r: Int, open: Bool = true) {
            for du in -r...r { for dv in -r...r where max(abs(du), abs(dv)) == r {
                if open && dv == r && abs(du) <= 1 { continue }
                box(u + du, y0 + 1, v + dv, u + du, y0 + (abs(du) == r || abs(dv) == r ? 2 : 1), v + dv, k.bags)
            } }
        }
        func flag(_ u: Int, _ v: Int, h: Int) {
            box(u, y0 + 1, v, u, y0 + h, v, k.chain == AIR ? k.bars : k.chain)
            box(u + 1, y0 + h - 3, v, u + 4, y0 + h, v, k.redWool)
            put(u + 2, y0 + h - 1, v, k.mark); put(u + 3, y0 + h - 2, v, k.mark)
            put(u, y0 + h + 1, v, k.lamp)
        }
        func tank(_ u0: Int, _ v0: Int, _ r: Int, h: Int) {
            // A fuel tank: black plated cylinder with a red band and the ember mark.
            for du in -r...r { for dv in -r...r where du * du + dv * dv <= r * r {
                let edge = du * du + dv * dv > (r - 1) * (r - 1)
                for y in (y0 + 1)...(y0 + h) {
                    if edge { put(u0 + du, y, v0 + dv, y == y0 + 3 ? k.redWool : k.plating) }
                    else if y == y0 + h { put(u0 + du, y, v0 + dv, k.plating) }
                }
            } }
            put(u0, y0 + 5, v0 + r, k.mark)
            put(u0, y0 + h + 1, v0, k.lamp)
        }
        func drums(_ u0: Int, _ v0: Int, _ n: Int, _ m: Int) {
            for a in 0..<n { for b in 0..<m where rng.int(5) != 0 { put(u0 + a, y0 + 1, v0 + b, k.drum) } }
        }
        func crates(_ u0: Int, _ v0: Int, _ n: Int, _ m: Int) {
            for a in 0..<n { for b in 0..<m {
                let h = 1 + rng.int(3)
                box(u0 + a, y0 + 1, v0 + b, u0 + a, y0 + h, v0 + b, k.crate)
            } }
        }
        func chest(_ u: Int, _ v: Int, _ loot: String, y: Int = y0 + 1) {
            w.chest(f.x(u, v), y, f.z(u, v), loot: loot, seed: rng.next(), facing: 0)
        }
        func lampPost(_ u: Int, _ v: Int) { box(u, y0 + 1, v, u, y0 + 3, v, k.plating); put(u, y0 + 4, v, k.lamp) }

        // Pad: levelled ground with a gravel and onyxstone apron, open air above.
        let r = s.r
        w.fill(s.x - r, y0 + 1, s.z - r, s.x + r, y0 + 28, s.z + r, AIR)
        w.fill(s.x - r, y0 - 4, s.z - r, s.x + r, y0 - 1, s.z + r, EMBERSLATE)
        for dz in -r...r { for dx in -r...r {
            let x = s.x + dx, z = s.z + dz
            guard w.inside(x, y0, z) else { continue }
            w.set(x, y0, z, AshWar.isRoad(x, z) ? k.floor : (hash3(x, 3, z, 0xA5) % 5 == 0 ? k.basalt : k.black))
        } }

        switch s.kind {
        case "hq":
            // Perimeter wall with crenels and lamps, four gates on the roads, corner towers.
            let a = 42
            for i in -a...a {
                for (u, v) in [(i, -a), (i, a), (-a, i), (a, i)] {
                    if abs(i) <= 4 { continue }                                     // gates
                    box(u, y0 + 1, v, u, y0 + 6, v, k.concrete)
                    if i % 2 == 0 { put(u, y0 + 7, v, k.concrete) }
                    if i % 8 == 0 { put(u, y0 + 7, v, k.lamp) }
                }
            }
            for (u, v) in [(-a, -a), (a, -a), (-a, a), (a, a)] {
                box(u - 2, y0 + 1, v - 2, u + 2, y0 + 12, v + 2, k.concrete)
                box(u - 1, y0 + 2, v - 1, u + 1, y0 + 12, v + 1, AIR)
                box(u - 2, y0 + 12, v - 2, u + 2, y0 + 12, v + 2, k.plating)
                for du in -2...2 { for dv in -2...2 where max(abs(du), abs(dv)) == 2 { put(u + du, y0 + 13, v + dv, k.bars) } }
                put(u, y0 + 13, v, k.lamp)
                soldier("marksman", Float(u), Float(v), y: y0 + 13)
            }
            for (u, v) in [(-6, -a), (6, -a), (-6, a), (6, a), (-a, -6), (-a, 6), (a, -6), (a, 6)] {
                box(u, y0 + 1, v, u, y0 + 8, v, k.plating); put(u, y0 + 9, v, k.lamp); put(u, y0 + 6, v, k.mark)
            }
            // The command bunker in the middle: thick ashcrete, sandbagged roof, the Marshal's map room.
            box(-13, y0 + 1, -10, 13, y0 + 8, 10, k.concrete)
            box(-11, y0 + 1, -8, 11, y0 + 6, 8, AIR)
            box(-11, y0, -8, 11, y0, 8, k.floor)
            box(-13, y0 + 9, -10, 13, y0 + 9, 10, k.bags)
            box(-2, y0 + 1, 10, 2, y0 + 4, 10, AIR)
            box(-1, y0 + 6, 11, 1, y0 + 8, 11, k.mark)
            for (u, v) in [(-8, -5), (8, -5), (-8, 5), (8, 5), (0, -6)] { put(u, y0 + 6, v, k.lamp) }
            box(-3, y0 + 1, -2, 3, y0 + 1, 2, k.console)
            box(-2, y0 + 2, -1, 2, y0 + 2, 1, k.table)
            box(-11, y0 + 1, -8, -9, y0 + 3, -8, k.console); box(9, y0 + 1, -8, 11, y0 + 3, -8, k.console)
            chest(-10, -6, "ash_command"); chest(10, -6, "ash_command"); chest(-10, 6, "ash_armory"); chest(10, 6, "ash_armory")
            for (u, v) in [(-13, -10), (13, -10), (-13, 10), (13, 10)] { put(u, y0 + 10, v, k.lamp) }
            flag(-5, 16, h: 16); flag(5, 16, h: 16)
            unit("ash_marshal", 0, -4, heading: 180)
            soldier("officer", -6, 2); soldier("officer", 6, 2); soldier("ironclad", -4, 8); soldier("ironclad", 4, 8)
            // Barracks (north-west, north-east), motor yard (south-east), gun pits and fuel (south-west).
            building(-36, -34, -12, -22, h: 6, wall: k.plating, roof: k.concrete)
            building(12, -34, 36, -22, h: 6, wall: k.plating, roof: k.concrete)
            chest(-34, -32, "ash_supply"); chest(34, -32, "ash_supply")
            for (u, v) in [(-30, -26), (-18, -26), (18, -26), (30, -26), (-24, -18), (24, -18)] { soldier(rng.chance(0.5) ? "trooper" : "recruit", Float(u), Float(v)) }
            shed(12, 14, 38, 24, h: 6)
            unit("ash_tank", 16, 19, heading: 180); unit("ash_tank", 22, 19, heading: 180); unit("ash_tank", 28, 19, heading: 180)
            unit("ash_halftrack", 34, 19, heading: 180)
            unit("ash_tank", 24, 31, heading: 0); unit("ash_halftrack", 32, 31, heading: 0)
            soldier("trooper", 18, 28); soldier("recruit", 30, 28)
            for (u, v) in [(-32, 18), (-18, 18)] {
                sandbagRing(u, v, 3)
                unit("ash_artillery", Float(u), Float(v), heading: 180)
                soldier("recruit", Float(u + 2), Float(v - 2))
            }
            drums(-36, 28, 5, 4); drums(-28, 30, 4, 3)
            unit("ash_truck:fuel", -16, 32, heading: 90)
            crates(-12, 28, 3, 2)
            for (u, v) in [(-20, -12), (20, -12), (-20, 12), (20, 12), (0, -30), (0, 30), (-30, 0), (30, 0)] { lampPost(u, v) }
            for (u, v) in [(-3, -40), (3, 40), (-40, 3), (40, -3)] { soldier("trooper", Float(u), Float(v)) }
        case "staging":
            // A tank column on the road shoulder, ready to roll: six tanks nose to tail, two trucks, crates.
            for i in 0..<6 { unit("ash_tank", -8, Float(-24 + i * 9), heading: 0) }
            unit("ash_truck", 6, -20, heading: 0); unit("ash_truck", 6, 6, heading: 0)
            crates(4, -4, 2, 3); crates(4, 14, 2, 2)
            for v in stride(from: -26, through: 26, by: 13) { lampPost(-14, v) }
            soldier("officer", 2, 0); soldier("trooper", 2, 10); soldier("recruit", 2, -12)
        case "motorpool":
            // Fenced lot: two vehicle sheds, a repair gantry, drums; tanks and half-tracks lined up.
            for i in -30...30 {
                for (u, v) in [(i, -30), (i, 30), (-30, i), (30, i)] where !(v == 30 && abs(i) <= 5) {
                    put(u, y0 + 1, v, k.concrete); put(u, y0 + 2, v, k.bars); put(u, y0 + 3, v, k.bars)
                    if i % 10 == 0 { put(u, y0 + 4, v, k.lamp) }
                }
            }
            shed(-26, -26, 2, -14, h: 6); shed(6, -26, 26, -14, h: 6)
            for (i, u) in [-22, -15, -8].enumerated() { unit(i == 2 ? "ash_halftrack" : "ash_tank", Float(u), -20, heading: 180) }
            for u in [10, 17, 23] { unit("ash_tank", Float(u), -20, heading: 180) }
            unit("ash_halftrack", -10, 8, heading: 0); unit("ash_truck", 4, 8, heading: 0); unit("ash_truck", 12, 8, heading: 0)
            box(-24, y0 + 1, 4, -24, y0 + 8, 4, k.plating); box(-16, y0 + 1, 4, -16, y0 + 8, 4, k.plating)
            box(-24, y0 + 8, 4, -16, y0 + 8, 4, k.plating); box(-20, y0 + 5, 4, -20, y0 + 7, 4, k.chain)
            drums(16, 16, 6, 3); crates(-26, 18, 4, 3)
            chest(-6, 22, "ash_supply")
            soldier("trooper", 0, -6); soldier("recruit", -18, 12); soldier("recruit", 20, 2); soldier("marksman", 0, 26); soldier("officer", -4, 14)
        case "fueldepot":
            // Four big fuel tanks, a pump house, drum stacks, tanker trucks; a tank on guard.
            for (u, v) in [(-14, -14), (14, -14), (-14, 6), (14, 6)] { tank(u, v, 6, h: 8) }
            building(-4, -6, 4, 2, h: 5, wall: k.concrete, roof: k.plating)
            drums(-24, 18, 8, 3); drums(12, 18, 8, 3)
            for u in [-6, 0, 6] { unit("ash_truck:fuel", Float(u), 18, heading: 0) }
            unit("ash_tank", 0, 24, heading: 0)
            sandbagRing(-22, -24, 2); sandbagRing(22, -24, 2)
            soldier("trooper", -22, -24); soldier("trooper", 22, -24); soldier("recruit", 0, 10); soldier("marksman", -10, 22)
            chest(0, -4, "ash_fuel")
            for (u, v) in [(-26, -26), (26, -26), (-26, 26), (26, 26)] { lampPost(u, v) }
        case "supply":
            // Two warehouses, crate yards, trucks at the loading bay.
            building(-22, -20, -2, -8, h: 6, wall: k.plating, roof: k.concrete)
            building(2, -20, 22, -8, h: 6, wall: k.plating, roof: k.concrete)
            chest(-20, -18, "ash_supply"); chest(-4, -18, "ash_armory"); chest(4, -18, "ash_supply"); chest(20, -18, "ash_supply")
            crates(-20, -16, 4, 3); crates(10, -16, 5, 3)
            crates(-22, 4, 6, 4); crates(14, 4, 6, 4)
            unit("ash_truck", -8, 4, heading: 0); unit("ash_truck", 0, 4, heading: 0); unit("ash_truck", 8, 4, heading: 0)
            unit("ash_halftrack", 0, 16, heading: 0)
            soldier("trooper", -12, 0); soldier("recruit", 12, 0); soldier("recruit", -18, 14); soldier("officer", 4, -4); soldier("marksman", 18, 16)
            for (u, v) in [(-24, -24), (24, -24), (-24, 22), (24, 22)] { lampPost(u, v) }
        case "battery":
            // Four field guns in sandbag pits facing out, an ammunition dugout behind them.
            for (i, u) in [-15, -5, 5, 15].enumerated() {
                sandbagRing(u, 6, 3)
                unit("ash_artillery", Float(u), 6, heading: 0)
                soldier(i % 2 == 0 ? "trooper" : "recruit", Float(u + 2), 3)
            }
            building(-6, -16, 6, -8, h: 4, wall: k.concrete, roof: k.bags)
            chest(-4, -14, "ash_armory"); chest(4, -14, "ash_supply")
            soldier("officer", 0, -4); soldier("marksman", -18, -6)
            lampPost(-20, -10); lampPost(20, -10)
        case "outpost":
            // A pillbox with a firing slit, a sandbag trench ring and a few men; sometimes a half-track.
            box(-3, y0 + 1, -3, 3, y0 + 4, 3, k.concrete)
            box(-2, y0 + 1, -2, 2, y0 + 3, 2, AIR)
            box(-2, y0 + 3, 3, 2, y0 + 3, 3, AIR)
            put(0, y0 + 1, -3, AIR); put(0, y0 + 2, -3, AIR)
            box(-3, y0 + 5, -3, 3, y0 + 5, 3, k.bags); put(0, y0 + 6, 0, k.lamp); put(0, y0 + 3, -4, k.mark)
            chest(-2, -2, "ash_supply")
            sandbagRing(0, 0, 9)
            soldier("marksman", 0, 1); soldier("trooper", -6, 5); soldier("recruit", 6, 5); soldier("trooper", 0, -7)
            if rng.chance(0.5) { unit("ash_halftrack", 12, 0, heading: 0) }
            lampPost(-12, -12); lampPost(12, 12)
        default:
            // Patrol camp: a black canvas tent, a fire, crates, three men; now and then a tank or half-track.
            for i in 0...3 {
                box(-4 + i, y0 + 1 + i, -3, -4 + i, y0 + 1 + i, 3, k.blackWool)
                box(4 - i, y0 + 1 + i, -3, 4 - i, y0 + 1 + i, 3, k.blackWool)
            }
            box(0, y0 + 5, -3, 0, y0 + 5, 3, k.blackWool)
            put(0, y0 + 4, 3, k.mark)
            put(0, y0 + 1, 7, k.fire)
            crates(5, -5, 2, 2)
            chest(-2, -2, "ash_supply")
            soldier("trooper", -2, 6); soldier("recruit", 2, 8); soldier(rng.chance(0.3) ? "marksman" : "recruit", 3, 4)
            let roll = rng.int(8)
            if roll < 2 { unit("ash_tank", -8, 6, heading: 0) } else if roll < 4 { unit("ash_halftrack", -8, 6, heading: 0) }
            lampPost(6, 9)
        }
    }
}
